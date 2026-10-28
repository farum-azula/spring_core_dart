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

/// A running application's container: it holds the beans and gives
/// access to the configuration, events, translated messages and resource
/// files.
///
/// Once started, the context has created every bean, injected each one's
/// dependencies and called their init methods. It is also the place where
/// the rest of the framework meets: beans are looked up here
/// ([getBean]), events are published to listeners ([publishEvent]),
/// messages are translated ([getMessage]) and files are found
/// ([getResource]). It falls back to a [parent] context for beans and
/// messages it does not have itself.
///
/// Most application code never touches it: beans receive what they need
/// by injection (an `ApplicationEventPublisher`, a `MessageSource`, the
/// `Environment`). You meet the context in `main`, where
/// [ApplicationContext.run] or Spring Boot's `SpringApplication.run`
/// returns it; in tests; and in code outside the container that needs a
/// bean, such as a Flutter widget. A bean can also inject it. This
/// interface only reads; starting and stopping is on
/// [ConfigurableApplicationContext].
///
/// ```dart
/// // In main: start the beans, then use a bean and the context's services.
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
  /// Creates an [AnnotationConfigApplicationContext] for [modules], starts
  /// it with [ConfigurableApplicationContext.refresh] and returns it.
  ///
  /// This is how a program without Spring Boot starts its beans. The
  /// optional arguments are those of the
  /// [AnnotationConfigApplicationContext] constructor: a [parent] context,
  /// an [environment] (for example with active profiles or properties
  /// read beforehand), a [resourceLoader] and an [id]. Throws what
  /// `refresh` throws, such as a missing dependency. Close the returned
  /// context when the program ends.
  ///
  /// ```dart
  /// // The `dev` profile picks the development beans.
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

  /// Like [run], but starts the context with
  /// [ConfigurableApplicationContext.refreshAsync] and completes once it
  /// is running.
  ///
  /// Use it when an init callback (`@PostConstruct`, `afterPropertiesSet`,
  /// init method) returns a `Future`, or when a `@PropertySource` reads a
  /// resource that is only available asynchronously, such as a Flutter
  /// asset.
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

  /// A name that tells this context apart from others in logs, for example
  /// a parent and a child.
  ///
  /// By default the class name and identity hash code
  /// (`AnnotationConfigApplicationContext@1b2c3d`, as Spring's
  /// `ObjectUtils.identityToString`). Spring Boot's `SpringApplication`
  /// uses `spring.application.name` (or `application`).
  String get id;

  /// The name used in error messages and `toString`: the [id], or the
  /// class name with the id when one was given explicitly.
  String get displayName;

  /// When the refresh started, for uptime reports; `null` before.
  DateTime? get startupDate;

  /// The context this one extends, or `null`.
  ///
  /// A child context sees the parent's beans and messages when it has none
  /// of its own, and every event published in the child is also published
  /// in the parent. Use a parent for beans shared by several contexts.
  ApplicationContext? get parent;

  /// The configuration the context was built with: properties from all
  /// sources, the active profiles and the type conversion used for them.
  Environment get environment;

  /// The factory that injects objects the container did not create, such
  /// as a `@Configurable` Flutter `State` (`autowireBean`).
  ///
  /// Throws a `StateError` before the refresh and after the close.
  AutowireCapableBeanFactory get autowireCapableBeanFactory;

  /// Calls [listener] for every event published from now on whose type,
  /// or payload type, is [E].
  ///
  /// Use it for code that is not a bean, for example a Flutter widget that
  /// refreshes when an event arrives, or a test that records events. Beans
  /// use `@EventListener` instead. Call `remove()` on the returned
  /// registration to stop listening. Listeners with a lower [order] run
  /// first; the default runs last.
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

