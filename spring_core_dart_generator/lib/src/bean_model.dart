// The intermediate model between `BeanScanner` (reads analyzer elements)
// and `ModuleEmitter` (writes Dart code). The scanner fills one
// [ModuleModel] per output file (a `@ComponentScan` or a
// `@SpringBootApplication`); the emitter turns it into a `*.spring.dart`
// library. Examples in this file show generated code
// without its import prefixes (`_i1.`, `_i2.`).

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spring_core_dart_generator/src/flutter_scanning.dart';
import 'package:spring_core_dart_generator/src/log_scanning.dart';

/// What an injection point asks for: one bean, all beans of a type in some
/// collection, a provider, a property value or a named resource.
///
/// The scanner derives it from the declared type and annotations of a
/// constructor parameter, field, setter or method parameter, and the
/// emitter picks the resolver call from it:
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

  /// All beans of the element type, as a `List` or `Iterable`, in order.
  list,

  /// All beans of the element type, as a `Set`.
  set,

  /// All beans of the value type, keyed by bean name (`Map<String, T>`).
  map,

  /// An `ObjectProvider<T>` (or `ObjectFactory<T>`, `Provider<T>`): the
  /// bean is looked up when the code asks for it, not at injection.
  provider,

  /// A `@Value` expression, resolved against the environment and
  /// converted to the declared type.
  value,

  /// A `@Resource` field or setter: the bean named [InjectionPoint.name]
  /// (`r.resource<T>('name')`).
  resource,
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
  /// Creates an injection point; [type] must not be nullable, since
  /// nullability is expressed by [optional].
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
    this.fallbackToType = false,
    this.exactType,
  });

  /// A copy for a constructor or `@Bean` method parameter.
  ///
  /// A Dart [defaultValue] makes the point optional: the default is used
  /// when nothing is found. With [collectionsMayBeEmpty], a required
  /// collection without a default resolves to an empty one when no bean
  /// matches, like Spring's `ConstructorResolver` fallback for single
  /// constructors.
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
    fallbackToType: fallbackToType,
    exactType: exactType,
    allowEmpty:
        collectionsMayBeEmpty &&
        defaultValue == null &&
        !optional &&
        (kind == PointKind.list ||
            kind == PointKind.set ||
            kind == PointKind.map),
  );

  /// A copy marked [optional], for the `dependencies` metadata of a bean
  /// with alternative constructors, where no single parameter is required.
  /// The lookup in the generated code is unchanged. A `@Value` point is
  /// returned as it is.
  InjectionPoint asOptional() => kind == PointKind.value
      ? this
      : InjectionPoint(
          kind: kind,
          type: type,
          optional: true,
          qualifier: qualifier,
          name: name,
          expression: expression,
          defaultValue: defaultValue,
          lazy: lazy,
          allowEmpty: allowEmpty,
          fallbackToType: fallbackToType,
          exactType: exactType,
        );

  /// How the value is looked up: one bean, a collection, a value...
  final PointKind kind;

  /// The requested bean type (the element type for collections and
  /// providers), or the target type of a `@Value`; never nullable.
  final InterfaceType type;

  /// Whether the point may stay unsatisfied: its type is nullable in the
  /// source, or it has a Dart default value.
  ///
  /// An optional point resolves to `null` (or an absent collection)
  /// instead of failing, like `@Autowired(required = false)` in Spring.
  final bool optional;

  /// The `@Qualifier` or `@Named` value, if any.
  final String? qualifier;

  /// The parameter or field name. Among several beans of the type, the
  /// one with this name is chosen.
  final String? name;

  /// The `@Value` expression, for a [PointKind.value] point.
  final String? expression;

  /// The parameter's Dart default value, used when no bean (or property)
  /// is found.
  final DartObject? defaultValue;

  /// Whether a required collection resolves to an empty collection when
  /// no bean matches (constructor and `@Bean` method parameters only).
  final bool allowEmpty;

  /// For a `@Lazy` single bean: the generated lazy proxy that is injected
  /// instead and resolves the bean on every member access (Spring's
  /// lazy-resolution proxy).
  final ProxyModel? lazy;

  /// For a `@Resource` point without an explicit name: inject by type when
  /// no bean has the field or setter name (Spring's
  /// `fallbackToDefaultTypeMatch`).
  final bool fallbackToType;

  /// For a single bean of a function or record type: that type. [type] is
  /// then `Function` or `Record`, which cannot tell such beans apart.
  final DartType? exactType;
}

/// One argument of a call the generated code makes to create or set up a
/// bean (a constructor, a `@Bean` method, an `@Autowired` method): what to
/// inject and, for a named parameter, under which name.
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

  /// The parameter's name for a named parameter, `null` for a positional
  /// one. A private named parameter is passed under its public name.
  final String? namedAs;
}

/// How the container creates a bean instance; the emitter writes it as the
/// `create` closure of the `BeanDefinition`.
///
/// It is one of: a constructor call ([ConstructorCreation]), a `@Bean`
/// method call ([BeanMethodCreation]), a generated interface
/// implementation ([InterfaceProxyCreation]), or constructor binding of a
/// `@ConfigurationProperties` class ([ConfigurationPropertiesCreation]).
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
  /// The arguments passed to the constructor or factory method, in order;
  /// empty for creations that inject nothing themselves.
  List<Argument> get arguments;
}

/// A bean created by calling a constructor of its class, `Type(args)` or
/// `Type.named(args)`: the usual creation of a component.
///
/// The constructor is the `@Autowired` one, else the only public one, the
/// primary constructor, or the one callable without arguments; any other
/// choice is ambiguous and fails the build. For a full-mode
/// `@Configuration` class or a class with `@Lookup` methods, the generated
/// subclass is created instead.
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
  ConstructorCreation(
    this.constructorName,
    this.arguments, {
    this.configuration,
    this.lookup,
    this.alternatives = const [],
  });

  /// The constructor's name; `null` for the unnamed constructor.
  final String? constructorName;

  @override
  final List<Argument> arguments;

  /// For a full-mode `@Configuration` class: the generated subclass that is
  /// created instead (its constructor takes the bean factory first).
  final ConfigurationClassModel? configuration;

  /// For a class with `@Lookup` methods: the generated subclass that is
  /// created instead (its constructor takes the bean factory first).
  final LookupClassModel? lookup;

  /// The other `@Autowired(required: false)` constructors, fewer
  /// parameters last: the constructor above is called when the beans of
  /// its parameters exist, else the first alternative whose beans exist,
  /// else the last one (Spring's ConstructorResolver).
  ///
  /// ```dart
  /// create: (r) => r.containsBeanOfType(Clock)
  ///     ? Report(r.dependency<Clock>(name: r'clock'))
  ///     : Report(),
  /// ```
  final List<ConstructorAlternative> alternatives;
}

/// Another `@Autowired(required: false)` constructor the container may call
/// when the beans of the selected one are missing (see
/// [ConstructorCreation.alternatives]).
class ConstructorAlternative {
  /// Creates an alternative; [constructorName] is `null` for the unnamed
  /// constructor.
  ConstructorAlternative(this.constructorName, this.arguments);

  /// The constructor's name; `null` for the unnamed constructor.
  final String? constructorName;

  /// One argument per parameter, in order.
  final List<Argument> arguments;
}

/// A bean that is a generated implementation of an annotated interface,
/// such as a `@FeignClient`: `_$XImpl.$create(r)`.
///
/// The interface has no class to construct, so the generator writes one
/// whose methods forward every call to an `InvocationHandler`. It gets the
/// handler for interface `X` from the `InvocationHandlerFactory` bean of
/// the starter that owns the annotation.
///
/// ```dart
/// // Input:
/// @FeignClient('catalog')
/// abstract interface class CatalogClient { ... }
/// // Output:
/// create: (r) => _$CatalogClientImpl.$create(r),
/// ```
class InterfaceProxyCreation extends Creation {
  /// Creates the interface proxy of [model].
  InterfaceProxyCreation(this.model);

