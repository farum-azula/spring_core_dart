import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_introspection.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';

/// The mapping of a class to a table is wrong: two `@Id`, a `@Version` of an
/// unusable type, a child class that is not described, and so on.
///
/// The message names the class and the property. It is thrown the first
/// time the class is mapped, never in the middle of a save.
///
/// Spring (Java): `org.springframework.data.mapping.MappingException`.
class MappingException extends InvalidDataAccessApiUsageException {
  /// A wrong mapping described by [message].
  MappingException(super.message, {super.cause});
}

/// Builds the [PersistentEntity] of each class from its generated
/// [EntityIntrospection], and keeps it: a class is mapped once.
///
/// The rules, applied to every property the class's description lists (the
/// non-static, non-private fields of the class and its superclasses):
///
/// * A [Transient] property is not stored. So is a property that is neither
///   writable nor a parameter of the constructor (a `final` field the
///   constructor does not take, such as `final int x = 5`): nothing could
///   load it back.
/// * The column is [Column]'s value, else the [NamingStrategy]'s.
/// * [Id] marks the id; [Version] the version (an `int` or `DateTime`, only
///   on a root); [CreatedDate], [LastModifiedDate] (a `DateTime`),
///   [CreatedBy] and [LastModifiedBy] are the audit properties.
/// * An `AggregateReference<X, ID>` is stored as its id: its
///   `referencedType` is the type of `ID`. A property marked [Reference]
///   (`@Reference(Author) int authorId`) is stored as it is. Both reference
///   another aggregate: `X` (or the annotation's class) must be described
///   and marked [Table] with an `@Id`, whose type must be the type of the
///   id (nullability aside); [OnDelete] says what the database does when
///   the referenced aggregate is deleted (`setNull` needs a nullable
///   property). A property whose type is itself an entity, without
///   [MappedCollection], is refused with a hint to use one of the two.
/// * [Unique] marks a property whose values are unique, and
///   [UniqueConstraint] on the class lists the properties of a composite
///   constraint; both become the entity's `uniqueConstraints`.
/// * A [MappedCollection] on a `List<C>`, `Set<C>` or `Map<K, C>` (or on a
///   single `C`) holds children: `C` must be described and marked [Table];
///   its entity is built the same way, as a child (it takes no [Version]).
///
/// The descriptions are the [introspections] the context is given: those
/// of the `EntityIntrospections` beans the generated `*.spring.dart`
/// modules register, or any a test writes by hand.
///
/// Spring (Java):
/// `org.springframework.data.relational.core.mapping.RelationalMappingContext`.
class RelationalMappingContext {
  /// A context over [introspections] (the first of a class counts when
  /// several describe it) naming tables and columns with [namingStrategy].
  RelationalMappingContext({
    required Iterable<EntityIntrospection<Object>> introspections,
    this.namingStrategy = const NamingStrategy(),
  }) {
    for (final introspection in introspections) {
      _described.putIfAbsent(introspection.type, () => introspection);
    }
  }

  /// How tables and columns are named when the annotations do not say.
  final NamingStrategy namingStrategy;

  final _described = <Type, EntityIntrospection<Object>>{};

  final _roots = <Type, PersistentEntity<Object>>{};
  final _children = <Type, PersistentEntity<Object>>{};

  /// Every class described: the entities, the classes stored inside them
  /// and the classes a `@Query` returns.
  Iterable<EntityIntrospection<Object>> get introspections => _described.values;

  /// The description of the class [type] (an entity or not), or null when
  /// it is not described.
  EntityIntrospection<Object>? introspectionOf(Type type) => _described[type];

  /// The entity of the root class [T]; throws a [MappingException] when [T]
  /// is not described or its mapping is wrong.
  PersistentEntity<T> getRequiredPersistentEntity<T extends Object>() {
    final cached = _roots[T];
    if (cached is PersistentEntity<T>) {
      return cached;
    }
    final introspection = _described[T];
    if (introspection == null) {
      throw MappingException(_notDescribed(T));
    }
    final entity = fromIntrospection<T>(
      introspection as EntityIntrospection<T>,
    );
    _roots[T] = entity;
    return entity;
  }

  /// The entity of the root class [type], or null when it is not described.
  ///
  /// The entity is a `PersistentEntity<Object>` (its [PersistentEntity.type]
  /// is [type]); prefer [getRequiredPersistentEntity] when the type is known
  /// statically.
  PersistentEntity<Object>? getPersistentEntity(Type type) {
    final cached = _roots[type];
    if (cached != null) {
      return cached;
    }
    final introspection = _described[type];
    if (introspection == null) {
      return null;
    }
    return _roots[type] = fromIntrospection<Object>(introspection);
  }

