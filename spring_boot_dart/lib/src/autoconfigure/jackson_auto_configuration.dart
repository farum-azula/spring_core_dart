import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#JacksonAutoConfiguration';
const _log = SpringLog('spring_boot_dart.JacksonAutoConfiguration');

/// Registers a `jacksonJsonMapper` bean (Boot 4's name) built from `spring.jackson.*` when the
/// application declares no `ObjectMapper`, like Spring Boot's
/// `JacksonAutoConfiguration`. It reads the classes of the context's
/// `BeanIntrospector` and adds every `JsonSerializer` / `JsonDeserializer`
/// bean (Boot's `@JsonComponent`) and every `JsonModule` bean, then lets
/// the [JsonMapperBuilderCustomizer] beans change the builder (in order).
///
/// ```properties
/// # lib/resources/application.properties
/// spring.jackson.property-naming-strategy=SNAKE_CASE
/// spring.jackson.default-property-inclusion=non_null
/// spring.jackson.deserialization.fail-on-unknown-properties=true
/// spring.jackson.datatype.datetime.write-dates-as-timestamps=true
/// spring.jackson.serialization.indent-output=true
/// spring.jackson.time-zone=UTC
/// spring.jackson.mapper.sort-properties-alphabetically=false
/// ```
final jacksonAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<ObjectMapper>(
    name: 'jacksonJsonMapper',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'jacksonJsonMapper',
    source: _source,
    conditions: const [
      ConditionGroup(_source, [ConditionalOnMissingBean(ObjectMapper)]),
    ],
    create: (r) {
      final builder = jsonMapperBuilderFromProperties(
        r.dependency<Environment>(),
        introspector: r.dependency<BeanIntrospector>(),
        serializers:
            r.optionalDependencyList<JsonSerializer<Object>>() ?? const [],
        deserializers:
            r.optionalDependencyList<JsonDeserializer<Object>>() ?? const [],
        modules: r.optionalDependencyList<JsonModule>() ?? const [],
      );
      for (final customizer
          in r.optionalDependencyList<JsonMapperBuilderCustomizer>() ??
              const <JsonMapperBuilderCustomizer>[]) {
        customizer.customize(builder);
      }
      return builder.build();
    },
  ),
];

/// Changes the builder of the auto-configured mapper, like Spring Boot 4's
/// `JsonMapperBuilderCustomizer`: declare beans of it to keep the
/// `spring.jackson.*` properties and adjust the rest. They run after the
/// properties are applied, in `@Order` order.
///
/// ```dart
/// @Bean()
/// JsonMapperBuilderCustomizer snakeCase() => JsonMapperBuilderCustomizer.of(
///   (builder) => builder.namingStrategy = PropertyNamingStrategy.snakeCase,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// JsonMapperBuilderCustomizer snakeCase() {
///   return builder -> builder.propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE);
/// }
/// ```
abstract interface class JsonMapperBuilderCustomizer {
  /// A customizer calling [customize].
  const factory JsonMapperBuilderCustomizer.of(
    void Function(JsonMapperBuilder builder) customize,
  ) = _FunctionCustomizer;

  /// Changes [builder].
  void customize(JsonMapperBuilder builder);
}

final class _FunctionCustomizer implements JsonMapperBuilderCustomizer {
  const _FunctionCustomizer(this._customize);

  final void Function(JsonMapperBuilder builder) _customize;

  @override
  void customize(JsonMapperBuilder builder) => _customize(builder);
}

