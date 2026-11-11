@Tags(['supabase'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A connection that records what is run on it.
final class _Connection implements JdbcConnection {
  final statements = <(String, List<Object?>)>[];

  @override
  Future<void> execute(String sql) async => statements.add((sql, const []));

  @override
  Future<JdbcResult> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    statements.add((sql, parameters));
    return JdbcResult(const [], const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Driver implements JdbcDriver {
  _Driver(this.name);

  @override
  final String name;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DataSource extends DataSource {
  _DataSource(String url, {String driver = 'postgres'})
    : super(
        name: 'default',
        driver: _Driver(driver),
        settings: ConnectionSettings(url: Uri.parse(url)),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Credentials implements SupabaseCredentials {
  SupabaseCaller who = const SupabaseCaller.anon();
  String token = 'anon-key';

  @override
  String get apiKey => 'k';

  @override
  Future<String> accessToken() async => token;

  @override
  SupabaseCaller get caller => who;

  @override
  Future<T> asServiceRole<T>(FutureOr<T> Function() body) async => await body();
}

const _database =
    'postgresql://postgres:secret@db.abcd.supabase.co:5432/postgres';

void main() {
  late _Credentials credentials;
  late _Connection connection;
  late SupabaseRlsSessionHook hook;
  final dataSource = _DataSource(
    'postgresql://db.abcd.supabase.co:5432/postgres',
  );

  SupabaseRlsSessionHook hookOf({SupabaseRls rls = SupabaseRls.user}) =>
      SupabaseRlsSessionHook(
        properties: properties()
          ..db.url = _database
          ..db.rls = rls,
        credentials: credentials,
      );

  setUp(() {
    credentials = _Credentials();
    connection = _Connection();
    hook = hookOf();
  });

  void asUser() {
    credentials
      ..who = const SupabaseCaller.user('user-7')
      ..token = unsignedToken({
        'sub': 'user-7',
        'role': 'authenticated',
        'email': "o'neil@example.com",
      });
  }

  test(
    'a transaction of a user: the role and the claims, for it only',
    () async {
      asUser();
      await hook.afterBegin(ConnectionHolder(dataSource, connection));
      expect(connection.statements.first.$1, 'set local role authenticated');
      expect(connection.statements.first.$2, isEmpty);
      final (sql, parameters) = connection.statements.last;
      expect(sql, contains("set_config('request.jwt.claims', ?, true)"));
      expect(jsonDecode(parameters[0]! as String), {
        'sub': 'user-7',
        'role': 'authenticated',
        'email': "o'neil@example.com",
      });
      expect(parameters.sublist(1), ['user-7', 'authenticated']);
      // The claims are values: nothing of them is in the SQL text.
      expect(sql, isNot(contains('user-7')));
      expect(sql, isNot(contains('neil')));
    },
  );

  test('nobody signed in: the role anon', () async {
    await hook.afterBegin(ConnectionHolder(dataSource, connection));
    expect(connection.statements.first.$1, 'set local role anon');
    expect(connection.statements.last.$2, ['{"role":"anon"}', '', 'anon']);
  });

  test(
    'outside a transaction: set on the connection, then taken off',
    () async {
      asUser();
      await hook.beforeWork(dataSource, connection);
      expect(connection.statements.first.$1, 'set role authenticated');
      expect(
        connection.statements.last.$1,
        contains("set_config('request.jwt.claims', ?, false)"),
      );
      connection.statements.clear();
      await hook.afterWork(dataSource, connection);
      expect(connection.statements.first.$1, 'reset role');
      expect(connection.statements.last.$2, ['', '', '']);
    },
  );

  test('the service role is the user of the address: nothing is set', () async {
    credentials.who = const SupabaseCaller.service();
    await hook.afterBegin(ConnectionHolder(dataSource, connection));
    await hook.beforeWork(dataSource, connection);
    expect(connection.statements, isEmpty);
  });

  test('a user whose token has no claims is refused', () async {
    credentials
      ..who = const SupabaseCaller.user('user-7')
      ..token = 'not-a-jwt';
    await expectLater(
      hook.afterBegin(ConnectionHolder(dataSource, connection)),
      throwsA(isA<PermissionDeniedDataAccessException>()),
    );
    expect(connection.statements, isEmpty);
  });

  group('only the database of spring.supabase.db.url is touched', () {
    for (final (name, other) in [
      (
        'another host',
        _DataSource('postgresql://other.example.com:5432/postgres'),
      ),
      (
        'another database',
        _DataSource('postgresql://db.abcd.supabase.co:5432/app'),
      ),
      (
        'another port',
        _DataSource('postgresql://db.abcd.supabase.co:6543/postgres'),
      ),
      (
        'another driver',
        _DataSource(
          'sqlite://db.abcd.supabase.co:5432/postgres',
          driver: 'sqlite',
        ),
      ),
    ]) {
      test(name, () async {
        asUser();
        await hook.afterBegin(ConnectionHolder(other, connection));
        await hook.beforeWork(other, connection);
        await hook.afterWork(other, connection);
        expect(connection.statements, isEmpty);
      });
    }

    test('the default port is 5432', () async {
      asUser();
      await hook.afterBegin(
        ConnectionHolder(
          _DataSource('postgresql://db.abcd.supabase.co/postgres'),
          connection,
        ),
      );
      expect(connection.statements, isNotEmpty);
    });
  });

  test('rls: off does nothing', () async {
    asUser();
    final off = hookOf(rls: SupabaseRls.off);
    await off.afterBegin(ConnectionHolder(dataSource, connection));
    await off.beforeWork(dataSource, connection);
    await off.afterWork(dataSource, connection);
    expect(connection.statements, isEmpty);
  });
}
