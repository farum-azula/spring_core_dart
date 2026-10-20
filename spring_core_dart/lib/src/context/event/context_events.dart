import 'package:spring_core_dart/src/context/application_context.dart';
import 'package:spring_core_dart/src/context/event/application_event.dart';

/// An event raised by an application context, like Spring's
/// `ApplicationContextEvent`.
///
/// Listen to it to react to every context event.
///
/// ```dart
/// @Component()
/// class ContextLog {
///   @EventListener()
///   void on(ApplicationContextEvent event) =>
///       print('${event.runtimeType} of ${event.applicationContext.id}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void on(ApplicationContextEvent event) { ... }
/// ```
abstract class ApplicationContextEvent extends ApplicationEvent {
  /// Creates an event raised by the context [source].
  ApplicationContextEvent(ApplicationContext super.source);

  /// The context that raised the event (same as `source`).
  ApplicationContext get applicationContext => source as ApplicationContext;
}

/// The context was refreshed: all eager singletons exist.
///
/// Published at the end of `refresh()`, after auto-startup lifecycle beans
/// were started.
///
/// ```dart
/// @Component()
/// class Warmup {
///   @EventListener()
///   void onReady(ContextRefreshedEvent event) => print('ready');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onReady(ContextRefreshedEvent event) { ... }
/// ```
class ContextRefreshedEvent extends ApplicationContextEvent {
  /// Creates the event for the context [source].
  ContextRefreshedEvent(super.source);
}

/// `start()` was called on the context.
///
/// ```dart
/// context.addListener<ContextStartedEvent>((_) => print('started'));
/// context.start();
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onStart(ContextStartedEvent event) { ... }
/// ```
class ContextStartedEvent extends ApplicationContextEvent {
  /// Creates the event for the context [source].
  ContextStartedEvent(super.source);
}

/// `stop()` was called on the context.
///
/// ```dart
/// context.addListener<ContextStoppedEvent>((_) => print('stopped'));
/// context.stop();
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onStop(ContextStoppedEvent event) { ... }
/// ```
class ContextStoppedEvent extends ApplicationContextEvent {
  /// Creates the event for the context [source].
  ContextStoppedEvent(super.source);
}

/// The context is closing; beans are still available.
///
/// Published first in `close()`, before lifecycle beans are stopped and
/// singletons destroyed.
///
/// ```dart
/// @Component()
/// class SessionStore {
///   @EventListener()
///   void onClose(ContextClosedEvent event) => saveAll();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onClose(ContextClosedEvent event) { saveAll(); }
/// ```
class ContextClosedEvent extends ApplicationContextEvent {
  /// Creates the event for the context [source].
  ContextClosedEvent(super.source);
}
