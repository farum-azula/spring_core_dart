// The intermediate model between `BeanScanner` (reads analyzer elements)
// and `ModuleEmitter` (writes Dart code). The scanner fills one
// [ModuleModel] per `@ComponentScan`; the emitter turns it into a
// `*.beans.dart` library. Examples in this file show generated code
// without its import prefixes (`_i1.`, `_i2.`).

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// How an injection point is satisfied.
///
/// The kind is derived from the declared type of a constructor parameter,
/// field, setter or method parameter:
///
/// ```dart
/// // Input:
/// @Component()
/// class Host {
///   Host(
///     Plugin single,               // PointKind.single
///     List<Plugin> list,           // PointKind.list (also Iterable)
///     Set<Plugin> set,             // PointKind.set
///     Map<String, Plugin> map,     // PointKind.map (keys: bean names)
///     ObjectProvider<Plugin> lazy, // PointKind.provider
///     @Value(r'${port:80}') int port, // PointKind.value
///   );
/// }
/// // Output (create closure):
/// create: (r) => Host(
///   r.dependency<Plugin>(name: r'single'),
///   r.dependencyList<Plugin>(),
///   r.dependencyList<Plugin>().toSet(),
///   r.dependencyMap<Plugin>(),
///   r.provider<Plugin>(),
///   r.value<int>(r'${port:80}'),
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // AutowiredAnnotationBeanPostProcessor resolves the same shapes at
/// // runtime through DependencyDescriptor and reflection:
/// @Component
/// class Host {
///   Host(Plugin single, List<Plugin> list, Set<Plugin> set,
///        Map<String, Plugin> map, ObjectProvider<Plugin> lazy,
///        @Value("${port:80}") int port) {}
/// }
/// ```
enum PointKind {
  /// One bean of the type (`r.dependency<T>()`).
  single,

  /// All beans of the element type, as a `List` or `Iterable`.
  list,

  /// All beans of the element type, as a `Set`.
  set,

  /// All beans of the value type keyed by bean name (`Map<String, T>`).
  map,

  /// A lazy `ObjectProvider<T>`.
  provider,

  /// A `@Value` expression resolved against the environment.
  value,
}

/// Something the container must supply: a constructor or method argument,
/// a field or a setter.
///
/// Each injection point becomes both a resolver call in the generated
/// code and a `Dependency` entry in `BeanDefinition.dependencies`:
///
/// ```dart
/// // Input:
/// @Service()
/// class ApiImpl {
///   ApiImpl(this.dep, {@Qualifier('x') Other? other});
///   final Other dep;
/// }
/// // Output:
/// dependencies: const [
///   Dependency(Other, name: r'dep'),
///   Dependency(Other, qualifier: r'x', optional: true, name: r'other'),
/// ],
/// create: (r) => ApiImpl(
///   r.dependency<Other>(name: r'dep'),
///   other: r.optionalDependency<Other>(qualifier: r'x', name: r'other'),
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring models the same thing at runtime as a DependencyDescriptor
/// // built from a reflected MethodParameter or Field:
/// var descriptor = new DependencyDescriptor(
///     MethodParameter.forExecutable(ctor, 1), /* required */ false);
/// Object other = beanFactory.resolveDependency(descriptor, "apiImpl");
/// ```
class InjectionPoint {
  /// Creates an injection point; [type] must not be nullable (nullability
  /// is expressed by [optional]).
  InjectionPoint({
    required this.kind,
    required this.type,
    required this.optional,
    this.qualifier,
    this.name,
    this.expression,
    this.defaultValue,
    this.allowEmpty = false,
    this.lazy,
  });

  /// A copy for a constructor or `@Bean` method parameter: a Dart default
  /// value makes the point optional (the default is used when nothing is
  /// found), and a required collection may be empty, like Spring's
  /// `ConstructorResolver` fallback for single constructors.
  InjectionPoint forParameter({
    DartObject? defaultValue,
    bool collectionsMayBeEmpty = false,
  }) => InjectionPoint(
    kind: kind,
    type: type,
    optional: optional || defaultValue != null,
    qualifier: qualifier,
    name: name,
    expression: expression,
    defaultValue: defaultValue,
    lazy: lazy,
    allowEmpty:
        collectionsMayBeEmpty &&
        defaultValue == null &&
        !optional &&
        (kind == PointKind.list ||
            kind == PointKind.set ||
            kind == PointKind.map),
  );

  /// How the value is looked up (single bean, collection, value, ...).
  final PointKind kind;

  /// Requested bean type (element type for collections and providers), or
  /// the target type of a `@Value`; never nullable.
  final InterfaceType type;

  /// Nullable in source.
  ///
  /// An optional point resolves to `null` (or an absent collection)
  /// instead of failing, like `@Autowired(required = false)` in Spring.
  final bool optional;

  /// The `@Qualifier` or `@Named` value, if any.
  final String? qualifier;

  /// Parameter or field name (fallback qualifier for single beans).
  final String? name;

  /// The `@Value` expression.
  final String? expression;

  /// The parameter's Dart default value, used when no bean (or property)
  /// is found.
  final DartObject? defaultValue;

