import 'dart:async';

/// Gives an advised bean access to its own proxy, so it can call itself
/// with the advice applied.
///
/// Advice runs only for calls that go through the proxy. When a bean calls
/// one of its own methods (`find` calling `count`), the call goes through
/// `this` and skips the advice: a `@Timed` or `@Cacheable` on the called
/// method has no effect. Inside a method called through a proxy,
/// [currentProxy] returns that proxy; calling the method on it applies the
/// advice. Injecting the bean into itself with `@Lazy()` is the other way.
///
/// ```dart
/// // Each find goes through the proxy, so @Timed applies to it.
/// @Service()
/// class BookService implements Books {
///   @Timed()
///   @override
///   Book find(String isbn) => ...;
///
///   @override
///   List<Book> findAll(List<String> isbns) => [
///     for (final isbn in isbns)
///       (AopContext.currentProxy() as Books).find(isbn),
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
/// returns `this`, and only the one call made right after it on that
/// object is advised. Call `currentProxy()` for every advised self-call,
/// as in the example above; a stored reference advises only its first
/// call.
abstract final class AopContext {
  /// Returns the proxy whose call is in progress; cast it to the bean's
  /// type to call it.
  ///
  /// Throws a [StateError] when no call through an AOP proxy is in
  /// progress. A bean that no advice matched has no proxy, so calling it
  /// from such a bean's own method fails unless an advised call is under
  /// way further up, whose proxy is then returned.
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
/// [AopContext.currentProxy]; it consumes the mark, so each
/// `currentProxy()` advises one call.
///
/// Used by `ProxyInvoker`; not exported.
bool takeCallThroughProxy(Object proxy) {
  if (identical(_throughProxy, proxy)) {
    _throughProxy = null;
    return true;
  }
  return false;
}

/// Marks the next call on [bean] as made through a reference to its proxy
/// (a `@Lazy` injection point resolved to it), not through `this`: when
/// [bean] is a subclass proxy whose own code is running, that call is
/// advised, as in Spring where the reference is the CGLIB proxy.
///
/// Used by `DefaultListableBeanFactory.lazyDependency`; not exported.
void callThroughProxyReference(Object bean) {
  if (isInProxyBody(bean)) {
    _throughProxy = bean;
  }
}

// Subclass proxies (the bean is its own proxy) whose own code runs: in
// the synchronous part of the call, and in the zone of a `Future` member.
final _bodies = <Object>[];
final _bodyZoneKey = Object();

/// Whether code of the subclass proxy [proxy] itself is running, so a
/// call it makes on itself is a self-call and not advised, as in Spring.
///
/// Used by `ProxyInvoker`; not exported.
bool isInProxyBody(Object proxy) =>
    _bodies.any((body) => identical(body, proxy)) ||
    ((Zone.current[_bodyZoneKey] as List<Object>?)?.any(
          (body) => identical(body, proxy),
        ) ??
        false);

/// Runs [body], the own code of the subclass proxy [proxy], and returns
/// its result; with [async], the code it schedules counts too (through a
/// zone).
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

/// Runs [body] with [proxy] as the current proxy, for the synchronous
/// part of a call.
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

/// Runs [body] with [proxy] as the current proxy, also in the code the
/// call schedules (through a zone), for members returning a `Future`.
///
/// Used by `ProxyInvoker`; not exported.
T runAsyncWithCurrentProxy<T>(Object proxy, T Function() body) => runZoned(
  () => runWithCurrentProxy(proxy, body),
  zoneValues: {_zoneKey: proxy},
);
