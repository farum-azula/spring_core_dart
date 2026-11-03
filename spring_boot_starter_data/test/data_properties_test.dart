// The properties classes of the Data starter and their editor metadata.
import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/src/data_auto_configuration.dart'
    show memoryLockTimeout;
import 'package:test/test.dart';

import 'sqlite/support.dart';

Environment env(Map<String, String> values) =>
    StandardEnvironment()
      ..propertySources.addFirst(MapPropertySource('test', values));

/// [path] in this package: the tests run from the package directory and from
/// the workspace root.
String _inPackage(String path) =>
    Directory('lib').existsSync() && Directory('test').existsSync()
    ? path
    : 'spring_boot_starter_data/$path';

File _packageFile(String path) => File(_inPackage(path));

Directory _packageDirectory(String path) => Directory(_inPackage(path));

void main() {
  test('the memory lock timeout: 10s, a value, never negative', () {
    expect(
      memoryLockTimeout(env({})),
      const Duration(seconds: 10),
    );
    expect(
      memoryLockTimeout(
        env({'spring.data.memory.lock-timeout': '500ms'}),
      ),
      const Duration(milliseconds: 500),
    );
    expect(
      () => memoryLockTimeout(
        env({'spring.data.memory.lock-timeout': '-1s'}),
      ),
      throwsArgumentError,
    );
  });

  test('the query timeout and the log switches', () {
    expect(jdbcQueryTimeout(env({})), isNull);
    expect(
      jdbcQueryTimeout(
        env({'spring.jdbc.template.query-timeout': '2s'}),
      ),
      const Duration(seconds: 2),
    );
    final log = jdbcLogSettingsOf(
      env({
        'spring.data.jdbc.show-sql': 'true',
        'spring.data.jdbc.format-sql': 'TRUE',
        'spring.data.jdbc.show-parameters': 'false',
        'spring.data.jdbc.slow-query-threshold': '250ms',
      }),
    );
    expect(log.showSql, isTrue);
    expect(log.formatSql, isTrue);
    expect(log.showParameters, isFalse);
    expect(log.slowQueryThreshold, const Duration(milliseconds: 250));
    expect(
      () => jdbcLogSettingsOf(
        env({'spring.data.jdbc.show-sql': 'maybe'}),
      ),
      throwsArgumentError,
    );
  });

  test('every metadata key is read somewhere in lib/', () {
    final json = jsonDecode(
      _packageFile('lib/spring_gen/spring_metadata.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final names = [
      for (final p in json['properties']! as List)
        (p as Map<String, Object?>)['name']! as String,
    ];
    expect(names, contains('spring.datasource.url'));
    expect(names, contains('spring.sql.migration.lock-timeout'));
    expect(names, contains('spring.datasources.*.sql.init.mode'));
    expect(names, contains('spring.data.web.sort.sort-parameter'));
    // The last part of a key (`lock-timeout`) is spelled out in the code
    // that reads it.
    final sources = [
      for (final f in _packageDirectory('lib/src').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f.readAsStringSync(),
    ].join('\n');
    final unread = [
      for (final name in names)
        if (!sources.contains(name.split('.').last)) name,
    ];
    expect(unread, isEmpty);
  });

  // The pool and the drivers read their settings as text or from their own
  // defaults, so the classes that describe (and bind) them must not drift.
  group('the classes and the readers they cannot bind agree', () {
    Set<String> keysBelow(String prefix) {
      final json = jsonDecode(
        _packageFile('lib/spring_gen/spring_metadata.json').readAsStringSync(),
      ) as Map<String, Object?>;
      return {
        for (final p in json['properties']! as List)
          if (((p as Map<String, Object?>)['name']! as String).startsWith(
            prefix,
          ))
            (p['name']! as String).substring(prefix.length),
      };
    }

    test('the pool defaults are those of PoolSettings', () {
      const pool = DataSourcePoolProperties();
      const settings = PoolSettings();
      expect(pool.maxSize, settings.maxSize);
      expect(pool.minIdle, settings.minIdle);
      expect(pool.connectionTimeout, settings.connectionTimeout);
      expect(pool.idleTimeout, settings.idleTimeout);
      expect(pool.maxLifetime, settings.maxLifetime);
      expect(pool.validation, settings.validation);
    });

    test('the SQLite keys and defaults are those of the driver', () async {
      final driver = await startDriver();
      expect(
        keysBelow('spring.datasource.sqlite.'),
        driver.propertyNames.toSet(),
      );
      const sqlite = SqliteConfigProperties();
      expect(
        Duration(milliseconds: sqlite.busyTimeout),
        SqliteJdbcDriver.defaultBusyTimeout,
      );
      expect(sqlite.isolate, isFalse);
    });

    test('the PostgreSQL keys and defaults are those of the driver', () {
      expect(
        keysBelow('spring.datasource.postgresql.'),
        PostgresTarget.propertyNames.toSet(),
      );
      final target = PostgresTarget.parse(
        ConnectionSettings(url: Uri.parse('postgresql://host/db')),
      );
      const postgresql = PostgresqlConfigProperties();
      expect(target.connectTimeout, postgresql.connectTimeout);
      expect(target.mode, postgresql.sslmode);
    });
  });
}
