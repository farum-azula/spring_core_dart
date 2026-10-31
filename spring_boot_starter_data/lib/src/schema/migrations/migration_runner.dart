import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_script.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_settings.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_source.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_version.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/schema_history.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';
import 'package:spring_boot_starter_data/src/schema/script_utils.dart';

/// What a run of the migrations did.
final class MigrationResult {
  /// A result of [applied] migrations, the database now at
  /// [currentVersion].
  const MigrationResult({
    this.applied = const [],
    this.currentVersion,
    this.executionTime = Duration.zero,
    this.baselined = false,
  });

  /// The migrations that ran, in order.
  final List<ResolvedMigration> applied;

  /// The latest versioned migration applied (or the baseline); null when
  /// there is none.
  final MigrationVersion? currentVersion;

  /// How long the run took.
  final Duration executionTime;

  /// Whether the run baselined an existing database.
  final bool baselined;

  /// How many migrations ran.
  int get count => applied.length;
}

/// Applies the migration files to a database, as Flyway does: the pending
/// ones in order, each in a transaction, recorded in a history table.
///
/// A run:
///
/// 1. finds the files (`V<version>__<description>.sql` run once in the
///    order of their versions, `R__<description>.sql` run again whenever
///    their checksum changed, after the versioned ones) and reads the
///    history table (created when missing);
/// 2. validates the history against the files (`validate-on-migrate`): an
///    applied migration whose file changed, or is gone, stops it, naming
///    the file; applied versions newer than every file are ignored by
///    default (a database from a later version of the application);
/// 3. applies each pending migration in its own transaction (or all in one
///    with `group`), after replacing the placeholders; a failed migration
///    is rolled back, not recorded, and stops the start naming the file,
///    the number and the line of the statement and the database's
///    message;
/// 4. holds the migration lock for the whole run, so that several
///    instances starting together migrate once: on SQLite the write lock
///    (`BEGIN IMMEDIATE`) at each step, retried until
///    `spring.sql.migration.lock-timeout`; on a database with a
///    [SqlDialect.migrationLock] (PostgreSQL's advisory lock) that
///    statement, for the whole run. The other runners wait, then find
///    nothing to do.
///
/// There is no clean command: a runner never drops anything.
///
/// Log lines (logger `spring.sql.migration`) name versions, descriptions
/// and counts, never values.
///
/// Spring (Java): Flyway (`org.flywaydb.core.Flyway.migrate`) as
/// `FlywayAutoConfiguration` runs it; Flyway itself is not used.
class MigrationRunner {
  /// A runner for [dataSource] with [settings], finding its files with
  /// [source] (the classpath, through [resourceLoader], by default).
  /// [sleep] waits between two attempts to take a lock, for tests.
  MigrationRunner(
    this.dataSource,
    this.settings, {
    MigrationSource? source,
    ResourceLoader? resourceLoader,
    Future<void> Function(Duration)? sleep,
  }) : source =
           source ??
           ResourceMigrationSource(
             settings.locations,
             resourceLoader: resourceLoader,
           ),
       _sleep = sleep ?? Future<void>.delayed,
       _history = SchemaHistory(dataSource.dialect, settings.table);

  static const _log = SpringLog('spring.sql.migration');

  /// The database to migrate.
  final DataSource dataSource;

  /// The settings.
  final MigrationSettings settings;

  /// Where the files come from.
  final MigrationSource source;

  final Future<void> Function(Duration) _sleep;
  final SchemaHistory _history;

  SqlDialect get _dialect => dataSource.dialect;

  /// Whether migrations are enabled and there is at least one file: what
  /// competes with `schema=create` and the SQL scripts for the ownership
  /// of the schema.
  Future<bool> hasMigrations() async {
    if (!settings.enabled) {
      return false;
    }
    return (await source.findMigrations(_dialect.name)).isNotEmpty;
  }

