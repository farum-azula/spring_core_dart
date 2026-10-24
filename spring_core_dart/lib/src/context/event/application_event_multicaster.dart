import 'package:spring_core_dart/src/context/event/application_listener.dart';
import 'package:spring_core_dart/src/context/task_executor.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Dispatches events to listeners, like Spring's
/// `ApplicationEventMulticaster`.
///
/// The context uses a bean named `applicationEventMulticaster` if one
/// exists, otherwise a [SimpleApplicationEventMulticaster]. Implement it to
/// change dispatching (asynchronous delivery is built in: see
/// [SimpleApplicationEventMulticaster.taskExecutor]).
///
/// ```dart
/// final multicaster = SimpleApplicationEventMulticaster()
///   ..addApplicationListener(
///     ApplicationListenerAdapter.of<String>(print),
///   );
/// multicaster.multicastEvent('hello'); // prints "hello"
/// ```
///
/// Spring (Java):
/// ```java
/// var multicaster = new SimpleApplicationEventMulticaster();
/// multicaster.addApplicationListener(
///     ApplicationListener.forPayload(System.out::println));
/// multicaster.multicastEvent(new PayloadApplicationEvent<>(this, "hello"));
/// ```
abstract interface class ApplicationEventMulticaster {
  /// Adds [listener]; adding it again moves it to the end.
  void addApplicationListener(GenericApplicationListener listener);

  /// Removes [listener] if present.
  void removeApplicationListener(GenericApplicationListener listener);

  /// Removes the listeners [predicate] accepts (Spring 5.3.5's
  /// `removeApplicationListeners(Predicate)`), e.g. those of one bean.
  ///
  /// ```dart
  /// multicaster.removeApplicationListeners((l) => l is AuditListener);
  /// ```
  void removeApplicationListeners(
    bool Function(GenericApplicationListener listener) predicate,
  );

  /// Removes every listener (called when the context closes).
  void removeAllListeners();

  /// Listeners in invocation order.
  List<GenericApplicationListener> get applicationListeners;

  /// Delivers [event] to every listener that supports it.
  void multicastEvent(Object event);
}

/// Calls listeners in `Ordered` order, like Spring's
/// `SimpleApplicationEventMulticaster`: synchronously, or each on the
/// [taskExecutor] when one is set.
///
/// Without an [errorHandler] the first listener error stops dispatching and
/// is rethrown (Spring's default); with a [taskExecutor] it is left to the
/// executor (a `SimpleAsyncTaskExecutor` logs it). A listener's condition
/// (`@EventListener(condition:)`) is evaluated inside this error handling,
/// on the executor when there is one, like in Spring.
///
/// ```dart
/// @Configuration()
/// class EventConfig {
///   @Bean()
///   ApplicationEventMulticaster applicationEventMulticaster() =>
///       SimpleApplicationEventMulticaster(
///         taskExecutor: SimpleAsyncTaskExecutor(),
///         errorHandler: (error, stack) => log.severe('listener', error),
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
  /// Creates a multicaster; see [taskExecutor] and [errorHandler].
  SimpleApplicationEventMulticaster({this.taskExecutor, this.errorHandler});

  /// Runs each listener invocation (Spring's `setTaskExecutor`); `null`
  /// calls the listeners on the publishing call. Which listeners match is
  /// decided when the event is published.
  TaskExecutor? taskExecutor;

  /// Receives listener errors instead of rethrowing them.
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

  /// Listeners sorted by order; equal orders keep insertion order.
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
  /// when there is one (Spring's `invokeListener`); override it to wrap
  /// each invocation.
  void invokeListener(GenericApplicationListener listener, Object event) {
    final handler = errorHandler;
    if (handler == null) {
      listener.onApplicationEvent(event);
      return;
    }
    try {
      listener.onApplicationEvent(event);
    } catch (error, stackTrace) {
      handler(error, stackTrace);
    }
  }
}
