import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/object_provider.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';

/// Read access to beans, like Spring's `BeanFactory`.
///
/// Lookups are by type (`getBean<T>()`), optionally narrowed by a
/// qualifier (bean name, alias or `@Qualifier` value), or by name.
/// Factories form a hierarchy: what is not found locally is looked up in
/// the parent.
///
/// ```dart
/// final context = ApplicationContext.run([appBeans]);
/// final mailer = context.getBean<Mailer>();
/// final smtp = context.getBean<Transport>(qualifier: 'smtp');
/// final audit = context.findBean<Audit>(); // null when absent
/// final raw = context.getBeanByName('mailer') as Mailer;
/// ```
///
/// Spring (Java):
/// ```java
/// Mailer mailer = context.getBean(Mailer.class);
/// Transport smtp = context.getBean("smtp", Transport.class);
/// Audit audit = context.getBeanProvider(Audit.class).getIfAvailable();
/// Mailer raw = (Mailer) context.getBean("mailer");
/// ```
abstract interface class BeanFactory {
  /// Prefix that selects a `FactoryBean` itself instead of its product.
  static const factoryBeanPrefix = '&';

  /// The bean of type [T]. With [qualifier], only beans with that name,
  /// alias or qualifier match. Throws `NoSuchBeanDefinitionException` if
  /// nothing matches and `NoUniqueBeanDefinitionException` if several beans
  /// match and none is primary (or all but one are fallbacks).
  ///
  /// Like Spring's `getBean(Class)`, beans that are not autowire
  /// candidates count only when they are the only matches, and a qualifier
  /// selects any bean. Local beans are looked up first, then values of
  /// `registerResolvableDependency` (Spring's `getBean` ignores those),
  /// then the parent.
  ///
  /// ```dart
  /// final greeter = factory.getBean<Greeter>(qualifier: 'french');
  /// ```
  ///
  /// Spring: `getBean(Class)`; with a qualifier, `getBean(name, Class)` or
  /// `BeanFactoryAnnotationUtils.qualifiedBeanOfType`.
  T getBean<T extends Object>({String? qualifier});

  /// Like [getBean], but `null` when no bean matches (still throws when
  /// several match). Spring: `getBeanProvider(T).getIfAvailable()`.
  T? findBean<T extends Object>({String? qualifier});

  /// The bean named [name] (or alias); `&name` returns a factory bean
  /// itself. Spring: `getBean(String)`.
  ///
  /// ```dart
  /// final product = factory.getBeanByName('client');
  /// final factoryBean = factory.getBeanByName('&client');
  /// ```
  Object getBeanByName(String name);

  /// A lazy handle for beans of [T]; nothing is created until the provider
  /// is used.
  ///
  /// ```dart
  /// final all = factory.getBeanProvider<Greeter>().orderedList();
  /// ```
  ObjectProvider<T> getBeanProvider<T extends Object>({String? qualifier});

  /// Whether a bean named [name] exists here or in a parent.
  bool containsBean(String name);

  /// Whether a bean of [type] would be injected by type, without creating
  /// it: an autowire candidate (and, without [qualifier], a default
  /// candidate) here or, with [includeAncestors], in a parent; or a
  /// resolvable dependency. This is what `@ConditionalOnBean` /
  /// `@ConditionalOnMissingBean` check, like Spring Boot's
  /// `OnBeanCondition`.
  bool containsBeanOfType(
    Type type, {
    String? qualifier,
    bool includeAncestors = true,
  });

  /// Whether the bean named [name] (`&name` for a factory bean itself) is
  /// of [type], without creating it; every bean is an `Object`. Throws
  /// `NoSuchBeanDefinitionException` when there is no such bean. Spring:
  /// `isTypeMatch(String, Class)`.
  ///
  /// ```dart
  /// factory.isTypeMatch('english', Greeter); // true
  /// ```
  bool isTypeMatch(String name, Type type);

  /// Whether [name] is a singleton. For a `FactoryBean`, whether its
  /// product is shared (`&name` asks about the factory itself).
  bool isSingleton(String name);

  /// Whether [name] is a prototype (a new instance per lookup). For a
  /// `FactoryBean`, whether its product is created per lookup.
  bool isPrototype(String name);