  /// Runs the pending migrations; returns what it did.
  ///
  /// Does nothing when the migrations are disabled or there are no files.
  /// Throws a [MigrationException] when the history does not match the
  /// files or a migration fails, and the database stays at the version
  /// before the failed migration.
  Future<MigrationResult> migrate() async {
    settings.validate();
    if (!settings.enabled) {
      _log.debug('Migrations are disabled (spring.sql.migration.enabled)');
      return const MigrationResult();
    }
    final files = await source.findMigrations(_dialect.name);
    if (files.isEmpty) {
      _log.debug(
        'No migration files in ${settings.locations.join(', ')}: nothing '
        'to migrate',
      );
      return const MigrationResult();
    }
    final resolved = _resolve(files);
    final target = _target();
    final patterns = _patterns();
    final watch = Stopwatch()..start();
    final applied = <ResolvedMigration>[];
    var baselined = false;
    MigrationVersion? current;
    final connection = await dataSource.getConnection();
    var locked = false;
    try {
      if (_dialect.migrationLock case final statement?) {
        await _guard('take the migration lock', () async {
          await connection.query(statement);
        });
        locked = true;
      }
      while (true) {
        final round = await _round(connection, resolved, target, patterns);
        baselined = baselined || round.baselined;
        current = round.current;
        if (round.applied.isEmpty) {
          break;
        }
        applied.addAll(round.applied);
      }
    } finally {
      if (locked && _dialect.migrationUnlock != null) {
        try {
          await connection.query(_dialect.migrationUnlock!);
        } on Object catch (error) {
          _log.warning('Could not release the migration lock: $error');
        }
      }
      await dataSource.releaseConnection(connection);
    }
    watch.stop();
    if (applied.isEmpty) {
      _log.info('Schema is up to date. No migration necessary.');
    } else {
      final version = current == null ? '' : ', now at version v$current';
      _log.info(
        'Successfully applied ${applied.length} '
        'migration${applied.length == 1 ? '' : 's'} to schema$version '
        '(execution time ${_format(watch.elapsed)})',
      );
    }
    return MigrationResult(
      applied: applied,
      currentVersion: current,
      executionTime: watch.elapsed,
      baselined: baselined,
    );
  }

  // ------------------------------------------------------------ one round

  // Takes the lock, reads the history, applies the next pending migration
  // (all of them with `group`) and commits. Reads the history again in the
  // next round, so what another runner applied meanwhile is not applied
  // twice.
  Future<_Round> _round(
    JdbcConnection connection,
    List<ResolvedMigration> resolved,
    MigrationVersion? target,
    List<_IgnorePattern> patterns,
  ) async {
    await _begin(connection);
    try {
      final tables = await _dialect.listTables(connection);
      await _history.create(connection);
      var rows = await _history.read(connection);
      var baselined = false;
      if (rows.isEmpty) {
        final others = [
          for (final table in tables ?? const <String>[])
            if (table.toLowerCase() != settings.table.toLowerCase()) table,
        ];
        if (others.isNotEmpty) {
          if (!settings.baselineOnMigrate) {
            throw MigrationException(
              'Found a database with ${others.length} table(s) and no '
              'schema history table (${settings.table}): set '
              'spring.sql.migration.baseline-on-migrate=true to take it as '
              'version ${settings.baselineVersion} and migrate from there',
            );
          }
          final baseline = AppliedMigration(
            rank: 1,
            version: MigrationVersion.parse(settings.baselineVersion),
            description: settings.baselineDescription,
            type: AppliedMigration.baselineType,
            script: settings.baselineDescription,
            checksum: null,
            installedBy: _user,
            installedOn: DateTime.now().toUtc(),
            executionTime: 0,
            success: true,
          );
          await _history.insert(connection, baseline);
          rows = [baseline];
          baselined = true;
          _log.info(
            'Successfully baselined schema with version: '
            '${settings.baselineVersion}',
          );
        }
      }
      final pending = _plan(resolved, rows, target, patterns);
      final batch = settings.group ? pending : pending.take(1).toList();
      var rank = rows.isEmpty
          ? 0
          : rows.map((r) => r.rank).reduce((a, b) => a > b ? a : b);
      var current = _latestVersion(rows);
      for (final migration in batch) {
        rank++;
        await _apply(connection, migration, rank);
        final version = migration.version;
        if (version != null && (current == null || version > current)) {
          current = version;
        }
      }
      await connection.commit();
      return _Round(batch, current, baselined);
    } on Object {
      await _rollbackQuietly(connection);
      rethrow;
    }
  }

