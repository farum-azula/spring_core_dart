// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

/// OAuth 2.0 and OpenID Connect clients for `spring_boot_dart`
/// applications: log the user of an app in with Keycloak, Google, Auth0 or
/// any other provider, keep them logged in, and send their token with
/// every Feign call.
///
/// Configure a registration with Spring Boot's properties; the starter
/// does the rest (discovery, PKCE, the token endpoint, refresh, the user,
/// the token store):
///
/// ```properties
/// spring.security.oauth2.client.registration.keycloak.client-id=neon-app
/// spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
/// spring.security.oauth2.client.registration.keycloak.redirect-uri=http://127.0.0.1/callback
/// spring.security.oauth2.client.provider.keycloak.issuer-uri=http://localhost:8180/realms/neon
/// spring.cloud.openfeign.oauth2.enabled=true
/// spring.cloud.openfeign.oauth2.client-registration-id=keycloak
/// ```
///
/// ```dart
/// @Service()
/// class Account {
///   Account(this._login);
///   final OAuth2LoginService _login;
///
///   Future<void> signIn() => _login.login('keycloak'); // the system browser
///   Future<void> signOut() => _login.logout();
/// }
/// ```
///
/// A server uses the same registrations for its client-credentials calls
/// to other services, and the security starter's `oauth2Login()` for
/// browsers. This import re-exports `spring_boot_starter_feign`,
/// `spring_security_core` and, through them, `spring_web_dart`,
/// `spring_boot_dart` and the logging starter: the starter is the only
/// dependency an application lists. It is the Dart version of Spring
/// Boot's `spring-boot-starter-oauth2-client` (Spring Security's
/// `spring-security-oauth2-client` and `-oauth2-core`).
library;

// Feign (and through it the web client and logging) and the security
// core, so this starter is the only dependency an application needs.
export 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
export 'package:spring_security_core/spring_security_core.dart';

export 'src/authorization_browser.dart';
export 'src/client/authorized_client.dart';
export 'src/client/authorized_client_manager.dart';
export 'src/core/oauth2_error.dart';
export 'src/core/parameter_names.dart' hide formUrlEncode, formUrlEncodeAll;
export 'src/core/sha256.dart' show sha256Base64Url;
export 'src/core/token_validator.dart';
export 'src/core/tokens.dart';
export 'src/endpoint/access_token_response.dart';
export 'src/endpoint/authorization_request.dart';
export 'src/endpoint/token_response_clients.dart' hide clientAuthentication;
export 'src/feign/oauth2_access_token_interceptor.dart';
export 'src/login/oauth2_login_service.dart';
export 'src/loopback_authorization_browser.dart'
    hide loopbackAuthorizationBrowserSupported;
export 'src/oidc/claims.dart';
export 'src/oidc/oidc_id_token.dart';
export 'src/oidc/oidc_id_token_decoder.dart';
export 'src/oidc/oidc_id_token_validator.dart';
export 'src/registration/client_registration.dart';
export 'src/registration/client_registration_repository.dart';
export 'src/registration/client_registrations.dart';
export 'src/registration/common_oauth2_provider.dart';
export 'src/registration/oauth2_client_properties.dart';
export 'src/token_store.dart';
export 'src/user/oauth2_user.dart';
export 'src/user/user_services.dart' hide loadUserAttributes;
