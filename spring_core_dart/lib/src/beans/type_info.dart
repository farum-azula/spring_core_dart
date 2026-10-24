/// The full type of a property or parameter: element types of
/// collections, enum values and nullability, which a plain `Type` does not
/// expose without reflection (`List<Book>` cannot be taken apart at
/// runtime). Written by the generator for introspected classes and used to
/// rebuild values, e.g. by `ObjectMapper`.
///
/// Each kind is generic, so the values built from it have the right static
/// type: a `ListType<Book>` creates a `List<Book>`, not a `List<dynamic>`.
///
/// ```dart
/// const books = ListType<Book>(ClassType<Book>());
/// const prices = MapType<String, double>(
///   ClassType<String>(),
///   ClassType<double>(),
/// );
/// const note = ClassType<String>(nullable: true); // String?
/// final mood = EnumType<Mood>(Mood.values);
/// ```
///
/// Spring (Java): `ResolvableType` / `TypeDescriptor`, read from generic
/// signatures by reflection:
/// ```java
/// ResolvableType books = ResolvableType.forClassWithGenerics(List.class, Book.class);
/// ```
sealed class TypeInfo<T> {
  const TypeInfo({this.nullable = false});

  /// Whether `null` is a valid value.
  final bool nullable;

  /// The described type (without the nullability of [nullable]).
  Type get type => T;

  /// Calls the [visitor] method for this kind with its type arguments.
  R accept<R>(TypeInfoVisitor<R> visitor);

  /// The same type, nullable (`T?`).
  TypeInfo<T> asNullable();

  /// Calls [body] with the described type as its type argument (`T?` when
  /// [nullable]), e.g. to create a `Page<T>` from a `TypeInfo` of `T`.
  R capture<R>(R Function<X>() body) => nullable ? body<T?>() : body<T>();

  /// Whether [value] belongs to this type (`null` only when [nullable]).
  bool isInstance(Object? value) => value == null ? nullable : value is T;
}

/// Callbacks per kind of [TypeInfo], with the type arguments in scope.
///
/// ```dart
/// final class Describe implements TypeInfoVisitor<String> {
///   @override
///   String visitClass<T>(ClassType<T> type) => '$T';
///   @override
///   String visitList<E>(ListType<E> type) =>
///       'List of ${type.element.accept(this)}';
///   ...
/// }
/// ```
abstract interface class TypeInfoVisitor<R> {
  /// A class or a scalar (`String`, `int`, `DateTime`, an introspected
  /// class, ...).
  R visitClass<T>(ClassType<T> type);

  /// `List<E>` (also used for `Iterable<E>`).
  R visitList<E>(ListType<E> type);

  /// `Set<E>`.
  R visitSet<E>(SetType<E> type);

  /// `Map<K, V>`.
  R visitMap<K, V>(MapType<K, V> type);

  /// An enum.
  R visitEnum<E extends Enum>(EnumType<E> type);

  /// Another generic class with its type arguments, e.g.
  /// `ResponseEntity<Book>`.
  R visitGeneric<T>(GenericType<T> type);

  /// `dynamic`, `Object` or a type that is not described further.
  R visitDynamic(DynamicType type);
}

/// A class or scalar type: `ClassType<String>()`, `ClassType<Book>()`.
final class ClassType<T> extends TypeInfo<T> {
  /// Describes [T]; `nullable` for `T?`.
  const ClassType({super.nullable});

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitClass<T>(this);

  @override
  ClassType<T> asNullable() => ClassType<T>(nullable: true);

  @override
  String toString() => '$T${nullable ? '?' : ''}';
}

/// `List<E>`: `ListType<Book>(ClassType<Book>())`.
final class ListType<E> extends TypeInfo<List<E>> {
  /// A list of [element]s.
  const ListType(this.element, {super.nullable});

  /// The element type.
  final TypeInfo<E> element;

  /// A `List<E>` of [items] (each must be an `E`).
  List<E> create(Iterable<Object?> items) => [for (final i in items) i as E];

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitList<E>(this);

