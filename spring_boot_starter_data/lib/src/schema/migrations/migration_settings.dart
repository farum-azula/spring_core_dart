import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';

/// The settings of the migration runner, `spring.sql.migration.*`: Flyway's
/// settings under our own name.
///
/// A data source's settings are bound from `sql.migration` below its prefix
/// by `DatabaseInitSettings.fromEnvironment`. A plain number of a duration is
/// in seconds.
///
/// Spring (Java): `org.springframework.boot.autoconfigure.flyway.
/// FlywayProperties` (`spring.flyway.*`), whose names these keep.
final class MigrationSettings {
  /// The settings; the defaults are Flyway's.
  const MigrationSettings({
    this.enabled = true,
    this.locations = const ['resources:db/migration'],
    this.table = 'schema_history',
    this.validateOnMigrate = true,
    this.outOfOrder = false,
    this.ignoreMigrationPatterns = const ['*:future'],
    this.baselineOnMigrate = false,
    this.baselineVersion = '1',
    this.baselineDescription = '<< Baseline >>',
    this.target = 'latest',
    this.placeholders = const {},
    this.placeholderReplacement = true,
    this.placeholderPrefix = r'${',
    this.placeholderSuffix = '}',
    this.group = false,
    this.connectRetries = 0,
    @DurationUnit(ChronoUnit.seconds)
    this.connectRetriesInterval = const Duration(seconds: 10),
    @DurationUnit(ChronoUnit.seconds)
    this.lockTimeout = const Duration(minutes: 1),
  });

  /// Whether migrations run: `lib/resources/db/migration/V<version>__<name>.sql`
  /// and `R__<name>.sql`; with no files nothing runs anyway (`enabled`).
  final bool enabled;

  /// Where the files are (`locations`); `{vendor}` is replaced by the
  /// dialect's name (`sqlite`, `postgresql`).
  final List<String> locations;

  /// The history table (`table`).
  final String table;

  /// Whether an applied migration whose checksum changed, or that is
  /// missing from the files, or a file older than the applied ones that
  /// was never applied, stops the start (`validate-on-migrate`).
  final bool validateOnMigrate;

  /// Whether a file with a version below the latest applied one still runs
  /// (`out-of-order`).
  final bool outOfOrder;

  /// Which problems of the history are ignored (`ignore-migration-
  /// patterns`): `type:status` with the type `versioned`,
  /// `repeatable` or `*` and the status `missing` (applied, not in the
  /// files, below the latest file), `future` (applied, newer than every
  /// file), `ignored` (a file below the latest applied, never applied) or
  /// `*`. The default `*:future` lets a database from a later version of
  /// the application start.
  final List<String> ignoreMigrationPatterns;

  /// Whether a database with tables and no history is taken as being at
  /// the [baselineVersion] instead of stopping the start
  /// (`baseline-on-migrate`).
  final bool baselineOnMigrate;

  /// The version of the baseline (`baseline-version`).
  final String baselineVersion;

  /// The description of the baseline (`baseline-description`).
  final String baselineDescription;

  /// The version to migrate to, or `latest` (`target`). Repeatable
  /// migrations run only for `latest`.
  final String target;

  /// The values of the placeholders of the scripts (`placeholders.<name>`).
  final Map<String, String> placeholders;

  /// Whether the scripts have their placeholders replaced
  /// (`placeholder-replacement`).
  final bool placeholderReplacement;

  /// What a placeholder starts with (`placeholder-prefix`).
  final String placeholderPrefix;

  /// What a placeholder ends with (`placeholder-suffix`).
  final String placeholderSuffix;

  /// Whether all the pending migrations run in one transaction instead of
  /// each in its own (`group`).
  final bool group;

  /// How many times a failed connection to the database is retried at
  /// startup (`connect-retries`).
  final int connectRetries;

  /// How long to wait between two of those attempts
  /// (`connect-retries-interval`).
  final Duration connectRetriesInterval;

  /// How long the runner waits for the migration lock another process
  /// holds before it gives up (`lock-timeout`, one minute).
  final Duration lockTimeout;

  /// Checks the settings that can be wrong; throws a [SchemaException].
  void validate() {
    if (table.trim().isEmpty) {
      throw SchemaException('spring.sql.migration.table must not be empty');
    }
    if (placeholderPrefix.isEmpty || placeholderSuffix.isEmpty) {
      throw SchemaException(
        'spring.sql.migration.placeholder-prefix and -suffix must not be '
        'empty',
      );
    }
    if (connectRetries < 0) {
      throw SchemaException(
        'spring.sql.migration.connect-retries must not be negative',
      );
    }
  }
}
