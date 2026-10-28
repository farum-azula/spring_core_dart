/// Web security for `spring_boot_starter_web` applications: logins and
/// access rules in front of the controllers. Import it, and add it as the
/// only dependency, to secure an HTTP server.
///
/// Adding the package is enough to be secure: with nothing configured,
/// every request needs a login, browsers get a login page, programs a
/// `401` asking for HTTP Basic, and there is one user (`user`, with the
/// password from `spring.security.user.password` or one generated and
/// logged at startup). CSRF protection, security headers and logout at
/// `POST /logout` are on.
///
/// To set your own rules, declare a `SecurityFilterChain` bean built with
/// `HttpSecurity`:
///
/// ```dart
/// @Configuration()
/// class SecurityConfig {
///   @Bean()
///   SecurityFilterChain filterChain(HttpSecurity http) => http
///       .authorizeHttpRequests((auth) => auth
///           .requestMatchers('/public/**').permitAll()
///           .requestMatchers('/api/admin/**').hasRole('ADMIN')
///           .anyRequest().authenticated())
///       .formLogin()
///       .httpBasic()
///       .build();
/// }
/// ```
///
/// Also here: JWT resource servers (`oauth2ResourceServer`, or the
/// `spring.security.oauth2.resourceserver.jwt.*` properties), CORS, a
/// firewall that refuses ambiguous paths before any rule, and
/// `@AuthenticationPrincipal` for controller parameters. Test helpers are
/// in `package:spring_boot_starter_security/testing.dart`.
///
/// This import re-exports `spring_security_core` (users, passwords,
/// `@PreAuthorize`) and `spring_boot_starter_web`. It is the Dart version
/// of Spring Boot's `spring-boot-starter-security`.
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