  /// The interface and the methods the generated class implements.
  final InterfaceProxyModel model;

  @override
  List<Argument> get arguments => const [];
}

/// A `@ConfigurationProperties` class whose constructor parameters are
/// bound from properties instead of injected as beans.
///
/// The bean is created by `ConstructorBound.from` of `spring_boot_dart` at
/// runtime, which reads the constructor through the class's introspection
/// and passes the bound values. Spring Boot calls this constructor
/// binding.
///
/// ```dart
/// // Input:
/// @ConfigurationProperties('db')
/// class DbProperties {
///   const DbProperties(this.url, {this.maxSize = 10});
///   final String url;
///   final int maxSize;
/// }
/// // Output:
/// create: (r) => ConstructorBound.from<DbProperties>(r, r'dbProperties'),
/// ```
class ConfigurationPropertiesCreation extends Creation {
  /// Creates the constructor-bound creation; it needs no data, since the
  /// runtime reads the constructor from the introspection.
  ConfigurationPropertiesCreation();

  @override
  List<Argument> get arguments => const [];
}

/// A bean created by calling a `@Bean` method of another bean (its
/// owner), or a static `@Bean` method.
///
/// An instance method is called on the owning bean, looked up by its name.
/// For a full-mode `@Configuration` owner the call goes through
/// `_$method(r)` of the generated subclass (see [enhanced]). A static
/// method is called on its class, and no owner instance is created.
///
/// ```dart
/// // Input:
/// @Configuration(proxyBeanMethods: false)
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
  /// Creates a `@Bean` method call.
  BeanMethodCreation({
    required this.ownerType,
    required this.ownerName,
    required this.methodName,
    required this.isStatic,
    required this.arguments,
    this.enhanced,
    this.declaredType,
  });

  /// The type of the owning bean, or the declaring class of a static
  /// method.
  final InterfaceType ownerType;

  /// For an instance method of a full-mode `@Configuration` class: its
  /// override in the generated subclass. The container then calls
  /// `_$method(r)`, which runs the original method.
  final EnhancedBeanMethod? enhanced;

  /// The method's declared return type when the bean type (inferred from
  /// the method body) is more specific; the call is cast to the bean type.
  final InterfaceType? declaredType;

  /// The bean name of the owner, used as qualifier to look it up.
  final String ownerName;

  /// The name of the `@Bean` method.
  final String methodName;

  /// Whether the method is static: it is called on the class, and no
  /// owner instance is needed.
  final bool isStatic;

  @override
  final List<Argument> arguments;
}

/// The generated subclass of a full-mode `@Configuration` class, whose
/// `@Bean` methods return the container's bean.
///
/// Without it, a `@Bean` method that calls another one (`calculator()`)
/// would create a second object instead of using the bean. The container
/// creates this subclass instead of the class, so such a call gets the
/// singleton (for a prototype, a new instance created by the container).
/// `@Configuration(proxyBeanMethods: false)` turns it off. Spring does the
/// same with a CGLIB subclass.
///
/// ```dart
/// // Input:
/// @Configuration()
/// class AppConfig {
///   @Bean()
///   Calculator calculator() => Calculator();
///
///   @Bean()
///   Pricing pricing() => Pricing(calculator()); // the singleton
/// }
///
/// // Output:
/// final class _$AppConfigConfiguration extends AppConfig {
///   _$AppConfigConfiguration(this._$beanFactory) : super();
///   final BeanFactory _$beanFactory;
///
///   @override
///   Calculator calculator() =>
///       _$beanFactory.getBeanByName(r'calculator') as Calculator;
///
///   Calculator _$calculator(DependencyResolver r) => super.calculator();
///   // ...
/// }
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ConfigurationClassEnhancer subclasses AppConfig with CGLIB at
/// // startup; its BeanMethodInterceptor calls beanFactory.getBean(...)
/// // unless the container itself is invoking the factory method.
/// ```
class ConfigurationClassModel {
  /// Creates the model; [beanMethods] are added afterwards.
  ConfigurationClassModel({
    required this.className,
    required this.type,
    required this.constructorName,
    required this.constructorParameters,
    required this.isBase,
  });

  /// The name of the generated subclass, e.g. `_$AppConfigConfiguration`,
  /// unique in the module.
  final String className;

  /// The configuration class it extends.
  final InterfaceType type;

  /// The super constructor the subclass calls; `null` for the unnamed
  /// one.
  final String? constructorName;

  /// Parameters of the super constructor, forwarded as super parameters
  /// (they keep their types and default values).
  final List<ProxyParameter> constructorParameters;

  /// Whether the configuration class is `base` (the subclass must then be
  /// `base`, `final` or `sealed`; it is always emitted `final`).
  final bool isBase;

  /// The overridden `@Bean` methods; static ones are not overridden.
  final List<EnhancedBeanMethod> beanMethods = [];
}

/// The generated subclass of a bean class with `@Lookup` methods, which
/// overrides each of them to return a bean of the container per call.
///
/// A singleton that needs a fresh prototype for every use (a command, a
/// request object) cannot get it injected once. A `@Lookup` method asks
/// the container each time instead. The container creates this subclass
/// in place of the class. Spring calls this lookup method injection and
/// does it with a CGLIB subclass.
///
/// ```dart
/// // Input:
/// @Component()
/// abstract class CommandManager {
///   @Lookup()
///   Command createCommand();
/// }
///
/// // Output:
/// class _$CommandManagerLookup extends CommandManager {
///   _$CommandManagerLookup(this._$beanFactory) : super();
///   final BeanFactory _$beanFactory;
///
///   @override
///   Command createCommand() => this._$beanFactory.getBean<Command>();
/// }
/// // ...and in the bean definition:
/// create: (r) => _$CommandManagerLookup(r),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // CglibSubclassingInstantiationStrategy subclasses the bean class; its
/// // LookupOverrideMethodInterceptor calls beanFactory.getBean(...).
/// ```
class LookupClassModel {
  /// Creates the model of the subclass [className] of [type].
  LookupClassModel({
    required this.className,
    required this.type,
    required this.constructorName,
    required this.constructorParameters,
    required this.isBase,
    required this.methods,
  });

  /// The name of the generated subclass, e.g. `_$CommandManagerLookup`.
  final String className;

  /// The bean class it extends.
  final InterfaceType type;

  /// The super constructor the subclass calls; `null` for the unnamed
  /// one.
  final String? constructorName;

  /// Parameters of the super constructor, forwarded as super parameters.
  final List<ProxyParameter> constructorParameters;

  /// Whether the bean class is `base` (the subclass is then emitted
  /// `final`; a subclass proxy in the same library may still extend it).
  final bool isBase;

  /// The overridden `@Lookup` methods, inherited ones included.
  final List<LookupMethod> methods;
}

/// One `@Lookup` method that a [LookupClassModel] overrides.
class LookupMethod {
  /// Creates the model.
  LookupMethod({
    required this.name,
    required this.beanName,
    required this.returnType,
  });

  /// The method name.
  final String name;

  /// The name of the bean returned (`@Lookup('name')`); `null` looks the
  /// bean up by [returnType].
  final String? beanName;

  /// The declared return type. When it is nullable, the method returns
  /// `null` if no bean matches instead of throwing.
  final DartType returnType;
}

/// One `@Bean` method that the subclass of a [ConfigurationClassModel]
/// overrides: the override returns the container's bean, and
/// `_$<method>(r)` keeps the original body for the container to call.
class EnhancedBeanMethod {
  /// Creates the model.
  EnhancedBeanMethod({
    required this.className,
    required this.methodName,
    required this.beanName,
    required this.returnType,
    required this.parameters,
    required this.defaults,
    required this.arguments,
    required this.isFactoryBean,
    required this.isSingleton,
  });

  /// The name of the generated subclass that overrides the method.
  final String className;

  /// The method name.
  final String methodName;

