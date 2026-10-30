/// A bean whose start finishes only after the context's refresh, such as
/// a web server whose socket is bound asynchronously.
///
/// In Spring a server binds its port inside the refresh, so a port in use
/// fails the start: no `ApplicationReadyEvent`, no runners, a non-zero
/// exit code. Dart binds sockets asynchronously, after the synchronous
/// lifecycle start. A bean implementing this lets `SpringApplication`
/// wait for it: once the context is refreshed, the application calls
/// [awaitStartup] on every singleton of this type and waits for all of
/// them before it logs the startup line, publishes
/// `ApplicationStartedEvent`, calls the runners and publishes
/// `ApplicationReadyEvent`. A failure counts as a failed refresh: the
/// `ApplicationFailedEvent`, the failure report, the context closed, and
/// the error thrown by `runAsync` (or, from `run`, uncaught).
///
/// Applications rarely implement it; the web starter's
/// `WebServerStartStopLifecycle` does.
///
/// ```dart
/// // A lifecycle bean that opens a socket when the context starts.
/// final class MetricsListener with SmartLifecycle implements AsyncStartup {
///   final _bound = Completer<void>();
///
///   @override
///   void start() => ServerSocket.bind('127.0.0.1', 9100)
///       .then((_) => _bound.complete(), onError: _bound.completeError);
///
///   @override
///   Future<void> awaitStartup() => _bound.future;
///   ...
/// }
/// ```
///
/// Spring has no counterpart: `SmartLifecycle.start()` blocks there.
abstract interface class AsyncStartup {
  /// Completes when the bean has started, or fails with the reason it
  /// could not. Whoever calls it takes over reporting the failure: the
  /// bean then does not report it or close the context itself.
  Future<void> awaitStartup();
}
