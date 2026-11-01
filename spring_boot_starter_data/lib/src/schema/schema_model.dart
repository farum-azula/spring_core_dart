import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';

/// A column the entities ask of the database.
final class ColumnSpec {
  /// A column [name] for [property], of the Dart [type].
  ColumnSpec({
    required this.name,
    required this.property,
    required this.type,
    required this.nullable,
    this.primaryKey = false,
    this.identity = false,
    this.references,
    this.hasDefaultValue = false,
    this.defaultValue,
  });

  /// The column name.
  final String name;

  /// Where it comes from, for messages: `Book.title`, or
  /// `OrderLine.items (reverse column)`.
  final String property;

  /// The Dart type the column holds.
  final TypeInfo<Object?> type;

  /// Whether the column accepts null; a key never does.
  bool nullable;

  /// Whether the column is the primary key.
  final bool primaryKey;

  /// Whether the database generates the key (an `int?` id).
  final bool identity;

  /// The column it references (the reverse column of a child table).
  final ForeignKeySpec? references;

  /// Whether the column gets a `DEFAULT`: the property's default value.
  final bool hasDefaultValue;

  /// The column's default, as the property holds it.
  final Object? defaultValue;
}

/// A foreign key: the column of a child table to the key of its parent's
/// table, or the column of an aggregate that references another one.
final class ForeignKeySpec {
  /// A reference to [column] of [table].
  const ForeignKeySpec(
    this.table,
    this.schema,
    this.column, {
    this.onDelete = OnDeleteAction.cascade,
    this.isReference = false,
    this.explicit = false,
  });

  /// The parent table.
  final String table;

  /// The schema of the parent table, null for the default.
  final String? schema;

  /// The key column of the parent table.
  final String column;

  /// What happens to a row when its parent is deleted: cascade for the
  /// children of an aggregate, the property's [OnDelete] for a reference.
  final OnDeleteAction onDelete;

  /// Whether it is a reference to another aggregate (an
  /// `AggregateReference` or a [Reference]), not the link of a child table
  /// to its root. Only references are validated.
  final bool isReference;

  /// Whether the property says its action with [OnDelete]: the validation
  /// then insists the database has it.
  final bool explicit;
}

/// A unique constraint a table asks for.
final class UniqueSpec {
  /// A constraint [name] over [columns], written [description] in messages.
  const UniqueSpec(this.name, this.columns, this.description);

  /// The constraint's name.
  final String name;

  /// The column names, in order.
  final List<String> columns;

  /// Where it comes from: `Book.isbn`, or `@UniqueConstraint(author,
  /// title) of Book`.
  final String description;
}

/// An index a table asks for, on the column of a reference (deletes of the
/// referenced row and the checks of the foreign key look for rows by it).
final class IndexSpec {
  /// An index [name] over [columns].
  const IndexSpec(this.name, this.columns);

  /// The index's name.
  final String name;

  /// The column names, in order.
  final List<String> columns;
}

/// A table the entities ask of the database: a root's table or the table
/// of a mapped collection's children.
final class TableSpec {
  /// A table [name] for [owner].
  TableSpec(
    this.name,
    this.schema,
    this.owner,
    this.columns, {
    this.uniques = const [],
    this.indexes = const [],
  });

  /// The table name.
  final String name;

  /// The schema of the table, null for the default.
  final String? schema;

  /// The entity (`Book`) or the mapped collection (`OrderLine.items`) the
  /// table is for, for messages.
  final String owner;

  /// The columns, in the order of the properties.
  final List<ColumnSpec> columns;

  /// The unique constraints.
  final List<UniqueSpec> uniques;

  /// The indexes.
  final List<IndexSpec> indexes;

  /// The tables this one references: they must exist first.
  Iterable<ForeignKeySpec> get parents =>
      columns.map((c) => c.references).whereType<ForeignKeySpec>();
}

