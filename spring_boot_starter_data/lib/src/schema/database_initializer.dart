import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/properties/data_properties.dart'
    show NamedDataJdbcProperties;
import 'package:spring_boot_starter_data/src/properties_binding.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_runner.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_settings.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_source.dart';
import 'package:spring_boot_starter_data/src/schema/schema_creator.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';
import 'package:spring_boot_starter_data/src/schema/schema_support.dart';
import 'package:spring_boot_starter_data/src/schema/schema_validator.dart';
import 'package:spring_boot_starter_data/src/schema/script_database_initializer.dart';

/// What `spring.data.jdbc.schema` asks of the entities' schema.
///
/// Spring (Java): Hibernate's `spring.jpa.hibernate.ddl-auto` (without
/// `update`, which never drops or renames and lets the schema drift).
enum SchemaMode {
  /// Does nothing.
  none('none'),

  /// Checks that the entities' tables and columns exist and fit; the
  /// default.
  validate('validate'),

  /// Creates the missing tables from the entities.
  create('create'),

  /// Creates the tables and drops them when the context closes.
  createDrop('create-drop');

  SchemaMode(this.value);

  /// The value of the property.
  final String value;

  /// Whether the mode writes the schema.
  bool get writes => this == create || this == createDrop;
}

/// Everything that sets up the schema of one data source, as plain
/// settings: the SQL scripts, the migrations and the schema mode.
final class DatabaseInitSettings {
  /// The settings; the defaults are those of the properties.
  const DatabaseInitSettings({
    this.sqlInit = const SqlInitSettings(),
    this.migration = const MigrationSettings(),
    this.schema = SchemaMode.validate,
  });

  /// Reads the settings of the data source whose keys start with [prefix]:
  /// `spring.` for the default data source (`spring.sql.init.mode`,
  /// `spring.sql.migration.enabled`, `spring.data.jdbc.schema`) and
  /// `spring.datasources.<name>.` for a named one
  /// (`spring.datasources.main.sql.init.mode`).
  factory DatabaseInitSettings.fromEnvironment(
    Environment environment, [
    String prefix = 'spring.',
  ]) {
    // The prefix ends with a dot, the names bound do not.
    T bound<T extends Object>(String key, T fallback) => bindSettings<T>(
      environment,
      '$prefix$key',
      fallback: fallback,
      onInvalid: refuseSetting,
    );
    return DatabaseInitSettings(
      sqlInit: bound('sql.init', const SqlInitSettings()),
      migration: bound('sql.migration', const MigrationSettings()),
      schema: bound(
        'data.jdbc',
        const NamedDataJdbcProperties(),
      ).schema,
    );
  }

  /// `spring.sql.init.*`.
  final SqlInitSettings sqlInit;

  /// `spring.sql.migration.*`.
  final MigrationSettings migration;

  /// `spring.data.jdbc.schema`.
  final SchemaMode schema;
}