  /// A required collection that resolves to an empty collection when no
  /// bean matches (constructor and `@Bean` method parameters).
  final bool allowEmpty;

  /// For a `@Lazy` single bean: the generated lazy proxy that resolves the
  /// bean on every member access (Spring's lazy-resolution proxy).
  final ProxyModel? lazy;
}

/// A constructor or method argument.
///
/// ```dart
/// // Input:
/// ApiImpl(this.dep, {Other? other});
/// // Output: one positional and one named argument
/// ApiImpl(
///   r.dependency<Other>(name: r'dep'),
///   other: r.optionalDependency<Other>(name: r'other'),
/// )
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring has no named parameters; ConstructorResolver resolves each
/// // argument by index and invokes the constructor reflectively:
/// ctor.newInstance(resolvedArgs);
/// ```
class Argument {
  /// Creates an argument; pass [namedAs] for named parameters.
  Argument(this.point, {this.namedAs});

  /// What to inject for this argument.
  final InjectionPoint point;

  /// Parameter name for named parameters, `null` for positional ones.
  final String? namedAs;
}

/// How a bean instance is created.
///
/// Either a constructor call ([ConstructorCreation]) or a `@Bean` factory
/// method call ([BeanMethodCreation]); both become the `create` closure of
/// a `BeanDefinition`.
///
/// ```dart
/// // Output for a component and for a @Bean method:
/// create: (r) => Greeter(r.dependency<Clock>(name: r'clock')),
/// create: (r) => r.dependency<Config>(qualifier: r'config').clock(),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ConstructorResolver picks between autowireConstructor(...) and
/// // instantiateUsingFactoryMethod(...) at runtime, via reflection.
/// ```
sealed class Creation {
  /// Arguments passed to the constructor or factory method, in order.
  List<Argument> get arguments;
}

/// `Type(args)` or `Type.named(args)`.
///
/// ```dart
/// // Input:
/// @Component()
/// class Pool {
///   @Autowired()
///   Pool.sized(@Value(r'${pool.size:4}') int size);
/// }
/// // Output:
/// create: (r) => Pool.sized(r.value<int>(r'${pool.size:4}')),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring selects the @Autowired (or single) constructor and calls
/// // it reflectively through BeanUtils.instantiateClass(ctor, args).
/// @Component
/// class Pool {
///   @Autowired
///   Pool(@Value("${pool.size:4}") int size) {}
/// }
/// ```
class ConstructorCreation extends Creation {
  /// Creates a constructor call; [constructorName] is `null` for the
  /// unnamed constructor.
  ConstructorCreation(this.constructorName, this.arguments);

  /// `null` for the unnamed constructor.
  final String? constructorName;

  @override
  final List<Argument> arguments;
}

/// A `@Bean` method on another bean (or a static one).
///
/// Instance methods are called on the owning bean, looked up by its name;
/// static methods are called on the class.
///
/// ```dart
/// // Input:
/// @Configuration()
/// class Config {
///   @Bean()
///   Clock clock() => SystemClock();
///
///   @Bean()
///   static Shut shut() => Shut();
/// }
/// // Output:
/// create: (r) => r.dependency<Config>(qualifier: r'config').clock(),
/// create: (r) => Config.shut(),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ConfigurationClassPostProcessor registers each @Bean method as a
/// // factory method; SimpleInstantiationStrategy invokes it reflectively
/// // (on a CGLIB-enhanced @Configuration instance):
/// @Configuration
/// class Config {
///   @Bean Clock clock() { return new SystemClock(); }
///   @Bean static Shut shut() { return new Shut(); }
/// }
/// ```
class BeanMethodCreation extends Creation {
  /// Creates a factory-method call.
  BeanMethodCreation({
    required this.ownerType,
    required this.ownerName,
    required this.methodName,
    required this.isStatic,
    required this.arguments,
  });

  /// The class that declares the `@Bean` method.
  final InterfaceType ownerType;

  /// The bean name of the owner (used as qualifier to look it up).
  final String ownerName;

  /// The name of the `@Bean` method.
  final String methodName;

  /// Whether the method is static (no owner instance is needed).
  final bool isStatic;

  @override
  final List<Argument> arguments;
}

/// `bean.name = value` after construction (field or setter).
///
/// ```dart
/// // Input:
/// @Component()
/// class Child {
///   @Value(r'${name}')
///   late final String name;
///
///   @Autowired()
///   set dep(Dep? value) => _dep = value;
/// }
/// // Output:
/// inject: (bean, r) {
///   bean.name = r.value<String>(r'${name}');
///   bean.dep = r.optionalDependency<Dep>(name: r'dep');
/// },
/// ```
///
/// Spring (Java):
///
/// ```java
/// // AutowiredAnnotationBeanPostProcessor finds @Autowired/@Value fields
/// // and setters by reflection and sets them in
/// // postProcessProperties(...):
/// field.setAccessible(true);
/// field.set(bean, beanFactory.resolveDependency(descriptor, beanName));
/// ```
class PropertyInjection {
  /// Creates a property injection for the field or setter [name].
  PropertyInjection(this.name, this.point);

  /// The field or setter name.
  final String name;

