import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/context/condition.dart';
import 'package:spring_core_dart/src/context/event/event_listener_method.dart';

/// How a dependency is injected; the kind of a [Dependency].
///
/// Each kind corresponds to a form of injection point the generator
/// understands:
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
  /// One bean (`T` or `T?`).
  single,

  /// All beans of a type (`List<T>` / `Set<T>`).
  collection,

  /// All beans of a type by name (`Map<String, T>`).
  map,

  /// A lazy `ObjectProvider<T>`; never required, never part of a cycle.
  provider,

  /// A `@Lazy` single bean: checked like [single] (present, unambiguous)
  /// but resolved on first use, so never part of a cycle.
  lazy,

  /// A `@Value` expression.
  value,
}

/// A declared dependency of a bean, used to validate the bean graph at
/// refresh before anything is created.
///
/// Generated definitions list one [Dependency] per injection point so that
/// missing, ambiguous and circular dependencies are reported by
/// `validateBeanGraph` before any constructor runs. Hand-written
/// definitions may omit them (validation then simply skips those edges).
///
/// ```dart
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
  /// One bean of [type].
  const Dependency(
    this.type, {
    this.qualifier,
    this.name,
    this.optional = false,
  }) : kind = DependencyKind.single,
       expression = null;

  /// All beans of [type] as a list or set.
  const Dependency.collection(
    this.type, {
    this.qualifier,
    this.optional = false,
  }) : kind = DependencyKind.collection,
       name = null,
       expression = null;

  /// All beans of [type] by name.
  const Dependency.map(this.type, {this.qualifier, this.optional = false})
    : kind = DependencyKind.map,
      name = null,
      expression = null;

  /// A lazy provider of [type].
  const Dependency.provider(this.type, {this.qualifier})
    : kind = DependencyKind.provider,
      name = null,
      optional = true,
      expression = null;

  /// A `@Lazy` bean of [type]: validated at refresh, resolved on first use.
  const Dependency.lazy(this.type, {this.qualifier, this.name})
    : kind = DependencyKind.lazy,
      optional = false,
      expression = null;

  /// A `@Value` [expression].
  const Dependency.value(String this.expression, {this.optional = false})
    : kind = DependencyKind.value,
      type = String,
      qualifier = null,
      name = null;

  /// How the dependency is injected.
  final DependencyKind kind;

  /// Requested type (element type for collections and maps).
  final Type type;

  /// Bean name, alias or qualifier required at the injection point.
  final String? qualifier;

  /// Parameter or field name; a fallback qualifier when several beans
  /// match.
  final String? name;

  /// Whether a missing bean (or placeholder value) is allowed.
  final bool optional;

  /// The `@Value` expression for [DependencyKind.value].
  final String? expression;

  @override
  String toString() => switch (kind) {
    DependencyKind.value => '@Value("$expression")',
    _ =>
      '${kind == DependencyKind.single ? '' : '${kind.name} of '}$type'
          '${qualifier == null ? '' : "('$qualifier')"}',
  };
}