  /// Declared type of the bean named [name] (the product type for factory
  /// beans), or `null` if unknown.
  Type? getType(String name);

  /// Aliases of the bean named [name].
  List<String> getAliases(String name);
}

/// A bean factory with a parent, like Spring's `HierarchicalBeanFactory`.
///
/// Lookups that fail locally fall back to the parent, so a child context
/// (e.g. a feature module) sees the beans of its parent but not vice
/// versa.
///
/// ```dart
/// final parent = DefaultListableBeanFactory();
/// final child = DefaultListableBeanFactory(parentBeanFactory: parent);
/// child.containsBean('fromParent');      // true if parent has it
/// child.containsLocalBean('fromParent'); // false
/// ```
///
/// Spring (Java):
/// ```java
/// DefaultListableBeanFactory child = new DefaultListableBeanFactory(parent);
/// child.containsBean("fromParent");
/// child.containsLocalBean("fromParent");
/// ```
abstract interface class HierarchicalBeanFactory implements BeanFactory {
  /// The parent factory, or `null` for a root factory.
  BeanFactory? get parentBeanFactory;

  /// Whether this factory itself (not a parent) holds [name].
  bool containsLocalBean(String name);
}

/// Enumerates beans, like Spring's `ListableBeanFactory`. Only local beans
/// are listed (not the parent's; see `BeanFactoryUtils` for the whole
/// hierarchy), except by [getSortedBeans].
///
/// ```dart
/// for (final name in factory.getBeanNamesForType(Greeter)) {
///   print(name);
/// }
/// final greeters = factory.getBeansOfType<Greeter>(); // name -> bean
/// final ordered = factory.getSortedBeans<Greeter>();
/// ```
///
/// Spring (Java):
/// ```java
/// for (String name : factory.getBeanNamesForType(Greeter.class)) { ... }
/// Map<String, Greeter> greeters = factory.getBeansOfType(Greeter.class);
/// List<Greeter> ordered =
///     factory.getBeanProvider(Greeter.class).orderedStream().toList();
/// ```
abstract interface class ListableBeanFactory implements BeanFactory {
  /// Whether a definition is registered under exactly [name] (aliases do
  /// not count).
  bool containsBeanDefinition(String name);

  /// Number of local bean definitions.
  int get beanDefinitionCount;

  /// Names of all local definitions, in registration order (singletons
  /// added with `registerSingleton` are not definitions).
  List<String> get beanDefinitionNames;

  /// Names of beans of [type] (definitions, then registered singletons), in
  /// registration order. Does not create beans. A `FactoryBean` looked up
  /// by its own type is listed as `&name` (by its product type as `name`).
  /// [includeNonSingletons] `false` restricts to singletons.
  List<String> getBeanNamesForType(
    Type type, {
    bool includeNonSingletons = true,
  });

  /// Beans of [T] by name (as [getBeanNamesForType]), in registration
  /// order (creates them).
  Map<String, T> getBeansOfType<T extends Object>({
    bool includeNonSingletons = true,
  });

  /// Beans of [T] here and in the parent factories (a bean hides a parent
  /// bean with the same name), sorted by `PriorityOrdered` / `Ordered` /
  /// `@Order`; with [qualifier], only the beans it selects. Like Spring's
  /// `getBeanProvider(T).orderedStream()`, beans that are not autowire
  /// candidates are included.
  List<T> getSortedBeans<T extends Object>({String? qualifier});

  /// Names of the local beans whose class (or `@Bean` method) carries an
  /// annotation of type [A] (or a subclass, e.g. `@Service` for
  /// `Component`). Spring: `getBeanNamesForAnnotation`.
  ///
  /// ```dart
  /// final services = factory.getBeanNamesForAnnotation<Service>();
  /// ```
  List<String> getBeanNamesForAnnotation<A extends Object>();

  /// The local beans annotated with [A], by name (creates them). Spring:
  /// `getBeansWithAnnotation`.
  Map<String, Object> getBeansWithAnnotation<A extends Object>();

  /// The [A] annotation on the class (or `@Bean` method) of the bean named
  /// [beanName], or `null`; looks in the parent when the bean is not local.
  /// Spring: `findAnnotationOnBean`.
  ///
  /// ```dart
  /// final order = factory.findAnnotationOnBean<Order>('english')?.value;
  /// ```
  A? findAnnotationOnBean<A extends Object>(String beanName);
}

