import 'dart:async';

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
  SecurityContextImpl([this.authentication]);

  @override
  Authentication? authentication;

  @override
  bool operator ==(Object other) =>
      other is SecurityContextImpl && other.authentication == authentication;

  @override
  int get hashCode => authentication.hashCode;

  @override
  String toString() =>
      'SecurityContextImpl ['
      // The interpolation cannot be wrapped (dart format keeps it).
      // ignore: lines_longer_than_80_chars
      '${authentication == null ? 'Null authentication' : 'Authentication=$authentication'}]';
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
  ZoneSecurityContextHolderStrategy();

  // Each strategy has its own key: scopes of one strategy are invisible to
  // another.
  final Object _key = Object();
  final _Holder _global = _Holder();

  _Holder get _holder => Zone.current[_key] as _Holder? ?? _global;

  /// Whether the caller runs inside a [runWithContext] scope of this
  /// strategy; `false` means it uses the program-wide context.
  bool get isScoped => Zone.current[_key] is _Holder;

  @override
  SecurityContext getContext() => _holder.context ??= createEmptyContext();

  @override
  void setContext(SecurityContext context) => _holder.context = context;

  @override
  void clearContext() => _holder.context = null;

  @override
  SecurityContext createEmptyContext() => SecurityContextImpl();

  @override
  R runWithContext<R>(R Function() body, [SecurityContext? context]) =>
      runZoned(body, zoneValues: {_key: _Holder()..context = context});
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
  SecurityContext getContext() => _context ??= createEmptyContext();

  @override
  void setContext(SecurityContext context) => _context = context;

  @override
  void clearContext() => _context = null;

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
    _context = context;
    try {
      return body();
    } finally {
      _context = previous;
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
  static SecurityContext getContext() => _strategy.getContext();

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