  /// The name of the bean the override returns.
  final String beanName;

  /// The declared return type (nullable for a method that may return
  /// `null`, a function or record type for such beans).
  final DartType returnType;

  /// The method's parameters, repeated by the override.
  final List<ProxyParameter> parameters;

  /// The default value of each optional parameter (by name), re-created as
  /// a constant in the override.
  final Map<String, DartObject> defaults;

  /// How the container resolves each parameter (same order as
  /// [parameters]).
  final List<Argument> arguments;

  /// Whether the bean is a `FactoryBean`: an inter-bean call then gets the
  /// factory itself (`&name`), not its product.
  final bool isFactoryBean;

  /// Whether the bean is a singleton. Like Spring, a singleton ignores the
  /// arguments of an inter-bean call when one of them is `null`, while a
  /// prototype is created with them.
  final bool isSingleton;
}

/// A field or setter the container assigns after it constructs the bean:
/// `bean.name = value` in the generated `inject` closure.
///
/// The scanner records one for every `@Autowired`, `@Value` or `@Resource`
/// field and setter, inherited ones included.
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
  PropertyInjection(this.name, this.point, {this.rank = 0});

  /// The field or setter name.
  final String name;

  /// What to assign.
  final InjectionPoint point;

  /// The position in the injection order; lower runs first (see
  /// [injectionRank]).
  final int rank;
}

/// The position in the injection order of a member declared by the class
/// at [depth] in the hierarchy (0 for the topmost superclass); lower runs
/// first.
///
/// The order matters when a setter or `@Autowired` method uses another
/// injected member. Superclass members come first, and per class fields
/// ([field]) come before setters and `@Autowired` methods, as in Spring's
/// `buildAutowiringMetadata`.
int injectionRank(int depth, {required bool field}) =>
    depth * 2 + (field ? 0 : 1);

/// [items] sorted by [rank], keeping their order within a rank.
///
/// This is a stable sort, which `List.sort` does not promise; the emitter
/// uses it to order injections by [injectionRank].
List<T> sortedByRank<T>(Iterable<T> items, int Function(T item) rank) => [
  for (final (_, item)
      in items.indexed.toList()..sort((a, b) {
        final byRank = rank(a.$2) - rank(b.$2);
        return byRank != 0 ? byRank : a.$1 - b.$1;
      }))
    item,
];

/// An `@Autowired` method the container calls after it constructs the bean
/// and sets its fields: `bean.name(args)` in the generated `inject`
/// closure, with every argument injected.
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
  MethodInjection(this.name, this.arguments, {this.rank = 0});

  /// The `@Autowired` method name.
  final String name;

  /// What to inject for each parameter, in order.
  final List<Argument> arguments;

  /// The position in the injection order; lower runs first (see
  /// [injectionRank]).
  final int rank;
}

/// A condition on a bean, written into its `BeanDefinition.conditions`.
///
/// Conditions decide when the context refreshes whether a bean is
/// registered: `@Profile`, `@Conditional`, or a const annotation that
/// implements `Condition` itself. Each subclass is one way to write the
/// condition as code.
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

/// A `@Profile([...])` condition: the bean is registered only when one of
/// the profile expressions matches the active profiles.
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

  /// The profile expressions (`cloud`, `!test`); the bean is registered if
  /// any of them matches.
  final List<String> profiles;
}

/// A `@Conditional([Type])` condition: the generated code creates the
/// `Condition` class with its no-argument constructor.
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

/// The conditions of a configuration class, evaluated once for the class,
/// its `@Bean` methods and its `@PropertySource`s.
///
/// Without the group, every `@Bean` method would evaluate the class's
/// conditions again, and they could disagree (a condition that looks at
/// beans registered so far). The runtime caches the result per [key].
///
/// ```dart
/// // Output: ConditionGroup(r'package:a/b.dart#Config', [ ... ])
/// ```
class GroupConditionModel extends ConditionModel {
  /// Groups [conditions] under [key].
  GroupConditionModel(this.key, this.conditions);

  /// The configuration class, as `library#Class`; the runtime caches the
  /// group's result under it.
  final String key;

  /// The class's conditions.
  final List<ConditionModel> conditions;
}

/// A condition written as a const annotation that implements `Condition`
/// itself; the generated code re-creates the annotation as a constant.
///
/// This lets a condition take arguments (`@OnMode(Mode.on)`) without a
/// separate `Condition` class.
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
class AnnotationConditionModel extends ConditionModel {
  /// Creates a condition re-created from the constant [value].
  AnnotationConditionModel(this.value);

  /// The evaluated annotation instance.
  final DartObject value;
}

/// A method of a bean that handles application events: an
/// `@EventListener` method, or `onApplicationEvent` of an
/// `ApplicationListener` bean.
///
/// The emitter writes it as an `EventListenerMethod` in the bean's
/// `eventListeners`, so the context can call the method without
/// reflection.
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
    this.resultType,
    this.order,
    this.condition,
    this.async = false,
    this.asyncExecutor,
  });

  /// The listener id: `@EventListener(id: ...)`, else `Class.method`.
  final String id;

  /// The method that handles the event.
  final String methodName;

  /// The event (or payload) types the method accepts: the
  /// `@EventListener(classes: ...)` list, else the parameter type.
  final List<InterfaceType> eventTypes;

  /// The method's parameter type; `null` for a method without parameters.
  final InterfaceType? parameterType;

  /// Whether the method's result is published as a new event.
  final bool returnsValue;

  /// The declared type of the published result (the element type of an
  /// `Iterable`), emitted as `resultType: EventResultType<R>()` so results
  /// reach `PayloadApplicationEvent<R>` listeners; `null` when unknown.
  final InterfaceType? resultType;

  /// The `@Order` value of the method (of the class for an
  /// `ApplicationListener`); `null` when unordered.
  final int? order;

  /// The `@EventListener(condition: ...)` filter: a top-level or static
  /// `bool Function(E)` that decides per event whether the method runs.
  final ExecutableElement? condition;

  /// Whether the method carries `@Async`, so it runs on an executor
  /// instead of the publisher's call (emitted as `async: Async(...)`).
  final bool async;

  /// The executor bean name of `@Async('name')`; `null` for the default
  /// executor.
  final String? asyncExecutor;
}

/// A `BeanRegistrar`, `ImportSelector` or `ImportBeanDefinitionRegistrar`
/// class named in an `@Import`.
///
/// Such a class registers beans with code instead of annotations, so it is
/// not scanned. The module lists it in `registrars`, and the runtime
/// creates it and lets it register its beans, only when the importing
/// class's conditions match.
///
/// ```dart
/// // Input:
/// @Configuration()
/// @Import([MessagingRegistrar])
/// @Profile(['cloud'])
/// class AppConfig {}
/// // Output (BeanModule argument):
/// registrars: [
///   ImportDeclaration(
///     MessagingRegistrar.new,
///     conditions: [ConditionGroup(..., [const ProfileCondition(['cloud'])])],
///     importer: 'package:app/app.dart#AppConfig',
///   ),
/// ],
/// ```
///
/// Spring (Java):
/// ```java
/// // ConfigurationClassParser.processImports instantiates it reflectively:
/// @Configuration
/// @Import(MessagingRegistrar.class)
/// @Profile("cloud")
/// class AppConfig {}
/// ```
class RegistrarModel {
  /// Creates a registrar model.
  RegistrarModel(
    this.type,
    this.element, {
    required this.importer,
    this.conditions = const [],
  });

  /// The registrar or selector class; it needs a no-argument constructor.
  final InterfaceType type;

  /// The importing class, from which the types in [conditions] are
  /// imported and errors are reported.
  final Element element;

  /// The conditions of the importing class; the registrar runs only when
  /// they match.
  final List<ConditionModel> conditions;

  /// The importing class, as `library#Class`; it places the import among
  /// the module's classes at runtime.
  final String importer;
}

