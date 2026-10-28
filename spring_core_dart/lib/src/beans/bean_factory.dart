import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/object_provider.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';

/// The read side of the container: it hands out beans by type or by name
/// and answers questions about them without creating them.
///
/// Inside beans, constructor injection is the normal way to get other
/// beans. You ask a `BeanFactory` directly when injection cannot help: in
/// `main` after the context has started, in a test, or in a class that
/// only learns at run time which bean it needs. The application context is
/// a `BeanFactory`, and a bean can have one injected.
///
/// Lookups by type ([getBean], [findBean]) can be narrowed by a qualifier:
/// a bean name, an alias or a `@Qualifier` value. Factories form a
/// hierarchy: what is not found here is looked up in the parent.
///
/// ```dart
/// // main: start the context, then take the entry points out of it.
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
  /// Put before a bean name (`&client`) to get a `FactoryBean` itself
  /// instead of the object it produces.
  static const factoryBeanPrefix = '&';

  /// The bean of type [T], created if it does not exist yet. With
  /// [qualifier], only the bean with that name, alias or `@Qualifier` value.
  ///
  /// When several beans match, the winner is the single `@Primary` one,
  /// else the only one not marked `@Fallback`, else the one whose name or
  /// alias is [qualifier], else the one with the lowest jakarta
  /// `@Priority`, else the only default candidate. Like Spring's
  /// `getBean(Class)`, beans that are not autowire candidates count only
  /// when they are the only matches, and a qualifier can select any bean.
  /// This factory's beans are looked up first, then the objects of
  /// `registerResolvableDependency` (Spring's `getBean` ignores those),
  /// then the parent.
  ///
  /// Throws `NoSuchBeanDefinitionException` when nothing matches (a bean
  /// whose `@Bean` method returned `null` counts as missing) and
  /// `NoUniqueBeanDefinitionException` when several match and none wins.
  ///
  /// ```dart
  /// // Two Greeter beans; this one is wanted.
  /// final greeter = factory.getBean<Greeter>(qualifier: 'french');
  /// ```
  ///
  /// Spring: `getBean(Class)`; with a qualifier, `getBean(name, Class)` or
  /// `BeanFactoryAnnotationUtils.qualifiedBeanOfType`.
  T getBean<T extends Object>({String? qualifier});

  /// Like [getBean], but returns `null` when no bean matches, for a
  /// collaborator the caller can do without. Still throws
  /// `NoUniqueBeanDefinitionException` when several match and none wins.
  /// Spring: `getBeanProvider(T).getIfAvailable()`.
  T? findBean<T extends Object>({String? qualifier});

  /// The bean registered under [name] or one of its aliases, created if
  /// needed; looks in the parent when the name is not known here.
  ///
  /// For a `FactoryBean`, `name` gives its product and `&name` the factory
  /// itself. A bean whose `@Bean` method returned `null` gives a
  /// `NullBean`. Throws `NoSuchBeanDefinitionException` for an unknown
  /// name and `BeanIsNotAFactoryException` for `&name` of a bean that is
  /// not a factory. Spring: `getBean(String)`.
  ///
  /// ```dart
  /// final product = factory.getBeanByName('client');
  /// final factoryBean = factory.getBeanByName('&client');
  /// ```
  Object getBeanByName(String name);

  /// A handle on the beans of [T] that creates nothing until it is used.
  ///
  /// Use it to look a bean up later or repeatedly, to accept that it is
  /// missing (`getIfAvailable`), or to go through all of them
  /// (`orderedList`). With [qualifier], only the beans it selects. This
  /// provider is a plain lookup: `getObject` behaves like [getBean], and
  /// listing includes every bean of [T], also from parent factories and
  /// those that are not autowire candidates.
  ///
  /// ```dart
  /// final all = factory.getBeanProvider<Greeter>().orderedList();
  /// ```
  ObjectProvider<T> getBeanProvider<T extends Object>({String? qualifier});

  /// Whether a bean or alias named [name] exists here or in a parent
  /// (`&name` only for a factory bean). Creates nothing.
  bool containsBean(String name);

  /// Whether injecting [type] would find a bean, without creating any.
  ///
  /// Counts the autowire candidates of [type] (without [qualifier] only
  /// default candidates, with it the beans it selects), the objects of
  /// `registerResolvableDependency` when there is no qualifier, and, with
  /// [includeAncestors] (the default), the parent's beans.
  /// `@ConditionalOnBean` and `@ConditionalOnMissingBean` are decided with
  /// it, like Spring Boot's `OnBeanCondition`.
  bool containsBeanOfType(
    Type type, {
    String? qualifier,
    bool includeAncestors = true,
  });

  /// Whether the bean named [name] can be used as a [type], judged from the
  /// types its definition declares, without creating it.
  ///
  /// `&name` asks about a factory bean itself, `name` about its product;
  /// every bean matches `Object`. Throws `NoSuchBeanDefinitionException`
  /// when there is no such bean. Spring: `isTypeMatch(String, Class)`.
  ///
  /// ```dart
  /// factory.isTypeMatch('english', Greeter); // true
  /// ```
  bool isTypeMatch(String name, Type type);

  /// Whether the bean named [name] is one shared instance. For a
  /// `FactoryBean`, whether its product is shared (this creates the
  /// factory); `&name` asks about the factory itself. Throws
  /// `NoSuchBeanDefinitionException` for an unknown name.
  bool isSingleton(String name);

  /// Whether every lookup of the bean named [name] creates a new instance.
  /// For a `FactoryBean`, whether its product is created per lookup (this
  /// creates the factory); `&name` asks about the factory itself. A bean in
  /// a custom scope is neither a singleton nor a prototype. Throws
  /// `NoSuchBeanDefinitionException` for an unknown name.
  bool isPrototype(String name);

  /// The type of the bean named [name], without creating it: the declared
  /// class (or what a `SmartInstantiationAwareBeanPostProcessor` predicts),
  /// the product type for a factory bean (`&name`: the factory's class),
  /// the runtime type of an object added with `registerSingleton`. `null`
  /// when no bean has that name.
  Type? getType(String name);

  /// The other names of the bean named [name]: its aliases, plus its bean
  /// name when [name] is itself an alias. Empty when there are none or no
  /// bean has that name.
  List<String> getAliases(String name);
}

