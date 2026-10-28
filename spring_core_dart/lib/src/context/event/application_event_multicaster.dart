import 'package:spring_core_dart/src/context/event/application_listener.dart';
import 'package:spring_core_dart/src/context/task_executor.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// The part of the context that holds the listeners and delivers each
/// published event to those that accept it.
///
/// Applications rarely touch it: they publish through the context (or an
/// injected `ApplicationEventPublisher`) and listen with `@EventListener`.
/// The context uses a bean named `applicationEventMulticaster` if one
/// exists, otherwise a [SimpleApplicationEventMulticaster]. Declare such a
/// bean to change how events are delivered; for asynchronous delivery or
/// an error handler, configuring a [SimpleApplicationEventMulticaster] is
/// enough. Implement the interface only for a different dispatch strategy.
///
/// ```dart
/// // A multicaster on its own, outside a context.
/// final multicaster = SimpleApplicationEventMulticaster()
///   ..addApplicationListener(
///     ApplicationListenerAdapter.of<String>(log.info),
///   );
/// multicaster.multicastEvent('hello'); // prints "hello"
/// ```
///
/// Spring (Java):
/// ```java
/// var multicaster = new SimpleApplicationEventMulticaster();
/// multicaster.addApplicationListener(
///     ApplicationListener.forPayload((String text) -> log.info(text)));
/// multicaster.multicastEvent(new PayloadApplicationEvent<>(this, "hello"));
/// ```
abstract interface class ApplicationEventMulticaster {
  /// Adds [listener]; adding it again moves it to the end of the
  /// listeners with the same order.
  void addApplicationListener(GenericApplicationListener listener);

  /// Removes [listener]; does nothing if it is not there.
  void removeApplicationListener(GenericApplicationListener listener);

  /// Removes every listener [predicate] accepts, for example those of one
  /// bean that is being destroyed (Spring 5.3.5's
  /// `removeApplicationListeners(Predicate)`).
  ///
  /// ```dart
  /// multicaster.removeApplicationListeners((l) => l is AuditListener);
  /// ```
  void removeApplicationListeners(
    bool Function(GenericApplicationListener listener) predicate,
  );

  /// Removes every listener; the context calls it when it closes.
  void removeAllListeners();

  /// The listeners, in the order they are called.
  List<GenericApplicationListener> get applicationListeners;

  /// Delivers [event] to every listener whose `supportsEvent` accepts it.
  /// The context passes events already wrapped: a published object that
  /// is not an `ApplicationEvent` arrives as a `PayloadApplicationEvent`.
  void multicastEvent(Object event);
}

/// The standard [ApplicationEventMulticaster]: it calls the accepting
/// listeners in order, in the publishing call or on a task executor.
///
/// Every context has one. Declare your own as an
/// `applicationEventMulticaster` bean to deliver events asynchronously
/// (set [taskExecutor]: the publisher no longer waits for the listeners)
/// or to keep one failing listener from stopping the others (set
/// [errorHandler]).
///
/// Listeners are called by their `Ordered` order. Without an
/// [errorHandler], the first listener error stops the delivery and is
/// rethrown to the publisher (Spring's default); with a [taskExecutor] it
/// is left to the executor (a `SimpleAsyncTaskExecutor` logs it). A
/// listener's condition (`@EventListener(condition:)`) is evaluated inside
/// this error handling, on the executor when there is one, as in Spring.
///
/// ```dart
/// // Listeners run later, on the event loop; their errors are logged.
/// @Configuration()
/// class EventConfig {
///   @Bean()
///   ApplicationEventMulticaster applicationEventMulticaster() =>
///       SimpleApplicationEventMulticaster(
///         taskExecutor: SimpleAsyncTaskExecutor(),
///         errorHandler: (error, stack) => log.error('listener', error: error),
///       );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// ApplicationEventMulticaster applicationEventMulticaster() {
///   var multicaster = new SimpleApplicationEventMulticaster();
///   multicaster.setTaskExecutor(new SimpleAsyncTaskExecutor());
///   multicaster.setErrorHandler(t -> log.error("listener", t));
///   return multicaster;
/// }
/// ```
class SimpleApplicationEventMulticaster implements ApplicationEventMulticaster {
  /// Creates a multicaster; without arguments it is synchronous and
  /// rethrows listener errors.
  SimpleApplicationEventMulticaster({this.taskExecutor, this.errorHandler});

  /// Runs each listener call, so that the publisher does not wait (Spring's
  /// `setTaskExecutor`); `null` calls the listeners in the publishing call.
  /// Which listeners match is still decided when the event is published.
  TaskExecutor? taskExecutor;

  /// Receives the error of a failing listener, and the delivery goes on
  /// to the next one; `null` rethrows the error to the publisher. The
  /// context also sends the failures of asynchronous `@EventListener`
  /// methods here.
  void Function(Object error, StackTrace stackTrace)? errorHandler;

  final _listeners = <GenericApplicationListener>[];

  @override
  void addApplicationListener(GenericApplicationListener listener) {
    _listeners
      ..remove(listener)
      ..add(listener);
  }

  @override
  void removeApplicationListener(GenericApplicationListener listener) =>
      _listeners.remove(listener);

  @override
  void removeApplicationListeners(
    bool Function(GenericApplicationListener listener) predicate,
  ) => _listeners.removeWhere(predicate);

  @override
  void removeAllListeners() => _listeners.clear();

  /// The listeners sorted by order; equal orders keep the order in which
  /// they were added.
  @override
  List<GenericApplicationListener> get applicationListeners =>
      OrderComparator.sort(_listeners);

  @override
  void multicastEvent(Object event) {
    final executor = taskExecutor;
    // Iterates a sorted copy, so listeners may add or remove listeners
    // while an event is dispatched.
    for (final listener in applicationListeners) {
      if (!listener.supportsEvent(event)) {
        continue;
      }
      if (executor == null) {
        invokeListener(listener, event);
      } else {
        executor.execute(() => invokeListener(listener, event));
      }
    }
  }

  /// Calls [listener] with [event], handing an error to [errorHandler]
  /// when there is one. Override it to wrap each call, for example to time
  /// it or to set up a zone (Spring's `invokeListener`).
  void invokeListener(GenericApplicationListener listener, Object event) {
    final handler = errorHandler;
    if (handler == null) {
      listener.onApplicationEvent(event);
      return;
    }
    try {
      listener.onApplicationEvent(event);
    } on Object catch (error, stackTrace) {
      handler(error, stackTrace);
    }
  }
}