/// The tables the entities ask of the database, in dependency order (a
/// table after the ones it references): what the validator checks and the
/// creator writes.
///
/// Spring (Java): `org.springframework.data.relational.core.mapping.
/// schema.SchemaDiff`'s model, kept to the little the two need.
final class SchemaModel {
  SchemaModel._(this.tables, this.problems, this.hasCycle);

  /// Builds the model of [entities] (the roots; the children come with
  /// them), with the names of [naming] for the reverse and key columns.
  factory SchemaModel.of(
    Iterable<PersistentEntity<Object>> entities, {
    NamingStrategy naming = const NamingStrategy(),
  }) {
    final builder = _Builder(naming);
    entities.forEach(builder.addRoot);
    final tables = builder.ordered();
    return SchemaModel._(tables, builder.problems, builder.hasCycle);
  }

  /// The tables, parents first.
  final List<TableSpec> tables;

  /// What cannot be mapped to a table, such as a mapped collection under
  /// an entity without an `@Id`.
  final List<String> problems;

  /// Whether tables reference each other in a cycle (two tables, or more;
  /// a table referencing itself is no cycle here): one of them has a
  /// foreign key to a table that comes later in [tables].
  final bool hasCycle;

  /// The position of the table [name] (in [schema]) in [tables], or -1.
  int indexOf(String name, String? schema) => tables.indexWhere(
    (t) =>
        t.name.toLowerCase() == name.toLowerCase() &&
        (t.schema?.toLowerCase() ?? '') == (schema?.toLowerCase() ?? ''),
  );

  /// Whether another table than itself has a foreign key to [table].
  bool isReferenced(TableSpec table) => tables.any(
    (other) =>
        !identical(other, table) &&
        other.parents.any(
          (parent) =>
              parent.table.toLowerCase() == table.name.toLowerCase() &&
              (parent.schema?.toLowerCase() ?? '') ==
                  (table.schema?.toLowerCase() ?? ''),
        ),
  );
}

class _Builder {
  _Builder(this.naming);

  final NamingStrategy naming;
  final tables = <String, TableSpec>{};
  final problems = <String>[];
  bool hasCycle = false;

  static String _key(String? schema, String name) =>
      '${schema?.toLowerCase() ?? ''}.${name.toLowerCase()}';

  void addRoot(PersistentEntity<Object> entity) {
    final name = entity.introspection.className;
    _add(entity, name, name, null);
  }

  // Adds the table of [entity] (merging with one of the same name), then
  // the tables of its mapped collections.
  void _add(
    PersistentEntity<Object> entity,
    String owner,
    String entityName,
    List<ColumnSpec>? extra,
  ) {
    final columns = <ColumnSpec>[];
    final targets = <PersistentEntity<Object>>[];
    for (final p in entity.columns) {
      final type = p.referencedType ?? p.type;
      final id = p.isId;
      ForeignKeySpec? references;
      if (p.referencedEntity case final resolve?) {
        final target = resolve();
        targets.add(target);
        references = ForeignKeySpec(
          target.tableName,
          target.schema,
          target.idProperty!.columnName,
          onDelete: p.onDelete,
          isReference: true,
          explicit: p.hasExplicitOnDelete,
        );
      }
      columns.add(
        ColumnSpec(
          name: p.columnName,
          property: '$entityName.${p.name}',
          type: type,
          nullable: !id && p.isNullable,
          primaryKey: id,
          identity: id && type.type == int && p.isNullable,
          references: references,
          hasDefaultValue: !id && p.hasDefaultValue,
          defaultValue: p.defaultValue,
        ),
      );
    }
    columns.addAll(extra ?? const []);
    final key = _key(entity.schema, entity.tableName);
    final existing = tables[key];
    if (existing == null) {
      tables[key] = TableSpec(
        entity.tableName,
        entity.schema,
        owner,
        columns,
        uniques: _uniques(entity, entityName),
        indexes: _indexes(entity, columns),
      );
    } else {
      _merge(existing, columns);
    }
    for (final p in entity.properties.where((p) => p.isMappedCollection)) {
      _addChildren(entity, entityName, p);
    }
    // The aggregates referenced are tables of the schema too: the foreign
    // keys need them.
    for (final target in targets) {
      if (!tables.containsKey(_key(target.schema, target.tableName))) {
        addRoot(target);
      }
    }
  }