/// Recipe for a bean, like Spring's `BeanDefinition`.
///
/// Generated code creates these from annotations; they can also be written
/// by hand. Creation order: `create` → `inject` (fields, setters, methods)
/// → aware callbacks → `postProcessBeforeInitialization` →
/// `postConstruct` → `InitializingBean.afterPropertiesSet` →
/// `initMethod` → `postProcessAfterInitialization`. Destruction:
/// `DestructionAwareBeanPostProcessor`s → `preDestroy` →
/// `DisposableBean.destroy` → `destroyMethod`.
///
/// Instead of reflection, a definition carries closures: `create` calls
/// the constructor with dependencies from the [DependencyResolver], and the
/// other callbacks invoke the annotated methods.
///
/// ```dart
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
  /// Creates a definition named [name] whose instances are made by
  /// `create`.
  ///
  /// - `create`: calls the constructor (or `@Bean` method); obtain
  ///   dependencies from the resolver (`r.dependency<Foo>()`).
  /// - `inject`: field, setter and method injection after construction.
  /// - `postConstruct` / `initMethod`: init callbacks (`@PostConstruct`,
  ///   `@Bean(initMethod:)`).
  /// - `preDestroy` / `destroyMethod`: destroy callbacks (`@PreDestroy`,
  ///   `@Bean(destroyMethod:)`).
  /// - [types]: lookup types; defaults to `[T]`.
  BeanDefinition({
    required this.name,
    required this._create,
    this._inject,
    this._postConstruct,
    this._initMethod,
    this._preDestroy,
    this._destroyMethod,
    List<Type>? types,
    this.scope = ScopeType.singleton,
    this.lazy = false,
    this.primary = false,
    this.fallback = false,
    this.autowireCandidate = true,
    this.order,
    this.description,
    this.source,
    Set<String> qualifiers = const {},
    List<String> aliases = const [],
    List<String> dependsOn = const [],
    List<Dependency> dependencies = const [],
    List<Condition> conditions = const [],
    List<EventListenerMethod<T>> eventListeners = const [],
    List<BeanMethod<T>> annotatedMethods = const [],
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
       factoryObjectTypes = factoryObjectTypes == null
           ? null
           : List.unmodifiable(factoryObjectTypes);

  /// Unique bean name.
  final String name;

  /// Types the bean can be requested by (the class and its supertypes).
  final List<Type> types;

  /// Scope name: [ScopeType.singleton], [ScopeType.prototype] or a
  /// registered custom scope. Mutable for `BeanFactoryPostProcessor`s.
  String scope;

  /// Whether a singleton is created on first use instead of at refresh.
  bool lazy;

  /// Whether this bean wins when several beans match a type.
  bool primary;

  /// Whether this bean is used only when no other candidate matches.
  bool fallback;

  /// Whether the bean takes part in injection by type.
  bool autowireCandidate;

  /// `@Order` value used when the bean is not `Ordered` itself.
  int? order;

  /// Human-readable description (`@Description`).
  String? description;

  /// Where the definition comes from (e.g. `package:x/y.dart#Foo`);
  /// registering the same name from the same source twice is a no-op.
  final String? source;

  /// Extra names the bean can be selected by with `@Qualifier`.
  final Set<String> qualifiers;

  /// Additional bean names.
  final List<String> aliases;

  /// Beans created before (and destroyed after) this one.
  final List<String> dependsOn;

  /// Declared dependencies, used to validate the graph before creation.
  final List<Dependency> dependencies;

  /// The bean is registered only when all conditions match.
  final List<Condition> conditions;

  /// `@EventListener` methods (and `ApplicationListener` implementations).
  final List<EventListenerMethod<T>> eventListeners;

  /// Methods carrying an annotation marked with `@BeanMethodAnnotation()`
  /// (e.g. `@Scheduled`), with all their annotations and a closure that
  /// calls them; written by the generator.
  ///
  /// ```dart
  /// for (final method in definition.annotatedMethods) {
  ///   if (method.annotations.whereType<Scheduled>().isNotEmpty) {
  ///     method.invoke(bean, const []);
  ///   }
  /// }
  /// ```
  final List<BeanMethod<T>> annotatedMethods;

  /// For a `FactoryBean`: the product type and its supertypes. Lookups by
  /// these types (and by [name]) return the product.
  final List<Type>? factoryObjectTypes;

  /// Creates the generated AOP proxy of this bean, if it can be proxied.
  final AopProxyFactory? aopProxy;

  /// Advice and pointcuts when this bean is an `@Aspect`.
  final AspectMetadata<T>? aspect;

  final T Function(DependencyResolver resolver) _create;
  final void Function(T bean, DependencyResolver resolver)? _inject;
  final void Function(T bean)? _postConstruct;
  final void Function(T bean)? _initMethod;
  final void Function(T bean)? _preDestroy;
  final void Function(T bean)? _destroyMethod;

  /// The declared bean type.
  Type get beanType => T;

  /// Whether [scope] is [ScopeType.singleton].
  bool get isSingleton => scope == ScopeType.singleton;

  /// Whether [scope] is [ScopeType.prototype].
  bool get isPrototype => scope == ScopeType.prototype;

  /// Whether the bean is a `FactoryBean` (it has [factoryObjectTypes]).
  bool get isFactoryBean => factoryObjectTypes != null;

  /// Whether the definition has destroy callbacks of its own.
  bool get hasDestroyCallbacks => _preDestroy != null || _destroyMethod != null;

  /// Whether this bean is selected by [qualifier] (name, alias or
  /// qualifier).
  bool isQualifiedBy(String qualifier) =>
      name == qualifier ||
      aliases.contains(qualifier) ||
      qualifiers.contains(qualifier);

  /// Whether lookups by [type] match this definition.
  bool matchesType(Type type) =>
      types.contains(type) || (factoryObjectTypes?.contains(type) ?? false);

  /// Whether lookups by [type] return the product of a factory bean.
  ///
  /// A type listed in both [types] and [factoryObjectTypes] selects the
  /// factory itself.
  bool isProductType(Type type) =>
      (factoryObjectTypes?.contains(type) ?? false) && !types.contains(type);

  /// Creates a new instance (calls `create`); used by the container.
  T instantiate(DependencyResolver resolver) => _create(resolver);

  /// Runs field, setter and method injection.
  void populate(Object bean, DependencyResolver resolver) =>
      _inject?.call(bean as T, resolver);

  /// Runs `@PostConstruct` methods.
  void invokePostConstruct(Object bean) => _postConstruct?.call(bean as T);

  /// Runs the custom init method.
  void invokeInitMethod(Object bean) => _initMethod?.call(bean as T);

  /// Runs `@PreDestroy` methods.
  void invokePreDestroy(Object bean) => _preDestroy?.call(bean as T);

  /// Runs the custom destroy method.
  void invokeDestroyMethod(Object bean) => _destroyMethod?.call(bean as T);

  @override
  String toString() => "BeanDefinition<$T>('$name', $scope)";
}
