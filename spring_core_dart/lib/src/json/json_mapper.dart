import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/json/annotations.dart';
import 'package:spring_core_dart/src/json/json_serializer.dart';
import 'package:spring_core_dart/src/json/naming.dart';
import 'package:spring_core_dart/src/json/object_mapper.dart';

/// An on/off setting of a mapper, for [JsonMapperBuilder.enable] /
/// [JsonMapperBuilder.disable] and [ObjectMapper.isEnabled] (Jackson's
/// `SerializationFeature`, `DeserializationFeature`, `DateTimeFeature` and
/// `MapperFeature`).
abstract interface class JsonFeature {
  /// Whether the feature is on unless configured.
  bool get enabledByDefault;
}

/// Writing features (Jackson's `SerializationFeature`).
enum SerializationFeature implements JsonFeature {
  /// Pretty-prints `writeValueAsString` (`INDENT_OUTPUT`).
  indentOutput(false);

  const SerializationFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// Reading features (Jackson's `DeserializationFeature`; the defaults are
/// Spring Boot's).
enum DeserializationFeature implements JsonFeature {
  /// JSON properties a class does not have are an error
  /// (`FAIL_ON_UNKNOWN_PROPERTIES`; off, as Spring Boot configures it).
  failOnUnknownProperties(false),

  /// A number with a fraction read into an `int` is truncated
  /// (`ACCEPT_FLOAT_AS_INT`).
  acceptFloatAsInt(true);

  const DeserializationFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// Date and duration features (Jackson 3's `DateTimeFeature`; Spring Boot
/// 4's `spring.jackson.datatype.datetime.*`).
enum DateTimeFeature implements JsonFeature {
  /// `DateTime` is written as a timestamp (`WRITE_DATES_AS_TIMESTAMPS`).
  writeDatesAsTimestamps(false),

  /// `Duration` is written as a number (`WRITE_DURATIONS_AS_TIMESTAMPS`).
  writeDurationsAsTimestamps(false),

  /// Timestamps are seconds with the fraction, not milliseconds
  /// (`WRITE_DATE_TIMESTAMPS_AS_NANOSECONDS`).
  writeDateTimestampsAsNanoseconds(true),

  /// Integer timestamps are read as seconds, not milliseconds
  /// (`READ_DATE_TIMESTAMPS_AS_NANOSECONDS`).
  readDateTimestampsAsNanoseconds(true);

  const DateTimeFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// Mapper-wide features (Jackson's `MapperFeature`).
enum MapperFeature implements JsonFeature {
  /// Properties are written sorted by name (`SORT_PROPERTIES_ALPHABETICALLY`,
  /// on in Jackson 3).
  sortPropertiesAlphabetically(true),

  /// Properties without `@JsonView` are in every view
  /// (`DEFAULT_VIEW_INCLUSION`, off in Jackson 3).
  defaultViewInclusion(false);

  const MapperFeature(this.enabledByDefault);

  @override
  final bool enabledByDefault;
}

/// The JSON [ObjectMapper], like Jackson 3's `JsonMapper`; built with
/// [JsonMapper.builder] (or the constructor), changed with `rebuild()`.
///
/// ```dart
/// final mapper = JsonMapper.builder()
///     .propertyNamingStrategy(PropertyNamingStrategy.snakeCase)
///     .enable(DeserializationFeature.failOnUnknownProperties)
///     .addModule(moneyModule)
///     .build();
/// final strict = mapper.rebuild().disable(MapperFeature.sortPropertiesAlphabetically).build();
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
  /// A mapper configured like [ObjectMapper.new].
  JsonMapper({
    super.introspector,
    super.namingStrategy,
    super.inclusion,
    super.failOnUnknownProperties,
    super.acceptFloatAsInt,
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

  /// A builder with the defaults.
  static JsonMapperBuilder builder() => JsonMapperBuilder();
}

/// Configures a [JsonMapper] (Jackson 3's `JsonMapper.Builder`); from
/// [JsonMapper.builder] or `ObjectMapper.rebuild()`.
final class JsonMapperBuilder {
  BeanIntrospector? _introspector;
  PropertyNamingStrategy _naming = PropertyNamingStrategy.lowerCamelCase;
  JsonInclusion _inclusion = JsonInclusion.always;
  String? _timeZone;
  final _features = <JsonFeature, bool>{};
  final _serializers = <JsonSerializer<Object>>[];
  final _deserializers = <JsonDeserializer<Object>>[];

  /// Reads class metadata from [introspector].
  JsonMapperBuilder introspector(BeanIntrospector introspector) {
    _introspector = introspector;
    return this;
  }

  /// Names properties with [strategy] (`PropertyNamingStrategies`).
  JsonMapperBuilder propertyNamingStrategy(PropertyNamingStrategy strategy) {
    _naming = strategy;
    return this;
  }

  /// Which property values are written unless `@JsonInclude` says
  /// (`changeDefaultPropertyInclusion`).
  JsonMapperBuilder defaultPropertyInclusion(JsonInclusion inclusion) {
    _inclusion = inclusion;
    return this;
  }

  /// The time zone dates are written and read in: `UTC`, `Z` or a fixed
  /// offset; `null` for none.
  JsonMapperBuilder defaultTimeZone(String? timeZone) {
    _timeZone = timeZone;
    return this;
  }

  /// Turns [feature] on.
  JsonMapperBuilder enable(JsonFeature feature) => configure(feature, true);

  /// Turns [feature] off.
  JsonMapperBuilder disable(JsonFeature feature) => configure(feature, false);

  /// Turns [feature] on or off.
  JsonMapperBuilder configure(JsonFeature feature, bool enabled) {
    _features[feature] = enabled;
    return this;
  }

  /// Whether [feature] is on in this builder.
  bool isEnabled(JsonFeature feature) =>
      _features[feature] ?? feature.enabledByDefault;

  /// Adds a writer, tried in the order added.
  JsonMapperBuilder addSerializer(JsonSerializer<Object> serializer) {
    _serializers.add(serializer);
    return this;
  }

  /// Adds writers.
  JsonMapperBuilder addSerializers(
    Iterable<JsonSerializer<Object>> serializers,
  ) {
    _serializers.addAll(serializers);
    return this;
  }

  /// Adds a reader, tried in the order added.
  JsonMapperBuilder addDeserializer(JsonDeserializer<Object> deserializer) {
    _deserializers.add(deserializer);
    return this;
  }

  /// Adds readers.
  JsonMapperBuilder addDeserializers(
    Iterable<JsonDeserializer<Object>> deserializers,
  ) {
    _deserializers.addAll(deserializers);
    return this;
  }

  /// Adds the serializers and deserializers of [module].
  JsonMapperBuilder addModule(JsonModule module) => this
    ..addSerializers(module.serializers)
    ..addDeserializers(module.deserializers);

  /// Adds every one of [modules].
  JsonMapperBuilder addModules(Iterable<JsonModule> modules) {
    modules.forEach(addModule);
    return this;
  }

  /// The mapper.
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