/// Registers bean definitions, like Spring's `BeanDefinitionRegistry`.
///
/// ```dart
/// registry.registerBeanDefinition(
///   BeanDefinition<Clock>(name: 'clock', create: (_) => SystemClock()),
/// );
/// registry.registerAlias('clock', 'systemClock');
/// ```
///
/// Spring (Java):
/// ```java
/// registry.registerBeanDefinition("clock",
///     new RootBeanDefinition(SystemClock.class));
/// registry.registerAlias("clock", "systemClock");
/// ```
abstract interface class BeanDefinitionRegistry {
  /// Registers [definition]; a duplicate name (or a name used as an alias)
  /// fails unless overriding is allowed. Re-registering a definition from
  /// the same `source` is a no-op; a singleton added with
  /// `registerSingleton` under the name is replaced (like Spring). Works
  /// after `freezeConfiguration` too (lookup caches are cleared).
  ///
  /// Unlike Spring, the name is part of the definition
  /// (`BeanDefinition.name`); its `aliases` are registered too.
  void registerBeanDefinition(BeanDefinition<Object> definition);

  /// Removes the definition named [name] (or alias), destroying its
  /// singleton (dependents first) and removing every alias that leads to
  /// it. Throws `NoSuchBeanDefinitionException` if unknown.
  void removeBeanDefinition(String name);

  /// The definition named [name] (or alias; `&name` gives the definition
  /// of a factory bean); throws `NoSuchBeanDefinitionException` if
  /// unknown. Singletons added with `registerSingleton` have none.
  BeanDefinition<Object> getBeanDefinition(String name);

  /// Whether a definition is registered under exactly [name].
  bool containsBeanDefinition(String name);

  /// Names of all definitions, in registration order.
  List<String> get beanDefinitionNames;

  /// Number of registered definitions.
  int get beanDefinitionCount;

  /// Makes [alias] another name for [name]; aliases also count as
  /// qualifiers and for matching parameter names. Throws
  /// `BeanDefinitionOverrideException` when [alias] is a bean name or,
  /// unless bean definition overriding is allowed, an alias of another
  /// bean.
  void registerAlias(String name, String alias);

  /// Removes [alias]; throws `ArgumentError` if it is not registered.
  void removeAlias(String alias);

  /// Whether [name] is an alias (not a canonical bean name).
  bool isAlias(String name);

  /// Whether [name] is used by a definition or alias.
  bool isBeanNameInUse(String name);
}

/// Registers ready-made objects as beans, like Spring's
/// `SingletonBeanRegistry`.
///
/// ```dart
/// factory.registerSingleton(
///   'clock',
///   SystemClock(),
///   types: const [SystemClock, Clock],
/// );
/// factory.getBean<Clock>();
/// ```
///
/// Spring (Java):
/// ```java
/// factory.registerSingleton("clock", new SystemClock());
/// factory.getBean(Clock.class);
/// ```
///
/// Spring matches supertypes by reflection; here pass every lookup type in
/// `types`.
abstract interface class SingletonBeanRegistry {
  /// Registers [singleton] under [name], exposed as [types] (default: its
  /// runtime type). No init or destroy callbacks are run for it, and it is
  /// not a bean definition (not in `beanDefinitionNames`), like in Spring.
  /// A registered `FactoryBean` is dereferenced: [name] gives its product,
  /// `&name` the factory.
  void registerSingleton(String name, Object singleton, {List<Type>? types});

  /// The created singleton named [name], or `null` (does not create it).
  Object? getSingleton(String name);

  /// Whether the singleton named [name] has been created or registered.
  bool containsSingleton(String name);

  /// Names of the singletons created or registered so far.
  List<String> get singletonNames;
}

/// Resolves `${...}`-style strings, like Spring's `StringValueResolver`.
///
/// ```dart
/// factory.addEmbeddedValueResolver(env.resolveRequiredPlaceholders);
/// ```
///
/// Spring (Java):
/// ```java
/// factory.addEmbeddedValueResolver(env::resolveRequiredPlaceholders);
/// ```
typedef StringValueResolver = String Function(String value);

