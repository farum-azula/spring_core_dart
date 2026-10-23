import 'dart:async';

import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_boot_dart/src/events.dart';
import 'package:spring_boot_dart/src/failure_analyzer.dart';
import 'package:spring_boot_dart/src/runners.dart';
import 'package:spring_boot_dart/src/startup_info_stub.dart'
    if (dart.library.io) 'package:spring_boot_dart/src/startup_info_io.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _log = SpringLog('spring_boot_dart.SpringApplication');

/// Bootstraps an application, like Spring Boot's `SpringApplication`.
///
/// `run` does what an application would otherwise write by hand:
///
/// 1. [ApplicationStartingEvent]; command-line arguments and OS
///    environment variables as property sources;
/// 2. `lib/resources/application.properties` (`classpath:`) and
///    `application-{profile}` files (Spring Boot config data: profiles,
///    imports, groups, ...); [ApplicationEnvironmentPreparedEvent];
/// 3. `logging.level.root` and `logging.level.<logger>` (also
///    `logging.group.<name>=a,b` and `LOGGING_LEVEL_<LOGGER>` variables)
///    applied to [SpringLog];
/// 4. the context: the application's modules, then [autoConfigurations]
///    (so `@ConditionalOnMissingBean` sees the application's beans),
///    `@ConfigurationProperties` binding, `ApplicationArguments` as a bean;
///    the [initializers], [ApplicationContextInitializedEvent],
///    [ApplicationPreparedEvent], then the refresh;
/// 5. startup info logged through [SpringLog] at INFO like Spring Boot's
///    (`Starting app using Dart 3.9.0 with PID 42`, the active profiles,
///    `Started app in 0.042 seconds`; off with
///    `spring.main.log-startup-info=false`) and [ApplicationStartedEvent];
///    or [ApplicationFailedEvent] and a readable
///    `APPLICATION FAILED TO START` report (from [failureAnalyzers] and
///    `FailureAnalyzer` beans first, then the built-in analysis) before
///    the error is rethrown;
/// 6. `ApplicationRunner` / `CommandLineRunner` beans, one after another
///    in order: a runner's `Future` completes before the next starts, then
///    [ApplicationReadyEvent]. A failing runner publishes
///    [ApplicationFailedEvent], is reported (`Application run failed`) and
///    the context is closed. [runAsync] completes after the last runner.
///
/// The events go to [listeners] (Spring Boot's `addListeners`); see
/// [SpringApplicationEvent] for which of them `@EventListener` beans see.
///
/// `spring.main.lazy-initialization=true` makes every singleton lazy
/// (see [LazyInitializationBeanFactoryPostProcessor]);
/// `spring.main.allow-bean-definition-overriding=true` lets a definition
/// replace another of the same name (off by default, as in Spring Boot).
///
/// With `@SpringBootApplication` the generator creates `runApplication`
/// for you; written by hand:
///
/// ```dart
/// final context = SpringApplication([appBeans]).run(args);
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurableApplicationContext context = SpringApplication.run(App.class, args);
/// ```
class SpringApplication {
  /// An application made of [modules] plus library [autoConfigurations].
  SpringApplication(
    List<BeanModule> modules, {
    List<BeanModule> autoConfigurations = const [],
    List<ApplicationContextInitializer> initializers = const [],
    List<FailureAnalyzer> failureAnalyzers = const [],
    List<GenericApplicationListener> listeners = const [],
    this.resourceLoader,
    this.fingerprint,
    void Function(String line)? out,
  }) : modules = List.unmodifiable(modules),
       autoConfigurations = List.unmodifiable(autoConfigurations),
       initializers = List.unmodifiable(initializers),
       failureAnalyzers = List.unmodifiable(failureAnalyzers),
       _listeners = [...listeners],
       out = out ?? print;

  /// The application's own modules.
  final List<BeanModule> modules;

  /// Library modules registered after [modules].
  final List<BeanModule> autoConfigurations;

  /// Called with the context before it is refreshed, in order (Spring's
  /// `ApplicationContextInitializer`): add post-processors, register
  /// singletons, ...
  final List<ApplicationContextInitializer> initializers;

  /// Consulted, together with the `FailureAnalyzer` beans of the context,
  /// before the built-in analysis when the start fails (Spring Boot's
  /// `FailureAnalyzers` from `spring.factories`).
  final List<FailureAnalyzer> failureAnalyzers;