/// Where the generated code takes the value of one parameter of an advice
/// method from: the join point, the returned value or thrown error, or a
/// value the pointcut binds.
///
/// Spring binds these parameters by reflection when the advice runs;
/// here the scanner works them out once, and the emitter writes the call.
///
/// ```dart
/// // Input:
/// @AfterReturning('all() && @annotation(timed)', returning: 'result')
/// void returned(JoinPoint jp, Timed timed, String result) {}
/// // Output:
/// invoke: (aspect, joinPoint, value, bindings) => aspect.returned(
///     joinPoint, (bindings[r'timed'] as Timed), (value as String)),
/// bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is Timed)},
/// ```
///
/// Spring (Java):
///
/// ```java
/// // AbstractAspectJAdvice binds JoinPoint/ProceedingJoinPoint, the
/// // returning/throwing argument and the pointcut's formals by
/// // reflection on the advice method:
/// @AfterReturning(pointcut = "all() && @annotation(timed)",
///     returning = "result")
/// void returned(JoinPoint jp, Timed timed, String result) {}
/// ```
sealed class AdviceParameter {
  const AdviceParameter();
}

/// A parameter that receives the join point: a `JoinPoint`, or a
/// `ProceedingJoinPoint` (only in `@Around` advice) when [proceeding].
final class JoinPointParameter extends AdviceParameter {
  /// Creates the parameter.
  const JoinPointParameter({required this.proceeding});

  /// Whether the parameter is a `ProceedingJoinPoint`, which the generated
  /// call casts the join point to.
  final bool proceeding;
}

/// A parameter that receives the returned value (`@AfterReturning`) or
/// the thrown error (`@AfterThrowing`).
final class ValueParameter extends AdviceParameter {
  /// Creates the parameter of type [type].
  const ValueParameter(this.type);

  /// The declared parameter type; the advice only runs for values of this
  /// type.
  final DartType type;
}

/// A parameter the pointcut binds (`@annotation(timed)`, `args(id, ..)`,
/// `this(proxy)`, `target(bean)`): the generated advice takes it from the
/// bindings map by [name].
final class BoundParameter extends AdviceParameter {
  /// Creates the parameter [name] of type [type].
  const BoundParameter(this.name, this.type);

  /// The parameter name, as written in the pointcut.
  final String name;

  /// The declared parameter type; the pointcut only matches when the bound
  /// value has it.
  final DartType type;
}

/// One advice method of an `@Aspect` class (`@Before`, `@Around`...): its
/// kind, its pointcut and how to call it.
///
/// The emitter writes it as an `AspectAdvice` whose `invoke` closure calls
/// the method directly, since the runtime cannot find or call it by
/// reflection.
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

  /// The advice kind: `around`, `before`, `after`, `afterReturning` or
  /// `afterThrowing`.
  final String kind;

  /// The pointcut expression, or a reference to a named `@Pointcut`.
  final String pointcut;

  /// The advice method name.
  final String methodName;

  /// How each positional parameter of the advice method is filled.
  final List<AdviceParameter> parameters;

  /// The type of the value parameter (return value or error), if there is
  /// one.
  final DartType? valueType;

  /// The parameters the pointcut binds, in parameter order.
  List<BoundParameter> get bindings => [
    for (final parameter in parameters)
      if (parameter is BoundParameter) parameter,
  ];
}

/// What the generator knows about an `@Aspect` class: its advice methods,
/// its named pointcuts and its introductions.
///
/// It is written as the bean's `AspectMetadata`, from which the runtime
/// builds the advisors. The build also uses it to check every pointcut
/// and to decide which beans no pointcut can match.
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
  AspectModel(
    this.advice,
    this.pointcuts, {
    this.perClause,
    this.typeTests = const {},
    this.argumentAnnotations = const {},
    this.introductions = const [],
  });

  /// The advice methods, in declaration order.
  final List<AdviceModel> advice;

  /// The named pointcuts: `@Pointcut` method name to expression.
  final Map<String, String> pointcuts;

  /// The `perthis(...)` or `pertarget(...)` clause of `@Aspect('...')`,
  /// which creates one aspect instance per advised object; `null` for a
  /// singleton aspect.
  final String? perClause;

  /// Types named in `args(...)` of the aspect's expressions, by the name
  /// written there: the runtime tests the argument against them (AspectJ
  /// matches `args` by the runtime type of the argument).
  final Map<String, InterfaceType> typeTests;

  /// Annotation names in `@args(...)` of the aspect's expressions; the
  /// emitter writes, for each, which scanned classes carry it.
  final Set<String> argumentAnnotations;

  /// The `@DeclareParents` fields of the aspect.
  final List<IntroductionModel> introductions;
}

/// What the build knows about the advice of an application's other
/// modules, so it can tell which beans no pointcut can match and skip
/// their proxy classes.
///
/// A bean of one module may be advised by an aspect of another. The
/// `@SpringBootApplication` output knows every module of the application
/// at build time: its scan, the nested `@ComponentScan` modules it imports
/// and the auto-configurations. A `@ComponentScan` module does not, since
/// any other module may import it, so it is never pruned.
///
/// ```dart
/// // The aspects of a nested module, then the application's emitter.
/// final foreign = ForeignAdvice()
///   ..aspects.add(('AuditAspect', auditAspectModel));
/// ModuleEmitter(output, foreignAdvice: foreign).emit(...);
/// ```
///
/// Spring (Java):
/// ```java
/// // No equivalent: Spring creates proxies at runtime, once every advisor
/// // of the context is known.
/// ```
class ForeignAdvice {
  /// The aspects of the other modules, with the aspect class name.
  final aspects = <(String, AspectModel)>[];

  /// Whether another module declares an advisor bean whose pointcut the
  /// build cannot read, which may match anything; nothing is pruned then.
  bool advisors = false;

  /// Whether another module may declare advice the build cannot read (an
  /// auto-configuration with aspects); nothing is pruned then.
  bool unknown = false;
}

/// A `@DeclareParents` field of an aspect: it adds an interface to beans
/// that do not implement it.
///
/// The proxies of the beans whose class matches [typePattern] also
/// implement [interfaceType], and forward its members to one [defaultImpl]
/// instance per proxy. Code can then cast such a bean to the interface.
/// Spring does the same with a `DeclareParentsAdvisor`.
///
/// ```dart
/// // Input:
/// @DeclareParents('Orders+', defaultImpl: DefaultUsageTracked)
/// static UsageTracked? mixin;
/// // Output, in the proxy of Orders:
/// class _$OrdersProxy implements Orders, UsageTracked, Advised {
///   @override
///   int get useCount =>
///       (this._invoker.introduction(0) as UsageTracked).useCount;
/// }
/// ```
///
/// Spring (Java):
///
/// ```java
/// @DeclareParents(value = "com.x.Orders+",
///     defaultImpl = DefaultUsageTracked.class)
/// public static UsageTracked mixin;
/// ```
class IntroductionModel {
  /// Creates the model.
  IntroductionModel({
    required this.aspectType,
    required this.typePattern,
    required this.interfaceType,
    required this.defaultImpl,
    required this.members,
  });

  /// The name of the declaring aspect class.
  final String aspectType;

  /// The `@DeclareParents` type pattern: a simple name with `*` wildcards,
  /// and `+` for subtypes too (`Orders+`, `*Service`).
  final String typePattern;

  /// The introduced interface.
  final InterfaceType interfaceType;

  /// The class created per proxy (`defaultImpl:`).
  final InterfaceType defaultImpl;

  /// The members of [interfaceType] the proxy forwards.
  final List<ProxyMember> members;
}

/// The name generated code gives the parameter at [index] of
/// [parameters] when it repeats a signature (proxies, overrides).
///
/// That is the parameter's own name, or for a wildcard (`_`, which cannot
/// be read) or an unnamed one a fresh `p<index>` that no other parameter
/// uses.
String forwardedParameterName(
  List<FormalParameterElement> parameters,
  int index,
) {
  final name = parameters[index].name;
  if (name != null && name.isNotEmpty && name != '_') {
    return name;
  }
  final taken = {for (final parameter in parameters) parameter.name};
  var underscores = 0;
  String candidate() => 'p$index${'_' * underscores}';
  while (taken.contains(candidate())) {
    underscores++;
  }
  return candidate();
}

