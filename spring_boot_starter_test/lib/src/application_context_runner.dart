import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_test/src/bean_override.dart';

/// Starts small contexts to test auto-configuration, like Spring Boot's
/// `ApplicationContextRunner`: the tool for starter authors.
///
/// The runner is immutable: every `with*` returns a new runner, so a base
/// runner can be shared by many tests. No config files are read and the
/// OS environment is empty unless set.
///
/// ```dart
/// final runner = ApplicationContextRunner()
///     .withAutoConfiguration(myStarterAutoConfiguration);
///
/// test('backs off when the app has its own client', () {
///   runner.withUserConfiguration(appWithClient).run((context) {
///     expect(context, hasSingleBean<HttpClient>());
///     expect(context.getBean<HttpClient>(), isA<AppClient>());
///   });
/// });
///
/// test('fails without a base url', () {
///   runner.withPropertyValues(['http.base-url=']).run((context) {
///     expect(context, hasFailed());
///   });
/// });
/// ```
///
/// Spring (Java):
/// ```java
/// new ApplicationContextRunner()
///     .withConfiguration(AutoConfigurations.of(MyAutoConfiguration.class))
///     .withPropertyValues("http.base-url=")
///     .run(context -> assertThat(context).hasFailed());
/// ```
final class ApplicationContextRunner {
  /// A runner without configuration.
  const ApplicationContextRunner() : this._();

  const ApplicationContextRunner._({
    this.userConfigurations = const [],
    this.autoConfigurations = const [],
    this.properties = const {},
    this.systemEnvironment = const {},
    this.initializers = const [],
    this.beans = const [],
  });

  /// Application modules, registered before [autoConfigurations].
  final List<BeanModule> userConfigurations;

  /// Auto-configuration modules under test.
  final List<BeanModule> autoConfigurations;

  /// Properties (highest precedence).
  final Map<String, Object?> properties;

  /// The OS environment seen by the context.
  final Map<String, String> systemEnvironment;

  /// Called before each refresh.
  final List<ApplicationContextInitializer> initializers;

  /// Extra beans registered with [withBean].
  final List<BeanOverride<Object>> beans;

  ApplicationContextRunner _copy({
    List<BeanModule>? userConfigurations,
    List<BeanModule>? autoConfigurations,
    Map<String, Object?>? properties,
    Map<String, String>? systemEnvironment,
    List<ApplicationContextInitializer>? initializers,
    List<BeanOverride<Object>>? beans,
  }) => ApplicationContextRunner._(
    userConfigurations: userConfigurations ?? this.userConfigurations,
    autoConfigurations: autoConfigurations ?? this.autoConfigurations,
    properties: properties ?? this.properties,
    systemEnvironment: systemEnvironment ?? this.systemEnvironment,
    initializers: initializers ?? this.initializers,
    beans: beans ?? this.beans,
  );

  /// Adds an application module (`withUserConfiguration`).
  ApplicationContextRunner withUserConfiguration(BeanModule module) =>
      _copy(userConfigurations: [...userConfigurations, module]);

  /// Adds an auto-configuration module (`withConfiguration(AutoConfigurations.of(...))`).
  ApplicationContextRunner withAutoConfiguration(BeanModule module) =>
      _copy(autoConfigurations: [...autoConfigurations, module]);

  /// Adds `key=value` properties (`withPropertyValues`).
  ApplicationContextRunner withPropertyValues(List<String> pairs) => _copy(
    properties: {
      ...properties,
      for (final pair in pairs)
        if (pair.indexOf('=') case final index when index > 0)
          pair.substring(0, index).trim(): pair.substring(index + 1)
        else
          pair.trim(): '',
    },
  );

  /// Replaces the OS environment (`withSystemProperties`, for variables).
  ApplicationContextRunner withSystemEnvironment(Map<String, String> env) =>
      _copy(systemEnvironment: {...systemEnvironment, ...env});

  /// Registers [instance] as a bean of [T], replacing an existing one
  /// (`withBean`).
  ApplicationContextRunner withBean<T extends Object>(
    T instance, {
    String? name,
  }) => _copy(
    beans: [
      ...beans,
      BeanOverride<T>(instance, name: name),
    ],
  );

  /// Adds an initializer (`withInitializer`).
  ApplicationContextRunner withInitializer(
    ApplicationContextInitializer initializer,
  ) => _copy(initializers: [...initializers, initializer]);

  /// Starts a context, passes it to [body] and closes it. A context that
  /// failed to start is passed too: check it with `hasFailed()` or
  /// [AssertableApplicationContext.startupFailure].
  R run<R>(R Function(AssertableApplicationContext context) body) {
    final environment = StandardEnvironment(
      systemEnvironment: systemEnvironment,
    );
    if (properties.isNotEmpty) {
      environment.propertySources.addFirst(
        MapPropertySource('test', Map.of(properties)),
      );
    }
    final context = AnnotationConfigApplicationContext([
      ...userConfigurations,
      ...autoConfigurations,
    ], environment: environment);
    context.beanFactory.addBeanPostProcessor(
      ConfigurationPropertiesBinder(environment, context.introspector),
    );
    if (beans.isNotEmpty) {
      context.addBeanFactoryPostProcessor(BeanOverrideProcessor(beans));
    }
    Object? failure;
    try {
      for (final initializer in initializers) {
        initializer(context);
      }
      context.refresh();
    } catch (error) {
      failure = error;
      if (context.isActive) {
        context.close();
      }
    }
    final assertable = AssertableApplicationContext._(context, failure);
    try {
      return body(assertable);
    } finally {
      if (context.isActive) {
        context.close();
      }
    }
  }
}

/// A context started by [ApplicationContextRunner.run], or the reason it
/// could not start (Spring's `AssertableApplicationContext`).
final class AssertableApplicationContext {
  AssertableApplicationContext._(this._context, this.startupFailure);

  final ConfigurableApplicationContext _context;

  /// Why the context failed to start; `null` when it started.
  final Object? startupFailure;

  /// Whether the context failed to start.
  bool get hasFailed => startupFailure != null;

  /// The started context; throws if it failed to start.
  ConfigurableApplicationContext get context {
    if (startupFailure case final failure?) {
      throw StateError('The context failed to start: $failure');
    }
    return _context;
  }

  /// The environment.
  ConfigurableEnvironment get environment => _context.environment;

  /// The bean of type [T] (optionally with [qualifier]).
  T getBean<T extends Object>({String? qualifier}) =>
      context.getBean<T>(qualifier: qualifier);

  /// The bean named [name].
  Object getBeanByName(String name) => context.getBeanByName(name);

  /// Names of the beans of type [T].
  List<String> getBeanNamesForType<T extends Object>() =>
      context.getBeanNamesForType(T);

  /// Whether a bean called [name] exists.
  bool containsBean(String name) => context.containsBean(name);
}
