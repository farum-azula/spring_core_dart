import 'package:spring_boot_actuator/spring_boot_actuator.dart'
    show EndpointId, EndpointRequestTarget, PrincipalRoleChecker;
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// Request matchers for the actuator's endpoints, to secure them in a
/// `SecurityFilterChain` without repeating their paths: they follow
/// `management.endpoints.web.base-path`, the path mappings and the
/// exposed endpoints.
///
/// ```dart
/// @Bean()
/// @Order(1)
/// SecurityFilterChain actuator(HttpSecurity http) => http
///     .securityMatcherOf(EndpointRequest.toAnyEndpoint())
///     .authorizeHttpRequests((auth) => auth
///         .requestMatchersOf([EndpointRequest.to(['health', 'info'])])
///         .permitAll()
///         .anyRequest()
///         .hasRole('ADMIN'))
///     .httpBasic()
///     .build();
/// ```
///
/// A request matches when the actuator starter recorded it as a request
/// for an exposed endpoint (or for the discovery page at the base path);
/// without the actuator starter no request matches. Paths are those the
/// handler mapping answers, so a path that is not an exposed endpoint
/// (`/actuator/env` while `env` is not exposed) matches nothing and gets
/// the rules of the other matchers.
///
/// Spring Boot (Java): `EndpointRequest` of
/// `org.springframework.boot.actuate.autoconfigure.security.servlet`.
abstract final class EndpointRequest {
  /// Every exposed endpoint and the discovery page.
  static EndpointRequestMatcher toAnyEndpoint() =>
      const EndpointRequestMatcher._(includeLinks: true);

  /// The endpoints [ids] (`health`, `info`).
  static EndpointRequestMatcher to(List<String> ids) =>
      EndpointRequestMatcher._(includes: ids, includeLinks: false);

  /// The discovery page at the base path (`/actuator`).
  static RequestMatcher toLinks() => const _LinksRequestMatcher();
}

/// The [RequestMatcher] of [EndpointRequest]: some endpoints, without some
/// others, with or without the discovery page.
///
/// Spring Boot (Java): `EndpointRequest.EndpointRequestMatcher`.
final class EndpointRequestMatcher extends SimpleRequestMatcher {
  const EndpointRequestMatcher._({
    required this.includeLinks,
    this.includes,
    this.excludes = const [],
  });

  /// The included endpoint ids; `null` for every exposed endpoint.
  final List<String>? includes;

  /// The excluded endpoint ids.
  final List<String> excludes;

  /// Whether the discovery page matches.
  final bool includeLinks;

  /// The same endpoints without [ids].
  EndpointRequestMatcher excluding(List<String> ids) =>
      EndpointRequestMatcher._(
        includes: includes,
        excludes: [...excludes, ...ids],
        includeLinks: includeLinks,
      );

  /// The same endpoints without the discovery page.
  EndpointRequestMatcher excludingLinks() => EndpointRequestMatcher._(
    includes: includes,
    excludes: excludes,
    includeLinks: false,
  );

  @override
  bool matches(ServerHttpRequest request) {
    final target = EndpointRequestTarget.of(request.attributes);
    if (target == null) {
      return false;
    }
    final id = target.endpointId;
    if (id == null) {
      return includeLinks;
    }
    bool named(List<String> ids) =>
        ids.any((other) => EndpointId.of(other) == id);
    return (includes == null || named(includes!)) && !named(excludes);
  }

  @override
  String toString() =>
      'EndpointRequest [${includes == null ? 'any' : includes!.join(', ')}'
      '${excludes.isEmpty ? '' : ' excluding ${excludes.join(', ')}'}'
      '${includeLinks ? ', links' : ''}]';
}

final class _LinksRequestMatcher extends SimpleRequestMatcher {
  const _LinksRequestMatcher();

  @override
  bool matches(ServerHttpRequest request) =>
      EndpointRequestTarget.of(request.attributes)?.isLinks ?? false;

  @override
  String toString() => 'EndpointRequest [links]';
}

/// The roles of an `Authentication` for the actuator
/// (`management.endpoint.health.show-details=when-authorized` with
/// `roles`): the user has the role `ADMIN` when one of its authorities is
/// `ROLE_ADMIN` or `ADMIN`.
///
/// The security starter declares it as the `authenticationRoleChecker`
/// bean.
///
/// Spring Boot (Java): `isUserInRole` of the request, and the authority
/// check of `AutoConfiguredHealthEndpointGroup.isAuthorized`.
final class AuthenticationRoleChecker implements PrincipalRoleChecker {
  /// The checker.
  const AuthenticationRoleChecker();

  @override
  bool isUserInRole(Principal principal, String role) {
    if (principal is! Authentication) {
      return false;
    }
    final prefixed = role.startsWith('ROLE_') ? role : 'ROLE_$role';
    return principal.authorities.any(
      (authority) =>
          authority.authority == prefixed || authority.authority == role,
    );
  }
}