/// A bean factory with a parent: what it cannot find among its own beans,
/// it looks up in the parent.
///
/// A parent lets separate parts of a program share common beans (a
/// database, a clock) while each part keeps beans of its own: the child
/// sees the parent's beans, the parent does not see the child's. Most
/// applications have a single context and never set a parent.
///
/// ```dart
/// // A feature module gets its own factory on top of the shared one.
/// final shared = DefaultListableBeanFactory();
/// final feature = DefaultListableBeanFactory(parentBeanFactory: shared);
/// feature.containsBean('clock');      // true if the shared factory has it
/// feature.containsLocalBean('clock'); // false
/// ```
///
/// Spring (Java):
/// ```java
/// DefaultListableBeanFactory child = new DefaultListableBeanFactory(parent);
/// child.containsBean("fromParent");
/// child.containsLocalBean("fromParent");
/// ```
abstract interface class HierarchicalBeanFactory implements BeanFactory {
  /// The factory consulted when a lookup finds nothing here; `null` for a
  /// root factory.
  BeanFactory? get parentBeanFactory;

  /// Whether this factory itself, ignoring the parent, has a bean or alias
  /// named [name] (`&name` only for a factory bean).
  bool containsLocalBean(String name);
}

/// A bean factory that can list its beans: all names, the beans of a type,
/// the beans carrying an annotation.
///
/// [BeanFactory.getBean] wants one bean. Listing is for code that handles
/// every bean of a kind, such as a framework that registers each handler
/// bean or a report of all beans with an annotation. In an application,
/// injecting a `List<T>` usually does the same with less code. Except for
/// [getSortedBeans], only this factory's own beans are listed, not the
/// parent's; `BeanFactoryUtils` adds the ancestors.
///
/// ```dart
/// // Log which beans implement Greeter, then use all of them in order.
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
  /// Whether a definition is registered here under exactly [name]. Aliases,
  /// parent beans and objects added with `registerSingleton` do not count.
  bool containsBeanDefinition(String name);

  /// How many definitions are registered here (objects added with
  /// `registerSingleton` are not counted).
  int get beanDefinitionCount;

  /// The names of the definitions registered here, in registration order.
  /// Objects added with `registerSingleton` are not definitions and are not
  /// listed.
  List<String> get beanDefinitionNames;

  /// The names of this factory's beans that can be used as [type], in
  /// registration order: definitions first, then objects added with
  /// `registerSingleton`. Creates no bean.
  ///
  /// A `FactoryBean` matched by its own type is listed as `&name`, matched
  /// by its product type as `name`. With [includeNonSingletons] `false`,
  /// only singletons are listed.
  List<String> getBeanNamesForType(
    Type type, {
    bool includeNonSingletons = true,
  });

  /// This factory's beans of [T] by name, in the order of
  /// [getBeanNamesForType]; creates those that do not exist yet. A bean
  /// whose `@Bean` method returned `null` is left out.
  Map<String, T> getBeansOfType<T extends Object>({
    bool includeNonSingletons = true,
  });

  /// Every bean of [T] here and in the parent factories, sorted to be used
  /// in order: `PriorityOrdered` beans first, then by `Ordered.order`,
  /// `@Order` or jakarta `@Priority` (lower first), then by registration.
  ///
  /// A bean hides a parent's bean with the same name. Beans that are not
  /// autowire candidates are included, like in Spring's
  /// `getBeanProvider(T).orderedStream()`; null beans are not. With
  /// [qualifier], only the beans it selects. Creates the beans.
  List<T> getSortedBeans<T extends Object>({String? qualifier});

  /// The names of this factory's definitions whose class (for a `@Bean`
  /// method: the method or the returned class) carries an annotation of
  /// type [A] or of a subclass of [A], so asking for `Component` also
  /// finds `@Service` beans. Creates no bean. Spring:
  /// `getBeanNamesForAnnotation`.
  ///
  /// ```dart
  /// // Every service bean, e.g. to list them on an admin page.
  /// final services = factory.getBeanNamesForAnnotation<Service>();
  /// ```
  List<String> getBeanNamesForAnnotation<A extends Object>();

  /// The beans named by [getBeanNamesForAnnotation], by name; creates them.
  /// Spring: `getBeansWithAnnotation`.
  Map<String, Object> getBeansWithAnnotation<A extends Object>();

  /// The first annotation of type [A] on the class (or `@Bean` method) of
  /// the bean named [beanName], or `null`. Creates no bean. Looks in the
  /// parent when the bean is not known here, and throws
  /// `NoSuchBeanDefinitionException` when no factory has it. Spring:
  /// `findAnnotationOnBean`.
  ///
  /// ```dart
  /// final order = factory.findAnnotationOnBean<Order>('english')?.value;
  /// ```
  A? findAnnotationOnBean<A extends Object>(String beanName);
}

