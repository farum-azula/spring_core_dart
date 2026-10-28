/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_oauth2_client`.
///
/// Applications do not import it: the generated `*.spring.dart` file does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_oauth2_client/src/oauth2_client_auto_configuration.dart';

// The auto-configurations this starter builds on (Feign, the security
// core, logging, and through them spring_boot_dart's), so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
export 'package:spring_security_core/spring_auto_configuration.dart';

/// The beans of OAuth 2.0 and OpenID Connect clients: the registrations of
/// `spring.security.oauth2.client.*`, the token store, the authorized
/// clients and their manager, the user services, the app login and the
/// Feign token interceptor (`oauth2ClientAutoConfiguration`).
///
/// It comes after the Flutter starter's module (`after`), so the Flutter
/// starter's `TokenStore` and `AuthorizationBrowser` replace the defaults
/// here; any other auto-configuration that declares them does the same
/// with `before: ['springBootStarterOauth2ClientAutoConfiguration']`.
@AutoConfigurationModule(after: ['springBootStarterFlutterAutoConfiguration'])
final BeanModule springBootStarterOauth2ClientAutoConfiguration = BeanModule(
  'springBootStarterOauth2ClientAutoConfiguration',
  [...oauth2ClientAutoConfiguration],
);