/// An [ObjectMapper] configured from `spring.jackson.*` of [environment]
/// (what the auto-configured bean is); [introspector], [serializers],
/// [deserializers] and [modules] are passed on.
///
/// | Property | Default |
/// |---|---|
/// | `spring.jackson.property-naming-strategy` | `LOWER_CAMEL_CASE` |
/// | `spring.jackson.default-property-inclusion` | `always` (or `non_null`, `non_absent`, `non_empty`, `non_default`) |
/// | `spring.jackson.deserialization.fail-on-unknown-properties` | `false` |
/// | `spring.jackson.deserialization.accept-float-as-int` | `true` |
/// | `spring.jackson.deserialization.fail-on-null-for-primitives` | `true` (Jackson 3; `false` reads `null` as `0` / `false`) |
/// | `spring.jackson.datatype.datetime.write-dates-as-timestamps` (Boot 4) or `spring.jackson.serialization.write-dates-as-timestamps` (Boot 3; the former wins) | `false` |
/// | `spring.jackson.datatype.datetime.write-durations-as-timestamps` (or `serialization.`) | `false` |
/// | `spring.jackson.datatype.datetime.write-date-timestamps-as-nanoseconds` (or `serialization.`) | `true` (seconds with the fraction; `false`: milliseconds) |
/// | `spring.jackson.datatype.datetime.read-date-timestamps-as-nanoseconds` (or `deserialization.`) | `true` (integers are seconds; `false`: milliseconds) |
/// | `spring.jackson.serialization.indent-output` | `false` |
/// | `spring.jackson.mapper.sort-properties-alphabetically` | `true` (properties sorted by name, constructor parameters first; `false`: declaration order) |
/// | `spring.jackson.mapper.default-view-inclusion` | `false` |
/// | `spring.jackson.time-zone` | none (each date in its own zone, read in UTC); `UTC` or a fixed offset such as `+02:00` |
///
/// Any other `spring.jackson.*` key is logged as a warning and ignored (Boot
/// binds the keys of Jackson's features, which this mapper does not have).
/// A named time zone (`Europe/Berlin`) throws an [ArgumentError]: Dart has no
/// time zone database, so only `UTC` / `Z` and fixed offsets work.
ObjectMapper objectMapperFromProperties(
  Environment environment, {
  BeanIntrospector? introspector,
  Iterable<JsonSerializer<Object>> serializers = const [],
  Iterable<JsonDeserializer<Object>> deserializers = const [],
  Iterable<JsonModule> modules = const [],
}) => jsonMapperBuilderFromProperties(
  environment,
  introspector: introspector,
  serializers: serializers,
  deserializers: deserializers,
  modules: modules,
).build();

/// The [JsonMapperBuilder] of [objectMapperFromProperties], before it is
/// built (what [JsonMapperBuilderCustomizer]s receive).
JsonMapperBuilder jsonMapperBuilderFromProperties(
  Environment environment, {
  BeanIntrospector? introspector,
  Iterable<JsonSerializer<Object>> serializers = const [],
  Iterable<JsonDeserializer<Object>> deserializers = const [],
  Iterable<JsonModule> modules = const [],
}) {
  _warnUnsupportedKeys(environment);
  // The first of [keys] that is set (the Boot 4 key before the Boot 3 one),
  // else the feature's default.
  bool flag(JsonFeature feature, List<String> keys) {
    for (final key in keys) {
      if (environment.getProperty(key) case final value?) {
        return value.trim().toLowerCase() == 'true';
      }
    }
    return feature.enabledByDefault;
  }

  final naming = environment.getProperty(
    'spring.jackson.property-naming-strategy',
  );
  final inclusion = environment.getProperty(
    'spring.jackson.default-property-inclusion',
  );
  final builder = JsonMapperBuilder()
    ..propertyNamingStrategy(
      naming == null
          ? PropertyNamingStrategy.lowerCamelCase
          : PropertyNamingStrategy.parse(naming),
    )
    ..defaultPropertyInclusion(
      inclusion == null ? JsonInclusion.always : _inclusion(inclusion),
    )
    ..defaultTimeZone(environment.getProperty('spring.jackson.time-zone'))
    ..addSerializers(serializers)
    ..addDeserializers(deserializers)
    ..addModules(modules);
  if (introspector != null) {
    builder.introspector(introspector);
  }
  void set(JsonFeature feature, List<String> keys) =>
      builder.configure(feature, flag(feature, keys));
  set(DeserializationFeature.failOnUnknownProperties, const [
    'spring.jackson.deserialization.fail-on-unknown-properties',
  ]);
  set(DeserializationFeature.acceptFloatAsInt, const [
    'spring.jackson.deserialization.accept-float-as-int',
  ]);
  set(DeserializationFeature.failOnNullForPrimitives, const [
    'spring.jackson.deserialization.fail-on-null-for-primitives',
  ]);
  set(DateTimeFeature.writeDatesAsTimestamps, const [
    '$_dateTime.write-dates-as-timestamps',
    'spring.jackson.serialization.write-dates-as-timestamps',
  ]);
  set(DateTimeFeature.writeDurationsAsTimestamps, const [
    '$_dateTime.write-durations-as-timestamps',
    'spring.jackson.serialization.write-durations-as-timestamps',
  ]);
  set(DateTimeFeature.writeDateTimestampsAsNanoseconds, const [
    '$_dateTime.write-date-timestamps-as-nanoseconds',
    'spring.jackson.serialization.write-date-timestamps-as-nanoseconds',
  ]);
  set(DateTimeFeature.readDateTimestampsAsNanoseconds, const [
    '$_dateTime.read-date-timestamps-as-nanoseconds',
    'spring.jackson.deserialization.read-date-timestamps-as-nanoseconds',
  ]);
  set(SerializationFeature.indentOutput, const [
    'spring.jackson.serialization.indent-output',
  ]);
  set(MapperFeature.sortPropertiesAlphabetically, const [
    'spring.jackson.mapper.sort-properties-alphabetically',
  ]);
  set(MapperFeature.defaultViewInclusion, const [
    'spring.jackson.mapper.default-view-inclusion',
  ]);
  return builder;
}