  Future<void> _begin(JdbcConnection connection) async {
    final deadline = DateTime.now().add(settings.lockTimeout);
    final lockForWrite = _dialect.lockStrategy == LockStrategy.databaseLock;
    while (true) {
      try {
        await connection.begin(lockForWrite: lockForWrite);
        return;
      } on SqlError catch (error) {
        final translated = _dialect.translate(error);
        if (translated is CannotAcquireLockException &&
            DateTime.now().isBefore(deadline)) {
          await _sleep(const Duration(milliseconds: 20));
          continue;
        }
        throw MigrationException(
          'Could not take the migration lock of ${dataSource.name}: '
          '${error.message}',
          cause: error,
        );
      }
    }
  }

  Future<void> _rollbackQuietly(JdbcConnection connection) async {
    try {
      await connection.rollback();
    } on Object {
      // The connection is gone: nothing was committed.
    }
  }

  // ----------------------------------------------------------------- plan

  // Validates the history against the files and returns the migrations to
  // apply, in order.
  List<ResolvedMigration> _plan(
    List<ResolvedMigration> resolved,
    List<AppliedMigration> rows,
    MigrationVersion? target,
    List<_IgnorePattern> patterns,
  ) {
    for (final row in rows) {
      if (!row.success) {
        throw MigrationException(
          'The history table ${settings.table} records a failed migration '
          '${row.script}${row.version == null ? '' : ' (version '
                    '${row.version})'}: remove the half-applied changes and '
          'its row by hand',
          script: row.script,
        );
      }
    }
    final versioned = {
      for (final m in resolved)
        if (!m.isRepeatable) m.version!: m,
    };
    final repeatables = [
      for (final m in resolved)
        if (m.isRepeatable) m,
    ]..sort((a, b) => a.description.compareTo(b.description));
    final appliedVersioned = [
      for (final r in rows)
        if (r.version != null && r.type == AppliedMigration.sqlType) r,
    ];
    final appliedRepeatable = [
      for (final r in rows)
        if (r.version == null && r.type == AppliedMigration.sqlType) r,
    ];
    final baseline = rows
        .where((r) => r.isBaseline)
        .map((r) => r.version)
        .whereType<MigrationVersion>()
        .fold<MigrationVersion?>(null, _max);
    final latestApplied = _latestVersion(rows);
    final latestResolved = versioned.keys.fold<MigrationVersion?>(null, _max);

    if (settings.validateOnMigrate) {
      for (final row in appliedVersioned) {
        final migration = versioned[row.version];
        if (migration == null) {
          final future =
              latestResolved != null && row.version! > latestResolved;
          if (!_ignored(patterns, repeatable: false, future: future)) {
            final hint = future
                ? ' (it is newer than every file: the database is from a '
                      'later version; add *:future to '
                      'ignore-migration-patterns)'
                : '';
            throw MigrationException(
              'Validate failed: the migration ${row.script} (version '
              '${row.version}) was applied to the database but is missing '
              'from the migration files in ${settings.locations.join(', ')}'
              '$hint',
              script: row.script,
            );
          }
        } else if (row.checksum != null && row.checksum != migration.checksum) {
          throw MigrationException(
            'Validate failed: the checksum of ${migration.script} '
            '(${migration.file.description}) changed after it was applied: '
            'applied ${row.checksum}, now ${migration.checksum}; undo the '
            'change and put it in a new migration',
            script: migration.script,
          );
        }
      }
      final repeatableNames = {for (final m in repeatables) m.description};
      for (final row in appliedRepeatable) {
        if (!repeatableNames.contains(row.description) &&
            !_ignored(patterns, repeatable: true, future: false)) {
          throw MigrationException(
            'Validate failed: the repeatable migration ${row.script} was '
            'applied to the database but is missing from the migration '
            'files in ${settings.locations.join(', ')}',
            script: row.script,
          );
        }
      }
    }

    final pending = <ResolvedMigration>[];
    final appliedVersions = {for (final r in appliedVersioned) r.version!};
    final ordered = versioned.values.toList()
      ..sort((a, b) => a.version!.compareTo(b.version!));
    for (final migration in ordered) {
      final version = migration.version!;
      if (appliedVersions.contains(version)) {
        continue;
      }
      if (baseline != null && version <= baseline) {
        continue;
      }
      if (target != null && version > target) {
        continue;
      }
      if (latestApplied != null &&
          version < latestApplied &&
          !settings.outOfOrder) {
        if (settings.validateOnMigrate &&
            !_ignoredStatus(patterns, _Status.ignored)) {
          throw MigrationException(
            'Validate failed: the migration ${migration.script} '
            '(${migration.file.description}) was never applied but is '
            'older than the latest applied version $latestApplied: '
            'renumber it above $latestApplied, or set spring.sql.migration.'
            ' out-of-order=true to run it now',
            script: migration.script,
          );
        }
        _log.warning(
          'Skipping the migration ${migration.script}: older than the '
          'latest applied version $latestApplied (out-of-order is off)',
        );
        continue;
      }
      pending.add(migration);
    }
    if (target == null) {
      for (final migration in repeatables) {
        final last = appliedRepeatable
            .where((r) => r.description == migration.description)
            .lastOrNull;
        if (last == null || last.checksum != migration.checksum) {
          pending.add(migration);
        }
      }
    }
    return pending;
  }

