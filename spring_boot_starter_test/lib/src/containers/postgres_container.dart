import 'dart:io';

import 'package:spring_boot_starter_test/src/containers/generic_container.dart';
import 'package:spring_boot_starter_test/src/containers/socket_guard.dart';
import 'package:spring_boot_starter_test/src/containers/wait.dart';

/// PostgreSQL in a container, ready for a test: a database, a user and a
/// password set through the image's environment, and a wait that outlasts
/// the image's two-step start: a temporary server initialises the database
/// and stops, then the real one starts, so the container is ready when
/// `database system is ready to accept connections` was logged twice (the
/// wait of Testcontainers' `PostgreSQLContainer`), the port accepts
/// connections, and the server answers the protocol's first message
/// through the published port.
///
/// [url] and [jdbcUrl] are in the form `spring_boot_starter_data` reads
/// (`postgresql://user:password@host:port/database`); as a
/// `@ServiceConnection()` it sets `spring.datasource.url`,
/// `spring.datasource.username` and `spring.datasource.password` for the
/// test's context, so a repository test runs on this server with no other
/// configuration. This package does not depend on the data starter: the
/// properties are plain strings.
///
/// ```dart
/// @DataTest(replaceDatabase: false) // the real Postgres, not SQLite
/// class BookRepositoryTest {
///   @Container()
///   @ServiceConnection()
///   static final postgres = PostgresContainer('postgres:17-alpine');
///   // ...
/// }
/// ```
///
/// Testcontainers (Java): `PostgreSQLContainer` (`getJdbcUrl()`,
/// `getUsername()`, `getPassword()`), with Spring Boot's `@ServiceConnection`.
class PostgresContainer extends GenericContainer
    implements ServiceConnectionProperties {
  /// PostgreSQL from [image] (`postgres:17-alpine` unless given), with the
  /// database, user and password `test`.
  PostgresContainer([super.image = 'postgres:17-alpine']) {
    withDatabaseName('test');
    withUsername('test');
    withPassword('test');
    withExposedPorts([port]);
    waitingFor(
      Wait.forAll([
        Wait.forLogMessage('database system is ready to accept connections', 2),
        Wait.forListeningPort(),
        const PostgresProtocolWait(),
      ]),
    );
  }

  /// PostgreSQL's port in the container.
  static const port = 5432;

  /// The database that is created and the tests connect to.
  String get databaseName => _database;
  String _database = 'test';

  /// The user that is created.
  String get username => _username;
  String _username = 'test';

  /// The user's password.
  String get password => _password;
  String _password = 'test';

  /// Names the database (`POSTGRES_DB`).
  PostgresContainer withDatabaseName(String name) {
    _database = name;
    withEnv('POSTGRES_DB', name);
    return this;
  }

  /// Names the user (`POSTGRES_USER`).
  PostgresContainer withUsername(String name) {
    _username = name;
    withEnv('POSTGRES_USER', name);
    return this;
  }

  /// Sets the user's password (`POSTGRES_PASSWORD`).
  PostgresContainer withPassword(String value) {
    _password = value;
    withEnv('POSTGRES_PASSWORD', value);
    return this;
  }

  /// Runs the SQL file at [hostPath] when the database is created (the
  /// image's `/docker-entrypoint-initdb.d/`); files run in the order of
  /// their names.
  PostgresContainer withInitScript(String hostPath) {
    withCopyFile(
      hostPath,
      '/docker-entrypoint-initdb.d/${hostPath.split(RegExp(r'[/\\]')).last}',
    );
    return this;
  }

  /// The address of the database without credentials,
  /// `postgresql://host:port/database`: with [username] and [password]
  /// as `spring.datasource.*` properties.
  String get jdbcUrl =>
      'postgresql://$host:${mappedPort(port)}/${Uri.encodeComponent(_database)}';

  /// The address with the credentials,
  /// `postgresql://user:password@host:port/database`, as the data starter's
  /// test settings (`SPRING_TEST_POSTGRES_URL`) have it.
  String get url =>
      'postgresql://${Uri.encodeComponent(_username)}:'
      '${Uri.encodeComponent(_password)}@$host:${mappedPort(port)}/'
      '${Uri.encodeComponent(_database)}';

  @override
  Map<String, String> get connectionProperties => {
    'spring.datasource.url': jdbcUrl,
    'spring.datasource.username': _username,
    'spring.datasource.password': _password,
  };

  @override
  String toString() => 'PostgresContainer($image)';
}

/// Ready when the published port answers PostgreSQL's `SSLRequest` with its
/// one-byte reply (`S` or `N`): the server, not a port forwarder in front of
/// a server that is not there (yet), is on the other side.
///
/// Not exported: the tests reach it through the file.
final class PostgresProtocolWait implements WaitStrategy {
  /// A wait for the server's answer to the protocol's first message.
  const PostgresProtocolWait();

  static const _sslRequest = [0, 0, 0, 8, 4, 210, 22, 47];

  @override
  Future<void> waitUntilReady(WaitTarget target) async {
    final port = target.mappedPort(PostgresContainer.port);
    await target.poll(
      'the server answering on port $port',
      () => _answers(target.host, port),
    );
  }

  static Future<bool> _answers(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      // The reset that ends a probe of a server not there yet also fails
      // the socket's `done`; nobody else would hear it.
      ignoreDoneErrors(socket);
      socket.add(_sslRequest);
      final reply = await socket.first.timeout(const Duration(seconds: 2));
      return reply.length == 1 && (reply[0] == 0x53 || reply[0] == 0x4e);
    } on Object {
      // Reset, closed without an answer, or no answer: not ready yet.
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
