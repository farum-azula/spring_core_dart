import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_properties.dart';
import 'package:spring_boot_starter_data/src/jdbc/sqlite/sqlite_jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_settings.dart';
import 'package:spring_boot_starter_data/src/schema/schema_support.dart';
import 'package:spring_boot_starter_data/src/schema/script_database_initializer.dart';

const _log = SpringLog('spring.data.test.TestDatabase');

/// Replaces the SQL databases of the properties by in-memory SQLite ones
/// before the context starts, as `@DataTest` does: each
/// `spring.datasource.url` and `spring.datasources.<name>.url` is set to
/// `sqlite::memory:`.
///
/// What it sets for each database, as a property source that wins over the
/// others:
///
/// - `url` is `sqlite::memory:` and `driver` is `sqlite3`: the database
///   lives as long as its connection;
/// - `pool.max-size` is 1, because each connection of SQLite gets a database
///   of its own, so a second connection would see none of the tables (the
///   SQLite that the `sqlite3` package bundles has no shared cache, which
///   would let connections share one). `pool.idle-timeout` and
///   `pool.max-lifetime` are 0 (never), `pool.min-idle` is 0, so the pool
///   never closes the connection and loses the data. The connection is used
///   by one task at a time, which a test running in its transaction is, but
///   a `Propagation.requiresNew` transaction waits for it and fails after
///   the connection timeout;
/// - `data.jdbc.schema` is `create` (the tables are made from the entities)
///   when the property is not set and neither migrations nor SQL scripts
///   make the schema: with them the application's own schema is used, as
///   it is in production.
///
/// Every other property stays: the username, the migrations' settings, the
/// logging of SQL. A database that is not configured is left alone, and the
/// application's own `DataSource` bean (one the properties do not describe)
/// cannot be replaced.
///
/// The start fails with a [StateError] when a database is to be replaced and
/// the application has no SQLite driver, since the tests would otherwise use
/// the configured database (Spring fails the same way when there is no
/// embedded database).
///
/// Spring (Java): `@AutoConfigureTestDatabase` (`TestDatabaseAutoConfiguration`
/// replaces the `DataSource` with an embedded H2, HSQL or Derby database).
final class TestDatabase implements ApplicationContextInitializer {
  /// A replacement; [hasSqliteDriver] says whether the application has the
  /// `sqlite3` driver (see [hasSqliteDriverIn]).
  const TestDatabase({required this.hasSqliteDriver});

  /// Whether the application has a SQLite driver to open the databases.
  final bool hasSqliteDriver;

  /// The URL of every replaced database.
  static const url = 'sqlite::memory:';

  /// The name of the property source the replacement adds.
  static const propertySourceName = 'Data Test Database';

  /// Whether [definitions] hold a SQLite driver: the bean the generator
  /// writes for the `sqlite3` package (`sqlite3JdbcDriver`), or one of the
  /// application's own of class `SqliteJdbcDriver`.
  static bool hasSqliteDriverIn(Iterable<BeanDefinition<Object>> definitions) =>
      definitions.any(
        (definition) =>
            definition.name == 'sqlite3JdbcDriver' ||
            definition.types.contains(SqliteJdbcDriver),
      );

  @override
  void initialize(ConfigurableApplicationContext context) {
    final environment = context.environment;
    final databases = _databases(environment);
    if (databases.isEmpty) {
      return;
    }
    if (!hasSqliteDriver) {
      final names = [
        for (final database in databases)
          database.prefix.substring(0, database.prefix.length - 1),
      ];
      throw StateError(
        'A @DataTest replaces the database of ${names.join(', ')} '
        'with an in-memory SQLite one, and the application has no SQLite '
        'driver: add the sqlite3 package to its dependencies (pubspec.yaml) '
        'and run the code generator again, or write '
        '@DataTest(replaceDatabase: false) to test on the configured '
        'database',
      );
    }
    final resolver = patternResolverOf(context);
    final properties = <String, Object?>{};
    for (final database in databases) {
      final p = database.prefix;
      properties.addAll({
        '${p}url': url,
        '${p}driver': 'sqlite3',
        '${p}pool.max-size': '1',
        '${p}pool.min-idle': '0',
        '${p}pool.idle-timeout': '0',
        '${p}pool.max-lifetime': '0',
      });
      final schemaKey = '${database.settingsPrefix}data.jdbc.schema';
      if ((environment.getProperty(schemaKey) ?? '').trim().isEmpty &&
          !_ownsSchema(environment, resolver, database.settingsPrefix)) {
        properties[schemaKey] = 'create';
      }
      _log.debug(() => 'Replaced the database of ${p}url by $url');
    }
    environment.propertySources.addFirst(
      MapPropertySource(propertySourceName, properties),
    );
  }

  // The databases the properties configure: the primary one, and each
  // named one.
  static List<_Database> _databases(Environment environment) => [
    if (DataSourceProperties.hasPrimary(environment))
      const _Database(DataSourceProperties.primaryPrefix, 'spring.'),
    for (final name in DataSourceProperties.namedDataSources(environment))
      if ((environment.getProperty(
                '${DataSourceProperties.prefixOf(name)}url',
              ) ??
              '')
          .trim()
          .isNotEmpty)
        _Database(
          DataSourceProperties.prefixOf(name),
          DataSourceProperties.prefixOf(name),
        ),
  ];

  // Whether migration files or SQL scripts own the schema, which
  // `spring.data.jdbc.schema=create` would then contest (the initializer
  // refuses both).
  static bool _ownsSchema(
    Environment environment,
    ResourcePatternResolver resolver,
    String prefix,
  ) {
    final migration = MigrationSettings.fromEnvironment(environment, prefix);
    if (migration.enabled) {
      for (final configured in migration.locations) {
        var location = configured.replaceAll('{vendor}', 'sqlite');
        while (location.endsWith('/')) {
          location = location.substring(0, location.length - 1);
        }
        final separator = location.endsWith(':') ? '' : '/';
        if (resolver.getResources('$location$separator*.sql').isNotEmpty) {
          return true;
        }
      }
    }
    final init = SqlInitSettings.fromEnvironment(environment, prefix);
    if (init.mode == SqlInitMode.never) {
      return false;
    }
    for (final (configured, kind) in [
      (init.schemaLocations, 'schema'),
      (init.dataLocations, 'data'),
    ]) {
      final locations = configured.isEmpty
          ? [
              'optional:resources:$kind.sql',
              'optional:resources:$kind-${init.platform}.sql',
            ]
          : [
              for (final location in configured)
                location.replaceAll('@@platform@@', init.platform),
            ];
      for (final location in locations) {
        final path = location.startsWith('optional:')
            ? location.substring('optional:'.length)
            : location;
        if (resolver.getResources(path).isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }
}

// A database to replace: the prefix of its data source properties
// (`spring.datasource.`) and of its schema settings (`spring.`).
final class _Database {
  const _Database(this.prefix, this.settingsPrefix);

  final String prefix;
  final String settingsPrefix;
}
