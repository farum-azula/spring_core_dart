import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#JacksonAutoConfiguration';
const _log = SpringLog('spring_boot_dart.JacksonAutoConfiguration');

/// Registers a `jacksonJsonMapper` bean (Boot 4's name) built from `spring.jackson.*` when the
/// application declares no `ObjectMapper`, like Spring Boot's
/// `JacksonAutoConfiguration`. It reads the classes of the context's
/// `BeanIntrospector` and adds every `JsonSerializer` / `JsonDeserializer`
/// bean (Boot's `@JsonComponent`) and every `JsonModule` bean.
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
    source: _source,
    conditions: const [
      ConditionGroup(_source, [ConditionalOnMissingBean(ObjectMapper)]),
    ],
    create: (r) => objectMapperFromProperties(
      r.dependency<Environment>(),
      introspector: r.dependency<BeanIntrospector>(),
      serializers:
          r.optionalDependencyList<JsonSerializer<Object>>() ?? const [],
      deserializers:
          r.optionalDependencyList<JsonDeserializer<Object>>() ?? const [],
      modules: r.optionalDependencyList<JsonModule>() ?? const [],
    ),
  ),
];

/// An [ObjectMapper] configured from `spring.jackson.*` of [environment]
/// (what the auto-configured bean is); [introspector], [serializers],
/// [deserializers] and [modules] are passed on.
///
/// | Property | Default |
/// |---|---|
/// | `spring.jackson.property-naming-strategy` | `LOWER_CAMEL_CASE` |
/// | `spring.jackson.default-property-inclusion` | `always` |
/// | `spring.jackson.deserialization.fail-on-unknown-properties` | `false` |
/// | `spring.jackson.datatype.datetime.write-dates-as-timestamps` (Boot 4) or `spring.jackson.serialization.write-dates-as-timestamps` (Boot 3; the former wins) | `false` |
/// | `spring.jackson.serialization.indent-output` | `false` |
/// | `spring.jackson.mapper.sort-properties-alphabetically` | `true` (properties sorted by name, constructor parameters first; `false`: declaration order) |
/// | `spring.jackson.time-zone` | none (each date in its own zone); `UTC` or a fixed offset such as `+02:00` |
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
}) {
  _warnUnsupportedKeys(environment);
  bool flag(String key) =>
      (environment.getProperty(key) ?? 'false').trim().toLowerCase() == 'true';
  final naming = environment.getProperty(
    'spring.jackson.property-naming-strategy',
  );
  final inclusion = environment.getProperty(
    'spring.jackson.default-property-inclusion',
  );
  return ObjectMapper(
    introspector: introspector,
    namingStrategy: naming == null
        ? PropertyNamingStrategy.lowerCamelCase
        : PropertyNamingStrategy.parse(naming),
    inclusion: inclusion == null ? JsonInclusion.always : _inclusion(inclusion),
    failOnUnknownProperties: flag(
      'spring.jackson.deserialization.fail-on-unknown-properties',
    ),
    writeDatesAsTimestamps: flag(
      environment.containsProperty(_timestampsBoot4)
          ? _timestampsBoot4
          : 'spring.jackson.serialization.write-dates-as-timestamps',
    ),
    timeZone: environment.getProperty('spring.jackson.time-zone'),
    indentOutput: flag('spring.jackson.serialization.indent-output'),
    sortPropertiesAlphabetically:
        (environment.getProperty(
                  'spring.jackson.mapper.sort-properties-alphabetically',
                ) ??
                'true')
            .trim()
            .toLowerCase() !=
        'false',
    serializers: serializers,
    deserializers: deserializers,
    modules: modules,
  );
}

JsonInclusion _inclusion(String value) =>
    switch (value.replaceAll(RegExp('[-_ ]'), '').toLowerCase()) {
      'always' => JsonInclusion.always,
      'nonnull' || 'nonabsent' => JsonInclusion.nonNull,
      'nonempty' => JsonInclusion.nonEmpty,
      _ => throw ArgumentError.value(
        value,
        'spring.jackson.default-property-inclusion',
        'one of always, non_null, non_empty',
      ),
    };

const _timestampsBoot4 =
    'spring.jackson.datatype.datetime.write-dates-as-timestamps';

// Keys read above, compared the way Boot binds them (case, `-` and `_`
// ignored).
const _supportedKeys = {
  'spring.jackson.property-naming-strategy',
  'spring.jackson.default-property-inclusion',
  'spring.jackson.deserialization.fail-on-unknown-properties',
  'spring.jackson.serialization.write-dates-as-timestamps',
  _timestampsBoot4,
  'spring.jackson.serialization.indent-output',
  'spring.jackson.mapper.sort-properties-alphabetically',
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
