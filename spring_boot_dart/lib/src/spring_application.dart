import 'dart:async';

import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/async_startup.dart';
import 'package:spring_boot_dart/src/auto_configuration_sorter.dart';
import 'package:spring_boot_dart/src/banner.dart';
import 'package:spring_boot_dart/src/binder.dart';
import 'package:spring_boot_dart/src/condition_evaluation_report.dart';
import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_boot_dart/src/deferred_logs.dart';
import 'package:spring_boot_dart/src/environment_post_processor.dart';
import 'package:spring_boot_dart/src/events.dart';
import 'package:spring_boot_dart/src/exit_code.dart';
import 'package:spring_boot_dart/src/failure_analyzer.dart';
import 'package:spring_boot_dart/src/hot_reload.dart';
import 'package:spring_boot_dart/src/runners.dart';
import 'package:spring_boot_dart/src/startup_info_stub.dart'
    if (dart.library.io) 'package:spring_boot_dart/src/startup_info_io.dart';
import 'package:spring_boot_dart/src/startup_runtime.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _log = SpringLog('spring_boot_dart.SpringApplication');

/// Starts an application: reads its configuration, creates its beans and
/// runs its startup tasks, in a fixed and documented order.
///
/// A program built from beans needs the same steps every time: collect
/// properties from the command line, the environment and the config
/// files, set the log levels, create the context with the application's
/// beans and the beans its libraries add, report a failed start in a
/// readable way, and run the startup tasks. This class does all of that.
///
/// Most applications never create one. With `@SpringBootApplication()`
/// on `main`, the generator writes a `springApplication` getter (a new
/// instance with the application's modules and the auto-configuration of
/// its dependencies) and `runApplication(args)`, which calls [run]. Reach
/// for this class directly to register listeners for the early events,
/// to set default properties, or to end the process with an exit code
/// ([exit]); tests usually go through `spring_boot_starter_test`.
///
/// What [run] does, in order:
///
/// 1. Publishes [ApplicationStartingEvent]. Adds the command-line
///    arguments, the `--dart-define` values and the OS environment
///    variables as property sources.
/// 2. Reads `lib/resources/application.properties` (or `.yml`), the
///    `application-{profile}` files, imports and profile groups, then
///    publishes [ApplicationEnvironmentPreparedEvent].
/// 3. Applies `logging.level.*` to [SpringLog] (see [applyLoggingLevels])
///    and prints the [banner].
/// 4. Creates the context from [modules], then [autoConfigurations], so
///    a `@ConditionalOnMissingBean()` of a library sees the application's
///    beans. Registers [ApplicationArguments] as a bean and the binding of
///    `@ConfigurationProperties`, runs the [initializers], publishes
///    [ApplicationContextInitializedEvent] and [ApplicationPreparedEvent],
///    then creates the beans.
/// 5. Logs `Starting app using Dart 3.9.0 with PID 42` (in Flutter,
///    `using Flutter 3.47.7 (Dart 3.13.5)`), the active profiles and
///    `Started app in 0.042 seconds` at INFO (off with
///    `spring.main.log-startup-info=false`), then publishes
///    [ApplicationStartedEvent].
/// 6. Calls the `ApplicationRunner` and `CommandLineRunner` beans one
///    after another, sorted by `@Order`, each finishing (its `Future`
///    included) before the next starts. Then publishes
///    [ApplicationReadyEvent].
///
/// When a step fails, [ApplicationFailedEvent] is published and an
/// `APPLICATION FAILED TO START` report explains the error (from the
/// [failureAnalyzers] and the `FailureAnalyzer` beans first, then the
/// built-in analysis); then the error is rethrown. A failing runner is
/// reported as `Application run failed` and the context is closed.
///
/// [SpringApplicationEvent] explains which listeners receive which event.
/// Two more properties change the context:
/// `spring.main.lazy-initialization=true` creates every singleton on
/// first use ([LazyInitializationBeanFactoryPostProcessor]), and
/// `spring.main.allow-bean-definition-overriding=true` lets a bean
/// definition replace another of the same name (off by default).
///
/// ```dart
/// // bin/main.dart: the generated getter, with a listener for an event
/// // that happens before any bean exists.
/// @SpringBootApplication()
/// void main(List<String> args) => (springApplication
///       ..addListener<ApplicationEnvironmentPreparedEvent>(
///         (event) => log.info(event.environment.activeProfiles),
///       ))
///     .run(args);
///
/// // Without the generator, from a module written by hand:
/// final context = SpringApplication([appBeans]).run(args);
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurableApplicationContext context =
///     SpringApplication.run(App.class, args);
/// ```
class SpringApplication {
  /// An application made of its own [modules] and the [autoConfigurations]
  /// of its libraries.
  ///
  /// The generated `springApplication` fills [modules],
  /// [autoConfigurations], [autoConfigurationMetadata], [exclude],
  /// [excludeName], [dartDefines] and [fingerprint]; the other parameters
  /// are for code that creates the application itself. Each is described
  /// at the field of the same name. [listeners] and [defaultProperties]
  /// can also be changed after construction with [addListeners] and
  /// [setDefaultProperties].
  SpringApplication(
    List<BeanModule> modules, {
    List<BeanModule> autoConfigurations = const [],
    Map<BeanModule, AutoConfigurationModule> autoConfigurationMetadata =
        const {},
    List<Type> exclude = const [],
    List<String> excludeName = const [],
    this.registerShutdownHook = false,
    List<ApplicationContextInitializer> initializers = const [],
    List<FailureAnalyzer> failureAnalyzers = const [],
    List<GenericApplicationListener> listeners = const [],
    Map<String, Object?> defaultProperties = const {},
    List<String> additionalProfiles = const [],
    List<EnvironmentPostProcessor> environmentPostProcessors = const [],
    Map<String, String> dartDefines = const {},
    this.banner,
    this.bannerMode = BannerMode.console,
    this.resourceLoader,
    this.fingerprint,
    this.out,
  }) : modules = List.unmodifiable(modules),
       autoConfigurations = List.unmodifiable(autoConfigurations),
       autoConfigurationMetadata = Map.unmodifiable(autoConfigurationMetadata),
       exclude = List.unmodifiable(exclude),
       excludeName = List.unmodifiable(excludeName),
       initializers = List.unmodifiable(initializers),
       failureAnalyzers = List.unmodifiable(failureAnalyzers),
       _listeners = [...listeners],
       _defaultProperties = {...defaultProperties},
       additionalProfiles = List.unmodifiable(additionalProfiles),
       dartDefines = Map.unmodifiable(dartDefines),
       environmentPostProcessors = List.unmodifiable(environmentPostProcessors);

  /// The application's own bean modules, registered first and in this
  /// order. The generator passes one module with every bean of the
  /// package.
  final List<BeanModule> modules;

