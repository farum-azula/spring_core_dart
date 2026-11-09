import 'package:spring_boot_dart/src/autoconfigure/jackson_auto_configuration.dart';
import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_boot_dart/src/properties/boot_properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#JsonSchemaAutoConfiguration';
const _log = SpringLog('spring_boot_dart.JsonSchemaAutoConfiguration');

/// The JSON Schemas of the app as beans.
///
/// - `jsonSchemaRegistry` ([JsonSchemaRegistry]), left out when the app
///   declares its own registry bean;
/// - every [JsonSchemaRegistryCustomizer] bean fills whichever registry
///   the context has, the app's own too, once, in `@Order` order;
/// - `propertiesJsonSchemas` ([PropertiesJsonSchemas]), the customizer of
///   the schemas of `spring.json.schemas`, of every `@JsonSchemaSource`
///   and of every `JsonSchema` bean (`spring.json.schemas-registry
///   .properties=false` leaves them out);
/// - a [JsonMapperBuilderCustomizer] that gives the `ObjectMapper` the
///   registry as its `schemaResolver`, so reading a class with
///   `@JsonSchemaSource` checks the JSON against its schema first.
///
/// ```yaml
/// spring:
///   json:
///     schemas:
///       - location: resources:schemas/order.json
///       - location: https://example.com/schemas/user.json
/// ```
///
/// Spring has no counterpart.
final jsonSchemaAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<JsonSchemaRegistry>(
    name: 'jsonSchemaRegistry',
    factoryMethodName: 'jsonSchemaRegistry',
    source: _source,
    conditions: const [
      ConditionGroup('$_source#jsonSchemaRegistry', [
        ConditionalOnMissingBean(JsonSchemaRegistry),
      ]),
    ],
    create: (_) => JsonSchemaRegistry(),
  ),
  BeanDefinition<JsonSchemaRegistryPostProcessor>(
    name: 'jsonSchemaRegistryPostProcessor',
    types: const [
      JsonSchemaRegistryPostProcessor,
      BeanPostProcessor,
      BeanFactoryAware,
    ],
    source: _source,
    create: (_) => JsonSchemaRegistryPostProcessor(),
  ),
  BeanDefinition<PropertiesJsonSchemas>(
    name: 'propertiesJsonSchemas',
    types: const [PropertiesJsonSchemas, JsonSchemaRegistryCustomizer],
    source: _source,
    create: (r) => PropertiesJsonSchemas(
      r.dependency<JsonProperties>(),
      r.dependency<ResourceLoader>(),
      introspector: r.dependency<BeanIntrospector>(),
      schemas: r.optionalDependencyList<JsonSchema>() ?? const [],
    ),
  ),
  BeanDefinition<JsonMapperBuilderCustomizer>(
    name: 'jsonSchemaMapperCustomizer',
    source: _source,
    create: (r) {
      final factory = r.dependency<ListableBeanFactory>();
      return JsonMapperBuilderCustomizer.of((builder) {
        final registries = factory.getBeansOfType<JsonSchemaRegistry>();
        if (registries.length != 1) {
          return;
        }
        final registry = registries.values.single;
        builder.schemaResolver((location) {
          final uri = Uri.tryParse(location);
          return uri == null ? null : registry.resolve(uri);
        });
      });
    },
  ),
];

/// A bean that adds schemas to the context's [JsonSchemaRegistry]: the
/// auto-configured one or the app's own. Every customizer runs once, when
/// the registry is made, in `@Order` order.
///
/// ```dart
/// @Bean()
/// JsonSchemaRegistryCustomizer partnerSchemas(PartnerClient client) =>
///     JsonSchemaRegistryCustomizer.of((registry) {
///       for (final schema in client.schemas()) {
///         registry.add(schema);
///       }
///     });
/// ```
///
/// Spring has no counterpart; it is shaped like
/// `JsonMapperBuilderCustomizer`.
abstract interface class JsonSchemaRegistryCustomizer {
  /// A customizer that runs [customize]; the short form for a `@Bean`
  /// method.
  const factory JsonSchemaRegistryCustomizer.of(
    void Function(JsonSchemaRegistry registry) customize,
  ) = _FunctionRegistryCustomizer;