/// A parameter of a method or constructor that a generated class repeats:
/// a proxy method, an overriding `@Bean` or `@Lookup` method, or a
/// forwarding constructor.
///
/// The repeated signature must match the original, so it keeps the name,
/// type, kind and default value.
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
  /// Creates a parameter; give [defaultValueCode] or [defaultValue] for an
  /// optional parameter with a default.
  ProxyParameter({
    required this.name,
    required this.type,
    required this.isNamed,
    required this.isRequired,
    this.defaultValueCode,
    this.defaultValue,
    this.annotations = const [],
  });

  /// The parameter name, as generated code writes it (see
  /// [forwardedParameterName]).
  final String name;

  /// The declared parameter type.
  final DartType type;

  /// The user annotations of the parameter, from the implementation and
  /// the interface. Method validation reads its constraints from them.
  final List<DartObject> annotations;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Whether the parameter is required: a required positional one, or a
  /// `required` named one.
  final bool isRequired;

  /// The source of the default value when it is a simple literal, copied
  /// as written.
  final String? defaultValueCode;

  /// The default value when it is another constant (re-created as code);
  /// `null` when [defaultValueCode] is set or there is no default.
  final DartObject? defaultValue;
}

/// Whether a proxied member is a method, a getter or a setter.
///
/// Dart proxies forward getters and setters too, so pointcuts can tell
/// them apart and the generated code calls them the right way.
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

/// A method, getter or setter that a generated proxy overrides, so advice
/// can run around it, with everything a pointcut may test about it.
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
    required this.returnType,
    required this.typeParameters,
    required this.parameters,
    required this.annotations,
    this.declaringTypes = const [],
    List<DartObject>? mergedAnnotations,
  }) : mergedAnnotations = mergedAnnotations ?? annotations;

  /// For an inherited member: the class whose body runs for it, then that
  /// class's supertypes. Empty when the target class declares the member.
  /// `within` and `@within` match the type that declares the code, as in
  /// AspectJ.
  List<String> implementingTypes = const [];

  /// The annotations of `implementingTypes.first`, for `@within`.
  List<DartObject> implementingTypeAnnotations = const [];

  /// Annotations of each superclass and mixin (those that have some) of
  /// the class whose body runs for the member (the target class when it is
  /// not inherited), nearest first: `MethodSignature.superclassAnnotations`,
  /// for find semantics on classes (`@CacheConfig`, class-level
  /// `@Cacheable`).
  List<List<DartObject>> superclassAnnotations = const [];

  /// Whether the member is `@protected` (from `package:meta`), for
  /// `execution(protected ...)`.
  bool isProtected = false;

  /// Whether the member is a method, a getter or a setter.
  final ProxyMemberKind kind;

  /// The member name.
  final String name;

  /// The simple name of the type reported as declaring the member: the
  /// first abstract supertype that declares it, else the target class.
  final String declaringType;

  /// The simple names of every proxied type that declares the member.
  final List<String> declaringTypes;

  /// The return type for methods and getters, the value type for setters.
  final DartType returnType;

  /// The type parameters of a generic method; empty otherwise.
  final List<TypeParameterElement> typeParameters;

  /// The parameters, in declaration order.
  final List<ProxyParameter> parameters;

  /// The user annotations of the implementation and of its interface
  /// declarations, plus the constraints and `@Valid` of every declaration.
  /// `@annotation(...)` pointcuts match against them.
  final List<DartObject> annotations;

  /// The user annotations of the implementation and of every declaration
  /// it overrides or implements (superclasses, mixins, interfaces), most
  /// specific first. They become `MethodSignature.mergedAnnotations`, which
  /// annotation-driven advisors (`@Cacheable`, `@Validated`) read.
  final List<DartObject> mergedAnnotations;
}

/// The generated AOP proxy class of one bean: a class that implements the
/// bean's types and runs the matching advice around each call before
/// forwarding it to the bean.
///
/// Dart cannot create such classes at runtime, so every bean that advice
/// may match gets one at build time. The runtime wraps the bean in it only
/// when an advisor actually matches; otherwise the bean is used as it is.
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
///   // aopTarget, aopAdvisors, toString and one override per member
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
    this.subclass,
  });

  /// The name of the generated class, e.g. `_$EnglishGreeterProxy`, or
  /// `_$Config$ClockProxy` for a `@Bean` method.
  final String className;

  /// The type the proxy forwards to: the bean class, or a `@Bean` method's
  /// return type.
  final InterfaceType targetType;

  /// The types the proxy `implements`, besides `Advised`.
  final List<InterfaceType> interfaces;

  /// The forwarded members; a member's index is its id at runtime.
  final List<ProxyMember> members;

  /// The user annotations of the target class, for `@within(...)`-style
  /// matching.
  final List<DartObject> classAnnotations;

  /// The simple names of the target type and all its supertypes, for
  /// type patterns.
  final List<String> targetTypeNames;

  /// Whether the target's `toString` takes parameters, so it is forwarded
  /// like any other member instead of the generated `toString()`.
  final bool customToString;

  /// Why no proxy class is generated: the type cannot be proxied, or the
  /// build pruned it. Then only the signatures are emitted
  /// (`AopProxyFactory.unavailable`), so advice that matches anyway fails
  /// the startup with this reason instead of being skipped silently.
  String? unavailableReason;

  /// Set when the proxy is a subclass of the target, created by the
  /// container as the bean itself, instead of a wrapper around it.
  final SubclassProxy? subclass;

  /// `@DeclareParents` introductions the proxy class implements, in the
  /// order of their runtime index.
  final introductions = <IntroductionModel>[];
}

/// The extra data of a subclass proxy: a generated class that extends the
/// bean class instead of wrapping it, like a CGLIB proxy in Spring.
///
/// It forwards the bean's constructor and overrides the public members to
/// run advice. The container creates the proxy class as the bean, and
/// advice is attached afterwards (`_$advise`). It is used, in
/// `aop_proxies: all` mode, for a component class that no generated class
/// can implement (private members, operators, `final` or `base`):
/// wrapping only its interfaces would hide the class itself.
///
/// ```dart
/// // Input:
/// @Service()
/// class Counter {
///   Counter(this.step, {this.name = 'n'});
///   int _n = 0;
///   int next() => _n += step;
/// }
/// // Output:
/// class _$CounterProxy extends Counter implements Advised {
///   _$CounterProxy(super.p0, {super.name});
///   ProxyInvoker? _$invoker;
///   _$CounterProxy _$advise(ProxyInvoker invoker) { ... }
///   @override int next() { ... super.next() through the advice ... }
/// }
/// // ...and in the bean definition:
/// create: (r) => _$CounterProxy(r.dependency<int>(name: r'step')),
/// aopProxy: AopProxyFactory.subclass(
///   signatures: const [MethodSignature(name: r'next', ...)],
///   advise: (bean, invoker) =>
///       bean is _$CounterProxy ? bean._$advise(invoker) : null,
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // CglibAopProxy generates a subclass of the bean class at runtime and
/// // creates the proxy from it (ObjenesisCglibAopProxy):
/// Enhancer enhancer = new Enhancer();
/// enhancer.setSuperclass(Counter.class);
/// enhancer.setCallbacks(callbacks);
/// ```
class SubclassProxy {
  /// Creates the model.
  SubclassProxy({
    required this.constructorName,
    required this.constructorParameters,
    required this.isFinal,
  });

  /// The bean constructor the subclass forwards to; `null` for the
  /// unnamed one.
  final String? constructorName;

  /// The constructor's parameters, forwarded as `super.` parameters.
  final List<ProxyParameter> constructorParameters;

