import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/spring_gen/src/config/config.spring.dart';
import 'package:spring_boot_starter_web/src/config/web_properties.dart';

/// The typed properties of the starter, scanned in this folder.
@ComponentScan()
final BeanModule webConfigBeans = $webConfigBeans;

/// Binds the web settings [target] from [environment], as the starter does
/// at startup (the same binder, the same class metadata): for code that
/// has an environment but no context, such as a condition or a test.
///
/// Throws a [ConfigurationPropertiesBindException] for a value that cannot
/// be converted, and an [ArgumentError] when [environment] is not a
/// [ConfigurableEnvironment].
T bindWebSettings<T extends Object>(
  PropertyResolver environment,
  T target,
  String beanName,
) {
  if (environment is! ConfigurableEnvironment) {
    throw ArgumentError.value(
      environment,
      'environment',
      'the web settings are bound from a ConfigurableEnvironment',
    );
  }
  ConfigurationPropertySources.attach(environment);
  return ConfigurationPropertiesBinder(
    environment,
    BeanIntrospector(introspections: webConfigBeans.introspections),
  ).postProcessBeforeInitialization(target, beanName) as T;
}

/// The `server.*` settings of [environment], bound.
ServerSettings bindServerSettings(PropertyResolver environment) =>
    bindWebSettings(environment, ServerSettings(), 'serverSettings');