  /// What to assign.
  final InjectionPoint point;
}

/// `bean.name(args)` after construction.
///
/// ```dart
/// // Input:
/// @Autowired()
/// void wire(Dep dep, {@Value(r'${x:1}') int x = 0}) {}
/// // Output (inside the inject closure):
/// bean.wire(
///   r.dependency<Dep>(name: r'dep'),
///   x: r.value<int>(r'${x:1}'),
/// );
/// ```
///
/// Spring (Java):
///
/// ```java
/// // AutowiredAnnotationBeanPostProcessor invokes @Autowired methods
/// // reflectively after field injection:
/// method.invoke(bean, resolvedArguments);
/// ```
class MethodInjection {
  /// Creates a method injection for the method [name].
  MethodInjection(this.name, this.arguments);

  /// The `@Autowired` method name.
  final String name;

  /// The method's arguments.
  final List<Argument> arguments;
}

/// A condition to emit.
///
/// Conditions decide at context refresh whether a bean is registered.
///
/// ```dart
/// // Input:
/// @Profile(['cloud'])
/// @Conditional([OnLinux])
/// @OnFeature('audit') // a const annotation implementing Condition
/// @Component()
/// class Audit {}
/// // Output:
/// conditions: [
///   const ProfileCondition([r'cloud']),
///   OnLinux(),
///   const OnFeature(r'audit'),
/// ],
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ConditionEvaluator instantiates the Condition classes reflectively
/// // and calls matches(context, metadata) while parsing configuration:
/// @Profile("cloud")
/// @Conditional(OnLinux.class)
/// @Component
/// class Audit {}
/// ```
sealed class ConditionModel {}

/// `@Profile([...])`.
///
/// ```dart
/// // Input:  @Profile(['cloud', '!test'])
/// // Output: const ProfileCondition([r'cloud', r'!test'])
/// ```
///
/// Spring (Java):
///
/// ```java
/// @Profile({"cloud", "!test"}) // evaluated by ProfileCondition
/// ```
class ProfileConditionModel extends ConditionModel {
  /// Creates a profile condition.
  ProfileConditionModel(this.profiles);

  /// Profile expressions; the bean is active if any of them matches.
  final List<String> profiles;
}

/// `@Conditional([Type])`: instantiated with its no-argument constructor.
///
/// ```dart
/// // Input:  @Conditional([OnLinux])
/// // Output: OnLinux()
/// ```
///
/// Spring (Java):
///
/// ```java
/// @Conditional(OnLinux.class) // BeanUtils.instantiateClass(OnLinux.class)
/// ```
class TypeConditionModel extends ConditionModel {
  /// Creates a condition instantiated from [type].
  TypeConditionModel(this.type);

  /// A class implementing `Condition` with a no-argument constructor.
  final InterfaceType type;
}

/// A const annotation that implements `Condition`, re-emitted as is.
///
/// ```dart
/// // Input:
/// class OnMode implements Condition {
///   const OnMode(this.mode);
///   final Mode mode;
///   @override
///   bool matches(ConditionContext context) => true;
/// }
/// @OnMode(Mode.on)
/// @Component()
/// class Feature {}
/// // Output:
/// conditions: [const OnMode(Mode.on)],
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring needs a meta-annotation plus a separate Condition class that
/// // reads the attributes from AnnotatedTypeMetadata at runtime:
/// @Conditional(OnModeCondition.class)
/// @interface OnMode { Mode value(); }
/// ```
/// The conditions of a configuration class, evaluated once for the class,
/// its `@Bean` methods and its `@PropertySource`s.
///
/// ```dart
/// // Output: ConditionGroup(r'package:a/b.dart#Config', [ ... ])
/// ```
class GroupConditionModel extends ConditionModel {
  /// Groups [conditions] under [key].
  GroupConditionModel(this.key, this.conditions);

  /// `library#Class`.
  final String key;

  /// The grouped conditions.
  final List<ConditionModel> conditions;
}

/// A condition annotation re-created as a constant (see above).
class AnnotationConditionModel extends ConditionModel {
  /// Creates a condition re-created from the constant [value].
  AnnotationConditionModel(this.value);

  /// The evaluated annotation instance.
  final DartObject value;
}

/// An event listener method (or `ApplicationListener.onApplicationEvent`).
///
/// ```dart
/// // Input:
/// @Component()
/// class Shipping {
///   @EventListener()
///   OrderShipped onPlaced(OrderPlaced order) => OrderShipped(order);
/// }
/// // Output:
/// eventListeners: [
///   EventListenerMethod.of<Shipping, OrderPlaced>(
///     r'Shipping.onPlaced',
///     (bean, event) => bean.onPlaced(event),
///   ),
/// ],
/// ```
///
/// Spring (Java):
///
/// ```java
/// // EventListenerMethodProcessor finds @EventListener methods by
/// // reflection after singleton instantiation and wraps each one in an
/// // ApplicationListenerMethodAdapter:
/// @EventListener
/// OrderShipped onPlaced(OrderPlaced order) { return new OrderShipped(); }
/// ```
class ListenerModel {
  /// Creates a listener model.
  ListenerModel({
    required this.id,
    required this.methodName,
    required this.eventTypes,
    required this.parameterType,
    required this.returnsValue,
    this.order,
    this.condition,
  });

