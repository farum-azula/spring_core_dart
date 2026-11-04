import 'package:spring_boot_starter_flutter_security/src/properties/flutter_security_properties.dart';
import 'package:spring_boot_starter_flutter_security/src/properties/properties_beans.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The web login's properties of [environment], bound and checked the way
/// the context does it for the bean. For code that decides before the bean
/// exists (the conditions of the auto-configuration) and for tests. Throws a
/// [ConfigurationPropertiesBindException] for a value it cannot use.
FlutterWebSecurityProperties boundWebSecurityProperties(
  Environment environment,
) => _bound<FlutterWebSecurityProperties>(
  environment,
  'flutterWebSecurityProperties',
);

/// The settings of the Flutter security starter of [environment], bound
/// the way the context does it for the bean.
FlutterSecurityProperties boundSecurityProperties(Environment environment) =>
    _bound<FlutterSecurityProperties>(environment, 'flutterSecurityProperties');

T _bound<T extends Object>(Environment environment, String beanName) {
  if (environment is! ConfigurableEnvironment) {
    throw StateError(
      'The properties of $T need a ConfigurableEnvironment, not '
      '${environment.runtimeType}.',
    );
  }
  ConfigurationPropertySources.attach(environment);
  return ConfigurationPropertiesBinder(
    environment,
    BeanIntrospector(introspections: flutterSecurityConfigBeans.introspections),
  ).bindOrCreate<T>(beanName);
}
