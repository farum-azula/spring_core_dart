import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/json/annotations.dart';
import 'package:spring_core_dart/src/json/json_serializer.dart';
import 'package:spring_core_dart/src/json/naming.dart';
import 'package:spring_core_dart/src/json/object_mapper.dart';

/// An on/off setting of a mapper, named after Jackson's feature flags.
///
/// The four enums that implement it ([SerializationFeature],
/// [DeserializationFeature], [DateTimeFeature], [MapperFeature]) let code
/// written against Jackson's style configure a mapper with
/// [JsonMapperBuilder.enable] / [JsonMapperBuilder.disable] and ask
/// [ObjectMapper.isEnabled]. Each flag is also a named parameter of the
/// `ObjectMapper` constructor; in Spring Boot the `spring.jackson.*`
/// properties set them.
///
/// ```dart
/// // Reject unknown properties in this mapper.
/// final strict = JsonMapper.builder()
///     .enable(DeserializationFeature.failOnUnknownProperties)
///     .build();
/// ```
abstract interface class JsonFeature {
  /// Whether the feature is on when nobody configured it.
  bool get enabledByDefault;
}

/// On/off settings for writing JSON, named after Jackson's
/// `SerializationFeature`.
enum SerializationFeature implements JsonFeature {
  /// Pretty-prints the output of `writeValueAsString`, for logs or files
  /// people read (`INDENT_OUTPUT`). Off by default.
  indentOutput(false);

  SerializationFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// On/off settings for reading JSON, named after Jackson's
/// `DeserializationFeature`; the defaults are Spring Boot's.
enum DeserializationFeature implements JsonFeature {
  /// A JSON property the class does not have is an error instead of
  /// being skipped (`FAIL_ON_UNKNOWN_PROPERTIES`). Off, as Spring Boot
  /// configures it, so clients can send extra fields.
  failOnUnknownProperties(false),

  /// A number with a fraction read into an `int` is truncated; off makes
  /// it an error (`ACCEPT_FLOAT_AS_INT`). On by default.
  acceptFloatAsInt(true),

  /// A JSON `null` (or a missing constructor parameter) for a non-nullable
  /// `int`, `double`, `num` or `bool` is an error
  /// (`FAIL_ON_NULL_FOR_PRIMITIVES`). On, like Jackson 3; off reads it as
  /// `0` / `false`.
  failOnNullForPrimitives(true);

  DeserializationFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// On/off settings for writing and reading `DateTime` and `Duration`,
/// named after Jackson 3's `DateTimeFeature` (Spring Boot 4's
/// `spring.jackson.datatype.datetime.*`).
enum DateTimeFeature implements JsonFeature {
  /// `DateTime` is written as a number instead of ISO-8601 text
  /// (`WRITE_DATES_AS_TIMESTAMPS`). Off by default.
  writeDatesAsTimestamps(false),

  /// `Duration` is written as a number instead of ISO-8601 text such as
  /// `PT1M30S` (`WRITE_DURATIONS_AS_TIMESTAMPS`). Off by default.
  writeDurationsAsTimestamps(false),

  /// Numbers written for dates and durations are seconds with the
  /// fraction, not milliseconds (`WRITE_DATE_TIMESTAMPS_AS_NANOSECONDS`).
  /// On by default, like Jackson 3.
  writeDateTimestampsAsNanoseconds(true),

  /// Integer timestamps are read as seconds, not milliseconds; a number
  /// with a fraction is seconds either way
  /// (`READ_DATE_TIMESTAMPS_AS_NANOSECONDS`). On by default.
  readDateTimestampsAsNanoseconds(true);

  DateTimeFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// On/off settings that change how the mapper sees classes, named after
/// Jackson's `MapperFeature`.
enum MapperFeature implements JsonFeature {
  /// Properties are written sorted by JSON name, constructor parameters
  /// first; off writes them in declaration order
  /// (`SORT_PROPERTIES_ALPHABETICALLY`). On, like Jackson 3.
  sortPropertiesAlphabetically(true),

