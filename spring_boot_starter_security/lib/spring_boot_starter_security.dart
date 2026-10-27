/// Spring Security for `spring_boot_starter_web`, like Spring Boot's
/// security starter: a filter chain in front of the controllers.
///
/// - `HttpSecurity` builds `SecurityFilterChain`s: access rules by path
///   pattern (`AuthorizeHttpRequestsConfigurer`), HTTP Basic, form login
///   with sessions, JWT resource servers (`NimbusJwtDecoder`), CSRF, CORS,
///   security headers, logout;
/// - without a chain of the application's: every request needs a login,
///   with a default user (`spring.security.user.*`);
/// - a `StrictHttpFirewall` refuses ambiguous paths before any rule;
/// - `@AuthenticationPrincipal`, `@CurrentSecurityContext` and
///   `Authentication` parameters in controllers;
/// - `package:spring_boot_starter_security/testing.dart`: users, Basic,
///   JWTs and CSRF tokens for `MockMvc`.
///
/// Re-exports `spring_security_core` (users, passwords, `@PreAuthorize`)
/// and `spring_boot_starter_web`: the starter is the only dependency an
/// application lists.
library;

export 'package:spring_boot_starter_security/src/config/http_security.dart';
export 'package:spring_boot_starter_security/src/config/security_auto_configuration.dart';
export 'package:spring_boot_starter_security/src/jwt/bearer.dart';
export 'package:spring_boot_starter_security/src/jwt/jose.dart'
    show
        EcVerificationKey,
        JoseException,
        JwsAlgorithm,
        RsaVerificationKey,
        SecretVerificationKey,
        VerificationKey;
export 'package:spring_boot_starter_security/src/jwt/jwt.dart';
export 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
export 'package:spring_boot_starter_security/src/web/access.dart';
export 'package:spring_boot_starter_security/src/web/arguments.dart';
export 'package:spring_boot_starter_security/src/web/authentication.dart';
export 'package:spring_boot_starter_security/src/web/csrf.dart';
export 'package:spring_boot_starter_security/src/web/entry_points.dart';
export 'package:spring_boot_starter_security/src/web/filter_chain.dart';
export 'package:spring_boot_starter_security/src/web/firewall.dart';
export 'package:spring_boot_starter_security/src/web/headers.dart';
export 'package:spring_boot_starter_security/src/web/request_cache.dart';
export 'package:spring_boot_starter_security/src/web/request_matcher.dart';
export 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
export 'package:spring_security_core/spring_security_core.dart';