/// The write side of the container: where bean definitions are registered,
/// removed and given aliases.
///
/// The generated code registers an application's definitions, so
/// application code rarely calls it. It is for code that adds beans the
/// generator cannot know about: a `BeanDefinitionRegistryPostProcessor`
/// that registers one bean per entry of a configuration file, a test that
/// replaces a bean, or a container used without a context.
///
/// ```dart
/// // In a BeanDefinitionRegistryPostProcessor: add a clock bean that can
/// // also be found as 'systemClock'.
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
  /// Adds [definition] under its `name` and registers its `aliases`.
  ///
  /// A name already used by another definition or by an alias fails with
  /// `BeanDefinitionOverrideException`, unless overriding is allowed
  /// (`DefaultListableBeanFactory.allowBeanDefinitionOverriding`); the
  /// replaced bean's singleton is then destroyed. Registering again a
  /// definition with the same `source` (one module imported twice) does
  /// nothing. An object added with `registerSingleton` under the name is
  /// replaced, like in Spring. An empty name, or one starting with `&`,
  /// fails with `BeanDefinitionStoreException`. Works after
  /// `freezeConfiguration` too (lookup caches are cleared).
  ///
  /// Unlike Spring, the name is part of the definition
  /// (`BeanDefinition.name`).
  void registerBeanDefinition(BeanDefinition<Object> definition);

  /// Removes the definition named [name] (or reached through the alias
  /// [name]). Its singleton is destroyed first, after the beans that
  /// depend on it, and every alias leading to it is removed. Throws
  /// `NoSuchBeanDefinitionException` when there is no such definition.
  void removeBeanDefinition(String name);

  /// The definition registered as [name], as an alias of it, or as `&name`
  /// for a factory bean. Throws `NoSuchBeanDefinitionException` when
  /// unknown; objects added with `registerSingleton` have no definition.
  BeanDefinition<Object> getBeanDefinition(String name);

  /// Whether a definition is registered under exactly [name] (aliases do
  /// not count).
  bool containsBeanDefinition(String name);

  /// The names of all definitions, in registration order.
  List<String> get beanDefinitionNames;

  /// How many definitions are registered.
  int get beanDefinitionCount;

  /// Makes [alias] a second name of the bean [name]. Lookups by name,
  /// `@Qualifier` values and parameter names all match it.
  ///
  /// Throws `BeanDefinitionOverrideException` when [alias] is already a
  /// bean name, when it would lead back to itself, or when it is already
  /// an alias of another bean and bean definition overriding is not
  /// allowed. Registering a name as its own alias removes that alias.
  void registerAlias(String name, String alias);

  /// Removes [alias]; the bean keeps its name and its other aliases.
  /// Throws `ArgumentError` when [alias] is not registered.
  void removeAlias(String alias);

  /// Whether [name] is registered here as an alias rather than as a bean
  /// name.
  bool isAlias(String name);

  /// Whether [name] is taken here: by a bean, by an alias, or as the name
  /// of a bean others are recorded as depending on. Code that makes up bean
  /// names checks it to avoid clashes.
  bool isBeanNameInUse(String name);
}

