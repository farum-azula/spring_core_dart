import 'dart:async';

import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/null_bean.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/context/condition.dart';
import 'package:spring_core_dart/src/context/event/event_listener_method.dart';

/// The form of an injection point that a [Dependency] describes: one bean,
/// all beans of a type, a provider, a `@Value`, and so on.
///
/// The generator picks the kind from the parameter or field it reads, and
/// `validateBeanGraph` checks each kind in its own way (a provider is never
/// required, a `@Lazy` point never closes a cycle). You choose one yourself
/// only through the [Dependency] constructors of a hand-written
/// definition. The forms, as the generator sees them:
///
/// ```dart
/// @Service()
/// class Checkout {
///   Checkout(
///     this.payments,          // single
///     this.validators,        // collection (List<Validator>)
///     this.byName,            // map (Map<String, Exporter>)
///     this.audit,             // provider (ObjectProvider<Audit>)
///     @Value(r'${shop.currency:EUR}') this.currency, // value
///   );
///   final Payments payments;
///   final List<Validator> validators;
///   final Map<String, Exporter> byName;
///   final ObjectProvider<Audit> audit;
///   final String currency;
/// }
/// ```
///
/// Spring (Java): no public equivalent; Spring discovers the same kinds of
/// injection points by reflection (`DependencyDescriptor`):
/// ```java
/// Checkout(Payments payments, List<Validator> validators,
///     Map<String, Exporter> byName, ObjectProvider<Audit> audit,
///     @Value("${shop.currency:EUR}") String currency) { ... }
/// ```
enum DependencyKind {
  /// One bean (`T`, or `T?` when it may be missing).
  single,

  /// All beans of a type (`List<T>` or `Set<T>`).
  collection,

  /// All beans of a type by bean name (`Map<String, T>`).
  map,

  /// A lazy `ObjectProvider<T>` (or `ObjectFactory<T>`, jakarta
  /// `Provider<T>`): nothing is resolved before it is used, so it is never
  /// required and never part of a cycle.
  provider,

  /// A `@Lazy` single bean: checked like [single] (present, unambiguous)
  /// but resolved on first use, so never part of a cycle.
  lazy,

  /// A `@Value` expression; a required one must have a value at startup.
  value,

  /// A `@Resource` field or setter: the bean named [Dependency.name], or
  /// with [Dependency.fallbackToType] a bean of the type when no bean has
  /// that name.
  resource,
}

/// The description of one injection point of a bean, used to check the
/// bean graph at startup before anything is created.
///
/// A definition's `create` and `inject` callbacks are closures: the
/// container cannot see which beans they will ask for. So generated
/// definitions also list one [Dependency] per injection point, and
/// `validateBeanGraph` uses that list to report missing, ambiguous and
/// circular dependencies before any constructor runs. Hand-written
/// definitions may leave it out; validation then skips those edges and a
/// problem shows only when the bean is created.
///
/// ```dart
/// // A hand-written definition that declares what `create` will ask for.
/// BeanDefinition<Checkout>(
///   name: 'checkout',
///   dependencies: const [
///     Dependency(Payments, name: 'payments'),
///     Dependency.collection(Validator),
///     Dependency.provider(Audit),
///     Dependency.value(r'${shop.currency:EUR}'),
///   ],
///   create: (r) => Checkout(
///     r.dependency<Payments>(name: 'payments'),
///     r.dependencyList<Validator>(),
///     r.provider<Audit>(),
///     r.value<String>(r'${shop.currency:EUR}'),
///   ),
/// );
/// ```
///
/// Spring (Java): no direct counterpart. Spring finds injection points by
/// reflection at creation time (`DependencyDescriptor`,
/// `InjectionPoint`); it does not validate the whole graph up front.
final class Dependency {
  /// One bean of [type]. [qualifier] is the `@Qualifier` value, [name] the
  /// parameter or field name (it picks among several candidates), and
  /// [optional] marks a nullable point.
  const Dependency(
    this.type, {
    this.qualifier,
    this.name,
    this.optional = false,
  }) : kind = DependencyKind.single,
       expression = null,
       fallbackToType = false;

  /// All beans of [type], for a `List` or `Set` point; with [optional] (a
  /// nullable point) having none is fine.
  const Dependency.collection(
    this.type, {
    this.qualifier,
    this.optional = false,
  }) : kind = DependencyKind.collection,
       name = null,
       expression = null,
       fallbackToType = false;

