import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    hide Banner, Size;

/// For display only: the server checks access. The logged-in user of the
/// app (the current `Authentication`) as a [Listenable], which notifies
/// on every login and logout.
///
/// A Flutter app shows who is logged in (a name in the app bar, a login
/// button or an account menu) and redraws when that changes. The user
/// lives in Spring Security's `SecurityContextHolder`, which tells nobody
/// when it changes; this bean listens to it and turns the changes into
/// notifications. It is a bean of every app with
/// `spring_boot_starter_flutter_security` (`principalNotifier`), and
/// widgets use it through `context.principal`, [PrincipalBuilder] and
/// [PrincipalView] rather than directly.
///
/// It sees a login or logout made in any of these ways:
///
/// - `SecurityContextHolder.setContext` and `clearContext` (a form login
///   of the app's own, a logout): at creation it wraps the holder's
///   strategy in a `ListeningSecurityContextHolderStrategy`;
/// - the authentication events (`AuthenticationSuccessEvent`,
///   `LogoutSuccessEvent`) that `OAuth2LoginService` and the
///   `AuthenticationManager` publish, for code that kept the strategy of
///   before.
///
/// Changing the `authentication` of a context object in place is not
/// seen; set a new context instead, as Spring Security advises.
///
/// Hiding a button is not security: the app is in the user's hands (it
/// can be patched, the API called directly), so only the server's checks
/// (a 403) protect anything. This only spares the user buttons that would
/// fail.
///
/// ```dart
/// // An app bar title that follows the user, without a widget of Spring.
/// class Greeting extends StatelessWidget {
///   const Greeting({super.key});
///
///   @override
///   Widget build(BuildContext context) =>
///       Text('Hello, ${context.principal?.name ?? 'guest'}');
/// }
/// ```
///
/// Spring has no such type: a server reads the user per request. The
/// nearest is Thymeleaf's `sec:authentication`, which reads it while a
/// page renders.
class PrincipalNotifier extends ChangeNotifier
    implements
        SecurityContextChangedListener,
        GenericApplicationListener,
        DisposableBean {
  /// A notifier holding the user logged in now, if any, and listening to
  /// the `SecurityContextHolder` from now on.
  PrincipalNotifier({
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  }) {
    _authentication = _current();
    final strategy = SecurityContextHolder.getContextHolderStrategy();
    if (strategy is ListeningSecurityContextHolderStrategy) {
      _strategy = strategy..addListener(this);
    } else {
      // Installed once and left in place: other notifiers (a context
      // started again after a hot reload, tests) add themselves to it.
      _strategy = ListeningSecurityContextHolderStrategy(strategy, [this]);
      SecurityContextHolder.setContextHolderStrategy(_strategy);
    }
  }

  /// Tells a real login from an anonymous user, who counts as nobody.
  final AuthenticationTrustResolver trustResolver;
  late final ListeningSecurityContextHolderStrategy _strategy;
  Authentication? _authentication;

  // The elements whose build read `context.principal`.
  final _dependents = <WeakReference<Element>>[];
  final _registered = Expando<bool>('PrincipalNotifier dependents');

  /// The user logged in now, or `null` when nobody is (or only an
  /// anonymous user is).
  Authentication? get authentication => _authentication;

  /// Whether someone is logged in.
  bool get isAuthenticated => _authentication != null;

  // The app-wide user: read outside every runWithContext scope, so work
  // run as another user (a job, a test) does not count.
  Authentication? _current() => Zone.root.run(() {
    final authentication = SecurityContextHolder.getContext().authentication;
    return trustResolver.isAuthenticated(authentication)
        ? authentication
        : null;
  });

  /// Reads the user again and notifies when it changed; called by the
  /// holder's strategy after each change.
  @override
  void securityContextChanged(SecurityContextChangedEvent event) => _refresh();

  /// Accepts the login and logout events.
  @override
  bool supportsEvent(Object event) => event is AbstractAuthenticationEvent;

  /// Reads the user again after a login or logout event.
  @override
  void onApplicationEvent(Object event) => _refresh();

  void _refresh() {
    final current = _current();
    if (identical(current, _authentication)) {
      return;
    }
    _authentication = current;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _rebuildDependents();
  }

  /// Makes the widget of [context] build again after each change; what
  /// `context.principal` calls. Only elements are tracked; it holds them
  /// weakly and forgets them once they are unmounted.
  void dependOn(BuildContext context) {
    if (context is! Element || _registered[context] != null) {
      return;
    }
    _registered[context] = true;
    _dependents.add(WeakReference(context));
  }

  void _rebuildDependents() {
    if (_dependents.isEmpty) {
      return;
    }
    // A change during a build (a login completed by a widget's build) is
    // applied after the frame: elements cannot be marked while building.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _rebuildDependents(),
      );
      return;
    }
    _dependents.removeWhere((reference) {
      final element = reference.target;
      if (element == null || !element.mounted) {
        return true;
      }
      element.markNeedsBuild();
      return false;
    });
  }

  /// Stops listening when the application context closes.
  @override
  void destroy() {
    _strategy.removeListener(this);
    _dependents.clear();
  }
}

/// `context.principal`: the logged-in user, for widgets.
extension PrincipalBuildContext on BuildContext {
  /// For display only: the server checks access. The user logged in now
  /// (`null` when nobody is), read from the [PrincipalNotifier] bean; the
  /// widget builds again when the user logs in or out.
  ///
  /// Call it in `build`:
  ///
  /// ```dart
  /// @override
  /// Widget build(BuildContext context) {
  ///   final user = context.principal;
  ///   return user == null
  ///       ? const LoginButton()
  ///       : Text('Hello, ${user.name}');
  /// }
  /// ```
  Authentication? get principal {
    final notifier = SpringScope.beanOf<PrincipalNotifier>(this)
      ..dependOn(this);
    return notifier.authentication;
  }
}
