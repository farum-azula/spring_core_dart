import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/auto_proxy_creator.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/default_listable_bean_factory.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/object_provider.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/context/bean_module.dart';
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
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/env/config/property_source_factory.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';
import 'package:spring_core_dart/src/core/io/resource_pattern_resolver.dart';
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

  /// Unique id of the context (defaults to `application`).
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

  /// Sets the parent context; its environment is merged into this one.
  set parent(ApplicationContext? parent);

  /// The underlying bean factory (available before refresh).
  ConfigurableListableBeanFactory get beanFactory;

  /// Adds a module before [refresh].
  void register(BeanModule module);

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
  /// `StateError`), also after a failed refresh.
  void refresh();

  /// Publishes `ContextClosedEvent`, stops lifecycle beans and destroys
  /// singletons. Safe to call more than once.
  ///
  /// ```dart
  /// final context = ApplicationContext.run([appBeans]);
  /// ProcessSignal.sigint.watch().listen((_) => context.close());
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// context.close(); // or context.registerShutdownHook();
  /// ```
  void close();

  /// Whether the context is refreshed and not closed.
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
  /// the id `application`. With a [parent], its environment is merged
  /// into [environment].
  AnnotationConfigApplicationContext(
    List<BeanModule> modules, {
    ApplicationContext? parent,
    ConfigurableEnvironment? environment,
    ResourceLoader? resourceLoader,
    String? id,
  }) : _modules = [...modules],
       environment = environment ?? StandardEnvironment(),
       _resources = PathMatchingResourcePatternResolver(
         resourceLoader: resourceLoader ?? DefaultResourceLoader(),
       ),
       id = id ?? 'application' {
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

  /// Name of the context's [BeanIntrospector] bean.
  static const beanIntrospectorBeanName = 'beanIntrospector';

  /// Introspection metadata of this context's modules (falls back to
  /// [BeanIntrospector.shared]).
  final BeanIntrospector introspector = BeanIntrospector(
    parent: BeanIntrospector.shared,
  );

  @override
  final String id;

  @override
  String get displayName => 'AnnotationConfigApplicationContext($id)';

  /// When the last refresh started; `null` before.
  @override
  DateTime? startupDate;

  @override
  final ConfigurableEnvironment environment;

  final DefaultListableBeanFactory _factory = DefaultListableBeanFactory();
  final List<BeanModule> _modules;
  final PathMatchingResourcePatternResolver _resources;
  final _factoryPostProcessors = <BeanFactoryPostProcessor>[];
  final _listeners = <GenericApplicationListener>[];
  ApplicationContext? _parent;
  ApplicationEventMulticaster? _multicaster;
  List<Object>? _earlyEvents;
  MessageSource? _messageSource;
  LifecycleProcessor? _lifecycleProcessor;
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
    _factory.parentBeanFactory = parent;
    final parentEnvironment = parent?.environment;
    if (parentEnvironment is ConfigurableEnvironment) {
      environment.merge(parentEnvironment);
    }
  }

  @override
  BeanFactory? get parentBeanFactory => _parent;

  @override
  bool get isActive => _state == _State.active;

  @override
  bool get isClosed => _state == _State.closed;

  @override
  void register(BeanModule module) {
    _checkNotRefreshed();
    _modules.add(module);
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

  void _checkNotRefreshed() {
    if (_state != _State.created) {
      throw StateError('Modules must be registered before refresh().');
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
    if (_state != _State.created) {
      throw StateError('$displayName.refresh() can be called only once.');
    }
    _state = _State.refreshing;
    startupDate = DateTime.now();
    // Events published while refreshing (before the multicaster and the
    // listeners exist) are buffered and replayed in _finishRefresh.
    _earlyEvents = [];
    try {
      environment.validateRequiredProperties();
      _prepareBeanFactory();
      _loadModules();
      _invokeBeanFactoryPostProcessors();
      _registerBeanPostProcessors();
      _initMessageSource();
      _initEventMulticaster();
      _registerListeners();
      _factory.validateBeanGraph();
      _finishBeanFactoryInitialization();
      _finishRefresh();
      _state = _State.active;
    } catch (_) {
      _factory.destroySingletons();
      _state = _State.failed;
      _earlyEvents = null;
      rethrow;
    }
  }

  // Infrastructure every context offers: conversion, SpEL with
  // introspection-based access, `${...}` resolution, the *Aware callbacks,
  // context interfaces injectable by type, and the environment and
  // introspector as singletons.
  void _prepareBeanFactory() {
    _factory
      ..conversionService = environment.conversionService
      ..beanExpressionResolver ??= StandardBeanExpressionResolver(
        propertyAccessors: [IntrospectionPropertyAccessor(introspector)],
        methodResolvers: [IntrospectionMethodResolver(introspector)],
      )
      ..addEmbeddedValueResolver(environment.resolveRequiredPlaceholders)
      ..addBeanPostProcessor(ApplicationContextAwareProcessor(this))
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

  void _loadModules() {
    final processor = PropertySourceProcessor(environment, this);
    final conditionContext = _ConditionContext(this);
    final seen = <BeanModule>{};
    // Depth-first: imports first; per module, property sources before
    // conditions so conditions can read the loaded properties. Each module
    // is loaded once even if imported several times.
    void load(BeanModule module) {
      if (!seen.add(module)) {
        return;
      }
      module.imports.forEach(load);
      for (final declaration in module.propertySources) {
        if (!declaration.conditions.every((c) => c.matches(conditionContext))) {
          continue;
        }
        processor.processPropertySource(
          declaration.locations,
          name: declaration.name,
          ignoreResourceNotFound: declaration.ignoreResourceNotFound,
          factory: declaration.factory,
        );
      }
      for (final definition in module.definitions) {
        if (definition.conditions.every((c) => c.matches(conditionContext))) {
          _factory.registerBeanDefinition(definition);
        }
      }
      module.configurers.forEach(_factory.registerConfigurer);
      introspector.registerAll(module.introspections);
    }

    _modules.forEach(load);
  }

  // Spring's order: programmatic registry post-processors, then registry
  // post-processor beans (repeatedly, since they may register more), then
  // postProcessBeanFactory on all of those and on the programmatic regular
  // ones, finally regular post-processor beans not handled yet.
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
    // Registry post-processor beans may register more of themselves.
    while (true) {
      final names = _factory
          .getBeanNamesForType(BeanDefinitionRegistryPostProcessor)
          .where(processed.add)
          .toList();
      if (names.isEmpty) {
        break;
      }
      for (final processor in _sortedBeans<BeanDefinitionRegistryPostProcessor>(
        names,
      )) {
        processor.postProcessBeanDefinitionRegistry(_factory);
        registryProcessors.add(processor);
      }
    }
    for (final processor in [...registryProcessors, ...regular]) {
      processor.postProcessBeanFactory(_factory);
    }
    final names = _factory
        .getBeanNamesForType(BeanFactoryPostProcessor)
        .where(processed.add)
        .toList();
    for (final processor in _sortedBeans<BeanFactoryPostProcessor>(names)) {
      processor.postProcessBeanFactory(_factory);
    }
  }

  /// Beans [names] as [T], `PriorityOrdered` first, then by order.
  List<T> _sortedBeans<T extends Object>(List<String> names) {
    final beans = <T, int?>{
      for (final name in names)
        _factory.getBeanByName(name) as T: _factory
            .getBeanDefinition(name)
            .order,
    };
    return OrderComparator.sort(beans.keys, (bean) => beans[bean]);
  }

  void _registerBeanPostProcessors() {
    final names = _factory.getBeanNamesForType(BeanPostProcessor);
    // Like Spring: PriorityOrdered processors are registered before the
    // Ordered ones are created, and those before the rest.
    final priority = <String>[];
    final ordered = <String>[];
    final rest = <String>[];
    for (final name in names) {
      final definition = _factory.getBeanDefinition(name);
      if (definition.types.contains(PriorityOrdered)) {
        priority.add(name);
      } else if (definition.types.contains(Ordered) ||
          definition.order != null) {
        ordered.add(name);
      } else {
        rest.add(name);
      }
    }
    for (final group in [priority, ordered, rest]) {
      for (final processor in _sortedBeans<BeanPostProcessor>(group)) {
        _factory.addBeanPostProcessor(processor);
      }
    }
    // AOP is on as soon as an aspect or advisor exists.
    final usesAop = _factory.beanDefinitionNames.any((name) {
      final definition = _factory.getBeanDefinition(name);
      return definition.aspect != null ||
          definition.types.contains(PointcutAdvisor);
    });
    if (usesAop) {
      _factory.addBeanPostProcessor(AspectAutoProxyCreator(_factory));
    }
  }

  // A user `messageSource` bean gets the parent context as its parent
  // (unless it has one); otherwise an empty DelegatingMessageSource
  // forwards to the parent.
  void _initMessageSource() {
    if (_factory.containsLocalBean(messageSourceBeanName)) {
      final source =
          _factory.getBeanByName(messageSourceBeanName) as MessageSource;
      if (source is HierarchicalMessageSource &&
          source.parentMessageSource == null &&
          _parent != null) {
        source.parentMessageSource = _parent;
      }
      _messageSource = source;
      return;
    }
    final delegating = DelegatingMessageSource(_parent);
    _messageSource = delegating;
    _factory.registerSingleton(
      messageSourceBeanName,
      delegating,
      types: [MessageSource, HierarchicalMessageSource],
    );
  }

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

  // Programmatic listeners plus one adapter per `@EventListener` method;
  // the adapters fetch the bean lazily on each event.
  void _registerListeners() {
    final multicaster = _multicaster!;
    _listeners.forEach(multicaster.addApplicationListener);
    for (final name in _factory.beanDefinitionNames) {
      final definition = _factory.getBeanDefinition(name);
      for (final method in definition.eventListeners) {
        multicaster.addApplicationListener(
          _BeanMethodListener(this, name, method),
        );
      }
    }
  }

  // A `conversionService` bean replaces the environment's service for
  // `@Value` conversion; then the configuration is frozen and eager
  // singletons are created.
  void _finishBeanFactoryInitialization() {
    if (_factory.containsLocalBean(conversionServiceBeanName)) {
      final service = _factory.getBeanByName(conversionServiceBeanName);
      if (service is ConversionService) {
        _factory.conversionService = service;
      }
    }
    _factory
      ..freezeConfiguration()
      ..preInstantiateSingletons();
  }

  void _finishRefresh() {
    // Clear the buffer first so the replayed events are really dispatched.
    // Replayed locally only: the parent already received them when they
    // were published (like Spring's registerListeners).
    final events = _earlyEvents!;
    _earlyEvents = null;
    events.forEach(_multicaster!.multicastEvent);
    final processor = _factory.containsLocalBean(lifecycleProcessorBeanName)
        ? _factory.getBeanByName(lifecycleProcessorBeanName)
              as LifecycleProcessor
        : DefaultLifecycleProcessor(_factory);
    _lifecycleProcessor = processor;
    processor.onRefresh();
    publishEvent(ContextRefreshedEvent(this));
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

  @override
  bool get isRunning => _lifecycleProcessor?.isRunning ?? false;

  /// See [ConfigurableApplicationContext.close]; a no-op unless active.
  @override
  void close() {
    if (_state != _State.active) {
      return;
    }
    // Like Spring's doClose: each step is guarded so a failing listener or
    // lifecycle bean neither stops the shutdown nor escapes from close().
    // The state changes first, so a close() from a listener is a no-op.
    _state = _State.closing;
    try {
      publishEvent(ContextClosedEvent(this));
    } catch (error, stackTrace) {
      _log.warning(
        'Exception thrown from a listener handling ContextClosedEvent',
        error: error,
        stackTrace: stackTrace,
      );
    }
    try {
      _lifecycleProcessor?.onClose();
    } catch (error, stackTrace) {
      _log.warning(
        'Exception thrown from the LifecycleProcessor on context close',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _factory.destroySingletons();
    _multicaster?.removeAllListeners();
    _state = _State.closed;
  }

  // ---------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------

  /// Dispatches [event] to matching listeners synchronously, then to the
  /// parent context. Non-[ApplicationEvent] objects are wrapped in a
  /// [PayloadApplicationEvent].
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
  void publishEvent(Object event) {
    if (_state == _State.failed) {
      throw StateError('$displayName failed to refresh and is unusable.');
    }
    final applicationEvent = event is ApplicationEvent
        ? event
        : PayloadApplicationEvent<Object>(this, event);
    final early = _earlyEvents;
    if (early != null) {
      early.add(applicationEvent);
    } else {
      final multicaster = _multicaster;
      if (multicaster == null) {
        throw StateError(
          '$displayName cannot publish events before refresh().',
        );
      }
      multicaster.multicastEvent(applicationEvent);
    }
    // The parent gets the original object so it wraps it itself.
    _parent?.publishEvent(event);
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
  String toString() => displayName;
}

/// Invokes an `@EventListener` method of a bean, fetching the bean when an
/// event arrives (so lazy and prototype beans work).
final class _BeanMethodListener implements GenericApplicationListener, Ordered {
  _BeanMethodListener(this._context, this._beanName, this._method);

  final AnnotationConfigApplicationContext _context;
  final String _beanName;
  final EventListenerMethod<Object> _method;

  @override
  int get order => _method.order ?? Ordered.lowestPrecedence;

  @override
  bool supportsEvent(Object event) => _method.supports(event);

  @override
  void onApplicationEvent(Object event) {
    final bean = _context._factory.getBeanByName(_beanName);
    final result = _method.invoke(bean, event);
    if (result == null) {
      return;
    }
    if (result is Iterable<Object?>) {
      for (final item in result) {
        if (item != null) {
          _context.publishEvent(item);
        }
      }
    } else {
      _context.publishEvent(result);
    }
  }

  @override
  String toString() => '_BeanMethodListener($_beanName, ${_method.id})';
}

/// The [ConditionContext] handed to conditions while modules load.
final class _ConditionContext implements ConditionContext {
  _ConditionContext(this._context);

  final AnnotationConfigApplicationContext _context;

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