  /// All beans of [type] by bean name, for a `Map<String, T>` point.
  const Dependency.map(this.type, {this.qualifier, this.optional = false})
    : kind = DependencyKind.map,
      name = null,
      expression = null,
      fallbackToType = false;

  /// A lazy provider of [type]; [name] (the parameter or field name)
  /// selects among several candidates like for a single bean.
  const Dependency.provider(this.type, {this.qualifier, this.name})
    : kind = DependencyKind.provider,
      optional = true,
      expression = null,
      fallbackToType = false;

  /// A `@Lazy` point of [type]: checked at startup like a single bean, but
  /// resolved on first use, so it never closes a cycle.
  const Dependency.lazy(this.type, {this.qualifier, this.name})
    : kind = DependencyKind.lazy,
      optional = false,
      expression = null,
      fallbackToType = false;

  /// A `@Value` [expression]; with [optional] (a nullable point) a
  /// placeholder without a value is fine.
  const Dependency.value(String this.expression, {this.optional = false})
    : kind = DependencyKind.value,
      type = String,
      qualifier = null,
      name = null,
      fallbackToType = false;

  /// A `@Resource` field or setter of [type]: the bean named [name]; with
  /// [fallbackToType] (the name was not given explicitly) a bean of [type]
  /// when no bean has that name.
  const Dependency.resource(
    this.type,
    String this.name, {
    this.fallbackToType = false,
    this.optional = false,
  }) : kind = DependencyKind.resource,
       qualifier = null,
       expression = null;

  /// The form of the injection point.
  final DependencyKind kind;

  /// The requested type; for collections and maps, the element type.
  final Type type;

  /// The bean name, alias or `@Qualifier` value the point requires, if any.
  final String? qualifier;

  /// The parameter or field name. When several beans match, the one with
  /// this name or alias is chosen.
  final String? name;

  /// Whether the point accepts a missing bean (or a placeholder without a
  /// value).
  final bool optional;

  /// The `@Value` expression for [DependencyKind.value].
  final String? expression;

  /// Whether a [DependencyKind.resource] falls back to injection by type
  /// when no bean is named [name].
  final bool fallbackToType;

  @override
  String toString() => switch (kind) {
    DependencyKind.value => '@Value("$expression")',
    DependencyKind.resource => "@Resource $type '$name'",
    _ =>
      '${kind == DependencyKind.single ? '' : '${kind.name} of '}$type'
          '${qualifier == null ? '' : "('$qualifier')"}'
          '${name == null ? '' : " '$name'"}',
  };
}