  /// The entity of the root class [type]; throws a [MappingException] when
  /// it is not described.
  PersistentEntity<Object> getRequiredPersistentEntityOfType(Type type) =>
      getPersistentEntity(type) ??
      (throw MappingException(_notDescribed(type)));

  /// Builds (without caching) the entity of a root class from
  /// [introspection]; for tests that describe a class by hand. Children
  /// are looked up among the context's [introspections].
  PersistentEntity<T> fromIntrospection<T extends Object>(
    EntityIntrospection<T> introspection,
  ) => _build<T>(introspection, isChild: false, path: const []);

  /// The column of a mapped collection's children table holding the id of
  /// [root]: [m]'s `idColumn`, else the [namingStrategy]'s.
  String reverseColumnName(
    PersistentEntity<Object> root,
    MappedCollection? m,
  ) => namingStrategy.reverseColumnName(root.tableName, m);

  /// The column of a mapped collection's children table holding a child's
  /// position or key: [m]'s `keyColumn`, else the [namingStrategy]'s.
  String keyColumnName(PersistentEntity<Object> root, MappedCollection? m) =>
      namingStrategy.keyColumnName(root.tableName, m);

  String _notDescribed(Type type) =>
      '$type is not described: mark it @Table (and register its '
      'module) so it can be stored';

  PersistentEntity<T> _build<T extends Object>(
    EntityIntrospection<T> introspection, {
    required bool isChild,
    required List<Type> path,
  }) {
    final className = introspection.className;
    final type = introspection.type;
    if (path.contains(type)) {
      throw MappingException(
        '$className: ${[...path, type].join(' -> ')} contains itself as '
        'a child; an aggregate is a tree',
      );
    }
    final properties = <PersistentProperty>[];
    for (final (index, described) in introspection.properties.indexed) {
      if (described.annotation<Transient>() != null) {
        continue;
      }
      if (!described.writable && !described.parameter) {
        continue;
      }
      properties.add(
        _property(introspection, index, isChild, [...path, type]),
      );
    }
    _checkEntity(className, properties, isChild: isChild);
    final table = introspection.annotations.whereType<Table>().firstOrNull;
    final tableName = namingStrategy.tableName(className, table);
    return PersistentEntity<T>(
      introspection: introspection,
      tableName: tableName,
      schema: table?.schema,
      properties: properties,
      uniqueConstraints: _uniqueConstraints(
        introspection,
        className,
        tableName,
        properties,
      ),
    );
  }

  // The constraints of the [Unique] properties and of the class's
  // [UniqueConstraint]s, checked.
  List<PersistentUniqueConstraint> _uniqueConstraints(
    EntityIntrospection<Object> introspection,
    String className,
    String tableName,
    List<PersistentProperty> properties,
  ) {
    final constraints = <PersistentUniqueConstraint>[
      for (final p in properties)
        if (p.isUnique)
          PersistentUniqueConstraint(
            name: 'uq_${tableName}_${p.columnName}',
            properties: [p],
          ),
    ];
    final stored = {
      for (final p in properties)
        if (!p.isMappedCollection) p.name: p,
    };
    for (final annotation
        in introspection.annotations.whereType<UniqueConstraint>()) {
      if (annotation.properties.isEmpty) {
        throw MappingException(
          '$className: a @UniqueConstraint needs at least one property',
        );
      }
      final covered = <PersistentProperty>[];
      for (final name in annotation.properties) {
        final property = stored[name];
        if (property == null) {
          throw MappingException(
            "$className: @UniqueConstraint names the property '$name', "
            'which is not a stored property of $className (the stored '
            'properties: ${stored.keys.join(', ')})',
          );
        }
        if (covered.contains(property)) {
          throw MappingException(
            "$className: @UniqueConstraint names the property '$name' "
            'twice',
          );
        }
        covered.add(property);
      }
      constraints.add(
        PersistentUniqueConstraint(
          name:
              annotation.name ??
              'uq_${tableName}_${covered.map((p) => p.columnName).join('_')}',
          properties: covered,
        ),
      );
    }
    final names = <String>{};
    for (final constraint in constraints) {
      if (!names.add(constraint.name.toLowerCase())) {
        throw MappingException(
          '$className has two unique constraints named '
          "'${constraint.name}'",
        );
      }
    }
    return constraints;
  }

