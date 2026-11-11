import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/collection_columns.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';
import 'package:spring_boot_starter_data/src/schema/schema_model.dart';
import 'package:spring_boot_starter_data/src/schema/schema_support.dart';

/// Writes the tables of the entities (`spring.data.jdbc.schema=create` or
/// `create-drop`), for tests, prototypes and on-device caches.
///
/// For each root entity a table (an `int?` id as the dialect's identity
/// column, any other id as its column type and `PRIMARY KEY`; `NOT NULL`
/// for a property that is not nullable; the `@Version`), and for each
/// mapped collection a child table in dependency order (the reverse
/// column, `NOT NULL`, referencing the root and `ON DELETE CASCADE`; the
/// key column of a `List` or `Map`; the child's columns). A reference to
/// another aggregate (`AggregateReference`, `@Reference`) is a foreign key
/// (`REFERENCES "authors" ("id")`, with the `ON DELETE` of its `@OnDelete`,
/// none for `noAction`) with an index on the column; `@Unique` and
/// `@UniqueConstraint` are `UNIQUE` constraints. Each table comes after the
/// tables it references. Tables that reference each other form a cycle: a
/// dialect that accepts a key to a table not created yet
/// ([SqlDialect.supportsForwardForeignKeys], SQLite) gets it in
/// `CREATE TABLE`, another gets it afterwards in an `ALTER TABLE`
/// ([SqlDialect.addForeignKeyStatement]). `create` uses
/// `CREATE TABLE IF NOT EXISTS`, so tables already there are left alone;
/// `drop` removes the tables in the reverse order, what `create-drop` does
/// when the context closes (with a cycle, the dialect's
/// [SqlDialect.beforeDropStatements] first, so the order does not matter).
/// There is no `update`: it never drops or renames, and the schema drifts.
///
/// Spring (Java): Hibernate's `hbm2ddl.auto=create` / `create-drop`;
/// Spring Data JDBC's `RelationalPersistentEntity` schema writer
/// (`LiquibaseChangeSetWriter`'s model).
class SchemaCreator {
  /// A creator for [dataSource]; [naming] writes the names of reverse and
  /// key columns.
  SchemaCreator(
    this.dataSource, {
    this.naming = const NamingStrategy(),
  });

  static const _log = SpringLog('spring.data.jdbc.schema');

  /// The database to write to.
  final DataSource dataSource;

  /// The naming strategy of the mapping.
  final NamingStrategy naming;

  SqlDialect get _dialect => dataSource.dialect;

  /// The `CREATE TABLE` statements for [entities], parents first, then the
  /// `ALTER TABLE` statements of the foreign keys the dialect cannot write
  /// in `CREATE TABLE` (a key to a table that comes later), then the
  /// `CREATE INDEX` statements.
  ///
  /// Throws a [SchemaException] naming each property the dialect has no
  /// column type for.
  List<String> createStatements(Iterable<PersistentEntity<Object>> entities) {
    final model = SchemaModel.of(entities, naming: naming);
    final problems = [
      ...model.problems,
      for (final entity in entities)
        ...CollectionColumns(_dialect).problemsOf(entity),
    ];
    final statements = <String>[];
    final later = <String>[];
    for (final (index, table) in model.tables.indexed) {
      statements.add(_create(model, index, table, problems, later));
    }
    statements.addAll(later);
    for (final table in model.tables) {
      for (final index in table.indexes) {
        statements.add(
          'CREATE INDEX IF NOT EXISTS ${_dialect.quote(index.name)} ON '
          '${_dialect.table(table.name, table.schema)} '
          '(${index.columns.map(_dialect.quote).join(', ')})',
        );
      }
    }
    if (problems.isNotEmpty) {
      final list = problems.map((p) => '  - $p').join('\n');
      throw SchemaException('Cannot create the schema:\n$list');
    }
    return statements;
  }

