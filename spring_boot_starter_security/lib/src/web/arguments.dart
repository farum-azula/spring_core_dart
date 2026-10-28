import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show OAuth2AuthenticationToken;
import 'package:spring_boot_starter_security/src/jwt/bearer.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// Marks a controller parameter that receives the principal of the
/// current user: the `UserDetails` of a password login, the `Jwt` of a
/// bearer token, or your own principal class.
///
/// It saves reading `SecurityContextHolder` in every handler. The
/// parameter is `null` when there is no user, when the user is anonymous,
/// or when the principal is not of the parameter's type; with
/// [errorOnInvalidType] a wrong type is an error instead. Make the
/// parameter nullable unless the access rules require a login for the
/// path.
///
/// ```dart
/// // `/me` requires a login, so the user is never null here.
/// @GetMapping('/me')
/// String me(@AuthenticationPrincipal() UserDetails user) => user.username;
///
/// // A resource server: the decoded token.
/// @GetMapping('/tenant')
/// String tenant(@AuthenticationPrincipal() Jwt jwt) =>
///     jwt.getClaimAsString('tenant') ?? '';
/// ```
///
/// Spring (Java):
/// ```java
/// @GetMapping("/me")
/// String me(@AuthenticationPrincipal UserDetails user) {
///   return user.getUsername();
/// }
/// ```
class AuthenticationPrincipal {
  /// Marks the parameter; [errorOnInvalidType] makes a principal of
  /// another type fail the request instead of giving `null`.
  const AuthenticationPrincipal({this.errorOnInvalidType = false});

  /// Whether a principal that is not of the parameter's type throws a
  /// [StateError] (failing the request) rather than giving `null`;
  /// `false` by default.
  final bool errorOnInvalidType;
}

/// Marks a controller parameter that receives the current
/// `SecurityContext`, even when its authentication is anonymous or
/// missing.
///
/// Use it when the handler needs the context itself; for the user,
/// prefer an `Authentication` parameter or [AuthenticationPrincipal].
///
/// ```dart
/// @GetMapping('/whoami')
/// String whoami(@CurrentSecurityContext() SecurityContext context) =>
///     context.authentication?.name ?? '';
/// ```
///
/// Spring (Java): `@CurrentSecurityContext SecurityContext context`.
class CurrentSecurityContext {
  /// Marks the parameter.
  const CurrentSecurityContext();
}

/// Fills the security parameters of controller methods: those marked
/// [AuthenticationPrincipal] or [CurrentSecurityContext], and those whose
/// type is `Authentication` or one of the built-in token classes.
///
/// The auto-configuration registers it with the web starter. An
/// `Authentication` parameter gets the current one, or `null` for an
/// anonymous user, no user, or a token of another class.
///
/// Spring (Java): `AuthenticationPrincipalArgumentResolver` and
/// `CurrentSecurityContextArgumentResolver`.
final class SecurityArgumentResolver implements HandlerMethodArgumentResolver {
  /// A resolver using [trustResolver] to recognise anonymous users.
  const SecurityArgumentResolver({
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// Tells anonymous users, who get `null`, from real logins.
  final AuthenticationTrustResolver trustResolver;

  static const _authenticationTypes = {
    Authentication,
    AbstractAuthenticationToken,
    UsernamePasswordAuthenticationToken,
    JwtAuthenticationToken,
    OAuth2AuthenticationToken,
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
