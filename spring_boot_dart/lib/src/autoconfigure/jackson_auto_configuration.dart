import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#JacksonAutoConfiguration';

/// Registers an `objectMapper` bean built from `spring.jackson.*` when the
/// application declares no `ObjectMapper`, like Spring Boot's
/// `JacksonAutoConfiguration`. It reads the classes of the context's
/// `BeanIntrospector` and adds every `JsonModule` bean.
///
/// ```properties
/// # lib/resources/application.properties
/// spring.jackson.property-naming-strategy=SNAKE_CASE
/// spring.jackson.default-property-inclusion=non_null
/// spring.jackson.deserialization.fail-on-unknown-properties=true
/// spring.jackson.serialization.write-dates-as-timestamps=true
/// spring.jackson.serialization.indent-output=true
/// ```
final jacksonAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<ObjectMapper>(
    name: 'objectMapper',
    source: _source,
    conditions: const [
      ConditionGroup(_source, [ConditionalOnMissingBean(ObjectMapper)]),
    ],
    create: (r) => objectMapperFromProperties(
      r.dependency<Environment>(),
      introspector: r.dependency<BeanIntrospector>(),
      modules: r.optionalDependencyList<JsonModule>() ?? const [],
    ),
  ),
];

/// An [ObjectMapper] configured from `spring.jackson.*` of [environment]
/// (what the auto-configured bean is); [introspector] and [modules] are
/// passed on.
///
/// | Property | Default |
/// |---|---|
/// | `spring.jackson.property-naming-strategy` | `LOWER_CAMEL_CASE` |
/// | `spring.jackson.default-property-inclusion` | `always` |
/// | `spring.jackson.deserialization.fail-on-unknown-properties` | `false` |
/// | `spring.jackson.serialization.write-dates-as-timestamps` | `false` |
/// | `spring.jackson.serialization.indent-output` | `false` |
ObjectMapper objectMapperFromProperties(
  Environment environment, {
  BeanIntrospector? introspector,
  Iterable<JsonModule> modules = const [],
}) {
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
      'spring.jackson.serialization.write-dates-as-timestamps',
    ),
    indentOutput: flag('spring.jackson.serialization.indent-output'),
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
