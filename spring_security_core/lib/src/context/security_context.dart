import 'dart:async';

import 'package:spring_security_core/src/core/authentication.dart';

/// Holds the [authentication] of the current request or user, like
/// Spring's `SecurityContext`.
abstract interface class SecurityContext {
  /// The current authentication, or `null`.
  Authentication? get authentication;

  /// Replaces the authentication.
  set authentication(Authentication? value);
}

/// The plain [SecurityContext], like Spring's `SecurityContextImpl`.
final class SecurityContextImpl implements SecurityContext {
  /// A context holding [authentication].
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

/// Where the current [SecurityContext] is kept, like Spring's
/// `SecurityContextHolderStrategy`.
abstract interface class SecurityContextHolderStrategy {
  /// The current context (created empty when there is none).
  SecurityContext getContext();

  /// Makes [context] the current one.
  void setContext(SecurityContext context);

  /// Forgets the current context.
  void clearContext();

  /// A new, empty context.
  SecurityContext createEmptyContext();

  /// Runs [body] with its own [context] (a new empty one by default): the
  /// context is current in [body] and in everything it starts (`await`,
  /// timers, streams), and gone afterwards. Contexts of scopes running at
  /// the same time (two requests) never mix.
  R runWithContext<R>(R Function() body, [SecurityContext? context]);
}

/// The default strategy: one context per `Zone` scope, like Spring's
/// `ThreadLocalSecurityContextHolderStrategy` — in Dart work continues on
/// other turns of the event loop rather than on a thread, and a `Zone`
/// follows it there.
///
/// The security filter chain runs every request in its own scope
/// ([runWithContext]), so a request sees only its user. Outside every
/// scope there is one context for the whole program, like Spring's
/// `MODE_GLOBAL`: what a Flutter app wants for its logged-in user, and
/// what a server's own background work (not a request) sees.
final class ZoneSecurityContextHolderStrategy
    implements SecurityContextHolderStrategy {
  /// A strategy whose program-wide context starts empty.
  ZoneSecurityContextHolderStrategy();

  // Each strategy has its own key: scopes of one strategy are invisible to
  // another.
  final Object _key = Object();
  final _Holder _global = _Holder();

  _Holder get _holder => Zone.current[_key] as _Holder? ?? _global;

  /// Whether the caller runs inside a [runWithContext] scope (not on the
  /// program-wide context).
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

/// One context for the whole program, ignoring scopes, like Spring's
/// `GlobalSecurityContextHolderStrategy` (`MODE_GLOBAL`). Never for a
/// server: requests would share their user.
final class GlobalSecurityContextHolderStrategy
    implements SecurityContextHolderStrategy {
  /// A strategy whose context starts empty.
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

  /// Runs [body] with [context] as the program's context, then restores
  /// the one before (no isolation between concurrent callers).
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

/// The current [SecurityContext], like Spring's `SecurityContextHolder`.
///
/// ```dart
/// final user = SecurityContextHolder.getContext().authentication;
///
/// // A scope with its own user (a job running as someone):
/// SecurityContextHolder.runWithContext(
///   () => reports.generate(),
///   SecurityContextImpl(TestingAuthenticationToken('system', null)),
/// );
/// ```
abstract final class SecurityContextHolder {
  static SecurityContextHolderStrategy _strategy =
      ZoneSecurityContextHolderStrategy();

  /// The strategy in use ([ZoneSecurityContextHolderStrategy] unless set).
  static SecurityContextHolderStrategy getContextHolderStrategy() => _strategy;

  /// Replaces the strategy (before anything was stored).
  // Spring's method, public API next to getContextHolderStrategy().
  // ignore: use_setters_to_change_properties
  static void setContextHolderStrategy(
    SecurityContextHolderStrategy strategy,
  ) => _strategy = strategy;

  /// The current context.
  static SecurityContext getContext() => _strategy.getContext();

  /// Makes [context] current.
  static void setContext(SecurityContext context) =>
      _strategy.setContext(context);

  /// Forgets the current context.
  static void clearContext() => _strategy.clearContext();

  /// A new empty context.
  static SecurityContext createEmptyContext() => _strategy.createEmptyContext();

  /// Runs [body] in its own scope with [context]; see
  /// [SecurityContextHolderStrategy.runWithContext].
  static R runWithContext<R>(R Function() body, [SecurityContext? context]) =>
      _strategy.runWithContext(body, context);
}