/// Sets up the schema of a database at startup, in one call and in the
/// right order, whether or not the rest of the application runs (it is
/// what a `--spring.data.migrate-only` start would call):
///
/// 1. the ownership checks: `create` and `create-drop` refuse to run with
///    migrations that have files or with `spring.sql.init` scripts to run,
///    and migrations refuse to run with those scripts: one owner of the
///    schema, as in Boot;
/// 2. the connection, retried `connect-retries` times, `connect-retries-
///    interval` apart;
/// 3. the migrations ([MigrationRunner]) or, when there are none, the SQL
///    scripts ([ScriptDatabaseInitializer]);
/// 4. the creation of the tables, for `create` and `create-drop`
///    ([SchemaCreator]);
/// 5. the validation of the entities against the schema, for `validate`
///    ([SchemaValidator]).
///
/// [initialize] is idempotent: a second call does nothing (and the
/// migrations would find nothing to do anyway). [close] drops the tables
/// the `create-drop` mode created.
///
/// Spring (Java): `DataSourceScriptDatabaseInitializer`,
/// `FlywayMigrationInitializer` and Hibernate's schema management, run by
/// the application context in that order.
class DatabaseInitializer {
  /// An initializer of [dataSource] for [entities] (the roots; the
  /// children come with them), with [settings]; the scripts and the
  /// migration files are found through [resourceLoader], or take
  /// [migrationSource] instead. [sleep] waits between connection attempts,
  /// for tests.
  DatabaseInitializer(
    this.dataSource, {
    this.settings = const DatabaseInitSettings(),
    this.entities = const [],
    this.resourceLoader,
    this.migrationSource,
    this.naming = const NamingStrategy(),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  /// An initializer whose settings are read from [environment] with
  /// [prefix] (see [DatabaseInitSettings.fromEnvironment]).
  factory DatabaseInitializer.fromEnvironment(
    DataSource dataSource,
    Environment environment, {
    String prefix = 'spring.',
    Iterable<PersistentEntity<Object>> entities = const [],
    ResourceLoader? resourceLoader,
    MigrationSource? migrationSource,
    NamingStrategy naming = const NamingStrategy(),
    Future<void> Function(Duration)? sleep,
  }) => DatabaseInitializer(
    dataSource,
    settings: DatabaseInitSettings.fromEnvironment(environment, prefix),
    entities: entities,
    resourceLoader: resourceLoader,
    migrationSource: migrationSource,
    naming: naming,
    sleep: sleep,
  );

  static const _log = SpringLog('spring.data.jdbc.DatabaseInitializer');

  /// The database to set up.
  final DataSource dataSource;

  /// What to do.
  final DatabaseInitSettings settings;

  /// The entities whose schema is created or validated.
  final Iterable<PersistentEntity<Object>> entities;

  /// Finds the scripts and migration files; the classpath by default.
  final ResourceLoader? resourceLoader;

  /// Where the migration files come from, instead of the locations.
  final MigrationSource? migrationSource;

  /// The naming strategy of the mapping.
  final NamingStrategy naming;

  final Future<void> Function(Duration) _sleep;

  Future<void>? _initializing;
  var _initialized = false;
  var _created = false;

  /// What the last [initialize] migrated; null before it ran or when it
  /// had no migrations.
  MigrationResult? migrationResult;

  /// Sets up the schema (see the class); a second call does nothing.
  ///
  /// Throws a [SchemaException] (a [MigrationException],
  /// [ScriptException] or [SchemaValidationException]) when something
  /// cannot be done, which stops the start.
  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }
    return _initializing ??= _run().then(
      (_) {
        _initialized = true;
        _initializing = null;
      },
      onError: (Object error, StackTrace stack) {
        _initializing = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  /// Drops the tables of the `create-drop` mode, if [initialize] created
  /// them; does nothing in the other modes. The wiring calls it when the
  /// context closes.
  Future<void> close() async {
    if (settings.schema == SchemaMode.createDrop && _created) {
      _created = false;
      await SchemaCreator(dataSource, naming: naming).drop(entities);
    }
  }

  MigrationRunner _runner() => MigrationRunner(
    dataSource,
    settings.migration,
    source: migrationSource,
    resourceLoader: resourceLoader,
    sleep: _sleep,
  );

  Future<void> _run() async {
    final scripts = ScriptDatabaseInitializer(
      dataSource,
      settings.sqlInit,
      resourceLoader: resourceLoader,
    );
    final runner = _runner();
    await _checkOwnership(scripts, runner);
    await _connect();
    if (await runner.hasMigrations()) {
      migrationResult = await runner.migrate();
    } else {
      await scripts.initialize();
    }
    final list = entities.toList();
    if (settings.schema.writes) {
      await SchemaCreator(dataSource, naming: naming).create(list);
      _created = true;
    }
    if (settings.schema == SchemaMode.validate && list.isNotEmpty) {
      final report = await SchemaValidator(
        dataSource,
        naming: naming,
      ).validateOrThrow(list);
      _log.debug(
        'Schema of ${dataSource.name} validated against ${list.length} '
        'entities (${report.warnings.length} warning(s))',
      );
    }
  }

  // One owner of the schema.
  Future<void> _checkOwnership(
    ScriptDatabaseInitializer scripts,
    MigrationRunner runner,
  ) async {
    final migrations = await runner.hasMigrations();
    final hasScripts = scripts.hasScriptsToRun;
    if (migrations && hasScripts) {
      final found = [
        ...scripts.schemaScripts(),
        ...scripts.dataScripts(),
      ].map((r) => r.description).join(', ');
      throw SchemaException(
        'The schema of ${dataSource.name} has two owners: the migrations '
        '(spring.sql.migration, ${settings.migration.locations.join(', ')}) '
        'and the SQL scripts (spring.sql.init: '
        '$found). '
        'Use one: set spring.sql.init.mode=never, or '
        'spring.sql.migration.enabled=false',
      );
    }
    if (settings.schema.writes && (migrations || hasScripts)) {
      final other = migrations
          ? 'the migrations (spring.sql.migration, '
                '${settings.migration.locations.join(', ')})'
          : 'the SQL scripts (spring.sql.init)';
      throw SchemaException(
        'spring.data.jdbc.schema=${settings.schema.value} would create the '
        'tables of ${dataSource.name}, which $other already own: use one '
        'owner of the schema. Set spring.data.jdbc.schema=validate or '
        'none, or remove ${migrations ? 'the migration files' : 'the scripts'}',
      );
    }
  }

  Future<void> _connect() async {
    final retries = settings.migration.connectRetries;
    final interval = settings.migration.connectRetriesInterval;
    for (var attempt = 0; ; attempt++) {
      try {
        final connection = await dataSource.getConnection();
        await dataSource.releaseConnection(connection);
        return;
      } on DataAccessResourceFailureException catch (error) {
        if (attempt >= retries) {
          rethrow;
        }
        _log.warning(
          'Could not connect to ${dataSource.settings.safeUrl} '
          '(attempt ${attempt + 1} of ${retries + 1}): ${error.message}; '
          'retrying in ${interval.inSeconds} s',
        );
        await _sleep(interval);
      }
    }
  }
}
