import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';

/// Finds the collection properties of an entity that a SQL database has
/// no column for: a `Map`, a `List` or a `Set` that is neither `@Json`,
/// nor a `@MappedCollection`, nor bytes (`List<int>`, `Uint8List`), nor a
/// collection the [dialect] keeps as it is (`SqlDialect.storesCollection`:
/// a list of simple values in an array column of PostgreSQL).
///
/// The SQL store asks it when a repository is created, and the schema
/// validation and creation when the application starts, so that such a
/// property is a problem with its fix before any statement runs, not an
/// error of the driver at the first insert. The build says the same of an
/// entity whose repository's store it knows to be the SQL store.
///
/// ```dart
/// // @Table() class Parcel { @Id() int? id; Map<String, Object?> meta; }
/// const CollectionColumns(SqliteDialect()).problemsOf(parcel);
/// // [Parcel.meta: a Map<String, Object?> property without @Json has no
/// //  column on a SQL store: add @Json() to keep it as JSON, or
/// //  @MappedCollection for rows of a child table]
/// ```
///
/// Spring (Java): none; Spring Data JDBC fails at the first statement
/// with the driver's error (or stores an array where the database has
/// them).
final class CollectionColumns {
  /// The check for the database of [dialect].
  const CollectionColumns(this.dialect);

  /// The database's dialect: it says which collections are columns.
  final SqlDialect dialect;

  /// The problem of the property [where] (`Entity.property`) of the
  /// collection type [type] (as written, without `?`): the words the build
  /// uses too.
  static String problem(String where, Object type) =>
      '$where: a $type property without @Json has no column on a SQL '
      'store: add @Json() to keep it as JSON, or @MappedCollection for '
      'rows of a child table';

  /// The problems of [entity] and of the children of its mapped
  /// collections, each naming the entity, the property and the fix; empty
  /// when every collection has its column or table.
  List<String> problemsOf(PersistentEntity<Object> entity) => [
    ..._problemsOf(entity),
    for (final property in entity.properties)
      if (property.childEntity case final child?) ..._problemsOf(child),
  ];

  Iterable<String> _problemsOf(PersistentEntity<Object> entity) sync* {
    for (final property in entity.columns) {
      final type = property.type;
      if (property.isJson ||
          property.isReference ||
          !(type is ListType<Object?> ||
              type is SetType<Object?> ||
              type is MapType<Object?, Object?>) ||
          dialect.columnType(type) != null ||
          dialect.storesCollection(type)) {
        continue;
      }
      yield problem(
        '${entity.introspection.className}.${property.name}',
        type.type,
      );
    }
  }
}