  /// The `DROP TABLE IF EXISTS` statements for [entities], children
  /// first; when tables reference each other in a cycle, the dialect's
  /// [SqlDialect.beforeDropStatements] come first.
  List<String> dropStatements(Iterable<PersistentEntity<Object>> entities) {
    final model = SchemaModel.of(entities, naming: naming);
    return [
      if (model.hasCycle) ..._dialect.beforeDropStatements,
      for (final table in model.tables.reversed)
        _dialect.dropTableStatement(
          table.name,
          schema: table.schema,
          referenced: model.isReferenced(table),
        ),
    ];
  }

  /// Creates the tables of [entities] that do not exist yet, in one
  /// transaction.
  Future<void> create(Iterable<PersistentEntity<Object>> entities) async {
    final statements = createStatements(entities);
    if (statements.isEmpty) {
      return;
    }
    await _run(statements);
    final count = SchemaModel.of(entities, naming: naming).tables.length;
    _log.info('Created $count table(s) from the entities');
  }

  /// Drops the tables of [entities], children first, in one transaction.
  Future<void> drop(Iterable<PersistentEntity<Object>> entities) async {
    final statements = dropStatements(entities);
    if (statements.isEmpty) {
      return;
    }
    await _run(statements);
    final count = SchemaModel.of(entities, naming: naming).tables.length;
    _log.info('Dropped $count table(s) of the entities');
  }

  Future<void> _run(List<String> statements) => withConnection(
    dataSource,
    (connection) async {
      await connection.begin();
      try {
        for (final statement in statements) {
          await connection.execute(statement);
        }
        await connection.commit();
      } on SqlError catch (error) {
        try {
          await connection.rollback();
        } on Object {
          // The connection is gone.
        }
        throw SchemaException(
          'Cannot run the schema statements: ${error.message}',
          cause: error,
        );
      }
    },
  );

  String _create(
    SchemaModel model,
    int position,
    TableSpec table,
    List<String> problems,
    List<String> later,
  ) {
    final lines = <String>[];
    for (final column in table.columns) {
      final name = _dialect.quote(column.name);
      if (column.identity) {
        lines.add('$name ${_dialect.identityColumn(column.type)}');
        continue;
      }
      final json = column.json == null
          ? null
          : _dialect.jsonStorage(column.json!);
      final type = json?.columnType ?? _dialect.columnType(column.type);
      if (type == null) {
        // A collection without @Json is reported already, with its fix.
        if (!problems.any((p) => p.startsWith('${column.property}: '))) {
          problems.add(
            '${column.property}: ${_dialect.name} has no column type for '
            '${column.type}',
          );
        }
        continue;
      }
      final out = StringBuffer('$name $type');
      if (column.primaryKey) {
        out.write(' NOT NULL PRIMARY KEY');
      } else if (!column.nullable) {
        out.write(' NOT NULL');
      }
      if (column.hasDefaultValue) {
        if (_dialect.defaultLiteral(column.defaultValue) case final value?) {
          out.write(' DEFAULT $value');
        }
      }
      if (json?.check(name) case final check?) {
        out.write(' CHECK ($check)');
      }
      if (column.references case final parent?) {
        // A key to a table created later, in a dialect that cannot have it
        // yet, is added afterwards.
        final forward =
            !_dialect.supportsForwardForeignKeys &&
            model.indexOf(parent.table, parent.schema) > position;
        if (forward) {
          later.add(
            _dialect.addForeignKeyStatement(
              name: 'fk_${table.name}_${column.name}',
              table: table.name,
              schema: table.schema,
              column: column.name,
              parentTable: parent.table,
              parentSchema: parent.schema,
              parentColumn: parent.column,
              onDelete: parent.onDelete,
            ),
          );
        } else {
          out.write(
            ' REFERENCES ${_dialect.table(parent.table, parent.schema)} '
            '(${_dialect.quote(parent.column)})'
            '${_dialect.onDeleteClause(parent.onDelete)}',
          );
        }
      }
      lines.add(out.toString());
    }
    for (final unique in table.uniques) {
      lines.add(
        'CONSTRAINT ${_dialect.quote(unique.name)} UNIQUE '
        '(${unique.columns.map(_dialect.quote).join(', ')})',
      );
    }
    return 'CREATE TABLE IF NOT EXISTS '
        '${_dialect.table(table.name, table.schema)} (\n'
        '  ${lines.join(',\n  ')}\n)';
  }
}
