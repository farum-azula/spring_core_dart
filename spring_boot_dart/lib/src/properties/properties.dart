import 'package:spring_boot_dart/spring_gen/src/properties/properties.spring.dart';
import 'package:spring_boot_dart/src/binder.dart' show dashedForm;
import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_boot_dart/src/properties/boot_properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// The typed properties of `spring_boot_dart` (`spring.main.*`,
/// `spring.messages.*`, `spring.json.*` ...), scanned in this folder.
@ComponentScan()
final BeanModule bootPropertiesBeans = $bootPropertiesBeans;

final _introspector = BeanIntrospector(
  introspections: bootPropertiesBeans.introspections,
);

/// Binds [properties], one of the classes of `boot_properties.dart`, from
/// [environment] and returns it.
///
/// For code that reads a setting before (or without) a context, where the
/// class cannot be injected: the start of `SpringApplication`, the mapper
/// built from an environment. Fields that [properties] already holds stay
/// as they are when the environment has no value for them.
T bindBootProperties<T extends Object>(Environment environment, T properties) {
  final name = '${properties.runtimeType}';
  return ConfigurationPropertiesBinder(
        environment as ConfigurableEnvironment,
        _introspector,
      ).postProcessBeforeInitialization(
        properties,
        '${name[0].toLowerCase()}${name.substring(1)}',
      )
      as T;
}

/// The keys of the `spring.json.*` settings, each in the dashed form
/// (`spring.json.serialization.indent-output`), read from the
/// introspection of [JsonProperties] so they are those the mapper reads.
List<String> jsonPropertyKeys() {
  List<String> under(String prefix, Type type) {
    final introspection = _introspector.forType(type);
    if (introspection == null) {
      return [prefix];
    }
    return [
      for (final property in introspection.properties)
        ...under('$prefix.${dashedForm(property.name)}', property.type),
    ];
  }

  return under('spring.json', JsonProperties);
}