/// Evaluates `#{...}` expressions in `@Value`, like Spring's
/// `BeanExpressionResolver`.
///
/// The application context installs the SpEL-based
/// `StandardBeanExpressionResolver`; a custom one can be set on the
/// factory.
///
/// ```dart
/// class UpperCaseResolver implements BeanExpressionResolver {
///   @override
///   Object? evaluate(String value, BeanFactory beanFactory) =>
///       value.replaceAll('#{', '').replaceAll('}', '').toUpperCase();
/// }
///
/// factory.beanExpressionResolver = UpperCaseResolver();
/// ```
///
/// Spring (Java):
/// ```java
/// factory.setBeanExpressionResolver(
///     new StandardBeanExpressionResolver(classLoader));
/// ```
abstract interface class BeanExpressionResolver {
  /// Evaluates [value] (which contains `#{...}`, placeholders already
  /// resolved); beans are accessible through [beanFactory].
  Object? evaluate(String value, BeanFactory beanFactory);
}

/// Configuration of a bean factory, like Spring's
/// `ConfigurableBeanFactory`.
///
/// ```dart
/// final factory = context.beanFactory
///   ..addBeanPostProcessor(TimingPostProcessor())
///   ..registerScope('screen', SimpleMapScope());
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurableListableBeanFactory factory = context.getBeanFactory();
/// factory.addBeanPostProcessor(new TimingPostProcessor());
/// factory.registerScope("screen", new SimpleThreadScope());
/// ```
abstract interface class ConfigurableBeanFactory
    implements HierarchicalBeanFactory, SingletonBeanRegistry {
  /// Sets the parent factory used for lookups that fail locally.
  set parentBeanFactory(BeanFactory? parent);

  /// Converts `@Value` results; defaults to the shared
  /// `DefaultConversionService`.
  ConversionService get conversionService;

  /// Replaces the conversion service used for `@Value` results.
  set conversionService(ConversionService value);

  /// Adds a resolver applied to `@Value` strings (placeholders).
  void addEmbeddedValueResolver(StringValueResolver resolver);

  /// Whether at least one embedded value resolver is registered.
  bool get hasEmbeddedValueResolver;

  /// Applies the embedded value resolvers to [value].
  String resolveEmbeddedValue(String value);

  /// Evaluates `#{...}` in `@Value`; `null` leaves them unevaluated.
  BeanExpressionResolver? get beanExpressionResolver;

  /// Sets the resolver for `#{...}` expressions.
  set beanExpressionResolver(BeanExpressionResolver? resolver);

  /// Adds [processor] (moving it to the end if already present); it
  /// applies to beans created afterwards, in the order added.
  void addBeanPostProcessor(BeanPostProcessor processor);

  /// Number of registered bean post-processors.
  int get beanPostProcessorCount;

  /// Registers a custom [scope] under [name] for `@Scope(name)` beans. The
  /// built-in `singleton` and `prototype` cannot be replaced.
  ///
  /// ```dart
  /// factory.registerScope('screen', SimpleMapScope());
  /// ```
  void registerScope(String name, CustomScope scope);

  /// Names of the registered custom scopes.
  List<String> get registeredScopeNames;

  /// The custom scope registered as [name], or `null`.
  CustomScope? getRegisteredScope(String name);

  /// Records that [dependentBeanName] depends on [beanName] (destroyed
  /// first).
  void registerDependentBean(String beanName, String dependentBeanName);

  /// Names of the beans that depend on [beanName].
  List<String> getDependentBeans(String beanName);

  /// Names of the beans [beanName] depends on.
  List<String> getDependenciesForBean(String beanName);

  /// Whether [beanName] is being created right now (on the creation
  /// stack).
  bool isCurrentlyInCreation(String beanName);

  /// Whether the bean named [name] is a `FactoryBean` (here or in a
  /// parent); throws `NoSuchBeanDefinitionException` when unknown. Spring:
  /// `isFactoryBean(String)`.
  bool isFactoryBean(String name);

  /// Destroys all singletons, dependents first. Requesting a singleton
  /// that does not exist yet meanwhile (e.g. from a destroy callback)
  /// throws `BeanCreationNotAllowedException`.
  void destroySingletons();

  /// Errors thrown by destroy callbacks during the last
  /// [destroySingletons] (and by `destroyBean`); they are logged as
  /// warnings and do not stop the shutdown.
  List<Object> get destructionErrors;

  /// Destroys the scoped instance named [name] in its custom scope.
  void destroyScopedBean(String name);
}

