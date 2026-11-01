import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/postgres/postgres_binding.dart';
import 'package:spring_boot_starter_data/src/jdbc/postgres/postgres_dialect.dart';
import 'package:spring_boot_starter_data/src/jdbc/postgres/postgres_markers.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/jdbc/statement_mutex.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';

/// The driver of PostgreSQL, written on a [PostgresBinding] (the generator
/// wires one over the `postgres` package when the application lists it).
///
/// The URLs it opens, `postgresql://` or `postgres://` (a leading `jdbc:` is
/// dropped before it gets here):
///
/// ```text
/// postgresql://user:password@db.example.com:5432/shop?sslmode=require
/// ```
///
/// The host defaults to `localhost`, the port to 5432, the database to the
/// user's name (else `postgres`); a user or password with special characters
/// is percent-encoded in the URL (`%40` for `@`), or given by the
/// `spring.datasource.username` and `password` properties (the URL wins).
/// The parameters after `?` are `sslmode`, `sslrootcert`, `connect_timeout`
/// (seconds), `application_name` and `currentSchema` (or `search_path`); any
/// other is an error, so that a typo never silently weakens a setting. The
/// data source's own properties (`spring.datasource.postgresql.*`, or
/// `postgres.*`) set the same, and win: `sslmode`, `ssl-root-cert`,
/// `connect-timeout` (milliseconds, or `500ms`, `30s`, `1m`),
/// `application-name` and `search-path`.
///
/// **TLS.** `sslmode` is libpq's, and the default is `prefer`:
///
/// - `disable`: no TLS;
/// - `prefer` and `allow`: TLS first, plain text when the server does not
///   have TLS (an attacker who can cut the connection can force that; use
///   `require` or `verify-full` for anything but a development database);
/// - `require`: TLS, the certificate is not checked;
/// - `verify-ca` and `verify-full`: TLS, with the certificate and the host
///   name checked (the package checks both, so `verify-ca` is as strict as
///   `verify-full`) against the system's roots or the `sslrootcert` PEM
///   file.
///
/// Statements use `?` for each parameter, written `$1`, `$2` for the server
/// (`??` is a literal `?`, as in PostgreSQL's JDBC driver, for the `jsonb`
/// operators); the text between quotes, in comments and in `$$` is left
/// alone. Values go to the server as parameters, never into the text.
/// Error messages keep what the server says about the statement and drop
/// what it says about the data (a rejected value in `invalid input syntax
/// for type integer`, the `DETAIL` line of a duplicate key).
///
/// Spring (Java): `org.postgresql.Driver` (pgjdbc), with Spring Boot's
/// `DataSourceProperties` choosing it by the URL.
final class PostgresJdbcDriver implements JdbcDriver {
  /// A driver over [binding].
  PostgresJdbcDriver(this.binding);

  /// What opens the connections.
  final PostgresBinding binding;

  static const _log = SpringLog('spring.jdbc.postgres');

  // The databases (by URL) whose fall back to plain text was reported.
  final _warned = <String>{};

  @override
  String get name => 'postgres';

  @override
  List<String> get schemes => const ['postgresql', 'postgres'];

  @override
  SqlDialect get dialect => const PostgresDialect();

  @override
  List<String> get propertyNames => PostgresTarget.propertyNames;

  @override
  Future<JdbcConnection> connect(ConnectionSettings settings) async {
    final target = PostgresTarget.parse(settings);
    PostgresSession? session;
    final attempts = target.mode.attempts;
    for (var i = 0; i < attempts.length; i++) {
      final endpoint = target.endpoint(attempts[i]);
      try {
        session = await binding.open(endpoint);
        _log.debug(
          () =>
              'Opened ${settings.safeUrl} '
              '(${attempts[i] == PostgresSslMode.disable ? 'no TLS' : 'TLS'})',
        );
        break;
      } on SqlError catch (error) {
        // `prefer` and `allow`: only a server without TLS is tried again
        // without; a wrong password or a missing database stops here.
        final last = i == attempts.length - 1;
        if (last || !PostgresTarget.noTls(error)) {
          throw cleanError(error);
        }
        // Once for each database: the pool opens connections all day.
        if (_warned.add(settings.safeUrl)) {
          _log.warning(
            'The server of ${settings.safeUrl} has no TLS: connecting in '
            'plain text (sslmode=${target.mode.text}). Set sslmode to '
            'require, or to verify-full to check the certificate and the '
            'host name, so a connection that cannot be encrypted is refused',
          );
        }
      }
    }
    final connection = _PostgresConnection(session!);
    if (target.searchPath.isNotEmpty) {
      try {
        await connection.execute(
          'SET search_path TO '
          '${target.searchPath.map(const PostgresDialect().quote).join(', ')}',
        );
      } on Object {
        await connection.close();
        rethrow;
      }
    }
    return connection;
  }
}

