/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_security`.
///
/// Applications do not import it: the generated `*.spring.dart` file does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_security/src/config/security_auto_configuration.dart';
import 'package:spring_boot_starter_security/src/properties/properties_beans.dart';

// The auto-configurations this starter builds on, so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_oauth2_client/spring_auto_configuration.dart';
export 'package:spring_boot_starter_web/spring_auto_configuration.dart';
export 'package:spring_security_core/spring_auto_configuration.dart';

/// The beans that switch web security on: the security filter, the
/// default filter chain and user, the JWT decoder from the properties, the
/// authorized client repository of `oauth2Login()`, and the controller
/// argument resolver.
///
/// It comes after the OAuth2 client starter's module (`after`), whose
/// `ClientRegistrationRepository` and `OAuth2AuthorizedClientService` its
/// conditions look for. It secures a server, so it is only where one can
/// run ([ModulePlatform.native]): a browser build has none of it.
@AutoConfigurationModule(
  after: ['springBootStarterOauth2ClientAutoConfiguration'],
  platform: ModulePlatform.native,
)
final BeanModule springBootStarterSecurityAutoConfiguration = BeanModule(
  'springBootStarterSecurityAutoConfiguration',
  [...securityAutoConfiguration],
  imports: [securityConfigBeans],
);

/// The ID token decoder of servers (`oidcIdTokenDecoder`, an
/// `OidcIdTokenDecoderFactory` that checks signatures with the provider's
/// keys), registered before the OAuth2 client starter's module
/// (`before`), so the client starter's default, which trusts the token
/// endpoint's TLS, steps aside for every user of the bean:
/// `oauth2Login()` and the refresh of authorized clients.
@AutoConfigurationModule(
  before: ['springBootStarterOauth2ClientAutoConfiguration'],
  platform: ModulePlatform.native,
)
final BeanModule springBootStarterSecurityOAuth2ClientAutoConfiguration =
    BeanModule('springBootStarterSecurityOAuth2ClientAutoConfiguration', [
      ...securityOAuth2ClientAutoConfiguration,
    ]);