  static MigrationVersion? _max(MigrationVersion? a, MigrationVersion b) =>
      a == null || b > a ? b : a;

  static MigrationVersion? _latestVersion(List<AppliedMigration> rows) => rows
      .map((r) => r.version)
      .whereType<MigrationVersion>()
      .fold<MigrationVersion?>(null, _max);

  // -------------------------------------------------------------- applying

  Future<void> _apply(
    JdbcConnection connection,
    ResolvedMigration migration,
    int rank,
  ) async {
    _log.info('Migrating schema to ${migration.label}');
    final watch = Stopwatch()..start();
    final text = _replacePlaceholders(migration);
    try {
      await ScriptUtils.executeSqlScript(
        connection,
        text,
        description: migration.file.description,
      );
    } on ScriptException catch (error) {
      final reason = error.cause is SqlError
          ? (error.cause! as SqlError).message
          : error.message;
      final where = error.statementNumber == null
          ? ' (${migration.file.description})'
          : ': statement #${error.statementNumber} at line ${error.line} of '
                '${migration.file.description}';
      throw MigrationException(
        'Migration ${migration.script} failed$where: $reason',
        script: migration.script,
        cause: error,
      );
    }
    watch.stop();
    await _guard('record ${migration.script} in ${settings.table}', () async {
      await _history.insert(
        connection,
        AppliedMigration(
          rank: rank,
          version: migration.version,
          description: migration.description,
          type: AppliedMigration.sqlType,
          script: migration.script,
          checksum: migration.checksum,
          installedBy: _user,
          installedOn: DateTime.now().toUtc(),
          executionTime: watch.elapsedMilliseconds,
          success: true,
        ),
      );
    });
  }

  String _replacePlaceholders(ResolvedMigration migration) {
    final content = migration.file.content;
    if (!settings.placeholderReplacement) {
      return content;
    }
    final pattern = RegExp(
      '${RegExp.escape(settings.placeholderPrefix)}'
      r'([A-Za-z0-9_.\-]+)'
      '${RegExp.escape(settings.placeholderSuffix)}',
    );
    return content.replaceAllMapped(pattern, (match) {
      final name = match.group(1)!;
      final value = settings.placeholders[name];
      if (value == null) {
        throw MigrationException(
          'Migration ${migration.script} (${migration.file.description}) '
          'uses the placeholder ${match.group(0)} that is not defined: set '
          'spring.sql.migration.placeholders.$name, or turn the '
          'replacement off with placeholder-replacement=false',
          script: migration.script,
        );
      }
      return value;
    });
  }