  /// The auto-configuration modules of the libraries, registered after
  /// [modules] so their conditions see the application's beans.
  ///
  /// They are registered in Spring Boot's auto-configuration order, not
  /// in the order listed: by `order`, then name, then the `before` /
  /// `after` constraints of [autoConfigurationMetadata]. The generator
  /// passes the modules it finds in the dependencies.
  final List<BeanModule> autoConfigurations;

  /// The `@AutoConfigurationModule` annotation of each of
  /// [autoConfigurations], whose `order`, `before` and `after` decide the
  /// order of registration. A module without an entry has order `0` and
  /// no constraints.
  final Map<BeanModule, AutoConfigurationModule> autoConfigurationMetadata;

  /// `@AutoConfiguration` classes whose beans are not registered, from
  /// `@SpringBootApplication(exclude:)`. A type that is not an
  /// auto-configuration class fails the start.
  final List<Type> exclude;

  /// Names of auto-configuration classes or modules that are not
  /// registered, from `@SpringBootApplication(excludeName:)`. The property
  /// `spring.autoconfigure.exclude` adds more at run time. Unknown names
  /// are ignored.
  final List<String> excludeName;

  /// Whether the context is closed cleanly when the process gets SIGINT
  /// (Ctrl+C) or SIGTERM, so `@PreDestroy` methods and
  /// `ContextClosedEvent` listeners run before the process ends.
  ///
  /// Turn it on in programs that run until they are stopped, such as
  /// servers. It is off by default, unlike in Spring Boot: listening for
  /// signals keeps a Dart program alive, so a program that has finished its
  /// work would never end. The property `spring.main.register-shutdown-hook`
  /// wins when set. It uses the context's `registerShutdownHook()` and
  /// does nothing without `dart:io` (on the web).
  final bool registerShutdownHook;

  /// Code that prepares the context before its beans are created: add
  /// post-processors or property sources, register ready-made objects as
  /// beans. Run in `Ordered` order (unordered ones last). Test tools use
  /// them; see [ApplicationContextInitializer].
  final List<ApplicationContextInitializer> initializers;

  /// Analyzers asked first when the start fails, before the
  /// `FailureAnalyzer` beans of the context and the built-in analysis.
  ///
  /// Unlike beans, they also work for failures that happen before the
  /// beans are created. Spring Boot finds them in `spring.factories`.
  final List<FailureAnalyzer> failureAnalyzers;

  final List<GenericApplicationListener> _listeners;

  /// The listeners registered on the application, from the constructor and
  /// [addListeners]; an unmodifiable copy.
  List<GenericApplicationListener> get listeners =>
      List.unmodifiable(_listeners);

  /// Registers listeners on the application itself, for the next runs.
  ///
  /// Unlike `@EventListener` beans, they receive every
  /// [SpringApplicationEvent], also those published before any bean
  /// exists. From [ApplicationPreparedEvent] on they are also listeners of
  /// the context, so they receive its events too (`ContextClosedEvent`,
  /// for example). Call it before [run]. [addListener] is shorter for a
  /// single function.
  ///
  /// ```dart
  /// SpringApplication([appBeans])
  ///   ..addListeners([
  ///     ApplicationListenerAdapter.of<ApplicationStartingEvent>(
  ///       (event) => log.info('starting'),
  ///     ),
  ///   ])
  ///   ..run(args);
  /// ```
  void addListeners(Iterable<GenericApplicationListener> listeners) =>
      _listeners.addAll(listeners);

  /// Registers [listener] on the application for the events of type [E],
  /// such as [ApplicationStartingEvent], which no bean can receive.
  ///
  /// [order] places it among the other listeners of the same event (lower
  /// first); by default it comes last. See [addListeners].
  void addListener<E>(
    void Function(E event) listener, {
    int order = Ordered.lowestPrecedence,
  }) =>
      _listeners.add(ApplicationListenerAdapter.of<E>(listener, order: order));

  final Map<String, Object?> _defaultProperties;

  /// Properties with the lowest precedence: every other source, config
  /// files included, overrides them.
  ///
  /// Use them for defaults that belong to the program rather than to a
  /// config file, such as the defaults of a tool that may run without
  /// `application.properties`. They form the property source named
  /// `defaultProperties`.
  ///
  /// ```dart
  /// SpringApplication(
  ///   [appBeans],
  ///   defaultProperties: {'server.port': 8080},
  /// ).run(args);
  /// ```
  Map<String, Object?> get defaultProperties =>
      Map.unmodifiable(_defaultProperties);

  /// Replaces all of [defaultProperties] with [properties], for the next
  /// runs.
  void setDefaultProperties(Map<String, Object?> properties) =>
      _defaultProperties
        ..clear()
        ..addAll(properties);

  /// Profiles that are always active, on top of those configured with
  /// `spring.profiles.active`.
  ///
  /// For a profile that belongs to the build rather than to the
  /// configuration, such as `mobile` in a Flutter app. They come first, so
  /// their `application-{profile}` files have the lowest precedence of
  /// the profile-specific ones. [run] and [runAsync] can add more for one
  /// launch.
  final List<String> additionalProfiles;

  /// Values given at build time with `--dart-define=KEY=value` (or
  /// `-DKEY=value` for `dart compile` / `dart run`), as properties.
  ///
  /// A Flutter or web app has no command line and often no environment
  /// variables, so build-time defines are how its configuration is
  /// chosen. They rank right below the command-line arguments, above the
  /// OS environment and the config files. Names are relaxed like
  /// environment variables: a define `API_URL` answers `${API_URL}` and
  /// `api.url`, and `SPRING_PROFILES_ACTIVE` activates profiles.
  ///
  /// The generator fills this map with the keys the application can read
  /// (placeholders, `@ConfigurationProperties`, config files), because on
  /// the web and in AOT builds `String.fromEnvironment` only works as a
  /// `const` with a literal key. Only the defines that were given end up
  /// here.
  ///
  /// ```sh
  /// flutter build apk --dart-define=SPRING_PROFILES_ACTIVE=prod \
  ///   --dart-define=API_URL=https://api.neon.books
  /// ```
  ///
  /// The values are compiled into the program and can be read from it:
  /// never pass secrets this way.
  final Map<String, String> dartDefines;

  /// The name of the property source that holds [dartDefines],
  /// `dartDefines`.
  static const dartDefinesPropertySourceName = 'dartDefines';

  /// The banner printed at startup when there is no banner file.
  ///
  /// A `lib/resources/banner.txt` (or the file named by
  /// `spring.banner.location`) wins over it; when both are missing, the
  /// [SpringBootBanner] is printed.
  final Banner? banner;

