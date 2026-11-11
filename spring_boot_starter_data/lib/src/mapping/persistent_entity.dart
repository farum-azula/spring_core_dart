import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_introspection.dart';

/// What the stores know of an aggregate's class: its table, its id and
/// version, and each stored property with its column.
///
/// Built once per class from the class's generated description
/// ([EntityIntrospection]: `@Table` makes the class described), with no
/// reflection. Every store (in memory, SQL, PostgREST) reads and writes
/// entities through it.
///
/// Spring (Java):
/// `RelationalPersistentEntity`
/// (`org.springframework.data.relational.core.mapping`).
final class PersistentEntity<T extends Object> {
  /// The entity of [type] in [tableName]; the mapping builds one from a
  /// class's description.
  PersistentEntity({
    required this.introspection,
    required this.tableName,
    required List<PersistentProperty> properties,
    this.schema,
    List<PersistentUniqueConstraint> uniqueConstraints = const [],
  }) : properties = List.unmodifiable(properties),
       uniqueConstraints = List.unmodifiable(uniqueConstraints),
       _byName = {for (final p in properties) p.name: p};

  /// The description of the class, to create instances and reach
  /// properties.
  final EntityIntrospection<T> introspection;

  /// The table's name.
  final String tableName;

  /// The schema of the table; null for the connection's default.
  final String? schema;

  /// The stored properties ([Transient] ones left out), in declaration
  /// order.
  final List<PersistentProperty> properties;

  /// The unique constraints the class asks for: one for each [Unique]
  /// property and each [UniqueConstraint] of the class.
  final List<PersistentUniqueConstraint> uniqueConstraints;

  final Map<String, PersistentProperty> _byName;

  // The stored properties by their index in the introspection.
  late final List<PersistentProperty?> _byIndex = () {
    final all = List<PersistentProperty?>.filled(
      introspection.properties.length,
      null,
    );
    for (final p in properties) {
      all[p.index] = p;
    }
    return all;
  }();

  /// The entity's class.
  Type get type => introspection.type;

  /// The stored property named [name] (the Dart name), or null.
  PersistentProperty? property(String name) => _byName[name];

  /// The stored property at [index] of the introspection's properties, or
  /// null when that property is not stored (a [Transient] one).
  PersistentProperty? propertyAt(int index) => _byIndex[index];

  /// The `@Id` property, or null when the class has none.
  PersistentProperty? get idProperty =>
      properties.where((p) => p.isId).firstOrNull;

  /// The `@Version` property, or null.
  PersistentProperty? get versionProperty =>
      properties.where((p) => p.isVersion).firstOrNull;

  /// The properties that reference another aggregate (an
  /// `AggregateReference` or a [Reference]), in declaration order.
  Iterable<PersistentProperty> get references =>
      properties.where((p) => p.isReference);

  /// Whether the class has a `@Version` property.
  bool get hasVersion => versionProperty != null;

  /// The properties stored in the entity's own table: every stored property
  /// but the [MappedCollection]s.
  Iterable<PersistentProperty> get columns =>
      properties.where((p) => !p.isMappedCollection);

  @override
  String toString() => 'PersistentEntity<$T>($tableName)';
}

/// One stored property of a [PersistentEntity].
///
/// Spring (Java):
/// `RelationalPersistentProperty`
/// (`org.springframework.data.relational.core.mapping`).
final class PersistentProperty {
  /// The property [name] stored in [columnName].
  PersistentProperty({
    required this.name,
    required this.columnName,
    required this.type,
    required this.owner,
    required this.index,
    this.isId = false,
    this.isVersion = false,
    this.audit,
    this.mappedCollection,
    this.json,
    this.childEntity,
    this.referencedType,
    this.referencedEntityType,
    this.referencedEntity,
    this.onDelete = OnDeleteAction.noAction,
    this.hasExplicitOnDelete = false,
    this.isUnique = false,
    this.hasDefaultValue = false,
    this.defaultValue,
  });

  /// The Dart property name.
  final String name;

  /// The column it is stored in (for a [MappedCollection], unused: the
  /// children have their own table).
  final String columnName;

  /// The property's type, as declared (with nullability); for an
  /// [AggregateReference], the reference type itself.
  final TypeInfo<Object?> type;

  /// The description of the class the property belongs to.
  final EntityIntrospection<Object> owner;