  /// Whether the subclass is emitted `final`, which Dart requires when the
  /// bean class is `base`.
  final bool isFinal;
}

/// One bean of the module: everything the emitter needs to write its
/// `BeanDefinition`.
///
/// The scanner creates one per component class and per `@Bean` method,
/// with its name, types, creation, injections, lifecycle methods,
/// conditions, listeners and proxy. Each field maps to an argument of the
/// generated `BeanDefinition`; arguments at their runtime default are left
/// out.
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
  /// Creates a bean model; the defaults match Spring's: singleton, eager,
  /// autowire candidate.
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
    this.defaultCandidate = true,
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
    this.destroyMethodInferred = false,
    this.asyncLifecycleMethods = const {},
    this.listeners = const [],
    this.annotatedMethods = const [],
    this.annotations = const [],
    this.aspect,
    this.proxy,
    this.scopedProxy,
    this.valueType,
    this.nullable = false,
  });

  /// The declaring class or `@Bean` method, for error messages and
  /// imports.
  final Element element;

  /// Where the bean is declared, as `package:x/y.dart#Class` or
  /// `...#Class.method`; it appears in runtime errors and reports.
  final String source;

  /// The bean name: an explicit name, else the decapitalized class name
  /// or the `@Bean` method name.
  final String name;

  /// The bean's class, or the type a `@Bean` method returns (inferred from
  /// its body when more specific than the declared type).
  final InterfaceType type;

  /// The types the bean can be injected by: [type] and its public
  /// supertypes, except `Object`.
  final List<InterfaceType> exposedTypes;

  /// For a `FactoryBean`: the types of the object it produces, which is
  /// what injection by type gets; `null` for other beans.
  final List<InterfaceType>? factoryObjectTypes;

  /// How the instance is created.
  final Creation creation;

  /// Extra names of the bean (`@Bean(aliases: ...)`).
  final List<String> aliases;

  /// The `@Scope` value; `singleton` by default.
  final String scope;

  /// Whether the bean is created on first use instead of at startup
  /// (`@Lazy`, or `@ComponentScan(lazyInit: true)`).
  final bool lazy;

  /// Whether `@Primary` makes the bean win among several candidates.
  final bool primary;

  /// Whether `@Fallback` makes the bean lose against other candidates.
  final bool fallback;

  /// `false` when `@Bean(autowireCandidate: false)` hides the bean from
  /// type-based injection.
  final bool autowireCandidate;

  /// `false` when `@Bean(defaultCandidate: false)` limits injection to
  /// points whose qualifier selects the bean.
  final bool defaultCandidate;

  /// The `@Order` value, which sorts the bean in injected lists; `null`
  /// when unordered.
  final int? order;

  /// The `@Description` value.
  final String? description;

  /// The names of the beans from `@DependsOn` that must be created first.
  final List<String> dependsOn;

  /// The `@Qualifier` values declared on the bean.
  final Set<String> qualifiers;

  /// The conditions under which the bean is registered; for a `@Bean`
  /// method, the class's conditions come first.
  final List<ConditionModel> conditions;

  /// The injected fields and setters.
  final List<PropertyInjection> properties;

  /// The injected (`@Autowired`) methods.
  final List<MethodInjection> methods;

  /// The `@PostConstruct` method names, superclass methods first.
  final List<String> postConstruct;

  /// The `@PreDestroy` method names, subclass methods first.
  final List<String> preDestroy;

  /// The `@Bean(initMethod: ...)` method name.
  final String? initMethod;

  /// The `@Bean(destroyMethod: ...)` method name, explicit or inferred
  /// (`close`, `shutdown`, `dispose`).
  final String? destroyMethod;

  /// Whether [destroyMethod] was inferred (written as
  /// `destroyMethodName: '(inferred)'`, skipped for a `DisposableBean`).
  final bool destroyMethodInferred;

  /// The lifecycle methods ([postConstruct], [preDestroy], [initMethod],
  /// [destroyMethod]) returning a `Future`: their callbacks are written as
  /// `async` closures awaiting them, for `refreshAsync()` / `closeAsync()`.
  final Set<String> asyncLifecycleMethods;

  /// The event listener methods of the bean.
  final List<ListenerModel> listeners;

  /// The methods that carry an annotation marked `@BeanMethodAnnotation()`
  /// (such as `@Scheduled`), which starters find and call at runtime.
  final List<AnnotatedMethodModel> annotatedMethods;

  /// Annotations of the class (for a `@Bean` method: of the method, then
  /// of the returned class) that can be re-created as constants, for
  /// `BeanDefinition.annotations`.
  final List<DartObject> annotations;

  /// The advice and pointcuts of an `@Aspect` bean; `null` for other
  /// beans.
  final AspectModel? aspect;

  /// The generated AOP proxy of the bean; `null` when the bean is never
  /// proxied (proxies off, an aspect, a configuration class, an
  /// infrastructure bean).
  final ProxyModel? proxy;

  /// For `@Scope(proxyMode: ...)`: the proxy class handed to
  /// `BeanDefinition.scopedProxy`, which finds the current instance of the
  /// scope on every call. It lets a singleton hold a request- or
  /// session-scoped bean.
  final ProxyModel? scopedProxy;

  /// The function or record type of a `@Bean` method returning one; [type]
  /// is then `Function` or `Record`.
  final DartType? valueType;

  /// Whether the `@Bean` method may return `null`; the container then
  /// stores a `NullBean`.
  final bool nullable;

  /// Every injection point of the bean, for `BeanDefinition.dependencies`,
  /// which the container uses to order creation and report missing beans.
  ///
  /// For an instance `@Bean` method the owning bean comes first, so the
  /// container creates it before the method is called:
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
    // With alternative constructors no single parameter is required: the
    // generated code only calls a constructor whose beans exist.
    if (creation case ConstructorCreation(:final alternatives)
        when alternatives.isNotEmpty) ...[
      for (final argument in creation.arguments) argument.point.asOptional(),
      for (final alternative in alternatives)
        for (final argument in alternative.arguments)
          argument.point.asOptional(),
    ] else
      for (final argument in creation.arguments) argument.point,
    for (final property in properties) property.point,
    for (final method in methods)
      for (final argument in method.arguments) argument.point,
  ];
}

/// A `@Configurable` class: a class created outside the container whose
/// fields, setters and methods the container can still inject.
///
/// Such objects (a Flutter `State`, an object made by a library) are
/// created with their own constructor, so the container cannot inject
/// them at creation. Code hands an instance to `autowireBean` afterwards,
/// which runs the configurer the module holds for its class.
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
  ConfigurableModel(
    this.element,
    this.type,
    this.properties,
    this.methods, {
    this.postConstruct = const [],
    this.preDestroy = const [],
  });

  /// The class element, for error messages and imports.
  final Element element;

  /// The configurable class, the key of its configurer in the module.
  final InterfaceType type;

  /// The injected fields and setters.
  final List<PropertyInjection> properties;

  /// The injected (`@Autowired`) methods.
  final List<MethodInjection> methods;

  /// The `@PostConstruct` method names, run by `initializeBean`,
  /// superclass methods first.
  final List<String> postConstruct;

  /// The `@PreDestroy` method names, run by `destroyBean`, subclass
  /// methods first.
  final List<String> preDestroy;
}

/// A `@PropertySource` on a configuration class: files whose properties
/// the context adds to the environment when it starts.
///
/// The module lists them in `propertySources`, and the context loads each
/// one only when the declaring class's conditions match.
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
    this.encoding,
  });

  /// The charset name the files are read in; `null` means UTF-8.
  final String? encoding;

  /// The conditions of the declaring class and of the classes importing
  /// it. The file is loaded only when they match, as Spring skips the
  /// `@PropertySource` of a configuration class that is not registered.
  final List<ConditionModel> conditions;

  /// The declaring class, from which the types in [conditions] are
  /// imported.
  final Element? element;

  /// The resource locations; they may contain `${...}` placeholders.
  final List<String> locations;

  /// The property source name; `null` lets the runtime derive one from
  /// the location.
  final String? name;

  /// Whether missing resources are skipped instead of failing the
  /// startup.
  final bool ignoreResourceNotFound;

  /// A `PropertySourceFactory` class that reads the files (YAML, for
  /// example); it needs a no-argument constructor. `null` for the default
  /// properties reader.
  final InterfaceType? factoryType;
}