  final List<GenericApplicationListener> _listeners;

  /// The listeners of the application events ([SpringApplicationEvent]s),
  /// like Spring Boot's `getListeners`.
  List<GenericApplicationListener> get listeners =>
      List.unmodifiable(_listeners);

  /// Adds listeners of the application events, like Spring Boot's
  /// `addListeners`. They receive every [SpringApplicationEvent] — also
  /// the ones published before the context exists, which `@EventListener`
  /// beans cannot see — and, from [ApplicationPreparedEvent] on, the
  /// events of the context as its listeners.
  ///
  /// ```dart
  /// SpringApplication([appBeans])
  ///   ..addListeners([
  ///     ApplicationListenerAdapter.of<ApplicationStartingEvent>(
  ///       (event) => print('starting'),
  ///     ),
  ///   ])
  ///   ..run(args);
  /// ```
  void addListeners(Iterable<GenericApplicationListener> listeners) =>
      _listeners.addAll(listeners);

  /// Adds a listener for events of type [E] (see [addListeners]).
  void addListener<E>(
    void Function(E event) listener, {
    int order = Ordered.lowestPrecedence,
  }) =>
      _listeners.add(ApplicationListenerAdapter.of<E>(listener, order: order));

  /// Identifies the generated code the application was built from (a hash
  /// written by the generator). [reload] keeps a running context when it
  /// is unchanged.
  final String? fingerprint;

  /// Reads config files; defaults to a `DefaultResourceLoader`. Use an
  /// asset-aware loader (and [runAsync]) in Flutter.
  final ResourceLoader? resourceLoader;

  /// Where failure reports go (the startup info is logged through
  /// [SpringLog]).
  final void Function(String line) out;

  /// Starts the application synchronously (config files read with
  /// `dart:io`). [systemEnvironment] replaces the OS environment and
  /// [properties] take precedence over every other property source,
  /// command line included (both for tests, like
  /// `@SpringBootTest(properties = ...)`).
  ///
  /// Returns once the synchronous part is done: asynchronous runners keep
  /// running one after another, and if one fails the context is closed and
  /// the error is rethrown (uncaught, it ends the program). Use [runAsync]
  /// to wait for the runners, as Spring Boot's `run` does.
  ConfigurableApplicationContext run(
    List<String> args, {
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties = const {},
  }) => _run(args, systemEnvironment, properties, runners: true);

  ConfigurableApplicationContext _run(
    List<String> args,
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties, {
    required bool runners,
  }) {
    final watch = Stopwatch()..start();
    final run = _RunListeners(this, args)..starting();
    final environment = _environment(args, systemEnvironment, properties);
    final (context, arguments) = _guard(run, () {
      ConfigDataEnvironment(
        environment,
        resourceLoader: resourceLoader,
      ).processAndApplySync();
      run.environmentPrepared(environment);
      return _start(run, args, environment, watch, (
        systemEnvironment,
        properties,
      ));
    });
    final FutureOr<void> called;
    try {
      run.started(context, watch.elapsed);
      called = runners ? _callRunners(context, arguments) : null;
    } catch (error) {
      _runFailed(run, context, error);
      rethrow;
    }
    if (called is Future<void>) {
      // run() cannot wait: the remaining runners still run in order, and a
      // failure closes the context and is rethrown (uncaught, it ends the
      // program, as a failed run does in Spring Boot).
      unawaited(
        called.then(
          (_) => _ready(run, context, watch),
          onError: (Object error, StackTrace stackTrace) {
            _runFailed(run, context, error);
            Error.throwWithStackTrace(error, stackTrace);
          },
        ),
      );
    } else {
      _ready(run, context, watch);
    }
    return context;
  }

  // ApplicationReadyEvent, unless the context was closed meanwhile; a
  // failing listener fails the run (without ApplicationFailedEvent, as in
  // Spring Boot).
  void _ready(
    _RunListeners run,
    ConfigurableApplicationContext context,
    Stopwatch watch,
  ) {
    if (!context.isActive) {
      return;
    }
    try {
      run.ready(context, watch.elapsed);
    } catch (error) {
      _runFailed(run, context, error, failedEvent: false);
      rethrow;
    }
  }