/// The recipe for one bean: its name, the types it can be found by, its
/// scope and flags, and the closures that create, inject, initialize and
/// destroy it.
///
/// The container never creates objects by reflection; it follows these
/// recipes. `create` calls the constructor with dependencies taken from the
/// [DependencyResolver], and the other closures call the annotated
/// methods. The generator writes one definition per `@Component` class and
/// `@Bean` method into the `*.spring.dart` file, so applications usually
/// never write one. You write one by hand for a bean the generator cannot
/// see (a class of a package you do not scan, a bean built from settings),
/// in a `BeanModule`, a `BeanDefinitionRegistryPostProcessor` or a
/// container used without a context. A `BeanFactoryPostProcessor` may
/// change the mutable fields ([scope], [lazy], [primary], ...) before the
/// beans are created.
///
/// The container calls the closures in this order: `create` → `inject`
/// (fields, setters, methods) → aware callbacks →
/// `postProcessBeforeInitialization` → `postConstruct` →
/// `InitializingBean.afterPropertiesSet` → `initMethod` →
/// `postProcessAfterInitialization`. On destruction:
/// `DestructionAwareBeanPostProcessor`s → `preDestroy` →
/// `DisposableBean.destroy` → `destroyMethod`.
///
/// ```dart
/// // A mailer from a package outside the scan, registered by hand. It can
/// // be injected as a Mailer or a Notifier and wins over other Notifiers.
/// final definition = BeanDefinition<Mailer>(
///   name: 'mailer',
///   types: const [Mailer, Notifier],
///   primary: true,
///   create: (r) => Mailer(r.dependency<SmtpClient>()),
///   inject: (bean, r) => bean.clock = r.optionalDependency<Clock>(),
///   postConstruct: (bean) => bean.connect(),
///   preDestroy: (bean) => bean.disconnect(),
/// );
/// factory.registerBeanDefinition(definition);
/// ```
///
/// Spring (Java):
/// ```java
/// RootBeanDefinition definition = new RootBeanDefinition(Mailer.class,
///     () -> new Mailer(factory.getBean(SmtpClient.class)));
/// definition.setPrimary(true);
/// definition.setInitMethodName("connect");
/// definition.setDestroyMethodName("disconnect");
/// factory.registerBeanDefinition("mailer", definition);
/// ```
///
/// Differences from Spring: [types] lists every type the bean can be
/// looked up by (Dart has no runtime subtype checks on `Type`), and the
/// definition is generic in the bean class.
final class BeanDefinition<T extends Object> {
  /// A definition named [name] whose instances `create` makes. The
  /// closures, all optional except `create`:
  ///
  /// - `create`: calls the constructor (or `@Bean` method), taking the
  ///   dependencies from the resolver (`r.dependency<Foo>()`). It may
  ///   return `null`: the bean is then a [NullBean].
  /// - `inject`: field, setter and method injection after construction.
  /// - `postConstruct` / `initMethod`: init callbacks (`@PostConstruct`,
  ///   `@Bean(initMethod:)`); a returned `Future` is awaited by
  ///   `refreshAsync()`.
  /// - `preDestroy` / `destroyMethod`: destroy callbacks (`@PreDestroy`,
  ///   `@Bean(destroyMethod:)`); a returned `Future` is awaited by
  ///   `closeAsync()`.
  /// - `scopedProxy`: for a custom-scoped (or prototype) bean, wraps a
  ///   function returning the current instance into an object of `T`
  ///   that forwards every call to it (`@Scope(proxyMode:)`, see
  ///   [ScopedProxyMode]); it is injected and returned instead of the
  ///   instance.
  ///
  /// The other arguments set the fields of the same name.
  BeanDefinition({
    required this.name,
    required this._create,
    this._inject,
    this._postConstruct,
    this._initMethod,
    this._preDestroy,
    this._destroyMethod,
    this._scopedProxy,
    List<Type>? types,
    this.scope = ScopeType.singleton,
    this.lazy = false,
    this.primary = false,
    this.fallback = false,
    this.autowireCandidate = true,
    this.defaultCandidate = true,
    this.order,
    this.description,
    this.source,
    this.factoryBeanName,
    this.factoryMethodName,
    this.initMethodName,
    this.destroyMethodName,
    Set<String> qualifiers = const {},
    List<String> aliases = const [],
    List<String> dependsOn = const [],
    List<Dependency> dependencies = const [],
    List<Condition> conditions = const [],
    List<EventListenerMethod<T>> eventListeners = const [],
    List<BeanMethod<T>> annotatedMethods = const [],
    List<Object> annotations = const [],
    List<Type>? factoryObjectTypes,
    this.aopProxy,
    this.aspect,
  }) : types = List.unmodifiable(types ?? [T]),
       qualifiers = Set.unmodifiable(qualifiers),
       aliases = List.unmodifiable(aliases),
       dependsOn = List.unmodifiable(dependsOn),
       dependencies = List.unmodifiable(dependencies),
       conditions = List.unmodifiable(conditions),
       eventListeners = List.unmodifiable(eventListeners),
       annotatedMethods = List.unmodifiable(annotatedMethods),
       annotations = List.unmodifiable(annotations),
       factoryObjectTypes = factoryObjectTypes == null
           ? null
           : List.unmodifiable(factoryObjectTypes);

  /// The [destroyMethodName] of a definition whose destroy method was not
  /// given but found by its name (`close`, `shutdown` or `dispose`), like
  /// Spring's `AbstractBeanDefinition.INFER_METHOD`. An inferred method is
  /// not called for a `DisposableBean`, whose `destroy()` runs instead.
  static const inferMethod = '(inferred)';

  /// The bean's name, unique within its factory. The generator uses the
  /// class name in lower camel case, or the `@Bean` method's name.
  final String name;

  /// The types the bean can be looked up and injected by: its class and
  /// every supertype it should be found as. Dart cannot ask at run time
  /// whether one `Type` is a subtype of another, so each one must be
  /// listed. Defaults to `[T]`.
  final List<Type> types;

