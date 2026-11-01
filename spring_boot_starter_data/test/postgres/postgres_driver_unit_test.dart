// PostgresJdbcDriver over a fake binding: how a URL and the properties
// become an endpoint, the TLS fallback, the statements of transactions and
// savepoints, the markers, the generated key, the timeout and what an error
// shows.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'fake_postgres.dart';

ConnectionSettings _settings(
  String url, {
  String? username,
  String? password,
  Map<String, String> properties = const {},
}) => ConnectionSettings(
  url: Uri.parse(url),
  username: username,
  password: password,
  properties: properties,
);

Future<(FakeBinding, FakeSession, JdbcConnection)> _connect(
  String url, {
  Map<String, String> properties = const {},
  String? username,
  String? password,
  FakeBinding? binding,
}) async {
  final fake = binding ?? FakeBinding();
  final connection = await PostgresJdbcDriver(fake).connect(
    _settings(
      url,
      properties: properties,
      username: username,
      password: password,
    ),
  );
  return (fake, fake.sessions.last, connection);
}

void main() {
  group('the driver', () {
    test('its name, schemes and dialect', () {
      final driver = PostgresJdbcDriver(FakeBinding());
      expect(driver.name, 'postgres');
      expect(driver.schemes, ['postgresql', 'postgres']);
      expect(driver.dialect, isA<PostgresDialect>());
    });
  });

  group('the URL', () {
    PostgresEndpoint endpointOf(
      String url, {
      Map<String, String> properties = const {},
      String? username,
      String? password,
    }) => PostgresTarget.parse(
      _settings(
        url,
        properties: properties,
        username: username,
        password: password,
      ),
    ).endpoint(PostgresSslMode.require);

    test('host, port, database, user and password', () {
      final e = endpointOf('postgresql://ann:s3cret@db.example.com:6543/shop');
      expect(
        (e.host, e.port, e.database, e.username, e.password),
        ('db.example.com', 6543, 'shop', 'ann', 's3cret'),
      );
    });

    test('defaults: localhost, 5432, the database of the user', () {
      var e = endpointOf('postgresql://ann@/');
      expect((e.host, e.port, e.database), ('localhost', 5432, 'ann'));
      e = endpointOf('postgres://localhost');
      expect((e.port, e.database, e.username), (5432, 'postgres', null));
    });

    test('percent escapes in the user, the password and the database', () {
      final e = endpointOf('postgresql://a%40b:p%3Ass%2F%25@h/my%20db');
      expect(
        (e.username, e.password, e.database),
        ('a@b', 'p:ss/%', 'my db'),
      );
    });

    test('the URL wins over the properties for the user and password, '
        'which fill what it lacks', () {
      var e = endpointOf(
        'postgresql://ann@h/db',
        username: 'bob',
        password: 'pw',
      );
      expect((e.username, e.password), ('ann', 'pw'));
      e = endpointOf('postgresql://h/db', username: 'bob', password: 'pw');
      expect((e.username, e.password), ('bob', 'pw'));
    });

    test('IPv6 hosts', () {
      final e = endpointOf('postgresql://[::1]:5433/db');
      expect((e.host, e.port), ('::1', 5433));
    });

    test('parameters of the URL', () {
      final e = endpointOf(
        'postgresql://h/db?application_name=shop&connect_timeout=3'
        '&sslrootcert=/etc/ca.pem',
      );
      expect(e.applicationName, 'shop');
      expect(e.connectTimeout, const Duration(seconds: 3));
      expect(e.rootCertificate, '/etc/ca.pem');
    });

    test('the properties win over the URL', () {
      final e = endpointOf(
        'postgresql://h/db?application_name=url&connect_timeout=3',
        properties: {
          'application-name': 'props',
          'connect-timeout': '2s',
          'ssl-root-cert': '/ca.pem',
        },
      );
      expect(e.applicationName, 'props');
      expect(e.connectTimeout, const Duration(seconds: 2));
      expect(e.rootCertificate, '/ca.pem');
    });

    test('connect-timeout: milliseconds, 500ms, 30s, 1m', () {
      Duration timeout(String text) => endpointOf(
        'postgresql://h/db',
        properties: {'connect-timeout': text},
      ).connectTimeout;
      expect(timeout('1500'), const Duration(milliseconds: 1500));
      expect(timeout('500ms'), const Duration(milliseconds: 500));
      expect(timeout('30s'), const Duration(seconds: 30));
      expect(timeout('1m'), const Duration(minutes: 1));
      expect(() => timeout('soon'), throwsA(isA<ArgumentError>()));
      expect(
        () => endpointOf('postgresql://h/db?connect_timeout=x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an unknown parameter or property is an error that never holds '
        'the password', () {
      for (final call in [
        () => endpointOf('postgresql://ann:hunter2@h/db?sslMod=require'),
        () => endpointOf(
          'postgresql://ann:hunter2@h/db',
          properties: {'ssl-mode': 'require'},
        ),
        () => endpointOf('postgresql://ann:hunter2@a,b/db'),
      ]) {
        expect(
          call,
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'text',
              isNot(contains('hunter2')),
            ),
          ),
        );
      }
    });

    test('sslmode, in any case, in the URL or the properties', () {
      PostgresSslSetting mode(
        String url, [
        Map<String, String> properties = const {},
      ]) => PostgresTarget.parse(_settings(url, properties: properties)).mode;
      expect(mode('postgresql://h/db'), PostgresSslSetting.prefer);
      expect(
        mode('postgresql://h/db?sslmode=disable'),
        PostgresSslSetting.disable,
      );
      expect(
        mode('postgresql://h/db?sslMode=REQUIRE'),
        PostgresSslSetting.require,
      );
      expect(
        mode('postgresql://h/db?sslmode=verify-ca'),
        PostgresSslSetting.verifyCa,
      );
      expect(
        mode('postgresql://h/db?sslmode=disable', {'sslmode': 'verify-full'}),
        PostgresSslSetting.verifyFull,
      );
      expect(
        () => mode('postgresql://h/db?sslmode=maybe'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the endpoint does not show the password', () {
      expect(
        endpointOf('postgresql://ann:hunter2@h/db').toString(),
        isNot(contains('hunter2')),
      );
    });
  });

  group('TLS', () {
    Future<FakeBinding> tried(
      String sslmode, {
      List<Object?> failures = const [],
    }) async {
      final binding = FakeBinding(failures: failures);
      await _connect('postgresql://h/db?sslmode=$sslmode', binding: binding);
      return binding;
    }

    test('each mode asks for its own', () async {
      expect((await tried('disable')).endpoints.map((e) => e.sslMode), [
        PostgresSslMode.disable,
      ]);
      expect((await tried('require')).endpoints.map((e) => e.sslMode), [
        PostgresSslMode.require,
      ]);
      expect((await tried('verify-ca')).endpoints.map((e) => e.sslMode), [
        PostgresSslMode.verifyFull,
      ]);
      expect((await tried('verify-full')).endpoints.map((e) => e.sslMode), [
        PostgresSslMode.verifyFull,
      ]);
      // prefer and allow try TLS first, and connect with it when they can.
      expect((await tried('prefer')).endpoints, hasLength(1));
      expect(
        (await tried('allow')).endpoints.single.sslMode,
        PostgresSslMode.require,
      );
    });

    test(
      'prefer falls back to plain text for a server without TLS only',
      () async {
        const noTls = SqlError(
          'Server does not support SSL, but it was required',
        );
        final binding = await tried('prefer', failures: [noTls]);
        expect(binding.endpoints.map((e) => e.sslMode), [
          PostgresSslMode.require,
          PostgresSslMode.disable,
        ]);
      },
    );

    test('a wrong password does not fall back', () async {
      const wrong = SqlError(
        'password authentication failed',
        sqlState: '28P01',
      );
      final binding = FakeBinding(failures: [wrong]);
      await expectLater(
        _connect('postgresql://h/db', binding: binding),
        throwsA(isA<SqlError>().having((e) => e.sqlState, 'state', '28P01')),
      );
      expect(binding.endpoints, hasLength(1));
    });

    test('require does not fall back', () async {
      const noTls = SqlError('Server does not support SSL');
      final binding = FakeBinding(failures: [noTls]);
      await expectLater(
        _connect('postgresql://h/db?sslmode=require', binding: binding),
        throwsA(isA<SqlError>()),
      );
      expect(binding.endpoints, hasLength(1));
    });

    test('when both attempts fail the last error is thrown', () async {
      const noTls = SqlError('Server does not support SSL');
      const refused = SqlError('refused', connectionLost: true);
      final binding = FakeBinding(failures: [noTls, refused]);
      await expectLater(
        _connect('postgresql://h/db', binding: binding),
        throwsA(isA<SqlError>().having((e) => e.message, 'message', 'refused')),
      );
    });
  });

  group('search_path', () {
    test('is set when the connection opens', () async {
      final (_, session, _) = await _connect(
        'postgresql://h/db?currentSchema=shop,public',
      );
      expect(session.statements, ['SET search_path TO "shop", "public"']);
      expect(session.ran.single.simple, isTrue);
    });

    test("the property wins, and none leaves the server's", () async {
      var (_, session, _) = await _connect(
        'postgresql://h/db?currentSchema=a',
        properties: {'search-path': 'b'},
      );
      expect(session.statements, ['SET search_path TO "b"']);
      (_, session, _) = await _connect('postgresql://h/db');
      expect(session.statements, isEmpty);
    });
  });

  group('statements', () {
    test(r'? becomes $1, values go as parameters', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      await connection.query('select * from t where a = ? and b = ?', [1, 'x']);
      expect(
        session.ran.single.sql,
        r'select * from t where a = $1 and b = $2',
      );
      expect(session.ran.single.parameters, [1, 'x']);
      expect(session.ran.single.simple, isFalse);
    });

    test('a marker count that does not match the values is an error', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      await expectLater(
        connection.query('select ?'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        connection.update('update t set a = 1', [5]),
        throwsA(isA<ArgumentError>()),
      );
      expect(session.ran, isEmpty);
    });

    test('a query returns its columns and rows', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      session.answer = (_) => const PostgresResult(
        ['id', 'name'],
        [
          [1, 'a'],
          [2, 'b'],
        ],
        2,
      );
      final result = await connection.query('select id, name from t');
      expect(result.columns, ['id', 'name']);
      expect(result.rows.map((r) => r['name']), ['a', 'b']);
    });

    test('execute goes through the simple protocol, as it is', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      await connection.execute("create table t (a text default '?')");
      expect(session.ran.single.simple, isTrue);
      expect(session.ran.single.sql, "create table t (a text default '?')");
    });

    test('an update returns the rows changed', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      session.answer = (_) => noRows(3);
      final update = await connection.update('delete from t where a = ?', [1]);
      expect(update.affectedRows, 3);
      expect(update.generatedKey, isNull);
    });

    test('a generated key comes through RETURNING the key column', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      session.answer = (_) => const PostgresResult(
        ['id'],
        [
          [42],
        ],
        1,
      );
      final update = await connection.update(
        'insert into t (a) values (?)',
        ['x'],
        true,
        'id',
      );
      expect(update.generatedKey, 42);
      expect(update.affectedRows, 1);
      expect(
        session.ran.single.sql,
        r'insert into t (a) values ($1) RETURNING "id"',
      );
    });

    test(
      'without a key column, the first column of the row is the key',
      () async {
        final (_, session, connection) = await _connect('postgresql://h/db');
        session.answer = (_) => const PostgresResult(
          ['id', 'a'],
          [
            [7, 'x'],
          ],
          1,
        );
        final update = await connection.update('insert into t values (?)', [
          'x',
        ], true);
        expect(update.generatedKey, 7);
        expect(session.ran.single.sql, endsWith('RETURNING *'));
      },
    );

    test('a batch runs the statement once for each list', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      session.answer = (_) => noRows(1);
      final counts = await connection.batchUpdate('insert into t values (?)', [
        [1],
        [2],
        [3],
      ]);
      expect(counts, [1, 1, 1]);
      expect(session.ran.map((r) => r.parameters), [
        [1],
        [2],
        [3],
      ]);
    });

    test('a stream gives the rows and ends the query when cancelled', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      const columns = ['n'];
      session.streamRows = [
        for (var i = 0; i < 5; i++) PostgresRow(columns, [i]),
      ];
      final first = await connection
          .queryStream('select n from t where n > ?', [0])
          .take(2)
          .map((row) => row['n'])
          .toList();
      expect(first, [0, 1]);
      expect(session.streamCancelled, isTrue);
      expect(session.ran.single.sql, r'select n from t where n > $1');
      // The connection is free again.
      await connection.query('select 1');
      expect(session.ran, hasLength(2));
    });

    test('statements run one at a time, in order', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      await Future.wait([
        connection.query('select 1'),
        connection.query('select 2'),
        connection.execute('select 3'),
      ]);
      expect(session.statements, ['select 1', 'select 2', 'select 3']);
    });
  });

  group('transactions', () {
    Future<(FakeSession, JdbcConnection)> open() async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      return (session, connection);
    }

    test('begin, commit and rollback', () async {
      final (session, connection) = await open();
      await connection.begin();
      await connection.commit();
      await connection.begin();
      await connection.rollback();
      expect(session.statements, ['BEGIN', 'COMMIT', 'BEGIN', 'ROLLBACK']);
      expect(session.ran.every((r) => r.simple), isTrue);
    });

    test('isolation levels, read uncommitted as the server takes it', () async {
      final (session, connection) = await open();
      for (final level in Isolation.values) {
        await connection.begin(isolation: level);
        await connection.rollback();
      }
      expect(session.statements.where((s) => s != 'ROLLBACK').toList(), [
        'BEGIN',
        'BEGIN ISOLATION LEVEL READ UNCOMMITTED',
        'BEGIN ISOLATION LEVEL READ COMMITTED',
        'BEGIN ISOLATION LEVEL REPEATABLE READ',
        'BEGIN ISOLATION LEVEL SERIALIZABLE',
      ]);
    });

    test('read only', () async {
      final (session, connection) = await open();
      await connection.begin(
        isolation: Isolation.serializable,
        readOnly: true,
      );
      await connection.begin(readOnly: true, lockForWrite: true);
      expect(session.statements, [
        'BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY',
        'BEGIN READ ONLY',
      ]);
    });

    test('savepoints are quoted', () async {
      final (session, connection) = await open();
      await connection.savepoint('SAVEPOINT_1');
      await connection.rollbackToSavepoint('SAVEPOINT_1');
      await connection.releaseSavepoint('SAVEPOINT_1');
      expect(session.statements, [
        'SAVEPOINT "SAVEPOINT_1"',
        'ROLLBACK TO SAVEPOINT "SAVEPOINT_1"',
        'RELEASE SAVEPOINT "SAVEPOINT_1"',
      ]);
    });
  });

  group('the statement timeout', () {
    test('bounds the statements that follow, until it is lifted', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      await connection.query('select 1');
      await connection.setStatementTimeout(const Duration(seconds: 2));
      await connection.query('select 2');
      await connection.update('update t set a = 1');
      await connection.setStatementTimeout(null);
      await connection.query('select 3');
      await connection.setStatementTimeout(Duration.zero);
      await connection.query('select 4');
      expect(session.ran.map((r) => r.timeout), [
        null,
        const Duration(seconds: 2),
        const Duration(seconds: 2),
        null,
        null,
      ]);
    });
  });

  group('errors', () {
    test('lose what the server says about the data', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      session.answer = (_) => throw const SqlError(
        'invalid input syntax for type integer: "hunter2"',
        sqlState: '22P02',
      );
      await expectLater(
        connection.query('select ?', ['hunter2']),
        throwsA(
          isA<SqlError>()
              .having(
                (e) => e.message,
                'message',
                'invalid input syntax for type integer',
              )
              .having((e) => e.sql, 'sql', 'select ?')
              .having((e) => e.sqlState, 'state', '22P02'),
        ),
      );
    });

    test('keep the message of other errors, and add the statement', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      session.answer = (_) => throw const SqlError(
        'relation "nope" does not exist',
        sqlState: '42P01',
      );
      await expectLater(
        connection.update('delete from nope where a = ?', [1]),
        throwsA(
          isA<SqlError>()
              .having(
                (e) => e.message,
                'message',
                'relation "nope" does not exist',
              )
              .having((e) => e.sql, 'sql', 'delete from nope where a = ?'),
        ),
      );
    });

    test('a failing stream is cleaned too', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      session.streamError = const SqlError(
        'invalid input syntax for type integer: "hunter2"',
        sqlState: '22P02',
      );
      await expectLater(
        connection.queryStream('select ?', [1]).toList(),
        throwsA(
          isA<SqlError>().having(
            (e) => e.message,
            'message',
            isNot(contains('hunter2')),
          ),
        ),
      );
    });
  });

  group('closing', () {
    test(
      'close closes the session once, after the statement running',
      () async {
        final (_, session, connection) = await _connect('postgresql://h/db');
        final pending = connection.query('select 1');
        await connection.close();
        await connection.close();
        await pending;
        expect(session.closed, isTrue);
        expect(connection.isClosed, isTrue);
        await expectLater(
          connection.query('select 2'),
          throwsA(
            isA<SqlError>().having((e) => e.connectionLost, 'lost', true),
          ),
        );
      },
    );

    test('a session the server closed makes the connection closed', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      expect(connection.isClosed, isFalse);
      session.open = false;
      expect(connection.isClosed, isTrue);
      expect(await connection.isValid(), isFalse);
    });

    test('isValid asks the server', () async {
      final (_, session, connection) = await _connect('postgresql://h/db');
      expect(await connection.isValid(), isTrue);
      expect(session.statements, ['SELECT 1']);
      session.answer = (_) =>
          throw const SqlError('gone', connectionLost: true);
      expect(await connection.isValid(), isFalse);
    });
  });
}