  /// Like [run], reading config files asynchronously (e.g. Flutter assets),
  /// and completing once every runner has finished — like Spring Boot's
  /// `SpringApplication.run`, which returns after the runners. A failing
  /// runner fails the returned `Future` (the context is closed).
  Future<ConfigurableApplicationContext> runAsync(
    List<String> args, {
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties = const {},
  }) => _runAsync(args, systemEnvironment, properties, runners: true);

  Future<ConfigurableApplicationContext> _runAsync(
    List<String> args,
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties, {
    required bool runners,
  }) async {
    final watch = Stopwatch()..start();
    final run = _RunListeners(this, args)..starting();
    final environment = _environment(args, systemEnvironment, properties);
    try {
      await ConfigDataEnvironment(
        environment,
        resourceLoader: resourceLoader,
      ).processAndApply();
      run.environmentPrepared(environment);
    } catch (error) {
      _report(run, error);
      rethrow;
    }
    final (context, arguments) = _guard(
      run,
      () => _start(run, args, environment, watch, (
        systemEnvironment,
        properties,
      )),
    );
    try {
      run.started(context, watch.elapsed);
      if (runners) {
        await _callRunners(context, arguments);
      }
    } catch (error) {
      _runFailed(run, context, error);
      rethrow;
    }
    _ready(run, context, watch);
    return context;
  }

  /// Restarts [running] with this application if the generated code
  /// changed, for hot reload: a hot reload does not run `main` again, but
  /// the generated `springApplication` getter returns the new beans.
  ///
  /// - Same [fingerprint] (only method bodies changed): [running] is
  ///   returned as it is, beans keep their state.
  /// - Different (beans, annotations or `lib/resources/` changed):
  ///   [running] is closed and the application starts again with the same
  ///   arguments.
  ///
  /// [runners]: whether `ApplicationRunner` / `CommandLineRunner` beans run
  /// again after such a restart. They hold "on startup" work (migrations,
  /// an `app_started` analytics event, a welcome log line); the app did not
  /// really start again, so pass `false` to skip them. The default `true`
  /// matches Spring Boot DevTools, which runs them after every restart.
  ///
  /// ```dart
  /// // Flutter, in the root widget's State:
  /// @override
  /// void reassemble() {
  ///   super.reassemble();
  ///   context = reloadApplication(context); // generated
  /// }
  /// ```
  ConfigurableApplicationContext reload(
    ConfigurableApplicationContext running, {
    bool runners = true,
  }) {
    final previous = _launches[running];
    if (_isCurrent(running, previous)) {
      return running;
    }
    if (running.isActive) {
      running.close();
    }
    return _run(
      previous?.args ?? const [],
      previous?.systemEnvironment,
      previous?.properties ?? const {},
      runners: runners,
    );
  }

  /// Like [reload], reading config files asynchronously.
  Future<ConfigurableApplicationContext> reloadAsync(
    ConfigurableApplicationContext running, {
    bool runners = true,
  }) async {
    final previous = _launches[running];
    if (_isCurrent(running, previous)) {
      return running;
    }
    if (running.isActive) {
      running.close();
    }
    return _runAsync(
      previous?.args ?? const [],
      previous?.systemEnvironment,
      previous?.properties ?? const {},
      runners: runners,
    );
  }

  bool _isCurrent(ConfigurableApplicationContext running, _Launch? previous) =>
      running.isActive &&
      previous != null &&
      fingerprint != null &&
      previous.fingerprint == fingerprint;

  // How each context was started, for [reload].
  static final _launches = Expando<_Launch>('SpringApplication launches');

  StandardEnvironment _environment(
    List<String> args,
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties,
  ) {
    final environment = StandardEnvironment(
      systemEnvironment: systemEnvironment,
    )..propertySources.addFirst(SimpleCommandLinePropertySource(args));
    if (properties.isNotEmpty) {
      environment.propertySources.addFirst(
        MapPropertySource('inlinedProperties', Map.of(properties)),
      );
    }
    return environment;
  }

  T _guard<T>(_RunListeners run, T Function() body) {
    try {
      return body();
    } catch (error) {
      _report(run, error);
      rethrow;
    }
  }

  // Errors reported where the failed context was known (its analyzer
  // beans), so the outer catch does not report them again.
  final Set<Object> _reported = Set.identity();

