import 'package:spring_core_dart/src/context/application_context.dart';
import 'package:spring_core_dart/src/context/event/application_event.dart';

/// The base class of the events a context publishes about itself: refreshed,
/// started, stopped, paused, restarted, closed.
///
/// Applications receive these events; they never create them. Listen to
/// this base class to react to all of them, or to one subclass for one
/// moment of the context's life. Events published in a child context reach
/// the parent's listeners too; compare [applicationContext] when that
/// matters.
///
/// ```dart
/// // Logs every state change of every context.
/// @Component()
/// @Log()
/// class ContextLog {
///   @EventListener()
///   void on(ApplicationContextEvent event) =>
///       log.info('${event.runtimeType} of ${event.applicationContext.id}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void on(ApplicationContextEvent event) { ... }
/// ```
abstract class ApplicationContextEvent extends ApplicationEvent {
  /// Creates an event raised by the context [source]; contexts do this.
  ApplicationContextEvent(ApplicationContext super.source);

  /// The context that raised the event (the same object as `source`,
  /// typed).
  ApplicationContext get applicationContext => source as ApplicationContext;
}

/// Published once a context has started: every eager singleton exists and
/// the auto-startup lifecycle beans run.
///
/// It is the last step of `refresh()`. Listen to it for work that needs
/// the whole application in place, such as warming caches or printing a
/// "ready" message. In a Spring Boot application, `ApplicationReadyEvent`
/// comes later, after the runners, and is usually the better moment. If a
/// listener throws, the refresh fails (unless the multicaster has an error
/// handler).
///
/// ```dart
/// @Component()
/// @Log()
/// class Warmup {
///   @EventListener()
///   void onReady(ContextRefreshedEvent event) => log.info('ready');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onReady(ContextRefreshedEvent event) { ... }
/// ```
class ContextRefreshedEvent extends ApplicationContextEvent {
  /// Creates the event for the context [source]; contexts do this.
  ContextRefreshedEvent(super.source);
}

/// Published after `start()` was called on a context and its lifecycle
/// beans were started.
///
/// The context does not publish it during its first startup (that is
/// [ContextRefreshedEvent]), only for an explicit `start()`, typically
/// after a `stop()`.
///
/// ```dart
/// context.addListener<ContextStartedEvent>((_) => log.info('started'));
/// context.start();
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onStart(ContextStartedEvent event) { ... }
/// ```
class ContextStartedEvent extends ApplicationContextEvent {
  /// Creates the event for the context [source]; contexts do this.
  ContextStartedEvent(super.source);
}

/// Published after `stop()` was called on a context and its running
/// lifecycle beans were stopped.
///
/// The beans still exist; a later `start()` runs them again. Closing the
/// context does not publish it (that is [ContextClosedEvent]).
///
/// ```dart
/// context.addListener<ContextStoppedEvent>((_) => log.info('stopped'));
/// context.stop();
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onStop(ContextStoppedEvent event) { ... }
/// ```
class ContextStoppedEvent extends ApplicationContextEvent {
  /// Creates the event for the context [source]; contexts do this.
  ContextStoppedEvent(super.source);
}

/// Published after `restart()` was called on a context: the auto-startup
/// lifecycle beans run again, typically after a pause.
///
/// It is a [ContextStartedEvent], so start listeners see it too. New in
/// Spring 7.
///
/// ```dart
/// context.addListener<ContextRestartedEvent>((_) => log.info('resumed'));
/// context.restart();
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onRestart(ContextRestartedEvent event) { ... }
/// ```
class ContextRestartedEvent extends ContextStartedEvent {
  /// Creates the event for the context [source]; contexts do this.
  ContextRestartedEvent(super.source);
}

/// Published after `pause()` (or `pauseAsync()`) was called on a context:
/// the pauseable lifecycle beans are stopped, for example while a Flutter
/// app is in the background.
///
/// It is a [ContextStoppedEvent], so stop listeners see it too. New in
/// Spring 7.
///
/// ```dart
/// context.addListener<ContextPausedEvent>((_) => log.info('paused'));
/// context.pause();
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onPause(ContextPausedEvent event) { ... }
/// ```
class ContextPausedEvent extends ContextStoppedEvent {
  /// Creates the event for the context [source]; contexts do this.
  ContextPausedEvent(super.source);
}

/// Published when a context starts closing, while every bean is still
/// available.
///
/// It is the first step of `close()`, before the lifecycle beans are
/// stopped and the singletons destroyed. Listen to it to save state that
/// needs other beans. An error thrown by a listener is logged and the
/// shutdown goes on.
///
/// ```dart
/// // Persists the sessions while the database bean still works.
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
  /// Creates the event for the context [source]; contexts do this.
  ContextClosedEvent(super.source);
}