  @override
  ListType<E> asNullable() => ListType<E>(element, nullable: true);

  @override
  String toString() => 'List<$element>${nullable ? '?' : ''}';
}

/// `Set<E>`: `SetType<String>(ClassType<String>())`.
final class SetType<E> extends TypeInfo<Set<E>> {
  /// A set of [element]s.
  const SetType(this.element, {super.nullable});

  /// The element type.
  final TypeInfo<E> element;

  /// A `Set<E>` of [items] (each must be an `E`).
  Set<E> create(Iterable<Object?> items) => {for (final i in items) i as E};

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitSet<E>(this);

  @override
  SetType<E> asNullable() => SetType<E>(element, nullable: true);

  @override
  String toString() => 'Set<$element>${nullable ? '?' : ''}';
}

/// `Map<K, V>`: `MapType<String, int>(ClassType<String>(), ClassType<int>())`.
final class MapType<K, V> extends TypeInfo<Map<K, V>> {
  /// A map from [key] to [value].
  const MapType(this.key, this.value, {super.nullable});

  /// The key type.
  final TypeInfo<K> key;

  /// The value type.
  final TypeInfo<V> value;

  /// A `Map<K, V>` of [entries] (keys `K`, values `V`).
  Map<K, V> create(Iterable<MapEntry<Object?, Object?>> entries) => {
    for (final entry in entries) entry.key as K: entry.value as V,
  };

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitMap<K, V>(this);

  @override
  MapType<K, V> asNullable() => MapType<K, V>(key, value, nullable: true);

  @override
  String toString() => 'Map<$key, $value>${nullable ? '?' : ''}';
}

/// An enum with its [values]: `EnumType<Mood>(Mood.values)`. [jsonValue]
/// is the field marked `@JsonValue()`, when the enum has one.
final class EnumType<E extends Enum> extends TypeInfo<E> {
  /// The enum [values]; [jsonValue] maps a value to its JSON form.
  const EnumType(this.values, {this.jsonValue, super.nullable});

  /// Every value of the enum.
  final List<E> values;

  /// The JSON form of a value (default: its `name`).
  final Object? Function(E value)? jsonValue;

  /// The JSON form of [value].
  Object? toJsonValue(E value) => jsonValue?.call(value) ?? value.name;

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitEnum<E>(this);

  @override
  EnumType<E> asNullable() =>
      EnumType<E>(values, jsonValue: jsonValue, nullable: true);

  @override
  String toString() => '$E${nullable ? '?' : ''}';
}

/// A generic class other than the collections, with its type [arguments]:
/// `GenericType<ResponseEntity<Book>>([ClassType<Book>()])`. [T] is the
/// whole type; [arguments] describe its type arguments in order.
final class GenericType<T> extends TypeInfo<T> {
  /// Describes [T] with the descriptions of its type [arguments].
  const GenericType(this.arguments, {super.nullable});

  /// The type arguments, in order.
  final List<TypeInfo<Object?>> arguments;

  /// Whether [T] is a subtype of [S] (e.g. `ResponseEntity<Object?>`).
  bool isSubtypeOf<S>() => <T>[] is List<S>;

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitGeneric<T>(this);

  @override
  GenericType<T> asNullable() => GenericType<T>(arguments, nullable: true);

  @override
  String toString() => '$T${nullable ? '?' : ''}';
}

/// `dynamic`, `Object?` or a type that is not described further: values
/// are taken as they are. `void` (e.g. of `ResponseEntity<void>`) is
/// [DynamicType.forVoid], so a reader can ignore the value.
final class DynamicType extends TypeInfo<Object?> {
  /// Any value.
  const DynamicType() : isVoid = false, super(nullable: true);

  /// `void`: no value is expected.
  const DynamicType.forVoid() : isVoid = true, super(nullable: true);

  /// Whether this stands for `void`.
  final bool isVoid;

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitDynamic(this);

  @override
  DynamicType asNullable() => this;

  @override
  String toString() => isVoid ? 'void' : 'dynamic';
}
