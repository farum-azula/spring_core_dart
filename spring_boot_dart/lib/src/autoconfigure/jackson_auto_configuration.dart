// Rows of Markdown tables and sample log lines in documentation cannot wrap.
// ignore_for_file: lines_longer_than_80_chars
import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_boot_dart/src/properties/boot_properties.dart';
import 'package:spring_boot_dart/src/properties/properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#JacksonAutoConfiguration';
const _log = SpringLog('spring_boot_dart.JacksonAutoConfiguration');

/// The `ObjectMapper` bean every application gets for reading and writing
/// JSON, set up from the `spring.json.*` properties.
///
/// Any bean can inject `ObjectMapper` and convert its `@Introspected`
/// classes to and from JSON; web starters use the same bean for request
/// and response bodies. The bean is named `jacksonJsonMapper` (Spring Boot
/// 4's name). It knows every class of the context's `BeanIntrospector`,
/// and adds every `JsonSerializer` / `JsonDeserializer` bean (Spring
/// Boot's `@JsonComponent`) and every `JsonModule` bean. Then the
/// [JsonMapperBuilderCustomizer] beans adjust it, in `@Order` order.
///
/// It is left out when the application declares its own `ObjectMapper`
/// bean, or with `spring.autoconfigure.exclude=JacksonAutoConfiguration`.
/// [objectMapperFromProperties] lists the properties.
///
/// ```properties
/// # lib/resources/application.properties
/// spring.json.property-naming-strategy=SNAKE_CASE
/// spring.json.default-property-inclusion=non_null
/// spring.json.deserialization.fail-on-unknown-properties=true
/// spring.json.datatype.datetime.write-dates-as-timestamps=true
/// spring.json.serialization.indent-output=true
/// spring.json.time-zone=UTC
/// spring.json.mapper.sort-properties-alphabetically=false
/// ```
///
/// Spring (Java): `JacksonAutoConfiguration`.
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

/// A bean that adjusts the auto-configured `ObjectMapper` while keeping
/// everything else about it.
///
/// Declaring your own `ObjectMapper` replaces the auto-configured one
/// completely, `spring.json.*` properties included. A customizer
/// instead changes one thing on the builder: a setting that has no
/// property, or a module that should only be added in some cases.
/// Customizers run after the properties are applied, in `@Order` order,
/// so they win over the properties.
///
/// ```dart
/// // The partner API expects snake_case, whatever the properties say.
/// @Bean()
/// JsonMapperBuilderCustomizer snakeCase() => JsonMapperBuilderCustomizer.of(
///   (builder) =>
///       builder.propertyNamingStrategy(PropertyNamingStrategy.snakeCase),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// JsonMapperBuilderCustomizer snakeCase() {
///   return builder -> builder.propertyNamingStrategy(
///       PropertyNamingStrategies.SNAKE_CASE);
/// }
/// ```
abstract interface class JsonMapperBuilderCustomizer {
  /// A customizer that runs [customize]; the short form for a `@Bean`
  /// method.
  const factory JsonMapperBuilderCustomizer.of(
    void Function(JsonMapperBuilder builder) customize,
  ) = _FunctionCustomizer;

  /// Changes [builder] before the mapper is built. Called once, when the
  /// `ObjectMapper` bean is created.
  void customize(JsonMapperBuilder builder);
}

final class _FunctionCustomizer implements JsonMapperBuilderCustomizer {
  const _FunctionCustomizer(this._customize);

  final void Function(JsonMapperBuilder builder) _customize;

  @override
  void customize(JsonMapperBuilder builder) => _customize(builder);
}

/// Builds an [ObjectMapper] from the `spring.json.*` properties of
/// [environment], the same way the auto-configured bean is built.
///
/// For code that needs a mapper outside the context: a command-line tool
/// without beans, a test, or a second mapper with other settings.
/// [introspector] describes the classes to map (without it the mapper
/// uses its default); [serializers], [deserializers] and [modules] are
/// added to the mapper.
///
/// ```dart
/// // In a test: the mapper the application would use.
/// final mapper = objectMapperFromProperties(
///   StandardEnvironment()..propertySources.addFirst(
///     MapPropertySource('test', {
///       'spring.json.property-naming-strategy': 'SNAKE_CASE',
///     }),
///   ),
/// );
/// ```
///
/// The properties:
///
/// | Property | Default |
/// |---|---|
/// | `spring.json.property-naming-strategy` | `LOWER_CAMEL_CASE` |
/// | `spring.json.default-property-inclusion` | `always` (or `non_null`, `non_absent`, `non_empty`, `non_default`) |
/// | `spring.json.deserialization.fail-on-unknown-properties` | `false` |
/// | `spring.json.deserialization.accept-float-as-int` | `true` |
/// | `spring.json.deserialization.fail-on-null-for-primitives` | `true` (Jackson 3; `false` reads `null` as `0` / `false`) |
/// | `spring.json.datatype.datetime.write-dates-as-timestamps` (Boot 4) or `spring.json.serialization.write-dates-as-timestamps` (Boot 3; the former wins) | `false` |
/// | `spring.json.datatype.datetime.write-durations-as-timestamps` (or `serialization.`) | `false` |
/// | `spring.json.datatype.datetime.write-date-timestamps-as-nanoseconds` (or `serialization.`) | `true` (seconds with the fraction; `false`: milliseconds) |
/// | `spring.json.datatype.datetime.read-date-timestamps-as-nanoseconds` (or `deserialization.`) | `true` (integers are seconds; `false`: milliseconds) |
/// | `spring.json.serialization.indent-output` | `false` |
/// | `spring.json.mapper.sort-properties-alphabetically` | `true` (properties sorted by name, constructor parameters first; `false`: declaration order) |
/// | `spring.json.mapper.default-view-inclusion` | `false` |
/// | `spring.json.time-zone` | none (each date in its own zone, read in UTC); `UTC` or a fixed offset such as `+02:00` |
///
/// Any other `spring.json.*` key is logged as a warning and ignored:
/// Spring Boot binds every Jackson feature flag, and most of them do not
/// exist in this mapper. A named time zone (`Europe/Berlin`) throws an
/// [ArgumentError]: Dart has no time zone database, so only `UTC` / `Z`
/// and fixed offsets work. An unknown naming strategy or inclusion throws
/// too. The properties are bound like any `@ConfigurationProperties`
/// class: a value that is not a boolean (or not a known inclusion) fails
/// with a `ConfigurationPropertiesBindException`.
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