/// The part of the container that accepts ready-made objects as beans.
///
/// Use it when an object exists before the container starts and should be
/// injectable: settings parsed in `main`, a connection opened by the
/// caller, a fake in a test. The container does not create, initialize or
/// destroy such an object; the caller owns it. Beans the container creates
/// itself are declared with annotations or bean definitions instead.
///
/// ```dart
/// // main built the clock; beans can now inject it as a Clock.
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
/// Spring finds the supertypes by reflection; here every type the object
/// should be found by must be listed in `types`.
abstract interface class SingletonBeanRegistry {
  /// Registers [singleton] under [name]. It is found by that name and by
  /// the [types] listed, which default to its runtime type only, so list
  /// every type it should be injected as.
  ///
  /// No injection, init or destroy callback runs for it, and it is not a
  /// bean definition (not in `beanDefinitionNames`), like in Spring. A
  /// `FactoryBean` is dereferenced: [name] gives its product (found by its
  /// `objectType`), `&name` the factory. Works after
  /// `freezeConfiguration`. Throws `BeanDefinitionOverrideException` when
  /// [name] is already a bean name or alias.
  void registerSingleton(String name, Object singleton, {List<Type>? types});

  /// The singleton named [name] (or an alias) if it has been created or
  /// registered, else `null`; never creates it. For a factory bean this is
  /// the factory, not its product.
  Object? getSingleton(String name);

  /// Whether the singleton named [name] (or an alias) exists already,
  /// created or registered.
  bool containsSingleton(String name);

  /// The names of the singletons that exist so far, created or registered.
  List<String> get singletonNames;
}

/// A function that resolves the `${...}` placeholders in a string and
/// returns the result.
///
/// The bean factory runs its resolvers over every `@Value` expression
/// before evaluating it. An application context adds one that reads the
/// environment, so you add one yourself only for a factory used without a
/// context, or to support another placeholder syntax.
///
/// ```dart
/// // A bare factory: @Value placeholders come from this environment.
/// factory.addEmbeddedValueResolver(env.resolveRequiredPlaceholders);
/// ```
///
/// Spring (Java):
/// ```java
/// factory.addEmbeddedValueResolver(env::resolveRequiredPlaceholders);
/// ```
typedef StringValueResolver = String Function(String value);

/// Evaluates the `#{...}` expressions of `@Value` strings, after their
/// `${...}` placeholders are resolved.
///
/// An application context installs the SpEL-based
/// `StandardBeanExpressionResolver`, so `@Value('#{...}')` works without
/// setup. Implement this interface only to evaluate expressions in another
/// way; set the standard one yourself on a factory used without a context.
///
/// ```dart
/// // A bare factory gets SpEL in @Value, as in a context.
/// factory.beanExpressionResolver = StandardBeanExpressionResolver();
///
/// // Or a resolver of your own: "#{name}" reads a feature flag.
/// class FlagResolver implements BeanExpressionResolver {
///   FlagResolver(this.flags);
///   final Map<String, bool> flags;
///
///   @override
///   Object? evaluate(String value, BeanFactory beanFactory) =>
///       value.startsWith('#{') && value.endsWith('}')
///           ? flags[value.substring(2, value.length - 1)]
///           : value;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// factory.setBeanExpressionResolver(
///     new StandardBeanExpressionResolver(classLoader));
/// ```
abstract interface class BeanExpressionResolver {
  /// The value of [value], a `@Value` string whose placeholders are
  /// already resolved and which may contain `#{...}`; a string without an
  /// expression is returned as it is. Other beans are reachable through
  /// [beanFactory]. The result is then converted to the injection point's
  /// type.
  Object? evaluate(String value, BeanFactory beanFactory);
}