  // ApplicationFailedEvent, then the failure report (Spring Boot's
  // handleRunFailure).
  void _report(
    _RunListeners run,
    Object error, [
    ConfigurableApplicationContext? context,
  ]) {
    if (_reported.remove(error)) {
      return;
    }
    run.failed(context, error);
    final analysis = analyzeFailure(error, analyzers: _analyzers(context));
    if (analysis != null) {
      out(analysis.report);
    }
    if (context != null) {
      _reported.add(error);
    }
  }

  // [failureAnalyzers], then the `FailureAnalyzer` beans of [context] (if
  // they can still be created), sorted by order.
  List<FailureAnalyzer> _analyzers(ConfigurableApplicationContext? context) {
    final beans = <FailureAnalyzer>[];
    if (context != null) {
      final factory = context.beanFactory;
      try {
        for (final name in factory.getBeanNamesForType(FailureAnalyzer)) {
          beans.add(factory.getBeanByName(name) as FailureAnalyzer);
        }
      } catch (_) {
        // A context that failed early cannot provide them.
      }
      if (!context.isActive) {
        factory.destroySingletons();
      }
    }
    return [...failureAnalyzers, ...OrderComparator.sort(beans, (_) => null)];
  }

  // Creates and refreshes the context and prints the startup line; the
  // runners are called by the caller afterwards (Spring Boot: logStarted,
  // then callRunners).
  (ConfigurableApplicationContext, ApplicationArguments) _start(
    _RunListeners run,
    List<String> args,
    StandardEnvironment environment,
    Stopwatch watch,
    (Map<String, String>?, Map<String, Object?>) launch,
  ) {
    applyLoggingLevels(environment);
    // Spring Boot's ContextIdApplicationContextInitializer.
    final applicationName = environment
        .getProperty('spring.application.name')
        ?.trim();
    final context = AnnotationConfigApplicationContext(
      [...modules, ...autoConfigurations],
      environment: environment,
      resourceLoader: resourceLoader,
      id: applicationName == null || applicationName.isEmpty
          ? 'application'
          : applicationName,
    );
    _launches[context] = _Launch(
      fingerprint,
      List.unmodifiable(args),
      launch.$1,
      launch.$2,
    );
    final arguments = ApplicationArguments(args);
    final logStartupInfo =
        environment.getPropertyAs<bool>('spring.main.log-startup-info') ?? true;
    final name =
        environment.getProperty('spring.application.name') ?? 'application';
    (context.beanFactory as DefaultListableBeanFactory)
            .allowBeanDefinitionOverriding =
        environment.getPropertyAs<bool>(
          'spring.main.allow-bean-definition-overriding',
        ) ??
        false;
    context.beanFactory
      ..registerSingleton(
        'springApplicationArguments',
        arguments,
        types: const [ApplicationArguments],
      )
      ..addBeanPostProcessor(
        ConfigurationPropertiesBinder(environment, context.introspector),
      );
    if (environment.getPropertyAs<bool>('spring.main.lazy-initialization') ??
        false) {
      context.addBeanFactoryPostProcessor(
        LazyInitializationBeanFactoryPostProcessor(),
      );
    }
    if (logStartupInfo) {
      // Spring Boot logs this before the refresh; here the logging system
      // is set up by a post-processor during the refresh, so this one runs
      // after the other post-processors, before any bean is created.
      context.beanFactory.registerSingleton(
        'springApplicationStartupInfoLogger',
        _StartupInfoLogger(name, environment),
        types: const [BeanFactoryPostProcessor, Ordered],
      );
    }
    for (final initializer in initializers) {
      initializer(context);
    }
    run
      ..contextPrepared(context)
      ..contextLoaded(context);
    try {
      context.refresh();
    } catch (error) {
      _report(run, error, context);
      if (context.isActive) {
        context.close();
      }
      rethrow;
    }
    if (logStartupInfo) {
      // Spring Boot's StartupInfoLogger.logStarted (without the process
      // uptime, which Dart does not know).
      _log.info('Started $name in ${watch.elapsedMilliseconds / 1000} seconds');
    }
    return (context, arguments);
  }

  // A runner failed: ApplicationFailedEvent, reported like Spring Boot's
  // "Application run failed", and the context is closed.
  void _runFailed(
    _RunListeners run,
    ConfigurableApplicationContext context,
    Object error, {
    bool failedEvent = true,
  }) {
    if (failedEvent) {
      run.failed(context, error);
    }
    out(
      analyzeFailure(error, analyzers: _analyzers(context))?.report ??
          'Application run failed: $error',
    );
    if (context.isActive) {
      context.close();
    }
  }