/// The `sslmode` of a URL, as libpq writes it.
enum PostgresSslSetting {
  /// `disable`.
  disable('disable', [PostgresSslMode.disable]),

  /// `allow`: tried with TLS first, like `prefer`.
  allow('allow', [PostgresSslMode.require, PostgresSslMode.disable]),

  /// `prefer`, the default.
  prefer('prefer', [PostgresSslMode.require, PostgresSslMode.disable]),

  /// `require`.
  require('require', [PostgresSslMode.require]),

  /// `verify-ca`: as strict as `verify-full`.
  verifyCa('verify-ca', [PostgresSslMode.verifyFull]),

  /// `verify-full`.
  verifyFull('verify-full', [PostgresSslMode.verifyFull]);

  PostgresSslSetting(this.text, this.attempts);

  /// How it is written.
  final String text;

  /// The modes tried in turn.
  final List<PostgresSslMode> attempts;

  /// The setting written [text], or null.
  static PostgresSslSetting? parse(String text) {
    final wanted = text.trim().toLowerCase();
    for (final value in values) {
      if (value.text == wanted) {
        return value;
      }
    }
    return null;
  }
}

/// What a URL and the properties of a data source ask for: the part of
/// [PostgresJdbcDriver.connect] that needs no connection.
final class PostgresTarget {
  PostgresTarget._({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.mode,
    required this.rootCertificate,
    required this.connectTimeout,
    required this.applicationName,
    required this.searchPath,
  });

