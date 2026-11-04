import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/properties/properties_beans.dart';

/// What the starter does at startup: binds `spring.security.oauth2.client.*`
/// of [environment].
OAuth2ClientProperties boundClientProperties(Environment environment) {
  final configurable = environment as ConfigurableEnvironment;
  ConfigurationPropertySources.attach(configurable);
  return ConfigurationPropertiesBinder(
    configurable,
    BeanIntrospector(introspections: oauth2ClientConfigBeans.introspections),
  ).bindOrCreate<OAuth2ClientProperties>('oauth2ClientProperties');
}

/// The resolver the starter makes of the `client-secret-jwt.*` properties
/// of [environment].
JwtClientSecretResolver jwtResolverOf(Environment environment) =>
    JwtClientSecretResolver.fromProperties(boundClientProperties(environment));