  /// The scope name: [ScopeType.singleton] (the default),
  /// [ScopeType.prototype] or the name of a registered custom scope. A
  /// `BeanFactoryPostProcessor` may change it.
  String scope;

  /// Whether a singleton is created on first use instead of at startup
  /// (`@Lazy()`). Defaults to `false`.
  bool lazy;

  /// Whether this bean wins when several beans match a type (`@Primary()`).
  bool primary;

  /// Whether this bean is used only when no other candidate matches
  /// (`@Fallback()`).
  bool fallback;

  /// Whether the bean can be injected at all (`@Bean(autowireCandidate:)`),
  /// even through a qualifier. When `false` it is never injected, but
  /// lookups by name, `getBean<T>(qualifier: name)`, and `getBean<T>()`
  /// when it is the only bean of `T` still return it.
  bool autowireCandidate;

  /// Whether the bean is injected by its plain type (Spring 6.2's
  /// `@Bean(defaultCandidate: false)`). When `false` it is injected only
  /// where a qualifier selects it (bean name, alias or `@Qualifier`), and
  /// `@ConditionalOnBean` / `@ConditionalOnMissingBean` ignore it.
  bool defaultCandidate;

  /// The `@Order` value. For a `@Bean` definition ([factoryMethodName]
  /// set) it is the `@Order` of the method and beats `Ordered.order`, like
  /// in Spring; otherwise it is the class's `@Order`, used only when the
  /// bean is not `Ordered` itself.
  int? order;

  /// A human-readable description (`@Description`), for tools and logs.
  String? description;

  /// Where the definition comes from (e.g. `package:x/y.dart#Foo`).
  /// Registering a definition with the same name and the same source again
  /// is ignored, so a module imported twice does no harm.
  final String? source;

  /// For a `@Bean` instance method: the name of the configuration bean that
  /// declares it, like Spring's `getFactoryBeanName()`. That bean is not
  /// given this one, in a single injection point or a collection, unless
  /// nothing else matches (Spring's self-reference rule: creating this bean
  /// needs the configuration first).
  final String? factoryBeanName;

  /// For a `@Bean` method: the method's name, like Spring's
  /// `getFactoryMethodName()`. Its presence also means [order] came from
  /// the method.
  final String? factoryMethodName;

  /// Name of the custom init method (`@Bean(initMethod:)`); an init method
  /// named `afterPropertiesSet` is not called again for an
  /// `InitializingBean`.
  final String? initMethodName;

  /// Name of the custom destroy method (`@Bean(destroyMethod:)`), or
  /// [inferMethod] when it was inferred. An inferred method, or one named
  /// `destroy`, is not called for a `DisposableBean` (its `destroy()` runs
  /// once).
  final String? destroyMethodName;

  /// The bean's `@Qualifier` values: extra names that select it at a
  /// qualified injection point or lookup, besides its name and aliases.
  final Set<String> qualifiers;

  /// More names for the bean; each also works as a qualifier.
  final List<String> aliases;

  /// The names of the beans that must be created before this one and
  /// destroyed after it (`@DependsOn`), for an order that no injection
  /// point expresses.
  final List<String> dependsOn;

  /// The bean's injection points, which `validateBeanGraph` checks before
  /// anything is created; empty in a hand-written definition that does not
  /// list them.
  final List<Dependency> dependencies;

  /// The bean is registered only when all of these match (`@Profile`,
  /// `@Conditional...`).
  final List<Condition> conditions;

  /// The bean's `@EventListener` methods (and its `ApplicationListener`
  /// implementation), which the application context subscribes to events.
  final List<EventListenerMethod<T>> eventListeners;

  /// Methods carrying an annotation marked with `@BeanMethodAnnotation()`
  /// (e.g. `@Scheduled`), with all their annotations and a closure that
  /// calls them; written by the generator.
  ///
  /// ```dart
  /// // A scheduler starts every @Scheduled method of a bean.
  /// for (final method in definition.annotatedMethods) {
  ///   if (method.annotations.whereType<Scheduled>().isNotEmpty) {
  ///     method.invoke(bean, const []);
  ///   }
  /// }
  /// ```
  final List<BeanMethod<T>> annotatedMethods;

  /// The annotations of the bean class (for a `@Bean` method: of the method,
  /// then of the returned class), written by the generator for
  /// `findAnnotationOnBean` and `getBeansWithAnnotation`. Spring reads them
  /// by reflection.
  final List<Object> annotations;