  /// Reads [settings]; throws an [ArgumentError] (which names the setting
  /// and never holds the password) for a URL or a property that is not
  /// valid.
  factory PostgresTarget.parse(ConnectionSettings settings) {
    final url = settings.url;
    final shown = settings.safeUrl.split('?').first;
    for (final key in settings.properties.keys) {
      if (!_properties.contains(key)) {
        throw ArgumentError.value(
          key,
          'property',
          'Unknown PostgreSQL property in $shown: the keys are '
              '${_properties.join(', ')}',
        );
      }
    }
    // The keys of the query are compared without case, as `sslMode`.
    final query = <String, String>{};
    for (final entry in url.queryParameters.entries) {
      final key = entry.key.toLowerCase();
      if (!_urlParameters.contains(key)) {
        throw ArgumentError.value(
          entry.key,
          'url',
          'Unknown parameter in $shown: the parameters are '
              '${_urlParameters.join(', ')}',
        );
      }
      query[key] = entry.value;
    }
    final properties = settings.properties;
    String? pick(String urlKey, String property) =>
        properties[property] ?? query[urlKey];

    final userInfo = url.userInfo;
    final colon = userInfo.indexOf(':');
    String? decode(String text) =>
        text.isEmpty ? null : Uri.decodeComponent(text);
    final username =
        decode(colon < 0 ? userInfo : userInfo.substring(0, colon)) ??
        settings.username;
    final password =
        (colon < 0 ? null : decode(userInfo.substring(colon + 1))) ??
        settings.password;

    final sslText = pick('sslmode', 'sslmode');
    final mode = sslText == null
        ? PostgresSslSetting.prefer
        : PostgresSslSetting.parse(sslText) ??
              (throw ArgumentError.value(
                sslText,
                'sslmode',
                'Must be disable, allow, prefer, require, verify-ca or '
                    'verify-full',
              ));
    final host = url.host.isEmpty ? 'localhost' : url.host;
    if (host.contains(',')) {
      throw ArgumentError.value(
        shown,
        'url',
        'One host only: the driver does not choose among several',
      );
    }
    final database = url.pathSegments.isEmpty || url.pathSegments.first.isEmpty
        ? (username ?? 'postgres')
        : Uri.decodeComponent(url.pathSegments.first);
    final timeoutText = properties['connect-timeout'];
    final Duration connectTimeout;
    if (timeoutText != null) {
      connectTimeout = _duration(timeoutText);
    } else if (query['connect_timeout'] case final seconds?) {
      final value = int.tryParse(seconds.trim());
      if (value == null || value < 0) {
        throw ArgumentError.value(
          seconds,
          'connect_timeout',
          'Must be a number of seconds, zero or more',
        );
      }
      connectTimeout = Duration(seconds: value);
    } else {
      connectTimeout = const Duration(seconds: 15);
    }
    final path = pick('currentschema', 'search-path') ?? query['search_path'];
    return PostgresTarget._(
      host: host,
      port: url.hasPort ? url.port : 5432,
      database: database,
      username: username,
      password: password,
      mode: mode,
      rootCertificate: properties['ssl-root-cert'] ?? query['sslrootcert'],
      connectTimeout: connectTimeout,
      applicationName: pick('application_name', 'application-name'),
      searchPath: [
        for (final part in (path ?? '').split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ],
    );
  }

  /// The host.
  final String host;

  /// The port.
  final int port;

  /// The database.
  final String database;

  /// The user.
  final String? username;

  /// The password.
  final String? password;

  /// The `sslmode`.
  final PostgresSslSetting mode;

  /// The `sslrootcert` file.
  final String? rootCertificate;

  /// The connection timeout.
  final Duration connectTimeout;

  /// The application name.
  final String? applicationName;

  /// The schemas of `search_path`, empty for the server's.
  final List<String> searchPath;

  static const _urlParameters = {
    'sslmode',
    'sslrootcert',
    'connect_timeout',
    'application_name',
    'currentschema',
    'search_path',
  };

  static const _properties = {
    'sslmode',
    'ssl-root-cert',
    'connect-timeout',
    'application-name',
    'search-path',
  };

  /// The settings of `spring.datasource.postgresql.*`.
  static List<String> get propertyNames => List.unmodifiable(_properties);

  /// The endpoint for one attempt, with [sslMode].
  PostgresEndpoint endpoint(PostgresSslMode sslMode) => PostgresEndpoint(
    host: host,
    port: port,
    database: database,
    username: username,
    password: password,
    sslMode: sslMode,
    rootCertificate: rootCertificate,
    connectTimeout: connectTimeout,
    applicationName: applicationName,
  );

  /// Whether [error] says that the server does not have TLS (the
  /// `postgres` package says it in its message; nothing else does).
  static bool noTls(SqlError error) =>
      error.sqlState == null && error.message.contains('does not support SSL');

  static Duration _duration(String text) {
    final match = RegExp(r'^\s*(\d+)\s*(ms|s|m)?\s*$').firstMatch(text);
    if (match == null) {
      throw ArgumentError.value(
        text,
        'connect-timeout',
        'Must be a number of milliseconds, or 500ms, 30s, 1m',
      );
    }
    final value = int.parse(match[1]!);
    return switch (match[2]) {
      's' => Duration(seconds: value),
      'm' => Duration(minutes: value),
      _ => Duration(milliseconds: value),
    };
  }
}

/// [error] without what the server says about the data: the `postgres`
/// package never passes the `DETAIL` line, and the message of a data
/// exception (`invalid input syntax for type integer: "abc"`) loses the
/// quoted value after the colon.
SqlError cleanError(SqlError error, {String? sql}) {
  var message = error.message;
  final state = error.sqlState;
  if (state != null && state.startsWith('22')) {
    final cut = message.indexOf(': ');
    if (cut >= 0) {
      message = message.substring(0, cut);
    }
  }
  if (identical(message, error.message) && error.sql == null && sql == null) {
    return error;
  }
  return SqlError(
    message,
    sqlState: error.sqlState,
    vendorCode: error.vendorCode,
    extendedCode: error.extendedCode,
    constraint: error.constraint,
    sql: error.sql ?? sql,
    cause: error.cause,
    connectionLost: error.connectionLost,
  );
}

final class _PostgresConnection implements JdbcConnection {
  _PostgresConnection(this._session);

  final PostgresSession _session;
  final _mutex = StatementMutex();
  bool _closed = false;
  Duration? _timeout;

  // Runs [action] on the session, with the errors cleaned.
  Future<T> _run<T>(Future<T> Function() action, {String? sql}) async {
    if (_closed) {
      throw const SqlError('The connection is closed', connectionLost: true);
    }
    try {
      return await action();
    } on SqlError catch (error) {
      throw cleanError(error, sql: sql);
    }
  }

  @override
  bool get isClosed => _closed || !_session.isOpen;

  // The text for the server, with its markers; [parameters] is what the
  // statement was given.
  static String _text(String sql, List<Object?> parameters) {
    final rewritten = PostgresMarkers.rewrite(sql);
    if (rewritten.count != parameters.length) {
      throw ArgumentError(
        'The statement has ${rewritten.count} parameter marker(s) and '
        '${parameters.length} value(s) were given',
      );
    }
    return rewritten.sql;
  }

