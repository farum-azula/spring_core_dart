import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';

/// What the stores know of an aggregate's class: its table, its id and
/// version, and each stored property with its column.
///
/// Built once per class from the class's generated description
/// ([BeanIntrospection]: `@Table` makes the class described), with no
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
  }) : properties = List.unmodifiable(properties),
       _byName = {for (final p in properties) p.name: p};

  /// The description of the class, to create instances and reach
  /// properties.
  final BeanIntrospection<T> introspection;

  /// The table's name.
  final String tableName;

  /// The schema of the table; null for the connection's default.
  final String? schema;

  /// The stored properties ([Transient] ones left out), in declaration
  /// order.
  final List<PersistentProperty> properties;

  final Map<String, PersistentProperty> _byName;

  /// The entity's class.
  Type get type => introspection.beanType;

  /// The stored property named [name] (the Dart name), or null.
  PersistentProperty? property(String name) => _byName[name];

  /// The `@Id` property, or null when the class has none.
  PersistentProperty? get idProperty =>
      properties.where((p) => p.isId).firstOrNull;

  /// The `@Version` property, or null.
  PersistentProperty? get versionProperty =>
      properties.where((p) => p.isVersion).firstOrNull;

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
    required this.accessor,
    this.isId = false,
    this.isVersion = false,
    this.audit,
    this.mappedCollection,
    this.childEntity,
    this.referencedType,
  });

  /// The Dart property name.
  final String name;

  /// The column it is stored in (for a [MappedCollection], unused: the
  /// children have their own table).
  final String columnName;

  /// The property's type, as declared (with nullability); for an
  /// [AggregateReference], the reference type itself.
  final TypeInfo<Object?> type;

  /// Reads and writes the property on an instance.
  final BeanProperty<Object> accessor;

  /// Whether it is the `@Id`.
  final bool isId;

  /// Whether it is the `@Version`.
  final bool isVersion;

  /// What auditing sets on it, or null.
  final AuditKind? audit;

  /// The `@MappedCollection` settings, or null when the property is not a
  /// collection of children.
  final MappedCollection? mappedCollection;

  /// For a [MappedCollection], the children's entity (or for a single
  /// child entity property); null otherwise.
  final PersistentEntity<Object>? childEntity;

  /// For an [AggregateReference], the id's type; null otherwise.
  final TypeInfo<Object?>? referencedType;

  /// Whether it holds children of the aggregate.
  bool get isMappedCollection => mappedCollection != null;

  /// Whether it references another aggregate by id.
  bool get isAggregateReference => referencedType != null;

  /// Whether the property may hold null.
  bool get isNullable => type.nullable;

  /// The value of the property on [entity].
  Object? getValue(Object entity) => accessor.getValue(entity);

  /// Sets the property on [entity] to [value]; throws a [StateError] when
  /// the property is final (set it through the constructor instead).
  void setValue(Object entity, Object? value) =>
      accessor.setValue(entity, value);

  @override
  String toString() => 'PersistentProperty($name -> $columnName)';
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