  // --------------------------------------------------------------- helpers

  String get _user => dataSource.settings.username ?? dataSource.name;

  List<ResolvedMigration> _resolve(List<MigrationFile> files) {
    final resolved = <ResolvedMigration>[];
    final seenVersion = <MigrationVersion, String>{};
    final seenRepeatable = <String, String>{};
    final sorted = [...files]..sort((a, b) => a.name.compareTo(b.name));
    for (final file in sorted) {
      final migration = ResolvedMigration.parse(file);
      final version = migration.version;
      final clash = version == null
          ? seenRepeatable[migration.description]
          : seenVersion[version];
      if (clash != null) {
        throw MigrationException(
          'Found two migrations with the same '
          '${version == null ? 'description' : 'version $version'}: '
          '$clash and ${file.name}',
          script: file.name,
        );
      }
      if (version == null) {
        seenRepeatable[migration.description] = file.name;
      } else {
        seenVersion[version] = file.name;
      }
      resolved.add(migration);
    }
    return resolved;
  }

  MigrationVersion? _target() {
    final text = settings.target.trim();
    if (text.isEmpty || text.toLowerCase() == 'latest') {
      return null;
    }
    try {
      return MigrationVersion.parse(text);
    } on MigrationException {
      throw MigrationException(
        'spring.sql.migration.target must be latest or a version, not '
        "'$text'",
      );
    }
  }

  List<_IgnorePattern> _patterns() => [
    for (final pattern in settings.ignoreMigrationPatterns)
      _IgnorePattern.parse(pattern),
  ];

  bool _ignored(
    List<_IgnorePattern> patterns, {
    required bool repeatable,
    required bool future,
  }) {
    final status = future ? _Status.future : _Status.missing;
    return patterns.any(
      (p) =>
          p.matchesStatus(status) &&
          (p.type == null ||
              p.type == (repeatable ? 'repeatable' : 'versioned')),
    );
  }

  bool _ignoredStatus(List<_IgnorePattern> patterns, _Status status) =>
      patterns.any((p) => p.matchesStatus(status) && p.type != 'repeatable');

  Future<void> _guard(String action, Future<void> Function() body) async {
    try {
      await body();
    } on SqlError catch (error) {
      throw MigrationException(
        'Could not $action: ${error.message}',
        cause: error,
      );
    }
  }

  static String _format(Duration time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final millis = (time.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '${two(time.inMinutes)}:${two(time.inSeconds % 60)}.${millis}s';
  }
}

enum _Status { missing, future, ignored }

final class _IgnorePattern {
  _IgnorePattern(this.type, this.status);

  factory _IgnorePattern.parse(String text) {
    final parts = text.split(':');
    if (parts.length != 2) {
      throw MigrationException(
        'Invalid spring.sql.migration.ignore-migration-patterns entry '
        "'$text': use <type>:<status>, such as *:future",
      );
    }
    final type = parts[0].trim().toLowerCase();
    final status = parts[1].trim().toLowerCase();
    if (!const {'*', 'versioned', 'repeatable'}.contains(type) ||
        !const {'*', 'missing', 'future', 'ignored'}.contains(status)) {
      throw MigrationException(
        'Invalid spring.sql.migration.ignore-migration-patterns entry '
        "'$text': the type is versioned, repeatable or *, the status "
        'missing, future, ignored or *',
      );
    }
    return _IgnorePattern(type == '*' ? null : type, status);
  }

  final String? type;
  final String status;

  bool matchesStatus(_Status wanted) => status == '*' || status == wanted.name;
}

final class _Round {
  _Round(this.applied, this.current, this.baselined);

  final List<ResolvedMigration> applied;
  final MigrationVersion? current;
  final bool baselined;
}