  /// Listener id: `@EventListener(id:)` or `Class.method`.
  final String id;

  /// The method that handles the event.
  final String methodName;

  /// Accepted event (or payload) types.
  final List<InterfaceType> eventTypes;

  /// The method's parameter type; `null` for methods without parameters.
  final InterfaceType? parameterType;

  /// Whether the result is published as an event.
  final bool returnsValue;

  /// The `@Order` value of the method (of the class for
  /// `ApplicationListener`).
  final int? order;

  /// A `bool Function(E)` top-level or static function.
  final ExecutableElement? condition;
}

/// How an advice method parameter is filled.
///
/// ```dart
/// // Input:
/// @AfterReturning('all()')
/// void returned(JoinPoint jp, String result) {}
/// // Output:
/// invoke: (aspect, joinPoint, value) =>
///     aspect.returned(joinPoint, (value as String)),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // AbstractAspectJAdvice binds JoinPoint/ProceedingJoinPoint and the
/// // returning/throwing argument by reflection on the advice method:
/// @AfterReturning(pointcut = "all()", returning = "result")
/// void returned(JoinPoint jp, String result) {}
/// ```
enum AdviceParameter {
  /// A `JoinPoint` parameter.
  joinPoint,

  /// A `ProceedingJoinPoint` parameter (only `@Around`).
  proceedingJoinPoint,

  /// The return value (`@AfterReturning`) or error (`@AfterThrowing`).
  value,
}

/// One advice method of an `@Aspect`.
///
/// ```dart
/// // Input:
/// @Around('@annotation(Timed)')
/// Object? time(ProceedingJoinPoint pjp) => pjp.proceed();
/// // Output:
/// AspectAdvice<TimingAspect>(
///   kind: AdviceKind.around,
///   pointcut: r'@annotation(Timed)',
///   methodName: r'time',
///   invoke: (aspect, joinPoint, value) =>
///       aspect.time((joinPoint as ProceedingJoinPoint)),
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ReflectiveAspectJAdvisorFactory turns each advice method into an
/// // InstantiationModelAwarePointcutAdvisorImpl at runtime:
/// @Around("@annotation(Timed)")
/// Object time(ProceedingJoinPoint pjp) throws Throwable {
///   return pjp.proceed();
/// }
/// ```
class AdviceModel {
  /// Creates an advice model.
  AdviceModel({
    required this.kind,
    required this.pointcut,
    required this.methodName,
    required this.parameters,
    this.valueType,
  });

  /// `around`, `before`, `after`, `afterReturning`, `afterThrowing`.
  final String kind;

  /// The pointcut expression (or a reference to a named `@Pointcut`).
  final String pointcut;

  /// The advice method name.
  final String methodName;

  /// How each positional parameter of the advice method is filled.
  final List<AdviceParameter> parameters;

  /// Type of the value parameter (return value or error), if any.
  final DartType? valueType;
}

/// The advice and named pointcuts of an `@Aspect` class.
///
/// ```dart
/// // Input:
/// @Aspect()
/// @Component()
/// class Audit {
///   @Pointcut('execution(* Calculator.*(..))')
///   void calculator() {}
///
///   @Before('calculator()')
///   void before(JoinPoint jp) {}
/// }
/// // Output:
/// aspect: AspectMetadata<Audit>(
///   advice: [
///     AspectAdvice<Audit>(
///       kind: AdviceKind.before,
///       pointcut: r'calculator()',
///       methodName: r'before',
///       invoke: (aspect, joinPoint, value) => aspect.before(joinPoint),
///     ),
///   ],
///   pointcuts: {r'calculator': r'execution(* Calculator.*(..))'},
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // BeanFactoryAspectJAdvisorsBuilder finds @Aspect beans at runtime and
/// // builds advisors from their annotated methods:
/// @Aspect
/// @Component
/// class Audit {
///   @Pointcut("execution(* Calculator.*(..))") void calculator() {}
///   @Before("calculator()") void before(JoinPoint jp) {}
/// }
/// ```
class AspectModel {
  /// Creates an aspect model.
  AspectModel(this.advice, this.pointcuts);

  /// Advice methods in declaration order.
  final List<AdviceModel> advice;

  /// Named pointcuts: method name to pointcut expression.
  final Map<String, String> pointcuts;
}

/// A parameter of a proxied method.
///
/// ```dart
/// // Input:
/// String plain(int a, [int b = 2, String? c]);
/// // Output (proxy method keeps the signature and literal defaults):
/// String plain(int a, [int b = 2, String? c]) => ...;
/// ```
///
/// Spring (Java):
///
/// ```java
/// // JDK/CGLIB proxies get parameters from java.lang.reflect.Method;
/// // Java has no default values, so nothing needs to be copied.
/// ```
class ProxyParameter {
  /// Creates a proxy parameter.
  ProxyParameter({
    required this.name,
    required this.type,
    required this.isNamed,
    required this.isRequired,
    this.defaultValueCode,
  });

  /// The parameter name.
  final String name;

