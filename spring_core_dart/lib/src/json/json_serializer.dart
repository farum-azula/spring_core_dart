import 'package:spring_core_dart/src/json/object_mapper.dart';

/// Writes values of [T] as JSON yourself, like a Jackson `JsonSerializer`;
/// register it with `ObjectMapper(serializers: [...])` or as a bean (Spring
/// Boot picks up serializer beans).
///
/// ```dart
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
  /// Const base constructor.
  const JsonSerializer();

  /// Whether this serializer writes [value].
  bool handles(Object value) => value is T;

  /// The JSON form of [value]: `null`, a bool, number, string, or a list or
  /// map of those. [mapper] writes nested values.
  Object? serialize(T value, ObjectMapper mapper);

  /// Calls [serialize] (internal: avoids a cast at the call site).
  Object? write(Object value, ObjectMapper mapper) =>
      serialize(value as T, mapper);
}

/// Reads values of [T] from JSON yourself, like a Jackson
/// `JsonDeserializer`; register it with `ObjectMapper(deserializers: [...])`
/// or as a bean.
///
/// ```dart
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
  /// Const base constructor.
  const JsonDeserializer();

  /// Whether this deserializer creates values of [S] (`T` or `T?`).
  bool handles<S>() => S == T || (<S>[] is List<T?> && <T?>[] is List<S>);

  /// A [T] from the non-null decoded [json] (a string, number, bool, list
  /// or map). [mapper] reads nested values.
  T deserialize(Object json, ObjectMapper mapper);
}

/// A set of serializers and deserializers, like a Jackson `SimpleModule`.
/// In a Spring Boot application every `JsonModule` bean is added to the
/// `ObjectMapper` bean (as Boot registers Jackson `Module` beans).
///
/// ```dart
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
  /// A module with [serializers] and [deserializers].
  const JsonModule({
    this.serializers = const [],
    this.deserializers = const [],
  });

  /// Writers for values of particular types.
  final List<JsonSerializer<Object>> serializers;

  /// Readers for values of particular types.
  final List<JsonDeserializer<Object>> deserializers;
}