  /// Properties without `@JsonView` are written and read under every
  /// view; off leaves them out when a view is active
  /// (`DEFAULT_VIEW_INCLUSION`). Off, like Jackson 3.
  defaultViewInclusion(false);

  MapperFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// An [ObjectMapper] with a builder, for configuring a mapper step by step
/// in Jackson 3's style.
///
/// It behaves exactly like an [ObjectMapper]; the difference is the way
/// in. [JsonMapper.builder] starts from the defaults, and
/// `ObjectMapper.rebuild()` from an existing mapper's settings, so you can
/// derive a variant (stricter reading, other naming) without changing the
/// original, which stays immutable. Use it when you need a mapper besides
/// the application's, or code ported from Jackson. In Spring Boot, inject
/// the auto-configured `ObjectMapper` instead.
///
/// ```dart
/// // A snake_case mapper for one external API, and a variant of it that
/// // keeps declaration order.
/// final mapper = JsonMapper.builder()
///     .propertyNamingStrategy(PropertyNamingStrategy.snakeCase)
///     .enable(DeserializationFeature.failOnUnknownProperties)
///     .addModule(moneyModule)
///     .build();
/// final declarationOrder = mapper
///     .rebuild()
///     .disable(MapperFeature.sortPropertiesAlphabetically)
///     .build();
/// ```
///
/// Spring (Java):
/// ```java
/// JsonMapper mapper = JsonMapper.builder()
///     .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
///     .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
///     .addModule(moneyModule)
///     .build();
/// ```
class JsonMapper extends ObjectMapper {
  /// A mapper with the given settings; each parameter is described on
  /// [ObjectMapper.new].
  JsonMapper({
    super.introspector,
    super.namingStrategy,
    super.inclusion,
    super.failOnUnknownProperties,
    super.acceptFloatAsInt,
    super.failOnNullForPrimitives,
    super.writeDatesAsTimestamps,
    super.writeDurationsAsTimestamps,
    super.writeDateTimestampsAsNanoseconds,
    super.readDateTimestampsAsNanoseconds,
    super.timeZone,
    super.indentOutput,
    super.sortPropertiesAlphabetically,
    super.defaultViewInclusion,
    super.serializers,
    super.deserializers,
    super.modules,
  });

  /// Returns a builder that starts from the default settings.
  static JsonMapperBuilder builder() => JsonMapperBuilder();
}

/// Collects settings, serializers and modules, then creates a [JsonMapper]
/// with [build].
///
/// Get one from [JsonMapper.builder] (defaults) or
/// `ObjectMapper.rebuild()` (an existing mapper's settings). Every method
/// returns the builder, so calls chain. A builder can [build] several
/// mappers. It mirrors Jackson 3's `JsonMapper.Builder`.
///
/// ```dart
/// // The application's mapper, but failing on unknown properties.
/// final strict = mapper.rebuild()
///     .enable(DeserializationFeature.failOnUnknownProperties)
///     .build();
/// ```
final class JsonMapperBuilder {
  BeanIntrospector? _introspector;
  PropertyNamingStrategy _naming = PropertyNamingStrategy.lowerCamelCase;
  JsonInclusion _inclusion = JsonInclusion.always;
  String? _timeZone;
  final _features = <JsonFeature, bool>{};
  final _serializers = <JsonSerializer<Object>>[];
  final _deserializers = <JsonDeserializer<Object>>[];

  /// Reads class metadata from [introspector] instead of
  /// `BeanIntrospector.shared`, for example the context's.
  JsonMapperBuilder introspector(BeanIntrospector introspector) {
    _introspector = introspector;
    return this;
  }

  /// Turns Dart property names into JSON names with [strategy], for
  /// every class without `@JsonNaming`.
  JsonMapperBuilder propertyNamingStrategy(PropertyNamingStrategy strategy) {
    _naming = strategy;
    return this;
  }