  /// The declared parameter type.
  final DartType type;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Whether the parameter is required (positional or `required` named).
  final bool isRequired;

  /// Source of the default value; only simple literals are allowed.
  final String? defaultValueCode;
}

/// Kind of a proxied member.
///
/// ```dart
/// // Output: getters and setters carry a kind in their signature
/// MethodSignature(name: r'count', kind: MemberKind.getter, ...)
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Java proxies only intercept methods; a getter is a getX() method.
/// ```
enum ProxyMemberKind {
  /// A regular instance method.
  method,

  /// A getter (including the implicit getter of a field).
  getter,

  /// A setter (including the implicit setter of a non-final field).
  setter,
}

/// A member forwarded by a generated proxy.
///
/// Its position in [ProxyModel.members] is the index passed to
/// `ProxyInvoker.invoke`, which links the call to its `MethodSignature`.
///
/// ```dart
/// // Input:
/// abstract interface class Calculator { int add(int a, int b); }
/// @Service()
/// class SimpleCalculator implements Calculator { ... }
/// // Output (in _$SimpleCalculatorProxy):
/// @override
/// int add(int a, int b) => (_invoker.invoke(this, _target, 0, [a, b],
///     (args) => _target.add((args[0] as int), (args[1] as int))) as int);
/// ```
///
/// Spring (Java):
///
/// ```java
/// // A JDK proxy routes every interface method through one
/// // InvocationHandler (JdkDynamicAopProxy) with the reflected Method:
/// Object invoke(Object proxy, Method method, Object[] args) { ... }
/// ```
class ProxyMember {
  /// Creates a proxy member.
  ProxyMember({
    required this.kind,
    required this.name,
    required this.declaringType,
    this.declaringTypes = const [],
    required this.returnType,
    required this.typeParameters,
    required this.parameters,
    required this.annotations,
  });

  /// Method, getter or setter.
  final ProxyMemberKind kind;

  /// The member name.
  final String name;

  /// Simple name of the type reported as declaring the member (the first
  /// abstract supertype that declares it, if any).
  final String declaringType;

  /// Every proxied type declaring the member.
  final List<String> declaringTypes;

  /// Return type for methods and getters, value type for setters.
  final DartType returnType;

  /// Type parameters of a generic method.
  final List<TypeParameterElement> typeParameters;

  /// The parameters, in declaration order.
  final List<ProxyParameter> parameters;

  /// User annotations of the implementation and of every declaration,
  /// matched by `@annotation(...)` pointcuts.
  final List<DartObject> annotations;
}

/// A generated AOP proxy class for one bean.
///
/// ```dart
/// // Input:
/// abstract interface class Greeter { String greet(String name); }
/// @Service()
/// class EnglishGreeter implements Greeter { ... }
/// // Output:
/// class _$EnglishGreeterProxy
///     implements EnglishGreeter, Greeter, Advised {
///   _$EnglishGreeterProxy(this._target, this._invoker);
///   final EnglishGreeter _target;
///   final ProxyInvoker _invoker;
///   // targetObject, advisors, toString and one override per member
/// }
/// // ...and in the bean definition:
/// aopProxy: AopProxyFactory(
///   signatures: const [MethodSignature(name: r'greet', ...)],
///   create: (target, invoker) =>
///       _$EnglishGreeterProxy((target as EnglishGreeter), invoker),
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // AnnotationAwareAspectJAutoProxyCreator wraps the bean at runtime in
/// // a JDK dynamic proxy (interfaces) or a CGLIB subclass (classes):
/// var factory = new ProxyFactory(target);
/// factory.addAdvisors(advisors);
/// Greeter proxy = (Greeter) factory.getProxy();
/// ```
class ProxyModel {
  /// Creates a proxy model.
  ProxyModel({
    required this.className,
    required this.targetType,
    required this.interfaces,
    required this.members,
    required this.classAnnotations,
    required this.targetTypeNames,
    this.customToString = false,
    this.unavailableReason,
  });

  /// Name of the generated class, e.g. `_$EnglishGreeterProxy` or
  /// `_$Config_clockProxy` for a `@Bean` method.
  final String className;

  /// The type the proxy forwards to.
  final InterfaceType targetType;

  /// Types the proxy `implements` (besides `Advised`).
  final List<InterfaceType> interfaces;

  /// Forwarded members; the index is the member id at runtime.
  final List<ProxyMember> members;

  /// User annotations of the target class (for `@within(...)`-style
  /// matching).
  final List<DartObject> classAnnotations;

  /// Simple names of the target type and all its supertypes.
  final List<String> targetTypeNames;

  /// Whether the target's `toString` takes parameters, so it is forwarded
  /// like any other member instead of the generated `toString()`.
  final bool customToString;

  /// Why no proxy class can be generated; then only the signatures are
  /// emitted (`AopProxyFactory.unavailable`) so matching advice fails the
  /// startup with this reason instead of being skipped silently.
  final String? unavailableReason;
}

