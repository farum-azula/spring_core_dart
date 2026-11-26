import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart'
    show
        CallerBoundReads,
        CallerContextPropagation,
        CallerContexts,
        CallerIdentitySource;
import 'package:spring_security_core/src/core/authentication.dart';

/// A small box holding the [authentication] of the current user, or
/// `null` when nobody is logged in.
///
/// Security checks never take the user as a parameter: they read it from
/// the current context, which [SecurityContextHolder] keeps. On a server
/// each request has its own context; in a Flutter app there is one for
/// the whole app. You meet it when you log a user in (store a new context
/// holding the result) or read who is calling.
///
/// Spring (Java): `SecurityContext`, the same interface.
abstract interface class SecurityContext {
  /// The user of this context, or `null` when nobody is logged in.
  Authentication? get authentication;

  /// Replaces the user of this context; `null` logs out.
  ///
  /// At a login, prefer storing a new context with
  /// `SecurityContextHolder.setContext`: a context object may be shared
  /// with other code.
  set authentication(Authentication? value);
}

/// The standard [SecurityContext]: a mutable field and nothing else.
///
/// Create one to log a user in or to run code as someone.
///
/// ```dart
/// // After a successful login in a Flutter app.
/// SecurityContextHolder.setContext(SecurityContextImpl(result));
/// ```
///
/// Spring (Java): `new SecurityContextImpl(result)`.
final class SecurityContextImpl implements SecurityContext {
  /// A context holding [authentication]; empty when it is omitted.
  SecurityContextImpl([this._authentication]);

  Authentication? _authentication;

  @override
  Authentication? get authentication {
    CallerBoundReads.note(const SecurityCallerSource());
    return _authentication;
  }

  // Whoever kept a value for the user there was is told.
  @override
  set authentication(Authentication? value) {
    if (identical(value, _authentication)) {
      return;
    }
    _authentication = value;
    CallerBoundReads.callerChanged();
  }

  @override
  bool operator ==(Object other) =>
      other is SecurityContextImpl && other._authentication == _authentication;

  @override
  int get hashCode => _authentication.hashCode;

  @override
  String toString() =>
      'SecurityContextImpl ['
      // The interpolation cannot be wrapped (dart format keeps it).
      // ignore: lines_longer_than_80_chars
      '${_authentication == null ? 'Null authentication' : 'Authentication=$_authentication'}]';
}

/// Says who the caller is, for what keeps values
/// ([CallerBoundReads]): the authentication of the current context.
final class SecurityCallerSource implements CallerIdentitySource {
  /// The source over [strategy]; without one, over the strategy of
  /// [SecurityContextHolder] at each read.
  const SecurityCallerSource([this.strategy]);

  /// Where the user is read.
  final SecurityContextHolderStrategy? strategy;

  // A token whose authentication was taken back is nobody's: a new object
  // each time, so that nothing kept for it is handed out again.
  @override
  Object? currentCaller() {
    final user = (strategy ?? SecurityContextHolder.getContextHolderStrategy())
        .getContext()
        .authentication;
    return user == null || user.isAuthenticated ? user : Object();
  }

  @override
  bool operator ==(Object other) =>
      other is SecurityCallerSource && identical(other.strategy, strategy);

  @override
  int get hashCode => identityHashCode(strategy);
}

/// Runs code later as the user of the moment it was captured: an effect
/// of the Flutter signals starter runs again as the user it was made for,
/// never as the user whose change ran it. With the default strategy a
/// capture outside every scope stands for the program-wide user (who that
/// is when the code runs); inside a scope, for that scope's context.
final class SecurityCallerContext implements CallerContextPropagation {
  /// The propagation over [SecurityContextHolder]'s strategy.
  const SecurityCallerContext();

  @override
  Object? capture() =>
      switch (SecurityContextHolder.getContextHolderStrategy()) {
        final ZoneSecurityContextHolderStrategy zones => zones.captureCaller(),
        final other => CallerBoundReads.quietly(other.getContext),
      };

  @override
  R runAs<R>(Object? captured, R Function() body) =>
      switch (SecurityContextHolder.getContextHolderStrategy()) {
        final ZoneSecurityContextHolderStrategy zones => zones.runAsCaller(
          captured,
          body,
        ),
        final other when captured is SecurityContext => other.runWithContext(
          body,
          captured,
        ),
        _ => body(),
      };
}

/// The rule that decides which [SecurityContext] is "current": one per
/// request, one per program, or something else.
///
/// [SecurityContextHolder] passes every call on to a strategy. The default,
/// [ZoneSecurityContextHolderStrategy], suits both servers and Flutter
/// apps, so applications almost never write or choose one.
///
/// Spring (Java): `SecurityContextHolderStrategy`; Spring keeps contexts
/// per thread, this package per `Zone`.
abstract interface class SecurityContextHolderStrategy {
  /// The current context; an empty one is created and stored when there
  /// is none, so the result is never `null`.
  SecurityContext getContext();

