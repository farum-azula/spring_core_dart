/// Security that does not depend on HTTP: who is logged in, users and
/// password hashes, and access rules on bean methods. Import it in a
/// Flutter app or any `spring_boot_dart` application that needs logins or
/// `@PreAuthorize`.
///
/// What it gives:
///
/// - **The current user**: `SecurityContextHolder` keeps the
///   `Authentication` of each request on a server (per `Zone`), and of the
///   whole app in Flutter.
/// - **Logins**: you write a `UserDetailsService` that loads your users;
///   the auto-configured `AuthenticationManager` checks passwords against
///   it and publishes success and failure events.
/// - **Password hashing**: `PasswordEncoder`s for Argon2 (the default),
///   PBKDF2 and scrypt in Spring's formats, so hashes move between Java
///   and Dart, behind a `DelegatingPasswordEncoder` that names the
///   algorithm in each hash (`{argon2}...`).
/// - **Method security**: `@PreAuthorize`, `@PostAuthorize`, `@Secured`,
///   `@PreFilter` and `@PostFilter` on bean methods, checked in the bean's
///   proxy. Adding the dependency switches them on.
/// - **Building blocks** for access rules: `AuthorizationManager`s for
///   roles, authorities and login kinds, and `RoleHierarchyImpl`.
///
/// ```dart
/// @Service()
/// class OrderService {
///   // Admins cancel any order, other users only their own.
///   @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
///   Future<void> cancel(Order order) async { ... }
/// }
/// ```
///
/// The web side (the filter chain in front of controllers, form, basic and
/// token logins, sessions, CSRF) is `spring_boot_starter_security`, which
/// brings this package. This import re-exports
/// `spring_boot_starter_logging` and, through it, `spring_boot_dart` and
/// `spring_core_dart`. It is the Dart version of Spring Security's core
/// (`spring-security-core` with method security).
library;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_security_core/src/authentication/authentication_manager.dart';
export 'package:spring_security_core/src/authentication/events.dart';
export 'package:spring_security_core/src/authentication/password_checks.dart';
export 'package:spring_security_core/src/authorization/authorization_manager.dart';
export 'package:spring_security_core/src/context/listening_security_context.dart';
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
