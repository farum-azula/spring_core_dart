import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_oauth2_client/spring_gen/src/properties/properties_beans.spring.dart';
import 'package:spring_boot_starter_oauth2_client/src/properties/oauth2_client_properties.dart';

/// The typed properties of the starter, scanned in this folder.
@ComponentScan()
final BeanModule oauth2ClientConfigBeans = $oauth2ClientConfigBeans;

/// The `spring.security.oauth2.client.*` properties of [environment], bound
/// the way the context binds the bean: for code that needs them before the
/// context exists, or without one (a widget). Throws a
/// [ConfigurationPropertiesBindException] for a value that cannot be
/// converted, and a [StateError] when [environment] is not a
/// [ConfigurableEnvironment].
OAuth2ClientProperties bindOAuth2ClientProperties(Environment environment) {
  if (environment is! ConfigurableEnvironment) {
    throw StateError(
      'The OAuth2 client properties are bound from a ConfigurableEnvironment, '
      'not ${environment.runtimeType}.',
    );
  }
  ConfigurationPropertySources.attach(environment);
  return ConfigurationPropertiesBinder(
    environment,
    BeanIntrospector(introspections: oauth2ClientConfigBeans.introspections),
  ).bindOrCreate<OAuth2ClientProperties>('oauth2ClientProperties');
}