/// Injection into objects the container did not create, like Spring's
/// `AutowireCapableBeanFactory`.
///
/// ```dart
/// @Configurable()
/// class ProfileScreenState extends State<ProfileScreen> {
///   @Autowired()
///   late final ProfileService profiles;
///
///   @override
///   void initState() {
///     super.initState();
///     appContext.autowireCapableBeanFactory.autowireBean(this);
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// context.getAutowireCapableBeanFactory().autowireBean(existingObject);
/// ```
///
/// Unlike Spring, only `@Configurable` classes can be autowired (their
/// injection code is generated).
abstract interface class AutowireCapableBeanFactory implements BeanFactory {
  /// Injects the `@Autowired` / `@Value` members of [existingBean], whose
  /// class must be `@Configurable`.
  void autowireBean(Object existingBean);

  /// Runs aware callbacks, post-processors, the `@PostConstruct` methods of
  /// a `@Configurable` class and `InitializingBean.afterPropertiesSet` for
  /// [existingBean]; returns the (possibly wrapped) bean.
  Object initializeBean(Object existingBean, String beanName);

  /// Destroys [existingBean]: destruction-aware post-processors, the
  /// `@PreDestroy` methods of a `@Configurable` class and
  /// `DisposableBean.destroy`. With [beanName], the destroy callbacks of
  /// that bean definition run instead (e.g. for a prototype instance).
  /// Errors are logged and collected in `destructionErrors`.
  ///
  /// Spring: `AutowireCapableBeanFactory.destroyBean(Object)`; with a name,
  /// `ConfigurableBeanFactory.destroyBean(String, Object)` (one method
  /// here: Dart has no overloads).
  void destroyBean(Object existingBean, {String? beanName});
}

/// Everything a bean factory offers, like Spring's
/// `ConfigurableListableBeanFactory`.
///
/// This is what `BeanFactoryPostProcessor`s receive and what
/// `ConfigurableApplicationContext.beanFactory` returns.
///
/// ```dart
/// final factory = context.beanFactory;
/// factory.getBeanDefinition('reports').lazy = true;
/// factory.registerResolvableDependency(Clock, SystemClock());
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurableListableBeanFactory factory = context.getBeanFactory();
/// factory.getBeanDefinition("reports").setLazyInit(true);
/// factory.registerResolvableDependency(Clock.class, Clock.systemUTC());
/// ```
abstract interface class ConfigurableListableBeanFactory
    implements
        ListableBeanFactory,
        ConfigurableBeanFactory,
        AutowireCapableBeanFactory {
  /// The definition named [name] (or alias), mutable for post-processors;
  /// throws `NoSuchBeanDefinitionException` if unknown.
  BeanDefinition<Object> getBeanDefinition(String name);

  /// Makes [value] injectable as [type] without being a named bean, like
  /// Spring's `registerResolvableDependency` (used for the bean factory and
  /// the application context themselves).
  void registerResolvableDependency(Type type, Object value);

  /// Validates the bean graph (missing, ambiguous, cyclic dependencies and
  /// unresolvable `@Value` placeholders) without creating beans.
  ///
  /// Uses the definitions' declared [Dependency] lists and `dependsOn`.
  /// Spring has no equivalent: it finds such problems only while creating
  /// beans.
  ///
  /// ```dart
  /// factory
  ///   ..validateBeanGraph() // throws e.g. BeanCurrentlyInCreationException
  ///   ..preInstantiateSingletons();
  /// ```
  void validateBeanGraph();

  /// Creates all non-lazy singletons, then calls
  /// `SmartInitializingSingleton.afterSingletonsInstantiated`.
  ///
  /// The application context calls this at the end of `refresh()`. Spring:
  /// `preInstantiateSingletons()`.
  void preInstantiateSingletons();

  /// Marks the definitions as final for now, so lookups by type may be
  /// cached. Like in Spring this is a hint: registering or removing
  /// definitions afterwards still works and clears the caches.
  void freezeConfiguration();

  /// Whether [freezeConfiguration] has been called.
  bool get isConfigurationFrozen;
}