/// An application context that can also be set up, started, paused and
/// closed.
///
/// [ApplicationContext] is what code that uses the beans needs. This
/// interface is for the code that owns the context: `main`, a test, or
/// Spring Boot's `SpringApplication`, which returns one from `run`. Before
/// [refresh] it accepts more modules, post-processors and listeners;
/// [refresh] creates the beans; [close] stops and destroys them. A bean
/// that must shut the application down can inject it.
///
/// ```dart
/// // A plugin module and a post-processor join before the start; the
/// // finally block destroys the beans even when the app fails.
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

  /// Sets the parent context; set it before [refresh]. The parent's bean
  /// factory becomes this context's parent factory, and the parent's
  /// environment (property sources and profiles) is merged into this one.
  set parent(ApplicationContext? parent);

  /// The bean factory inside the context, which holds the bean
  /// definitions and the created beans.
  ///
  /// It is available before [refresh], so code that sets up the context can
  /// change definitions or register ready-made objects
  /// (`registerSingleton`). Bean lookups go through the context itself.
  ConfigurableListableBeanFactory get beanFactory;

  /// Adds beans before [refresh]: a [BeanModule], or an object that
  /// registers beans in code (a `BeanRegistrar`, an `ImportSelector` or an
  /// `ImportBeanDefinitionRegistrar`).
  ///
  /// Use it for beans chosen at runtime, such as plugins or test
  /// replacements. Components are processed in registration order, after
  /// the modules given to the constructor, while the modules load (Spring's
  /// `register(Class...)` / `register(BeanRegistrar...)`). Throws an
  /// `ArgumentError` for other objects and a `StateError` once [refresh]
  /// has started.
  ///
  /// ```dart
  /// context
  ///   ..register(appBeans)
  ///   ..register(const MessagingRegistrar());
  /// ```
  void register(Object component);

  /// Adds a post-processor that [refresh] runs once every bean definition
  /// is loaded and before any bean is created.
  ///
  /// Use it to adjust definitions from the code that builds the context,
  /// without declaring the processor as a bean. Processors added here run
  /// before the post-processor beans; one added after [refresh] never runs.
  void addBeanFactoryPostProcessor(BeanFactoryPostProcessor processor);

  /// Adds a listener object that is not a bean; works before and after
  /// [refresh].
  ///
  /// Listeners added before [refresh] also receive the context's own
  /// events, such as `ContextRefreshedEvent`. For a plain function,
  /// [addListener] is shorter; for an `ApplicationListener<E>` object, wrap
  /// it with `ApplicationListenerAdapter.forListener`.
  ///
  /// ```dart
  /// // Run ready() once every bean exists.
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

  /// Removes a listener added with [addApplicationListener]; it receives
  /// no more events.
  void removeApplicationListener(GenericApplicationListener listener);

  /// The listener objects the context holds, for diagnostics.
  ///
  /// These are the listeners added with [addApplicationListener], plus the
  /// singleton [GenericApplicationListener] beans and `registerSingleton`
  /// objects, which the context adds once they are created (as Spring's
  /// `ApplicationListenerDetector` does). Not included:
  /// `ApplicationListener<E>` beans (wired by bean name), lazy listener
  /// beans not created yet and `@EventListener` methods.
  List<GenericApplicationListener> get applicationListeners;

  /// Teaches [getResource] a custom location prefix, such as `asset:` for
  /// Flutter assets.
  ///
  /// The resolver is asked before the built-in prefixes, for every
  /// location, including `@Value` resources and `@PropertySource` files.
  /// Add it before [refresh] so that the beans see it. Throws a
  /// `StateError` when the context was given a resource loader that is not
  /// a `DefaultResourceLoader` (Spring's
  /// `DefaultResourceLoader.addProtocolResolver`).
  void addProtocolResolver(ProtocolResolver resolver);

  /// Starts the context: registers the beans, checks them and creates
  /// every singleton that is not lazy. Call it once.
  ///
  /// In order: check the required properties; load the modules (their
  /// `@PropertySource` files and conditions decide which beans exist); run
  /// the bean factory post-processors; register the bean post-processors;
  /// set up the message source and the event multicaster; register the
  /// listeners; check the bean graph (a missing or ambiguous dependency
  /// or a cycle fails here, before any constructor runs); create the eager
  /// singletons; start the auto-startup [SmartLifecycle] beans; publish
  /// `ContextRefreshedEvent`.
  ///
  /// When a step fails, the lifecycle beans already started are stopped,
  /// the created singletons are destroyed, the error is rethrown and the
  /// context becomes unusable. Like Spring's `GenericApplicationContext`,
  /// a second call throws a `StateError`, also after a failed refresh. An
  /// init callback (`@PostConstruct`, `afterPropertiesSet`, init method)
  /// that returns a `Future` fails the refresh: use [refreshAsync] for
  /// those.
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
  void refresh();

  /// Like [refresh], for beans whose init callbacks are asynchronous.
  ///
  /// It first reads `@PropertySource` files that are only available
  /// asynchronously (Flutter assets). The eager singletons are created,
  /// then every `Future` returned by their `@PostConstruct`,
  /// `afterPropertiesSet` and init methods is awaited, one bean after
  /// another, before `SmartInitializingSingleton`, the lifecycle start and
  /// `ContextRefreshedEvent`; a failure fails the refresh and names the
  /// bean. A failed refresh stops the lifecycle beans already started and
  /// destroys the created singletons, awaiting asynchronous destroy
  /// callbacks.
  ///
  /// ```dart
  /// final context = AnnotationConfigApplicationContext([appBeans]);
  /// await context.refreshAsync();
  /// ```
  Future<void> refreshAsync();

  /// Shuts the context down: publishes `ContextClosedEvent`, stops the
  /// running [Lifecycle] beans and destroys the singletons (each bean after
  /// the beans that depend on it), which runs their `@PreDestroy` and
  /// destroy methods.
  ///
  /// Call it when the program ends, or let [registerShutdownHook] do it. It
  /// does nothing unless the context is active, so a second call is
  /// harmless; it also works during [refresh], for example from a
  /// `ContextRefreshedEvent` listener. It never throws because of a failing
  /// `ContextClosedEvent` listener or a bean that fails to stop: the error
  /// is logged and the shutdown goes on. It does not wait: a
  /// `SmartLifecycle` stop callback that comes later, or a destroy callback
  /// that returns a `Future`, is logged and skipped; use [closeAsync] to
  /// wait for them.
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

  /// Closes the context when the process is asked to stop (Ctrl+C or a
  /// `kill`), so that the beans release their resources.
  ///
  /// On SIGINT or SIGTERM it runs [closeAsync], which waits for
  /// asynchronous `SmartLifecycle` stops and destroy callbacks, then ends
  /// the process with `128 + signal` (`130`, `143`), like Spring's
  /// `registerShutdownHook()` on the JVM. A second call does nothing. The
  /// signals are no longer watched once the context closes, because a Dart
  /// program that watches signals does not end by itself. Does nothing
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

  /// Stops the running [Lifecycle] beans for a while, keeping every bean
  /// alive, then publishes `ContextPausedEvent`; [restart] resumes them.
  ///
  /// Use it when the application goes to the background, for example a
  /// Flutter app on `AppLifecycleState.paused`, so that pollers and
  /// connections stop. [SmartLifecycle] beans whose
  /// [SmartLifecycle.isPauseable] is `false` keep running. Nothing is
  /// stopped unless the lifecycle is running. It does not wait for
  /// `SmartLifecycle.stopWithCallback` callbacks; [pauseAsync] does. Like
  /// Spring 7's `pause()`.
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

  /// Like [pause], but waits for the `SmartLifecycle.stopWithCallback`
  /// callbacks of each phase (at most the lifecycle processor's timeout per
  /// phase) before `ContextPausedEvent` is published.
  Future<void> pauseAsync();

  /// Brings the lifecycle beans back to the state right after [refresh],
  /// typically after [pause], then publishes `ContextRestartedEvent`.
  ///
  /// It stops the pauseable [Lifecycle] beans if the lifecycle is still
  /// running, then starts the auto-startup [SmartLifecycle] beans again.
  /// Unlike [start], beans that are not auto-startup stay stopped. A bean
  /// whose `SmartLifecycle.stopWithCallback` callback is still pending is
  /// started when the callback fires. Like Spring 7's `restart()`.
  void restart();

  /// Like [close], but waits for asynchronous shutdown work and completes
  /// once the context is closed.
  ///
  /// It waits for the `SmartLifecycle.stopWithCallback` callbacks of each
  /// phase (at most the lifecycle processor's timeout per phase, 10
  /// seconds by default; then the beans still running are logged and the
  /// next phase is stopped) and for the destroy callbacks (`@PreDestroy`,
  /// `DisposableBean.destroy`, destroy methods) that return a `Future`,
  /// each bean after its dependents. Use it when beans flush or disconnect
  /// asynchronously. Does nothing unless the context is active.
  ///
  /// ```dart
  /// // Your own signal handling, instead of registerShutdownHook().
  /// ProcessSignal.sigint.watch().listen((_) async {
  ///   await context.closeAsync();
  ///   exit(0);
  /// });
  /// ```
  Future<void> closeAsync();

  /// Whether beans can be looked up: `true` from the start of [refresh]
  /// until [close] has finished, `false` again after a failed refresh.
  bool get isActive;

  /// Whether [close] (or [closeAsync]) has completed; a closed context
  /// cannot be started again.
  bool get isClosed;
}