  /// Where the banner goes; [BannerMode.console] by default. The property
  /// `spring.main.banner-mode` (`off`, `console` or `log`) wins when set.
  final BannerMode bannerMode;

  // Boot's printBanner: after the environment is prepared, before the
  // context is created. [preloaded] is the banner file read
  // asynchronously (runAsync: Flutter assets).
  void _printBanner(StandardEnvironment environment, [Resource? preloaded]) {
    final property = environment
        .getProperty('spring.main.banner-mode')
        ?.trim()
        .toLowerCase();
    final mode = switch (property) {
      null || '' => bannerMode,
      'off' || 'false' => BannerMode.off,
      'console' => BannerMode.console,
      'log' => BannerMode.log,
      _ => throw ConfigurationPropertiesBindException('spring.main', null, [
        // One element, split for the line width.
        // ignore: no_adjacent_strings_in_list
        'spring.main.banner-mode: failed to convert to BannerMode (one of '
            'off, console, log) (was "$property")',
      ]),
    };
    if (mode == BannerMode.off) {
      return;
    }
    final resource = preloaded ?? _bannerResource(environment);
    (resource.supportsSyncRead && resource.exists()
            ? ResourceBanner(resource)
            : banner ?? const SpringBootBanner())
        .printBanner(
          environment,
          mode == BannerMode.log ? (text) => _log.info(text) : print,
        );
  }

  Resource _bannerResource(Environment environment) =>
      (resourceLoader ?? DefaultResourceLoader()).getResource(
        environment.getProperty('spring.banner.location') ??
            'classpath:banner.txt',
      );

  // The banner file when it can only be read asynchronously (a Flutter
  // asset), read into memory; `null` otherwise or when it cannot be read.
  Future<Resource?> _readBannerAsync(Environment environment) async {
    final resource = _bannerResource(environment);
    if (resource.supportsSyncRead || !resource.exists()) {
      return null;
    }
    try {
      return ByteArrayResource(
        await resource.readAsBytes(),
        description: resource.description,
      );
    } on Object {
      return null;
    }
  }

  /// Code that changes the properties or profiles before the context is
  /// created, some before the config files are read and some after,
  /// depending on their order. See [EnvironmentPostProcessor].
  final List<EnvironmentPostProcessor> environmentPostProcessors;

  // The post-processors before (`true`) or after config data, in order;
  // Boot's built-in SpringApplicationJsonEnvironmentPostProcessor among
  // them.
  Iterable<EnvironmentPostProcessor> _postProcessors({required bool before}) =>
      OrderComparator.sort([
        const SpringApplicationJsonEnvironmentPostProcessor(),
        ...environmentPostProcessors,
      ]).where(
        (processor) =>
            (OrderComparator.orderOf(processor) <
                EnvironmentPostProcessor.configDataOrder) ==
            before,
      );

  void _postProcessEnvironment(
    StandardEnvironment environment, {
    required bool before,
  }) {
    for (final processor in _postProcessors(before: before)) {
      processor.postProcessEnvironment(environment, this);
    }
  }

  /// A hash of the generated code the application was built from, written
  /// by the generator.
  ///
  /// After a hot reload, [reload] compares it with the running context's:
  /// when it is unchanged (only method bodies changed), the context keeps
  /// running. Null when the application was not generated; [reload] then
  /// always restarts.
  final String? fingerprint;

  /// Reads the config files, the banner file and `classpath:` resources;
  /// a `DefaultResourceLoader` by default. In Flutter, pass a loader that
  /// reads assets and start with [runAsync], since assets can only be
  /// read asynchronously.
  final ResourceLoader? resourceLoader;

  /// Where the failure report of a failed start goes instead of the log;
  /// for a tool that shows it somewhere else, or a test that checks it.
  ///
  /// With `null` (the default) failures are logged as in Spring Boot: an
  /// analyzed failure at error level under
  /// `spring_boot_dart.diagnostics.LoggingFailureAnalysisReporter`, any
  /// other failure as `Application run failed` with the error and stack
  /// trace under `spring_boot_dart.SpringApplication`. A logging system
  /// (`spring_boot_starter_logging`) stays installed until the failure is
  /// logged, so the report reaches the log file too. Given a function, it
  /// receives the report text, or `Application run failed: <error>`.
  final void Function(String line)? out;

  /// Starts the application with the program arguments [args] and returns
  /// the running context.
  ///
  /// Config files are read synchronously, which needs files on disk or
  /// embedded resources; in Flutter use [runAsync]. When the start fails,
  /// [ApplicationFailedEvent] is published, the failure report is logged
  /// and the error is rethrown.
  ///
  /// It returns as soon as the synchronous part is done: runners that
  /// return a `Future` keep running one after another afterwards. If one
  /// of them fails, the context is closed and the error is rethrown
  /// outside any `try` (uncaught, it ends the program). Use [runAsync] to
  /// wait for the runners, as Spring Boot's `run` does.
  ///
  /// The named parameters are for tests and tools:
  ///
  /// - [systemEnvironment] replaces the OS environment variables.
  /// - [properties] take precedence over every other property source,
  ///   command line included (what `@SpringBootTest(properties: ...)`
  ///   does).
  /// - [additionalProfiles] are activated for this launch, after the
  ///   application's own [SpringApplication.additionalProfiles] (the more
  ///   specific last) and before the config files are read, so their
  ///   `application-{profile}` files load. A [reload] keeps them.
  /// - [hotReload] returns the application as the code is now (the
  ///   generated `runApplication` passes `() => springApplication`). With
  ///   it, a hot reload on the Dart VM restarts the context when the
  ///   generated code changed; see [SpringHotReload].
  ConfigurableApplicationContext run(
    List<String> args, {
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties = const {},
    List<String> additionalProfiles = const [],
    SpringApplication Function()? hotReload,
  }) {
    final context = _run(
      args,
      systemEnvironment,
      properties,
      List.unmodifiable(additionalProfiles),
      runners: true,
    );
    if (hotReload != null) {
      SpringHotReload.track(context, hotReload);
    }
    return context;
  }

