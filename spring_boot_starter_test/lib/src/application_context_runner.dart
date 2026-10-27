import 'dart:async';

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
    this.autoConfigurationMetadata = const {},
    this.properties = const {},
    this.systemEnvironment = const {},
    this.initializers = const [],
    this.beans = const [],
    this.overrides = const [],
    this.parent,
    this.allowBeanDefinitionOverriding = false,
    this.allowCircularReferences = false,
  });

  /// Application modules, registered before [autoConfigurations].
  final List<BeanModule> userConfigurations;

  /// Auto-configuration modules under test, registered in Spring Boot's
  /// order (by name, `order`, then `before` / `after` of
  /// [autoConfigurationMetadata]), like `AutoConfigurations.of(...)`.
  final List<BeanModule> autoConfigurations;

  /// The `@AutoConfigurationModule` of each module of
  /// [autoConfigurations] given to [withAutoConfiguration].
  final Map<BeanModule, AutoConfigurationModule> autoConfigurationMetadata;

  /// The parent of the contexts ([withParent]).
  final ApplicationContext? parent;

  /// Whether a bean definition may replace another of the same name
  /// ([withAllowBeanDefinitionOverriding]; `false` like Boot's runner).
  final bool allowBeanDefinitionOverriding;

  /// [withAllowCircularReferences]: always `false` in a working run.
  final bool allowCircularReferences;

  /// Properties (highest precedence).
  final Map<String, Object?> properties;

  /// The OS environment seen by the context.
  final Map<String, String> systemEnvironment;

  /// Called before each refresh.
  final List<ApplicationContextInitializer> initializers;

  /// Beans registered with [withBean], before the configurations.
  final List<BeanDefinition<Object>> beans;

  /// Bean replacements added with [withBeanOverride].
  final List<BeanOverride<Object>> overrides;

  ApplicationContextRunner _copy({
    List<BeanModule>? userConfigurations,
    List<BeanModule>? autoConfigurations,
    Map<BeanModule, AutoConfigurationModule>? autoConfigurationMetadata,
    Map<String, Object?>? properties,
    Map<String, String>? systemEnvironment,
    List<ApplicationContextInitializer>? initializers,
    List<BeanDefinition<Object>>? beans,
    List<BeanOverride<Object>>? overrides,
    (ApplicationContext?,)? parent,
    bool? allowBeanDefinitionOverriding,
    bool? allowCircularReferences,
  }) => ApplicationContextRunner._(
    userConfigurations: userConfigurations ?? this.userConfigurations,
    autoConfigurations: autoConfigurations ?? this.autoConfigurations,
    autoConfigurationMetadata:
        autoConfigurationMetadata ?? this.autoConfigurationMetadata,
    properties: properties ?? this.properties,
    systemEnvironment: systemEnvironment ?? this.systemEnvironment,
    initializers: initializers ?? this.initializers,
    beans: beans ?? this.beans,
    overrides: overrides ?? this.overrides,
    parent: parent == null ? this.parent : parent.$1,
    allowBeanDefinitionOverriding:
        allowBeanDefinitionOverriding ?? this.allowBeanDefinitionOverriding,
    allowCircularReferences:
        allowCircularReferences ?? this.allowCircularReferences,
  );

  /// Adds an application module (`withUserConfiguration`).
  ApplicationContextRunner withUserConfiguration(BeanModule module) =>
      _copy(userConfigurations: [...userConfigurations, module]);

  /// Adds an auto-configuration module
  /// (`withConfiguration(AutoConfigurations.of(...))`) with the [metadata]
  /// of its `@AutoConfigurationModule` annotation (the generator passes it
  /// to `SpringApplication`; a runner needs it by hand). The modules are
  /// registered in Boot's order: by name, then `order`, then `before` /
  /// `after`, whatever order they were added in.
  ///
  /// ```dart
  /// runner
  ///     .withAutoConfiguration(webModule, const AutoConfigurationModule(
  ///       after: ['jacksonModule'],
  ///     ))
  ///     .withAutoConfiguration(jacksonModule);
  /// ```
  ApplicationContextRunner withAutoConfiguration(
    BeanModule module, [
    AutoConfigurationModule? metadata,
  ]) => _copy(
    autoConfigurations: [...autoConfigurations, module],
    autoConfigurationMetadata: {
      ...autoConfigurationMetadata,
      module: ?metadata,
    },
  );

  /// Uses [parent] as the parent of every context the runner starts
  /// (`withParent`): its beans can be injected, its environment is merged.
  ApplicationContextRunner withParent(ApplicationContext parent) =>
      _copy(parent: (parent,));

  /// Whether a bean definition may replace another of the same name
  /// (`withAllowBeanDefinitionOverriding`; off by default, like Boot).
  ApplicationContextRunner withAllowBeanDefinitionOverriding(bool allow) =>
      _copy(allowBeanDefinitionOverriding: allow);

  /// Boot's `withAllowCircularReferences`: `false` is the default and the
  /// only behaviour of `spring_core_dart`, which has no early references;
  /// with `true` every run fails with an `UnsupportedError` saying so.
  ApplicationContextRunner withAllowCircularReferences(bool allow) =>
      _copy(allowCircularReferences: allow);

  /// Adds `key=value` or `key:value` properties (`withPropertyValues`),
  /// split at the first `=` or `:` like Boot's `TestPropertyValues`; name
  /// and value are trimmed, a pair without a separator has an empty value.
  ///
  /// ```dart
  /// runner.withPropertyValues(['shop.name=Books', 'shop.url: http://x', 'flag'])
  /// ```
  ApplicationContextRunner withPropertyValues(List<String> pairs) => _copy(
    properties: {
      ...properties,
      for (final pair in pairs)
        if (_separatorIndex(pair) case final index when index > 0)
          pair.substring(0, index).trim(): pair.substring(index + 1).trim()
        else
          pair.trim(): '',
    },
  );

  // The first `=` or `:` (Boot's `TestPropertyValues.Pair.parse`).
  static int _separatorIndex(String pair) {
    final colon = pair.indexOf(':');
    final equals = pair.indexOf('=');
    if (colon < 0) {
      return equals;
    }
    return equals < 0 || colon < equals ? colon : equals;
  }

  /// Replaces the OS environment (`withSystemProperties`, for variables).
  ApplicationContextRunner withSystemEnvironment(Map<String, String> env) =>
      _copy(systemEnvironment: {...systemEnvironment, ...env});

  /// Registers an extra bean of [T] called [name] (default: the type name
  /// in lower camel case, see [defaultBeanName]), created by [supplier] in
  /// each context the runner starts, like Boot's `withBean(type, supplier)`:
  /// every run gets a new instance, never one a previous run destroyed.
  ///
  /// The bean is registered before the configurations are processed, so
  /// auto-configuration sees it: a `@ConditionalOnMissingBean` backs off,
  /// and a missing back-off shows up as a second bean (`hasSingleBean`
  /// fails) or, with the same name, as a failed start. It never replaces a
  /// bean; use [withBeanOverride] for that.
  ///
  /// ```dart
  /// runner.withBean<HttpClient>(FakeClient.new).run((context) {
  ///   expect(context, hasSingleBean<HttpClient>()); // the starter backed off
  /// });
  /// ```
  ///
  /// Spring Boot (Java):
  /// ```java
  /// runner.withBean(HttpClient.class, FakeClient::new)
  ///     .run(context -> assertThat(context).hasSingleBean(HttpClient.class));
  /// ```
  ApplicationContextRunner withBean<T extends Object>(
    T Function() supplier, {
    String? name,
  }) => _copy(
    beans: [
      ...beans,
      BeanDefinition<T>(
        name: name ?? defaultBeanName('$T'),
        types: [T],
        create: (_) => supplier(),
        // Unique: definitions of the same source are taken as one.
        source: 'ApplicationContextRunner.withBean<$T>#${beans.length}',
      ),
    ],
  );

  /// Replaces the bean of type [T] (or the bean called [name]) with
  /// [instance] after the configurations were processed, like Spring's
  /// `@TestBean` / `@MockitoBean`; see [BeanOverride]. Not in Boot's
  /// runner: to check auto-configuration, prefer [withBean].
  ///
  /// ```dart
  /// runner.withBeanOverride<Clock>(FixedClock(at)).run((context) { ... });
  /// ```
  ApplicationContextRunner withBeanOverride<T extends Object>(
    T instance, {
    String? name,
  }) => _copy(
    overrides: [
      ...overrides,
      BeanOverride<T>(instance, name: name),
    ],
  );

  /// Adds an initializer (`withInitializer`).
  ApplicationContextRunner withInitializer(
    ApplicationContextInitializer initializer,
  ) => _copy(initializers: [...initializers, initializer]);

  /// Starts a context, passes it to [body] and closes it. A context that
  /// failed to start is passed too: check it with `hasFailed()` or
  /// [AssertableApplicationContext.startupFailure]. For asynchronous
  /// checks use [runAsync] (this closes the context when [body] returns).
  R run<R>(R Function(AssertableApplicationContext context) body) {
    final assertable = _start();
    try {
      return body(assertable);
    } finally {
      assertable._close();
    }
  }

  /// Like [run], for an asynchronous [body]: the context is closed with
  /// `closeAsync()` (asynchronous `@PreDestroy` and lifecycle stops are
  /// awaited) once the returned future completes.
  ///
  /// ```dart
  /// await runner.runAsync((context) async {
  ///   expect(await context.getBean<CatalogClient>().find('1'), isNotNull);
  /// });
  /// ```
  Future<R> runAsync<R>(
    FutureOr<R> Function(AssertableApplicationContext context) body,
  ) async {
    final assertable = await _startAsync();
    try {
      return await body(assertable);
    } finally {
      await assertable._closeAsync();
    }
  }

  AssertableApplicationContext _start() {
    final context = _create();
    Object? failure;
    try {
      _prepare(context);
      context.refresh();
    } on Object catch (error) {
      failure = error;
      if (context.isActive) {
        context.close();
      }
    }
    return AssertableApplicationContext._(context, failure);
  }

  // Like [_start] with `refreshAsync()`: asynchronous init callbacks are
  // awaited, a failed context is closed with `closeAsync()`.
  Future<AssertableApplicationContext> _startAsync() async {
    final context = _create();
    Object? failure;
    try {
      _prepare(context);
      await context.refreshAsync();
    } on Object catch (error) {
      failure = error;
      if (context.isActive) {
        await context.closeAsync();
      }
    }
    return AssertableApplicationContext._(context, failure);
  }

  void _prepare(AnnotationConfigApplicationContext context) {
    if (allowCircularReferences) {
      throw UnsupportedError(
        'withAllowCircularReferences(true): circular references are always '
        'an error in spring_core_dart (there are no early references); '
        'break the cycle with ObjectProvider<T> or a lazy lookup',
      );
    }
    for (final initializer in initializers) {
      initializer.initialize(context);
    }
  }

  AnnotationConfigApplicationContext _create() {
    final environment = StandardEnvironment(
      systemEnvironment: systemEnvironment,
    );
    if (properties.isNotEmpty) {
      environment.propertySources.addFirst(
        MapPropertySource('test', Map.of(properties)),
      );
    }
    // Like Spring's ApplicationContextRunner (not the web one): a web
    // starter starts no server unless the test asks for one
    // (`spring.test.web-environment=random-port`).
    environment.propertySources.addLast(
      const MapPropertySource('applicationContextRunnerDefaults', {
        'spring.test.web-environment': 'mock',
      }),
    );
    // Relaxed names, as in an application started by SpringApplication.
    ConfigurationPropertySources.attach(environment);
    final context = AnnotationConfigApplicationContext(
      [
        // Like Boot: registered beans first, then the configurations.
        if (beans.isNotEmpty)
          BeanModule('ApplicationContextRunner.beans', beans),
        ...userConfigurations,
        ...selectAutoConfigurations(
          autoConfigurations,
          metadata: autoConfigurationMetadata,
        ),
      ],
      environment: environment,
      parent: parent,
    );
    if (context.beanFactory case final DefaultListableBeanFactory factory) {
      factory.allowBeanDefinitionOverriding = allowBeanDefinitionOverriding;
    }
    context.beanFactory.addBeanPostProcessor(
      ConfigurationPropertiesBinder(
        environment,
        context.introspector,
        beanFactory: context.beanFactory,
      ),
    );
    if (overrides.isNotEmpty) {
      context.addBeanFactoryPostProcessor(BeanOverrideProcessor(overrides));
    }
    return context;
  }
}

/// A context started by [ApplicationContextRunner.run], or the reason it
/// could not start (Spring's `AssertableApplicationContext`).
final class AssertableApplicationContext {
  AssertableApplicationContext._(this._context, this.startupFailure);

  final ConfigurableApplicationContext _context;

  void _close() {
    if (_context.isActive) {
      _context.close();
    }
  }

  Future<void> _closeAsync() async {
    if (_context.isActive) {
      await _context.closeAsync();
    }
  }

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
