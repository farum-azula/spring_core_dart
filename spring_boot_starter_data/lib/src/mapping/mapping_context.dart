import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
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
/// [BeanIntrospection], and keeps it: a class is mapped once.
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
///   `referencedType` is the type of `ID`.
/// * A [MappedCollection] on a `List<C>`, `Set<C>` or `Map<K, C>` (or on a
///   single `C`) holds children: `C` must be described and marked [Table];
///   its entity is built the same way, as a child (it takes no [Version]).
///
/// The descriptions are read from a [BeanIntrospector]: the application
/// context's (`ApplicationContext.introspector`, which the generated
/// `*.spring.dart` modules fill and whose parent is
/// `BeanIntrospector.shared`) or any other, such as one a test fills by hand.
///
/// Spring (Java):
/// `org.springframework.data.relational.core.mapping.RelationalMappingContext`.
class RelationalMappingContext {
  /// A context reading descriptions from [introspector] (by default
  /// `BeanIntrospector.shared`) and naming tables and columns with
  /// [namingStrategy].
  RelationalMappingContext({
    BeanIntrospector? introspector,
    this.namingStrategy = const NamingStrategy(),
  }) : introspector = introspector ?? BeanIntrospector.shared;

  /// Where the classes' descriptions come from.
  final BeanIntrospector introspector;

  /// How tables and columns are named when the annotations do not say.
  final NamingStrategy namingStrategy;

  final _roots = <Type, PersistentEntity<Object>>{};
  final _children = <Type, PersistentEntity<Object>>{};

  /// The entity of the root class [T]; throws a [MappingException] when [T]
  /// is not described or its mapping is wrong.
  PersistentEntity<T> getRequiredPersistentEntity<T extends Object>() {
    final cached = _roots[T];
    if (cached is PersistentEntity<T>) {
      return cached;
    }
    final introspection = introspector.forTypeArgument<T>();
    if (introspection == null) {
      throw MappingException(_notDescribed(T));
    }
    final entity = fromIntrospection<T>(introspection as BeanIntrospection<T>);
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
    final introspection = introspector.forType(type);
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

  /// The entity of the class [instance] is an instance of, for the most
  /// specific class described; throws a [MappingException] when there is
  /// none.
  PersistentEntity<Object> entityOf(Object instance) {
    final introspection = introspector.findIntrospection(instance);
    if (introspection == null) {
      throw MappingException(_notDescribed(instance.runtimeType));
    }
    return getRequiredPersistentEntityOfType(introspection.beanType);
  }

  /// Builds (without caching) the entity of a root class from
  /// [introspection]; for tests that describe a class by hand. Children
  /// are looked up in [introspector].
  PersistentEntity<T> fromIntrospection<T extends Object>(
    BeanIntrospection<T> introspection,
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
    BeanIntrospection<T> introspection, {
    required bool isChild,
    required List<Type> path,
  }) {
    final className = introspection.className;
    final type = introspection.beanType;
    if (path.contains(type)) {
      throw MappingException(
        '$className: ${[...path, type].join(' -> ')} contains itself as '
        'a child; an aggregate is a tree',
      );
    }
    final constructorParameters = {
      for (final p
          in introspection.constructor?.parameters ?? const <BeanParameter>[])
        p.name,
    };
    final properties = <PersistentProperty>[];
    for (final bean in introspection.properties) {
      if (bean.annotationsOf<Transient>().isNotEmpty) {
        continue;
      }
      if (!bean.isWritable && !constructorParameters.contains(bean.name)) {
        continue;
      }
      properties.add(
        _property(introspection, bean, isChild, [...path, type]),
      );
    }
    _checkEntity(className, properties, isChild: isChild);
    final table = introspection.annotations.whereType<Table>().firstOrNull;
    return PersistentEntity<T>(
      introspection: introspection,
      tableName: namingStrategy.tableName(className, table),
      schema: table?.schema,
      properties: properties,
    );
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
    BeanIntrospection<Object> owner,
    BeanProperty<Object> bean,
    bool isChild,
    List<Type> path,
  ) {
    final where = '${owner.className}.${bean.name}';
    var type = bean.typeInfo ?? const DynamicType();
    if (bean.nullable && !type.nullable) {
      type = type.asNullable();
    }
    final annotations = bean.annotations;
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
    if (type is GenericType<Object?> &&
        type.isSubtypeOf<AggregateReference<Object?, Object?>>()) {
      if (type.arguments.length != 2) {
        throw MappingException(
          '$where: an AggregateReference needs its two type arguments',
        );
      }
      referenced = type.arguments[1];
    }
    final column = annotations.whereType<Column>().firstOrNull;
    return PersistentProperty(
      name: bean.name,
      columnName: namingStrategy.columnName(bean.name, column),
      type: type,
      accessor: bean,
      isId: isId,
      isVersion: isVersion,
      audit: audit,
      mappedCollection: mapped,
      childEntity: child,
      referencedType: referenced,
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
    final introspection = introspector.forType(element.type);
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
    final cached = _children[introspection.beanType];
    if (cached != null && !path.contains(introspection.beanType)) {
      return cached;
    }
    final entity = _build<Object>(introspection, isChild: true, path: path);
    _children[introspection.beanType] = entity;
    return entity;
  }
}
