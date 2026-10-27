/// Spring Security for Dart: who is logged in, users and passwords, and
/// method security, like Spring Security's core.
///
/// - `SecurityContextHolder`: the current `Authentication`, kept per
///   request (a `Zone`) on a server, for the whole app in Flutter;
/// - `UserDetailsService`, `User`, `InMemoryUserDetailsManager`;
///   `AuthenticationManager`, `ProviderManager`,
///   `DaoAuthenticationProvider`; success and failure events;
/// - `PasswordEncoder`s: Argon2, PBKDF2 and scrypt in Spring's formats
///   (Bouncy Castle's Dart port), `DelegatingPasswordEncoder` with
///   `{id}` prefixes;
/// - `PreAuthorize`, `PostAuthorize`, `Secured`, `PreFilter`,
///   `PostFilter` on bean methods, checked through the bean's proxy;
/// - `AuthorizationManager`s for roles, authorities and login kinds,
///   `RoleHierarchyImpl`.
///
/// The web side (the filter chain, logins, sessions, CSRF, JWT) is
/// `spring_boot_starter_security`. Re-exports `spring_boot_starter_logging`
/// and through it `spring_boot_dart` and `spring_core_dart`.
library;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_security_core/src/authentication/authentication_manager.dart';
export 'package:spring_security_core/src/authentication/events.dart';
export 'package:spring_security_core/src/authorization/authorization_manager.dart';
export 'package:spring_security_core/src/context/security_context.dart';
export 'package:spring_security_core/src/core/authentication.dart';
export 'package:spring_security_core/src/core/authority.dart';
export 'package:spring_security_core/src/core/exceptions.dart';
export 'package:spring_security_core/src/crypto/password_encoder.dart';
export 'package:spring_security_core/src/method/annotations.dart';
export 'package:spring_security_core/src/method/expression_handler.dart';
export 'package:spring_security_core/src/method/method_security_interceptor.dart';
export 'package:spring_security_core/src/security_core_auto_configuration.dart';
export 'package:spring_security_core/src/userdetails/user_details.dart';
export 'package:spring_security_core/src/userdetails/user_details_service.dart';