/// The [JsonMapperBuilder] that [objectMapperFromProperties] would build,
/// with the `spring.json.*` properties of [environment] applied.
///
/// Use it to change a setting before building the mapper; the
/// auto-configuration hands this builder to the
/// [JsonMapperBuilderCustomizer] beans. The parameters are those of
/// [objectMapperFromProperties].
JsonMapperBuilder jsonMapperBuilderFromProperties(
  Environment environment, {
  BeanIntrospector? introspector,
  Iterable<JsonSerializer<Object>> serializers = const [],
  Iterable<JsonDeserializer<Object>> deserializers = const [],
  Iterable<JsonModule> modules = const [],
}) {
  _warnUnsupportedKeys(environment);
  final json = bindBootProperties(environment, JsonProperties());
  final builder = JsonMapperBuilder()
    ..propertyNamingStrategy(
      PropertyNamingStrategy.parse(json.propertyNamingStrategy),
    )
    ..defaultPropertyInclusion(json.defaultPropertyInclusion)
    ..defaultTimeZone(json.timeZone)
    ..addSerializers(serializers)
    ..addDeserializers(deserializers)
    ..addModules(modules);
  if (introspector != null) {
    builder.introspector(introspector);
  }
  final deserialization = json.deserialization;
  final serialization = json.serialization;
  final dateTime = json.datatype.datetime;
  builder
    ..configure(
      DeserializationFeature.failOnUnknownProperties,
      deserialization.failOnUnknownProperties,
    )
    ..configure(
      DeserializationFeature.acceptFloatAsInt,
      deserialization.acceptFloatAsInt,
    )
    ..configure(
      DeserializationFeature.failOnNullForPrimitives,
      deserialization.failOnNullForPrimitives,
    )
    // The Boot 4 key (`datatype.datetime`) wins over the Boot 3 one.
    ..configure(
      DateTimeFeature.writeDatesAsTimestamps,
      dateTime.writeDatesAsTimestamps ?? serialization.writeDatesAsTimestamps,
    )
    ..configure(
      DateTimeFeature.writeDurationsAsTimestamps,
      dateTime.writeDurationsAsTimestamps ??
          serialization.writeDurationsAsTimestamps,
    )
    ..configure(
      DateTimeFeature.writeDateTimestampsAsNanoseconds,
      dateTime.writeDateTimestampsAsNanoseconds ??
          serialization.writeDateTimestampsAsNanoseconds,
    )
    ..configure(
      DateTimeFeature.readDateTimestampsAsNanoseconds,
      dateTime.readDateTimestampsAsNanoseconds ??
          deserialization.readDateTimestampsAsNanoseconds,
    )
    ..configure(SerializationFeature.indentOutput, serialization.indentOutput)
    ..configure(
      MapperFeature.sortPropertiesAlphabetically,
      json.mapper.sortPropertiesAlphabetically,
    )
    ..configure(
      MapperFeature.defaultViewInclusion,
      json.mapper.defaultViewInclusion,
    );
  return builder;
}

String _canonical(String key) =>
    key.replaceAll(RegExp('[-_]'), '').toLowerCase();

// Boot binds `spring.json.*` leniently; a key this mapper does not read
// would otherwise be ignored without a trace.
void _warnUnsupportedKeys(Environment environment) {
  if (environment is! ConfigurableEnvironment) {
    return;
  }
  // The keys of the JsonProperties class: what the mapper reads.
  final keys = jsonPropertyKeys();
  final supported = {for (final key in keys) _canonical(key)};
  final reported = <String>{};
  for (final source in environment.propertySources) {
    if (source is! EnumerablePropertySource<Object>) {
      continue;
    }
    for (final key in source.propertyNames) {
      if (key.startsWith('spring.json.') &&
          !supported.contains(_canonical(key)) &&
          reported.add(_canonical(key))) {
        _log.warning(
          "Ignoring unsupported property '$key': spring.json.* supports "
          '${keys.join(', ')}.',
        );
      }
    }
  }
}
