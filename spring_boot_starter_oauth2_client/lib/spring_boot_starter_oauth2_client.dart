// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

/// OAuth 2.0 and OpenID Connect clients for `spring_boot_dart`
/// applications: Spring Security's OAuth2 client with Spring Boot's
/// auto-configuration. Registrations from `spring.security.oauth2.client.*`,
/// provider discovery, the token endpoint of every grant
/// (`authorization_code` with PKCE, `refresh_token`,
/// `client_credentials`), authorized clients that refresh themselves, the
/// users of OAuth 2.0 and OpenID Connect, and the access token on every
/// Feign call.
///
/// Configure a registration with Spring Boot's properties; the starter
/// does the rest:
///
/// ```properties
/// spring.security.oauth2.client.registration.partner.client-id=shop
/// spring.security.oauth2.client.registration.partner.client-secret=${PARTNER_SECRET}
/// spring.security.oauth2.client.registration.partner.authorization-grant-type=client_credentials
/// spring.security.oauth2.client.provider.partner.token-uri=https://id.partner.example/oauth2/token
/// spring.cloud.openfeign.oauth2.enabled=true
/// spring.cloud.openfeign.oauth2.client-registration-id=partner
/// ```
///
/// ```dart
/// // Every call carries the partner's access token, renewed before it
/// // expires.
/// @FeignClient('orders', url: r'${partner.url}')
/// abstract class OrdersClient {
///   @GetMapping('/orders')
///   Future<List<Order>> orders();
/// }
/// ```
///
/// A server logs browsers in with these registrations through the
/// security starter's `oauth2Login()`; a Flutter app logs its user in
/// with `spring_boot_starter_flutter_security`. This import re-exports
/// `spring_boot_starter_feign`, `spring_security_core` and, through them,
/// `spring_web_dart`, `spring_boot_dart` and the logging starter: the
/// starter is the only dependency an application lists. It is the Dart
/// version of Spring Boot's `spring-boot-starter-oauth2-client` (Spring
/// Security's `spring-security-oauth2-client` and `-oauth2-core`).
library;

// Feign (and through it the web client and logging) and the security
// core, so this starter is the only dependency an application needs.
export 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
export 'package:spring_security_core/spring_security_core.dart';

export 'src/client/authorized_client.dart';
export 'src/client/authorized_client_manager.dart';
export 'src/client/oauth2_access_token_headers.dart';
export 'src/core/oauth2_error.dart';
export 'src/core/parameter_names.dart' hide formUrlEncode, formUrlEncodeAll;
export 'src/core/sha256.dart' show sha256Base64Url;
export 'src/core/token_validator.dart';
export 'src/core/tokens.dart';
export 'src/dpop/dpop_key.dart';
export 'src/dpop/dpop_proof_builder.dart';
export 'src/dpop/dpop_proof_claims.dart';
export 'src/dpop/jwk_thumbprint.dart';
export 'src/endpoint/access_token_response.dart';
export 'src/endpoint/authorization_request.dart';
export 'src/endpoint/jwt_client_secret.dart';
export 'src/endpoint/token_response_clients.dart' hide clientAuthentication;
export 'src/feign/oauth2_access_token_interceptor.dart';
export 'src/oidc/claims.dart';
export 'src/oidc/jwk_set_oidc_id_token_decoder.dart';
export 'src/oidc/oidc_id_token.dart';
export 'src/oidc/oidc_id_token_decoder.dart';
export 'src/oidc/oidc_id_token_validator.dart';
export 'src/registration/client_registration.dart';
export 'src/registration/client_registration_repository.dart';
export 'src/registration/client_registrations.dart';
export 'src/registration/common_oauth2_provider.dart';
export 'src/registration/oauth2_client_properties.dart';
export 'src/user/oauth2_user.dart';
export 'src/user/user_services.dart' hide loadUserAttributes;