  /// Adds schemas to [registry].
  void customize(JsonSchemaRegistry registry);
}

final class _FunctionRegistryCustomizer
    implements JsonSchemaRegistryCustomizer {
  const _FunctionRegistryCustomizer(this._customize);

  final void Function(JsonSchemaRegistry registry) _customize;

  @override
  void customize(JsonSchemaRegistry registry) => _customize(registry);
}

/// Runs every [JsonSchemaRegistryCustomizer] bean on each
/// [JsonSchemaRegistry] bean once it is made, whoever declares it.
///
/// Spring has no counterpart.
final class JsonSchemaRegistryPostProcessor extends BeanPostProcessor
    implements BeanFactoryAware {
  BeanFactory? _beanFactory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (bean is JsonSchemaRegistry && factory is ListableBeanFactory) {
      final customizers = OrderComparator.sort(
        factory.getBeansOfType<JsonSchemaRegistryCustomizer>().values.toList(),
      );
      for (final customizer in customizers) {
        customizer.customize(bean);
      }
    }
    return bean;
  }
}

/// The customizer of the schemas the app names: the `spring.json.schemas`
/// locations, the location of each `@JsonSchemaSource` among the
/// introspections, and every `JsonSchema` bean. A location is read from
/// `resources:`, a remote one from the copy the build keeps
/// ([JsonSchemaLocations.resourceOf]); each is added under its location,
/// which the `ObjectMapper` looks up. A bean is added under its `$id`.
///
/// Nothing is added with `spring.json.schemas-registry.properties=false`.
///
/// Spring has no counterpart.
final class PropertiesJsonSchemas implements JsonSchemaRegistryCustomizer {
  /// The schemas of [properties], read through [resources], of the
  /// `@JsonSchemaSource` annotations of [introspector] and the beans
  /// [schemas].
  PropertiesJsonSchemas(
    this.properties,
    this.resources, {
    BeanIntrospector? introspector,
    this.schemas = const [],
  }) : introspector = introspector ?? BeanIntrospector.shared;

  /// The `spring.json.*` settings.
  final JsonProperties properties;

  /// Reads the schemas.
  final ResourceLoader resources;

  /// The classes whose `@JsonSchemaSource` count.
  final BeanIntrospector introspector;

  /// The `JsonSchema` beans.
  final List<JsonSchema> schemas;

  /// The locations to add: those of the properties, then those of the
  /// annotations, each once.
  List<String> get locations => {
    for (final entry in properties.schemas)
      if (entry.location case final location? when location.isNotEmpty)
        location,
    for (final introspection in introspector.introspections)
      for (final annotation in introspection.annotations)
        if (annotation is JsonSchemaSource) annotation.location,
  }.toList();

  @override
  void customize(JsonSchemaRegistry registry) {
    if (!properties.schemasRegistry.properties) {
      return;
    }
    for (final location in locations) {
      final schema = read(location);
      if (schema != null) {
        registry.add(schema, uri: Uri.parse(location));
      }
    }
    for (final schema in schemas) {
      if (schema.id case final id?) {
        registry.add(schema, uri: id);
      } else {
        _log.warning(
          r'A JsonSchema bean without $id is not in the registry: give it '
          r'one (an id: or a $id in the document).',
        );
      }
    }
  }

  /// The schema at [location]; `null` (and a warning) when its resource
  /// is missing. A file that is no schema fails, naming the location.
  JsonSchema? read(String location) {
    final String path;
    try {
      path = JsonSchemaLocations.resourceOf(location);
    } on ArgumentError catch (error) {
      throw StateError('spring.json.schemas: ${error.message} ($location).');
    }
    final resource = resources.getResource('resources:$path');
    if (!resource.exists()) {
      _log.warning(
        JsonSchemaLocations.isRemote(location)
            ? 'The JSON Schema $location has no copy at resources:$path: '
                  'the build downloads it (dart run build_runner build).'
            : 'The JSON Schema $location does not exist.',
      );
      return null;
    }
    try {
      return JsonSchema.parse(
        resource.readAsStringSync(),
        id: Uri.parse(location),
      );
    } on FormatException catch (error) {
      throw StateError(
        'The JSON Schema $location is no schema: ${error.message}',
      );
    }
  }
}