// created → refreshing → active → closed; a throwing refresh() ends in
// failed. Only `active` (and `refreshing`, for beans created during
// refresh) allows bean lookups.
enum _State { created, refreshing, active, closing, failed, closed }

/// The application context of this package: it builds its beans from the
/// [BeanModule]s the generator writes for `@ComponentScan`.
///
/// It is the only implementation of [ConfigurableApplicationContext] here;
/// [ApplicationContext.run] and Spring Boot's `SpringApplication` create
/// one for you. Construct it yourself when something must happen between
/// creating the context and starting it: [register] more modules,
/// [registerBean] a bean in code, add a post-processor, set a parent. Then
/// call [refresh]. A subclass can override the template methods
/// [postProcessBeanFactory], [onRefresh] and [onClose].
///
/// Some of its own parts can be replaced by declaring a bean with a
/// well-known name: [messageSourceBeanName] for the translated messages,
/// [applicationEventMulticasterBeanName] for event delivery,
/// [lifecycleProcessorBeanName] for starting and stopping lifecycle
/// beans, [conversionServiceBeanName] for `@Value` conversion.
///
/// ```dart
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
///
/// // The `dev` profile is set before any bean definition is loaded.
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
  /// Creates a context for [modules]; nothing is loaded or created until
  /// [refresh].
  ///
  /// Without an [environment] the context uses a new
  /// `StandardEnvironment` (OS environment variables, no config files;
  /// read those beforehand with `ConfigDataEnvironment`, or use Spring
  /// Boot). Without a [resourceLoader] it uses a `DefaultResourceLoader`;
  /// without an [id], the class name and identity hash code. With a
  /// [parent], the parent's environment is merged into [environment].
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

  /// The bean name of the context's `MessageSource`.
  ///
  /// Declare a bean with this name (for example a
  /// `ReloadableResourceBundleMessageSource` reading `messages.properties`)
  /// and [getMessage] uses it; in a child context it falls back to the
  /// parent's message source. Without one, the context registers an empty
  /// `DelegatingMessageSource` that asks the parent, if any.
  static const messageSourceBeanName = 'messageSource';

  /// The bean name of the object that delivers events to listeners.
  ///
  /// Declare an `ApplicationEventMulticaster` bean with this name to change
  /// how events are delivered, for example a
  /// `SimpleApplicationEventMulticaster` with a task executor so that
  /// listeners run asynchronously. Without one, the context registers a
  /// synchronous `SimpleApplicationEventMulticaster`.
  static const applicationEventMulticasterBeanName =
      'applicationEventMulticaster';

  /// The bean name of the object that starts and stops the [Lifecycle]
  /// beans.
  ///
  /// Declare a `DefaultLifecycleProcessor` bean with this name to change
  /// its shutdown timeouts. Without one, the context registers a default
  /// one.
  static const lifecycleProcessorBeanName = 'lifecycleProcessor';

  /// The bean name of a `ConversionService` that replaces the
  /// environment's for converting `@Value` texts to their target types.
  ///
  /// A bean of this name in this context or an ancestor is used; without
  /// one, the environment's conversion service converts.
  static const conversionServiceBeanName = 'conversionService';

  /// The bean name under which the context registers its [environment],
  /// so it can be injected as `Environment` or looked up by name.
  static const environmentBeanName = 'environment';

  /// The bean name of the `TaskExecutor` that `@Async` listeners use when
  /// there are several executors and none is `@Primary` (Spring's
  /// `AsyncExecutionAspectSupport.DEFAULT_TASK_EXECUTOR_BEAN_NAME`).
  static const defaultTaskExecutorBeanName = 'taskExecutor';

  /// The bean name under which the context registers its [introspector].
  static const beanIntrospectorBeanName = 'beanIntrospector';

  /// The generated descriptions of the `@Introspected` classes of this
  /// context's modules: their properties and methods, which data binding,
  /// validation and SpEL use instead of reflection. Classes it does not
  /// know are looked up in [BeanIntrospector.shared].
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

  /// When [refresh] started; `null` before. Set by the context.
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

  /// Adds a bean of type [T], created by [supplier], before [refresh].
  ///
  /// Use it for a bean that is not in a module: an object built from
  /// command-line arguments, or a test replacement marked `primary`. The
  /// [supplier] gets a resolver for the bean's own dependencies. The
  /// options are those of [BeanRegistry.registerBean]; without a [name]
  /// the bean is called `Type#0`, `Type#1`, ... The bean is registered while
  /// the modules load, in order with the [register]ed components. Throws a
  /// `StateError` once [refresh] has started.
  ///
  /// ```dart
  /// // A system clock, and a mailer that takes precedence over the
  /// // module's one.
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

  /// Every condition the refresh evaluated, with its outcome, in
  /// evaluation order.
  ///
  /// It answers "why is this bean missing?": each entry names the bean or
  /// class, the condition (a profile, `@ConditionalOnProperty`, ...) and
  /// whether it matched. `SpringApplication` prints it as the condition
  /// evaluation report for `--debug` (Spring Boot's
  /// `ConditionEvaluationReport`). The conditions shared by a
  /// configuration class appear once, under the class's key.
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

  /// The beans named [names] as [T], sorted: `PriorityOrdered` first,
  /// then by order.
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

  /// Starts every [Lifecycle] bean that is not running, also those that
  /// are not auto-startup, then publishes `ContextStartedEvent`. Throws a
  /// `StateError` unless the context is active.
  @override
  void start() {
    _checkActive();
    _lifecycleProcessor!.start();
    publishEvent(ContextStartedEvent(this));
  }

  /// Stops every running [Lifecycle] bean, keeping the beans themselves,
  /// then publishes `ContextStoppedEvent`; [start] starts them again.
  /// Throws a `StateError` unless the context is active.
  @override
  void stop() {
    _checkActive();
    _lifecycleProcessor!.stop();
    publishEvent(ContextStoppedEvent(this));
  }

  @override
  void restart() {
    _checkActive();
    _lifecycleProcessor!.onRestart();
    publishEvent(ContextRestartedEvent(this));
  }

  @override
  void pause() {
    _checkActive();
    _lifecycleProcessor!.onPause();
    publishEvent(ContextPausedEvent(this));
  }

  @override
  Future<void> pauseAsync() async {
    _checkActive();
    await _lifecycleProcessor!.onPauseAsync();
    publishEvent(ContextPausedEvent(this));
  }

  @override
  bool get isRunning => _lifecycleProcessor?.isRunning ?? false;

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

  /// A hook for subclasses, called by [refresh] once every bean
  /// definition is registered and before the bean factory post-processors
  /// run; no bean exists yet.
  ///
  /// Override it in a context subclass that always adds the same
  /// definitions, singletons or post-processors. Does nothing by default;
  /// not meant to be called directly. Spring's `postProcessBeanFactory`.
  ///
  /// ```dart
  /// // Every MyContext has a `clock` bean.
  /// class MyContext extends AnnotationConfigApplicationContext {
  ///   MyContext(super.modules);
  ///
  ///   @override
  ///   void postProcessBeanFactory(ConfigurableListableBeanFactory factory) =>
  ///       factory.registerSingleton('clock', SystemClock());
  /// }
  /// ```
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}

  /// A hook for subclasses, called by [refresh] once the message source
  /// and the event multicaster exist, before the listeners are registered
  /// and the eager singletons are created.
  ///
  /// Override it for work a special kind of context must do at that point
  /// (Spring's web contexts create their server here). Does nothing by
  /// default; not meant to be called directly. Spring's `onRefresh`.
  void onRefresh() {}

  /// A hook for subclasses, called last by [close] and [closeAsync], after
  /// the singletons are destroyed and before the context counts as closed.
  ///
  /// Override it to release what the context subclass itself holds. Does
  /// nothing by default; not meant to be called directly. Spring's
  /// `onClose`.
  void onClose() {}

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

  /// Delivers [event] to this context's listeners, then publishes it in
  /// the parent context.
  ///
  /// The listeners run in the publishing call, unless the event
  /// multicaster has a task executor. An object that is not an
  /// [ApplicationEvent] is wrapped in a [PayloadApplicationEvent] of its
  /// static type [T] (Spring uses the runtime type): listeners of `T` get
  /// the object, listeners of `PayloadApplicationEvent<T>` the wrapper.
  /// Events published during [refresh] before the listeners are registered
  /// are kept and delivered once they are. Like Spring 7, an event
  /// published before [refresh], after a failed refresh or after [close]
  /// reaches only the parent.
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

  /// Looks up the message [code] in the context's message source (the
  /// `messageSource` bean, else the parent's) and fills in [args].
  ///
  /// Throws a `StateError` unless the context is active, and a
  /// `NoSuchMessageException` when the code is unknown and there is no
  /// [defaultMessage].
  ///
  /// ```dart
  /// // The Russian greeting: messages_ru_RU.properties, else messages_ru.
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

