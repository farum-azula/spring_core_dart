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
abstract final class AopContext {
  /// The proxy whose call is in progress.
  ///
  /// Throws a [StateError] outside a call through an AOP proxy.
  static Object currentProxy() =>
      _current ??
      Zone.current[_zoneKey] as Object? ??
      (throw StateError(
        'Cannot find current proxy: AopContext.currentProxy() was called '
        'outside a method invoked through an AOP proxy (only beans matched '
        'by advice are proxied).',
      ));
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
