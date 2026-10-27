import 'package:spring_boot_starter_security/src/jwt/bearer.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// Injects the principal of the current user into a controller parameter,
/// like Spring's `@AuthenticationPrincipal`: a `UserDetails`, a `Jwt`, ...
/// `null` when there is no user, the user is anonymous, or the principal
/// is not of the parameter's type (an error instead with
/// [errorOnInvalidType]).
///
/// ```dart
/// @GetMapping('/me')
/// String me(@AuthenticationPrincipal() UserDetails user) => user.username;
/// ```
class AuthenticationPrincipal {
  /// Injects the principal.
  const AuthenticationPrincipal({this.errorOnInvalidType = false});

  /// Whether a principal of another type is an error.
  final bool errorOnInvalidType;
}

/// Injects the current `SecurityContext`, like Spring's
/// `@CurrentSecurityContext`.
///
/// ```dart
/// @GetMapping('/whoami')
/// String whoami(@CurrentSecurityContext() SecurityContext context) =>
///     context.authentication?.name ?? '';
/// ```
class CurrentSecurityContext {
  /// Injects the context.
  const CurrentSecurityContext();
}

/// Resolves `@AuthenticationPrincipal`, `@CurrentSecurityContext` and
/// parameters typed as an `Authentication`, like Spring's
/// `AuthenticationPrincipalArgumentResolver` and
/// `CurrentSecurityContextArgumentResolver`.
final class SecurityArgumentResolver implements HandlerMethodArgumentResolver {
  /// The resolver.
  const SecurityArgumentResolver({
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// Tells anonymous users apart.
  final AuthenticationTrustResolver trustResolver;

  static const _authenticationTypes = {
    Authentication,
    AbstractAuthenticationToken,
    UsernamePasswordAuthenticationToken,
    JwtAuthenticationToken,
    TestingAuthenticationToken,
    AnonymousAuthenticationToken,
  };

  @override
  bool supportsParameter(MethodParameter parameter) =>
      parameter.annotations.any(
        (a) => a is AuthenticationPrincipal || a is CurrentSecurityContext,
      ) ||
      _authenticationTypes.contains(parameter.type.type);

  @override
  Object? resolveArgument(
    MethodParameter parameter,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final context = SecurityContextHolder.getContext();
    if (parameter.annotations.any((a) => a is CurrentSecurityContext)) {
      return context;
    }
    final authentication = context.authentication;
    final principalAnnotation = parameter.annotations
        .whereType<AuthenticationPrincipal>()
        .firstOrNull;
    if (principalAnnotation == null) {
      // An Authentication-typed parameter: the user, null when anonymous.
      return authentication == null ||
              trustResolver.isAnonymous(authentication) ||
              !parameter.type.isInstance(authentication)
          ? null
          : authentication;
    }
    if (authentication == null || trustResolver.isAnonymous(authentication)) {
      return null;
    }
    final principal = authentication.principal;
    if (principal != null && !parameter.type.isInstance(principal)) {
      if (principalAnnotation.errorOnInvalidType) {
        throw StateError(
          'The principal ${principal.runtimeType} is not a '
          '${parameter.type.type}',
        );
      }
      return null;
    }
    return principal;
  }
}
