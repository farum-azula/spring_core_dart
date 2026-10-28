import 'package:spring_boot_dart/src/spring_application.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// A step of the application's start, announced to listeners.
///
/// Code sometimes has to act at a precise point of the start: after the
/// config files are read but before any bean exists, or once the
/// application is ready to serve. [SpringApplication] publishes one
/// subclass of this event at each such point, in this order:
///
/// 1. [ApplicationStartingEvent]: the run has begun.
/// 2. [ApplicationEnvironmentPreparedEvent]: properties and profiles are
///    known.
/// 3. [ApplicationContextInitializedEvent] and [ApplicationPreparedEvent]:
///    the context exists, no bean is created yet.
/// 4. (the context's own `ContextRefreshedEvent`: every bean is created.)
/// 5. [ApplicationStartedEvent]: then the runners are called.
/// 6. [ApplicationReadyEvent]: the runners are done.
///
/// If the start or a runner fails, [ApplicationFailedEvent] is published
/// instead of the rest.
///
/// Which listeners see which event matters. The events up to
/// [ApplicationPreparedEvent] happen before any bean exists, so an
/// `@EventListener` method never receives them; only listeners registered
/// on the application itself do (`SpringApplication.addListener`, or
/// `listeners:`). From [ApplicationPreparedEvent] on, those listeners are
/// also listeners of the context. [ApplicationStartedEvent],
/// [ApplicationReadyEvent] and the [ApplicationFailedEvent] of a failing
/// runner go through the context, so `@EventListener` methods and
/// `ApplicationListener` beans receive them too. Most applications only
/// listen to [ApplicationReadyEvent] from a bean.
///
/// ```dart
/// // Before any bean exists: only a listener on the application sees this.
/// void main(List<String> args) => (springApplication
///       ..addListener<ApplicationEnvironmentPreparedEvent>(
///         (event) => print(event.environment.activeProfiles),
///       ))
///     .run(args);
/// ```
///
/// Spring (Java): `SpringApplicationEvent`, with the same events in the
/// same order.
abstract class SpringApplicationEvent extends ApplicationEvent {
  /// An event of [application], run with [args]. Only `SpringApplication`
  /// creates these events; create one yourself only to test a listener.
  // Positional, and named after what the event carries.
  // ignore: matching_super_parameters
  SpringApplicationEvent(SpringApplication super.application, List<String> args)
    : args = List.unmodifiable(args);

  /// The application being started; the same object as `source`, with its
  /// type.
  SpringApplication get springApplication => source as SpringApplication;

  /// The arguments of the run, as `main` received them.
  final List<String> args;
}

/// The first event of a run, published as soon as `run` begins, before
/// anything is read or created.
///
/// Neither properties nor beans exist yet; only a listener registered on
/// the [SpringApplication] receives it. It suits work that must happen
/// before everything else, such as starting a timer or installing a log
/// handler.
///
/// Spring (Java): `ApplicationStartingEvent`.
class ApplicationStartingEvent extends SpringApplicationEvent {
  /// The event for [application] run with [args]; published by
  /// `SpringApplication`.
  ApplicationStartingEvent(super.application, super.args);
}

/// Published once every property is known (command line, environment
/// variables, config files, active profiles) and before the context is
/// created.
///
/// It is the last point where a listener can change the configuration for
/// the whole run: a property source added to [environment] here is seen
/// by the log levels, the banner, `@Value` and `@ConfigurationProperties`.
/// Only a listener registered on the [SpringApplication] receives it.
///
/// ```dart
/// // Settings fetched from a configuration service, above the files.
/// springApplication.addListener<ApplicationEnvironmentPreparedEvent>(
///   (event) => event.environment.propertySources.addFirst(
///     MapPropertySource('remote', remoteSettings()),
///   ),
/// );
/// ```
///
/// Spring (Java): `ApplicationEnvironmentPreparedEvent`.
class ApplicationEnvironmentPreparedEvent extends SpringApplicationEvent {
  /// The event for [application] run with [args], carrying
  /// [environment]; published by `SpringApplication`.
  ApplicationEnvironmentPreparedEvent(
    super.application,
    super.args,
    this.environment,
  );

  /// The environment of the run; it can still be changed.
  final ConfigurableEnvironment environment;
}

