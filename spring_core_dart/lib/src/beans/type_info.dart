/// A description of a full Dart type, such as `List<Book>` or `String?`,
/// that code can take apart at run time without reflection.
///
/// A plain `Type` hides its type arguments, enum values and nullability:
/// at run time `List<Book>` cannot be asked for `Book`. The generator
/// writes a `TypeInfo` for every property and parameter of an
/// introspected class, and `ObjectMapper`, `BeanWrapper` and data binding
/// read it to build values of the right type. You write one by hand to
/// tell `ObjectMapper.readValue` a generic target type, or in a
/// hand-written introspection.
///
/// Each kind is generic, so the values built from it have the right static
/// type: a `ListType<Book>` creates a `List<Book>`, not a `List<dynamic>`.
///
/// ```dart
/// // Read a JSON array as a real List<Book>.
/// const books = ListType<Book>(ClassType<Book>());
/// const prices = MapType<String, double>(
///   ClassType<String>(),
///   ClassType<double>(),
/// );
/// const note = ClassType<String>(nullable: true); // String?
/// final mood = EnumType<Mood>(Mood.values);
/// final list = mapper.readValue('[...]', books);
/// ```
///
/// Spring (Java): `ResolvableType` / `TypeDescriptor`, read from generic
/// signatures by reflection:
/// ```java
/// ResolvableType books =
///     ResolvableType.forClassWithGenerics(List.class, Book.class);
/// ```
sealed class TypeInfo<T> {
  const TypeInfo({this.nullable = false});

  /// Whether `null` is a valid value (the type is `T?`).
  final bool nullable;

  /// The described type (without the nullability of [nullable]).
  Type get type => T;

  /// Calls the method of [visitor] for this kind, with its type arguments
  /// in scope, and returns its result. Code that handles every kind
  /// (a JSON reader, a value factory) uses it instead of a type switch.
  R accept<R>(TypeInfoVisitor<R> visitor);

  /// The same type, nullable (`T?`).
  TypeInfo<T> asNullable();

  /// Calls [body] with the described type as its type argument (`T?` when
  /// [nullable]), e.g. to create a `Page<T>` from a `TypeInfo` of `T`.
  R capture<R>(R Function<X>() body) => nullable ? body<T?>() : body<T>();

  /// Whether [value] belongs to this type (`null` only when [nullable]).
  bool isInstance(Object? value) => value == null ? nullable : value is T;
}

/// One method per kind of [TypeInfo], called by [TypeInfo.accept] with the
/// kind's type arguments in scope.
///
/// Implement it to do something with any described type where you need the
/// type arguments as real types, for example to create a `List<E>` of the
/// right element type. Most code never does; `ObjectMapper` and
/// `BeanWrapper` do it internally.
///
/// ```dart
/// // Describe a type in words.
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

/// The [TypeInfo] of a class or scalar type that needs no further
/// description: `ClassType<String>()`, `ClassType<Book>()`.
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

/// The [TypeInfo] of a `List<E>`, with the description of its elements:
/// `ListType<Book>(ClassType<Book>())`.
final class ListType<E> extends TypeInfo<List<E>> {
  /// A list of [element]s.
  const ListType(this.element, {super.nullable});

  /// The element type.
  final TypeInfo<E> element;

  /// A new `List<E>` of [items]; each must be an `E` (else a `TypeError`).
  List<E> create(Iterable<Object?> items) => [for (final i in items) i as E];

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitList<E>(this);

  @override
  ListType<E> asNullable() => ListType<E>(element, nullable: true);

  @override
  String toString() => 'List<$element>${nullable ? '?' : ''}';
}

/// The [TypeInfo] of a `Set<E>`, with the description of its elements:
/// `SetType<String>(ClassType<String>())`.
final class SetType<E> extends TypeInfo<Set<E>> {
  /// A set of [element]s.
  const SetType(this.element, {super.nullable});

  /// The element type.
  final TypeInfo<E> element;

  /// A new `Set<E>` of [items]; each must be an `E` (else a `TypeError`).
  Set<E> create(Iterable<Object?> items) => {for (final i in items) i as E};

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitSet<E>(this);

  @override
  SetType<E> asNullable() => SetType<E>(element, nullable: true);

  @override
  String toString() => 'Set<$element>${nullable ? '?' : ''}';
}

/// The [TypeInfo] of a `Map<K, V>`, with the descriptions of its keys and
/// values: `MapType<String, int>(ClassType<String>(), ClassType<int>())`.
final class MapType<K, V> extends TypeInfo<Map<K, V>> {
  /// A map from [key] to [value].
  const MapType(this.key, this.value, {super.nullable});

  /// The key type.
  final TypeInfo<K> key;

  /// The value type.
  final TypeInfo<V> value;

  /// A new `Map<K, V>` of [entries]; keys must be `K` and values `V` (else
  /// a `TypeError`).
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

/// The [TypeInfo] of an enum, with its [values], so a value can be found by
/// name: `EnumType<Mood>(Mood.values)`. [jsonValue] reads the field marked
/// `@JsonValue()`, when the enum has one.
final class EnumType<E extends Enum> extends TypeInfo<E> {
  /// The enum [values]; [jsonValue] maps a value to its JSON form.
  const EnumType(this.values, {this.jsonValue, super.nullable});

  /// Every value of the enum.
  final List<E> values;

  /// The JSON form of a value (default: its `name`).
  final Object? Function(E value)? jsonValue;

  /// The JSON form of [value]: [jsonValue]'s result, else its `name`.
  Object? toJsonValue(E value) => jsonValue?.call(value) ?? value.name;

  @override
  R accept<R>(TypeInfoVisitor<R> visitor) => visitor.visitEnum<E>(this);

  @override
  EnumType<E> asNullable() =>
      EnumType<E>(values, jsonValue: jsonValue, nullable: true);

  @override
  String toString() => '$E${nullable ? '?' : ''}';
}

/// The [TypeInfo] of a generic class other than the collections, with the
/// descriptions of its type [arguments]:
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

/// The [TypeInfo] of `dynamic`, `Object?` or a type that is not described
/// further: values are taken as they are. `void` (e.g. of
/// `ResponseEntity<void>`) is [DynamicType.forVoid], so a reader can ignore
/// the value.
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