  // Both kinds sorted together by order, as in Spring Boot's callRunners;
  // each runner finishes (its Future completes) before the next starts.
  // Synchronous while every runner is.
  static FutureOr<void> _callRunners(
    ConfigurableApplicationContext context,
    ApplicationArguments arguments,
  ) {
    // Bean -> its @Order value; Ordered / PriorityOrdered beans win.
    final orders = <Object, int?>{
      for (final type in const [ApplicationRunner, CommandLineRunner])
        for (final name in context.getBeanNamesForType(type))
          context.getBeanByName(name): context.beanFactory
              .getBeanDefinition(name)
              .order,
    };
    final beans = OrderComparator.sort(orders.keys, (bean) => orders[bean]);
    final calls = <FutureOr<void> Function()>[
      for (final runner in beans) ...[
        // A bean implementing both is called as both, like in Spring Boot.
        if (runner is ApplicationRunner) () => runner.run(arguments),
        if (runner is CommandLineRunner) () => runner.run(arguments.sourceArgs),
      ],
    ];
    return _inOrder(context, calls.iterator);
  }

  static FutureOr<void> _inOrder(
    ConfigurableApplicationContext context,
    Iterator<FutureOr<void> Function()> calls,
  ) {
    // Stops when the context was closed meanwhile.
    while (context.isActive && calls.moveNext()) {
      final result = calls.current();
      if (result is Future<Object?>) {
        return result.then<void>((_) => _inOrder(context, calls));
      }
    }
  }

  /// Applies `logging.level.*` from [environment] to [SpringLog], like
  /// Spring Boot's `LoggingApplicationListener`:
  ///
  /// ```properties
  /// logging.level.root=info
  /// logging.level.neon.checkout=debug
  /// logging.group.payments=neon.payments,neon.checkout
  /// logging.level.payments=trace
  /// ```
  ///
  /// `LOGGING_LEVEL_NEON_CHECKOUT=debug` (environment variable) is the
  /// same as `logging.level.neon.checkout`. Levels of an earlier run are
  /// replaced.
  static void applyLoggingLevels(ConfigurableEnvironment environment) {
    String? rootValue; // `root` in any case, like Spring Boot
    final groups = <String, List<String>>{};
    final levels = <String, String>{};
    for (final source in environment.propertySources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      for (final key in source.propertyNames) {
        final name = _loggingKey(key, 'logging.group.', 'LOGGING_GROUP_');
        if (name != null && !groups.containsKey(name)) {
          groups[name] = [
            for (final logger in '${source.getProperty(key)}'.split(','))
              if (logger.trim().isNotEmpty) logger.trim(),
          ];
          continue;
        }
        final logger = _loggingKey(key, 'logging.level.', 'LOGGING_LEVEL_');
        if (logger != null && logger.toLowerCase() == 'root') {
          rootValue ??= environment.getProperty(key);
        } else if (logger != null && !levels.containsKey(logger)) {
          // Earlier sources win, as in the environment itself.
          levels[logger] = '${source.getProperty(key)}';
        }
      }
    }
    final root = parseSpringLogLevel(
      rootValue ??
          environment.getProperty('logging.level.root') ??
          environment.getProperty('logging.level'),
    );
    if (root != null) {
      SpringLog.level = root;
    }
    SpringLog.resetLevels();
    for (final MapEntry(key: logger, value: value) in levels.entries) {
      final level = parseSpringLogLevel(value);
      if (level != null) {
        for (final name in groups[logger] ?? [logger]) {
          SpringLog.setLevel(name, level);
        }
      }
    }
  }

  static String? _loggingKey(String key, String prefix, String envPrefix) {
    if (key.startsWith(prefix) && key.length > prefix.length) {
      return key.substring(prefix.length);
    }
    if (key.startsWith(envPrefix) && key.length > envPrefix.length) {
      return key.substring(envPrefix.length).toLowerCase().replaceAll('_', '.');
    }
    return null;
  }
}

