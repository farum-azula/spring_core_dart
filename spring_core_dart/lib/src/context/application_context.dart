import 'dart:async';

import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/auto_proxy_creator.dart';
import 'package:spring_core_dart/src/beans/aware.dart';
import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/default_listable_bean_factory.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/object_provider.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/context/annotations.dart'
    show Async, Configuration;
import 'package:spring_core_dart/src/context/bean_module.dart';
import 'package:spring_core_dart/src/context/bean_registrar.dart';
import 'package:spring_core_dart/src/context/condition.dart';
import 'package:spring_core_dart/src/context/context_aware.dart';
import 'package:spring_core_dart/src/context/event/application_event.dart';
import 'package:spring_core_dart/src/context/event/application_event_multicaster.dart';
import 'package:spring_core_dart/src/context/event/application_listener.dart';
import 'package:spring_core_dart/src/context/event/context_events.dart';
import 'package:spring_core_dart/src/context/event/event_listener_method.dart';
import 'package:spring_core_dart/src/context/lifecycle.dart';
import 'package:spring_core_dart/src/context/message/abstract_message_source.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/context/shutdown_hook.dart';
import 'package:spring_core_dart/src/context/task_executor.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/env/config/config_data_environment.dart'
    show ConfigDataEnvironment;
import 'package:spring_core_dart/src/core/env/config/property_source_factory.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';
import 'package:spring_core_dart/src/core/io/resource_pattern_resolver.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/order.dart';
import 'package:spring_core_dart/src/expression/bean_expression_resolver.dart';
import 'package:spring_core_dart/src/expression/introspection_access.dart';