/// The settings side of a bean factory: parent, conversion, `@Value`
/// resolution, bean post-processors, custom scopes, dependency records and
/// shutdown.
///
/// An application context sets all of this up while it starts. You use it
/// from code that extends the container: a library that adds a custom
/// scope or a post-processor, a test, or a factory used without a context.
/// `context.beanFactory` returns it (as the
/// [ConfigurableListableBeanFactory] that includes it).
///
/// ```dart
/// // Time every bean's creation, and give a Flutter app a 'screen' scope.
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
  @override
  BeanFactory? get parentBeanFactory;

  /// Sets the factory consulted when a lookup finds nothing here; `null`
  /// makes this a root factory. Set it before beans are resolved: cached
  /// selections are cleared, beans already injected keep what they got.
  set parentBeanFactory(BeanFactory? parent);

  /// Converts the result of a `@Value` expression to the injection point's
  /// type (the string `'8080'` to an `int`, say). Defaults to the shared
  /// `DefaultConversionService`; an application context uses its
  /// environment's.
  ConversionService get conversionService;

  /// Replaces the conversion service used for `@Value` results, for
  /// example with one that knows the application's own value types.
  set conversionService(ConversionService value);

  /// Adds [resolver] to the chain run over every `@Value` string to resolve
  /// its `${...}` placeholders. Resolvers run in the order added, each on
  /// the previous one's result. An application context adds the
  /// environment's.
  void addEmbeddedValueResolver(StringValueResolver resolver);

  /// Whether any placeholder resolver was added; without one, `${...}`
  /// stays as written.
  bool get hasEmbeddedValueResolver;

  /// Runs every added resolver over [value], in order, and returns the
  /// result ([value] itself when there is none). Throws what a resolver
  /// throws, e.g. for a placeholder that has no value.
  String resolveEmbeddedValue(String value);

  /// Evaluates the `#{...}` part of `@Value` strings. `null`, the default
  /// of a bare factory, leaves them as written; an application context
  /// sets the SpEL resolver.
  BeanExpressionResolver? get beanExpressionResolver;

  /// Installs the resolver of `#{...}` expressions, or removes it with
  /// `null`.
  set beanExpressionResolver(BeanExpressionResolver? resolver);

  /// Adds [processor] to the chain applied to every bean created from now
  /// on, after the ones already added; adding one again moves it to the
  /// end. Beans that exist already are not processed. An application
  /// context adds the post-processor beans itself; call this on a bare
  /// factory, or for a processor that is not a bean.
  void addBeanPostProcessor(BeanPostProcessor processor);

  /// How many bean post-processors are registered.
  int get beanPostProcessorCount;

  /// Makes [alias] a second name of the bean [name]: lookups by name,
  /// `@Qualifier` values and parameter names match it. Throws
  /// `BeanDefinitionOverrideException` when [alias] is already a bean name,
  /// or an alias of another bean while overriding is not allowed. Spring:
  /// `ConfigurableBeanFactory.registerAlias`.
  ///
  /// ```dart
  /// // A library expects 'primaryDb'; the application named it 'dataSource'.
  /// context.beanFactory.registerAlias('dataSource', 'primaryDb');
  /// ```
  void registerAlias(String name, String alias);

  /// Registers [scope] under [name], so beans declared with `@Scope(name)`
  /// get their instances from it.
  ///
  /// Register it before such a bean is first looked up: the lookup of a
  /// bean whose scope is not registered throws
  /// `ScopeNotRegisteredException`. Registering a name again replaces the
  /// scope. Throws `ArgumentError` for the built-in `singleton` and
  /// `prototype`.
  ///
  /// ```dart
  /// factory.registerScope('screen', SimpleMapScope());
  /// ```
  void registerScope(String name, CustomScope scope);

  /// The names of the custom scopes registered so far (not `singleton` or
  /// `prototype`).
  List<String> get registeredScopeNames;

  /// The custom scope registered under [name], or `null` (also for
  /// `singleton` and `prototype`).
  CustomScope? getRegisteredScope(String name);

  /// Records that the bean [dependentBeanName] uses the bean [beanName], so
  /// it is destroyed before it. The container records this itself for
  /// every injection and `@DependsOn`; call it for a dependency it cannot
  /// see, such as a bean looked up by name inside a method.
  void registerDependentBean(String beanName, String dependentBeanName);

  /// The names of the beans recorded as using [beanName]; they are
  /// destroyed before it.
  List<String> getDependentBeans(String beanName);

  /// The names of the beans [beanName] is recorded as using.
  List<String> getDependenciesForBean(String beanName);

  /// Whether [beanName] is being created right now: its creation has
  /// started and not finished. A post-processor can check it to avoid
  /// asking for a bean that is still being built.
  bool isCurrentlyInCreation(String beanName);

  /// Whether the bean named [name] is a `FactoryBean` (here or in a
  /// parent), without creating it. Throws `NoSuchBeanDefinitionException`
  /// when no bean has that name. Spring: `isFactoryBean(String)`.
  bool isFactoryBean(String name);

  /// Destroys every singleton the factory created, in reverse creation
  /// order and each after the beans that depend on it, then forgets them.
  /// Objects added with `registerSingleton` are kept and not destroyed. An
  /// application context calls it on `close()`.
  ///
  /// A destroy callback that throws does not stop the shutdown: the error
  /// is logged as a warning and kept in [destructionErrors]. A destroy
  /// callback that returns a `Future` is not awaited: a warning is logged
  /// (and an error recorded) and the shutdown goes on; use
  /// [destroySingletonsAsync] to await it. Asking for a singleton that does
  /// not exist yet while this runs (e.g. from a destroy callback) throws
  /// `BeanCreationNotAllowedException`.
  void destroySingletons();

  /// Like [destroySingletons], but awaits the destroy callbacks that return
  /// a `Future` (`@PreDestroy`, `DisposableBean.destroy`, the destroy
  /// method): each bean's callbacks one after another, each bean after its
  /// dependents. The application context's `closeAsync()` calls this.
  Future<void> destroySingletonsAsync();

  /// The errors thrown by destroy callbacks during the last
  /// [destroySingletons] or [destroySingletonsAsync], and by `destroyBean`
  /// and [destroyScopedBean] since. Each was also logged as a warning; none
  /// stopped the shutdown.
  List<Object> get destructionErrors;

  /// Removes the current instance of the bean [name] from its custom scope
  /// and runs its destroy callbacks, for example when one screen closes
  /// while its scope goes on. Does nothing when the scope holds no
  /// instance. Throws `ArgumentError` when the bean is not in a custom
  /// scope and `NoSuchBeanDefinitionException` when no bean has that name.
  void destroyScopedBean(String name);
}