/// Makes every singleton lazy (created on first use), like Spring Boot's
/// `LazyInitializationBeanFactoryPostProcessor`; [SpringApplication] adds
/// it for `spring.main.lazy-initialization=true`.
///
/// Beans with their own `@Lazy(...)` and `SmartInitializingSingleton`
/// beans are left alone.
///
/// Spring (Java):
/// ```java
/// context.addBeanFactoryPostProcessor(
///     new LazyInitializationBeanFactoryPostProcessor());
/// ```
class LazyInitializationBeanFactoryPostProcessor
    implements BeanFactoryPostProcessor, Ordered {
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    for (final name in beanFactory.beanDefinitionNames) {
      final definition = beanFactory.getBeanDefinition(name);
      if (definition.annotations.any((a) => a is Lazy) ||
          definition.types.contains(SmartInitializingSingleton)) {
        continue;
      }
      definition.lazy = true;
    }
  }

  @override
  int get order => Ordered.highestPrecedence;
}

// Logs "Starting ..." and the profiles like Spring Boot's
// StartupInfoLogger.logStarting and SpringApplication.logStartupProfileInfo.
final class _StartupInfoLogger implements BeanFactoryPostProcessor, Ordered {
  _StartupInfoLogger(this.name, this.environment);

  final String name;
  final Environment environment;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    final version = dartVersion();
    final pid = processId();
    _log.info(
      'Starting $name'
      '${version == null ? '' : ' using Dart $version'}'
      '${pid == null ? '' : ' with PID $pid'}',
    );
    String quoted(List<String> profiles) =>
        profiles.map((p) => '"$p"').join(', ');
    final active = environment.activeProfiles;
    if (active.isEmpty) {
      final defaults = environment.defaultProfiles;
      _log.info(
        'No active profile set, falling back to ${defaults.length} default '
        '${defaults.length <= 1 ? 'profile' : 'profiles'}: ${quoted(defaults)}',
      );
    } else {
      _log.info(
        'The following '
        '${active.length == 1 ? '1 profile is' : '${active.length} profiles are'}'
        ' active: ${quoted(active)}',
      );
    }
  }

  @override
  int get order => Ordered.lowestPrecedence;
}

/// Prepares a context before it is refreshed, like Spring's
/// `ApplicationContextInitializer`; see [SpringApplication.initializers].
typedef ApplicationContextInitializer = void Function(
  ConfigurableApplicationContext context,
);

// Spring Boot's EventPublishingRunListener: the application's listeners
// get the early events through their own multicaster, the later ones
// through the context.
final class _RunListeners {
  _RunListeners(this.application, this.args) {
    for (final listener in application._listeners) {
      _multicaster.addApplicationListener(listener);
    }
  }

  final SpringApplication application;
  final List<String> args;
  final _multicaster = SimpleApplicationEventMulticaster();

  void starting() =>
      _multicaster.multicastEvent(ApplicationStartingEvent(application, args));

  void environmentPrepared(ConfigurableEnvironment environment) =>
      _multicaster.multicastEvent(
        ApplicationEnvironmentPreparedEvent(application, args, environment),
      );

  void contextPrepared(ConfigurableApplicationContext context) =>
      _multicaster.multicastEvent(
        ApplicationContextInitializedEvent(application, args, context),
      );

  void contextLoaded(ConfigurableApplicationContext context) {
    for (final listener in application._listeners) {
      context.addApplicationListener(listener);
    }
    _multicaster.multicastEvent(
      ApplicationPreparedEvent(application, args, context),
    );
  }

  void started(ConfigurableApplicationContext context, Duration timeTaken) =>
      context.publishEvent(
        ApplicationStartedEvent(application, args, context, timeTaken),
      );

  void ready(ConfigurableApplicationContext context, Duration timeTaken) =>
      context.publishEvent(
        ApplicationReadyEvent(application, args, context, timeTaken),
      );

  // Through the context when it runs (the application's listeners are
  // among its listeners by then), else to the application's listeners; a
  // failing listener is logged, the original failure goes on.
  void failed(ConfigurableApplicationContext? context, Object error) {
    final event = ApplicationFailedEvent(application, args, context, error);
    try {
      if (context != null && context.isActive) {
        context.publishEvent(event);
      } else {
        _multicaster.multicastEvent(event);
      }
    } catch (listenerError, stackTrace) {
      _log.warning(
        'Error handling failed',
        error: listenerError,
        stackTrace: stackTrace,
      );
    }
  }
}

final class _Launch {
  _Launch(this.fingerprint, this.args, this.systemEnvironment, this.properties);

  final String? fingerprint;
  final List<String> args;
  final Map<String, String>? systemEnvironment;
  final Map<String, Object?> properties;
}
