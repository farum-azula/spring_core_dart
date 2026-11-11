import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/jdbc/collection_columns.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';
import 'package:spring_boot_starter_data/src/schema/schema_model.dart';
import 'package:spring_boot_starter_data/src/schema/schema_support.dart';

/// What the validation of a schema found.
final class SchemaValidationReport {
  /// A report of [problems] (they stop the start) and [warnings].
  const SchemaValidationReport(this.problems, this.warnings);

  /// What does not fit: a missing table or column, a type that does not
  /// fit; each names the entity, the property, the table, the column, what
  /// was expected and what was found.
  final List<String> problems;

  /// What is allowed but suspect: a non-null property on a nullable column
  /// without a default.
  final List<String> warnings;

  /// Whether there is no problem.
  bool get isValid => problems.isEmpty;
}

/// Checks that the tables and columns the entities map exist in the
/// database with types that fit (`spring.data.jdbc.schema=validate`, the
/// default): the table of each entity and its columns, and for each
/// mapped collection the children table with its reverse column and key
/// column. Extra tables and columns are fine. A property that is not
/// nullable on a nullable column without a default is only a warning.
///
/// It checks the keys too, through the dialect's `describeForeignKeys` and
/// `describeUniqueKeys` (a dialect that cannot describe them is skipped,
/// with a line in the debug log):
///
/// - a reference (`AggregateReference`, `@Reference`) with an explicit
///   `@OnDelete` needs a foreign key to the referenced table with that
///   action: a missing key or another action is an error, as the database
///   would behave differently;
/// - a reference without `@OnDelete` and no foreign key in the database
///   is a warning only (its integrity is not enforced; a key with another
///   action is a warning too);
/// - every `@Unique` and `@UniqueConstraint` needs a unique constraint or
///   unique index over exactly those columns (SQLite reports a `UNIQUE`
///   constraint as an `sqlite_autoindex_*` index, which counts); a missing
///   one is an error.
///
/// One error lists every problem, not the first.
///
/// Spring (Java): Hibernate's `hbm2ddl.auto=validate` (Spring Data JDBC
/// has no equivalent).
class SchemaValidator {
  /// A validator of [dataSource]; [naming] writes the names of reverse and
  /// key columns.
  SchemaValidator(
    this.dataSource, {
    this.naming = const NamingStrategy(),
  });

  static const _log = SpringLog('spring.data.jdbc.schema');

  /// The database to check.
  final DataSource dataSource;

  /// The naming strategy of the mapping.
  final NamingStrategy naming;

  /// Checks [entities] against the database; the problems and warnings are
  /// in the report (the warnings are logged too).
  ///
  /// Throws a [SchemaException] when the dialect cannot describe tables.
  Future<SchemaValidationReport> validate(
    Iterable<PersistentEntity<Object>> entities,
  ) async {
    final model = SchemaModel.of(entities, naming: naming);
    final dialect = dataSource.dialect;
    final problems = [
      ...model.problems,
      for (final entity in entities)
        ...CollectionColumns(dialect).problemsOf(entity),
    ];
    final warnings = <String>[];
    await withConnection(dataSource, (connection) async {
      for (final table in model.tables) {
        final found = await dialect.describeTable(
          connection,
          table.name,
          table.schema,
        );
        if (found == null) {
          throw SchemaException(
            'The ${dialect.name} dialect cannot describe tables, so the '
            'schema cannot be validated: set spring.data.jdbc.schema=none',
          );
        }
        _check(dialect, table, found, problems, warnings);
        if (found.isNotEmpty) {
          await _checkKeys(connection, dialect, table, problems, warnings);
        }
      }
    });
    warnings.forEach(_log.warning);
    return SchemaValidationReport(problems, warnings);
  }

  /// Like [validate], but throws a [SchemaValidationException] listing
  /// every problem.
  Future<SchemaValidationReport> validateOrThrow(
    Iterable<PersistentEntity<Object>> entities,
  ) async {
    final report = await validate(entities);
    if (!report.isValid) {
      throw SchemaValidationException(report.problems);
    }
    return report;
  }