/// A property of an `@Introspected` class: a public field, or a getter
/// with an optional setter, that runtime code can read and write by name.
///
/// The emitter writes it as a `BeanProperty` with `get` and `set`
/// closures. JSON mapping, validation and property binding use it in
/// place of reflection.
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
    required this.declaredType,
    required this.nullable,
    required this.writable,
    required this.annotations,
  });

  /// The declared type as written, with nullability and type arguments,
  /// for `BeanProperty.typeInfo`.
  final DartType declaredType;

  /// The property name.
  final String name;

  /// The declared type without `?`: a class type, or a type parameter of
  /// a generic introspected class.
  final DartType type;

  /// Whether the declared type is nullable; always `true` for a type
  /// parameter.
  final bool nullable;

  /// Whether the property has a setter, so it gets a `set` closure.
  final bool writable;

  /// The user annotations of the field and its getter, such as
  /// constraints and JSON annotations.
  final List<DartObject> annotations;
}

/// A public method of an `@Introspected` class that runtime code can call
/// by name, written as a `BeanMethod` with an `invoke` closure.
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

  /// The return type; `null` for `void` and for non-class return types.
  final InterfaceType? returnType;

  /// The types of the positional parameters, without `?`.
  final List<InterfaceType> parameterTypes;

  /// The user annotations of the method.
  final List<DartObject> annotations;
}

/// An `@Introspected` class: the metadata that lets runtime code create
/// instances, read and write properties and call methods by name.
///
/// Spring reflects over any class when it needs to; Dart cannot, so a
/// class that JSON mapping, validation or binding works on is marked
/// `@Introspected` (or introspected automatically), and the module lists
/// a `BeanIntrospection` for it.
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
    this.constructor,
    this.fromJson,
    this.hasToJson = false,
  });

  /// The constructor that creates instances from data, such as JSON (the
  /// `@JsonCreator` one, else the unnamed one), when it is usable.
  final ConstructorModel? constructor;

  /// The class's own `fromJson` (constructor or static method), which JSON
  /// reading then uses instead of the properties.
  final FromJsonModel? fromJson;

  /// Whether the class has its own `toJson()` method, which JSON writing
  /// then uses.
  final bool hasToJson;

  /// The class element, for error messages and imports.
  final Element element;

  /// The introspected class.
  final InterfaceType type;

  /// The public instance properties, subclass declarations first.
  final List<IntrospectedProperty> properties;

  /// The public instance methods that can be called with positional
  /// arguments.
  final List<IntrospectedMethod> methods;

  /// The user annotations of the class.
  final List<DartObject> annotations;

  /// Whether the class has a public unnamed constructor callable without
  /// arguments, so the introspection gets an `instantiate` closure.
  final bool instantiable;
}

/// How a [TypeFilterModel] tests a class; the build-time form of Spring's
/// `FilterType`.
enum TypeFilterKind {
  /// The class is annotated with one of the classes (or a subclass of
  /// one).
  annotation,

  /// The class is, extends, implements or mixes in one of the classes.
  assignableType,

  /// The class name matches one of the patterns.
  regex,
}

/// One `Filter` of `@ComponentScan`, which includes or excludes classes
/// from the scan.
///
/// The scan runs at build time, so the filter is read from the annotation
/// and evaluated by the generator; it never reaches the runtime.
///
/// ```dart
/// // @ComponentScan(includeFilters: [Filter(type: FilterType.regex, pattern: ['.*Repo'])])
/// TypeFilterModel(TypeFilterKind.regex, patterns: [RegExp('.*Repo')])
///   .matches(userRepoElement) // true
/// ```
class TypeFilterModel {
  /// Creates a filter of [kind].
  const TypeFilterModel(
    this.kind, {
    this.classes = const [],
    this.patterns = const [],
  });

  /// How the filter tests a class.
  final TypeFilterKind kind;

  /// The annotation classes or assignable types, for those kinds.
  final List<InterfaceElement> classes;

  /// The patterns for the class name, for [TypeFilterKind.regex]. A
  /// pattern matches anywhere in the name unless anchored.
  final List<RegExp> patterns;

  /// Whether [element] matches the filter.
  bool matches(ClassElement element) => switch (kind) {
    TypeFilterKind.annotation => element.metadata.annotations.any(
      (annotation) => switch (annotation.computeConstantValue()?.type) {
        final InterfaceType type => classes.any((c) => _isSubtype(type, c)),
        _ => false,
      },
    ),
    TypeFilterKind.assignableType => classes.any(
      (c) => _isSubtype(element.thisType, c),
    ),
    TypeFilterKind.regex => patterns.any((p) => p.hasMatch(element.name!)),
  };

  static bool _isSubtype(InterfaceType type, InterfaceElement of) =>
      type.element == of || type.allSupertypes.any((s) => s.element == of);
}

/// The `@ComponentScan` options of one module: which classes of the
/// scanned directory become beans, and whether they start lazily.
///
/// They match the settings of Spring's
/// `ClassPathScanningCandidateComponentProvider`. The
/// `@SpringBootApplication` output uses the defaults.
class ComponentScanModel {
  /// Creates the options; the defaults are Spring's.
  const ComponentScanModel({
    this.includeFilters = const [],
    this.excludeFilters = const [],
    this.useDefaultFilters = true,
    this.lazyInit = false,
  });

  /// Classes matching one of these are beans even without `@Component`.
  final List<TypeFilterModel> includeFilters;

  /// Classes matching one of these are never beans, whatever else
  /// matches.
  final List<TypeFilterModel> excludeFilters;

  /// Whether `@Component` (and its stereotypes) marks a bean. With
  /// `false`, only [includeFilters] make beans.
  final bool useDefaultFilters;

  /// Whether every scanned bean is lazy unless it says `@Lazy(false)`.
  final bool lazyInit;

  /// Whether [element] becomes a bean of the scan; [isComponent] says
  /// whether it has `@Component` (or a stereotype).
  ///
  /// Exclude filters win. A class that only an include filter matches must
  /// be concrete, as in Spring's `isCandidateComponent`.
  bool isCandidate(ClassElement element, {required bool isComponent}) {
    if (excludeFilters.any((f) => f.matches(element))) {
      return false;
    }
    if (useDefaultFilters && isComponent) {
      return true;
    }
    return !element.isAbstract && includeFilters.any((f) => f.matches(element));
  }
}