/// Published once the context is created and the
/// [ApplicationContextInitializer]s have run, before any bean is created.
///
/// Only a listener registered on the [SpringApplication] receives it. Here
/// [ApplicationPreparedEvent] follows right after it, because the bean
/// definitions are known from the start; in Spring Boot the sources are
/// loaded in between.
///
/// Spring (Java): `ApplicationContextInitializedEvent`.
class ApplicationContextInitializedEvent extends SpringApplicationEvent {
  /// The event for [application] run with [args], carrying
  /// [applicationContext]; published by `SpringApplication`.
  ApplicationContextInitializedEvent(
    super.application,
    super.args,
    this.applicationContext,
  );

  /// The new context. Its bean definitions can still be changed; no bean
  /// is created yet.
  final ConfigurableApplicationContext applicationContext;
}

/// Published when the context is fully prepared, just before its beans are
/// created.
///
/// From this event on, the listeners registered on the
/// [SpringApplication] are also listeners of the context, so they receive
/// the context's own events (`ContextRefreshedEvent`,
/// `ContextClosedEvent`, ...). Only those listeners receive this event
/// itself.
///
/// Spring (Java): `ApplicationPreparedEvent`.
class ApplicationPreparedEvent extends SpringApplicationEvent {
  /// The event for [application] run with [args], carrying
  /// [applicationContext]; published by `SpringApplication`.
  ApplicationPreparedEvent(
    super.application,
    super.args,
    this.applicationContext,
  );

  /// The prepared context; no bean is created yet.
  final ConfigurableApplicationContext applicationContext;
}

/// Published once every bean is created and the `Started ...` line is
/// logged, just before the `ApplicationRunner`s are called.
///
/// It goes through the context, so `@EventListener` methods receive it.
/// Most code that waits for the start should listen to
/// [ApplicationReadyEvent] instead, which comes after the runners.
///
/// Spring (Java): `ApplicationStartedEvent`.
class ApplicationStartedEvent extends SpringApplicationEvent {
  /// The event for [application] run with [args]; published by
  /// `SpringApplication`.
  ApplicationStartedEvent(
    super.application,
    super.args,
    this.applicationContext,
    this.timeTaken,
  );

  /// The context, with every bean created.
  final ConfigurableApplicationContext applicationContext;

  /// The time from the beginning of `run` until the beans were created.
  final Duration timeTaken;
}

/// Published when the start is complete: every bean is created and every
/// runner has finished.
///
/// This is the usual event for "do this once the application is up", such
/// as filling a cache or announcing the service, without delaying the
/// start. It goes through the context, so an `@EventListener` method of a
/// bean receives it. It is not published when the context was closed by a
/// runner. A listener that throws fails the run (the error is reported and
/// the context closed) but no [ApplicationFailedEvent] is published.
///
/// ```dart
/// @Component()
/// class Warmup {
///   Warmup(this.catalog);
///   final Catalog catalog;
///
///   // After the start: requests can already be served meanwhile.
///   @EventListener()
///   void onReady(ApplicationReadyEvent event) => catalog.preload();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onReady(ApplicationReadyEvent event) { catalog.preload(); }
/// ```
class ApplicationReadyEvent extends SpringApplicationEvent {
  /// The event for [application] run with [args]; published by
  /// `SpringApplication`.
  ApplicationReadyEvent(
    super.application,
    super.args,
    this.applicationContext,
    this.timeTaken,
  );

  /// The running context.
  final ConfigurableApplicationContext applicationContext;

  /// The time from the beginning of `run` until the last runner finished.
  final Duration timeTaken;
}

/// Published when the start fails or a runner throws, before the failure
/// is reported and the context is closed.
///
/// Use it to tell someone that the application did not start, for
/// example to send an alert or to flush a log. When the failure happens
/// while the beans are created there are no beans to receive it, so only
/// listeners registered on the [SpringApplication] (and those of the
/// failed context) see it. When a runner fails, it goes through the
/// running context, and `@EventListener` methods receive it too. A
/// listener that throws is logged and does not hide the original failure.
///
/// ```dart
/// springApplication.addListener<ApplicationFailedEvent>(
///   (event) => alerts.send('checkout did not start: ${event.exception}'),
/// );
/// ```
///
/// Spring (Java): `ApplicationFailedEvent`.
class ApplicationFailedEvent extends SpringApplicationEvent {
  /// The event for [application] run with [args], carrying [exception]
  /// and, when one was created, [applicationContext]; published by
  /// `SpringApplication`.
  ApplicationFailedEvent(
    super.application,
    super.args,
    this.applicationContext,
    this.exception,
  );

  /// The context, or null when the start failed before it was created
  /// (while reading the configuration, for example).
  final ConfigurableApplicationContext? applicationContext;

  /// The error that stopped the start, as it is rethrown afterwards.
  final Object exception;
}