/// The part of the container that injects and initializes objects it did
/// not create.
///
/// Some objects are built by someone else: Flutter creates `State`
/// objects, a plugin system creates its handlers. When such an object
/// needs beans, mark its class `@Configurable()` (the generator then
/// writes its injection code) and hand the object to [autowireBean].
/// Objects the container creates itself never need this.
///
/// ```dart
/// // Flutter made this State; the container fills in its service.
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
  /// Injects the `@Autowired` and `@Value` members of [existingBean]. Its
  /// exact runtime class must be `@Configurable` and its module registered;
  /// otherwise throws `ArgumentError`. Init callbacks do not run: call
  /// [initializeBean] for those.
  void autowireBean(Object existingBean);

  /// Runs on [existingBean] what the container runs on its own beans after
  /// injection: the aware callbacks, the post-processors, the
  /// `@PostConstruct` methods of a `@Configurable` class and
  /// `InitializingBean.afterPropertiesSet`. [beanName] is the name those
  /// callbacks receive. Returns the object to use from now on, which a
  /// post-processor may have wrapped.
  Object initializeBean(Object existingBean, String beanName);

  /// Runs the destroy callbacks of [existingBean]: destruction-aware
  /// post-processors, the `@PreDestroy` methods of a `@Configurable` class
  /// and `DisposableBean.destroy`. With [beanName], the destroy callbacks
  /// of that bean definition run instead, for example to release a
  /// prototype instance, which the container never destroys by itself.
  /// Errors are logged and collected in `destructionErrors`.
  ///
  /// Spring: `AutowireCapableBeanFactory.destroyBean(Object)`; with a name,
  /// `ConfigurableBeanFactory.destroyBean(String, Object)` (one method
  /// here: Dart has no overloads).
  void destroyBean(Object existingBean, {String? beanName});
}