/// Everything needed to emit one `BeanDefinition`.
///
/// One model is created per component class and per `@Bean` method.
///
/// ```dart
/// // Input:
/// @Service()
/// @Lazy()
/// class Greeter {
///   Greeter(this.clock);
///   final Clock clock;
///
///   @PostConstruct()
///   void init() {}
/// }
/// // Output:
/// BeanDefinition<Greeter>(
///   name: r'greeter',
///   source: r'package:app/src/greeter.dart#Greeter',
///   types: const [Greeter],
///   lazy: true,
///   dependencies: const [Dependency(Clock, name: r'clock')],
///   create: (r) => Greeter(r.dependency<Clock>(name: r'clock')),
///   postConstruct: (bean) {
///     bean.init();
///   },
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ClassPathBeanDefinitionScanner produces a ScannedGenericBeanDefinition
/// // whose attributes are later read by AbstractAutowireCapableBeanFactory:
/// @Service
/// @Lazy
/// class Greeter {
///   Greeter(Clock clock) {}
///   @PostConstruct void init() {}
/// }
/// ```
class BeanModel {
  /// Creates a bean model; defaults match Spring's (singleton, eager,
  /// autowire candidate).
  BeanModel({
    required this.element,
    required this.source,
    required this.name,
    required this.type,
    required this.exposedTypes,
    required this.creation,
    this.factoryObjectTypes,
    this.aliases = const [],
    this.scope = 'singleton',
    this.lazy = false,
    this.primary = false,
    this.fallback = false,
    this.autowireCandidate = true,
    this.order,
    this.description,
    this.dependsOn = const [],
    this.qualifiers = const {},
    this.conditions = const [],
    this.properties = const [],
    this.methods = const [],
    this.postConstruct = const [],
    this.preDestroy = const [],
    this.initMethod,
    this.destroyMethod,
    this.listeners = const [],
    this.annotatedMethods = const [],
    this.aspect,
    this.proxy,
  });

  /// Source element, for error messages.
  final Element element;

  /// `package:x/y.dart#Class` or `...#Class.method`.
  final String source;

  /// The bean name (decapitalized class name, `@Bean` method name or an
  /// explicit name).
  final String name;

  /// The bean's class (or the `@Bean` method's return type).
  final InterfaceType type;

  /// [type] and its public supertypes, except `Object`.
  final List<InterfaceType> exposedTypes;

  /// Product types of a `FactoryBean`.
  final List<InterfaceType>? factoryObjectTypes;

  /// How the instance is created.
  final Creation creation;

  /// Extra names (`@Bean(aliases:)`).
  final List<String> aliases;

  /// The `@Scope` value; `singleton` by default.
  final String scope;

  /// Whether `@Lazy` defers creation until first use.
  final bool lazy;

  /// Whether `@Primary` wins among several candidates.
  final bool primary;

  /// Whether `@Fallback` loses against other candidates.
  final bool fallback;

  /// `false` when `@Bean(autowireCandidate: false)` hides the bean from
  /// type-based injection.
  final bool autowireCandidate;

  /// The `@Order` value.
  final int? order;

  /// The `@Description` value.
  final String? description;

  /// Bean names from `@DependsOn` that must be created first.
  final List<String> dependsOn;

  /// `@Qualifier` values declared on the bean.
  final Set<String> qualifiers;

  /// Registration conditions (class conditions first for `@Bean`
  /// methods).
  final List<ConditionModel> conditions;

  /// Injected fields and setters.
  final List<PropertyInjection> properties;

  /// Injected (`@Autowired`) methods.
  final List<MethodInjection> methods;

  /// `@PostConstruct` methods, superclass methods first.
  final List<String> postConstruct;

  /// `@PreDestroy` methods, subclass methods first.
  final List<String> preDestroy;

  /// `@Bean(initMethod:)`.
  final String? initMethod;

  /// `@Bean(destroyMethod:)`, explicit or inferred (`close`, `shutdown`,
  /// `dispose`).
  final String? destroyMethod;

  /// Event listener methods of the bean.
  final List<ListenerModel> listeners;

  /// Methods carrying an annotation marked `@BeanMethodAnnotation()`.
  final List<AnnotatedMethodModel> annotatedMethods;

  /// Set for `@Aspect` beans.
  final AspectModel? aspect;

  /// The generated AOP proxy, when the bean can be proxied.
  final ProxyModel? proxy;

  /// Every injection point, for `BeanDefinition.dependencies`.
  ///
  /// For an instance `@Bean` method the owning bean comes first, so the
  /// container creates it before the factory method is called:
  ///
  /// ```dart
  /// dependencies: const [Dependency(AopConfig, qualifier: r'aopConfig')],
  /// ```
  List<InjectionPoint> get dependencies => [
    if (creation case BeanMethodCreation(
      isStatic: false,
      :final ownerType,
      :final ownerName,
    ))
      InjectionPoint(
        kind: PointKind.single,
        type: ownerType,
        optional: false,
        qualifier: ownerName,
      ),
    for (final argument in creation.arguments) argument.point,
    for (final property in properties) property.point,
    for (final method in methods)
      for (final argument in method.arguments) argument.point,
  ];
}

