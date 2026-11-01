import 'package:spring_boot_dart/spring_boot_dart.dart';

/// What the build writes for a class the data layer stores or reads: an
/// entity (`@Table`), a class stored inside one (the children of a
/// `@MappedCollection`, a single child), or a class a `@Query` returns.
///
/// It lists the class's properties, in order, and the build gives three
/// functions: [valueAt] takes the value of one of them from an instance,
/// [create] calls the constructor with all of them, and [write] sets one in
/// place. The getter reads one property at a time, so a property the
/// mapping does not store (a `@Transient` one, perhaps a `late` field that
/// was never set) is never touched by a save. The mapping rules (the table,
/// the columns, the id, the version, the references) stay in the mapping,
/// which reads the annotations given here: the build writes no more than
/// the class itself says.
///
/// ```dart
/// // For `Author({this.id, required this.name})` with mutable fields:
/// EntityIntrospection<Author>(
///   'Author',
///   const [
///     EntityProperty('id', ClassType<int>(nullable: true),
///         annotations: [Id()], parameter: true, writable: true),
///     EntityProperty('name', ClassType<String>(),
///         parameter: true, writable: true),
///   ],
///   annotations: const [Table('authors')],
///   get: (e, i) => switch (i) {
///     0 => e.id,
///     _ => e.name,
///   },
///   create: (v) => Author(id: v[0] as int?, name: v[1] as String),
///   write: (e, i, v) => switch (i) {
///     0 => e.id = v as int?,
///     _ => e.name = v as String,
///   },
/// );
/// ```
///
/// Hibernate: the metamodel's `EntityType`; Micronaut Data: the entity's
/// `BeanIntrospection`.
final class EntityIntrospection<T extends Object> {
  /// The description of class [className] with [properties].
  EntityIntrospection(
    this.className,
    List<EntityProperty> properties, {
    required this._get,
    required this._create,
    this._write,
    this.annotations = const [],
  }) : properties = List.unmodifiable(properties),
       _indexes = {
         for (final (index, property) in properties.indexed)
           property.name: index,
       };

  /// The class's name, such as `Author`.
  final String className;

  /// The class's annotations (`Table`, `UniqueConstraint`), as constants.
  final List<Object> annotations;

  /// Every public instance field with a getter, the inherited ones too, in
  /// declaration order (the class's own first).
  final List<EntityProperty> properties;

  // Private, and called through methods taking an Object: an
  // `EntityIntrospection<Author>` is used as an
  // `EntityIntrospection<Object>`, and a function of `Author` read through
  // that type would fail its type check.
  final Object? Function(T instance, int index) _get;
  final T Function(List<Object?> values) _create;
  final void Function(T instance, int index, Object? value)? _write;
  final Map<String, int> _indexes;

  /// The value of the property at [index] of [properties] on [instance] (a
  /// `T`); only that property is read.
  Object? valueAt(Object instance, int index) => _get(instance as T, index);

  /// The values of all of [properties] on [instance] (a `T`), in the same
  /// order. It reads the properties that are not stored too: to read some,
  /// call [valueAt].
  List<Object?> values(Object instance) {
    final value = instance as T;
    return [for (var i = 0; i < properties.length; i++) _get(value, i)];
  }

  /// Creates an instance from [values], in the order of [properties]: the
  /// constructor takes those that are [EntityProperty.parameter]s; the
  /// others are not used (set them with [write]).
  T create(List<Object?> values) => _create(values);

  /// Sets the property at [index] of [properties] on [instance] (a `T`) to
  /// [value]; for an [EntityProperty.writable] property only.
  void write(Object instance, int index, Object? value) {
    final write = _write;
    if (write == null || !properties[index].writable) {
      throw StateError(
        '$className.${properties[index].name} is final: create a copy '
        'instead of setting it',
      );
    }
    write(instance as T, index, value);
  }

  /// The class described.
  Type get type => T;

  /// The index in [properties] of the property named [name], or null.
  int? indexOf(String name) => _indexes[name];

  /// The property named [name], or null.
  EntityProperty? property(String name) => switch (_indexes[name]) {
    final index? => properties[index],
    null => null,
  };

  /// Calls [body] with `T`, the class described.
  R capture<R>(R Function<E extends Object>() body) => body<T>();

  @override
  String toString() => 'EntityIntrospection<$T>';
}

/// One property of an [EntityIntrospection].
final class EntityProperty {
  /// The property [name] of [type].
  const EntityProperty(
    this.name,
    this.type, {
    this.annotations = const [],
    this.parameter = false,
    this.writable = false,
    this.hasDefaultValue = false,
    this.defaultValue,
  });

  /// The Dart name.
  final String name;

  /// The declared type, with its nullability.
  final TypeInfo<Object?> type;

  /// The annotations of the field and its getter, as constants.
  final List<Object> annotations;

  /// Whether the constructor takes it (a parameter of the same name).
  final bool parameter;

  /// Whether it has a setter.
  final bool writable;

  /// Whether it has a default value: a constant initializer of the field
  /// (`bool inStock = true`), else a constant default of the constructor
  /// parameter (`this.inStock = true`).
  final bool hasDefaultValue;

  /// The default value (see [hasDefaultValue]).
  final Object? defaultValue;

  /// The first annotation of type [A], or null.
  A? annotation<A>() => annotations.whereType<A>().firstOrNull;

  @override
  String toString() => 'EntityProperty($name: $type)';
}

/// The entity introspections of one module, which the build registers as
/// a bean; the mapping takes those of every module.
final class EntityIntrospections {
  /// The [introspections] of a module.
  const EntityIntrospections(this.introspections);

  /// One for each class the module's data layer stores or reads.
  final List<EntityIntrospection<Object>> introspections;
}
