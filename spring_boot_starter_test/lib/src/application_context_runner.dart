import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_test/src/bean_override.dart';

/// Starts a small, throwaway application context per test, to check what
/// an auto-configuration creates under which properties and beans.
///
/// It is the tool for starter authors. A starter's auto-configuration
/// must react to its surroundings: create a bean by default, back off when
/// the application declares its own, change with a property, fail on a
/// bad value. Starting the whole application for each case would be slow
/// and would read its config files; the runner starts only the modules
/// you give it, with the properties you give it. Application tests use
/// `springBootTest` instead.
///
/// The runner is immutable: every `with...` method returns a new runner,
/// so a base runner can be shared by many tests and extended in each. No
/// config files are read, and the OS environment is empty unless set with
/// [withSystemEnvironment]. `@ConfigurationProperties` beans are bound and
/// relaxed property names work, as in an application. No web server
/// starts: the runner sets `spring.test.web-environment=mock` (add
/// `withPropertyValues(['spring.test.web-environment=random-port'])` for
/// one).
///
/// ```dart
/// final runner = const ApplicationContextRunner()
///     .withAutoConfiguration(myStarterAutoConfiguration);
///
/// test('backs off when the app has its own client', () {
///   // The application's own HttpClient, registered before the starter.
///   runner.withBean<HttpClient>(AppClient.new).run((context) {
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
  /// A runner with no modules, properties or beans; add them with the
  /// `with...` methods.
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

  /// The application modules added with [withUserConfiguration],
  /// registered before [autoConfigurations] so their beans are seen by the
  /// conditions.
  final List<BeanModule> userConfigurations;

  /// The auto-configuration modules under test, added with
  /// [withAutoConfiguration]. They are registered in Spring Boot's order,
  /// whatever order they were added in: by `order`, then by name, then
  /// moved by `before` / `after` of [autoConfigurationMetadata].
  final List<BeanModule> autoConfigurations;

  /// The `@AutoConfigurationModule` annotation of each module of
  /// [autoConfigurations], as given to [withAutoConfiguration]; a module
  /// without one has order `0` and no `before` / `after`.
  final Map<BeanModule, AutoConfigurationModule> autoConfigurationMetadata;

  /// The parent of every context the runner starts, set with [withParent];
  /// `null` for none.
  final ApplicationContext? parent;

  /// Whether a bean definition may replace another of the same name, set
  /// with [withAllowBeanDefinitionOverriding]; `false` by default, as in
  /// Boot's runner.
  final bool allowBeanDefinitionOverriding;

  /// The value set with [withAllowCircularReferences]. Only `false` gives a
  /// working run.
  final bool allowCircularReferences;

  /// The properties added with [withPropertyValues]. They win over every
  /// other property source, the environment included.
  final Map<String, Object?> properties;

  /// The environment variables the contexts see, set with
  /// [withSystemEnvironment]; empty by default.
  final Map<String, String> systemEnvironment;

  /// The initializers added with [withInitializer], called in order on each
  /// context before it is refreshed.
  final List<ApplicationContextInitializer> initializers;

  /// The beans added with [withBean], registered before the configurations.
  final List<BeanDefinition<Object>> beans;

  /// The bean replacements added with [withBeanOverride].
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

  /// Adds an application module, registered before the auto-configuration:
  /// the way to give the context beans that a real application would
  /// declare, so that a `@ConditionalOnMissingBean` sees them. Spring Boot's
  /// `withUserConfiguration`.
  ApplicationContextRunner withUserConfiguration(BeanModule module) =>
      _copy(userConfigurations: [...userConfigurations, module]);

  /// Adds an auto-configuration module under test, with the [metadata] of
  /// its `@AutoConfigurationModule` annotation.
  ///
  /// In an application the generator passes that annotation to
  /// `SpringApplication`; Dart cannot read the annotation of a variable at
  /// run time, so a runner needs it by hand when the module has an `order`,
  /// `before` or `after`. The modules are registered in Spring Boot's order
  /// (by `order`, then by name, then moved by `before` / `after`), whatever
  /// order they were added in. Spring Boot's
  /// `withConfiguration(AutoConfigurations.of(...))`.
  ///
  /// ```dart
  /// // The web module's conditions must see the JSON module's beans.
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

  /// Makes [parent] the parent of every context the runner starts: its
  /// beans can be injected and count for the matchers, and its environment
  /// is merged. Use it to test a starter that runs in a child context.
  ApplicationContextRunner withParent(ApplicationContext parent) =>
      _copy(parent: (parent,));

  /// Sets whether a bean definition may replace another of the same name.
  /// Off by default, as in Boot, so a duplicate name fails the start.
  ApplicationContextRunner withAllowBeanDefinitionOverriding(bool allow) =>
      _copy(allowBeanDefinitionOverriding: allow);

  /// Exists for Spring Boot's `withAllowCircularReferences`. `false` is the
  /// default and the only behaviour of `spring_core_dart`, which has no
  /// early references; with `true` every run fails with an
  /// `UnsupportedError` that says so.
  ApplicationContextRunner withAllowCircularReferences(bool allow) =>
      _copy(allowCircularReferences: allow);

  /// Adds properties written as `key=value` or `key:value`, the form of
  /// Boot's `TestPropertyValues`.
  ///
  /// Each pair is split at its first `=` or `:`; name and value are
  /// trimmed, and a pair without a separator gets an empty value. They win
  /// over every other property source; a key added again replaces the
  /// earlier value.
  ///
  /// ```dart
  /// // shop.name = Books, shop.url = http://x, flag = '' (empty)
  /// runner.withPropertyValues([
  ///   'shop.name=Books',
  ///   'shop.url: http://x',
  ///   'flag',
  /// ]);
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

  /// Sets environment variables for the contexts, in place of the OS
  /// environment; added to those of earlier calls. Use it to test settings
  /// that come from variables (`NEON_CACHE_SIZE` for `neon.cache.size`).
  /// Spring Boot's `withSystemProperties` is the closest.
  ApplicationContextRunner withSystemEnvironment(Map<String, String> env) =>
      _copy(systemEnvironment: {...systemEnvironment, ...env});

  /// Registers an extra bean of [T] called [name] (default: the type name in
  /// lower camel case, see [defaultBeanName]), created by [supplier] in each
  /// context the runner starts. Every run gets a new instance, never one
  /// that a previous run destroyed.
  ///
  /// The bean is registered before the configurations, so the
  /// auto-configuration sees it: a `@ConditionalOnMissingBean` backs off,
  /// and a missing back-off shows up as a second bean (`hasSingleBean`
  /// fails) or, with the same name, as a failed start. It never replaces a
  /// bean; use [withBeanOverride] for that.
  ///
  /// ```dart
  /// // The application has its own client: the starter must not add one.
  /// runner.withBean<HttpClient>(FakeClient.new).run((context) {
  ///   expect(context, hasSingleBean<HttpClient>());
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
  /// [instance] after the configurations were registered, as
  /// `springBootTest(overrides:)` does; see [BeanOverride].
  ///
  /// Use it when a configuration's bean needs a fake collaborator, such as a
  /// fixed clock. It is not in Boot's runner, and it hides back-off
  /// mistakes: to check that a configuration backs off, use [withBean].
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

  /// Adds an initializer, called on each context before it is refreshed:
  /// for setup the other methods do not cover, such as adding a property
  /// source or a bean factory post-processor. Spring Boot's
  /// `withInitializer`.
  ApplicationContextRunner withInitializer(
    ApplicationContextInitializer initializer,
  ) => _copy(initializers: [...initializers, initializer]);

  /// Starts a context, passes it to [body], closes it with `close()` when
  /// [body] returns, and returns what [body] returned.
  ///
  /// A context that failed to start is passed too, instead of throwing:
  /// check it with `hasFailed()` or
  /// [AssertableApplicationContext.startupFailure]. For a [body] that
  /// awaits, use [runAsync]; here the context would be closed at the first
  /// `await`.
  R run<R>(R Function(AssertableApplicationContext context) body) {
    final assertable = _start();
    try {
      return body(assertable);
    } finally {
      assertable._close();
    }
  }

  /// Like [run], for an asynchronous [body]: the context is refreshed with
  /// `refreshAsync()` (asynchronous init methods are awaited) and closed
  /// with `closeAsync()` (asynchronous `@PreDestroy` methods and lifecycle
  /// stops are awaited) once the returned future completes.
  ///
  /// ```dart
  /// test('calls the client', () async {
  ///   await runner.runAsync((context) async {
  ///     expect(await context.getBean<CatalogClient>().find('1'), isNotNull);
  ///   });
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