  /// Which property values are written, for properties and classes
  /// without `@JsonInclude` (Jackson's `changeDefaultPropertyInclusion`);
  /// [JsonInclusion.always] by default.
  JsonMapperBuilder defaultPropertyInclusion(JsonInclusion inclusion) {
    _inclusion = inclusion;
    return this;
  }

  /// The time zone dates are written in and dates without an offset are
  /// read in: `UTC`, `Z` or a fixed offset such as `+02:00`; `null` (the
  /// default) keeps each `DateTime`'s own zone.
  JsonMapperBuilder defaultTimeZone(String? timeZone) {
    _timeZone = timeZone;
    return this;
  }

  /// Turns [feature] on.
  JsonMapperBuilder enable(JsonFeature feature) => configure(feature, true);

  /// Turns [feature] off.
  JsonMapperBuilder disable(JsonFeature feature) => configure(feature, false);

  /// Turns [feature] on when [enabled], else off.
  JsonMapperBuilder configure(JsonFeature feature, bool enabled) {
    _features[feature] = enabled;
    return this;
  }

  /// Whether [feature] is on in this builder: as configured, else its
  /// default.
  bool isEnabled(JsonFeature feature) =>
      _features[feature] ?? feature.enabledByDefault;

  /// Adds [serializer]; serializers are tried in the order added.
  JsonMapperBuilder addSerializer(JsonSerializer<Object> serializer) {
    _serializers.add(serializer);
    return this;
  }

  /// Adds [serializers], after those added before.
  JsonMapperBuilder addSerializers(
    Iterable<JsonSerializer<Object>> serializers,
  ) {
    _serializers.addAll(serializers);
    return this;
  }

  /// Adds [deserializer]; deserializers are tried in the order added.
  JsonMapperBuilder addDeserializer(JsonDeserializer<Object> deserializer) {
    _deserializers.add(deserializer);
    return this;
  }

  /// Adds [deserializers], after those added before.
  JsonMapperBuilder addDeserializers(
    Iterable<JsonDeserializer<Object>> deserializers,
  ) {
    _deserializers.addAll(deserializers);
    return this;
  }

  /// Adds the serializers and deserializers of [module], after those
  /// added before.
  JsonMapperBuilder addModule(JsonModule module) => this
    ..addSerializers(module.serializers)
    ..addDeserializers(module.deserializers);

  /// Adds each of [modules], in order.
  JsonMapperBuilder addModules(Iterable<JsonModule> modules) {
    modules.forEach(addModule);
    return this;
  }

  /// Creates a mapper with the settings collected so far.
  JsonMapper build() => JsonMapper(
    introspector: _introspector,
    namingStrategy: _naming,
    inclusion: _inclusion,
    timeZone: _timeZone,
    indentOutput: isEnabled(SerializationFeature.indentOutput),
    failOnUnknownProperties: isEnabled(
      DeserializationFeature.failOnUnknownProperties,
    ),
    acceptFloatAsInt: isEnabled(DeserializationFeature.acceptFloatAsInt),
    failOnNullForPrimitives: isEnabled(
      DeserializationFeature.failOnNullForPrimitives,
    ),
    writeDatesAsTimestamps: isEnabled(DateTimeFeature.writeDatesAsTimestamps),
    writeDurationsAsTimestamps: isEnabled(
      DateTimeFeature.writeDurationsAsTimestamps,
    ),
    writeDateTimestampsAsNanoseconds: isEnabled(
      DateTimeFeature.writeDateTimestampsAsNanoseconds,
    ),
    readDateTimestampsAsNanoseconds: isEnabled(
      DateTimeFeature.readDateTimestampsAsNanoseconds,
    ),
    sortPropertiesAlphabetically: isEnabled(
      MapperFeature.sortPropertiesAlphabetically,
    ),
    defaultViewInclusion: isEnabled(MapperFeature.defaultViewInclusion),
    serializers: _serializers,
    deserializers: _deserializers,
  );
}