  ConfigurableApplicationContext _run(
    List<String> args,
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties,
    List<String> launchProfiles, {
    required bool runners,
  }) {
    final watch = Stopwatch()..start();
    final run = _RunListeners(this, args)..starting();
    final environment = run.releasingLogsOnError(
      () => _environment(args, systemEnvironment, properties),
    );
    final (context, arguments, startup) = _guard(run, () {
      _postProcessEnvironment(environment, before: true);
      ConfigDataEnvironment(
        environment,
        resourceLoader: resourceLoader,
        additionalProfiles: [...additionalProfiles, ...launchProfiles],
      ).processAndApplySync();
      _postProcessEnvironment(environment, before: false);
      run.environmentPrepared(environment);
      _applyLoggingLevels(run, environment);
      _printBanner(environment);
      return _start(run, args, environment, watch, (
        systemEnvironment,
        properties,
        launchProfiles,
      ));
    });
    if (startup != null) {
      // A bean still starting (the web server binding its port): run()
      // cannot wait, so the rest follows once it has started. A failure
      // is a failed start, rethrown uncaught (it ends the program with a
      // non-zero exit code, as a failed refresh does in Spring Boot).
      unawaited(
        startup.then(
          (_) => _started(run, context, arguments, watch, runners: runners),
          onError: (Object error, StackTrace stackTrace) {
            _startupFailed(run, context, error, stackTrace);
            Error.throwWithStackTrace(error, stackTrace);
          },
        ),
      );
      return context;
    }
    _started(run, context, arguments, watch, runners: runners);
    return context;
  }