/// The container's full control: besides handing out beans, it lets code
/// change bean definitions and the container's setup before any bean is
/// created.
///
/// Most applications never need it: beans are declared with annotations
/// and the generator registers them. It is for code that adjusts the
/// container itself, such as a library that makes some beans lazy,
/// registers an object that is not a bean as injectable, or checks the
/// bean graph. That code gets it in a [BeanFactoryPostProcessor] (called
/// after the definitions are registered, before beans are created).
///
/// ```dart
/// // The slow `reports` bean starts on first use, not at startup.
/// @Component()
/// class LazyReports implements BeanFactoryPostProcessor {
///   @override
///   void postProcessBeanFactory(ConfigurableListableBeanFactory factory) {
///     factory.getBeanDefinition('reports').lazy = true;
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class LazyReports implements BeanFactoryPostProcessor {
///   @Override
///   public void postProcessBeanFactory(
///       ConfigurableListableBeanFactory factory) {
///     factory.getBeanDefinition("reports").setLazyInit(true);
///   }
/// }
/// ```
abstract interface class ConfigurableListableBeanFactory
    implements
        ListableBeanFactory,
        ConfigurableBeanFactory,
        AutowireCapableBeanFactory {
  /// The definition registered as [name] (or an alias, or `&name`), to read
  /// or change. Its mutable fields (`scope`, `lazy`, `primary`,
  /// `fallback`, `autowireCandidate`, ...) apply to beans created
  /// afterwards. Throws `NoSuchBeanDefinitionException` when unknown.
  BeanDefinition<Object> getBeanDefinition(String name);

  /// Makes [value] injectable wherever exactly [type] is asked for, without
  /// making it a bean: it has no name, is not listed, and is used only when
  /// no bean of [type] matches and the point has no qualifier. The
  /// application context registers its bean factory and itself this way, so
  /// they can be injected. Spring: `registerResolvableDependency`.
  void registerResolvableDependency(Type type, Object value);

  /// Checks the whole bean graph without creating any bean, so a
  /// configuration error fails at startup instead of on first use.
  ///
  /// Every required dependency must resolve to one bean, every required
  /// `@Value` placeholder must have a value, every `@DependsOn` name must
  /// exist, and no beans may depend on each other in a cycle. The first
  /// problem is thrown: an `UnsatisfiedDependencyException` naming the bean
  /// and the injection point, a `NoSuchBeanDefinitionException` for a
  /// missing `@DependsOn` bean, or a `BeanCurrentlyInCreationException`
  /// with the cycle. Providers, `@Lazy` points and scoped proxies are
  /// resolved later, so they never close a cycle.
  ///
  /// It reads the [Dependency] lists the generator writes into each
  /// definition, and `dependsOn`; a hand-written definition without them
  /// is not checked. The application context calls it during refresh,
  /// after the factory post-processors and before the singletons are
  /// created. Spring has no equivalent: it finds such problems only while
  /// creating beans.
  ///
  /// ```dart
  /// // A container without a context: fail before creating anything.
  /// factory
  ///   ..validateBeanGraph() // throws e.g. BeanCurrentlyInCreationException
  ///   ..preInstantiateSingletons();
  /// ```
  void validateBeanGraph();

  /// Creates every singleton that is not lazy, so failures show at startup
  /// rather than on first use, then calls
  /// `SmartInitializingSingleton.afterSingletonsInstantiated` on the beans
  /// that implement it. The product of a `SmartFactoryBean` whose
  /// `isEagerInit` is `true` is created too.
  ///
  /// The application context calls this at the end of `refresh()`. An init
  /// callback (`@PostConstruct`, `afterPropertiesSet`, the init method)
  /// that returns a `Future` makes it fail with a `BeanCreationException`
  /// naming the bean: use [preInstantiateSingletonsAsync] (the context's
  /// `refreshAsync()`) for those. Spring: `preInstantiateSingletons()`.
  void preInstantiateSingletons();

  /// Like [preInstantiateSingletons], but awaits the init callbacks that
  /// returned a `Future` (in creation order; a failure is a
  /// `BeanCreationException` of that bean) before
  /// `SmartInitializingSingleton.afterSingletonsInstantiated`. Only beans
  /// created up to this point may have asynchronous init callbacks: for a
  /// bean created later (lazy, prototype, scoped) they fail its creation.
  Future<void> preInstantiateSingletonsAsync();

  /// Declares that the definitions will not change any more, so the factory
  /// may cache which bean each lookup and injection point selects. The
  /// application context calls it before creating the singletons. Like in
  /// Spring it is only a hint: registering or removing definitions
  /// afterwards still works and clears the caches.
  void freezeConfiguration();

  /// Whether [freezeConfiguration] has been called.
  bool get isConfigurationFrozen;
}

/// The view of the container that a bean definition's `create` and
/// `inject` callbacks receive, to get the dependencies of the bean being
/// built.
///
/// The generator writes these calls for every injection point, so most
/// code never calls them. You write them yourself in hand-made bean
/// definitions, such as
/// `create: (r) => LowStockAlarm(r.dependency<StockService>())`. Lookups
/// made through it are recorded (the bean is destroyed before its
/// dependencies), and a failure while the bean is being created is thrown
/// as an `UnsatisfiedDependencyException` naming the bean and the
/// injection point.
///
/// Injection points are resolved like Spring's `resolveDependency`: the
/// candidates are the autowire candidates of this factory and its parents
/// (a parent bean is hidden by a local bean with the same name); without a
/// qualifier only default candidates count. The bean being created and the
/// beans of its own `@Bean` methods are left out (for a single bean only
/// when nothing else matches), so a `@Primary` decorator of `Greeter`
/// receives the other greeters. Among several candidates the winner is the
/// single `@Primary` one (a local one beats a parent's; two at the same
/// level are ambiguous), else the only non-`@Fallback` one, else the one
/// whose name or alias equals the parameter name, then the one named by
/// the `@Qualifier` value, then the one with the lowest jakarta
/// `@Priority`, else the only default candidate.
///
/// ```dart
/// // A hand-written definition for OrderService and its four
/// // dependencies.
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
  /// The bean of [T] for a required injection point. [qualifier] is the
  /// `@Qualifier` value; [name] is the parameter or field name, which picks
  /// the candidate whose name or alias equals it when several remain (like
  /// Spring). Throws when no bean, or no single winner, is found.
  ///
  /// ```dart
  /// create: (r) => Mailer(r.dependency<Transport>(qualifier: 'smtp')),
  /// ```
  T dependency<T extends Object>({String? qualifier, String? name});

  /// Like [dependency], for a nullable point: `null` when no bean matches
  /// (or the match is a null bean). Several candidates without a winner
  /// still throw.
  T? optionalDependency<T extends Object>({String? qualifier, String? name});

  /// Every matching bean of [T], for a `List<T>` point, sorted:
  /// `PriorityOrdered` first, then by `Ordered.order`, `@Order` or
  /// `@Priority`, then registration order. Includes the parents' beans.
  /// Throws when there is none.
  List<T> dependencyList<T extends Object>({String? qualifier});

  /// Like [dependencyList], but `null` when there is none.
  List<T>? optionalDependencyList<T extends Object>({String? qualifier});

  /// Every matching bean of [T] by bean name, for a `Map<String, T>` point,
  /// in registration order (this factory's beans first). Like in Spring,
  /// only lists are sorted; a `Set<T>` point is built from these values.
  /// Throws when there is none.
  Map<String, T> dependencyMap<T extends Object>({String? qualifier});

  /// Like [dependencyMap], but `null` when there is none.
  Map<String, T>? optionalDependencyMap<T extends Object>({String? qualifier});

  /// An `ObjectProvider<T>` for a provider injection point. Nothing is
  /// resolved now: each later call resolves as if [T] were injected into the
  /// bean being created now ([name] is the parameter or field name). Used
  /// for optional, late or multiple beans, and to break a cycle.
  ///
  /// ```dart
  /// create: (r) => Loud(r.provider<Greeter>(name: 'delegate')),
  /// ```
  ObjectProvider<T> provider<T extends Object>({
    String? qualifier,
    String? name,
  });

  /// A function that resolves the bean of [T] each time it is called, as if
  /// it were injected into the bean being created now. The generated proxy
  /// of a `@Lazy` injection point calls it on every member access, so the
  /// bean is found on first use and a cycle is broken.
  ///
  /// ```dart
  /// create: (r) => BookService(
  ///   _$BookServiceLazy(r.lazyDependency<BookService>()),
  /// ),
  /// ```
  T Function() lazyDependency<T extends Object>({
    String? qualifier,
    String? name,
  });

  /// The bean for a `@Resource` field or setter (from
  /// `package:spring_core_dart/jakarta.dart`): the bean named [name] (an
  /// alias or `&factory` too), as [T].
  ///
  /// With [fallbackToType], set when the annotation gives no name and
  /// [name] is the field or setter name, a bean of [T] is injected by type
  /// when no bean has that name, like Spring's
  /// `CommonAnnotationBeanPostProcessor`. Throws when the bean is missing.
  ///
  /// ```dart
  /// inject: (bean, r) =>
  ///     bean.dataSource =
  ///         r.resource<DataSource>('dataSource', fallbackToType: true),
  /// ```
  T resource<T extends Object>(String name, {bool fallbackToType = false});

  /// Like [resource], for a nullable point: `null` when the bean is
  /// missing.
  T? optionalResource<T extends Object>(
    String name, {
    bool fallbackToType = false,
  });

  /// The value of a `@Value` [expression] as [T]: the `${...}` placeholders
  /// are resolved, then `#{...}` is evaluated, then the result is converted
  /// to [T] (a `Resource` comes from the context's resource loader). Throws
  /// when a placeholder has neither a value nor a default.
  ///
  /// ```dart
  /// final port = r.value<int>(r'${server.port:8080}');
  /// ```
  T value<T>(String expression);

  /// Like [value], for a nullable point: `null` when a placeholder has no
  /// value.
  T? optionalValue<T>(String expression);
}