  void _checkEntity(
    String className,
    List<PersistentProperty> properties, {
    required bool isChild,
  }) {
    final ids = properties.where((p) => p.isId).toList();
    if (ids.length > 1) {
      throw MappingException(
        '$className has more than one @Id: '
        '${ids.map((p) => p.name).join(', ')}',
      );
    }
    final versions = properties.where((p) => p.isVersion).toList();
    if (versions.length > 1) {
      throw MappingException(
        '$className has more than one @Version: '
        '${versions.map((p) => p.name).join(', ')}',
      );
    }
    if (isChild && versions.isNotEmpty) {
      throw MappingException(
        '$className.${versions.single.name}: @Version is only allowed on '
        'the aggregate root; its version covers its children',
      );
    }
  }

  PersistentProperty _property(
    EntityIntrospection<Object> owner,
    int index,
    bool isChild,
    List<Type> path,
  ) {
    final described = owner.properties[index];
    final where = '${owner.className}.${described.name}';
    final type = described.type;
    final annotations = described.annotations;
    final isId = annotations.any((a) => a is Id);
    final isVersion = annotations.any((a) => a is Version);
    if (isVersion && type.type != int && type.type != DateTime) {
      throw MappingException(
        '$where: @Version must be an int or a DateTime, not ${type.type}',
      );
    }
    final audits = <AuditKind>[
      if (annotations.any((a) => a is CreatedDate)) AuditKind.createdDate,
      if (annotations.any((a) => a is LastModifiedDate))
        AuditKind.lastModifiedDate,
      if (annotations.any((a) => a is CreatedBy)) AuditKind.createdBy,
      if (annotations.any((a) => a is LastModifiedBy)) AuditKind.lastModifiedBy,
    ];
    if (audits.length > 1) {
      throw MappingException(
        '$where has more than one audit annotation: '
        '${audits.map((a) => a.name).join(', ')}',
      );
    }
    final audit = audits.firstOrNull;
    if ((audit == AuditKind.createdDate ||
            audit == AuditKind.lastModifiedDate) &&
        type.type != DateTime) {
      final annotationName = audit == AuditKind.createdDate
          ? 'CreatedDate'
          : 'LastModifiedDate';
      throw MappingException(
        '$where: @$annotationName must be a DateTime, not ${type.type}',
      );
    }
    final mapped = annotations.whereType<MappedCollection>().firstOrNull;
    PersistentEntity<Object>? child;
    if (mapped != null) {
      if (isId || isVersion || audit != null) {
        throw MappingException(
          '$where: a @MappedCollection cannot be an @Id, a @Version or '
          'an audited property',
        );
      }
      child = _childEntity(where, type, path);
    }
    TypeInfo<Object?>? referenced;
    Type? aggregateReferenceTarget;
    if (type is GenericType<Object?> &&
        type.isSubtypeOf<AggregateReference<Object?, Object?>>()) {
      if (type.arguments.length != 2) {
        throw MappingException(
          '$where: an AggregateReference needs its two type arguments',
        );
      }
      aggregateReferenceTarget = type.arguments[0].type;
      referenced = type.arguments[1];
    }
    final plain = annotations.whereType<Reference>().firstOrNull;
    if (plain != null && aggregateReferenceTarget != null) {
      throw MappingException(
        '$where is an AggregateReference and marked @Reference: use one '
        'of the two',
      );
    }
    if (plain != null && mapped != null) {
      throw MappingException(
        '$where: a @MappedCollection cannot be a @Reference',
      );
    }
    final target = plain?.target ?? aggregateReferenceTarget;
    if (target != null) {
      _checkReference(
        where,
        target,
        referenced ?? type,
        isAggregateReference: plain == null,
      );
    } else if (mapped == null) {
      _checkNotAnEntity(where, owner.className, described.name, type);
    }
    final onDelete = annotations.whereType<OnDelete>().firstOrNull;
    if (onDelete != null) {
      if (target == null) {
        throw MappingException(
          '$where: @OnDelete applies to a reference only: make it an '
          'AggregateReference or mark it @Reference',
        );
      }
      if (onDelete.action == OnDeleteAction.setNull && !type.nullable) {
        throw MappingException(
          '$where: @OnDelete(OnDeleteAction.setNull) needs a nullable '
          'property, as the reference is set to null when the referenced '
          'aggregate is deleted',
        );
      }
    }
    final hasDefault = described.hasDefaultValue;
    final defaultValue = described.defaultValue;
    if (onDelete?.action == OnDeleteAction.setDefault) {
      if (!hasDefault) {
        throw MappingException(
          '$where: @OnDelete(OnDeleteAction.setDefault) needs a default '
          'value (a constant initializer, `int? authorId = 1`, or a constant '
          'default of the constructor parameter)',
        );
      }
      if (defaultValue == null && !type.nullable) {
        throw MappingException(
          '$where: @OnDelete(OnDeleteAction.setDefault) with a null default '
          'needs a nullable property',
        );
      }
    }
    final unique = annotations.any((a) => a is Unique);
    if (unique && mapped != null) {
      throw MappingException(
        '$where: a @MappedCollection cannot be @Unique',
      );
    }
    final column = annotations.whereType<Column>().firstOrNull;
    return PersistentProperty(
      name: described.name,
      columnName: namingStrategy.columnName(described.name, column),
      type: type,
      owner: owner,
      index: index,
      isId: isId,
      isVersion: isVersion,
      audit: audit,
      mappedCollection: mapped,
      childEntity: child,
      referencedType: referenced,
      referencedEntityType: target,
      referencedEntity: target == null
          ? null
          : () => getRequiredPersistentEntityOfType(target),
      onDelete: onDelete?.action ?? OnDeleteAction.noAction,
      hasExplicitOnDelete: onDelete != null,
      isUnique: unique,
      hasDefaultValue: hasDefault,
      defaultValue: defaultValue,
    );
  }

