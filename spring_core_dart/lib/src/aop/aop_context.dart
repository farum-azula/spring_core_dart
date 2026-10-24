import 'dart:async';

/// The AOP proxy of the call in progress, like Spring's `AopContext`.
///
/// Inside a method called through a proxy, [currentProxy] returns that
/// proxy, so the bean can call itself *through* the proxy and get the
/// advice applied (a plain `this.method()` call skips it).
///
/// ```dart
/// @Service()
/// class BookService implements Books {
///   @Timed()
///   @override
///   Book find(String isbn) => ...;
///
///   @override
///   List<Book> findAll(List<String> isbns) => [
///     for (final isbn in isbns) (AopContext.currentProxy() as Books).find(isbn),
///   ];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EnableAspectJAutoProxy(exposeProxy = true)
/// ...
/// ((Books) AopContext.currentProxy()).find(isbn);
/// ```
///
/// Unlike Spring, the proxy is always exposed (there is no `exposeProxy`
/// flag). It is available during the synchronous part of a call and, for
/// methods returning a `Future` (or `FutureOr`), in the asynchronous code
/// that call starts.
///
/// A generated subclass proxy is the bean itself, so `currentProxy()`
/// returns `this`: the call made right after it on that object is
/// advised (call `currentProxy()` for every advised self-call, as in the
/// example above; a stored reference advises only its first call).
abstract final class AopContext {
  /// The proxy whose call is in progress.
  ///
  /// Throws a [StateError] outside a call through an AOP proxy.
  static Object currentProxy() {
    final proxy =
        _current ??
        Zone.current[_zoneKey] as Object? ??
        (throw StateError(
          'Cannot find current proxy: AopContext.currentProxy() was called '
          'outside a method invoked through an AOP proxy (only beans matched '
          'by advice are proxied).',
        ));
    _throughProxy = proxy;
    return proxy;
  }
}

// The proxy whose next call comes through `currentProxy()`: a subclass
// proxy advises it although its body is running.
Object? _throughProxy;

/// Whether the call on [proxy] that starts now was made through
/// [AopContext.currentProxy] (one call per `currentProxy()`).
///
/// Used by `ProxyInvoker`; not exported.
bool takeCallThroughProxy(Object proxy) {
  if (identical(_throughProxy, proxy)) {
    _throughProxy = null;
    return true;
  }
  return false;
}

// Subclass proxies (the bean is its own proxy) whose own code runs: in
// the synchronous part of the call, and in the zone of a `Future` member.
final _bodies = <Object>[];
final _bodyZoneKey = Object();

/// Whether code of the subclass proxy [proxy] itself is running (a call
/// it makes on itself is a self-call, not advised as in Spring).
///
/// Used by `ProxyInvoker`; not exported.
bool isInProxyBody(Object proxy) =>
    _bodies.any((body) => identical(body, proxy)) ||
    ((Zone.current[_bodyZoneKey] as List<Object>?)?.any(
          (body) => identical(body, proxy),
        ) ??
        false);

/// Runs [body], the own code of the subclass proxy [proxy]; with [async],
/// the code it schedules counts too (a zone).
///
/// Used by `ProxyInvoker`; not exported.
T runProxyBody<T>(Object proxy, T Function() body, {bool async = false}) {
  _bodies.add(proxy);
  try {
    if (!async) {
      return body();
    }
    final outer = Zone.current[_bodyZoneKey] as List<Object>? ?? const [];
    return runZoned(
      body,
      zoneValues: {
        _bodyZoneKey: [...outer, proxy],
      },
    );
  } finally {
    _bodies.removeLast();
    if (identical(_throughProxy, proxy)) {
      _throughProxy = null;
    }
  }
}

// The proxy of the synchronous call in progress.
Object? _current;

// Zone value carrying the proxy into asynchronous continuations.
final _zoneKey = Object();

/// Runs [body] as part of a call through [proxy] (synchronous part).
///
/// Used by `ProxyInvoker`; not exported.
T runWithCurrentProxy<T>(Object proxy, T Function() body) {
  final previous = _current;
  _current = proxy;
  try {
    return body();
  } finally {
    _current = previous;
  }
}

/// Runs [body] as part of an asynchronous call through [proxy]: the proxy
/// stays current in the code the call schedules.
///
/// Used by `ProxyInvoker`; not exported.
T runAsyncWithCurrentProxy<T>(Object proxy, T Function() body) => runZoned(
  () => runWithCurrentProxy(proxy, body),
  zoneValues: {_zoneKey: proxy},
);