/// What [ApplicationContextRunner.run] hands to the test: the started
/// context, or the reason it could not start.
///
/// A failed start does not throw, so a test can check that a
/// configuration rejects bad input: `expect(context, hasFailed())`. On a
/// started context, the matchers and [getBean] read the beans; reading a
/// bean of a failed one throws a [StateError] with the failure.
///
/// ```dart
/// runner.run((context) {
///   // The starter's default, created because the app has none.
///   expect(context, hasSingleBean<CacheManager>());
///   expect(context.getBean<CacheManager>(), isA<InMemoryCacheManager>());
/// });
/// ```
///
/// Spring (Java): Spring Boot's `AssertableApplicationContext`, used with
/// AssertJ's `assertThat(context)`.
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

  /// The error that stopped the start; `null` when the context started.
  final Object? startupFailure;

  /// Whether the context failed to start.
  bool get hasFailed => startupFailure != null;

  /// The started context, for checks the shortcuts below do not cover.
  /// Throws a [StateError] with the failure when the context did not start.
  ConfigurableApplicationContext get context {
    if (startupFailure case final failure?) {
      throw StateError('The context failed to start: $failure');
    }
    return _context;
  }

  /// The context's environment, also after a failed start: to check the
  /// properties the configuration saw.
  ConfigurableEnvironment get environment => _context.environment;

  /// The bean of type [T]; with [qualifier], the one it names among
  /// several. Throws when no bean matches or the context did not start.
  T getBean<T extends Object>({String? qualifier}) =>
      context.getBean<T>(qualifier: qualifier);

  /// The bean called [name], whatever its type. Throws when there is none
  /// or the context did not start.
  Object getBeanByName(String name) => context.getBeanByName(name);

  /// The names of the beans of type [T] in this context (not its parent),
  /// to check which configuration created them.
  List<String> getBeanNamesForType<T extends Object>() =>
      context.getBeanNamesForType(T);

  /// Whether a bean called [name] exists, here or in a parent context.
  bool containsBean(String name) => context.containsBean(name);
}