/// The application context, like Spring's `ApplicationContext`: a bean
/// factory plus environment, events, messages and resources.
///
/// Read-only view: lookups, events, messages and resources. Lifecycle
/// methods (`refresh`, `close`) live on [ConfigurableApplicationContext].
///
/// ```dart
/// final context = ApplicationContext.run([coreBeans, authBeans]);
/// final auth = context.getBean<AuthFacade>();
/// context.publishEvent(UserLoggedIn('ada'));
/// final title = context.getMessage('app.title', locale: 'de');
/// ```
///
/// Spring (Java):
/// ```java
/// ApplicationContext context =
///     new AnnotationConfigApplicationContext(AppConfig.class);
/// AuthFacade auth = context.getBean(AuthFacade.class);
/// context.publishEvent(new UserLoggedIn("ada"));
/// String title = context.getMessage("app.title", null, Locale.GERMAN);
/// ```
abstract interface class ApplicationContext
    implements
        ListableBeanFactory,
        HierarchicalBeanFactory,
        MessageSource,
        ApplicationEventPublisher,
        ResourcePatternResolver {
  /// Creates and refreshes an [AnnotationConfigApplicationContext].
  ///
  /// ```dart
  /// final context = ApplicationContext.run(
  ///   [appBeans],
  ///   environment: StandardEnvironment()..setActiveProfiles(['dev']),
  /// );
  /// // ...
  /// context.close();
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// var context = new AnnotationConfigApplicationContext(AppConfig.class);
  /// ```
  static ConfigurableApplicationContext run(
    List<BeanModule> modules, {
    ApplicationContext? parent,
    ConfigurableEnvironment? environment,
    ResourceLoader? resourceLoader,
    String? id,
  }) => AnnotationConfigApplicationContext(
    modules,
    parent: parent,
    environment: environment,
    resourceLoader: resourceLoader,
    id: id,
  )..refresh();

  /// Like [run], refreshing with [ConfigurableApplicationContext.refreshAsync]
  /// (asynchronous init callbacks are awaited).
  static Future<ConfigurableApplicationContext> runAsync(
    List<BeanModule> modules, {
    ApplicationContext? parent,
    ConfigurableEnvironment? environment,
    ResourceLoader? resourceLoader,
    String? id,
  }) async {
    final context = AnnotationConfigApplicationContext(
      modules,
      parent: parent,
      environment: environment,
      resourceLoader: resourceLoader,
      id: id,
    );
    await context.refreshAsync();
    return context;
  }

  /// Unique id of the context; by default the class name and identity
  /// hash code (`AnnotationConfigApplicationContext@1b2c3d`), like Spring's
  /// `ObjectUtils.identityToString`. Spring Boot's `SpringApplication`
  /// uses `spring.application.name` (or `application`).
  String get id;

  /// Human-readable name used in error messages and `toString`.
  String get displayName;

  /// When the last refresh started; `null` before.
  DateTime? get startupDate;

  /// The parent context, or `null`. Beans, messages and events fall back
  /// to (or propagate to) the parent.
  ApplicationContext? get parent;

  /// The environment: properties, profiles and conversion.
  Environment get environment;

  /// The factory for injecting objects the container did not create.
  AutowireCapableBeanFactory get autowireCapableBeanFactory;

  /// Adds a listener for events (or payloads) of type [E]; remove it with
  /// the returned registration. Lower [order] values run first.
  ///
  /// ```dart
  /// final registration = context.addListener<OrderPlaced>(
  ///   (order) => print('placed ${order.id}'),
  /// );
  /// context.publishEvent(OrderPlaced(1, 20)); // prints "placed 1"
  /// registration.remove();
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.addApplicationListener(ApplicationListener.forPayload(
  ///     (OrderPlaced order) -> System.out.println("placed " + order.id())));
  /// // Spring has no registration handle: keep the listener and call
  /// // removeApplicationListener.
  /// ```
  ListenerRegistration addListener<E>(
    void Function(E event) listener, {
    int order,
  });
}

/// A configurable [ApplicationContext], like Spring's
/// `ConfigurableApplicationContext`.
///
/// Adds module registration, [refresh], [close] and [Lifecycle] control.
///
/// ```dart
/// final context = AnnotationConfigApplicationContext([appBeans])
///   ..register(pluginBeans)
///   ..addBeanFactoryPostProcessor(MyPostProcessor())
///   ..refresh();
/// try {
///   context.getBean<App>().run();
/// } finally {
///   context.close();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try (var context = new AnnotationConfigApplicationContext()) {
///   context.register(AppConfig.class, PluginConfig.class);
///   context.addBeanFactoryPostProcessor(new MyPostProcessor());
///   context.refresh();
///   context.getBean(App.class).run();
/// }
/// ```
abstract interface class ConfigurableApplicationContext
    implements ApplicationContext, Lifecycle {
  @override
  ConfigurableEnvironment get environment;

  @override
  ApplicationContext? get parent;

  /// Sets the parent context; its environment is merged into this one.
  set parent(ApplicationContext? parent);

  /// The underlying bean factory (available before refresh).
  ConfigurableListableBeanFactory get beanFactory;

  /// Adds a [BeanModule], a `BeanRegistrar`, an `ImportSelector` or an
  /// `ImportBeanDefinitionRegistrar` before [refresh] (Spring's
  /// `register(Class...)` / `register(BeanRegistrar...)`); they are
  /// processed in registration order while the modules load. Throws an
  /// `ArgumentError` for other objects and a `StateError` once [refresh]
  /// has started.
  ///
  /// ```dart
  /// context
  ///   ..register(appBeans)
  ///   ..register(const MessagingRegistrar());
  /// ```
  void register(Object component);

  /// Adds a post-processor applied during [refresh].
  void addBeanFactoryPostProcessor(BeanFactoryPostProcessor processor);

  /// Adds a listener; works before and after [refresh].
  ///
  /// ```dart
  /// context.addApplicationListener(
  ///   ApplicationListenerAdapter.of<ContextRefreshedEvent>((_) => ready()),
  /// );
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.addApplicationListener(
  ///     (ContextRefreshedEvent e) -> ready());
  /// ```
  void addApplicationListener(GenericApplicationListener listener);

  /// Removes a listener added with [addApplicationListener].
  void removeApplicationListener(GenericApplicationListener listener);

  /// The listeners added with [addApplicationListener] (Spring's
  /// `getApplicationListeners`), including the singleton
  /// [GenericApplicationListener] beans and `registerSingleton` objects
  /// added once created, as Spring's `ApplicationListenerDetector` does;
  /// `ApplicationListener<E>` beans (wired by bean name), lazy listener
  /// beans not created yet and `@EventListener` methods are not included.
  List<GenericApplicationListener> get applicationListeners;

  /// Adds a resolver for a custom location scheme (for example `asset:`),
  /// like Spring's `DefaultResourceLoader.addProtocolResolver`.
  void addProtocolResolver(ProtocolResolver resolver);

  /// Registers, validates and creates eager singletons. Call once.
  ///
  /// Steps: validate required properties, load modules (property sources,
  /// conditions), run bean factory post-processors, register bean
  /// post-processors, init message source and event multicaster, register
  /// listeners, validate the bean graph, create eager singletons, start
  /// auto-startup [SmartLifecycle] beans and publish
  /// `ContextRefreshedEvent`. On failure created singletons are destroyed
  /// and the context becomes unusable.
  ///
  /// ```dart
  /// final context = AnnotationConfigApplicationContext([appBeans])
  ///   ..refresh();
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// var context = new AnnotationConfigApplicationContext();
  /// context.register(AppConfig.class);
  /// context.refresh();
  /// ```
  ///
  /// Like Spring's `GenericApplicationContext`, a second call throws (a
  /// `StateError`), also after a failed refresh. An init callback
  /// (`@PostConstruct`, `afterPropertiesSet`, init method) that returns a
  /// `Future` fails the refresh: use [refreshAsync] for those.
  void refresh();

  /// Like [refresh], awaiting asynchronous init callbacks: the eager
  /// singletons are created, then every `Future` returned by their
  /// `@PostConstruct`, `afterPropertiesSet` and init methods is awaited
  /// (a failure fails the refresh, naming the bean) before
  /// `SmartInitializingSingleton`, the lifecycle start and
  /// `ContextRefreshedEvent`. A failed refresh stops the lifecycle beans
  /// already started and destroys the created singletons, awaiting
  /// asynchronous destroy callbacks.
  ///
  /// ```dart
  /// final context = AnnotationConfigApplicationContext([appBeans]);
  /// await context.refreshAsync();
  /// ```
  Future<void> refreshAsync();

  /// Publishes `ContextClosedEvent`, stops lifecycle beans and destroys
  /// singletons. Safe to call more than once. Does not wait: a
  /// `SmartLifecycle` callback that comes later or a destroy callback
  /// returning a `Future` is logged and the shutdown goes on; see
  /// [closeAsync].
  ///
  /// ```dart
  /// final context = ApplicationContext.run([appBeans]);
  /// context.registerShutdownHook(); // or close() yourself
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.close(); // or context.registerShutdownHook();
  /// ```
  void close();

  /// Closes the context with [closeAsync] (waiting for asynchronous
  /// `SmartLifecycle` stops and destroy callbacks) when the process gets
  /// SIGINT or SIGTERM, then ends the process with `128 + signal` (`130`,
  /// `143`),
  /// like Spring's `registerShutdownHook()` on the JVM. Registered once;
  /// the signals are no longer watched once the context closes (a Dart
  /// program that watches signals does not end by itself). Does nothing
  /// without `dart:io` (web).
  ///
  /// ```dart
  /// final context = ApplicationContext.run([appBeans])
  ///   ..registerShutdownHook();
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.registerShutdownHook();
  /// ```
  void registerShutdownHook();

  /// Stops the running [Lifecycle] beans except the [SmartLifecycle] beans
  /// that are not [SmartLifecycle.isPauseable], then publishes
  /// `ContextPausedEvent`, like Spring 7's `pause()`; [restart] resumes.
  /// A no-op for the beans unless the lifecycle is running. Does not wait
  /// for `SmartLifecycle.stopWithCallback` callbacks; see [pauseAsync].
  ///
  /// ```dart
  /// // Flutter: AppLifecycleState.paused / resumed
  /// context.pause();
  /// context.restart();
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.pause();
  /// context.restart();
  /// ```
  void pause();

  /// Like [pause], waiting for the `SmartLifecycle.stopWithCallback`
  /// callbacks of each phase (at most the lifecycle processor's timeout
  /// per phase) before `ContextPausedEvent` is published.
  Future<void> pauseAsync();

  /// Stops the pauseable [Lifecycle] beans if the lifecycle is running,
  /// then starts the auto-startup [SmartLifecycle] beans again (restoring
  /// the state after [refresh]) and publishes `ContextRestartedEvent`,
  /// like Spring 7's `restart()`. Unlike [start], beans that are not
  /// auto-startup stay stopped. A bean whose
  /// `SmartLifecycle.stopWithCallback` callback is still pending is started
  /// when the callback fires.
  void restart();

  /// Like [close], waiting: for the `SmartLifecycle.stopWithCallback`
  /// callbacks of each phase (at most the lifecycle processor's timeout
  /// per phase, 10 seconds by default; then the beans still running are
  /// logged and the next phase is stopped) and for destroy callbacks
  /// (`@PreDestroy`, `DisposableBean.destroy`, destroy methods) that
  /// return a `Future`, each bean after its dependents. Completes once
  /// the context is closed; a no-op unless active.
  ///
  /// ```dart
  /// ProcessSignal.sigint.watch().listen((_) async {
  ///   await context.closeAsync();
  ///   exit(0);
  /// });
  /// ```
  Future<void> closeAsync();

  /// Whether the context is active: from the start of [refresh] until
  /// [close] has finished (`false` again after a failed refresh), like
  /// Spring's `isActive()`.
  bool get isActive;

  /// Whether [close] has completed.
  bool get isClosed;
}

// created → refreshing → active → closed; a throwing refresh() ends in
// failed. Only `active` (and `refreshing`, for beans created during
// refresh) allows bean lookups.
enum _State { created, refreshing, active, closing, failed, closed }

/// The standard context for generated modules, like Spring's
/// `AnnotationConfigApplicationContext`.
///
/// Beans come from [BeanModule]s (usually generated by `@ComponentScan`)
/// instead of scanned classes. Override infrastructure by declaring beans
/// with the well-known names below (for example a `messageSource` bean).
///
/// ```dart
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
///
/// void main() {
///   final context = AnnotationConfigApplicationContext(
///     [appBeans],
///     environment: StandardEnvironment()..setActiveProfiles(['dev']),
///   )..refresh();
///   context.getBean<App>().run();
///   context.close();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// var context = new AnnotationConfigApplicationContext();
/// context.getEnvironment().setActiveProfiles("dev");
/// context.register(AppConfig.class);
/// context.refresh();
/// context.getBean(App.class).run();
/// context.close();
/// ```
class AnnotationConfigApplicationContext
    implements ConfigurableApplicationContext {
  /// Creates a context for [modules]; call [refresh] before using it.
  ///
  /// Defaults: a new `StandardEnvironment`, a `DefaultResourceLoader` and
  /// a unique id (see [ApplicationContext.id]). With a [parent], its
  /// environment is merged into [environment].
  AnnotationConfigApplicationContext(
    List<BeanModule> modules, {
    ApplicationContext? parent,
    ConfigurableEnvironment? environment,
    ResourceLoader? resourceLoader,
    String? id,
  }) : _components = [...modules],
       environment = environment ?? StandardEnvironment(),
       _resources = PathMatchingResourcePatternResolver(
         resourceLoader: resourceLoader ?? DefaultResourceLoader(),
       ),
       _explicitId = id {
    this.parent = parent;
  }

  /// Name of the message source bean the context looks for.
  static const messageSourceBeanName = 'messageSource';

  /// Name of the event multicaster bean the context looks for.
  static const applicationEventMulticasterBeanName =
      'applicationEventMulticaster';

  /// Name of the lifecycle processor bean the context looks for.
  static const lifecycleProcessorBeanName = 'lifecycleProcessor';

  /// Name of the conversion service bean used for `@Value`.
  static const conversionServiceBeanName = 'conversionService';

  /// Name of the environment bean.
  static const environmentBeanName = 'environment';

  /// Name of the `TaskExecutor` bean `@Async` falls back to when there are
  /// several (Spring's
  /// `AsyncExecutionAspectSupport.DEFAULT_TASK_EXECUTOR_BEAN_NAME`).
  static const defaultTaskExecutorBeanName = 'taskExecutor';

  /// Name of the context's [BeanIntrospector] bean.
  static const beanIntrospectorBeanName = 'beanIntrospector';

  /// Introspection metadata of this context's modules (falls back to
  /// [BeanIntrospector.shared]).
  final BeanIntrospector introspector = BeanIntrospector(
    parent: BeanIntrospector.shared,
  );

  final String? _explicitId;

  @override
  late final String id =
      _explicitId ??
      'AnnotationConfigApplicationContext@'
          '${identityHashCode(this).toRadixString(16)}';

  @override
  String get displayName =>
      _explicitId == null ? id : 'AnnotationConfigApplicationContext($id)';

  /// When the last refresh started; `null` before.
  @override
  DateTime? startupDate;

  @override
  final ConfigurableEnvironment environment;

  final DefaultListableBeanFactory _factory = DefaultListableBeanFactory();
  // Modules, registrars and selectors, in registration order.
  final List<Object> _components;
  final PathMatchingResourcePatternResolver _resources;
  final _factoryPostProcessors = <BeanFactoryPostProcessor>[];
  final _listeners = <GenericApplicationListener>[];
  late final _listenerDetector = _ApplicationListenerDetector(this);
  ApplicationContext? _parent;
  ApplicationEventMulticaster? _multicaster;
  List<Object>? _earlyEvents;
  MessageSource? _messageSource;
  LifecycleProcessor? _lifecycleProcessor;
  TaskExecutor? _defaultAsyncExecutor;
  void Function()? _stopShutdownHook;
  _State _state = _State.created;

  @override
  ConfigurableListableBeanFactory get beanFactory => _factory;

  @override
  AutowireCapableBeanFactory get autowireCapableBeanFactory {
    _checkActive();
    return _factory;
  }

  @override
  ApplicationContext? get parent => _parent;

  @override
  set parent(ApplicationContext? parent) {
    _parent = parent;
    // Like Spring's getInternalParentBeanFactory: the parent's bean
    // factory, so injection sees its definitions (@Primary, @Order, ...).
    _factory.parentBeanFactory = parent is ConfigurableApplicationContext
        ? parent.beanFactory
        : parent;
    final parentEnvironment = parent?.environment;
    if (parentEnvironment is ConfigurableEnvironment) {
      environment.merge(parentEnvironment);
    }
  }

  @override
  BeanFactory? get parentBeanFactory => _parent;

  // Spring's `active` flag: set when refresh starts, cleared when refresh
  // fails or close() has finished.
  @override
  bool get isActive => switch (_state) {
    _State.refreshing || _State.active || _State.closing => true,
    _State.created || _State.failed || _State.closed => false,
  };

  @override
  bool get isClosed => _state == _State.closed;

  @override
  void register(Object component) {
    _checkNotRefreshed('register $component');
    if (component is! BeanModule &&
        component is! BeanRegistrar &&
        component is! ImportSelector &&
        component is! ImportBeanDefinitionRegistrar) {
      throw ArgumentError.value(
        component,
        'component',
        'Expected a BeanModule, BeanRegistrar, ImportSelector or '
            'ImportBeanDefinitionRegistrar',
      );
    }
    _components.add(component);
  }

  /// Registers a bean of type [T] made by [supplier] before [refresh],
  /// like Spring's `GenericApplicationContext.registerBean`; the options
  /// are those of [BeanRegistry.registerBean]. The bean is registered
  /// when the modules load, in registration order with [register]ed
  /// components.
  ///
  /// ```dart
  /// final context = AnnotationConfigApplicationContext([appBeans])
  ///   ..registerBean<Clock>((_) => SystemClock(), name: 'clock')
  ///   ..registerBean<Mailer>(
  ///     (r) => SmtpMailer(r.dependency<Clock>()),
  ///     primary: true,
  ///   )
  ///   ..refresh();
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// var context = new AnnotationConfigApplicationContext();
  /// context.registerBean("clock", Clock.class, SystemClock::new);
  /// context.registerBean(Mailer.class,
  ///     () -> new SmtpMailer(context.getBean(Clock.class)),
  ///     definition -> definition.setPrimary(true));
  /// context.refresh();
  /// ```
  void registerBean<T extends Object>(
    T Function(DependencyResolver context) supplier, {
    String? name,
    List<Type>? types,
    String scope = ScopeType.singleton,
    bool lazy = false,
    bool primary = false,
    bool fallback = false,
    bool autowireCandidate = true,
    bool defaultCandidate = true,
    int? order,
    String? description,
    List<String> aliases = const [],
    List<String> dependsOn = const [],
  }) {
    _checkNotRefreshed("register bean '${name ?? T}'");
    _components.add(
      _SingleBeanRegistrar(
        (registry) => registry.registerBean<T>(
          supplier,
          name: name,
          types: types,
          scope: scope,
          lazy: lazy,
          primary: primary,
          fallback: fallback,
          autowireCandidate: autowireCandidate,
          defaultCandidate: defaultCandidate,
          order: order,
          description: description,
          aliases: aliases,
          dependsOn: dependsOn,
        ),
      ),
    );
  }

  @override
  void addBeanFactoryPostProcessor(BeanFactoryPostProcessor processor) =>
      _factoryPostProcessors.add(processor);

  @override
  void addApplicationListener(GenericApplicationListener listener) {
    final multicaster = _multicaster;
    if (multicaster != null) {
      multicaster.addApplicationListener(listener);
    }
    _listeners.add(listener);
  }

  @override
  List<GenericApplicationListener> get applicationListeners =>
      List.unmodifiable(_listeners);

  @override
  void removeApplicationListener(GenericApplicationListener listener) {
    _multicaster?.removeApplicationListener(listener);
    _listeners.remove(listener);
  }

  @override
  ListenerRegistration addListener<E>(
    void Function(E event) listener, {
    int order = Ordered.lowestPrecedence,
  }) {
    final adapter = ApplicationListenerAdapter.of<E>(listener, order: order);
    addApplicationListener(adapter);
    return ListenerRegistration(() => removeApplicationListener(adapter));
  }

  @override
  void addProtocolResolver(ProtocolResolver resolver) {
    final loader = _resources.resourceLoader;
    if (loader is! DefaultResourceLoader) {
      throw StateError(
        'The resource loader does not accept protocol resolvers',
      );
    }
    loader.addProtocolResolver(resolver);
  }

  void _checkNotRefreshed(String action) {
    if (_state != _State.created) {
      throw StateError(
        'Cannot $action: $displayName has been refreshed already '
        '(${_state.name}). Register modules, registrars and beans before '
        'refresh(), or create a new context.',
      );
    }
  }

  void _checkActive() {
    switch (_state) {
      case _State.active || _State.refreshing || _State.closing:
        return;
      case _State.created:
        throw StateError(
          '$displayName has not been refreshed yet; call refresh() first.',
        );
      case _State.failed:
        throw StateError('$displayName failed to refresh and is unusable.');
      case _State.closed:
        throw StateError('$displayName has been closed already.');
    }
  }

  // ---------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------

  /// See [ConfigurableApplicationContext.refresh].
  @override
  void refresh() {
    _prepareRefresh();
    try {
      _refreshUntilSingletons();
      _factory.preInstantiateSingletons();
      _finishRefresh();
    } catch (_) {
      if (_cancelRefresh()) {
        _factory.destroySingletons();
        _state = _State.failed;
      }
      rethrow;
    }
  }

  /// See [ConfigurableApplicationContext.refreshAsync].
  @override
  Future<void> refreshAsync() async {
    _prepareRefresh();
    try {
      await _preloadPropertySources();
      _refreshUntilSingletons();
      await _factory.preInstantiateSingletonsAsync();
      _finishRefresh();
    } catch (_) {
      if (_cancelRefresh()) {
        await _factory.destroySingletonsAsync();
        _state = _State.failed;
      }
      rethrow;
    }
  }

  void _prepareRefresh() {
    if (_state != _State.created) {
      throw StateError('$displayName.refresh() can be called only once.');
    }
    _state = _State.refreshing;
    startupDate = DateTime.now();
    // Events published while refreshing (before the multicaster and the
    // listeners exist) are buffered and replayed in _registerListeners.
    _earlyEvents = [];
  }

  // The refresh steps before the eager singletons are created.
  void _refreshUntilSingletons() {
    environment.validateRequiredProperties();
    _prepareBeanFactory();
    _loadModules();
    postProcessBeanFactory(_factory);
    _invokeBeanFactoryPostProcessors();
    _registerBeanPostProcessors();
    _initMessageSource();
    _initEventMulticaster();
    onRefresh();
    _registerListeners();
    _factory.validateBeanGraph();
    _finishBeanFactoryInitialization();
  }

  // A failed refresh: like Spring's cancelRefresh, but the lifecycle beans
  // started so far (an earlier phase, or all of them when a
  // ContextRefreshedEvent listener failed) are stopped first. `false`
  // when a listener closed the context already (nothing left to do).
  bool _cancelRefresh() {
    _earlyEvents = null;
    if (_state == _State.closed) {
      return false;
    }
    try {
      _lifecycleProcessor?.onClose();
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Exception thrown from the LifecycleProcessor cancelling the refresh',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return true;
  }

  // Infrastructure every context offers: conversion, SpEL with
  // introspection-based access, `${...}` resolution, the *Aware callbacks,
  // context interfaces injectable by type, and the environment and
  // introspector as singletons.
  void _prepareBeanFactory() {
    _factory
      ..conversionService = environment.conversionService
      ..resourceLoader = this
      ..beanExpressionResolver ??= StandardBeanExpressionResolver(
        propertyAccessors: [IntrospectionPropertyAccessor(introspector)],
        methodResolvers: [IntrospectionMethodResolver(introspector)],
      )
      ..addEmbeddedValueResolver(environment.resolveRequiredPlaceholders)
      ..addBeanPostProcessor(ApplicationContextAwareProcessor(this))
      ..addBeanPostProcessor(_listenerDetector)
      ..addSingletonsInstantiatedCallback(_registerEventListenerMethods)
      ..registerResolvableDependency(BeanFactory, _factory)
      ..registerResolvableDependency(ListableBeanFactory, _factory)
      ..registerResolvableDependency(ConfigurableListableBeanFactory, _factory)
      ..registerResolvableDependency(AutowireCapableBeanFactory, _factory)
      ..registerResolvableDependency(ApplicationContext, this)
      ..registerResolvableDependency(ConfigurableApplicationContext, this)
      ..registerResolvableDependency(ApplicationEventPublisher, this)
      ..registerResolvableDependency(ResourceLoader, this)
      ..registerResolvableDependency(ResourcePatternResolver, this)
      ..registerSingleton(
        beanIntrospectorBeanName,
        introspector,
        types: [BeanIntrospector],
      )
      ..registerSingleton(
        environmentBeanName,
        environment,
        types: [
          Environment,
          ConfigurableEnvironment,
          PropertyResolver,
          ConfigurablePropertyResolver,
          environment.runtimeType,
        ],
      );
  }

  // Loads `@PropertySource` files; shared with _preloadPropertySources.
  late final _propertySources = PropertySourceProcessor(environment, this);

  // Reads async-only `@PropertySource` resources (Flutter assets) ahead,
  // so _loadModules can stay synchronous.
  Future<void> _preloadPropertySources() async {
    final seen = <BeanModule>{};
    Future<void> preload(BeanModule module) async {
      if (seen.add(module)) {
        for (final imported in module.imports) {
          await preload(imported);
        }
        for (final declaration in module.propertySources) {
          await _propertySources.preload(declaration.locations);
        }
      }
    }

    // Registrars and selectors add their modules while loading; those are
    // read synchronously (async-only resources belong in BeanModules).
    for (final component in _components) {
      if (component is BeanModule) {
        await preload(component);
      }
    }
  }

  // `@PropertySource` files go last, but `defaultProperties` stays the
  // lowest source (Spring Boot's
  // PropertySourceOrderingBeanFactoryPostProcessor).
  void _keepDefaultPropertiesLast() {
    final sources = environment.propertySources;
    final defaults = sources.remove(
      ConfigDataEnvironment.defaultPropertiesSourceName,
    );
    if (defaults != null) {
      sources.addLast(defaults);
    }
  }

  final _conditionEvaluations = <ConditionEvaluation>[];

  /// The outcome of every condition evaluated by the last refresh, in
  /// evaluation order (Spring Boot's `ConditionEvaluationReport`, printed
  /// by `SpringApplication` for `--debug`). A condition group (the
  /// conditions of a configuration class) appears once, under its key.
  List<ConditionEvaluation> get conditionEvaluations =>
      List.unmodifiable(_conditionEvaluations);

  // How modules load: Spring Framework 7's ConfigurationClassParser, then
  // its ConfigurationClassBeanDefinitionReader, per configuration class.
  // A class is the definitions sharing one class key (the ConditionGroup
  // key, else the `library#Class` of their source) plus the
  // ImportDeclarations naming it (`importer`, else their ConditionGroup).
  // It is a configuration class when it has `@Configuration`, `@Bean`
  // methods or imports (Spring's full and lite modes); otherwise a
  // component.
  //
  // Parse phase, per module (its BeanModule.imports first), then per class
  // in definition order; only parse-phase conditions count (plain ones and
  // parseConfiguration ConfigurationConditions; registerBean ones such as
  // Boot's @ConditionalOnBean / @ConditionalOnMissingBean are ignored):
  //  1. the module's @PropertySources (a registerBean-phase condition of
  //     the declaring class does not stop them);
  //  2. the class's imports in declaration order, when the class's
  //     parse-phase conditions match (decided once per class key): an
  //     ImportSelector runs now and the modules it selects are parsed
  //     recursively, so their classes come before the importing class
  //     (they are read first) and their property sources are visible to
  //     later parse-phase conditions (a DeferredImportSelector waits until
  //     everything else is parsed); registrars (BeanRegistrar,
  //     ImportBeanDefinitionRegistrar) are collected on the class;
  //  3. the class's definitions. One without a registerBean-phase
  //     condition registers at once, unless every class importing it is
  //     decided by the reader. One with such a condition waits for the
  //     reader when it comes from a class (a `source`: a scanned
  //     component or an imported class, which Spring parses as a lite
  //     configuration class too) or its class is a configuration class;
  //     only a hand-written definition with neither is decided in both
  //     phases at once.
  // Imports without a class (hand-written) act as a class of their own:
  // selectors before the module's classes, registrars after them. A module
  // selected again adds its importer (Spring's mergeImportedBy); loaded
  // again directly, it is no longer imported.
  //
  // Reader phase, per class in parse order (user classes before the
  // auto-configurations after them, imported classes before their
  // importer), like its TrackedConditionEvaluator: the class is decided
  // once — skipped when every class importing it was skipped, else by its
  // registerBean-phase conditions (the ConditionGroup caches the decision
  // per class key, so the class, its @Bean methods, its imports and the
  // classes it imports share it). A kept class registers its waiting
  // definitions (each @Bean method's own conditions decided now), then its
  // registrars run; a skipped class registers nothing and runs no
  // registrar. So an earlier class's @Bean or registrar bean is visible
  // to every later class's @ConditionalOnBean / @ConditionalOnMissingBean,
  // a component's as much as a configuration class's.
  void _loadModules() {
    _conditionEvaluations.clear();
    final processor = _propertySources;
    final conditionContext = _ConditionContext(this);
    final seen = <BeanModule>{};
    const parse = ConfigurationPhase.parseConfiguration;
    const registerBean = ConfigurationPhase.registerBean;
    bool matchIn(
      ConfigurationPhase phase,
      List<Condition> conditions,
      String source, [
      BeanDefinition<Object>? definition,
    ]) {
      conditionContext.definition = definition;
      return conditionsMatch(
        conditions,
        conditionContext,
        phase: phase,
        source: source,
      );
    }

    // Spring's configurationClasses, in parse order.
    final classes = <_ConfigurationClass>[];
    // The classes of each loaded module, for a later importer.
    final moduleClasses = Map<BeanModule, List<_ConfigurationClass>>.identity();
    // Spring's DeferredImportSelectorHandler: selectors collected while
    // parsing and run at the end (null while they run: then at once).
    final deferredSelectors =
        Map<DeferredImportSelector, _ConfigurationClass?>.identity();
    var deferring = true;

    // [module] (and the modules it imports) loaded again: imported by
    // [importedBy] too, or (with `null`) no longer imported.
    void importAgain(
      BeanModule module,
      _ConfigurationClass? importedBy,
      Set<BeanModule> visited,
    ) {
      if (!visited.add(module)) {
        return;
      }
      for (final imported in module.imports) {
        importAgain(imported, importedBy, visited);
      }
      for (final configurationClass
          in moduleClasses[module] ?? const <_ConfigurationClass>[]) {
        final importers = configurationClass.importedBy;
        if (importedBy == null) {
          importers.clear();
        } else if (importers.isNotEmpty && !importers.contains(importedBy)) {
          importers.add(importedBy);
        }
      }
    }

    void load(BeanModule module, _ConfigurationClass? importedBy) {
      if (!seen.add(module)) {
        importAgain(module, importedBy, {});
        return;
      }
      final moduleOwn = moduleClasses[module] = [];
      _ConfigurationClass newClass(String? key, List<Condition> conditions) {
        final configurationClass = _ConfigurationClass(
          key,
          importedBy,
          conditions,
        );
        moduleOwn.add(configurationClass);
        return configurationClass;
      }

      for (final imported in module.imports) {
        load(imported, importedBy);
      }
      for (final declaration in module.propertySources) {
        if (!matchIn(
          parse,
          declaration.conditions,
          '@PropertySource ${declaration.locations.join(', ')}',
        )) {
          continue;
        }
        processor.processPropertySource(
          declaration.locations,
          name: declaration.name,
          ignoreResourceNotFound: declaration.ignoreResourceNotFound,
          factory: declaration.factory,
          encoding: declaration.encoding,
        );
        _keepDefaultPropertiesLast();
      }
      // The module's classes, in definition order.
      final byKey = <String, _ConfigurationClass>{};
      _ConfigurationClass classFor(String key, List<Condition> conditions) =>
          byKey.putIfAbsent(key, () => newClass(key, conditions));
      for (final definition in module.definitions) {
        final (key, group) = _classKeyOf(definition);
        classFor(key, group).definitions.add(definition);
      }
      final ownImports = newClass(null, const []);
      final leadingSelectors = <(_ConfigurationClass, ImportSelector)>[];
      final source = '@Import (module ${module.name})';
      for (final declaration in module.registrars) {
        final group = declaration.conditions
            .whereType<ConditionGroup>()
            .firstOrNull;
        final key = declaration.importer ?? group?.key;
        if (key != null) {
          // Decided with its class, when the class is parsed.
          classFor(key, [?group]).imports.add(declaration);
          continue;
        }
        if (!matchIn(parse, declaration.conditions, source)) {
          continue;
        }
        final import = declaration.create();
        if (import is ImportSelector) {
          leadingSelectors.add((
            newClass(null, declaration.conditions),
            import,
          ));
        } else {
          ownImports.registrars.add((import, declaration.conditions, source));
        }
      }

      void select(_ConfigurationClass importer, ImportSelector selector) {
        if (selector is DeferredImportSelector && deferring) {
          _awareCallbacks(selector);
          deferredSelectors[selector] = importer;
        } else {
          _processImport(selector, (module) => load(module, importer));
        }
      }

      for (final (importer, selector) in leadingSelectors) {
        select(importer, selector);
      }
      // Imported only by classes the reader decides: everything waits.
      final tracked = importedBy?.decidedByReader() ?? false;
      for (final configurationClass in [...byKey.values, ownImports]) {
        // Its imports, in declaration order, if the class is parsed.
        for (final declaration in configurationClass.imports) {
          if (!matchIn(
            parse,
            declaration.conditions,
            source,
            configurationClass.definitions.firstOrNull,
          )) {
            continue;
          }
          switch (declaration.create()) {
            case final ImportSelector selector:
              select(configurationClass, selector);
            case final registrar:
              configurationClass.registrars.add((
                registrar,
                declaration.conditions,
                source,
              ));
          }
        }
        final configuration =
            configurationClass.imports.isNotEmpty ||
            configurationClass.registrars.isNotEmpty ||
            configurationClass.definitions.any(_isConfigurationDefinition);
        for (final definition in configurationClass.definitions) {
          final conditions = definition.conditions;
          final name = definition.name;
          if (!matchIn(parse, conditions, name, definition)) {
            continue;
          }
          final decidedLater = hasPhaseCondition(conditions, registerBean);
          if (tracked ||
              (decidedLater && (configuration || definition.source != null))) {
            configurationClass.waiting.add(definition);
          } else if (!decidedLater ||
              matchIn(registerBean, conditions, name, definition)) {
            // Nothing left to decide, or a hand-written definition without
            // a class: both phases now.
            _factory.registerBeanDefinition(definition);
          }
        }
        classes.add(configurationClass);
      }
      module.configurers.forEach(
        (type, configurer) => _factory.registerConfigurer(
          type,
          configurer,
          postConstruct: module.configurablePostConstruct[type],
          preDestroy: module.configurablePreDestroy[type],
        ),
      );
      introspector.registerAll(module.introspections);
    }

    for (final component in _components) {
      if (component is BeanModule) {
        load(component, null);
      } else if (component is DeferredImportSelector) {
        _awareCallbacks(component);
        deferredSelectors[component] = null;
      } else {
        _processImport(component, (module) => load(module, null));
      }
    }
    // Deferred selectors by order (stable); those they import run at once.
    deferring = false;
    for (final selector in OrderComparator.sort(deferredSelectors.keys)) {
      selector.selectImports().forEach(
        (module) => load(module, deferredSelectors[selector]),
      );
    }

    // The reader's TrackedConditionEvaluator, memoized per class (a class
    // on an import cycle counts as kept while it is being decided).
    bool isSkipped(_ConfigurationClass configurationClass) {
      if (configurationClass.skipped case final skipped?) {
        return skipped;
      }
      configurationClass.skipped = false;
      final importers = configurationClass.importedBy;
      return configurationClass.skipped =
          (importers.isNotEmpty && importers.every(isSkipped)) ||
          (hasPhaseCondition(configurationClass.conditions, registerBean) &&
              !matchIn(
                registerBean,
                configurationClass.conditions,
                configurationClass.key ?? '@Import',
                configurationClass.definitions.firstOrNull,
              ));
    }

    for (final configurationClass in classes) {
      if ((configurationClass.waiting.isEmpty &&
              configurationClass.registrars.isEmpty) ||
          isSkipped(configurationClass)) {
        continue;
      }
      for (final definition in configurationClass.waiting) {
        if (matchIn(
          registerBean,
          definition.conditions,
          definition.name,
          definition,
        )) {
          _factory.registerBeanDefinition(definition);
        }
      }
      for (final (registrar, conditions, source)
          in configurationClass.registrars) {
        if (!hasPhaseCondition(conditions, registerBean) ||
            matchIn(registerBean, conditions, source)) {
          _processImport(registrar, (module) => load(module, null));
        }
      }
    }
    conditionContext.definition = null;
  }

  // The class a definition belongs to: the key of its class's
  // ConditionGroup (with the group), else `library#Class` of its source
  // (`library#Class.method` for a @Bean method), else its factory bean or
  // its own name.
  static (String, List<Condition>) _classKeyOf(
    BeanDefinition<Object> definition,
  ) {
    final group = definition.conditions.whereType<ConditionGroup>().firstOrNull;
    if (group != null) {
      return (group.key, [group]);
    }
    if (definition.source case final source?) {
      final hash = source.indexOf('#');
      final dot = hash < 0 ? -1 : source.indexOf('.', hash);
      return (dot < 0 ? source : source.substring(0, dot), const []);
    }
    return (definition.factoryBeanName ?? definition.name, const []);
  }

  // A configuration class or `@Bean` method: what its class holds waits
  // for the reader (as does any definition with a class source).
  static bool _isConfigurationDefinition(BeanDefinition<Object> definition) =>
      definition.factoryMethodName != null ||
      definition.annotations.any((a) => a is Configuration);

  // Like Spring's ConfigurationClassParser.processImports (with
  // ParserStrategyUtils' Aware callbacks) and BeanRegistryAdapter.
  void _processImport(Object import, void Function(BeanModule) load) {
    _awareCallbacks(import);
    switch (import) {
      case final ImportSelector selector:
        selector.selectImports().forEach(load);
      case final ImportBeanDefinitionRegistrar registrar:
        registrar.registerBeanDefinitions(_factory);
      case final BeanRegistrar registrar:
        registrar.register(
          _BeanRegistryAdapter(
            _factory,
            environment,
            '${registrar.runtimeType}',
          ),
          environment,
        );
      case final _SingleBeanRegistrar registrar:
        registrar.register(
          _BeanRegistryAdapter(_factory, environment, 'registerBean'),
        );
      default:
        throw ArgumentError.value(
          import,
          'import',
          '@Import expects a BeanRegistrar, ImportSelector or '
              'ImportBeanDefinitionRegistrar (configuration classes are '
              'imported by the generator)',
        );
    }
  }

  // The Aware callbacks of an imported registrar or selector
  // (ParserStrategyUtils).
  void _awareCallbacks(Object import) {
    if (import is EnvironmentAware) {
      import.setEnvironment(environment);
    }
    if (import is BeanFactoryAware) {
      import.setBeanFactory(_factory);
    }
    if (import is ResourceLoaderAware) {
      import.setResourceLoader(this);
    }
  }

  // Spring's PostProcessorRegistrationDelegate: programmatic registry
  // post-processors, then registry post-processor beans in phases
  // (repeating the last while they register more of themselves), then
  // postProcessBeanFactory on all of those and on the programmatic regular
  // ones, finally the regular post-processor beans not handled yet, in
  // phases too.
  void _invokeBeanFactoryPostProcessors() {
    final processed = <String>{};
    final registryProcessors = <BeanDefinitionRegistryPostProcessor>[];
    final regular = <BeanFactoryPostProcessor>[];
    for (final processor in _factoryPostProcessors) {
      if (processor is BeanDefinitionRegistryPostProcessor) {
        processor.postProcessBeanDefinitionRegistry(_factory);
        registryProcessors.add(processor);
      } else {
        regular.add(processor);
      }
    }
    _postProcessorPhases<BeanDefinitionRegistryPostProcessor>(
      BeanDefinitionRegistryPostProcessor,
      processed,
      (processor) {
        processor.postProcessBeanDefinitionRegistry(_factory);
        registryProcessors.add(processor);
      },
      repeatLastPhase: true,
    );
    for (final processor in [...registryProcessors, ...regular]) {
      processor.postProcessBeanFactory(_factory);
    }
    _postProcessorPhases<BeanFactoryPostProcessor>(
      BeanFactoryPostProcessor,
      processed,
      (processor) => processor.postProcessBeanFactory(_factory),
    );
  }

  // Post-processor beans of [type] not [processed] yet, in Spring's phases:
  // `PriorityOrdered`, then `Ordered` (or `@Order`), then the rest. A
  // phase's beans are created only after the previous phase was handled
  // (so a PriorityOrdered processor already applies to the creation of
  // the Ordered ones), sorted, and passed to [handle] one by one; the
  // names are queried again before each phase, so a phase sees what the
  // previous ones registered. With [repeatLastPhase] the last phase runs
  // until no new name appears. [beforePhase] runs before each phase.
  void _postProcessorPhases<T extends Object>(
    Type type,
    Set<String> processed,
    void Function(T processor) handle, {
    bool repeatLastPhase = false,
    void Function(int phase)? beforePhase,
  }) {
    for (var phase = 0; phase <= 2; phase++) {
      beforePhase?.call(phase);
      while (true) {
        final names = [
          for (final name in _factory.getBeanNamesForType(type))
            if (!processed.contains(name) && _phaseOf(name) <= phase) name,
        ];
        processed.addAll(names);
        _sortedBeans<T>(names).forEach(handle);
        if (!repeatLastPhase || phase < 2 || names.isEmpty) {
          break;
        }
      }
    }
  }

  // 0: PriorityOrdered, 1: Ordered or @Order, 2: the rest.
  int _phaseOf(String name) {
    if (_factory.isTypeMatch(name, PriorityOrdered)) {
      return 0;
    }
    // Registered singletons have no definition.
    final order = _factory.containsBeanDefinition(name)
        ? _factory.getBeanDefinition(name).order
        : null;
    return _factory.isTypeMatch(name, Ordered) || order != null ? 1 : 2;
  }

  /// Beans [names] as [T], `PriorityOrdered` first, then by order.
  List<T> _sortedBeans<T extends Object>(List<String> names) {
    final beans = <T, int?>{
      for (final name in names)
        _factory.getBeanByName(name) as T: _factory.containsBeanDefinition(name)
            ? DefaultListableBeanFactory.annotatedOrderOf(
                _factory.getBeanDefinition(name),
              )
            : null,
    };
    return OrderComparator.sort(beans.keys, (bean) => beans[bean]);
  }

  void _registerBeanPostProcessors() {
    // AOP is on as soon as an aspect or advisor exists (here or in an
    // ancestor); its proxy creator is the first Ordered processor (Spring:
    // HIGHEST_PRECEDENCE), so later processors see the proxies.
    final usesAop = AspectAutoProxyCreator.isRequiredFor(_factory);
    // Like Spring's BeanPostProcessorChecker: counts the processors still
    // to come, to report beans created before all of them exist (only
    // needed when there are post-processor beans to create).
    final names = _factory.getBeanNamesForType(BeanPostProcessor);
    if (names.isNotEmpty) {
      _factory.addBeanPostProcessor(
        _BeanPostProcessorChecker(
          this,
          names,
          _factory.beanPostProcessorCount +
              2 +
              names.length +
              (usesAop ? 1 : 0),
        ),
      );
    }
    // `@PostConstruct` runs at the place of Spring's
    // CommonAnnotationBeanPostProcessor: among the PriorityOrdered
    // processors by its order (an internal bean, so before user processors
    // of the same order), before the Ordered and plain ones.
    final common = CommonAnnotationBeanPostProcessor();
    var commonAdded = false;
    void addCommon() {
      if (!commonAdded) {
        commonAdded = true;
        _factory.addBeanPostProcessor(common);
      }
    }

    _postProcessorPhases<BeanPostProcessor>(
      BeanPostProcessor,
      <String>{},
      (processor) {
        final beforeCommon = switch (processor) {
          PriorityOrdered(:final order) => order <= common.order,
          _ => false,
        };
        if (!beforeCommon) {
          addCommon();
        }
        _factory.addBeanPostProcessor(processor);
      },
      beforePhase: (phase) {
        if (phase == 1) {
          addCommon();
          if (usesAop) {
            _factory.addBeanPostProcessor(AspectAutoProxyCreator(_factory));
          }
        }
      },
    );
    // Last, so it sees the proxies (like Spring re-registering its
    // ApplicationListenerDetector at the end).
    _factory.addBeanPostProcessor(_listenerDetector);
  }

  // A user `messageSource` bean gets the parent's message source as its
  // parent (unless it has one); otherwise an empty DelegatingMessageSource
  // forwards to it.
  void _initMessageSource() {
    if (_factory.containsLocalBean(messageSourceBeanName)) {
      final source =
          _factory.getBeanByName(messageSourceBeanName) as MessageSource;
      if (source is HierarchicalMessageSource &&
          source.parentMessageSource == null &&
          _parent != null) {
        source.parentMessageSource = _internalParentMessageSource;
      }
      _messageSource = source;
      return;
    }
    final delegating = DelegatingMessageSource(_internalParentMessageSource);
    _messageSource = delegating;
    _factory.registerSingleton(
      messageSourceBeanName,
      delegating,
      types: [MessageSource, HierarchicalMessageSource],
    );
  }

  // Like Spring's getInternalParentMessageSource: the message source of a
  // parent of this class (so lookups do not go through the parent
  // context), else the parent context itself.
  MessageSource? get _internalParentMessageSource => switch (_parent) {
    final AnnotationConfigApplicationContext parent =>
      parent._messageSource ?? parent,
    final parent => parent,
  };

  // A user `applicationEventMulticaster` bean wins over the default.
  void _initEventMulticaster() {
    if (_factory.containsLocalBean(applicationEventMulticasterBeanName)) {
      _multicaster = _factory.getBeanByName(
        applicationEventMulticasterBeanName,
      ) as ApplicationEventMulticaster;
      return;
    }
    final multicaster = SimpleApplicationEventMulticaster();
    _multicaster = multicaster;
    _factory.registerSingleton(
      applicationEventMulticasterBeanName,
      multicaster,
      types: [ApplicationEventMulticaster],
    );
  }

  // Programmatic and detected listeners, listener objects registered as
  // singletons, plus the `ApplicationListener` beans (one adapter each,
  // fetching the bean on each event, like the listener bean names of
  // Spring's multicaster); then the early events are replayed, like
  // Spring's registerListeners, so events published while the singletons
  // are created go straight to the listeners. `@EventListener` methods
  // come later, in [_registerEventListenerMethods].
  void _registerListeners() {
    final multicaster = _multicaster!;
    for (final name in _factory.singletonNames) {
      if (_factory.containsBeanDefinition(name)) {
        continue;
      }
      if (_factory.getSingleton(name) case final GenericApplicationListener l) {
        addApplicationListener(l);
      }
    }
    _listeners.forEach(multicaster.addApplicationListener);
    for (final name in _factory.beanDefinitionNames) {
      final definition = _factory.getBeanDefinition(name);
      for (final method in definition.eventListeners) {
        if (_isListenerInterface(method)) {
          multicaster.addApplicationListener(
            _BeanMethodListener(this, name, method),
          );
        }
      }
      // A lazy GenericApplicationListener / SmartApplicationListener bean
      // is only known by name until the first event creates it (Spring's
      // listener bean names: it cannot decide without the instance).
      if (definition.lazy &&
          definition.isSingleton &&
          !definition.eventListeners.any(_isListenerInterface) &&
          _factory.getSingleton(name) == null &&
          _factory.isTypeMatch(name, GenericApplicationListener)) {
        multicaster.addApplicationListener(_LazyListenerBean(this, name));
      }
    }
    // Clear the buffer first so the replayed events are really dispatched.
    // Replayed locally only: the parent already received them when they
    // were published.
    final events = _earlyEvents!;
    _earlyEvents = null;
    events.forEach(multicaster.multicastEvent);
  }

  // One adapter per `@EventListener` method, registered once the eager
  // singletons exist and before the SmartInitializingSingleton callbacks,
  // like Spring's EventListenerMethodProcessor.afterSingletonsInstantiated:
  // an event published while the singletons are created (from a
  // `@PostConstruct`, say) does not reach `@EventListener` methods, so it
  // never needs a listener bean that is still being created.
  void _registerEventListenerMethods() {
    final multicaster = _multicaster;
    if (multicaster == null) {
      return;
    }
    for (final name in _factory.beanDefinitionNames) {
      final definition = _factory.getBeanDefinition(name);
      for (final method in definition.eventListeners) {
        if (!_isListenerInterface(method)) {
          multicaster.addApplicationListener(
            _BeanMethodListener(this, name, method),
          );
        }
      }
    }
  }

  // The `onApplicationEvent` of an `ApplicationListener` bean (wired by the
  // generator like an `@EventListener` method).
  static bool _isListenerInterface(EventListenerMethod<Object> method) =>
      method.id.endsWith('.onApplicationEvent');

  // A `conversionService` bean (here or in an ancestor, like Spring's
  // containsBean) replaces the environment's service for `@Value`
  // conversion; then the configuration is frozen (the caller creates the
  // eager singletons).
  void _finishBeanFactoryInitialization() {
    if (_factory.containsBean(conversionServiceBeanName) &&
        _factory.isTypeMatch(conversionServiceBeanName, ConversionService)) {
      _factory.conversionService = _factory.getBeanByName(
        conversionServiceBeanName,
      ) as ConversionService;
    }
    _factory.freezeConfiguration();
  }

  void _finishRefresh() {
    // Like Spring's initLifecycleProcessor: a `lifecycleProcessor` bean, or
    // a DefaultLifecycleProcessor registered under that name.
    final LifecycleProcessor processor;
    if (_factory.containsLocalBean(lifecycleProcessorBeanName)) {
      processor = _factory.getBeanByName(
        lifecycleProcessorBeanName,
      ) as LifecycleProcessor;
    } else {
      processor = DefaultLifecycleProcessor(_factory);
      _factory.registerSingleton(
        lifecycleProcessorBeanName,
        processor,
        types: [LifecycleProcessor, DefaultLifecycleProcessor],
      );
    }
    _lifecycleProcessor = processor;
    processor.onRefresh();
    publishEvent(ContextRefreshedEvent(this));
    // A listener of ContextRefreshedEvent may have closed the context.
    if (_state == _State.refreshing) {
      _state = _State.active;
    }
  }

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// Starts all [Lifecycle] beans and publishes `ContextStartedEvent`.
  @override
  void start() {
    _checkActive();
    _lifecycleProcessor!.start();
    publishEvent(ContextStartedEvent(this));
  }

  /// Stops running [Lifecycle] beans and publishes `ContextStoppedEvent`.
  @override
  void stop() {
    _checkActive();
    _lifecycleProcessor!.stop();
    publishEvent(ContextStoppedEvent(this));
  }

  /// See [ConfigurableApplicationContext.restart].
  @override
  void restart() {
    _checkActive();
    _lifecycleProcessor!.onRestart();
    publishEvent(ContextRestartedEvent(this));
  }

  /// See [ConfigurableApplicationContext.pause].
  @override
  void pause() {
    _checkActive();
    _lifecycleProcessor!.onPause();
    publishEvent(ContextPausedEvent(this));
  }

  /// See [ConfigurableApplicationContext.pauseAsync].
  @override
  Future<void> pauseAsync() async {
    _checkActive();
    await _lifecycleProcessor!.onPauseAsync();
    publishEvent(ContextPausedEvent(this));
  }

  @override
  bool get isRunning => _lifecycleProcessor?.isRunning ?? false;

  /// See [ConfigurableApplicationContext.registerShutdownHook].
  @override
  void registerShutdownHook() {
    if (_stopShutdownHook != null) {
      return;
    }
    final (:watch, :exit) = shutdownHookPlatform;
    // closeAsync, so asynchronous SmartLifecycle stops and destroy
    // callbacks finish before the process ends (Spring's hook thread
    // blocks on them).
    _stopShutdownHook = watch(
      (code) => unawaited(closeAsync().whenComplete(() => exit(code))),
    );
  }

  /// See [ConfigurableApplicationContext.close]; a no-op unless active
  /// (like Spring, it also works while refreshing, e.g. from a
  /// `ContextRefreshedEvent` listener).
  @override
  void close() {
    if (!_beginClose()) {
      return;
    }
    try {
      _lifecycleProcessor?.onClose();
    } on Object catch (error, stackTrace) {
      _lifecycleCloseFailed(error, stackTrace);
    }
    _factory.destroySingletons();
    _finishClose();
  }

  /// Template method called by [refresh] after the modules are loaded
  /// (every bean definition is registered, no bean is created yet) and
  /// before the bean factory post-processors run, like Spring's
  /// `postProcessBeanFactory`. Override in a subclass to register
  /// definitions, singletons or post-processors; not meant to be called
  /// directly. Does nothing by default.
  ///
  /// ```dart
  /// class MyContext extends AnnotationConfigApplicationContext {
  ///   MyContext(super.modules);
  ///
  ///   @override
  ///   void postProcessBeanFactory(ConfigurableListableBeanFactory factory) =>
  ///       factory.registerSingleton('clock', SystemClock());
  /// }
  /// ```
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}

  /// Template method called by [refresh] once the message source and the
  /// event multicaster exist, before the listeners are registered and the
  /// eager singletons are created, like Spring's `onRefresh`. Override in
  /// a subclass for context-specific refresh work; not meant to be called
  /// directly. Does nothing by default.
  void onRefresh() {}

  /// Template method called by [close] and [closeAsync] last, after the
  /// singletons are destroyed and before the context counts as closed,
  /// like Spring's `onClose`. Override in a subclass for context-specific
  /// shutdown work; not meant to be called directly. Does nothing by
  /// default.
  void onClose() {}

  /// See [ConfigurableApplicationContext.closeAsync].
  @override
  Future<void> closeAsync() async {
    if (!_beginClose()) {
      return;
    }
    try {
      await _lifecycleProcessor?.onCloseAsync();
    } on Object catch (error, stackTrace) {
      _lifecycleCloseFailed(error, stackTrace);
    }
    await _factory.destroySingletonsAsync();
    _finishClose();
  }

  // Like Spring's doClose: each step is guarded so a failing listener or
  // lifecycle bean neither stops the shutdown nor escapes from close().
  // The state changes first, so a close() from a listener is a no-op.
  // `false` when the context is not active (nothing to close).
  bool _beginClose() {
    if (_state != _State.active && _state != _State.refreshing) {
      return false;
    }
    _state = _State.closing;
    // Like Spring removing the JVM shutdown hook on an explicit close.
    _stopShutdownHook?.call();
    _stopShutdownHook = null;
    try {
      publishEvent(ContextClosedEvent(this));
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Exception thrown from a listener handling ContextClosedEvent',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return true;
  }

  void _lifecycleCloseFailed(Object error, StackTrace stackTrace) =>
      _log.warning(
        'Exception thrown from the LifecycleProcessor on context close',
        error: error,
        stackTrace: stackTrace,
      );

  void _finishClose() {
    try {
      onClose();
    } finally {
      _multicaster?.removeAllListeners();
      _state = _State.closed;
    }
  }

  // ---------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------

  /// Dispatches [event] to matching listeners synchronously, then to the
  /// parent context. Non-[ApplicationEvent] objects are wrapped in a
  /// [PayloadApplicationEvent] of their static type [T] (Spring uses the
  /// runtime type), so `addListener<PayloadApplicationEvent<OrderPlaced>>`
  /// sees `publishEvent(OrderPlaced(...))`. Like Spring 7, before [refresh],
  /// after a failed refresh and after [close] the event is not delivered
  /// locally (only to the parent).
  ///
  /// ```dart
  /// context.publishEvent(OrderPlaced(1, 250)); // payload event
  /// context.publishEvent(OrderShipped(this, 1)); // ApplicationEvent
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.publishEvent(new OrderPlaced(1, 250));
  /// ```
  @override
  void publishEvent<T extends Object>(T event) {
    final applicationEvent = event is ApplicationEvent
        ? event
        : PayloadApplicationEvent<T>(this, event);
    final early = _earlyEvents;
    if (early != null) {
      early.add(applicationEvent);
    } else if (_state != _State.created && _state != _State.failed) {
      // After close() the multicaster has no listeners left.
      _multicaster?.multicastEvent(applicationEvent);
    }
    // The parent gets the original object so it wraps it itself.
    _parent?.publishEvent(event);
  }

  // The error of an asynchronous `@EventListener` result: the
  // multicaster's error handler when it has one, else logged (Spring's
  // handleAsyncError).
  void _asyncListenerFailed(Object error, StackTrace stackTrace) {
    if (_multicaster case SimpleApplicationEventMulticaster(
      errorHandler: final handler?,
    )) {
      handler(error, stackTrace);
      return;
    }
    _log.error(
      'Unexpected error occurred in asynchronous listener',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // The executor of an `@Async` listener (Spring's
  // AsyncExecutionAspectSupport.determineAsyncExecutor): the named bean,
  // else the only (or primary) TaskExecutor, else the one named
  // `taskExecutor`, else a SimpleAsyncTaskExecutor of the context. `null`
  // while the context has no TaskExecutor bean at all: like Spring
  // without `@EnableAsync`, `@Async` is ignored.
  TaskExecutor? _asyncExecutor(
    Async async,
    EventListenerMethod<Object> method,
  ) {
    if (async.value case final name?) {
      if (!_factory.containsBean(name) ||
          !_factory.isTypeMatch(name, TaskExecutor)) {
        throw StateError(
          "No TaskExecutor bean named '$name' for @Async on "
          '${method.id}; declare one or remove the qualifier.',
        );
      }
      return _factory.getBeanByName(name) as TaskExecutor;
    }
    if (!_factory.containsBeanOfType(TaskExecutor)) {
      return null;
    }
    return _defaultAsyncExecutor ??=
        _factory.getBeanProvider<TaskExecutor>().getIfUnique() ??
        (_factory.containsBean(defaultTaskExecutorBeanName) &&
                _factory.isTypeMatch(defaultTaskExecutorBeanName, TaskExecutor)
            ? _factory.getBeanByName(defaultTaskExecutorBeanName)
                  as TaskExecutor
            : SimpleAsyncTaskExecutor(errorHandler: _asyncListenerFailed));
  }

  // ---------------------------------------------------------------------
  // Messages and resources
  // ---------------------------------------------------------------------

  MessageSource get _messages {
    _checkActive();
    return _messageSource!;
  }

  /// Resolves [code] through the context's message source (the
  /// `messageSource` bean, then the parent context).
  ///
  /// ```dart
  /// context.getMessage('greeting', args: ['Ada'], locale: 'ru_RU');
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.getMessage("greeting", new Object[] {"Ada"},
  ///     Locale.of("ru", "RU"));
  /// ```
  @override
  String getMessage(
    String code, {
    List<Object?> args = const [],
    String? defaultMessage,
    String? locale,
  }) => _messages.getMessage(
    code,
    args: args,
    defaultMessage: defaultMessage,
    locale: locale,
  );

  @override
  String getMessageFromResolvable(
    MessageSourceResolvable resolvable, {
    String? locale,
  }) => _messages.getMessageFromResolvable(resolvable, locale: locale);

  @override
  Resource getResource(String location) => _resources.getResource(location);

  @override
  List<Resource> getResources(String locationPattern) =>
      _resources.getResources(locationPattern);

  // ---------------------------------------------------------------------
  // Bean factory delegation
  // ---------------------------------------------------------------------

  @override
  T getBean<T extends Object>({String? qualifier}) {
    _checkActive();
    return _factory.getBean<T>(qualifier: qualifier);
  }

  @override
  T? findBean<T extends Object>({String? qualifier}) {
    _checkActive();
    return _factory.findBean<T>(qualifier: qualifier);
  }

  @override
  Object getBeanByName(String name) {
    _checkActive();
    return _factory.getBeanByName(name);
  }

  @override
  ObjectProvider<T> getBeanProvider<T extends Object>({String? qualifier}) {
    _checkActive();
    return _factory.getBeanProvider<T>(qualifier: qualifier);
  }

  @override
  bool containsBean(String name) => _factory.containsBean(name);

  @override
  bool containsLocalBean(String name) => _factory.containsLocalBean(name);

  @override
  bool containsBeanOfType(
    Type type, {
    String? qualifier,
    bool includeAncestors = true,
  }) => _factory.containsBeanOfType(
    type,
    qualifier: qualifier,
    includeAncestors: includeAncestors,
  );

  @override
  bool isSingleton(String name) {
    _checkActive();
    return _factory.isSingleton(name);
  }

  @override
  bool isPrototype(String name) {
    _checkActive();
    return _factory.isPrototype(name);
  }

  @override
  Type? getType(String name) => _factory.getType(name);

  @override
  bool isTypeMatch(String name, Type type) => _factory.isTypeMatch(name, type);

  @override
  List<String> getAliases(String name) => _factory.getAliases(name);

  @override
  bool containsBeanDefinition(String name) =>
      _factory.containsBeanDefinition(name);

  @override
  int get beanDefinitionCount => _factory.beanDefinitionCount;

  @override
  List<String> get beanDefinitionNames => _factory.beanDefinitionNames;

  @override
  List<String> getBeanNamesForType(
    Type type, {
    bool includeNonSingletons = true,
  }) => _factory.getBeanNamesForType(
    type,
    includeNonSingletons: includeNonSingletons,
  );

  @override
  Map<String, T> getBeansOfType<T extends Object>({
    bool includeNonSingletons = true,
  }) {
    _checkActive();
    return _factory.getBeansOfType<T>(
      includeNonSingletons: includeNonSingletons,
    );
  }

  @override
  List<T> getSortedBeans<T extends Object>({String? qualifier}) {
    _checkActive();
    return _factory.getSortedBeans<T>(qualifier: qualifier);
  }

  @override
  List<String> getBeanNamesForAnnotation<A extends Object>() =>
      _factory.getBeanNamesForAnnotation<A>();

  @override
  Map<String, Object> getBeansWithAnnotation<A extends Object>() {
    _checkActive();
    return _factory.getBeansWithAnnotation<A>();
  }

  @override
  A? findAnnotationOnBean<A extends Object>(String beanName) =>
      _factory.findAnnotationOnBean<A>(beanName);

  @override
  String toString() => displayName;
}

/// Invokes an `@EventListener` method of a bean, fetching the bean when an
/// event arrives (so lazy and prototype beans work).
final class _BeanMethodListener implements GenericApplicationListener, Ordered {
  _BeanMethodListener(this._context, this._beanName, this._method);

  final AnnotationConfigApplicationContext _context;
  final String _beanName;
  final EventListenerMethod<Object> _method;

  // An ApplicationListener bean that is Ordered is ordered by its order
  // (before its @Order), like Spring's AnnotationAwareOrderComparator; an
  // @EventListener method only by its own @Order. The bean is not created
  // for it (a lazy listener not created yet uses its @Order).
  @override
  int get order {
    final listenerBean =
        AnnotationConfigApplicationContext._isListenerInterface(_method);
    if (_context._factory.getSingleton(_beanName) case final Ordered bean
        when bean is ApplicationListener<Object> && listenerBean) {
      return bean.order;
    }
    // A listener bean's jakarta @Priority counts after its @Order.
    final factory = _context._factory;
    final priority = listenerBean && factory.containsBeanDefinition(_beanName)
        ? DefaultListableBeanFactory.annotatedOrderOf(
            factory.getBeanDefinition(_beanName),
          )
        : null;
    return _method.order ?? priority ?? Ordered.lowestPrecedence;
  }

  @override
  bool supportsEvent(Object event) => _method.supports(event);

  // Like Spring's ApplicationListenerMethodAdapter.processEvent: the
  // condition is checked here, inside the multicaster's error handling;
  // an `@Async` method then runs on its executor.
  @override
  void onApplicationEvent(Object event) {
    if (!_method.shouldHandle(event)) {
      return;
    }
    if (_method.async case final async?) {
      if (_context._asyncExecutor(async, _method) case final executor?) {
        executor.execute(() => _invokeAsync(event));
        return;
      }
    }
    final result = _method.invoke(_target(), event);
    if (result is Future<Object?>) {
      // Like Spring's CompletionStage handling: the value is published
      // when it arrives, a failure goes to the error handler.
      unawaited(
        result.then(_publishResult, onError: _context._asyncListenerFailed),
      );
      return;
    }
    _publishResult(result);
  }

  // An `@Async` invocation: a failure goes to the error handler (Spring's
  // AsyncUncaughtExceptionHandler), a result is published when it arrives.
  Future<void> _invokeAsync(Object event) async {
    try {
      var result = _method.invoke(_target(), event);
      if (result is Future<Object?>) {
        result = await result;
      }
      _publishResult(result);
    } on Object catch (error, stackTrace) {
      _context._asyncListenerFailed(error, stackTrace);
    }
  }

  // The bean declaring the method: for a FactoryBean, the factory itself
  // (`&name`), not its product.
  Object _target() {
    final factory = _context._factory;
    final isFactoryBean =
        factory.containsBeanDefinition(_beanName) &&
        factory.getBeanDefinition(_beanName).isFactoryBean;
    return factory.getBeanByName(
      isFactoryBean ? '${BeanFactory.factoryBeanPrefix}$_beanName' : _beanName,
    );
  }

  // Non-null results are published, an Iterable element by element, as
  // the method's declared result type when known.
  void _publishResult(Object? result) {
    if (result == null) {
      return;
    }
    void publish(Object item) => switch (_method.resultType) {
      final type? => type.publish(_context, item),
      null => _context.publishEvent(item),
    };
    if (result is Iterable<Object?>) {
      for (final item in result) {
        if (item != null) {
          publish(item);
        }
      }
    } else {
      publish(result);
    }
  }

  @override
  String toString() => '_BeanMethodListener($_beanName, ${_method.id})';
}

/// A lazy [GenericApplicationListener] bean known by name, like a listener
/// bean name in Spring's multicaster: the first event creates the bean
/// (whose detector registration then receives the later events), asks it
/// whether it handles the event, and retires this placeholder.
final class _LazyListenerBean implements GenericApplicationListener, Ordered {
  _LazyListenerBean(this._context, this._beanName);

  final AnnotationConfigApplicationContext _context;
  final String _beanName;
  late GenericApplicationListener _bean;

  // Its @Order / @Priority: the bean is not created to ask it.
  @override
  int get order {
    final factory = _context._factory;
    return (factory.containsBeanDefinition(_beanName)
            ? DefaultListableBeanFactory.annotatedOrderOf(
                factory.getBeanDefinition(_beanName),
              )
            : null) ??
        Ordered.lowestPrecedence;
  }

  @override
  bool supportsEvent(Object event) {
    // The multicaster dispatches a copy, so leaving it now is safe.
    _context._multicaster?.removeApplicationListener(this);
    final factory = _context._factory;
    if (factory.getSingleton(_beanName) != null) {
      // Created meanwhile: registered by the detector already.
      return false;
    }
    final bean = factory.getBeanByName(_beanName) as GenericApplicationListener;
    _bean = bean;
    return bean.supportsEvent(event);
  }

  @override
  void onApplicationEvent(Object event) => _bean.onApplicationEvent(event);

  @override
  String toString() => '_LazyListenerBean($_beanName)';
}

/// Registers listener beans with the context once they are created, like
/// Spring's `ApplicationListenerDetector`: a singleton that is a
/// [GenericApplicationListener] (an `ApplicationListener<E>` bean is wired
/// by the generator instead, through its `onApplicationEvent` method) is
/// added when initialized and removed when destroyed; a non-singleton one
/// is not reachable and gets a warning.
final class _ApplicationListenerDetector
    extends DestructionAwareBeanPostProcessor {
  _ApplicationListenerDetector(this._context);

  final AnnotationConfigApplicationContext _context;

  // ApplicationListener beans (wired as adapters by bean name) removed
  // from the multicaster when destroyed; added back when created again.
  final _detached = <String>{};

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (bean is! GenericApplicationListener &&
        bean is! ApplicationListener<Object>) {
      return bean;
    }
    final factory = _context._factory;
    final definition = factory.containsBeanDefinition(beanName)
        ? factory.getBeanDefinition(beanName)
        : null;
    if (definition != null &&
        definition.eventListeners.any(
          AnnotationConfigApplicationContext._isListenerInterface,
        )) {
      if (_detached.remove(beanName) && definition.isSingleton) {
        for (final method in definition.eventListeners) {
          if (AnnotationConfigApplicationContext._isListenerInterface(method)) {
            _context._multicaster?.addApplicationListener(
              _BeanMethodListener(_context, beanName, method),
            );
          }
        }
      }
      return bean;
    }
    if (bean is! GenericApplicationListener) {
      return bean;
    }
    if (definition == null || definition.isSingleton) {
      _context.addApplicationListener(bean);
    } else {
      _log.warning(
        "Bean '$beanName' implements GenericApplicationListener but is not "
        'reachable for event multicasting by its containing '
        'ApplicationContext because it does not have singleton scope.',
      );
    }
    return bean;
  }

  @override
  bool requiresDestruction(Object bean) =>
      bean is GenericApplicationListener || bean is ApplicationListener<Object>;

  // Like Spring's ApplicationListenerDetector: a destroyed listener bean
  // (also one wired by name, e.g. after destroySingleton or the end of
  // its scope) no longer receives events; it would be created again.
  @override
  void postProcessBeforeDestruction(Object bean, String beanName) {
    if (bean is GenericApplicationListener) {
      _context.removeApplicationListener(bean);
    }
    var removed = false;
    _context._multicaster?.removeApplicationListeners(
      (listener) =>
          listener is _LazyListenerBean && listener._beanName == beanName,
    );
    _context._multicaster?.removeApplicationListeners((listener) {
      final match =
          listener is _BeanMethodListener &&
          listener._beanName == beanName &&
          AnnotationConfigApplicationContext._isListenerInterface(
            listener._method,
          );
      removed |= match;
      return match;
    });
    if (removed) {
      _detached.add(beanName);
    }
  }
}

// A configuration class while modules load (Spring's ConfigurationClass):
// its definitions, the imports it declares, and the classes importing it.
final class _ConfigurationClass {
  _ConfigurationClass(
    this.key,
    _ConfigurationClass? importedBy,
    this.conditions,
  ) : importedBy = [?importedBy];

  // The class key; `null` for imports without a class.
  final String? key;

  // The classes whose selectors imported this one's module (Spring's
  // importedBy); empty when it was not imported.
  final List<_ConfigurationClass> importedBy;

  // The class's ConditionGroup (or a classless import's conditions).
  final List<Condition> conditions;

  // Whether the reader decides if this class (and what it imports) is
  // registered: it has a registerBean-phase condition, or every class
  // importing it is decided by the reader.
  // [path] guards against import cycles.
  bool decidedByReader([Set<_ConfigurationClass>? path]) {
    if (hasPhaseCondition(conditions, ConfigurationPhase.registerBean)) {
      return true;
    }
    final importers = path ?? {};
    if (importedBy.isEmpty || !importers.add(this)) {
      return false;
    }
    try {
      return importedBy.every(
        (importer) => importer.decidedByReader(importers),
      );
    } finally {
      importers.remove(this);
    }
  }

  final definitions = <BeanDefinition<Object>>[];

  // The @Imports naming this class.
  final imports = <ImportDeclaration>[];

  // Registrars with their declaration's conditions and source.
  final registrars = <(Object, List<Condition>, String)>[];

  // Definitions registered (or not) by the reader.
  final waiting = <BeanDefinition<Object>>[];

  // The reader's decision, once made.
  bool? skipped;
}

/// A bean registered by `AnnotationConfigApplicationContext.registerBean`.
final class _SingleBeanRegistrar {
  _SingleBeanRegistrar(this.register);

  final void Function(BeanRegistry registry) register;
}

/// The [BeanRegistry] handed to a [BeanRegistrar], like Spring 7's
/// `BeanRegistryAdapter`.
final class _BeanRegistryAdapter implements BeanRegistry {
  _BeanRegistryAdapter(this._factory, this._environment, this._origin);

  final DefaultListableBeanFactory _factory;
  final Environment _environment;

  // The registrar's type, or `registerBean` for the context's.
  final String _origin;

  // Each registration is its own source: two beans of the same name are
  // an override (or a BeanDefinitionOverrideException), never "the same
  // module registered twice".
  static var _registrations = 0;

  @override
  String registerBean<T extends Object>(
    T Function(DependencyResolver context) supplier, {
    String? name,
    List<Type>? types,
    String scope = ScopeType.singleton,
    bool lazy = false,
    bool primary = false,
    bool fallback = false,
    bool autowireCandidate = true,
    bool defaultCandidate = true,
    int? order,
    String? description,
    List<String> aliases = const [],
    List<String> dependsOn = const [],
  }) {
    final beanName = name ?? _uniqueName('$T');
    _factory.registerBeanDefinition(
      BeanDefinition<T>(
        name: beanName,
        create: supplier,
        types: types,
        scope: scope,
        lazy: lazy,
        primary: primary,
        fallback: fallback,
        autowireCandidate: autowireCandidate,
        defaultCandidate: defaultCandidate,
        order: order,
        description: description,
        aliases: aliases,
        dependsOn: dependsOn,
        source: 'BeanRegistrar $_origin#${_registrations++}',
      ),
    );
    return beanName;
  }

  // Spring's BeanDefinitionReaderUtils.uniqueBeanName: `Type#0`, `Type#1`.
  String _uniqueName(String base) {
    for (var counter = 0; ; counter++) {
      final candidate = '$base#$counter';
      if (!_factory.containsBeanDefinition(candidate) &&
          !_factory.containsBean(candidate)) {
        return candidate;
      }
    }
  }

  @override
  void registerAlias(String name, String alias) =>
      _factory.registerAlias(name, alias);

  @override
  void register(BeanRegistrar registrar) =>
      registrar.register(this, _environment);
}

/// Spring's `BeanPostProcessorChecker`: logs (info) a bean created while
/// the post-processors are registered, since the processors registered
/// after it never see it (no AOP proxy, for example) — usually a
/// post-processor depending on a regular bean.
final class _BeanPostProcessorChecker extends BeanPostProcessor {
  _BeanPostProcessorChecker(
    this._context,
    this._postProcessorNames,
    this._targetCount,
  );

  final AnnotationConfigApplicationContext _context;
  final List<String> _postProcessorNames;
  final int _targetCount;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    final factory = _context._factory;
    if (bean is BeanPostProcessor ||
        bean is Advisor ||
        factory.beanPostProcessorCount >= _targetCount ||
        !factory.containsBeanDefinition(beanName) ||
        factory.getBeanDefinition(beanName).aspect != null ||
        !_log.isEnabled(SpringLogLevel.info)) {
      return bean;
    }
    final creating = _postProcessorNames
        .where(factory.isCurrentlyInCreation)
        .firstOrNull;
    _log.info(
      "Bean '$beanName' of type [${bean.runtimeType}] is not eligible for "
      'getting processed by all BeanPostProcessors (for example: not '
      'eligible for auto-proxying).'
      '${creating == null ? '' : ' Is this bean getting eagerly injected '
                'into a currently created BeanPostProcessor [$creating]? '
                'Check the corresponding BeanPostProcessor declaration and '
                'its dependencies (an ObjectProvider or @Lazy dependency '
                'defers the creation).'}',
    );
    return bean;
  }
}

/// The [ConditionContext] handed to conditions while modules load.
final class _ConditionContext
    implements
        ConditionContext,
        ConditionEvaluationCache,
        ConditionEvaluationRecorder {
  _ConditionContext(this._context);

  final AnnotationConfigApplicationContext _context;
  final _results = <String, bool>{};

  // Outcomes recorded so far: a condition evaluated again with the same
  // outcome (a plain condition of a class in both phases) is reported
  // once, like Boot's ConditionAndOutcomes.
  final _recorded = <(String, Condition, bool)>{};

  @override
  void recordCondition(String source, Condition condition, bool matched) {
    if (_recorded.add((source, condition, matched))) {
      _context._conditionEvaluations.add(
        ConditionEvaluation(source, condition, matched: matched),
      );
    }
  }

  @override
  BeanDefinition<Object>? definition;

  @override
  bool evaluateOnce(String key, bool Function() evaluate) =>
      _results[key] ??= evaluate();

  @override
  ConfigurableListableBeanFactory get beanFactory => _context._factory;

  @override
  Environment get environment => _context.environment;

  @override
  BeanDefinitionRegistry get registry => _context._factory;

  @override
  ResourceLoader get resourceLoader => _context;
}

const _log = SpringLog('spring_core_dart.context');