/// Everything the scan of one output file found: beans, introspections,
/// configurables, property sources, registrars, imports, Flutter
/// bindings and loggers.
///
/// The `BeanScanner` fills it library by library; the
/// emitter writes it as one `BeanModule` getter plus the generated
/// classes:
///
/// ```dart
/// // Output:
/// BeanModule get $appBeans => BeanModule(
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
  /// The beans, in scan order; a configuration class comes before its
  /// `@Bean` methods.
  final beans = <BeanModel>[];

  /// The `@Introspected` classes, explicit and automatic.
  final introspections = <IntrospectionModel>[];

  /// The `@Configurable` classes.
  final configurables = <ConfigurableModel>[];

  /// The `@PropertySource` declarations of scanned and imported classes.
  final propertySources = <PropertySourceModel>[];

  /// The `@Import`ed registrars and selectors (`BeanModule.registrars`).
  final registrars = <RegistrarModel>[];

  /// The module variables of nested `@ComponentScan` roots, registered
  /// before this module's beans (`BeanModule.imports`).
  final imports = <TopLevelVariableElement>[];

  /// The lazy proxies for `@Lazy` injection points, one per type, keyed by
  /// library URI and type name.
  final lazyProxies = <String, ProxyModel>{};

  /// Every public class of the scanned libraries. The emitter needs it for
  /// `@args(...)` pointcuts: which classes carry an annotation.
  final classes = <ClassElement>[];

  /// The `BuildContext` getters to generate for `@BuildContextAccess`
  /// beans (`spring_boot_starter_flutter`).
  final buildContextAccess = <BuildContextAccessModel>[];

  /// The `SpringStatelessWidget` and `SpringState` classes
  /// (`spring_boot_starter_flutter`), in scan order.
  final springWidgets = <SpringWidgetModel>[];

  /// The `@Log` classes, each of which gets a logger getter.
  final loggers = <LogModel>[];

  final _proxyNames = <String>{};

  /// [name], or `name2`, `name3`... when a generated class of the module
  /// already uses it, as two classes with the same name in different
  /// directories would. Generated class names come from here.
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

  /// Records [classSource] (`library#Class`) and returns `false` when that
  /// class was already scanned: the component scan and `@Import` may reach
  /// the same class, which must become one bean.
  bool markScanned(String classSource) => _sources.add(classSource);
}

/// The public `dart:` library, among those [context]'s library imports,
/// that exports [name]; `null` when none does.
///
/// Generated code cannot import an internal SDK library such as
/// `dart:_http`, so a type declared there is imported through the public
/// library that exports it (`dart:io`).
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

/// Whether [type] is declared in an internal SDK library (`dart:_...`),
/// which generated code cannot import directly.
bool isInternalSdkType(InterfaceType type) {
  final uri = type.element.library.uri;
  return uri.scheme == 'dart' && uri.path.startsWith('_');
}

/// A method of a bean that carries an annotation marked
/// `@BeanMethodAnnotation()`, such as `@Scheduled`.
///
/// Starters find such methods at runtime and call them (a scheduler runs
/// every `@Scheduled` method). Without reflection they cannot find or
/// call them, so the method is written as a `BeanMethod`, with an `invoke`
/// closure and its annotations, into `BeanDefinition.annotatedMethods`.
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
    required this.parameters,
    required this.valueType,
    required this.isFuture,
    required this.isVoid,
    required this.annotations,
  });

  /// The method name.
  final String name;

  /// The types of the positional parameters; `null` entries are written
  /// as `Object` (non-class types).
  final List<InterfaceType?> parameterTypes;

  /// Every parameter in declaration order (positional, then named), for
  /// `BeanMethod.parameters`.
  final List<ConstructorParameterModel> parameters;

  /// The result type; for `Future<T>`, the type `T`.
  final DartType valueType;

  /// Whether the method returns a non-nullable `Future`, which callers
  /// await.
  final bool isFuture;

  /// Whether the result (or the future's value) is `void`.
  final bool isVoid;

  /// All user annotations of the method; starters read their own
  /// annotation from them.
  final List<DartObject> annotations;
}

/// The constructor of an introspected class that creates instances from
/// data (JSON reading, constructor binding), written as
/// `BeanIntrospection.constructor`.
///
/// ```dart
/// // Input: Book({required this.isbn, this.tags = const []})
/// // Output:
/// constructor: BeanConstructor<Book>(
///   parameters: [
///     BeanParameter(r'isbn', type: const ClassType<String>(), symbol: #isbn,
///         isRequired: true),
///     BeanParameter(r'tags',
///         type: const ListType<String>(ClassType<String>()), symbol: #tags),
///   ],
///   create: (positional, named) =>
///       Function.apply(Book.new, positional, named) as Book,
/// ),
/// ```
class ConstructorModel {
  /// Creates the model.
  ConstructorModel({required this.name, required this.parameters});

  /// The constructor name; empty for the unnamed constructor.
  final String name;

  /// Its parameters, in declaration order.
  final List<ConstructorParameterModel> parameters;
}

/// A parameter of a [ConstructorModel], an [AnnotatedMethodModel] or an
/// [InterfaceMethodModel], written as a `BeanParameter` that runtime code
/// fills by name or position.
class ConstructorParameterModel {
  /// Creates the model.
  ConstructorParameterModel({
    required this.name,
    required this.type,
    required this.isNamed,
    required this.isRequired,
    required this.annotations,
    this.hasDefault = false,
    this.defaultValue,
  });

  /// The parameter name.
  final String name;

  /// The declared type.
  final DartType type;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Whether a value must be passed: a required positional parameter, or
  /// a `required` named one.
  final bool isRequired;

  /// The user annotations on the parameter, such as `@JsonProperty` or
  /// `@PathVariable`.
  final List<DartObject> annotations;

  /// Whether the parameter declares a default value.
  final bool hasDefault;

  /// The default value when generated code can re-create it; set for
  /// introspected constructors only.
  final DartObject? defaultValue;
}

/// A `fromJson` that an introspected class declares itself
/// (`factory Book.fromJson(Map json)` or a static method), written as
/// `BeanIntrospection.fromJson`.
///
/// JSON reading calls it instead of filling the properties, so a class
/// that already knows how to read itself keeps doing so.
class FromJsonModel {
  /// Creates the model.
  FromJsonModel({required this.parameterType});

  /// The type of its JSON parameter (`Map<String, dynamic>`...); the
  /// runtime converts the decoded JSON to it.
  final DartType parameterType;
}

/// An abstract class with an annotation marked `@InterfaceProxy()` (such
/// as `@FeignClient`), and the implementation the generator writes for it.
///
/// The application declares only the interface. The generated class
/// forwards every method call, with its metadata and arguments, to an
/// `InvocationHandler` that the starter provides: an HTTP client for
/// `@FeignClient`, for example.
///
/// ```dart
/// // Input:
/// @FeignClient('catalog')
/// abstract interface class CatalogClient {
///   @GetMapping('/books/{isbn}')
///   Future<Book> find(@PathVariable() String isbn);
/// }
///
/// // Output:
/// class _$CatalogClientImpl implements CatalogClient {
///   _$CatalogClientImpl(this._handler, this._metadata);
///   static _$CatalogClientImpl $create(DependencyResolver r) { ... }
///   @override
///   Future<Book> find(String isbn) => retypeFuture<Book>(
///       _handler.invoke(_metadata.methods[0], [isbn]));
/// }
/// ```
class InterfaceProxyModel {
  /// Creates the model.
  InterfaceProxyModel({
    required this.className,
    required this.type,
    required this.signatures,
    required this.methods,
    required this.annotations,
  });

  /// The name of the generated class, e.g. `_$CatalogClientImpl`.
  final String className;

  /// The annotated interface.
  final InterfaceType type;

  /// The members to implement, with their signatures as for AOP proxies,
  /// so advice can match them too.
  final ProxyModel signatures;

  /// One entry per member of [signatures], in the same order.
  final List<InterfaceMethodModel> methods;

  /// The user annotations on the interface, which the handler reads
  /// (`@FeignClient('catalog')`).
  final List<DartObject> annotations;
}

/// A method of an [InterfaceProxyModel], written as the metadata the
/// `InvocationHandler` receives with each call.
class InterfaceMethodModel {
  /// Creates the model.
  InterfaceMethodModel({
    required this.name,
    required this.valueType,
    required this.isFuture,
    required this.isVoid,
    required this.parameters,
    required this.annotations,
  });

  /// The method name.
  final String name;

  /// The result type; for `Future<T>`, the type `T`.
  final DartType valueType;

  /// Whether the method returns a non-nullable `Future`; the generated
  /// method then retypes the handler's future.
  final bool isFuture;

  /// Whether the result (or the future's value) is `void`.
  final bool isVoid;

  /// The parameters, positional first, then named.
  final List<ConstructorParameterModel> parameters;

  /// The user annotations of the method (`@GetMapping('/books/{isbn}')`),
  /// which the handler reads.
  final List<DartObject> annotations;
}