  Future<void> _checkKeys(
    JdbcConnection connection,
    SqlDialect dialect,
    TableSpec table,
    List<String> problems,
    List<String> warnings,
  ) async {
    final qualified = table.schema == null
        ? table.name
        : '${table.schema}.${table.name}';
    final references = [
      for (final column in table.columns)
        if (column.references case final fk? when fk.isReference) (column, fk),
    ];
    if (references.isNotEmpty) {
      final keys = await dialect.describeForeignKeys(
        connection,
        table.name,
        table.schema,
      );
      if (keys == null) {
        _log.debug(
          'The ${dialect.name} dialect cannot describe foreign keys: the '
          'references of table "$qualified" are not checked',
        );
      } else {
        for (final (column, fk) in references) {
          _checkForeignKey(qualified, column, fk, keys, problems, warnings);
        }
      }
    }
    if (table.uniques.isNotEmpty) {
      final keys = await dialect.describeUniqueKeys(
        connection,
        table.name,
        table.schema,
      );
      if (keys == null) {
        _log.debug(
          'The ${dialect.name} dialect cannot describe unique constraints: '
          'the ones of table "$qualified" are not checked',
        );
      } else {
        for (final unique in table.uniques) {
          final wanted = {for (final c in unique.columns) c.toLowerCase()};
          final found = keys.any(
            (key) =>
                key.columns.length == wanted.length &&
                {for (final c in key.columns) c.toLowerCase()}.containsAll(
                  wanted,
                ),
          );
          if (!found) {
            problems.add(
              'Missing unique constraint "${unique.name}" in table '
              '"$qualified" for ${unique.description}: expected the '
              'columns ${unique.columns.map((c) => '"$c"').join(', ')} to '
              'be unique, found no UNIQUE constraint or unique index over '
              'them (a save the entity expects to fail would succeed)',
            );
          }
        }
      }
    }
  }

  void _checkForeignKey(
    String qualified,
    ColumnSpec column,
    ForeignKeySpec expected,
    List<ForeignKeyInfo> keys,
    List<String> problems,
    List<String> warnings,
  ) {
    final parent = expected.schema == null
        ? expected.table
        : '${expected.schema}.${expected.table}';
    final want = _actionName(expected.onDelete);
    final found = keys
        .where((k) => k.column.toLowerCase() == column.name.toLowerCase())
        .firstOrNull;
    // Without `@OnDelete` the reference is not picky about the action.
    void report(String message) =>
        (expected.explicit ? problems : warnings).add(message);
    if (found == null) {
      report(
        expected.explicit
            ? 'Missing foreign key on column "${column.name}" in table '
                  '"$qualified" for ${column.property}: expected '
                  'REFERENCES "$parent" ON DELETE $want, found no foreign '
                  'key'
            : 'Column "${column.name}" in table "$qualified" has no '
                  'foreign key to "$parent", but ${column.property} '
                  'references it: its integrity is not enforced',
      );
      return;
    }
    if (found.parentTable.toLowerCase() != expected.table.toLowerCase()) {
      report(
        'Column "${column.name}" in table "$qualified" references '
        '"${found.parentTable}", but ${column.property} references '
        '"$parent"',
      );
      return;
    }
    final actual = found.onDelete;
    final same =
        actual == null ||
        actual == expected.onDelete ||
        (!expected.explicit &&
            const {
              OnDeleteAction.noAction,
              OnDeleteAction.restrict,
            }.containsAll({actual, expected.onDelete}));
    if (!same) {
      report(
        'The foreign key on column "${column.name}" in table "$qualified" '
        'for ${column.property} has the wrong action: expected ON DELETE '
        '$want, found ${_actionName(actual)}',
      );
    }
  }

  static String _actionName(OnDeleteAction action) => switch (action) {
    OnDeleteAction.noAction => 'NO ACTION',
    OnDeleteAction.restrict => 'RESTRICT',
    OnDeleteAction.cascade => 'CASCADE',
    OnDeleteAction.setNull => 'SET NULL',
    OnDeleteAction.setDefault => 'SET DEFAULT',
  };

  void _check(
    SqlDialect dialect,
    TableSpec table,
    List<ColumnInfo> found,
    List<String> problems,
    List<String> warnings,
  ) {
    final qualified = table.schema == null
        ? table.name
        : '${table.schema}.${table.name}';
    if (found.isEmpty) {
      problems.add(
        'Missing table "$qualified" for ${table.owner}: expected a table '
        'named "$qualified" with the columns '
        '${table.columns.map((c) => '"${c.name}"').join(', ')}',
      );
      return;
    }
    final byName = {for (final c in found) c.name.toLowerCase(): c};
    for (final column in table.columns) {
      final actual = byName[column.name.toLowerCase()];
      final json = column.json == null
          ? null
          : dialect.jsonStorage(column.json!);
      final expected =
          json?.columnType ??
          dialect.columnType(column.type) ??
          '${column.type}';
      if (actual == null) {
        problems.add(
          'Missing column "${column.name}" in table "$qualified" for '
          '${column.property}: expected $expected, found no such column '
          '(the table has ${found.map((c) => '"${c.name}"').join(', ')})',
        );
        continue;
      }
      final fits = json == null
          ? dialect.columnType(column.type) == null ||
                dialect.columnFits(actual.type, column.type)
          : json.fits(actual.type);
      if (!fits) {
        problems.add(
          'Column "${column.name}" in table "$qualified" for '
          '${column.property} has the wrong type: expected $expected '
          '(${column.type}), found '
          '${actual.type.isEmpty ? 'no declared type' : actual.type}',
        );
      }
      if (!column.nullable &&
          !actual.notNull &&
          !actual.primaryKey &&
          actual.defaultValue == null) {
        warnings.add(
          'Column "${column.name}" in table "$qualified" is nullable and '
          'has no default, but ${column.property} is not nullable',
        );
      }
    }
  }
}
