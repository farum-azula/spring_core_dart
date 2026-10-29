import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_security/src/principal/principal_notifier.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    hide Banner, Size;

/// Builds the UI of the logged-in user's kind.
typedef PrincipalWidgetBuilder = Widget Function(
  BuildContext context,
  Authentication? authentication,
);

/// For display only: the server checks access. Builds with the user
/// logged in now (`null` when nobody is), again on every login and
/// logout.
///
/// Use it where part of the screen depends on who is logged in: a login
/// button or the user's name, an account menu. It listens to the
/// [PrincipalNotifier] bean, so only this part builds again.
///
/// ```dart
/// PrincipalBuilder(
///   builder: (context, authentication) => authentication == null
///       ? const LoginButton()
///       : Text('Hello, ${authentication.name}'),
/// )
/// ```
///
/// Spring has no widget; the nearest is Thymeleaf's
/// `sec:authentication="name"`, which a page reads while it renders.
class PrincipalBuilder extends StatelessWidget {
  /// A widget built by [builder] with the current authentication.
  const PrincipalBuilder({required this.builder, super.key});

  /// Builds the UI for the authentication (`null`: nobody logged in).
  final PrincipalWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final notifier = SpringScope.beanOf<PrincipalNotifier>(context);
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => builder(context, notifier.authentication),
    );
  }
}

/// For display only: the server checks access. Shows [child] when the
/// logged-in user matches, [otherwise] when not, and switches on every
/// login and logout.
///
/// It spares the user buttons that would fail: an admin menu for an
/// admin, a "Sign in" button for nobody. It protects nothing: the app is
/// in the user's hands (it can be patched, the API called directly), so
/// the server must check every request (a 403). The same holds for
/// `@PreAuthorize` on the app's own beans.
///
/// The conditions, all of which must hold (at least one is required):
///
/// - [hasRole]: the user has the role (`'ADMIN'` looks for
///   `ROLE_ADMIN`);
/// - [hasAuthority]: the user has the authority, written in full
///   (`'SCOPE_orders:write'`);
/// - [authenticated]: `true` for a logged-in user, `false` for nobody
///   logged in;
/// - [expression]: a security expression as in `@PreAuthorize`
///   (`"hasRole('ADMIN') or hasAuthority('SCOPE_admin')"`,
///   `"principal.username == 'ada'"`), evaluated by the application's
///   `MethodSecurityExpressionHandler` bean, so the role hierarchy and the
///   role prefix of the app apply to every condition.
///
/// ```dart
/// // Admins see the menu; everyone else nothing.
/// PrincipalView(
///   hasRole: 'ADMIN',
///   child: const AdminMenu(),
/// )
///
/// // A "Sign in" button only when nobody is logged in.
/// PrincipalView(
///   authenticated: false,
///   child: const SignInButton(),
///   otherwise: const AccountButton(),
/// )
/// ```
///
/// Spring (Thymeleaf), the same idea on a server page:
/// ```html
/// <div sec:authorize="hasRole('ADMIN')">...</div>
/// ```
class PrincipalView extends StatelessWidget {
  /// A view showing [child] when every given condition holds, [otherwise]
  /// (nothing by default) when one does not.
  const PrincipalView({
    required this.child,
    this.otherwise = const SizedBox.shrink(),
    this.hasRole,
    this.hasAuthority,
    this.authenticated,
    this.expression,
    super.key,
  }) : assert(
         hasRole != null ||
             hasAuthority != null ||
             authenticated != null ||
             expression != null,
         'PrincipalView needs a condition: hasRole, hasAuthority, '
         'authenticated or expression',
       );

  /// Shown when the user matches.
  final Widget child;

  /// Shown when the user does not match; nothing by default.
  final Widget otherwise;

  /// The role the user must have, without or with its prefix.
  final String? hasRole;

  /// The authority the user must have, written in full.
  final String? hasAuthority;

  /// `true`: someone must be logged in; `false`: nobody may be.
  final bool? authenticated;

  /// A security expression that must be `true` for the user, in the
  /// language of `@PreAuthorize`.
  final String? expression;

  static final _defaultHandler = MethodSecurityExpressionHandler();

  static const _signature = MethodSignature(
    name: 'build',
    declaringType: 'PrincipalView',
    targetType: 'PrincipalView',
  );

  /// Whether [authentication] matches every condition of this view.
  ///
  /// [handler] evaluates them (the application's
  /// `MethodSecurityExpressionHandler`). An [expression] that does not
  /// evaluate to a `bool` throws an [ArgumentError], as in method
  /// security; a missing user makes it `false`, never an error.
  bool matches(
    Authentication? authentication,
    MethodSecurityExpressionHandler handler,
  ) {
    final root = handler.createRoot(() => authentication);
    if (authenticated case final wanted?) {
      if (root.isAuthenticated() != wanted) {
        return false;
      }
    }
    if (hasRole case final role? when !root.hasRole(role)) {
      return false;
    }
    if (hasAuthority case final authority? when !root.hasAuthority(authority)) {
      return false;
    }
    if (expression case final text?) {
      try {
        return handler.evaluate(
          text,
          handler.createEvaluationContext(root, _signature, const []),
        );
      } on AuthenticationException {
        return false;
      } on ArgumentError {
        // `principal.username` with nobody logged in: no match. With a
        // user, a broken expression is the app's bug and is thrown.
        if (authentication == null) {
          return false;
        }
        rethrow;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final application = SpringScope.of(context);
    final notifier = application.getBean<PrincipalNotifier>();
    final handler =
        application.findBean<MethodSecurityExpressionHandler>() ??
        _defaultHandler;
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) =>
          matches(notifier.authentication, handler) ? child : otherwise,
    );
  }
}