  /// For a `FactoryBean`: its product type and the product's supertypes.
  /// Lookups by these types (and by [name]) return the product. `null` for
  /// any other bean.
  final List<Type>? factoryObjectTypes;

  /// Creates the generated AOP proxy of the bean, when the generator could
  /// write one; used when an aspect applies to the bean.
  final AopProxyFactory? aopProxy;

  /// The advice and pointcuts of the bean, when its class is an `@Aspect`.
  final AspectMetadata<T>? aspect;

  // May return `null` (a `@Bean` method declared `T?`): the bean is then a
  // [NullBean].
  final T? Function(DependencyResolver resolver) _create;
  final void Function(T bean, DependencyResolver resolver)? _inject;
  final FutureOr<void> Function(T bean)? _postConstruct;
  final FutureOr<void> Function(T bean)? _initMethod;
  final FutureOr<void> Function(T bean)? _preDestroy;
  final FutureOr<void> Function(T bean)? _destroyMethod;
  final T Function(T Function() target)? _scopedProxy;

  /// The bean's class, the type argument [T].
  Type get beanType => T;

  /// Whether [scope] is [ScopeType.singleton].
  bool get isSingleton => scope == ScopeType.singleton;

  /// Whether [scope] is [ScopeType.prototype].
  bool get isPrototype => scope == ScopeType.prototype;

  /// Whether the bean is a `FactoryBean` (it has [factoryObjectTypes]).
  bool get isFactoryBean => factoryObjectTypes != null;

  /// Whether the definition has destroy callbacks of its own (`preDestroy`
  /// or `destroyMethod`).
  bool get hasDestroyCallbacks => _preDestroy != null || _destroyMethod != null;

  /// Whether lookups and injection get a scoped proxy instead of the
  /// instance (see [createScopedProxy]); never for singletons.
  bool get hasScopedProxy => _scopedProxy != null && !isSingleton;

  /// Creates the scoped proxy: an object of the bean's type that forwards
  /// every call to the instance [target] returns at that moment. The
  /// container calls it once per bean.
  Object createScopedProxy(Object Function() target) =>
      _scopedProxy!(() => target() as T);

  /// Whether [qualifier] selects this bean: it is the bean's name, one of
  /// its [aliases] or one of its [qualifiers].
  bool isQualifiedBy(String qualifier) =>
      name == qualifier ||
      aliases.contains(qualifier) ||
      qualifiers.contains(qualifier);

  /// Whether lookups by [type] match this definition. Every bean is an
  /// `Object`.
  bool matchesType(Type type) =>
      type == Object ||
      types.contains(type) ||
      (factoryObjectTypes?.contains(type) ?? false);

  /// Whether lookups by [type] return the product of a factory bean.
  ///
  /// A type listed in both [types] and [factoryObjectTypes] selects the
  /// factory itself; `Object` selects the product (like Spring).
  bool isProductType(Type type) =>
      isFactoryBean &&
      (type == Object ||
          (factoryObjectTypes!.contains(type) && !types.contains(type)));

  /// Calls `create` and returns the new instance, or a [NullBean] when
  /// `create` returned `null`. The container calls it; other code looks
  /// beans up instead.
  Object instantiate(DependencyResolver resolver) =>
      _create(resolver) ?? NullBean();

  /// Runs the `inject` callback on [bean]: field, setter and method
  /// injection.
  void populate(Object bean, DependencyResolver resolver) =>
      _inject?.call(bean as T, resolver);

  /// Runs `@PostConstruct` methods; a `Future` when they are asynchronous.
  FutureOr<void> invokePostConstruct(Object bean) =>
      _postConstruct?.call(bean as T);

  /// Runs the custom init method; a `Future` when it is asynchronous.
  FutureOr<void> invokeInitMethod(Object bean) => _initMethod?.call(bean as T);

  /// Runs `@PreDestroy` methods; a `Future` when they are asynchronous.
  FutureOr<void> invokePreDestroy(Object bean) => _preDestroy?.call(bean as T);

  /// Runs the custom destroy method; a `Future` when it is asynchronous.
  FutureOr<void> invokeDestroyMethod(Object bean) =>
      _destroyMethod?.call(bean as T);

  @override
  String toString() => "BeanDefinition<$T>('$name', $scope)";
}
