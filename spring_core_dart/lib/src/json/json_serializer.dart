import 'package:spring_core_dart/src/json/object_mapper.dart';

/// Custom code that writes values of [T] as JSON, for a type the mapper
/// cannot handle or should write differently.
///
/// The mapper writes introspected classes, enums and the common Dart types
/// on its own. Write a serializer for a class you cannot annotate (from
/// another package), or for a compact form such as money as
/// `"12.50 EUR"`. It returns plain JSON values; maps and lists it returns
/// are written further, so they may hold other objects. Register it with
/// `ObjectMapper(serializers: [...])`, in a [JsonModule], or, in Spring
/// Boot, as a bean: the auto-configured mapper picks it up. Serializers
/// are tried in order before the built-in handling, the first that
/// [handles] a value wins, and subtypes of [T] count. Pair it with a
/// [JsonDeserializer] to read the same form back.
///
/// ```dart
/// // Money is written as one string, "1250 EUR".
/// final class MoneySerializer extends JsonSerializer<Money> {
///   const MoneySerializer();
///   @override
///   Object? serialize(Money value, ObjectMapper mapper) =>
///       '${value.amount} ${value.currency}';
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class MoneySerializer extends JsonSerializer<Money> {
///   public void serialize(
///       Money value, JsonGenerator gen, SerializerProvider p) { ... }
/// }
/// ```
abstract class JsonSerializer<T extends Object> {
  /// Lets subclasses be `const`.
  const JsonSerializer();

  /// Whether this serializer writes [value]; by default, whether it is a
  /// [T] (subtypes included). Override it to be more selective.
  bool handles(Object value) => value is T;

  /// Returns the JSON form of [value]: `null`, a bool, a number, a string,
  /// or a list or map, whose elements the mapper writes in turn. [mapper]
  /// is the mapper at work, for writing nested values with its settings.
  Object? serialize(T value, ObjectMapper mapper);

  /// Calls [serialize] with [value] cast to [T]; the mapper uses it, since
  /// it only knows the serializer as a `JsonSerializer<Object>`.
  Object? write(Object value, ObjectMapper mapper) =>
      serialize(value as T, mapper);
}

/// Custom code that builds values of [T] from decoded JSON, for a type the
/// mapper cannot read on its own or should read differently.
///
/// It is the reading half of a [JsonSerializer]: use it for classes you
/// cannot annotate, or for a compact JSON form. It receives what
/// `jsonDecode` produced (never `null`; a JSON `null` gives `null`
/// without calling it). Register it with `ObjectMapper(deserializers:
/// [...])`, in a [JsonModule], or, in Spring Boot, as a bean. It is used
/// when the requested type is exactly [T] or `T?`, not a subtype, before
/// the built-in handling. An error it throws becomes a
/// `JsonMappingException` with the path of the value.
///
/// ```dart
/// // Reads the "1250 EUR" form back.
/// final class MoneyDeserializer extends JsonDeserializer<Money> {
///   const MoneyDeserializer();
///   @override
///   Money deserialize(Object json, ObjectMapper mapper) {
///     final [amount, currency] = (json as String).split(' ');
///     return Money(int.parse(amount), currency);
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class MoneyDeserializer extends JsonDeserializer<Money> {
///   public Money deserialize(JsonParser p, DeserializationContext c) { ... }
/// }
/// ```
abstract class JsonDeserializer<T extends Object> {
  /// Lets subclasses be `const`.
  const JsonDeserializer();

  /// Whether this deserializer reads the requested type [S]: `true` for
  /// `T` and `T?`.
  bool handles<S>() => S == T || (<S>[] is List<T?> && <T?>[] is List<S>);

  /// Returns a [T] built from the decoded [json]: a string, number, bool,
  /// list or map, never `null`. [mapper] is the mapper at work, for reading
  /// nested values with its settings. Throw when [json] has the wrong
  /// shape.
  T deserialize(Object json, ObjectMapper mapper);
}

/// A group of serializers and deserializers that is added to a mapper in
/// one step.
///
/// Use it to ship the JSON support of a set of types together, for
/// example a library's money and currency types. In Spring Boot every
/// `JsonModule` bean is added to the auto-configured `ObjectMapper`, as
/// Boot registers Jackson `Module` beans; otherwise pass it to
/// `ObjectMapper(modules: [...])`. Its serializers and deserializers come
/// after those passed to the mapper directly.
///
/// ```dart
/// // Money support for the whole application.
/// @Configuration()
/// class JsonSetup {
///   @Bean()
///   JsonModule moneyModule() => const JsonModule(
///     serializers: [MoneySerializer()],
///     deserializers: [MoneyDeserializer()],
///   );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// Module moneyModule() {
///   return new SimpleModule()
///       .addSerializer(Money.class, new MoneySerializer())
///       .addDeserializer(Money.class, new MoneyDeserializer());
/// }
/// ```
class JsonModule {
  /// A module holding [serializers] and [deserializers]; both default to
  /// none.
  const JsonModule({
    this.serializers = const [],
    this.deserializers = const [],
  });

  /// The serializers, tried in order.
  final List<JsonSerializer<Object>> serializers;

  /// The deserializers, tried in order.
  final List<JsonDeserializer<Object>> deserializers;
}