/// A `@Configurable` class: injected by `autowireBean`.
///
/// Such classes are created outside the container (e.g. Flutter state
/// objects) and get their fields, setters and methods injected later.
///
/// ```dart
/// // Input:
/// @Configurable()
/// class ScreenState {
///   @Autowired()
///   late Greeter greeter;
/// }
/// // Output (BeanModule argument):
/// configurers: {
///   ScreenState: (bean, r) {
///     final target = (bean as ScreenState);
///     target.greeter = r.dependency<Greeter>(name: r'greeter');
///   },
/// },
/// ```
///
/// Spring (Java):
///
/// ```java
/// // @Configurable relies on AspectJ weaving; without it, code calls
/// // AutowireCapableBeanFactory, which injects via reflection:
/// context.getAutowireCapableBeanFactory().autowireBean(screenState);
/// ```
class ConfigurableModel {
  /// Creates a configurable model.
  ConfigurableModel(this.element, this.type, this.properties, this.methods);

  /// Source element, for error messages.
  final Element element;

  /// The configurable class.
  final InterfaceType type;

  /// Injected fields and setters.
  final List<PropertyInjection> properties;

  /// Injected methods.
  final List<MethodInjection> methods;
}

/// A `@PropertySource` declaration.
///
/// ```dart
/// // Input:
/// @PropertySource([r'${dir}/b.yml'], name: 'b', factory: YamlFactory)
/// @Configuration()
/// class Config {}
/// // Output (BeanModule argument):
/// propertySources: [
///   PropertySourceDeclaration(
///     const [r'${dir}/b.yml'],
///     name: r'b',
///     factory: YamlFactory(),
///   ),
/// ],
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ConfigurationClassParser.processPropertySource(...) loads it while
/// // parsing configuration classes, instantiating the factory reflectively:
/// @PropertySource(value = "${dir}/b.yml", name = "b",
///     factory = YamlFactory.class)
/// @Configuration
/// class Config {}
/// ```
class PropertySourceModel {
  /// Creates a property source model.
  PropertySourceModel(
    this.locations, {
    this.name,
    this.ignoreResourceNotFound = false,
    this.factoryType,
    this.conditions = const [],
    this.element,
  });

  /// Conditions of the declaring class (and of the classes importing it):
  /// the file is loaded only when they match, like Spring skipping a
  /// `@PropertySource` of a configuration class that is not registered.
  final List<ConditionModel> conditions;

  /// The declaring class (for imports of condition types).
  final Element? element;

  /// Resource locations (may contain `${...}` placeholders).
  final List<String> locations;

  /// Optional property source name.
  final String? name;

  /// Whether missing resources are skipped instead of failing.
  final bool ignoreResourceNotFound;

  /// A `PropertySourceFactory` class with a no-argument constructor.
  final InterfaceType? factoryType;
}

/// A property of an `@Introspected` class.
///
/// ```dart
/// // Input:
/// @Introspected()
/// class Form {
///   @Size(max: 3)
///   String? nick;
/// }
/// // Output:
/// BeanProperty<Form>(
///   r'nick',
///   type: String,
///   nullable: true,
///   get: (bean) => bean.nick,
///   set: (bean, value) => bean.nick = (value as String?),
///   annotations: const [Size(max: 3)],
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // BeanWrapperImpl discovers properties with java.beans.Introspector
/// // and reads/writes them through reflected getters and setters:
/// var wrapper = new BeanWrapperImpl(form);
/// wrapper.setPropertyValue("nick", "neo");
/// ```
class IntrospectedProperty {
  /// Creates an introspected property.
  IntrospectedProperty({
    required this.name,
    required this.type,
    required this.nullable,
    required this.writable,
    required this.annotations,
  });

  /// The property name.
  final String name;

  /// Non-nullable declared type.
  final InterfaceType type;

  /// Whether the declared type is nullable.
  final bool nullable;

  /// Whether the property has a setter.
  final bool writable;

  /// User annotations of the field and its getter.
  final List<DartObject> annotations;
}

/// A method of an `@Introspected` class.
///
/// ```dart
/// // Input:
/// String greet(String name, [int times = 1]) => name * times;
/// // Output:
/// BeanMethod<Form>(
///   r'greet',
///   returnType: String,
///   parameterTypes: const [String, int],
///   invoke: (bean, arguments) => Function.apply(bean.greet, arguments),
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring invokes methods reflectively, e.g. through ReflectionUtils:
/// Method greet = ReflectionUtils.findMethod(Form.class, "greet",
///     String.class, int.class);
/// ReflectionUtils.invokeMethod(greet, form, "Neo", 2);
/// ```
class IntrospectedMethod {
  /// Creates an introspected method.
  IntrospectedMethod({
    required this.name,
    required this.returnType,
    required this.parameterTypes,
    required this.annotations,
  });

  /// The method name.
  final String name;

  /// `null` for `void` (or non-class return types).
  final InterfaceType? returnType;

  /// Non-nullable types of the positional parameters.
  final List<InterfaceType> parameterTypes;

  /// User annotations of the method.
  final List<DartObject> annotations;
}