  @override
  Future<JdbcResult> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) => _mutex.run(() async {
    final text = _text(sql, parameters);
    final result = await _run(
      () => _session.execute(text, parameters: parameters, timeout: _timeout),
      sql: sql,
    );
    return JdbcResult(result.columns, result.rows);
  });

  @override
  Stream<JdbcRow> queryStream(
    String sql, [
    List<Object?> parameters = const [],
  ]) async* {
    final text = _text(sql, parameters);
    // The rows come on the connection until the stream ends or is
    // cancelled: nothing else runs meanwhile.
    final release = await _mutex.acquire();
    try {
      if (_closed) {
        throw const SqlError('The connection is closed', connectionLost: true);
      }
      try {
        await for (final row in _session.stream(
          text,
          parameters: parameters,
          timeout: _timeout,
        )) {
          yield JdbcRow(row.columns, row.values);
        }
      } on SqlError catch (error) {
        throw cleanError(error, sql: sql);
      }
    } finally {
      release();
    }
  }

  @override
  Future<JdbcUpdate> update(
    String sql, [
    List<Object?> parameters = const [],
    bool returnGeneratedKey = false,
    String? keyColumn,
  ]) => _mutex.run(() async {
    final returning = keyColumn == null
        ? '*'
        : const PostgresDialect().quote(keyColumn);
    final keyed = returnGeneratedKey ? '$sql RETURNING $returning' : sql;
    final text = _text(keyed, parameters);
    final result = await _run(
      () => _session.execute(text, parameters: parameters, timeout: _timeout),
      sql: sql,
    );
    final key = returnGeneratedKey && result.rows.isNotEmpty
        ? result.rows.first.first
        : null;
    return JdbcUpdate(result.affectedRows, key);
  });

  @override
  Future<List<int>> batchUpdate(String sql, List<List<Object?>> batch) =>
      _mutex.run(() async {
        final counts = <int>[];
        for (final parameters in batch) {
          final text = _text(sql, parameters);
          final result = await _run(
            () => _session.execute(
              text,
              parameters: parameters,
              timeout: _timeout,
            ),
            sql: sql,
          );
          counts.add(result.affectedRows);
        }
        return counts;
      });

  @override
  Future<void> execute(String sql) => _mutex.run(
    () => _run(() => _session.execute(sql, simple: true), sql: sql),
  );

  @override
  Future<void> begin({
    Isolation isolation = Isolation.defaultLevel,
    bool readOnly = false,
    bool lockForWrite = false,
  }) {
    // READ UNCOMMITTED is accepted and works as READ COMMITTED, as the
    // server documents.
    final level = switch (isolation) {
      Isolation.defaultLevel => '',
      Isolation.readUncommitted => ' ISOLATION LEVEL READ UNCOMMITTED',
      Isolation.readCommitted => ' ISOLATION LEVEL READ COMMITTED',
      Isolation.repeatableRead => ' ISOLATION LEVEL REPEATABLE READ',
      Isolation.serializable => ' ISOLATION LEVEL SERIALIZABLE',
    };
    return execute('BEGIN$level${readOnly ? ' READ ONLY' : ''}');
  }

  @override
  Future<void> commit() => execute('COMMIT');

  @override
  Future<void> rollback() => execute('ROLLBACK');

  @override
  Future<void> savepoint(String name) => execute('SAVEPOINT ${_quote(name)}');

  @override
  Future<void> rollbackToSavepoint(String name) =>
      execute('ROLLBACK TO SAVEPOINT ${_quote(name)}');

  @override
  Future<void> releaseSavepoint(String name) =>
      execute('RELEASE SAVEPOINT ${_quote(name)}');

  static String _quote(String name) => const PostgresDialect().quote(name);

  /// Bounds each statement that follows: the server cancels one past the
  /// time (SQL state `57014`, a `QueryTimeoutException`), and the
  /// connection stays usable, in its transaction too (which the failed
  /// statement leaves to be rolled back, as any error does).
  @override
  Future<void> setStatementTimeout(Duration? timeout) async {
    _timeout = timeout == null || timeout <= Duration.zero ? null : timeout;
  }

  @override
  Future<bool> isValid() async {
    if (isClosed) {
      return false;
    }
    try {
      await _mutex.run(() => _session.execute('SELECT 1', simple: true));
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    // After the statement running now.
    await _mutex.run(() {
      if (_closed) {
        return null;
      }
      _closed = true;
      return _session.close();
    });
  }
}
