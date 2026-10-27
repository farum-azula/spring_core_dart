import 'package:spring_boot_dart/src/spring_application.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// An event of a `SpringApplication` run, like Spring Boot's
/// `SpringApplicationEvent`; `source` is the application.
///
/// Published in this order: [ApplicationStartingEvent],
/// [ApplicationEnvironmentPreparedEvent],
/// [ApplicationContextInitializedEvent], [ApplicationPreparedEvent],
/// (the context's `ContextRefreshedEvent`), [ApplicationStartedEvent],
/// the runners, [ApplicationReadyEvent] — or [ApplicationFailedEvent].
///
/// The first four happen before the context is refreshed: only the
/// listeners of the application (`SpringApplication.addListeners` or
/// `listeners:`) receive them. From [ApplicationPreparedEvent] on those
/// listeners are also listeners of the context; [ApplicationStartedEvent],
/// [ApplicationReadyEvent] and an [ApplicationFailedEvent] of a refreshed
/// context are published through the context, so `@EventListener` methods
/// and `ApplicationListener` beans receive them too.
///
/// ```dart
/// void main(List<String> args) => (springApplication
///       ..addListener<ApplicationEnvironmentPreparedEvent>(
///         (event) => print(event.environment.activeProfiles),
///       ))
///     .run(args);
/// ```
abstract class SpringApplicationEvent extends ApplicationEvent {
  /// An event of [application] started with [args].
  // Positional, and named after what the event carries.
  // ignore: matching_super_parameters
  SpringApplicationEvent(SpringApplication super.application, List<String> args)
    : args = List.unmodifiable(args);

  /// The application that publishes the event (same as `source`).
  SpringApplication get springApplication => source as SpringApplication;

  /// The command-line arguments of the run.
  final List<String> args;
}

/// Published first, as soon as `run` starts (nothing is prepared yet),
/// like Spring Boot's `ApplicationStartingEvent`.
class ApplicationStartingEvent extends SpringApplicationEvent {
  /// Creates the event.
  ApplicationStartingEvent(super.application, super.args);
}

/// The environment is ready (command line, environment variables, config
/// files, profiles), the context not created yet, like Spring Boot's
/// `ApplicationEnvironmentPreparedEvent`. Listeners may still change the
/// environment.
class ApplicationEnvironmentPreparedEvent extends SpringApplicationEvent {
  /// Creates the event for [environment].
  ApplicationEnvironmentPreparedEvent(
    super.application,
    super.args,
    this.environment,
  );

  /// The prepared environment.
  final ConfigurableEnvironment environment;
}

/// The context is created and the `ApplicationContextInitializer`s have
/// run, like Spring Boot's `ApplicationContextInitializedEvent`.
class ApplicationContextInitializedEvent extends SpringApplicationEvent {
  /// Creates the event for [applicationContext].
  ApplicationContextInitializedEvent(
    super.application,
    super.args,
    this.applicationContext,
  );

  /// The context, not refreshed yet.
  final ConfigurableApplicationContext applicationContext;
}

/// The context is fully prepared but not refreshed, like Spring Boot's
/// `ApplicationPreparedEvent`; from now on the application's listeners are
/// also listeners of the context.
class ApplicationPreparedEvent extends SpringApplicationEvent {
  /// Creates the event for [applicationContext].
  ApplicationPreparedEvent(
    super.application,
    super.args,
    this.applicationContext,
  );

  /// The context, not refreshed yet.
  final ConfigurableApplicationContext applicationContext;
}

/// The context is refreshed, the runners not called yet, like Spring
/// Boot's `ApplicationStartedEvent`.
class ApplicationStartedEvent extends SpringApplicationEvent {
  /// Creates the event for [applicationContext].
  ApplicationStartedEvent(
    super.application,
    super.args,
    this.applicationContext,
    this.timeTaken,
  );

  /// The started context.
  final ConfigurableApplicationContext applicationContext;

  /// How long the start took.
  final Duration timeTaken;
}

/// The runners have finished: the application is ready to serve, like
/// Spring Boot's `ApplicationReadyEvent`.
class ApplicationReadyEvent extends SpringApplicationEvent {
  /// Creates the event for [applicationContext].
  ApplicationReadyEvent(
    super.application,
    super.args,
    this.applicationContext,
    this.timeTaken,
  );

  /// The running context.
  final ConfigurableApplicationContext applicationContext;

  /// How long the start (with the runners) took.
  final Duration timeTaken;
}

/// The start (or a runner) failed, like Spring Boot's
/// `ApplicationFailedEvent`; published before the failure is reported and
/// the context closed. It reaches `@EventListener` beans only when the
/// context was refreshed already (a failing runner).
class ApplicationFailedEvent extends SpringApplicationEvent {
  /// Creates the event for [exception].
  ApplicationFailedEvent(
    super.application,
    super.args,
    this.applicationContext,
    this.exception,
  );

  /// The context, when it was created already.
  final ConfigurableApplicationContext? applicationContext;

  /// What failed.
  final Object exception;
}