  /// Makes [context] the current one, in the current scope only.
  void setContext(SecurityContext context);

  /// Removes the current context; the next [getContext] creates an empty
  /// one.
  void clearContext();

  /// A new context with no user, not yet stored anywhere.
  SecurityContext createEmptyContext();

  /// Runs [body] with its own [context] (an empty one when omitted) and
  /// returns what [body] returns.
  ///
  /// The context is current in [body] and in everything it starts
  /// (`await`, timers, streams), and gone afterwards. Contexts of scopes
  /// running at the same time, such as two requests, never mix. Changes
  /// made inside (a login, [clearContext]) stay inside.
  R runWithContext<R>(R Function() body, [SecurityContext? context]);
}

/// The default strategy: each [runWithContext] scope has its own context,
/// and code outside every scope shares one program-wide context.
///
/// A Dart server handles many requests at once on one thread, switching
/// between them at each `await`, so "the current user" cannot be a global
/// variable. A `Zone` follows the work of one request across its `await`s,
/// timers and streams; this strategy stores the context in it. The
/// security filter chain runs every request in its own scope, so a
/// request sees only its user.
///
/// Outside every scope there is one context for the whole program: what a
/// Flutter app wants for its logged-in user, and what a server's own
/// background work (not a request) sees.
///
/// Spring (Java): `ThreadLocalSecurityContextHolderStrategy` inside a
/// scope (a `Zone` plays the role of the thread), and `MODE_GLOBAL`
/// outside.
final class ZoneSecurityContextHolderStrategy
    implements SecurityContextHolderStrategy {
  /// A strategy whose program-wide context starts empty.
  ///
  /// Each instance has its own scopes: a scope opened by one strategy is
  /// invisible to another.
  ZoneSecurityContextHolderStrategy() {
    CallerContexts.register(const SecurityCallerContext());
  }

  /// Where the current code takes its context from: its scope, or the
  /// program-wide context; for [runAsCaller].
  Object captureCaller() => _holder;

  /// Runs [body] with the context [captured] (a [captureCaller]) came
  /// from: a scope's own, or the program-wide one even inside a scope.
  R runAsCaller<R>(Object? captured, R Function() body) => captured is _Holder
      ? runZoned(body, zoneValues: {_key: captured})
      : body();

  // Each strategy has its own key: scopes of one strategy are invisible to
  // another.
  final Object _key = Object();
  final _Holder _global = _Holder();

  _Holder get _holder => Zone.current[_key] as _Holder? ?? _global;

  /// Whether the caller runs inside a [runWithContext] scope of this
  /// strategy; `false` means it uses the program-wide context.
  bool get isScoped => Zone.current[_key] is _Holder;

  /// Told each time an authentication is put into the program-wide
  /// context (set outside every scope), with where it was set; nothing is
  /// told by default.
  ///
  /// In a Flutter app that is the login. On a server it is rarely meant:
  /// the authentication stays after the work that set it, and all the code
  /// that runs outside a request (scheduled work, listeners, timers) then
  /// acts as that user. The security starter logs it through this.
  ///
  /// Differs from Spring: Spring has no such report; a `ThreadLocal` left
  /// set on a pooled thread is found there with a debugger.
  void Function(Authentication authentication, StackTrace where)?
  onProgramWideAuthentication;

  /// The authentication of the program-wide context: who all the code
  /// outside a scope acts as; `null` when nobody.
  Authentication? get programWideAuthentication =>
      _global.context?.authentication;

  void _reportProgramWide(Authentication authentication) =>
      onProgramWideAuthentication?.call(authentication, StackTrace.current);

  @override
  SecurityContext getContext() {
    CallerBoundReads.note(const SecurityCallerSource());
    final holder = _holder;
    return holder.context ??= identical(holder, _global)
        ? _ProgramWideContext(this)
        : createEmptyContext();
  }

  @override
  void setContext(SecurityContext context) {
    final holder = _holder;
    final before = _userOf(holder.context);
    holder.context = context;
    if (identical(holder, _global)) {
      final user = _userOf(context);
      if (user != null) {
        _reportProgramWide(user);
      }
      if (!identical(before, user)) {
        CallerBoundReads.callerChanged();
      }
    }
  }

  @override
  void clearContext() {
    final holder = _holder;
    final before = _userOf(holder.context);
    holder.context = null;
    if (identical(holder, _global) && before != null) {
      CallerBoundReads.callerChanged();
    }
  }

  // Storing a user is no read of the current one.
  static Authentication? _userOf(SecurityContext? context) =>
      CallerBoundReads.quietly(() => context?.authentication);

  @override
  SecurityContext createEmptyContext() => SecurityContextImpl();

  @override
  R runWithContext<R>(R Function() body, [SecurityContext? context]) =>
      runZoned(body, zoneValues: {_key: _Holder()..context = context});
}