  // A reference needs a described aggregate with an `@Id` of the type the
  // property holds.
  void _checkReference(
    String where,
    Type target,
    TypeInfo<Object?> idType, {
    required bool isAggregateReference,
  }) {
    final introspection = _described[target];
    if (introspection == null ||
        !introspection.annotations.any((a) => a is Table)) {
      throw MappingException(
        '$where references $target, which is not described: mark '
        '$target @Table (and register its module) so it can be referenced',
      );
    }
    final ids = [
      for (final p in introspection.properties)
        if (p.annotation<Id>() != null) p,
    ];
    if (ids.length != 1) {
      throw MappingException(
        '$where references ${introspection.className}, which has '
        '${ids.isEmpty ? 'no' : 'more than one'} @Id',
      );
    }
    final id = ids.single;
    final actual = id.type.type;
    if (idType.type != actual && idType is! DynamicType) {
      throw MappingException(
        isAggregateReference
            ? '$where is an AggregateReference<${introspection.className}, '
                  '${idType.type}>, but ${introspection.className}.${id.name} '
                  'is a $actual: the id type must be $actual'
            : '$where is a @Reference(${introspection.className}) of type '
                  '${idType.type}, but ${introspection.className}.${id.name} '
                  'is a $actual: the property must be a $actual',
      );
    }
  }

  // `Author author;` without `@MappedCollection`: another aggregate (or a
  // child) held as an object, which the starter never guesses.
  void _checkNotAnEntity(
    String where,
    String ownerName,
    String propertyName,
    TypeInfo<Object?> type,
  ) {
    final introspection = _described[type.type];
    if (introspection == null ||
        !introspection.annotations.any((a) => a is Table)) {
      return;
    }
    final name = introspection.className;
    final id = [
      for (final p in introspection.properties)
        if (p.annotation<Id>() != null) p,
    ].firstOrNull;
    final idType = id?.type.type ?? 'int';
    throw MappingException(
      '$where is another aggregate: use AggregateReference<$name, $idType> '
      'or @Reference($name) $idType ${propertyName}Id (a field of an entity '
      'type is never guessed: in Spring Data JDBC it would be a child of '
      '$ownerName, a @MappedCollection)',
    );
  }

  PersistentEntity<Object> _childEntity(
    String where,
    TypeInfo<Object?> type,
    List<Type> path,
  ) {
    final element = switch (type) {
      ListType(:final element) => element,
      SetType(:final element) => element,
      MapType(:final value) => value,
      _ => type,
    };
    final introspection = _described[element.type];
    if (introspection == null) {
      throw MappingException(
        '$where: the children of type ${element.type} are not described; '
        'mark the class @Table',
      );
    }
    if (!introspection.annotations.any((a) => a is Table)) {
      throw MappingException(
        '$where: the child class ${introspection.className} must be '
        'marked @Table',
      );
    }
    final cached = _children[introspection.type];
    if (cached != null && !path.contains(introspection.type)) {
      return cached;
    }
    final entity = _build<Object>(introspection, isChild: true, path: path);
    _children[introspection.type] = entity;
    return entity;
  }
}
