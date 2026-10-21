import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_boot_dart/src/failure_analyzer.dart';
import 'package:spring_boot_dart/src/runners.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Bootstraps an application, like Spring Boot's `SpringApplication`.
///
/// `run` does what an application would otherwise write by hand:
///
/// 1. command-line arguments and OS environment variables as property
///    sources;
/// 2. `config/application.properties` and `application-{profile}` files
///    (Spring Boot config data: profiles, imports, groups, ...);
/// 3. `logging.level.root` / `logging.level` applied to [SpringLog];
/// 4. the context: the application's modules, then [autoConfigurations]
///    (so `@ConditionalOnMissingBean` sees the application's beans),
///    `@ConfigurationProperties` binding, `ApplicationArguments` as a bean;
/// 5. `ApplicationRunner` / `CommandLineRunner` beans, in order;
/// 6. a startup line (`Started app in 42 ms (profiles: dev)`), or a
///    readable `APPLICATION FAILED TO START` report before the error is
///    rethrown.
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
    this.resourceLoader,
    void Function(String line)? out,
  }) : modules = List.unmodifiable(modules),
       autoConfigurations = List.unmodifiable(autoConfigurations),
       out = out ?? print;

  /// The application's own modules.
  final List<BeanModule> modules;

  /// Library modules registered after [modules].
  final List<BeanModule> autoConfigurations;

  /// Reads config files; defaults to a `DefaultResourceLoader`. Use an
  /// asset-aware loader (and [runAsync]) in Flutter.
  final ResourceLoader? resourceLoader;

  /// Where the startup line and failure reports go.
  final void Function(String line) out;

  /// Starts the application synchronously (config files read with
  /// `dart:io`). [systemEnvironment] replaces the OS environment (tests).
  ConfigurableApplicationContext run(
    List<String> args, {
    Map<String, String>? systemEnvironment,
  }) {
    final watch = Stopwatch()..start();
    final environment = _environment(args, systemEnvironment);
    return _guard(() {
      ConfigDataEnvironment(
        environment,
        resourceLoader: resourceLoader,
      ).processAndApplySync();
      return _start(args, environment, watch);
    });
  }

  /// Like [run], reading config files asynchronously (e.g. Flutter assets).
  Future<ConfigurableApplicationContext> runAsync(
    List<String> args, {
    Map<String, String>? systemEnvironment,
  }) async {
    final watch = Stopwatch()..start();
    final environment = _environment(args, systemEnvironment);
    try {
      await ConfigDataEnvironment(
        environment,
        resourceLoader: resourceLoader,
      ).processAndApply();
    } catch (error) {
      _report(error);
      rethrow;
    }
    return _guard(() => _start(args, environment, watch));
  }

  StandardEnvironment _environment(
    List<String> args,
    Map<String, String>? systemEnvironment,
  ) =>
      StandardEnvironment(systemEnvironment: systemEnvironment)
        ..propertySources.addFirst(SimpleCommandLinePropertySource(args));

  T _guard<T>(T Function() body) {
    try {
      return body();
    } catch (error) {
      _report(error);
      rethrow;
    }
  }

  void _report(Object error) {
    final analysis = analyzeFailure(error);
    if (analysis != null) {
      out(analysis.report);
    }
  }

  ConfigurableApplicationContext _start(
    List<String> args,
    StandardEnvironment environment,
    Stopwatch watch,
  ) {
    _applyLogging(environment);
    final context = AnnotationConfigApplicationContext(
      [...modules, ...autoConfigurations],
      environment: environment,
      resourceLoader: resourceLoader,
    );
    final arguments = ApplicationArguments(args);
    context.beanFactory
      ..registerSingleton(
        'springApplicationArguments',
        arguments,
        types: const [ApplicationArguments],
      )
      ..addBeanPostProcessor(
        ConfigurationPropertiesBinder(environment, context.introspector),
      );
    try {
      context.refresh();
      for (final runner in context.getSortedBeans<ApplicationRunner>()) {
        runner.run(arguments);
      }
      for (final runner in context.getSortedBeans<CommandLineRunner>()) {
        runner.run(args);
      }
    } catch (_) {
      if (context.isActive) {
        context.close();
      }
      rethrow;
    }
    if (environment.getProperty('spring.main.log-startup-info') != 'false') {
      final name =
          environment.getProperty('spring.application.name') ?? 'application';
      final profiles = environment.activeProfiles.isEmpty
          ? environment.defaultProfiles
          : environment.activeProfiles;
      out(
        'Started $name in ${watch.elapsedMilliseconds} ms '
        '(profiles: ${profiles.join(', ')})',
      );
    }
    return context;
  }

  // `logging.level.root` (or `logging.level`) sets SpringLog's threshold.
  static void _applyLogging(Environment environment) {
    final value =
        (environment.getProperty('logging.level.root') ??
                environment.getProperty('logging.level'))
            ?.trim()
            .toLowerCase();
    final level = switch (value) {
      'trace' => SpringLogLevel.trace,
      'debug' => SpringLogLevel.debug,
      'info' => SpringLogLevel.info,
      'warn' || 'warning' => SpringLogLevel.warning,
      'error' => SpringLogLevel.error,
      'off' => SpringLogLevel.off,
      _ => null,
    };
    if (level != null) {
      SpringLog.level = level;
    }
  }
}