JsonInclusion _inclusion(String value) =>
    switch (value.replaceAll(RegExp('[-_ ]'), '').toLowerCase()) {
      'always' => JsonInclusion.always,
      'nonnull' => JsonInclusion.nonNull,
      'nonabsent' => JsonInclusion.nonAbsent,
      'nonempty' => JsonInclusion.nonEmpty,
      'nondefault' => JsonInclusion.nonDefault,
      _ => throw ArgumentError.value(
        value,
        'spring.jackson.default-property-inclusion',
        'one of always, non_null, non_absent, non_empty, non_default',
      ),
    };

const _dateTime = 'spring.jackson.datatype.datetime';

// Keys read above, compared the way Boot binds them (case, `-` and `_`
// ignored).
const _supportedKeys = {
  'spring.jackson.property-naming-strategy',
  'spring.jackson.default-property-inclusion',
  'spring.jackson.deserialization.fail-on-unknown-properties',
  'spring.jackson.deserialization.accept-float-as-int',
  'spring.jackson.deserialization.fail-on-null-for-primitives',
  'spring.jackson.serialization.write-dates-as-timestamps',
  'spring.jackson.serialization.write-durations-as-timestamps',
  'spring.jackson.serialization.write-date-timestamps-as-nanoseconds',
  'spring.jackson.deserialization.read-date-timestamps-as-nanoseconds',
  '$_dateTime.write-dates-as-timestamps',
  '$_dateTime.write-durations-as-timestamps',
  '$_dateTime.write-date-timestamps-as-nanoseconds',
  '$_dateTime.read-date-timestamps-as-nanoseconds',
  'spring.jackson.serialization.indent-output',
  'spring.jackson.mapper.sort-properties-alphabetically',
  'spring.jackson.mapper.default-view-inclusion',
  'spring.jackson.time-zone',
};

String _canonical(String key) =>
    key.replaceAll(RegExp('[-_]'), '').toLowerCase();

// Boot binds `spring.jackson.*` leniently; a key this mapper does not read
// would otherwise be ignored without a trace.
void _warnUnsupportedKeys(Environment environment) {
  if (environment is! ConfigurableEnvironment) {
    return;
  }
  final supported = {for (final key in _supportedKeys) _canonical(key)};
  final reported = <String>{};
  for (final source in environment.propertySources) {
    if (source is! EnumerablePropertySource<Object>) {
      continue;
    }
    for (final key in source.propertyNames) {
      if (key.startsWith('spring.jackson.') &&
          !supported.contains(_canonical(key)) &&
          reported.add(_canonical(key))) {
        _log.warning(
          "Ignoring unsupported property '$key': spring.jackson.* supports "
          '${_supportedKeys.join(', ')}.',
        );
      }
    }
  }
}