/// The listener the context registers for one `@EventListener` method (or
/// the `onApplicationEvent` of an `ApplicationListener` bean).
///
/// It looks the bean up when an event arrives, so lazy and prototype beans
/// work. It checks the method's condition, runs an `@Async` method on its
/// executor, and publishes the method's non-null results as new events.
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

/// A stand-in for a lazy [GenericApplicationListener] bean that does not
/// exist yet, like a listener bean name in Spring's multicaster.
///
/// The first event creates the bean, asks it whether it handles the event,
/// and removes this stand-in; from then on the bean receives the events
/// directly (the detector registered it when it was created).
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

/// Adds listener beans to the context when they are created and removes
/// them when they are destroyed, like Spring's
/// `ApplicationListenerDetector`.
///
/// A singleton [GenericApplicationListener] is added once initialized. A
/// non-singleton one cannot be reached and is logged as a warning. An
/// `ApplicationListener<E>` bean is wired by the generator through its
/// `onApplicationEvent` method instead; when it is destroyed, its listener
/// is removed, and added back if the bean is created again.
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

/// One bean added with `AnnotationConfigApplicationContext.registerBean`,
/// kept until the modules load so that it is registered in order with the
/// other components.
final class _SingleBeanRegistrar {
  _SingleBeanRegistrar(this.register);

  final void Function(BeanRegistry registry) register;
}

/// The [BeanRegistry] a [BeanRegistrar] registers its beans in: it turns
/// each call into a bean definition of the context's factory, like
/// Spring 7's `BeanRegistryAdapter`.
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

/// Logs, at INFO, a bean created while the post-processors are still being
/// registered, like Spring's `BeanPostProcessorChecker`.
///
/// The processors registered after such a bean never see it, so it may
/// miss its AOP proxy, for example. The usual cause is a post-processor
/// that injects a regular bean; the message names it.
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

/// The [ConditionContext] that conditions receive while the modules load;
/// it also caches shared decisions and records every outcome for
/// [AnnotationConfigApplicationContext.conditionEvaluations].
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