/// The API used by generated code (and hand-written definitions) to obtain
/// dependencies of a bean while it is being created.
///
/// It is the argument of `BeanDefinition`'s `create` and `inject`
/// callbacks. Lookups made through it record dependent beans (for
/// destruction order) and report the bean being created in errors.
///
/// Injection points are resolved like Spring's `resolveDependency`: the
/// candidates are the autowire candidates of this factory and its parents
/// (a parent bean is hidden by a local bean with the same name); without a
/// qualifier only default candidates count. The bean being created and the
/// beans of its own `@Bean` methods are left out (for a single bean only
/// when nothing else matches). Among several candidates the winner is the
/// single `@Primary` one (a local one beats a parent's; two at the same
/// level are ambiguous), else the only non-`@Fallback` one, else the one
/// whose name or alias equals the parameter name, then the `@Qualifier`
/// value, else the only default candidate. A failure while the bean is
/// being created is thrown as an `UnsatisfiedDependencyException` naming
/// the bean and the injection point.
///
/// ```dart
/// BeanDefinition<OrderService>(
///   name: 'orderService',
///   create: (r) => OrderService(
///     r.dependency<OrderRepository>(name: 'repository'),
///     r.dependencyList<OrderListener>(),
///     r.optionalDependency<Clock>(),
///     r.value<int>(r'${orders.limit:100}'),
///   ),
/// );
/// ```
///
/// Spring (Java): no public counterpart; the equivalent work is done by
/// reflection in `AutowiredAnnotationBeanPostProcessor` and
/// `DefaultListableBeanFactory.resolveDependency(...)`:
/// ```java
/// @Service
/// class OrderService {
///   OrderService(OrderRepository repository, List<OrderListener> listeners,
///       Optional<Clock> clock, @Value("${orders.limit:100}") int limit) {}
/// }
/// ```
abstract interface class DependencyResolver
    implements ConfigurableListableBeanFactory {
  /// A required dependency. [name] is the parameter or field name, used as
  /// a qualifier when several candidates remain (like Spring).
  ///
  /// ```dart
  /// create: (r) => Mailer(r.dependency<Transport>(qualifier: 'smtp')),
  /// ```
  T dependency<T extends Object>({String? qualifier, String? name});

  /// An optional dependency: `null` when no bean matches.
  T? optionalDependency<T extends Object>({String? qualifier, String? name});

  /// All matching beans, sorted by `PriorityOrdered` / `Ordered` /
  /// `@Order`; throws when there are none.
  List<T> dependencyList<T extends Object>({String? qualifier});

  /// All matching beans, sorted; `null` when there are none.
  List<T>? optionalDependencyList<T extends Object>({String? qualifier});

  /// All matching beans by name, in registration order (like Spring, only
  /// lists are sorted; a `Set` is built from these values); throws when
  /// there are none.
  Map<String, T> dependencyMap<T extends Object>({String? qualifier});

  /// All matching beans by name, in registration order; `null` when there
  /// are none.
  Map<String, T>? optionalDependencyMap<T extends Object>({String? qualifier});

  /// A lazy provider resolving on behalf of the bean being created now:
  /// [name] is the parameter or field name (see `ObjectProvider`).
  ///
  /// ```dart
  /// create: (r) => Loud(r.provider<Greeter>(name: 'delegate')),
  /// ```
  ObjectProvider<T> provider<T extends Object>({
    String? qualifier,
    String? name,
  });

  /// A function resolving the bean of [T] each time it is called, as if
  /// it were injected into the bean being created now (`@Lazy` injection
  /// points: the generated lazy proxy calls it on every member access).
  ///
  /// ```dart
  /// create: (r) => BookService(_$BookServiceLazy(r.lazyDependency<BookService>())),
  /// ```
  T Function() lazyDependency<T extends Object>({
    String? qualifier,
    String? name,
  });

  /// A `@Value` expression converted to [T]: `${...}` placeholders are
  /// resolved, then `#{...}` is evaluated, then the result is converted.
  ///
  /// ```dart
  /// final port = r.value<int>(r'${server.port:8080}');
  /// ```
  T value<T>(String expression);

  /// A `@Value` expression; `null` when a placeholder has no value.
  T? optionalValue<T>(String expression);
}
