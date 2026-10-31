import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_version.dart';

/// A row of the history table: a migration that was applied (or the
/// baseline).
///
/// Spring (Java): Flyway's `AppliedMigration`.
final class AppliedMigration {
  /// A row of the history.
  const AppliedMigration({
    required this.rank,
    required this.version,
    required this.description,
    required this.type,
    required this.script,
    required this.checksum,
    required this.installedBy,
    required this.installedOn,
    required this.executionTime,
    required this.success,
  });

  /// The position in the order of application, from 1.
  final int rank;

  /// The version; null for a repeatable migration.
  final MigrationVersion? version;

  /// The description.
  final String description;

  /// `SQL` for a migration file, `BASELINE` for the baseline.
  final String type;

  /// The file name.
  final String script;

  /// The checksum of the file when it ran; null for a baseline.
  final int? checksum;

  /// The user that applied it.
  final String installedBy;

  /// When it was applied.
  final DateTime? installedOn;

  /// How long it took, in milliseconds.
  final int executionTime;

  /// Whether it succeeded.
  final bool success;

  /// Whether this row is the baseline.
  bool get isBaseline => type == baselineType;

  /// The type of a migration file's row.
  static const sqlType = 'SQL';

  /// The type of the baseline row.
  static const baselineType = 'BASELINE';
}

/// The history table of the migrations (`schema_history`): what ran, in
/// which order, with which checksum. It is created through the dialect.
///
/// Spring (Java): Flyway's `SchemaHistory`.
class SchemaHistory {
  /// The history table [table] of the database with [dialect].
  SchemaHistory(this.dialect, this.table);

  /// The dialect that writes the table.
  final SqlDialect dialect;

  /// The name of the table.
  final String table;

  static const _int = ClassType<int>();
  static const _text = ClassType<String>();
  static const _date = ClassType<DateTime>();
  static const _bool = ClassType<bool>();

  String get _quoted => dialect.quote(table);

  /// The `CREATE TABLE IF NOT EXISTS` statement of the table.
  String get createStatement {
    String type(TypeInfo<Object?> info) =>
        dialect.columnType(info) ??
        (throw StateError('${dialect.name} has no column type for $info'));
    String column(
      String name,
      TypeInfo<Object?> info, {
      bool nullable = false,
    }) => '${dialect.quote(name)} ${type(info)}${nullable ? '' : ' NOT NULL'}';
    return 'CREATE TABLE IF NOT EXISTS $_quoted (\n'
        '  ${column('installed_rank', _int)} PRIMARY KEY,\n'
        '  ${column('version', _text, nullable: true)},\n'
        '  ${column('description', _text)},\n'
        '  ${column('type', _text)},\n'
        '  ${column('script', _text)},\n'
        '  ${column('checksum', _int, nullable: true)},\n'
        '  ${column('installed_by', _text)},\n'
        '  ${column('installed_on', _date)},\n'
        '  ${column('execution_time', _int)},\n'
        '  ${column('success', _bool)}\n'
        ')';
  }

  /// Creates the table when it is not there yet.
  Future<void> create(JdbcConnection connection) =>
      connection.execute(createStatement);

  /// The rows of the history, in the order they were applied.
  Future<List<AppliedMigration>> read(JdbcConnection connection) async {
    final result = await connection.query(
      'SELECT installed_rank, version, description, type, script, checksum, '
      'installed_by, installed_on, execution_time, success FROM $_quoted '
      'ORDER BY installed_rank',
    );
    return [
      for (final row in result.rows)
        AppliedMigration(
          rank: row['installed_rank']! as int,
          version: row['version'] == null
              ? null
              : MigrationVersion.parse(row['version']! as String),
          description: row['description']! as String,
          type: row['type']! as String,
          script: row['script']! as String,
          checksum: row['checksum'] as int?,
          installedBy: row['installed_by']! as String,
          installedOn: dialect.fromDatabase(
            row['installed_on'],
            const ClassType<DateTime>(nullable: true),
          ) as DateTime?,
          executionTime: row['execution_time']! as int,
          success:
              dialect.fromDatabase(row['success'], _bool) as bool? ?? false,
        ),
    ];
  }

  /// Adds [row] to the history.
  Future<void> insert(JdbcConnection connection, AppliedMigration row) async {
    await connection.update(
      'INSERT INTO $_quoted (installed_rank, version, description, type, '
      'script, checksum, installed_by, installed_on, execution_time, '
      'success) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        row.rank,
        row.version?.toString(),
        row.description,
        row.type,
        row.script,
        row.checksum,
        row.installedBy,
        dialect.toDatabase((row.installedOn ?? DateTime.now()).toUtc()),
        row.executionTime,
        dialect.toDatabase(row.success),
      ],
    );
  }
}