// The context outside every scope: an authentication put into it is
// reported.
final class _ProgramWideContext extends SecurityContextImpl {
  _ProgramWideContext(this._strategy);

  final ZoneSecurityContextHolderStrategy _strategy;

  @override
  set authentication(Authentication? value) {
    super.authentication = value;
    if (value != null) {
      _strategy._reportProgramWide(value);
    }
  }
}

/// A strategy with exactly one context for the whole program.
///
/// Never use it on a server: all requests would share one user. Even in a
/// Flutter app the default [ZoneSecurityContextHolderStrategy] already
/// gives one program-wide context outside scopes, so this one is only for
/// code that wants scopes ignored.
///
/// Spring (Java): `GlobalSecurityContextHolderStrategy` (`MODE_GLOBAL`).
final class GlobalSecurityContextHolderStrategy
    implements SecurityContextHolderStrategy {
  /// A strategy whose only context starts empty.
  GlobalSecurityContextHolderStrategy();

  SecurityContext? _context;

  @override
  SecurityContext getContext() {
    CallerBoundReads.note(const SecurityCallerSource());
    return _context ??= createEmptyContext();
  }

  @override
  void setContext(SecurityContext context) => _replace(context);

  @override
  void clearContext() => _replace(null);

  void _replace(SecurityContext? context) {
    final before = CallerBoundReads.quietly(() => _context?.authentication);
    final user = CallerBoundReads.quietly(() => context?.authentication);
    _context = context;
    if (!identical(before, user)) {
      CallerBoundReads.callerChanged();
    }
  }

  @override
  SecurityContext createEmptyContext() => SecurityContextImpl();

  /// Makes [context] the program's context while [body] runs, then puts
  /// back the one before.
  ///
  /// Nothing is isolated: other code running at the same time sees
  /// [context] too. The old context comes back as soon as [body] returns,
  /// so for an `async` [body] it comes back at its first `await`, not when
  /// its `Future` completes.
  @override
  R runWithContext<R>(R Function() body, [SecurityContext? context]) {
    final previous = _context;
    _replace(context);
    try {
      return body();
    } finally {
      _replace(previous);
    }
  }
}

final class _Holder {
  SecurityContext? context;
}

/// The entry point to the current user: static methods that read, set and
/// scope the current [SecurityContext].
///
/// Every security check reads the user from here, so code never passes the
/// user around. You use it to find out who is calling, to log a user in
/// (in a Flutter app or a custom login), and to run work as a given user.
/// On a server the starter's filter chain gives every request its own
/// context; outside every scope there is one context for the whole
/// program. The calls go to a [SecurityContextHolderStrategy],
/// [ZoneSecurityContextHolderStrategy] unless you change it.
///
/// ```dart
/// // Who is calling?
/// final user = SecurityContextHolder.getContext().authentication;
///
/// // A nightly job calls secured services as a system user, in a scope
/// // of its own so no request sees that user.
/// await SecurityContextHolder.runWithContext(
///   () => reports.generate(),
///   SecurityContextImpl(
///     TestingAuthenticationToken('system', null, ['ROLE_SYSTEM']),
///   ),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// Authentication user =
///     SecurityContextHolder.getContext().getAuthentication();
/// ```
abstract final class SecurityContextHolder {
  static SecurityContextHolderStrategy _strategy =
      ZoneSecurityContextHolderStrategy();

  /// The strategy in use; a [ZoneSecurityContextHolderStrategy] unless
  /// [setContextHolderStrategy] replaced it.
  static SecurityContextHolderStrategy getContextHolderStrategy() => _strategy;

  /// Replaces the strategy for the whole program.
  ///
  /// Call it once at startup, before any context is stored: contexts kept
  /// by the old strategy are not carried over, and nothing checks this.
  // Spring's method, public API next to getContextHolderStrategy().
  // ignore: use_setters_to_change_properties
  static void setContextHolderStrategy(
    SecurityContextHolderStrategy strategy,
  ) => _strategy = strategy;

  /// The current context, never `null` (an empty one is created when
  /// there is none). Read `.authentication` on it for the user.
  static SecurityContext getContext() {
    CallerBoundReads.note(const SecurityCallerSource());
    return _strategy.getContext();
  }

  /// Makes [context] current in the current scope; this is how a login
  /// takes effect.
  static void setContext(SecurityContext context) =>
      _strategy.setContext(context);

  /// Removes the current context of the current scope, which logs the
  /// user out of it.
  static void clearContext() => _strategy.clearContext();

  /// A new context with no user, not yet stored anywhere.
  static SecurityContext createEmptyContext() => _strategy.createEmptyContext();

  /// Runs [body] as the user of [context] (no user when omitted) and
  /// returns its result.
  ///
  /// With the default strategy the context is current in [body] and in
  /// everything it starts, also after `await`, and nowhere else. Use it
  /// for jobs and tests that call secured methods.
  static R runWithContext<R>(R Function() body, [SecurityContext? context]) =>
      _strategy.runWithContext(body, context);
}