  List<UniqueSpec> _uniques(PersistentEntity<Object> entity, String name) => [
    for (final constraint in entity.uniqueConstraints)
      UniqueSpec(
        constraint.name,
        constraint.columnNames,
        constraint.properties.length == 1 &&
                constraint.properties.single.isUnique
            ? '$name.${constraint.properties.single.name} (@Unique)'
            : '@UniqueConstraint('
                  '${constraint.properties.map((p) => p.name).join(', ')}) '
                  'of $name',
      ),
  ];

  // An index on each reference's column, but where the primary key or a
  // unique constraint of that column alone is one already.
  List<IndexSpec> _indexes(
    PersistentEntity<Object> entity,
    List<ColumnSpec> columns,
  ) => [
    for (final column in columns)
      if (column.references?.isReference ?? false)
        if (!column.primaryKey &&
            !entity.uniqueConstraints.any(
              (u) =>
                  u.properties.length == 1 &&
                  u.properties.single.columnName == column.name,
            ))
          IndexSpec('idx_${entity.tableName}_${column.name}', [column.name]),
  ];

  // Two parents with the same child class share its table (as in Spring
  // Data JDBC): its columns are the union, and the ones not in both accept
  // null.
  void _merge(TableSpec table, List<ColumnSpec> columns) {
    final byName = {for (final c in table.columns) c.name.toLowerCase(): c};
    final seen = <String>{};
    for (final column in columns) {
      final name = column.name.toLowerCase();
      seen.add(name);
      final present = byName[name];
      if (present == null) {
        column.nullable = true;
        table.columns.add(column);
      } else {
        present.nullable = present.nullable || column.nullable;
      }
    }
    for (final column in table.columns) {
      if (!seen.contains(column.name.toLowerCase()) && !column.primaryKey) {
        column.nullable = true;
      }
    }
  }

  void _addChildren(
    PersistentEntity<Object> parent,
    String parentName,
    PersistentProperty property,
  ) {
    final child = property.childEntity!;
    final where = '$parentName.${property.name}';
    final id = parent.idProperty;
    if (id == null) {
      problems.add(
        '$where: a @MappedCollection needs an @Id on $parentName, which '
        "the children's reverse column references",
      );
      return;
    }
    final mapped = property.mappedCollection;
    final type = property.type;
    final extra = <ColumnSpec>[
      ColumnSpec(
        name: naming.reverseColumnName(parent.tableName, mapped),
        property: '$where (reverse column)',
        type: id.referencedType ?? id.type,
        nullable: false,
        references: ForeignKeySpec(
          parent.tableName,
          parent.schema,
          id.columnName,
        ),
      ),
      if (type is ListType<Object?> || type is MapType<Object?, Object?>)
        ColumnSpec(
          name: naming.keyColumnName(parent.tableName, mapped),
          property: '$where (key column)',
          type: type is MapType<Object?, Object?>
              ? type.key
              : const ClassType<int>(),
          nullable: false,
        ),
    ];
    _add(child, where, child.introspection.className, extra);
  }

  // Parents first: a table after the tables it references.
  List<TableSpec> ordered() {
    final result = <TableSpec>[];
    final done = <String>{};
    void visit(TableSpec table, Set<String> path) {
      final key = _key(table.schema, table.name);
      if (done.contains(key)) {
        return;
      }
      if (!path.add(key)) {
        hasCycle = true;
        return;
      }
      for (final parent in table.parents) {
        final spec = tables[_key(parent.schema, parent.table)];
        // A table referencing itself is no cycle (it is created first).
        if (spec != null && !identical(spec, table)) {
          visit(spec, path);
        }
      }
      done.add(key);
      result.add(table);
    }

    for (final table in tables.values) {
      visit(table, {});
    }
    return result;
  }
}
