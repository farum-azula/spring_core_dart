import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/properties/properties_beans.dart';

/// The properties class [T] of the starter, bound from [environment].
///
/// For code that runs before, or beside, the context: the same binding the
/// context does for the class as a bean, so both read the same values.
/// [beanName] is the name in error messages. Throws a
/// [ConfigurationPropertiesBindException] for a value that does not fit.
T boundProperties<T extends Object>(Environment environment, String beanName) {
  if (environment is! ConfigurableEnvironment) {
    throw StateError(
      'The properties of $T need a ConfigurableEnvironment, not '
      '${environment.runtimeType}.',
    );
  }
  ConfigurationPropertySources.attach(environment);
  return ConfigurationPropertiesBinder(
    environment,
    BeanIntrospector(introspections: flutterConfigBeans.introspections),
  ).bindOrCreate<T>(beanName);
}

/// Whether [defines] (the `--dart-define` values) switch
/// `spring.flutter.scan-os-environment` on. The application reads them
/// before it has an environment, so they are bound on one of their own;
/// the relaxed environment form (`SPRING_FLUTTER_SCANOSENVIRONMENT`) is
/// understood too.
bool scanOsEnvironmentIn(Map<String, String> defines) {
  final environment = StandardEnvironment()
    ..propertySources.addFirst(MapPropertySource('dartDefines', {...defines}))
    ..propertySources.addLast(
      SystemEnvironmentPropertySource('dartDefinesEnvironment', {...defines}),
    );
  return boundProperties<FlutterProperties>(
    environment,
    'flutterProperties',
  ).scanOsEnvironment;
}