/// An `@Introspected` class.
///
/// ```dart
/// // Input:
/// @Introspected()
/// @PasswordsMatch()
/// class SignupForm {
///   @NotBlank()
///   String name = '';
/// }
/// // Output (BeanModule argument):
/// introspections: [
///   BeanIntrospection<SignupForm>(
///     properties: [BeanProperty<SignupForm>(r'name', ...)],
///     annotations: const [PasswordsMatch()],
///     instantiate: () => SignupForm(),
///   ),
/// ],
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring reflects over any class on demand; Spring 6 AOT registers
/// // reflection hints instead (RuntimeHintsRegistrar) for native images:
/// BeanUtils.getPropertyDescriptors(SignupForm.class);
/// BeanUtils.instantiateClass(SignupForm.class);
/// ```
class IntrospectionModel {
  /// Creates an introspection model.
  IntrospectionModel({
    required this.element,
    required this.type,
    required this.properties,
    required this.methods,
    required this.annotations,
    required this.instantiable,
  });

  /// Source element, for error messages.
  final Element element;

  /// The introspected class.
  final InterfaceType type;

  /// Public instance properties, subclass declarations first.
  final List<IntrospectedProperty> properties;

  /// Public instance methods that can be called with positional
  /// arguments.
  final List<IntrospectedMethod> methods;

  /// User annotations of the class.
  final List<DartObject> annotations;

  /// Whether the class has a public no-argument unnamed constructor.
  final bool instantiable;
}

/// Everything found by one component scan.
///
/// Becomes one `BeanModule` variable:
///
/// ```dart
/// // Output:
/// final BeanModule $appBeans = BeanModule(
///   r'appBeans',
///   [/* beans */],
///   propertySources: [/* propertySources */],
///   introspections: [/* introspections */],
///   configurers: {/* configurables */},
/// );
/// ```
///
/// Spring (Java):
///
/// ```java
/// // The runtime counterpart is the BeanDefinitionRegistry that scanning
/// // and ConfigurationClassPostProcessor fill:
/// var registry = new DefaultListableBeanFactory();
/// new ClassPathBeanDefinitionScanner(registry).scan("com.example.app");
/// registry.getBeanDefinitionNames();
/// ```
class ModuleModel {
  /// Beans in scan order (a configuration class before its `@Bean`s).
  final beans = <BeanModel>[];

  /// `@Introspected` classes.
  final introspections = <IntrospectionModel>[];

  /// `@Configurable` classes.
  final configurables = <ConfigurableModel>[];

  /// `@PropertySource` declarations of scanned and imported classes.
  final propertySources = <PropertySourceModel>[];

  /// Lazy proxies for `@Lazy` injection points, one per type (keyed by
  /// library URI and type name).
  final lazyProxies = <String, ProxyModel>{};

  final _proxyNames = <String>{};

  /// [name], or `name2`, `name3`... if a generated class of the module
  /// already uses it (two classes with the same name in different
  /// directories).
  String uniqueClassName(String name) {
    if (_proxyNames.add(name)) {
      return name;
    }
    for (var i = 2; ; i++) {
      final candidate = '$name$i';
      if (_proxyNames.add(candidate)) {
        return candidate;
      }
    }
  }

  final _sources = <String>{};

  /// Records [classSource] and returns `false` if that class was already
  /// scanned (component scan and `@Import` may meet the same class).
  bool markScanned(String classSource) => _sources.add(classSource);
}

/// The public `dart:` library imported by [context]'s library that exports
/// [name] (for declarations of internal libraries such as `dart:_http`),
/// else `dart:core` if it exports it, else `null`.
Uri? publicSdkLibrary(String name, Element context) {
  final library = context.library;
  if (library == null) {
    return null;
  }
  final candidates = [
    for (final fragment in library.fragments) ...fragment.importedLibraries,
  ];
  for (final candidate in candidates) {
    final uri = candidate.uri;
    if (uri.scheme == 'dart' &&
        !uri.path.startsWith('_') &&
        candidate.exportNamespace.get2(name) != null) {
      return uri;
    }
  }
  return null;
}

/// Whether [type] is declared in an internal SDK library (`dart:_...`).
bool isInternalSdkType(InterfaceType type) {
  final uri = type.element.library.uri;
  return uri.scheme == 'dart' && uri.path.startsWith('_');
}

/// A bean method carrying an annotation marked `@BeanMethodAnnotation()`,
/// written as a `BeanMethod` into `BeanDefinition.annotatedMethods`.
///
/// ```dart
/// // Input:
/// @Component()
/// class Reports {
///   @Scheduled(cron: '0 0 * * * *')
///   void hourly() { ... }
/// }
///
/// // Output (in the BeanDefinition):
/// annotatedMethods: [
///   BeanMethod<Reports>('hourly',
///     invoke: (bean, arguments) => Function.apply(bean.hourly, arguments),
///     annotations: const [Scheduled(cron: '0 0 * * * *')]),
/// ],
/// ```
class AnnotatedMethodModel {
  /// Creates the model.
  AnnotatedMethodModel({
    required this.name,
    required this.parameterTypes,
    required this.annotations,
  });

  /// The method name.
  final String name;

  /// Types of the positional parameters (`Object` for non-class types).
  final List<InterfaceType?> parameterTypes;

  /// All user annotations of the method.
  final List<DartObject> annotations;
}