  // ApplicationStartedEvent, the runners, ApplicationReadyEvent.
  void _started(
    _RunListeners run,
    ConfigurableApplicationContext context,
    ApplicationArguments arguments,
    Stopwatch watch, {
    required bool runners,
  }) {
    final FutureOr<void> called;
    try {
      run.started(context, watch.elapsed);
      called = runners ? _callRunners(context, arguments) : null;
    } catch (error, stackTrace) {
      _runFailed(run, context, error, stackTrace: stackTrace);
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
            _runFailed(run, context, error, stackTrace: stackTrace);
            Error.throwWithStackTrace(error, stackTrace);
          },
        ),
      );
    } else {
      _ready(run, context, watch);
    }
  }

  // A bean of [AsyncStartup] failed to start after the refresh: reported
  // like a failed refresh, and the context is closed.
  void _startupFailed(
    _RunListeners run,
    ConfigurableApplicationContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    _logConditionReport(context, crash: true);
    _report(run, error, context: context, stackTrace: stackTrace);
    // No outer catch reports it again.
    _reported.remove(error);
    if (context.isActive) {
      context.close();
    }
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
    } catch (error, stackTrace) {
      _runFailed(
        run,
        context,
        error,
        failedEvent: false,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Starts the application like [run], and completes once every runner
  /// has finished, as Spring Boot's `run` does.
  ///
  /// Use it in Flutter, where config files and the banner are assets that
  /// can only be read asynchronously, and wherever `main` should wait for
  /// the startup work. The beans are created with `refreshAsync()`, so
  /// asynchronous `@PostConstruct` and init methods are awaited before the
  /// runners start. A failing start or runner fails the returned `Future`;
  /// after a runner failure the context is closed with `closeAsync()`.
  /// The parameters are those of [run].
  Future<ConfigurableApplicationContext> runAsync(
    List<String> args, {
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties = const {},
    List<String> additionalProfiles = const [],
    SpringApplication Function()? hotReload,
  }) async {
    final context = await _runAsync(
      args,
      systemEnvironment,
      properties,
      List.unmodifiable(additionalProfiles),
      runners: true,
    );
    if (hotReload != null) {
      SpringHotReload.track(context, hotReload);
    }
    return context;
  }

  Future<ConfigurableApplicationContext> _runAsync(
    List<String> args,
    Map<String, String>? systemEnvironment,
    Map<String, Object?> properties,
    List<String> launchProfiles, {
    required bool runners,
  }) async {
    final watch = Stopwatch()..start();
    final run = _RunListeners(this, args)..starting();
    final environment = run.releasingLogsOnError(
      () => _environment(args, systemEnvironment, properties),
    );
    try {
      _postProcessEnvironment(environment, before: true);
      await ConfigDataEnvironment(
        environment,
        resourceLoader: resourceLoader,
        additionalProfiles: [...additionalProfiles, ...launchProfiles],
      ).processAndApply();
      _postProcessEnvironment(environment, before: false);
      run.environmentPrepared(environment);
      _applyLoggingLevels(run, environment);
      _printBanner(environment, await _readBannerAsync(environment));
    } catch (error, stackTrace) {
      _report(run, error, stackTrace: stackTrace);
      rethrow;
    }
    final (context, arguments) = await _guardAsync(
      run,
      () => _startAsync(run, args, environment, watch, (
        systemEnvironment,
        properties,
        launchProfiles,
      )),
    );
    try {
      run.started(context, watch.elapsed);
      if (runners) {
        await _callRunners(context, arguments);
      }
    } catch (error, stackTrace) {
      await _runFailedAsync(run, context, error, stackTrace);
      rethrow;
    }
    _ready(run, context, watch);
    return context;
  }

  /// After a hot reload, returns a context built from the current code:
  /// [running] itself when its beans did not change, or a restarted one.
  ///
  /// A hot reload does not run `main` again, so the beans of the running
  /// context stay as they were built. Call this on the application the
  /// generated `springApplication` getter returns after the reload
  /// (Flutter's root widget does it through the generated
  /// `reloadApplication`):
  ///
  /// - Same [fingerprint] (only method bodies changed): [running] is
  ///   returned as it is, and the beans keep their state.
  /// - Different (beans, annotations or `lib/resources/` changed):
  ///   [running] is closed and the application starts again with the same
  ///   arguments, properties and profiles.
  ///
  /// [runners] says whether the `ApplicationRunner` and
  /// `CommandLineRunner` beans run again after such a restart. They hold
  /// "on startup" work (migrations, an `app_started` analytics event, a
  /// welcome log line), and the app did not really start again, so pass
  /// `false` to skip them. The default `true` matches Spring Boot
  /// DevTools, which runs them after every restart.
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
      previous?.additionalProfiles ?? const [],
      runners: runners,
    );
  }

  /// The asynchronous form of [reload], for Flutter and for code that
  /// uses [runAsync].
  ///
  /// [running] is closed with `closeAsync()`, which awaits its
  /// asynchronous destroy callbacks, and the new application starts as
  /// with [runAsync].
  Future<ConfigurableApplicationContext> reloadAsync(
    ConfigurableApplicationContext running, {
    bool runners = true,
  }) async {
    final previous = _launches[running];
    if (_isCurrent(running, previous)) {
      return running;
    }
    if (running.isActive) {
      await running.closeAsync();
    }
    return await _runAsync(
      previous?.args ?? const [],
      previous?.systemEnvironment,
      previous?.properties ?? const {},
      previous?.additionalProfiles ?? const [],
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
    if (dartDefines.isNotEmpty) {
      // Relaxed names like environment variables, right below the
      // command line.
      environment.propertySources.addAfter(
        SimpleCommandLinePropertySource.defaultName,
        SystemEnvironmentPropertySource(
          dartDefinesPropertySourceName,
          Map.of(dartDefines),
        ),
      );
    }
    if (properties.isNotEmpty) {
      environment.propertySources.addFirst(
        MapPropertySource('inlinedProperties', Map.of(properties)),
      );
    }
    if (_defaultProperties.isNotEmpty) {
      environment.propertySources.addLast(
        MapPropertySource(
          ConfigDataEnvironment.defaultPropertiesSourceName,
          Map.of(_defaultProperties),
        ),
      );
    }
    // Boot's RandomValuePropertySourceEnvironmentPostProcessor: `random.*`
    // before config data is loaded.
    RandomValuePropertySource.addToEnvironment(environment);
    return environment;
  }

  // The `logging.level.*` properties, then the lines held since the start
  // of the run, at those levels (Boot's LoggingApplicationListener
  // replaying the DeferredLogs once the logging system is initialized).
  static void _applyLoggingLevels(
    _RunListeners run,
    ConfigurableEnvironment environment,
  ) {
    applyLoggingLevels(environment);
    run.releaseLogs();
  }

  T _guard<T>(_RunListeners run, T Function() body) {
    try {
      return body();
    } catch (error, stackTrace) {
      _report(run, error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<T> _guardAsync<T>(_RunListeners run, Future<T> Function() body) async {
    try {
      return await body();
    } catch (error, stackTrace) {
      _report(run, error, stackTrace: stackTrace);
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
    Object error, {
    ConfigurableApplicationContext? context,
    StackTrace? stackTrace,
  }) {
    run.releaseLogs();
    run.deferredLogs.switchOver();
    if (_reported.remove(error)) {
      return;
    }
    _handleExitCode(context, error);
    run.failed(context, error);
    _reportFailure(context, error, stackTrace);
    if (context != null) {
      _reported.add(error);
    }
  }

  // Boot's reportFailure: the failure analysis (LoggingFailureAnalysisReporter)
  // or "Application run failed" with the error, to [out] or the log.
  void _reportFailure(
    ConfigurableApplicationContext? context,
    Object error,
    StackTrace? stackTrace,
  ) {
    final analysis = analyzeFailure(error, analyzers: _analyzers(context));
    final out = this.out;
    if (out != null) {
      out(analysis?.report ?? 'Application run failed: $error');
    } else if (analysis != null) {
      _reporterLog.error(analysis.report);
    } else {
      _log.error(
        'Application run failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static const _reporterLog = SpringLog(
    'spring_boot_dart.diagnostics.LoggingFailureAnalysisReporter',
  );

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
      } on Object catch (_) {
        // A context that failed early cannot provide them.
      }
      if (!context.isActive) {
        factory.destroySingletons();
      }
    }
    return [...failureAnalyzers, ...OrderComparator.sort(beans, (_) => null)];
  }

  // The auto-configurations left after the exclusions (`exclude`,
  // `excludeName`, `spring.autoconfigure.exclude`), in Boot's order.
  List<BeanModule> _selectedAutoConfigurations(
    StandardEnvironment environment,
  ) => selectAutoConfigurations(
    autoConfigurations,
    metadata: autoConfigurationMetadata,
    excludeTypes: exclude,
    excludeNames: [
      ...excludeName,
      ...Binder.get(environment)
          .bind(
            'spring.autoconfigure.exclude',
            const ListType<String>(ClassType<String>()),
          )
          .orElse(const []),
    ],
  );

  // Creates and refreshes the context and prints the startup line; the
  // runners are called by the caller afterwards (Spring Boot: logStarted,
  // then callRunners).
  // When a bean of [AsyncStartup] is still starting, the startup line
  // waits for it and the third value is its future.
  (ConfigurableApplicationContext, ApplicationArguments, Future<void>?) _start(
    _RunListeners run,
    List<String> args,
    StandardEnvironment environment,
    Stopwatch watch,
    (Map<String, String>?, Map<String, Object?>, List<String>) launch,
  ) {
    final prepared = _prepare(run, args, environment, launch);
    final context = prepared.context;
    try {
      context.refresh();
    } catch (error, stackTrace) {
      _logConditionReport(context, crash: true);
      _report(run, error, context: context, stackTrace: stackTrace);
      if (context.isActive) {
        context.close();
      }
      rethrow;
    }
    run.deferredLogs.switchOver();
    _logConditionReport(context);
    _registerShutdownHook(environment, context);
    final startup = _asyncStartups(context);
    if (startup != null) {
      return (
        context,
        prepared.arguments,
        startup.then((_) => _logStarted(prepared, watch)),
      );
    }
    _logStarted(prepared, watch);
    return (context, prepared.arguments, null);
  }

  // The starts still in progress after the refresh ([AsyncStartup]
  // singletons), as one future; `null` when there are none.
  static Future<void>? _asyncStartups(ConfigurableApplicationContext context) {
    final factory = context.beanFactory;
    final pending = <Future<void>>[
      for (final name in factory.singletonNames)
        if (factory.getSingleton(name) case final AsyncStartup bean)
          bean.awaitStartup(),
    ];
    return pending.isEmpty ? null : Future.wait(pending, eagerError: true);
  }

  // Like [_start] with `refreshAsync()`: asynchronous init callbacks are
  // awaited, and a failed context is closed with `closeAsync()`.
  Future<(ConfigurableApplicationContext, ApplicationArguments)> _startAsync(
    _RunListeners run,
    List<String> args,
    StandardEnvironment environment,
    Stopwatch watch,
    (Map<String, String>?, Map<String, Object?>, List<String>) launch,
  ) async {
    final prepared = _prepare(run, args, environment, launch);
    final context = prepared.context;
    try {
      await context.refreshAsync();
      // Beans that finish starting after the refresh (the web server
      // binding its port): their failure is a failed start.
      await _asyncStartups(context);
    } catch (error, stackTrace) {
      _logConditionReport(context, crash: true);
      _report(run, error, context: context, stackTrace: stackTrace);
      if (context.isActive) {
        await context.closeAsync();
      }
      rethrow;
    }
    run.deferredLogs.switchOver();
    _logConditionReport(context);
    _registerShutdownHook(environment, context);
    _logStarted(prepared, watch);
    return (context, prepared.arguments);
  }

  // Boot's ConditionEvaluationReportLogger: the report when `debug` is set
  // (`--debug`); for a failed start without it, how to get the report.
  static void _logConditionReport(
    ConfigurableApplicationContext context, {
    bool crash = false,
  }) {
    final debug = context.environment.getProperty('debug');
    if (debug != null && debug.trim().toLowerCase() != 'false') {
      _reportLog.info('${ConditionEvaluationReport.of(context)}');
    } else if (crash) {
      _reportLog.info(
        'Error starting ApplicationContext. To display the condition '
        "evaluation report re-run your application with 'debug' enabled.",
      );
    }
  }

  static const _reportLog = SpringLog(
    'spring_boot_dart.ConditionEvaluationReport',
  );

  void _logStarted(_Prepared prepared, Stopwatch watch) {
    if (prepared.logStartupInfo) {
      // Spring Boot's StartupInfoLogger.logStarted (without the process
      // uptime, which Dart does not know).
      _log.info(
        'Started ${prepared.name} in ${watch.elapsedMilliseconds / 1000} '
        'seconds',
      );
    }
  }

  // Creates and prepares the context up to the refresh (Spring Boot's
  // prepareContext).
  _Prepared _prepare(
    _RunListeners run,
    List<String> args,
    StandardEnvironment environment,
    (Map<String, String>?, Map<String, Object?>, List<String>) launch,
  ) {
    // Spring Boot's ContextIdApplicationContextInitializer.
    final applicationName = environment
        .getProperty('spring.application.name')
        ?.trim();
    final context = AnnotationConfigApplicationContext(
      [...modules, ..._selectedAutoConfigurations(environment)],
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
      launch.$3,
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
      ..registerSingleton(
        DeferredLogs.beanName,
        run.deferredLogs,
        types: const [DeferredLogs],
      )
      ..addBeanPostProcessor(
        ConfigurationPropertiesBinder(
          environment,
          context.introspector,
          beanFactory: context.beanFactory,
        ),
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
    for (final initializer in OrderComparator.sort(initializers)) {
      initializer.initialize(context);
    }
    run
      ..contextPrepared(context)
      ..contextLoaded(context);
    return (
      context: context,
      arguments: arguments,
      name: name,
      logStartupInfo: logStartupInfo,
    );
  }

  // SIGINT / SIGTERM close the context (Spring Boot's shutdown hook), unless
  // switched off by the property or the constructor.
  void _registerShutdownHook(
    StandardEnvironment environment,
    ConfigurableApplicationContext context,
  ) {
    if (environment.getPropertyAs<bool>('spring.main.register-shutdown-hook') ??
        registerShutdownHook) {
      context.registerShutdownHook();
    }
  }

  // A runner failed: ApplicationFailedEvent, reported like Spring Boot's
  // "Application run failed", and the context is closed.
  void _runFailed(
    _RunListeners run,
    ConfigurableApplicationContext context,
    Object error, {
    bool failedEvent = true,
    StackTrace? stackTrace,
  }) {
    _reportRunFailure(
      run,
      context,
      error,
      failedEvent: failedEvent,
      stackTrace: stackTrace,
    );
    if (context.isActive) {
      context.close();
    }
  }

  Future<void> _runFailedAsync(
    _RunListeners run,
    ConfigurableApplicationContext context,
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    _reportRunFailure(
      run,
      context,
      error,
      failedEvent: true,
      stackTrace: stackTrace,
    );
    if (context.isActive) {
      await context.closeAsync();
    }
  }

  void _reportRunFailure(
    _RunListeners run,
    ConfigurableApplicationContext context,
    Object error, {
    required bool failedEvent,
    StackTrace? stackTrace,
  }) {
    _handleExitCode(context, error);
    if (failedEvent) {
      run.failed(context, error);
    }
    _reportFailure(context, error, stackTrace);
  }

  // Boot's handleExitCode: the code from the ExitCodeExceptionMapper beans
  // (while the context is active), else from the error being an
  // ExitCodeGenerator; remembered for [exitCodeOf] and published as
  // ExitCodeEvent.
  void _handleExitCode(ConfigurableApplicationContext? context, Object error) {
    final active = context != null && context.isActive;
    var code = 0;
    if (active) {
      try {
        final generators = ExitCodeGenerators();
        for (final (mapper, order) in _beansWithOrder<ExitCodeExceptionMapper>(
          context,
        )) {
          generators.addMapped(error, mapper, order);
        }
        code = generators.exitCode;
      } on Object catch (_) {
        // Mappers that cannot be created map nothing.
      }
    }
    if (code == 0) {
      for (
        Object? e = error;
        e != null;
        e = e is BeansException ? e.cause : null
      ) {
        if (e is ExitCodeGenerator) {
          code = e.getExitCode();
          break;
        }
      }
    }
    if (code == 0) {
      return;
    }
    try {
      _exitCodes[error] = code;
    } on ArgumentError {
      // Strings and numbers cannot be keys; their exit code is not kept.
    }
    if (active) {
      context.publishEvent(ExitCodeEvent(context, code));
    }
  }

  static final _exitCodes = Expando<int>('SpringApplication exit codes');

  // The beans of type [T] with their `@Order` value.
  static List<(T, int?)> _beansWithOrder<T extends Object>(
    ConfigurableApplicationContext context,
  ) => [
    for (final name in context.getBeanNamesForType(T))
      (context.getBeanByName(name) as T, _definitionOrder(context, name)),
  ];

  // The `@Order` of bean [name]'s definition; `null` for a singleton
  // registered without one (`registerSingleton`).
  static int? _definitionOrder(
    ConfigurableApplicationContext context,
    String name,
  ) {
    final factory = context.beanFactory;
    return factory.containsBeanDefinition(name)
        ? factory.getBeanDefinition(name).order
        : null;
  }

  /// The exit code a failed run chose for [error], the error [run] or
  /// [runAsync] threw; `null` when it chose none.
  ///
  /// The code comes from the [ExitCodeExceptionMapper] beans, which are
  /// asked while the context is still active (so for a failing runner, not
  /// for a start that failed while creating the beans), else from [error]
  /// itself, or the error a `BeansException` wraps, when it is an
  /// [ExitCodeGenerator]. Strings and numbers thrown as errors never have
  /// one. Spring Boot passes the code to its exception handler; here
  /// `main` ends the process with it:
  ///
  /// ```dart
  /// try {
  ///   runApplication(args);
  /// } catch (error) {
  ///   exit(SpringApplication.exitCodeOf(error) ?? 1);
  /// }
  /// ```
  static int? exitCodeOf(Object error) {
    try {
      return _exitCodes[error];
    } on ArgumentError {
      return null;
    }
  }

  /// Closes [context] and returns the code the process should exit with.
  ///
  /// Call it at the end of a program whose result is its exit code (a
  /// batch job, a command-line tool), then pass the code to `exit`. The
  /// code comes from [exitCodeGenerators] and the [ExitCodeGenerator]
  /// beans, sorted by order (`Ordered`, `@Order`): the first non-zero code
  /// wins, `0` when there is none. A non-zero code is published as an
  /// [ExitCodeEvent] before the context closes. A failure on the way,
  /// closing included, is logged as a warning and gives `1` unless a code
  /// was found already.
  ///
  /// ```dart
  /// exit(SpringApplication.exit(context)); // dart:io
  /// ```
  static int exit(
    ConfigurableApplicationContext context, [
    List<ExitCodeGenerator> exitCodeGenerators = const [],
  ]) {
    var exitCode = 0;
    try {
      try {
        final generators = ExitCodeGenerators()..addAll(exitCodeGenerators);
        for (final (generator, order) in _beansWithOrder<ExitCodeGenerator>(
          context,
        )) {
          generators.add(generator, order);
        }
        exitCode = generators.exitCode;
        if (exitCode != 0) {
          context.publishEvent(ExitCodeEvent(context, exitCode));
        }
      } finally {
        context.close();
      }
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Failed to exit the application',
        error: error,
        stackTrace: stackTrace,
      );
      exitCode = exitCode != 0 ? exitCode : 1;
    }
    return exitCode;
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
          context.getBeanByName(name): _definitionOrder(context, name),
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

  // Like Boot's LenientObjectToEnumConverterFactory: `false` (YAML's `off`)
  // is OFF.
  static SpringLogLevel? _parseLevel(String? value) =>
      value?.trim().toLowerCase() == 'false'
      ? SpringLogLevel.off
      : parseSpringLogLevel(value);

  /// Sets the levels of [SpringLog] from the `logging.level.*` and
  /// `logging.group.*` properties of [environment].
  ///
  /// [run] calls it once the config files are read, with or without a
  /// logging starter, so applications only write the properties. Call it
  /// yourself only when you prepare an environment without
  /// `SpringApplication`:
  ///
  /// ```properties
  /// logging.level.root=info
  /// logging.level.neon.checkout=debug
  /// logging.group.payments=neon.payments,neon.checkout
  /// logging.level.payments=trace
  /// ```
  ///
  /// A level applies to the logger and every logger below it
  /// (`neon.checkout.cart`); a group sets the level of each logger it
  /// lists. The environment variable `LOGGING_LEVEL_NEON_CHECKOUT=debug`
  /// is the same as `logging.level.neon.checkout`; `false` (what YAML
  /// makes of an unquoted `off`) means `off`; an empty value leaves the
  /// level inherited. The levels set by an earlier call are cleared first.
  /// A value that is no level throws a
  /// [ConfigurationPropertiesBindException], which fails the start.
  static void applyLoggingLevels(ConfigurableEnvironment environment) {
    // Bound like Boot's LoggingApplicationListener: groups as lists (a
    // comma list or `logging.group.x[0]`), levels as a map whose values
    // must be log levels (anything else fails the start).
    final binder = Binder.get(environment);
    final groups = binder
        .bind(
          'logging.group',
          const MapType<String, List<String>>(
            ClassType<String>(),
            ListType<String>(ClassType<String>()),
          ),
        )
        .orElse(const {});
    final values = binder
        .bind(
          'logging.level',
          const MapType<String, String>(
            ClassType<String>(),
            ClassType<String>(),
          ),
        )
        .orElse(const {});
    final levels = <String, SpringLogLevel>{};
    final invalid = <String>[];
    for (final MapEntry(key: logger, :value) in values.entries) {
      if (value.trim().isEmpty) {
        continue; // no level: inherited
      }
      final level = _parseLevel(value);
      if (level == null) {
        invalid.add(
          'logging.level.$logger: failed to convert to LogLevel (was '
          '"$value"; use trace, debug, info, warn, error, fatal or off)',
        );
      } else {
        levels.putIfAbsent(logger, () => level);
      }
    }
    final scalar = environment.getProperty('logging.level');
    if (scalar != null &&
        scalar.trim().isNotEmpty &&
        _parseLevel(scalar) == null) {
      invalid.add(
        'logging.level: failed to convert to LogLevel (was "$scalar")',
      );
    }
    if (invalid.isNotEmpty) {
      throw ConfigurationPropertiesBindException(
        'logging.level',
        null,
        invalid,
      );
    }
    // `root` in any case, like Spring Boot; the first (highest) source's.
    final rootKey = levels.keys
        .where((name) => name.toLowerCase() == 'root')
        .firstOrNull;
    final root = rootKey != null ? levels[rootKey] : _parseLevel(scalar);
    levels.removeWhere((name, _) => name.toLowerCase() == 'root');
    if (root != null) {
      SpringLog.level = root;
    }
    SpringLog.resetLevels();
    for (final MapEntry(key: logger, value: level) in levels.entries) {
      for (final name in groups[logger] ?? [logger]) {
        if (name.trim().isNotEmpty) {
          SpringLog.setLevel(name.trim(), level);
        }
      }
    }
  }
}

/// Makes every singleton bean lazy: created the first time it is needed,
/// not at startup.
///
/// Starting faster matters for command-line tools and mobile apps that
/// use only some of their beans per run. The application only sets the
/// property `spring.main.lazy-initialization=true`, and
/// [SpringApplication] adds this post-processor. The price is that a bean
/// that cannot be created fails on first use instead of at startup.
///
/// Beans with their own `@Lazy(...)` annotation keep their setting.
/// `SmartInitializingSingleton` beans and the beans a
/// [LazyInitializationExcludeFilter] bean excludes stay eager.
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
    // Like Boot, the filter beans are created here.
    final filters = [
      const LazyInitializationExcludeFilter.forBeanTypes([
        SmartInitializingSingleton,
      ]),
      ...beanFactory.getBeansOfType<LazyInitializationExcludeFilter>().values,
    ];
    for (final name in beanFactory.beanDefinitionNames) {
      final definition = beanFactory.getBeanDefinition(name);
      if (definition.annotations.any((a) => a is Lazy) ||
          filters.any(
            (filter) =>
                filter.isExcluded(name, definition, definition.beanType),
          )) {
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
    final runtime = runtimeDescription(
      dart: dartVersion(),
      flutter: flutterVersionDefine,
      flutterDart: flutterDartVersionDefine,
    );
    final pid = processId();
    _log.info(
      'Starting $name'
      '${runtime == null ? '' : ' using $runtime'}'
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
      final profiles = active.length == 1
          ? '1 profile is'
          : '${active.length} profiles are';
      _log.info('The following $profiles active: ${quoted(active)}');
    }
  }

  @override
  int get order => Ordered.lowestPrecedence;
}

// A context ready to be refreshed, with what the startup line needs.
typedef _Prepared = ({
  ConfigurableApplicationContext context,
  ApplicationArguments arguments,
  String name,
  bool logStartupInfo,
});

/// Keeps some beans created at startup when
/// `spring.main.lazy-initialization=true` makes the others lazy.
///
/// Some beans must exist from the start even in a lazy application: a
/// bean that warms a cache, listens for messages or schedules work does
/// nothing if nobody asks for it. Declare a filter as a bean, and
/// [LazyInitializationBeanFactoryPostProcessor] leaves the beans it
/// excludes eager. Filter beans are created before the other beans.
///
/// ```dart
/// // The cache warmer must run at startup, lazy or not.
/// @Bean()
/// LazyInitializationExcludeFilter eagerCaches() =>
///     const LazyInitializationExcludeFilter.forBeanTypes([CacheWarmer]);
/// ```
///
/// Spring (Java), where the `@Bean` method is static:
/// ```java
/// @Bean
/// static LazyInitializationExcludeFilter eagerCaches() {
///   return LazyInitializationExcludeFilter.forBeanTypes(CacheWarmer.class);
/// }
/// ```
abstract interface class LazyInitializationExcludeFilter {
  /// A filter that asks [isExcluded] for each bean, for rules other than
  /// a list of types (by name, by annotation, ...).
  const factory LazyInitializationExcludeFilter.of(
    bool Function(
      String beanName,
      BeanDefinition<Object> definition,
      Type beanType,
    )
    isExcluded,
  ) = _FunctionExcludeFilter;

  /// A filter that keeps the beans of [types] eager: beans whose type, or
  /// one of the types they are registered under, is in [types].
  const factory LazyInitializationExcludeFilter.forBeanTypes(List<Type> types) =
      _TypesExcludeFilter;

  /// Whether the bean [beanName], with its [definition] and [beanType],
  /// stays eager (true) or may be made lazy (false).
  bool isExcluded(
    String beanName,
    BeanDefinition<Object> definition,
    Type beanType,
  );
}

final class _FunctionExcludeFilter implements LazyInitializationExcludeFilter {
  const _FunctionExcludeFilter(this._isExcluded);

  final bool Function(String, BeanDefinition<Object>, Type) _isExcluded;

  @override
  bool isExcluded(
    String beanName,
    BeanDefinition<Object> definition,
    Type beanType,
  ) => _isExcluded(beanName, definition, beanType);
}

final class _TypesExcludeFilter implements LazyInitializationExcludeFilter {
  const _TypesExcludeFilter(this.types);

  final List<Type> types;

  @override
  bool isExcluded(
    String beanName,
    BeanDefinition<Object> definition,
    Type beanType,
  ) => types.any((type) => type == beanType || definition.types.contains(type));
}

/// Code that prepares the context before its beans are created.
///
/// Some setup cannot be done with beans because it must happen before
/// any bean exists: a property source that every bean should see, a
/// ready-made object registered as a bean, a post-processor. Pass
/// initializers to `SpringApplication(initializers: [...])`; they run
/// after the context is created and before its beans are, sorted by
/// `Ordered` (unordered ones last). Test tools are the main users: they
/// add test properties and replace beans this way. Applications rarely
/// need one.
///
/// ```dart
/// // Point the clients at the local test servers, before any bean reads
/// // `api.url`.
/// final class TestServers implements ApplicationContextInitializer, Ordered {
///   @override
///   int get order => Ordered.highestPrecedence;
///
///   @override
///   void initialize(ConfigurableApplicationContext context) =>
///       context.environment.propertySources.addFirst(
///         MapPropertySource('servers', {'api.url': 'http://localhost:8081'}),
///       );
/// }
///
/// SpringApplication([appBeans], initializers: [
///   TestServers(),
///   ApplicationContextInitializer.of((context) => log.info(context.id)),
/// ]);
/// ```
///
/// Spring (Java):
/// ```java
/// class TestServers implements
///     ApplicationContextInitializer<ConfigurableApplicationContext>, Ordered {
///   public void initialize(ConfigurableApplicationContext context) { ... }
/// }
/// application.addInitializers(new TestServers(), context -> ...);
/// ```
abstract interface class ApplicationContextInitializer {
  /// An initializer that runs [initialize], placed by [order] (last by
  /// default); the short form of a class.
  const factory ApplicationContextInitializer.of(
    void Function(ConfigurableApplicationContext context) initialize, {
    int order,
  }) = _FunctionInitializer;

  /// Prepares [context], which has its environment and bean definitions
  /// but no beans yet.
  void initialize(ConfigurableApplicationContext context);
}

final class _FunctionInitializer
    implements ApplicationContextInitializer, Ordered {
  const _FunctionInitializer(
    this._initialize, {
    this.order = Ordered.lowestPrecedence,
  });

  final void Function(ConfigurableApplicationContext context) _initialize;

  @override
  final int order;

  @override
  void initialize(ConfigurableApplicationContext context) =>
      _initialize(context);
}

// Spring Boot's EventPublishingRunListener: the application's listeners
// get the early events through their own multicaster, the later ones
// through the context.
final class _RunListeners {
  _RunListeners(this.application, this.args) {
    application._listeners.forEach(_multicaster.addApplicationListener);
  }

  final SpringApplication application;
  final List<String> args;
  final _multicaster = SimpleApplicationEventMulticaster();

  // Every line logged before the `logging.level.*` properties are applied,
  // emitted then at those levels (releaseLogs).
  final SpringLogHold _logHold = SpringLog.hold();

  // What is logged before a logging system takes over (replayed by it).
  final deferredLogs = DeferredLogs.capture();

  void releaseLogs() => _logHold.release();

  // [body], releasing the held lines when it fails.
  T releasingLogsOnError<T>(T Function() body) {
    try {
      return body();
    } catch (_) {
      releaseLogs();
      rethrow;
    }
  }

  void starting() => releasingLogsOnError(
    () => _multicaster.multicastEvent(
      ApplicationStartingEvent(application, args),
    ),
  );

  void environmentPrepared(ConfigurableEnvironment environment) =>
      _multicaster.multicastEvent(
        ApplicationEnvironmentPreparedEvent(application, args, environment),
      );

  void contextPrepared(ConfigurableApplicationContext context) =>
      _multicaster.multicastEvent(
        ApplicationContextInitializedEvent(application, args, context),
      );

  void contextLoaded(ConfigurableApplicationContext context) {
    application._listeners.forEach(context.addApplicationListener);
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
        // Like Boot, also to the listeners added to the context.
        for (final listener
            in context?.applicationListeners ??
                const <GenericApplicationListener>[]) {
          if (!application._listeners.contains(listener)) {
            _multicaster.addApplicationListener(listener);
          }
        }
        _multicaster.multicastEvent(event);
      }
    } on Object catch (listenerError, stackTrace) {
      _log.warning(
        'Error handling failed',
        error: listenerError,
        stackTrace: stackTrace,
      );
    }
  }
}

final class _Launch {
  _Launch(
    this.fingerprint,
    this.args,
    this.systemEnvironment,
    this.properties,
    this.additionalProfiles,
  );

  final String? fingerprint;
  final List<String> args;
  final Map<String, String>? systemEnvironment;
  final Map<String, Object?> properties;
  final List<String> additionalProfiles;
}
