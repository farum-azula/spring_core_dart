import 'package:spring_core_dart/src/context/event/application_listener.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Dispatches events to listeners, like Spring's
/// `ApplicationEventMulticaster`.
///
/// The context uses a bean named `applicationEventMulticaster` if one
/// exists, otherwise a [SimpleApplicationEventMulticaster]. Implement it to
/// change dispatching (for example to deliver events asynchronously).
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

  /// Removes every listener (called when the context closes).
  void removeAllListeners();

  /// Listeners in invocation order.
  List<GenericApplicationListener> get applicationListeners;

  /// Delivers [event] to every listener that supports it.
  void multicastEvent(Object event);
}

/// Calls listeners synchronously in `Ordered` order, like Spring's
/// `SimpleApplicationEventMulticaster`.
///
/// Without an [errorHandler] the first listener error stops dispatching and
/// is rethrown (Spring's default).
///
/// ```dart
/// @Configuration()
/// class EventConfig {
///   @Bean()
///   ApplicationEventMulticaster applicationEventMulticaster() =>
///       SimpleApplicationEventMulticaster(
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
///   multicaster.setErrorHandler(t -> log.error("listener", t));
///   return multicaster;
/// }
/// ```
///
/// Unlike Spring there is no task executor: dispatching is always
/// synchronous.
class SimpleApplicationEventMulticaster implements ApplicationEventMulticaster {
  /// Creates a multicaster; see [errorHandler].
  SimpleApplicationEventMulticaster({this.errorHandler});

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
  void removeAllListeners() => _listeners.clear();

  /// Listeners sorted by order; equal orders keep insertion order.
  @override
  List<GenericApplicationListener> get applicationListeners =>
      OrderComparator.sort(_listeners);

  @override
  void multicastEvent(Object event) {
    // Iterates a sorted copy, so listeners may add or remove listeners
    // while an event is dispatched.
    for (final listener in applicationListeners) {
      if (!listener.supportsEvent(event)) {
        continue;
      }
      final handler = errorHandler;
      if (handler == null) {
        listener.onApplicationEvent(event);
        continue;
      }
      try {
        listener.onApplicationEvent(event);
      } catch (error, stackTrace) {
        handler(error, stackTrace);
      }
    }
  }
}