  /// The property's index in the [owner]'s properties.
  final int index;

  /// Whether it is the `@Id`.
  final bool isId;

  /// Whether it is the `@Version`.
  final bool isVersion;

  /// What auditing sets on it, or null.
  final AuditKind? audit;

  /// The `@MappedCollection` settings, or null when the property is not a
  /// collection of children.
  final MappedCollection? mappedCollection;

  /// The `@Json` settings, or null when the property is not stored as
  /// JSON. Such a property's column holds JSON: `EntityConverter.write`
  /// gives its decoded JSON (maps, lists, numbers, strings) and
  /// `EntityConverter.read` takes that back.
  final Json? json;

  /// For a [MappedCollection], the children's entity (or for a single
  /// child entity property); null otherwise.
  final PersistentEntity<Object>? childEntity;

  /// For an [AggregateReference], the id's type; null otherwise.
  final TypeInfo<Object?>? referencedType;

  /// For a reference to another aggregate (an `AggregateReference` or a
  /// [Reference]), the referenced aggregate's class; null otherwise.
  final Type? referencedEntityType;

  /// For a reference, the referenced aggregate's entity (the table and the
  /// id column the foreign key points to). Resolved on first use, so that
  /// aggregates may reference each other; null for a property that is no
  /// reference.
  final PersistentEntity<Object> Function()? referencedEntity;

  /// What happens to this property's row when the aggregate it references
  /// is deleted: [OnDelete]'s action, [OnDeleteAction.noAction] without
  /// it.
  final OnDeleteAction onDelete;

  /// Whether the property carries an [OnDelete] annotation (and so the
  /// schema validation insists the database matches it).
  final bool hasExplicitOnDelete;

  /// Whether the property is marked [Unique].
  final bool isUnique;

  /// Whether the property has a default value: a constant initializer of
  /// its field (`bool inStock = true`), else a constant default of the
  /// constructor parameter of the same name (`this.inStock = true`). A
  /// generated schema writes it as the column's `DEFAULT`, and
  /// `@OnDelete(OnDeleteAction.setDefault)` sets it.
  final bool hasDefaultValue;

  /// The default value (see [hasDefaultValue]), as the property holds it.
  final Object? defaultValue;

  /// Whether it references another aggregate by id, in either form.
  bool get isReference => referencedEntityType != null;

  /// Whether it is stored as JSON in one column ([Json]).
  bool get isJson => json != null;

  /// Whether it holds children of the aggregate.
  bool get isMappedCollection => mappedCollection != null;

  /// Whether it references another aggregate by id.
  bool get isAggregateReference => referencedType != null;

  /// Whether the property may hold null.
  bool get isNullable => type.nullable;

  /// Whether the property has a setter.
  bool get isWritable => owner.properties[index].writable;

  /// The value of the property on [entity]; no other property is read.
  Object? getValue(Object entity) => owner.valueAt(entity, index);

  /// Sets the property on [entity] to [value]; throws a [StateError] when
  /// the property is final (set it through the constructor instead).
  void setValue(Object entity, Object? value) =>
      owner.write(entity, index, value);

  @override
  String toString() => 'PersistentProperty($name -> $columnName)';
}

/// A unique constraint of a [PersistentEntity]: no two rows hold the same
/// values in [properties] (a row with a null among them never conflicts).
///
/// Spring (Java): `jakarta.persistence.UniqueConstraint`.
final class PersistentUniqueConstraint {
  /// A constraint named [name] over [properties].
  PersistentUniqueConstraint({
    required this.name,
    required List<PersistentProperty> properties,
  }) : properties = List.unmodifiable(properties);

  /// The constraint's name in the database: the annotation's, else
  /// `uq_<table>_<columns>`.
  final String name;

  /// The properties it covers, in the order given.
  final List<PersistentProperty> properties;

  /// The names of the columns, in the order given.
  List<String> get columnNames => [for (final p in properties) p.columnName];

  @override
  String toString() => 'UNIQUE $name (${columnNames.join(', ')})';
}

/// What auditing sets on a property.
enum AuditKind {
  /// `@CreatedDate`: the time of the insert.
  createdDate,

  /// `@LastModifiedDate`: the time of each save.
  lastModifiedDate,

  /// `@CreatedBy`: the auditor at the insert.
  createdBy,

  /// `@LastModifiedBy`: the auditor at each save.
  lastModifiedBy,
}
