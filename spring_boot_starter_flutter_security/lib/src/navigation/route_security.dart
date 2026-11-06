import 'dart:async';

import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:spring_boot_starter_flutter_security/src/principal/principal_notifier.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.flutter.navigation');

/// The address a guard sent to the login, kept so the app returns there
/// once the user is logged in.
///
/// [RouteSecurity] keeps it when it sends someone to the login, and the
/// starter goes back to it after the next login, however the user logged
/// in (a form, a provider's button, a restored session).
///
/// Spring (Java): `RequestCache` with its `SavedRequest`, which Spring
/// Security keeps when it sends a browser to the login page.
class RouteRequestCache {
  RouteLocation? _saved;

  /// Keeps [location] as the address to return to.
  void save(RouteLocation location) => _saved = location;

  /// The address kept, or `null`.
  RouteLocation? get saved => _saved;

  /// The address kept, which is forgotten.
  RouteLocation? take() {
    final saved = _saved;
    _saved = null;
    return saved;
  }
}

/// Decides whether a route opens for the current user: `@PreAuthorize` on a
/// screen (the route's `preAuthorize` attribute), or
/// [RouteSecurity.preAuthorize] among the filters of a route in Dart
/// configuration.
///
/// The expression is the language of `@PreAuthorize`
/// (`isAuthenticated()`, `hasRole('ADMIN')`,
/// `principal.username == 'ada'`), evaluated by the application's
/// `MethodSecurityExpressionHandler`, so a role hierarchy applies. When it
/// is `false` for nobody logged in, the navigation goes to the login
/// (`spring.flutter.navigation.login`) and back after it; without a login
/// route it shows the route's error screen. A logged-in user it is `false`
/// for gets the error screen (an `AccessDeniedException`). On the device
/// this hides screens; the server still checks every request.
///
/// ```dart
/// @ScreenRoute('/admin')
/// @PreAuthorize("hasRole('ADMIN')")
/// class AdminPage extends StatelessWidget { ... }
///
/// // Dart configuration:
/// ScreenRoutes.route()
///     .nest((admin) => admin
///         .screen('/admin/users', (r) => const UsersPage())
///         .filter(RouteSecurity.preAuthorize("hasRole('ADMIN')")))
/// ```
///
/// Spring (Java): `AuthorizationFilter` with `authorizeHttpRequests`, and
/// the `LoginUrlAuthenticationEntryPoint` that sends to the login.
final class RouteSecurity implements RouteAuthorizationFilter {
  /// The guard: [handler] evaluates, [login] is where nobody logged in
  /// goes, [requests] keeps where they wanted to go.
  RouteSecurity({
    required this.requests,
    MethodSecurityExpressionHandler? handler,
    this.login,
  }) : handler = handler ?? MethodSecurityExpressionHandler();

  /// A filter of the routes it is added to: they open only when
  /// [expression] is `true` for the user. The [RouteSecurity] bean
  /// enforces it; without that bean the start fails.
  static RouteAuthorizationRequirement preAuthorize(String expression) =>
      _Requirement(expression);

  /// Keeps the address a guard turned away.
  final RouteRequestCache requests;

  /// Evaluates the expressions.
  final MethodSecurityExpressionHandler handler;

  /// The login route (`spring.flutter.navigation.login`), or `null`.
  final String? login;

  static const _signature = MethodSignature(
    name: 'open',
    declaringType: 'ScreenRoute',
    targetType: 'ScreenRoute',
  );

  @override
  RouteLocation? filter(RouteRequest request) {
    final route = request.route;
    if (route == null) {
      return null;
    }
    final expressions = [
      if (route.attributes[RouteAttributes.preAuthorize] case final String e) e,
      for (final requirement
          in route.filters.whereType<RouteAuthorizationRequirement>())
        requirement.expression,
    ];
    if (expressions.isEmpty) {
      return null;
    }
    final authentication = SecurityContextHolder.getContext().authentication;
    final root = handler.createRoot(() => authentication);
    for (final expression in expressions) {
      final bool allowed;
      try {
        allowed = handler.evaluate(
          expression,
          handler.createEvaluationContext(root, _signature, const []),
        );
      } on AuthenticationException {
        return _toLogin(request);
      }
      if (allowed) {
        continue;
      }
      if (root.isAuthenticated()) {
        _log.debug(() => 'Access to ${request.location} denied ($expression)');
        throw AccessDeniedException('Access to ${request.location} denied');
      }
      return _toLogin(request);
    }
    return null;
  }

  RouteLocation _toLogin(RouteRequest request) {
    final login = this.login;
    if (login == null || login.isEmpty) {
      throw AuthenticationCredentialsNotFoundException(
        'Nobody is logged in to open ${request.location}, and no login route '
        'is set (spring.flutter.navigation.login).',
      );
    }
    final target = RouteLocation.parse(login);
    if (request.location.path != target.path) {
      requests.save(request.location);
    }
    _log.debug(() => 'Sending ${request.location} to the login $login');
    return target;
  }
}

final class _Requirement implements RouteAuthorizationRequirement {
  const _Requirement(this.expression);

  @override
  final String expression;

  // Declares only; RouteSecurity enforces it.
  @override
  RouteLocation? filter(RouteRequest request) => null;

  @override
  String toString() => 'preAuthorize($expression)';
}

/// Follows the user: after a login, back to the address a guard sent to
/// the login; after a logout, the screen on top is opened again through
/// the guards, so a screen that needs a user goes.
final class RouteSecurityNavigator {
  /// Follows [principal] for [route], with the addresses [requests] kept.
  RouteSecurityNavigator(this.principal, this.route, this.requests)
    : _was = principal.authentication?.isAuthenticated ?? false {
    principal.addListener(_changed);
  }

  /// The logged-in user.
  final PrincipalNotifier principal;

  /// Navigates.
  final RouteTemplate route;

  /// The address to go back to.
  final RouteRequestCache requests;

  bool _was;

  void _changed() {
    final now = principal.authentication?.isAuthenticated ?? false;
    if (now == _was) {
      return;
    }
    _was = now;
    if (now) {
      final saved = requests.take();
      if (saved != null) {
        unawaited(route.go(saved));
      }
      return;
    }
    final RouteState current;
    try {
      current = route.state;
    } on StateError {
      return; // No screen yet.
    }
    unawaited(route.go(current.location));
  }

  /// Stops following the user.
  void dispose() => principal.removeListener(_changed);
}
