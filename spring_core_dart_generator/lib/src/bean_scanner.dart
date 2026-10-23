import 'package:analyzer/dart/ast/ast.dart'
    show
        AstNode,
        BlockFunctionBody,
        ExpressionFunctionBody,
        FunctionDeclarationStatement,
        FunctionExpression,
        MethodDeclaration,
        ReturnStatement;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart' show log;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/constraint_checker.dart';

part 'bean_type_inference.dart';
part 'configuration_scanning.dart';

// Annotations are matched by name in `package:spring_core_dart`, so the
// generator does not depend on the runtime package (consumers can pull both
// from git without dependency overrides).
TypeChecker _spring(String name) =>
    TypeChecker.typeNamedLiterally(name, inPackage: 'spring_core_dart');

final _component = _spring('Component');
final _configuration = _spring('Configuration');
final _named = _spring('Named');
final _bean = _spring('Bean');
final _scope = _spring('Scope');
final _lazy = _spring('Lazy');
final _primary = _spring('Primary');
final _fallback = _spring('Fallback');
final _qualifier = _spring('Qualifier');
final _dependsOn = _spring('DependsOn');
final _description = _spring('Description');
final _order = _spring('Order');
final _autowired = _spring('Autowired');
final _value = _spring('Value');
final _postConstruct = _spring('PostConstruct');
final _preDestroy = _spring('PreDestroy');
final _profile = _spring('Profile');
final _conditional = _spring('Conditional');
final _condition = _spring('Condition');
final _import = _spring('Import');
final _propertySource = _spring('PropertySource');
final _configurable = _spring('Configurable');
final _eventListener = _spring('EventListener');
final _beanMethodAnnotation = _spring('BeanMethodAnnotation');
final _jsonCreator = _spring('JsonCreator');

// `@ConfigurationProperties` from spring_boot_dart (matched by URL, so the
// generator does not depend on that package): constructor binding.
const _configurationProperties = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#ConfigurationProperties',
);
final _interfaceProxy = _spring('InterfaceProxy');
final _jsonValue = _spring('JsonValue');
final _factoryBean = _spring('FactoryBean');
final _applicationListener = _spring('ApplicationListener');
final _objectProvider = _spring('ObjectProvider');
final _objectFactory = _spring('ObjectFactory');
final _introspected = _spring('Introspected');
final _aspectAnnotation = _spring('Aspect');
final _pointcutAnnotation = _spring('Pointcut');
final _adviceAnnotations = {
  'around': _spring('Around'),
  'before': _spring('Before'),
  'after': _spring('After'),
  'afterReturning': _spring('AfterReturning'),
  'afterThrowing': _spring('AfterThrowing'),
};
final _joinPoint = _spring('JoinPoint');
final _proceedingJoinPoint = _spring('ProceedingJoinPoint');

// spring_boot_starter_cache annotations, matched by URL (no dependency).
const _cacheAnnotations =
    'package:spring_boot_starter_cache/src/annotations.dart';
const _cacheable = TypeChecker.fromUrl('$_cacheAnnotations#Cacheable');
const _cachePut = TypeChecker.fromUrl('$_cacheAnnotations#CachePut');
const _caching = TypeChecker.fromUrl('$_cacheAnnotations#Caching');

/// Infrastructure types that are never proxied.
///
/// Like Spring's `AbstractAutoProxyCreator.isInfrastructureClass`, which
/// skips `Advice`, `Pointcut`, `Advisor` and `AopInfrastructureBean`.
/// Members every generated AOP proxy declares (from `Advised`).
const _advisedMembers = {'aopTarget', 'aopAdvisors'};

String _reservedMessage(String? type, String member) =>
    '$type.$member has the name of a member every proxy declares '
    '(Advised.$member). Rename it.';

final _notProxied = [
  _spring('BeanPostProcessor'),
  _spring('BeanFactoryPostProcessor'),
  _spring('Advisor'),
  _spring('FactoryBean'),
];

/// Which beans get generated AOP proxies.
///
/// Set with the `aop_proxies` build option. Proxies are generated at build
/// time because Dart cannot create classes at runtime; a proxy can only be
/// generated for a type that another library may `implements` (public, not
/// sealed/final/base, no private members, no operators, emittable member
/// types and literal default values).
///
/// ```dart
/// // Input:
/// abstract interface class Greeter { String greet(String name); }
/// @Service()
/// class EnglishGreeter implements Greeter { ... }
/// @Service()
/// class Plain { void work() {} }
///
/// // ProxyMode.all:
/// class _$EnglishGreeterProxy
///     implements EnglishGreeter, Greeter, Advised { ... }
/// class _$PlainProxy implements Plain, Advised { ... }
///
/// // ProxyMode.interfaces (Plain has no abstract supertype: no proxy):
/// class _$EnglishGreeterProxy implements Greeter, Advised { ... }
///
/// // ProxyMode.none: no proxy classes, no `aopProxy:` arguments.
/// ```
///
/// Spring (Java):
///
/// ```java
/// // AnnotationAwareAspectJAutoProxyCreator decides at runtime between a
/// // JDK dynamic proxy (interfaces only) and a CGLIB subclass:
/// @EnableAspectJAutoProxy(proxyTargetClass = true)  // like `all`
/// @EnableAspectJAutoProxy(proxyTargetClass = false) // like `interfaces`
/// // Not enabling auto-proxying at all is like `none`.
/// ```
enum ProxyMode {
  /// Every bean whose class (or interfaces) can be implemented.
  all,

  /// Only through abstract types (like JDK dynamic proxies).
  interfaces,

  /// No proxies (AOP disabled for this module).
  none,
}

// Default values a proxy may copy verbatim into its own signature: numbers,
// booleans, `null`, strings without `$` or escapes, and empty list/map/set
// literals. Anything else (e.g. `const Duration(...)` or a constant from
// another library) may not resolve in the generated file, so such a member
// makes the whole bean non-proxyable.
// Pointcut designators whose body may name an advice parameter, and the
// text between their parentheses.
final _bindingDesignator = RegExp(
  r'(?<![@\w.])(@annotation|@within|@target|this|target|args)\s*\(([^()]*)\)',
);

// A reference to a named pointcut: `name()` or `Type.name()`.
final _namedReference = RegExp(r'(?<![@\w.])([A-Za-z_][\w.]*)\s*\(\s*\)');

final _bindingName = RegExp(r'^[a-z_]\w*$');

const _lowercaseTypes = {'int', 'double', 'num', 'bool', 'dynamic', 'void'};

const _designators = {
  'execution',
  'within',
  'target',
  'this',
  'args',
  'bean',
  'annotation',
};

final _literalDefault = RegExp(
  r'''^(-?\d+(\.\d+)?|true|false|null|'[^'\\$]*'|"[^"\\$]*"|(const\s*)?\[\]|(const\s*)?\{\})$''',
);

/// Spring's own DI annotations are not copied into introspection metadata.
const _diAnnotations = {
  'Autowired',
  'Inject',
  'Value',
  'Qualifier',
  'Named',
  'PostConstruct',
  'PreDestroy',
  'EventListener',
  'Bean',
  'Order',
  'Scope',
  'Lazy',
  'Primary',
  'Fallback',
  'DependsOn',
  'Description',
  'Introspected',
};

/// Marks the scan root.
///
/// Matches `@ComponentScan` from `package:spring_core_dart` by name, so the
/// generator needs no dependency on the runtime package.
///
/// ```dart
/// // Input (the scan root; its directory is scanned recursively):
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
/// ```
///
/// Spring (Java):
///
/// ```java
/// // ComponentScanAnnotationParser reads the annotation at runtime and
/// // scans the base packages (by default the annotated class's package):
/// @Configuration
/// @ComponentScan
/// class AppConfig {}
/// ```
final componentScanChecker = _spring('ComponentScan');

/// Reads the options of the `@ComponentScan` [annotation] on [element]
/// (`includeFilters`, `excludeFilters`, `useDefaultFilters`, `lazyInit`).
/// A filter without the argument its type uses fails the build.
///
/// ```dart
/// // @ComponentScan(includeFilters: [Filter(type: FilterType.regex, pattern: ['.*Repo'])])
/// componentScanModel(annotation, variable).includeFilters.single.kind
/// // TypeFilterKind.regex
/// ```
ComponentScanModel componentScanModel(DartObject annotation, Element element) {
  final reader = ConstantReader(annotation);
  List<TypeFilterModel> filters(String field) => [
    for (final (index, filter)
        in (reader.peek(field)?.listValue ?? const <DartObject>[]).indexed)
      _typeFilter(ConstantReader(filter), '$field[$index]', element),
  ];
  return ComponentScanModel(
    includeFilters: filters('includeFilters'),
    excludeFilters: filters('excludeFilters'),
    useDefaultFilters: reader.peek('useDefaultFilters')?.boolValue ?? true,
    lazyInit: reader.peek('lazyInit')?.boolValue ?? false,
  );
}

TypeFilterModel _typeFilter(
  ConstantReader filter,
  String where,
  Element element,
) {
  Never fail(String problem) =>
      BeanScanner._fail('@ComponentScan $where: $problem', element);
  final kind = TypeFilterKind.values.byName(
    filter.read('type').revive().accessor.split('.').last,
  );
  final classes = [
    for (final value in filter.read('classes').listValue)
      switch (value.toTypeValue()) {
        InterfaceType(:final element) => element,
        _ => fail('`classes` must list classes.'),
      },
  ];
  final patterns = <RegExp>[];
  for (final value in filter.read('pattern').listValue) {
    final pattern = value.toStringValue()!;
    try {
      patterns.add(RegExp(pattern));
    } on FormatException catch (e) {
      fail("invalid pattern '$pattern': ${e.message}.");
    }
  }
  final (used, unused) = kind == TypeFilterKind.regex
      ? ('pattern', 'classes')
      : ('classes', 'pattern');
  if ((kind == TypeFilterKind.regex ? patterns : classes).isEmpty) {
    fail('a FilterType.${kind.name} filter needs `$used`.');
  }
  if ((kind == TypeFilterKind.regex ? classes : patterns).isNotEmpty) {
    fail('a FilterType.${kind.name} filter uses `$used`, not `$unused`.');
  }
  return TypeFilterModel(kind, classes: classes, patterns: patterns);
}

/// Reads bean declarations from analyzer elements.
///
/// The scanner fills a [ModuleModel] with one [BeanModel] per component
/// class and `@Bean` method, plus `@Configurable`, `@Introspected` and
/// `@PropertySource` metadata. It validates declarations eagerly and
/// reports problems as `InvalidGenerationSource` errors pointing at the
/// offending element (private or abstract bean classes, ambiguous
/// constructors, async lifecycle methods, nullable collection elements,
/// ...).
///
/// ```dart
/// // Input:
/// @Configuration()
/// class Config {
///   @Bean()
///   Clock clock() => SystemClock();
/// }
///
/// @Service()
/// class Greeter {
///   Greeter(this.clock);
///   final Clock clock;
/// }
///
/// // Output (one BeanModel each, emitted as):
/// BeanDefinition<Config>(
///   name: r'config',
///   types: const [Config],
///   create: (r) => Config(),
/// ),
/// BeanDefinition<Clock>(
///   name: r'clock',
///   types: const [Clock],
///   dependencies: const [Dependency(Config, qualifier: r'config')],
///   create: (r) => r.dependency<Config>(qualifier: r'config').clock(),
/// ),
/// BeanDefinition<Greeter>(
///   name: r'greeter',
///   types: const [Greeter],
///   dependencies: const [Dependency(Clock, name: r'clock')],
///   create: (r) => Greeter(r.dependency<Clock>(name: r'clock')),
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring does this work at runtime, split over several components:
/// // ClassPathBeanDefinitionScanner finds @Component classes,
/// // ConfigurationClassPostProcessor parses @Configuration/@Bean/@Import,
/// // AutowiredAnnotationBeanPostProcessor and
/// // CommonAnnotationBeanPostProcessor find injection points and
/// // @PostConstruct/@PreDestroy methods by reflection.
/// var scanner = new ClassPathBeanDefinitionScanner(registry);
/// scanner.scan("com.example.app");
/// new ConfigurationClassPostProcessor()
///     .postProcessBeanDefinitionRegistry(registry);
/// ```
class BeanScanner {
  /// Creates a scanner that adds everything it finds to [module].
  ///
  /// ```dart
  /// final module = ModuleModel();
  /// final scanner = BeanScanner(module, proxyMode: ProxyMode.interfaces);
  /// scanner.scanLibrary(library);
  /// ```
  BeanScanner(
    this.module, {
    this.proxyMode = ProxyMode.all,
    this.scan = const ComponentScanModel(),
  });

  /// The model being filled.
  final ModuleModel module;

  /// Which beans get a [ProxyModel].
  final ProxyMode proxyMode;

  /// The `@ComponentScan` filters and `lazyInit` of the module.
  final ComponentScanModel scan;

  // Classes introspected so far (explicitly or automatically).
  final _introspectedClasses = <ClassElement>{};

  // Resolved `@Bean` method declarations by `library#Class.method`, for
  // the bean type inferred from the method body (bean_type_inference.dart).
  final _beanMethodDeclarations = <String, MethodDeclaration>{};

  /// Resolves the bodies of the `@Bean` methods of [library]'s classes
  /// (and of the classes they `@Import`), so that [scanLibrary] can
  /// register each bean under the type its method really returns. Call it
  /// before [scanLibrary]; [astNodeFor] is the build resolver's
  /// `astNodeFor(fragment, resolve: true)`. Without it, beans get the
  /// declared return type.
  ///
  /// ```dart
  /// await scanner.resolveBeanMethods(
  ///   library,
  ///   (fragment) => resolver.astNodeFor(fragment, resolve: true),
  /// );
  /// scanner.scanLibrary(library);
  /// ```
  Future<void> resolveBeanMethods(
    LibraryElement library,
    Future<AstNode?> Function(Fragment fragment) astNodeFor,
  ) => resolveBeanMethodDeclarations(library, astNodeFor);

  /// Adds the components, configurables and property sources of [library].
  ///
  /// Every class annotated with `@Component` (or a stereotype such as
  /// `@Service`, `@Repository`, `@Configuration`, `@Named`) is passed to
  /// [scanClass]; `@Configurable` and `@Introspected` classes are recorded
  /// as well (a class may be several of these at once).
  ///
  /// ```dart
  /// // Input: lib/src/greeting/greeter.dart
  /// @Service()
  /// class EnglishGreeter implements Greeter { ... }
  ///
  /// @Introspected()
  /// class Address { String city = ''; }
  /// // Result: module.beans gets EnglishGreeter,
  /// //         module.introspections gets Address.
  /// ```
  ///
  /// Spring (Java):
  ///
  /// ```java
  /// // ClassPathScanningCandidateComponentProvider reads class files with
  /// // ASM and keeps those whose metadata has @Component:
  /// provider.findCandidateComponents("com.example.app.greeting");
  /// ```
  void scanLibrary(LibraryElement library) {
    for (final element in library.classes) {
      if (_configurable.hasAnnotationOf(element)) {
        _scanConfigurable(element);
      }
      if (_introspected.hasAnnotationOf(element)) {
        _scanIntrospected(element);
      }
      if (_interfaceProxyPrimary(element) case final primary?) {
        _scanInterfaceProxy(element, primary: primary);
        continue;
      }
      final annotation = _component.firstAnnotationOf(element);
      if (scan.isCandidate(element, isComponent: annotation != null)) {
        scanClass(element, annotation: annotation);
      }
    }
  }

  /// Adds the beans of [element] (a component, or an `@Import`ed class).
  ///
  /// [annotation] is the component annotation, used for an explicit bean
  /// name (`@Component('x')`); without one the name is the decapitalized
  /// class name (`AuthService` → `authService`, `URLService` stays).
  /// The class becomes one bean, each of its `@Bean` methods another, and
  /// every class in `@Import([...])` is scanned recursively. A class is
  /// added only once even if reached several times.
  ///
  /// ```dart
  /// // Input:
  /// @Configuration()
  /// @Import([LegacyConfig])
  /// @Profile(['cloud'])
  /// class AppConfig {
  ///   @Bean(name: 'main', initMethod: 'open')
  ///   Pool pool() => Pool();
  /// }
  /// // Output (LegacyConfig's beans are emitted too):
  /// BeanDefinition<Pool>(
  ///   name: r'main',
  ///   types: const [Pool],
  ///   conditions: [const ProfileCondition([r'cloud'])],
  ///   dependencies: const [Dependency(AppConfig, qualifier: r'appConfig')],
  ///   create: (r) => (r.dependency<AppConfig>(qualifier: r'appConfig')
  ///       as _$AppConfigConfiguration)._$pool(r), // full-mode subclass
  ///   initMethod: (bean) {
  ///     bean.open();
  ///   },
  /// ),
  /// ```
  ///
  /// Spring (Java):
  ///
  /// ```java
  /// // ConfigurationClassParser processes @Import and @PropertySource,
  /// // ConfigurationClassBeanDefinitionReader registers one definition
  /// // per @Bean method, AnnotationBeanNameGenerator derives the name via
  /// // Introspector.decapitalize(...):
  /// @Configuration
  /// @Import(LegacyConfig.class)
  /// @Profile("cloud")
  /// class AppConfig {
  ///   @Bean(name = "main", initMethod = "open") Pool pool() { ... }
  /// }
  /// ```
  // [inheritedConditions] are the conditions of the class that imports
  // [element] with `@Import`: an imported class is registered only when
  // its importer is (first importer wins when several import it).
  void scanClass(
    ClassElement element, {
    DartObject? annotation,
    List<ConditionModel> inheritedConditions = const [],
  }) {
    final className = _requireName(element);
    final source = '${element.library.uri}#$className';
    if (!module.markScanned(source)) {
      return;
    }
    if (element.isPrivate) {
      _fail(
        'Bean class $className must be public: the generated module cannot '
        'reference a private class of ${element.library.uri}. Make it '
        'public, or move it out of the scanned directory.',
        element,
      );
    }
    if (element.isAbstract) {
      _fail('Bean class $className must not be abstract.', element);
    }
    if (element.typeParameters.isNotEmpty) {
      _fail('Generic bean class $className is not supported.', element);
    }

    // Evaluated once for the class, its @Bean methods, its property
    // sources and the classes it imports (Spring: all or nothing).
    final ownConditions = [...inheritedConditions, ..._conditions(element)];
    final classConditions = ownConditions.isEmpty
        ? const <ConditionModel>[]
        : [GroupConditionModel(source, ownConditions)];
    for (final imported in _importedClasses(element)) {
      scanClass(
        imported,
        annotation: _component.firstAnnotationOf(imported),
        inheritedConditions: classConditions,
      );
    }
    module.propertySources.addAll(_propertySources(element, classConditions));

    final type = element.thisType;
    final name =
        (annotation == null
            ? null
            : ConstantReader(annotation).peek('name')?.stringValue) ??
        _decapitalize(className);
    // A constructor-bound @ConfigurationProperties class is created from
    // properties, not beans (see _boundConstructor).
    final constructor = _boundConstructor(element) == null
        ? _selectConstructor(element)
        : null;
    final classLazy = _isLazy(element);
    // Checked before the configuration subclass: a private parameter type
    // is an error in lite mode too.
    final arguments = constructor == null
        ? null
        : _arguments(constructor.formalParameters, creation: true);
    // `@Bean` methods of the class, its superclasses and mixins (Spring
    // scans the hierarchy).
    final beanMethods = _beanMethods(type);
    // A full-mode @Configuration class is created as its generated
    // subclass, which intercepts the instance @Bean methods (without any,
    // there is nothing to intercept).
    final configuration =
        constructor != null &&
            isFullConfiguration(element) &&
            beanMethods.any((m) => !m.$1.isStatic)
        ? configurationClassModel(element, constructor)
        : null;
    final owner = BeanModel(
      element: element,
      source: source,
      name: name,
      type: type,
      exposedTypes: _exposedTypes(type),
      factoryObjectTypes: _factoryObjectTypes(type),
      creation: arguments == null
          ? ConfigurationPropertiesCreation()
          : ConstructorCreation(
              _constructorName(constructor!),
              arguments,
              configuration: configuration,
            ),
      scope: _scopeOf(element),
      lazy: classLazy ?? scan.lazyInit,
      primary: _primary.hasAnnotationOf(element),
      fallback: _fallback.hasAnnotationOf(element),
      order: _orderOf(element),
      description: _descriptionOf(element),
      dependsOn: _dependsOnOf(element),
      qualifiers: _qualifiersOf(element),
      conditions: classConditions,
      properties: _propertyInjections(type),
      methods: _methodInjections(type),
      postConstruct: _lifecycleMethods(type, _postConstruct, superFirst: true),
      preDestroy: _lifecycleMethods(type, _preDestroy, superFirst: false),
      asyncLifecycleMethods: _asyncMethods(type, [
        ..._lifecycleMethods(type, _postConstruct, superFirst: true),
        ..._lifecycleMethods(type, _preDestroy, superFirst: false),
      ]),
      listeners: _listeners(element),
      annotatedMethods: _annotatedMethods(type),
      annotations: _beanAnnotations(element),
      aspect: _aspectModel(element),
      proxy: _isProxyCandidate(element)
          ? _proxyModel(
              type,
              '_\$${className}Proxy',
              implementSelf: true,
              constructor: constructor,
            )
          : null,
    );
    module.beans.add(owner);

    // `@Lazy` on a `@Configuration` class is the default for its `@Bean`
    // methods (as in Spring); on other components it only affects the
    // component itself.
    final isConfiguration = _configuration.hasAnnotationOf(element);
    for (final (method, beanAnnotation) in beanMethods) {
      module.beans.add(
        _scanBeanMethod(
          owner,
          method,
          ConstantReader(beanAnnotation),
          classConditions: classConditions,
          classLazy: isConfiguration ? classLazy : null,
          configuration: configuration,
        ),
      );
    }
  }

  /// The `@Bean` methods of [type], its superclasses and mixins (Spring
  /// scans the class hierarchy), each with its annotation. A method is
  /// taken from its most derived declaration (with the type arguments of
  /// [type] substituted); the annotation may sit on an overridden one.
  ///
  /// ```dart
  /// // Input:
  /// abstract class BaseConfig<T> {
  ///   @Bean()
  ///   Store<T> store() => Store<T>();
  /// }
  /// @Configuration()
  /// class UserConfig extends BaseConfig<User> {}
  /// // Result: [(UserConfig's store(): Store<User>, @Bean())]
  /// ```
  List<(MethodElement, DartObject)> _beanMethods(InterfaceType type) {
    final declarations = <String, MethodElement>{};
    final annotations = <String, DartObject>{};
    for (final current in _linearization(type)) {
      for (final method in current.methods) {
        if (method.isAbstract) {
          continue;
        }
        final name = _requireName(method);
        declarations.putIfAbsent(name, () => method);
        if (_bean.firstAnnotationOf(method) case final annotation?) {
          annotations.putIfAbsent(name, () => annotation);
        }
      }
    }
    return [
      for (final MapEntry(key: name, value: annotation) in annotations.entries)
        (declarations[name]!, annotation),
    ];
  }

  /// [type] and its superclasses and mixins, most derived first, as Dart
  /// linearizes them (`class C extends B with M1, M2`: C, M2, M1, B).
  /// Each type has the type arguments substituted, so the members of
  /// `BaseService<R>` seen through `UserService extends BaseService<User>`
  /// mention `User`.
  List<InterfaceType> _linearization(InterfaceType type) {
    final chain = <InterfaceType>[];
    InterfaceType? current = type;
    while (current != null && !current.isDartCoreObject) {
      chain.add(current);
      chain.addAll(current.mixins.reversed);
      current = current.superclass;
    }
    return chain;
  }

  /// [type] first, then every supertype (subclass declarations win), with
  /// the type arguments substituted (see [_linearization]).
  Iterable<InterfaceType> _hierarchyTypes(InterfaceType type) => [
    type,
    for (final supertype in type.allSupertypes)
      if (!supertype.isDartCoreObject) supertype,
  ];

  void _scanConfigurable(ClassElement element) {
    final name = _requireName(element);
    if (element.isPrivate) {
      _fail('@Configurable class $name must be public.', element);
    }
    if (element.typeParameters.isNotEmpty) {
      _fail('Generic @Configurable class $name is not supported.', element);
    }
    final type = element.thisType;
    module.configurables.add(
      ConfigurableModel(
        element,
        type,
        _propertyInjections(type),
        _methodInjections(type),
        // Configurables are initialized synchronously (initializeBean).
        postConstruct: _lifecycleMethods(
          type,
          _postConstruct,
          superFirst: true,
          allowAsync: false,
        ),
        preDestroy: _lifecycleMethods(
          type,
          _preDestroy,
          superFirst: false,
          allowAsync: false,
        ),
      ),
    );
  }

  // [automatic]: a class of the same package used by an introspected class
  // (a property or constructor parameter type); skipped silently when it
  // cannot be introspected.
  void _scanIntrospected(ClassElement element, {bool automatic = false}) {
    final name = _requireName(element);
    if (element.isPrivate || element.typeParameters.isNotEmpty) {
      if (automatic) {
        return;
      }
      _fail(
        element.isPrivate
            ? '@Introspected class $name must be public.'
            : 'Generic @Introspected class $name is not supported.',
        element,
      );
    }
    if (!_introspectedClasses.add(element)) {
      return;
    }
    final type = element.thisType;
    // Subclass first, so overriding declarations win (first one kept).
    // Only fields with a getter and an interface type, and methods callable
    // with positional arguments only, can be described by BeanProperty and
    // BeanMethod; anything else is skipped silently.
    final hierarchy = [element, ..._superclasses(type)];
    final properties = <String, IntrospectedProperty>{};
    final methods = <String, IntrospectedMethod>{};
    for (final current in hierarchy) {
      for (final field in current.fields) {
        final fieldName = field.name;
        if (field.isStatic ||
            field.isPrivate ||
            fieldName == null ||
            properties.containsKey(fieldName)) {
          continue;
        }
        final fieldType = field.type;
        if (fieldType is! InterfaceType || field.getter == null) {
          continue;
        }
        properties[fieldName] = IntrospectedProperty(
          name: fieldName,
          type: _requireInterfaceType(fieldType, field, stripNullable: true),
          declaredType: fieldType,
          nullable: fieldType.nullabilitySuffix == NullabilitySuffix.question,
          writable: field.setter != null,
          annotations: [
            ..._userAnnotations(field),
            if (field.getter case final getter?) ..._userAnnotations(getter),
          ],
        );
        _checkConstraints(
          properties[fieldName]!.annotations,
          fieldType,
          '$name.$fieldName',
          field,
        );
      }
      for (final method in current.methods) {
        final methodName = method.name;
        if (method.isStatic ||
            method.isPrivate ||
            method.isOperator ||
            methodName == null ||
            methods.containsKey(methodName) ||
            method.formalParameters.any((p) => p.isNamed && p.isRequired)) {
          continue;
        }
        final parameterTypes = [
          for (final parameter in method.formalParameters)
            if (parameter.isPositional) parameter.type,
        ];
        if (parameterTypes.any((t) => t is! InterfaceType)) {
          continue;
        }
        final returnType = method.returnType;
        methods[methodName] = IntrospectedMethod(
          name: methodName,
          returnType: returnType is InterfaceType
              ? _requireInterfaceType(returnType, method, stripNullable: true)
              : null,
          parameterTypes: [
            for (final t in parameterTypes)
              _requireInterfaceType(t, method, stripNullable: true),
          ],
          annotations: _userAnnotations(method),
        );
      }
    }
    final constructor = element.unnamedConstructor;
    final dataConstructor = _dataConstructor(element);
    module.introspections.add(
      IntrospectionModel(
        element: element,
        type: type,
        properties: properties.values.toList(),
        methods: methods.values.toList(),
        annotations: _userAnnotations(element),
        instantiable:
            !element.isAbstract &&
            constructor != null &&
            constructor.isPublic &&
            !constructor.isFactory &&
            !constructor.formalParameters.any((p) => p.isRequired),
        constructor: dataConstructor,
        fromJson: _fromJson(element),
        hasToJson: _hasToJson(type),
      ),
    );
    // Classes of the same package it is made of are introspected too, so
    // one `@Introspected()` on the root of a model is enough.
    for (final property in properties.values) {
      _introspectUsed(property.declaredType, element);
    }
    for (final parameter
        in dataConstructor?.parameters ?? const <ConstructorParameterModel>[]) {
      _introspectUsed(parameter.type, element);
    }
    // `@Introspected(classes: [ExternalDto])`.
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value == null || !_introspected.isAssignableFromType(value.type!)) {
        continue;
      }
      for (final listed
          in ConstantReader(value).peek('classes')?.listValue ?? const []) {
        if (listed.toTypeValue() case final InterfaceType listedType
            when listedType.element is ClassElement) {
          _scanIntrospected(listedType.element as ClassElement);
        }
      }
    }
  }

  void _introspectUsed(DartType type, ClassElement user) {
    if (type is! InterfaceType) {
      return;
    }
    for (final argument in type.typeArguments) {
      _introspectUsed(argument, user);
    }
    final element = type.element;
    if (element is! ClassElement ||
        element.library.isInSdk ||
        _packageOf(element) != _packageOf(user)) {
      return;
    }
    _scanIntrospected(element, automatic: true);
  }

  static String? _packageOf(Element element) {
    final uri = element.library?.uri;
    return uri != null && (uri.isScheme('package') || uri.isScheme('asset'))
        ? uri.pathSegments.firstOrNull
        : null;
  }

  // The constructor data is turned into instances with: the one marked
  // @JsonCreator, else the unnamed one (public; generative only on concrete
  // classes).
  ConstructorModel? _dataConstructor(ClassElement element) {
    final constructors = element.constructors.where(
      (c) => c.isPublic && (c.isFactory || !element.isAbstract),
    );
    final constructor =
        _boundConstructor(element) ??
        constructors.where(_jsonCreator.hasAnnotationOf).firstOrNull ??
        constructors.where((c) => (c.name ?? 'new') == 'new').firstOrNull;
    if (constructor == null) {
      return null;
    }
    for (final parameter in constructor.formalParameters) {
      _checkConstraints(
        _userAnnotations(parameter),
        parameter.type,
        '${element.name}(${parameter.name})',
        parameter,
      );
    }
    final name = constructor.name;
    return ConstructorModel(
      name: name == null || name == 'new' ? '' : name,
      parameters: [
        for (final parameter in constructor.formalParameters)
          ConstructorParameterModel(
            name: _requireName(parameter),
            type: parameter.type,
            isNamed: parameter.isNamed,
            isRequired: parameter.isRequired,
            annotations: _userAnnotations(parameter),
          ),
      ],
    );
  }

  // `factory Book.fromJson(Map<String, dynamic> json)` (or a static method)
  // with one required positional parameter.
  FromJsonModel? _fromJson(ClassElement element) {
    final candidates = <ExecutableElement>[
      ...element.constructors.where((c) => c.name == 'fromJson'),
      ...element.methods.where((m) => m.isStatic && m.name == 'fromJson'),
    ];
    for (final candidate in candidates) {
      final parameters = candidate.formalParameters;
      if (!candidate.isPublic ||
          parameters.isEmpty ||
          !parameters.first.isRequiredPositional ||
          parameters.skip(1).any((p) => p.isRequired)) {
        continue;
      }
      return FromJsonModel(parameterType: parameters.first.type);
    }
    return null;
  }

  bool _hasToJson(InterfaceType type) {
    for (final element in _hierarchy(type)) {
      for (final method in element.methods) {
        if (method.name == 'toJson' &&
            !method.isStatic &&
            method.isPublic &&
            !method.formalParameters.any((p) => p.isRequired)) {
          return true;
        }
      }
    }
    return false;
  }

  /// The field of [element] marked `@JsonValue()`, if any (for emitters).
  static String? jsonValueField(EnumElement element) => element.fields
      .where((f) => !f.isStatic && _jsonValue.hasAnnotationOf(f))
      .firstOrNull
      ?.name;

  /// Const annotations worth keeping at runtime: user annotations and
  /// constraints, not `dart:` ones or Spring's DI annotations.
  List<DartObject> _userAnnotations(Element element) => [
    for (final annotation in element.metadata.annotations)
      if (annotation.computeConstantValue() case final value?)
        if (value.type case final InterfaceType type
            when !type.element.library.isInSdk &&
                type.element.isPublic &&
                !(_isSpringType(type) &&
                    _diAnnotations.contains(type.element.name)))
          value,
  ];

  /// The annotations of a bean class or `@Bean` method for
  /// `BeanDefinition.annotations` (`findAnnotationOnBean`,
  /// `getBeansWithAnnotation`): every const annotation not from the SDK
  /// that generated code can re-create; others are left out silently.
  List<DartObject> _beanAnnotations(Element element) => [
    for (final annotation in element.metadata.annotations)
      if (annotation.computeConstantValue() case final value?)
        if (value.type case final InterfaceType type
            when !type.element.library.isInSdk &&
                type.element.isPublic &&
                _isRecreatable(value))
          value,
  ];

  // Mirrors `ModuleEmitter._constant`: whether [value] can be written as a
  // constant expression in generated code.
  bool _isRecreatable(DartObject value) {
    final reader = ConstantReader(value);
    if (reader.isNull ||
        reader.isBool ||
        reader.isInt ||
        reader.isDouble ||
        reader.isString) {
      return true;
    }
    if (reader.isType) {
      return _isWritableType(reader.typeValue);
    }
    if (reader.isList) {
      return reader.listValue.every(_isRecreatable);
    }
    if (reader.isSet) {
      return reader.setValue.every(_isRecreatable);
    }
    if (reader.isMap) {
      return reader.mapValue.entries.every(
        (e) =>
            e.key != null &&
            e.value != null &&
            _isRecreatable(e.key!) &&
            _isRecreatable(e.value!),
      );
    }
    final function = value.toFunctionValue();
    if (function != null) {
      final enclosing = function.enclosingElement;
      return function.isPublic &&
          (function is TopLevelFunctionElement ||
              (function is MethodElement &&
                  function.isStatic &&
                  enclosing is InterfaceElement &&
                  enclosing.isPublic));
    }
    try {
      final revivable = reader.revive();
      return !revivable.isPrivate &&
          revivable.positionalArguments.every(_isRecreatable) &&
          revivable.namedArguments.values.every(_isRecreatable);
    } on Object {
      return false;
    }
  }

  // A public class type (with writable type arguments), `dynamic` or
  // `void`.
  bool _isWritableType(DartType type) =>
      type is DynamicType ||
      type is VoidType ||
      (type is InterfaceType &&
          type.element.isPublic &&
          !isInternalSdkType(type) &&
          type.typeArguments.every(_isWritableType));

  // Whether [type] is declared in `package:spring_core_dart`.
  static bool _isSpringType(InterfaceType type) =>
      type.element.library.uri.pathSegments.firstOrNull == 'spring_core_dart';

  // One bean per `@Bean` method. Class conditions are inherited; the bean
  // is created by calling the method on the owner bean (or statically).
  // [configuration]: the owner is a full-mode configuration class, whose
  // generated subclass overrides the instance `@Bean` methods. The bean
  // type is inferred from the method body (bean_type_inference.dart).
  BeanModel _scanBeanMethod(
    BeanModel owner,
    MethodElement method,
    ConstantReader annotation, {
    required List<ConditionModel> classConditions,
    required bool? classLazy,
    ConfigurationClassModel? configuration,
  }) {
    final methodName = _requireName(method);
    if (method.isPrivate) {
      _fail('@Bean method $methodName must be public.', method);
    }
    if (method.typeParameters.isNotEmpty) {
      _fail('Generic @Bean method $methodName is not supported.', method);
    }
    final declaredType = method.returnType;
    if (declaredType is! InterfaceType ||
        declaredType.nullabilitySuffix != NullabilitySuffix.none) {
      _fail(
        '@Bean method $methodName must return a non-nullable class type.',
        method,
      );
    }
    if (declaredType.isDartAsyncFuture || declaredType.isDartAsyncFutureOr) {
      _fail('@Bean method $methodName must not be async.', method);
    }
    final returnType = inferredBeanType(method, declaredType);
    final inferred = returnType != declaredType;
    for (final type in {declaredType, returnType}) {
      _requirePublicType(
        type,
        method,
        '${_describe(method)} returns',
        'or declare a public supertype as the return type',
      );
    }
    final initMethod = annotation.peek('initMethod')?.stringValue;
    final destroyMethod = annotation.peek('destroyMethod')?.stringValue;
    final name = annotation.peek('name')?.stringValue ?? methodName;
    final scope = _scopeOf(method);
    final arguments = _arguments(method.formalParameters, creation: true);
    final factoryObjectTypes = _factoryObjectTypes(returnType);
    return BeanModel(
      element: method,
      source: '${owner.source}.$methodName',
      name: name,
      aliases: [
        for (final alias
            in annotation.peek('aliases')?.listValue ?? const <DartObject>[])
          alias.toStringValue()!,
      ],
      type: returnType,
      exposedTypes: inferred
          ? exposedInferredTypes(returnType, declaredType)
          : _exposedTypes(returnType),
      factoryObjectTypes: factoryObjectTypes,
      creation: BeanMethodCreation(
        // A static method is not inherited: it is called on its declaring
        // class.
        ownerType: method.isStatic
            ? (method.enclosingElement as InterfaceElement).thisType
            : owner.type,
        ownerName: owner.name,
        methodName: methodName,
        isStatic: method.isStatic,
        arguments: arguments,
        // Static methods are not intercepted, as in Spring.
        enhanced: configuration == null || method.isStatic
            ? null
            : enhancedBeanMethod(
                configuration,
                method,
                beanName: name,
                declaredType: declaredType,
                isFactoryBean: factoryObjectTypes != null,
                isSingleton: scope == 'singleton',
                arguments: arguments,
              ),
        declaredType: inferred ? declaredType : null,
      ),
      scope: scope,
      lazy: _isLazy(method) ?? classLazy ?? scan.lazyInit,
      primary: _primary.hasAnnotationOf(method),
      fallback: _fallback.hasAnnotationOf(method),
      autowireCandidate:
          annotation.peek('autowireCandidate')?.boolValue ?? true,
      defaultCandidate: annotation.peek('defaultCandidate')?.boolValue ?? true,
      order: _orderOf(method),
      description: _descriptionOf(method),
      dependsOn: _dependsOnOf(method),
      qualifiers: _qualifiersOf(method),
      conditions: [...classConditions, ..._conditions(method)],
      // Like Spring, the returned object is processed like any bean:
      // its `@Autowired`/`@Value` members, lifecycle methods and listeners
      // (declared on the return type) apply too. An init/destroy method
      // that is also annotated runs once.
      properties: _propertyInjections(returnType),
      methods: _methodInjections(returnType),
      postConstruct: [
        for (final name in _lifecycleMethods(
          returnType,
          _postConstruct,
          superFirst: true,
        ))
          if (name != initMethod) name,
      ],
      preDestroy: _lifecycleMethods(returnType, _preDestroy, superFirst: false),
      asyncLifecycleMethods: _asyncMethods(returnType, [
        ..._lifecycleMethods(returnType, _postConstruct, superFirst: true),
        ..._lifecycleMethods(returnType, _preDestroy, superFirst: false),
        ?initMethod,
        ?_beanDestroyMethod(returnType, destroyMethod, method),
      ]),
      listeners: switch (returnType.element) {
        final ClassElement element => _listeners(element),
        _ => const [],
      },
      annotatedMethods: _annotatedMethods(returnType),
      annotations: [
        ..._beanAnnotations(method),
        ..._beanAnnotations(returnType.element),
      ],
      initMethod: initMethod == null
          ? null
          : _requireNoArgMethod(returnType, initMethod, method, 'initMethod'),
      destroyMethod: _beanDestroyMethod(returnType, destroyMethod, method),
      destroyMethodInferred: destroyMethod == '(inferred)',
      // The proxy class is named after owner and method, because two
      // `@Bean` methods may return the same type.
      proxy:
          _notProxied.any((c) => c.isAssignableFromType(returnType)) ||
              _aspectAnnotation.hasAnnotationOf(returnType.element) ||
              _configuration.hasAnnotationOf(returnType.element)
          ? null
          : _proxyModel(
              returnType,
              '_\$${owner.type.element.name}_${methodName}Proxy',
              implementSelf: true,
            ),
    );
  }

  // ---------------------------------------------------------------------
  // AOP
  // ---------------------------------------------------------------------

  // Collects `@Pointcut` methods (name -> expression) and advice methods
  // of an `@Aspect` class and its superclasses and mixins (an override
  // wins, like Spring's ReflectiveAspectJAdvisorFactory); `null` for other
  // classes.
  AspectModel? _aspectModel(ClassElement element) {
    if (!_aspectAnnotation.hasAnnotationOf(element)) {
      return null;
    }
    final pointcuts = <String, String>{};
    final adviceMethods = <(MethodElement, String, DartObject)>[];
    final seen = <String>{};
    for (final current in _classChain(element)) {
      for (final method in current.methods) {
        final name = _requireName(method);
        if (!seen.add(name) || (method.isAbstract && current != element)) {
          continue;
        }
        final pointcut = _pointcutAnnotation.firstAnnotationOf(method);
        if (pointcut != null) {
          pointcuts[name] = ConstantReader(pointcut)
              .read('expression')
              .stringValue;
        }
        for (final MapEntry(key: kind, value: checker)
            in _adviceAnnotations.entries) {
          final annotation = checker.firstAnnotationOf(method);
          if (annotation != null) {
            adviceMethods.add((method, kind, annotation));
          }
        }
      }
    }
    final advice = [
      for (final (method, kind, annotation) in adviceMethods)
        _adviceModel(method, kind, annotation, pointcuts, element.name!),
    ];
    return AspectModel(advice, pointcuts);
  }

  // The class, its mixins (last applied first) and superclasses up to the
  // SDK: where inherited members are declared, most derived first.
  Iterable<InterfaceElement> _classChain(ClassElement element) sync* {
    InterfaceElement? current = element;
    while (current != null && !current.library.isInSdk) {
      yield current;
      for (final mixin in current.mixins.reversed) {
        yield mixin.element;
      }
      current = current.supertype?.element;
    }
  }

  // Maps advice parameters: (Proceeding)JoinPoint by exact type, the
  // parameters the pointcut binds by name, and for after-returning /
  // after-throwing advice the `returning` / `throwing` parameter (by
  // default the first other one) receives the return value or error.
  AdviceModel _adviceModel(
    MethodElement method,
    String kind,
    DartObject annotation,
    Map<String, String> pointcuts,
    String aspectName,
  ) {
    final name = _requireName(method);
    final reader = ConstantReader(annotation);
    final pointcut = reader.read('pointcut').stringValue;
    final valueField = switch (kind) {
      'afterReturning' => 'returning',
      'afterThrowing' => 'throwing',
      _ => null,
    };
    final valueName = valueField == null
        ? null
        : reader.peek(valueField)?.stringValue;
    final annotationName = '@${kind[0].toUpperCase()}${kind.substring(1)}';
    if (method.isStatic || method.isPrivate) {
      _fail('Advice method $name must be a public instance method.', method);
    }
    final bound = _boundNames(pointcut, pointcuts, aspectName);
    final parameters = <AdviceParameter>[];
    DartType? valueType;
    for (final parameter in method.formalParameters) {
      final type = parameter.type;
      final parameterName = parameter.name ?? '';
      if (parameter.isNamed) {
        _fail('Advice method $name must use positional parameters.', method);
      }
      if (_proceedingJoinPoint.isExactlyType(type)) {
        parameters.add(const JoinPointParameter(proceeding: true));
      } else if (_joinPoint.isExactlyType(type)) {
        parameters.add(const JoinPointParameter(proceeding: false));
      } else if (bound.names.contains(parameterName)) {
        parameters.add(_boundParameter(parameter, annotationName, name));
      } else if (valueField != null &&
          valueType == null &&
          (valueName == null || valueName == parameterName)) {
        parameters.add(ValueParameter(type));
        valueType = type;
      } else if (!bound.complete) {
        // The pointcut refers to pointcuts of another class, which may
        // bind the parameter; the runtime checks that it does.
        parameters.add(_boundParameter(parameter, annotationName, name));
      } else {
        _fail(
          'Unexpected parameter $parameterName of $annotationName advice '
          '$name: the pointcut does not bind it. Bind it with '
          '@annotation($parameterName), @within($parameterName), '
          '@target($parameterName), this($parameterName), '
          'target($parameterName) or args($parameterName, ..)'
          '${valueField == null ? '' : ', or name it in `$valueField:`'}.',
          parameter,
        );
      }
    }
    if (valueName != null && valueType == null) {
      _fail(
        "$annotationName advice $name names the $valueField parameter "
        "'$valueName', which it does not declare.",
        method,
      );
    }
    final parameterNames = {for (final p in method.formalParameters) p.name};
    for (final binding in bound.names) {
      if (!parameterNames.contains(binding)) {
        _fail(
          "The pointcut of $annotationName advice $name binds '$binding', "
          'which is not a parameter of the advice method. Add a parameter '
          'named $binding, or match by type with a type name (starting with '
          'an uppercase letter).',
          method,
        );
      }
    }
    final proceeding = parameters.any(
      (p) => p is JoinPointParameter && p.proceeding,
    );
    if (kind == 'around' && !proceeding) {
      _fail(
        '@Around advice $name needs a ProceedingJoinPoint parameter.',
        method,
      );
    }
    if (kind != 'around' && proceeding) {
      _fail(
        'Only @Around advice can take a ProceedingJoinPoint ($name).',
        method,
      );
    }
    return AdviceModel(
      kind: kind,
      pointcut: pointcut,
      methodName: name,
      parameters: parameters,
      valueType: valueType,
    );
  }

  BoundParameter _boundParameter(
    FormalParameterElement parameter,
    String annotationName,
    String adviceName,
  ) {
    final type = parameter.type;
    if (!_isEmittable(type)) {
      _fail(
        'Parameter ${parameter.name} of $annotationName advice $adviceName '
        'has the private type ${type.getDisplayString()}, which generated '
        'code cannot name. Make the type public.',
        parameter,
      );
    }
    return BoundParameter(parameter.name!, type);
  }

  // The advice parameters [expression] binds: lowercase-initial names in
  // `@annotation(x)`, `@within(x)`, `@target(x)`, `this(x)`, `target(x)`
  // and `args(x, ..)` (type names start uppercase; Dart's lowercase core
  // types are excluded), following the aspect's own named pointcuts.
  // `complete` is false when a reference to another class's pointcut
  // cannot be followed here.
  ({Set<String> names, bool complete}) _boundNames(
    String expression,
    Map<String, String> pointcuts,
    String owner,
  ) {
    final names = <String>{};
    var complete = true;
    final visited = <String>{};
    void visit(String expression) {
      for (final match in _bindingDesignator.allMatches(expression)) {
        final items = match[1] == 'args' ? match[2]!.split(',') : [match[2]!];
        for (final item in items) {
          final id = item.trim();
          if (_bindingName.hasMatch(id) && !_lowercaseTypes.contains(id)) {
            names.add(id);
          }
        }
      }
      for (final match in _namedReference.allMatches(expression)) {
        final reference = match[1]!;
        if (_designators.contains(reference)) {
          continue;
        }
        final String? key;
        if (!reference.contains('.')) {
          key = pointcuts.containsKey(reference) ? reference : null;
        } else {
          final segments = reference.split('.');
          key =
              segments.length == 2 &&
                  segments.first == owner &&
                  pointcuts.containsKey(segments.last)
              ? segments.last
              : null;
        }
        if (key == null) {
          complete = false;
        } else if (visited.add(key)) {
          visit(pointcuts[key]!);
        }
      }
    }

    visit(expression);
    return (names: names, complete: complete);
  }

  // Aspects, configuration classes (their `@Bean` methods are called
  // directly) and infrastructure beans are never proxied, as in Spring.
  bool _isProxyCandidate(ClassElement element) =>
      proxyMode != ProxyMode.none &&
      !_aspectAnnotation.hasAnnotationOf(element) &&
      !_configuration.hasAnnotationOf(element) &&
      !_notProxied.any((c) => c.isAssignableFromType(element.thisType));

  /// The proxy of [targetType]; `null` when proxies are off or the type is
  /// from the SDK. A component class (created by the container through
  /// [constructor]) that cannot be implemented gets a subclass proxy in
  /// `all` mode, or fails the build when it cannot be extended either; any
  /// other type that cannot be proxied gets a signature-only model with
  /// [ProxyModel.unavailableReason].
  ProxyModel? _proxyModel(
    InterfaceType targetType,
    String className, {
    required bool implementSelf,
    ProxyMode? mode,
    ConstructorElement? constructor,
  }) {
    _proxyFailure = null;
    final model = _buildProxyModel(
      targetType,
      className,
      implementSelf: implementSelf,
      mode: mode,
    );
    final failure = _proxyFailure;
    if (model != null || failure == null) {
      return _rejectCachedStreams(model);
    }
    if (constructor != null && (mode ?? proxyMode) == ProxyMode.all) {
      return _rejectCachedStreams(
        _subclassProxyModel(targetType, className, constructor, failure),
      );
    }
    return _rejectCachedStreams(
      _signatureOnlyModel(targetType, className, failure),
    );
  }

  // A subclass proxy (see `SubclassProxy`) of a component class that no
  // generated class can implement ([implementFailure]); fails the build
  // when the class cannot be extended, saying what to change.
  ProxyModel? _subclassProxyModel(
    InterfaceType targetType,
    String className,
    ConstructorElement constructor,
    String implementFailure,
  ) {
    final element = targetType.element;
    final typeName = element.name!;
    Never fail(String problem, String change) => _fail(
      '$typeName cannot be proxied for AOP: $implementFailure A subclass '
      'proxy (the bean created as a generated subclass of $typeName) is not '
      'possible either, because $typeName $problem. $change, add an '
      'interface with the advised methods and inject the bean by it, or '
      'generate no proxy for it (aop_proxies: interfaces or none).',
      element,
    );
    if (element is! ClassElement) {
      fail('is not a class', 'Make it a class');
    }
    final modifier = element.isSealed
        ? 'sealed'
        : element.isFinal
        ? 'final'
        : element.isInterface
        ? 'interface'
        : null;
    if (modifier != null || !element.isExtendableOutside) {
      fail(
        'cannot be extended${modifier == null ? '' : ' (it is $modifier)'}',
        modifier == null ? 'Make it extendable' : 'Remove `$modifier`',
      );
    }
    if (targetType.typeArguments.isNotEmpty) {
      fail('is generic', 'Remove its type parameters');
    }
    if (constructor.isFactory) {
      fail(
        'is created through the factory constructor '
            '${constructor.displayName}, which a subclass cannot call',
        'Add a public generative constructor',
      );
    }
    // Public members with an implementation the subclass can override and
    // forward; one it cannot (private types, a non-constant default) stays
    // inherited and unadvised, like a final method under CGLIB.
    final library = element.library;
    final members = <ProxyMember>[];
    final seen = <String>{};
    void skip(String kind, String name, String reason) => log.warning(
      'The $kind $typeName.$name is not advised: the subclass proxy of '
      '$typeName cannot override it ($reason).',
    );
    for (final current in _hierarchy(targetType)) {
      final declaring = current.name!;
      for (final method in current.methods) {
        final name = method.name;
        if (method.isStatic ||
            method.isPrivate ||
            name == null ||
            method.isOperator ||
            name == 'noSuchMethod' ||
            !seen.add('m:$name')) {
          continue;
        }
        final implementation = targetType.lookUpMethod(name, library);
        if (implementation == null ||
            implementation.library.isInSdk ||
            (name == 'toString' && implementation.formalParameters.isEmpty)) {
          continue;
        }
        if (_advisedMembers.contains(name)) {
          _fail(_reservedMessage(typeName, name), element);
        }
        final member = _proxyMethod(implementation, method, declaring);
        if (member == null) {
          skip(
            'method',
            name,
            'a parameter default value is not a public constant, or a '
                'signature uses a private type',
          );
          continue;
        }
        members.add(member);
      }
      for (final getter in current.getters) {
        final name = getter.name;
        if (getter.isStatic ||
            getter.isPrivate ||
            name == null ||
            name == 'hashCode' ||
            name == 'runtimeType' ||
            !seen.add('g:$name')) {
          continue;
        }
        final implementation = targetType.lookUpGetter(name, library);
        if (implementation == null || implementation.library.isInSdk) {
          continue;
        }
        if (_advisedMembers.contains(name)) {
          _fail(_reservedMessage(typeName, name), element);
        }
        if (!_isEmittable(implementation.returnType)) {
          skip('getter', name, 'its type is private');
          continue;
        }
        members.add(
          ProxyMember(
            kind: ProxyMemberKind.getter,
            name: name,
            declaringType: declaring,
            returnType: implementation.returnType,
            typeParameters: const [],
            parameters: const [],
            annotations: [
              ..._userAnnotations(implementation),
              ..._userAnnotations(getter),
            ],
          ),
        );
      }
      for (final setter in current.setters) {
        final name = setter.name;
        if (setter.isStatic ||
            setter.isPrivate ||
            name == null ||
            !seen.add('s:$name')) {
          continue;
        }
        final implementation = targetType.lookUpSetter(name, library);
        if (implementation == null || implementation.library.isInSdk) {
          continue;
        }
        final parameterType = implementation.formalParameters.single.type;
        if (!_isEmittable(parameterType)) {
          skip('setter', name, 'its type is private');
          continue;
        }
        members.add(
          ProxyMember(
            kind: ProxyMemberKind.setter,
            name: name,
            declaringType: declaring,
            returnType: parameterType,
            typeParameters: const [],
            parameters: [
              ProxyParameter(
                name: 'value',
                type: parameterType,
                isNamed: false,
                isRequired: true,
              ),
            ],
            annotations: _userAnnotations(implementation),
          ),
        );
      }
    }
    final allTypes = [
      targetType,
      for (final supertype in targetType.allSupertypes)
        if (!supertype.isDartCoreObject) supertype,
    ];
    final toString = targetType.lookUpMethod('toString', library);
    return ProxyModel(
      className: module.uniqueClassName(className),
      customToString: toString != null && toString.formalParameters.isNotEmpty,
      targetType: targetType,
      interfaces: const [],
      members: _withDeclaringTypes(members, allTypes, targetType),
      classAnnotations: _userAnnotations(element),
      targetTypeNames: [for (final type in allTypes) type.element.name!],
      subclass: SubclassProxy(
        constructorName: _constructorName(constructor),
        constructorParameters: [
          for (final parameter in constructor.formalParameters)
            ProxyParameter(
              name: parameter.name ?? 'p',
              type: parameter.type,
              isNamed: parameter.isNamed,
              isRequired: parameter.isRequired,
            ),
        ],
        isFinal: element.isBase,
      ),
    );
  }

  String? _proxyFailure;

  // `@Cacheable` / `@CachePut` of spring_boot_starter_cache (matched by
  // URL, so the generator does not depend on it) on a member returning a
  // Stream: a stream can be listened to once, so the cached one would fail
  // every later caller.
  ProxyModel? _rejectCachedStreams(ProxyModel? model) {
    if (model == null) {
      return null;
    }
    for (final member in model.members) {
      if (member.kind != ProxyMemberKind.method ||
          !member.returnType.isDartAsyncStream) {
        continue;
      }
      for (final annotation in member.annotations) {
        final type = annotation.type;
        if (type is! InterfaceType) {
          continue;
        }
        final caches =
            _cacheable.isExactlyType(type) ||
            _cachePut.isExactlyType(type) ||
            (_caching.isExactlyType(type) &&
                ['cacheable', 'put'].any(
                  (field) =>
                      annotation.getField(field)?.toListValue()?.isNotEmpty ??
                      false,
                ));
        if (caches) {
          final target = model.targetType;
          _fail(
            '@${type.element.name} on ${target.element.name}.${member.name} '
            'cannot cache a Stream: a stream can be listened to only once. '
            'Return a Future<List<T>> instead.',
            target.lookUpMethod(member.name, target.element.library) ??
                target.element,
          );
        }
      }
    }
    return model;
  }

  // Signatures of the public members, for pointcut matching only.
  ProxyModel _signatureOnlyModel(
    InterfaceType targetType,
    String className,
    String reason,
  ) {
    const objectMembers = {
      'toString',
      'hashCode',
      'noSuchMethod',
      'runtimeType',
      '==',
    };
    final members = <ProxyMember>[];
    final seen = <String>{};
    for (final element in _hierarchy(targetType)) {
      final declaring = element.name!;
      for (final method in element.methods) {
        final name = method.name;
        if (method.isStatic ||
            method.isPrivate ||
            name == null ||
            objectMembers.contains(name) ||
            !seen.add('m:$name')) {
          continue;
        }
        members.add(
          ProxyMember(
            kind: ProxyMemberKind.method,
            name: name,
            declaringType: declaring,
            returnType: method.returnType,
            typeParameters: const [],
            parameters: [
              for (final parameter in method.formalParameters)
                ProxyParameter(
                  name: parameter.name ?? 'p',
                  type: parameter.type,
                  isNamed: parameter.isNamed,
                  isRequired: parameter.isRequired,
                ),
            ],
            annotations: _userAnnotations(method),
          ),
        );
      }
      for (final getter in element.getters) {
        final name = getter.name;
        if (getter.isStatic ||
            getter.isPrivate ||
            name == null ||
            objectMembers.contains(name) ||
            !seen.add('g:$name')) {
          continue;
        }
        members.add(
          ProxyMember(
            kind: ProxyMemberKind.getter,
            name: name,
            declaringType: declaring,
            returnType: getter.returnType,
            typeParameters: const [],
            parameters: const [],
            annotations: _userAnnotations(getter),
          ),
        );
      }
    }
    return ProxyModel(
      className: className,
      targetType: targetType,
      interfaces: const [],
      members: members,
      classAnnotations: _userAnnotations(targetType.element),
      targetTypeNames: [
        targetType.element.name!,
        for (final supertype in targetType.allSupertypes)
          if (!supertype.isDartCoreObject) supertype.element.name!,
      ],
      unavailableReason: reason,
    );
  }

  ProxyModel? _buildProxyModel(
    InterfaceType targetType,
    String className, {
    required bool implementSelf,
    ProxyMode? mode,
  }) {
    final proxyMode = mode ?? this.proxyMode;
    if (proxyMode == ProxyMode.none || targetType.element.library.isInSdk) {
      return null;
    }
    final typeName = targetType.element.name;
    // Types the proxy implements: the target class itself only in `all`
    // mode (CGLIB style); supertypes that can be implemented, restricted to
    // abstract ones in `interfaces` mode (JDK style).
    final interfaces = <InterfaceType>[
      if (implementSelf &&
          proxyMode == ProxyMode.all &&
          _canImplement(targetType))
        targetType,
      for (final supertype in targetType.allSupertypes)
        if (!supertype.isDartCoreObject &&
            _canImplement(supertype) &&
            (proxyMode == ProxyMode.all || _isAbstract(supertype)))
          supertype,
    ];
    if (proxyMode == ProxyMode.interfaces &&
        _isAbstract(targetType) &&
        _canImplement(targetType)) {
      interfaces.insert(0, targetType);
    }
    if (interfaces.isEmpty) {
      _proxyFailure = proxyMode == ProxyMode.interfaces
          ? '$typeName implements no interface (aop_proxies: interfaces '
                'proxies interfaces only). Add an interface with the advised '
                'methods and inject the bean by it.'
          : '$typeName cannot be implemented by a generated class (it has '
                'private members, or is final, base or sealed) and implements '
                'no interface. Add an interface with the advised methods and '
                'inject the bean by it, or make its members public.';
      return null;
    }
    // Every member of every implemented type must be forwarded, otherwise
    // the proxy would not compile; one member that cannot be emitted makes
    // the whole bean non-proxyable (`return null`). Members are looked up
    // on the target so the implementation's signature (with its defaults)
    // is used.
    final library = targetType.element.library;
    final members = <ProxyMember>[];
    final seen = <String>{};
    for (final interface in interfaces) {
      for (final type in [interface, ...interface.allSupertypes]) {
        if (type.isDartCoreObject) {
          continue;
        }
        final declaring = type.element.name!;
        for (final method in type.methods) {
          final name = method.name;
          if (method.isStatic || name == null || method.isPrivate) {
            continue;
          }
          // `==` keeps proxy identity semantics; other operators cannot be
          // forwarded, so the bean is not proxied at all.
          if (name == '==') {
            continue;
          }
          if (method.isOperator) {
            _proxyFailure =
                '$typeName declares the operator $name, which a proxy cannot '
                'forward. Move the advised methods to an interface without '
                'operators.';
            return null;
          }
          // A plain `toString()` is forwarded without advice by the proxy
          // class; one with parameters is proxied like any method.
          // `noSuchMethod` must not be overridden.
          if (name == 'toString' &&
              (targetType
                      .lookUpMethod(name, library)
                      ?.formalParameters
                      .isEmpty ??
                  true)) {
            continue;
          }
          if (name == 'noSuchMethod' || !seen.add('m:$name')) {
            continue;
          }
          // Members of `Advised` cannot also be target members.
          if (_advisedMembers.contains(name)) {
            _proxyFailure = _reservedMessage(typeName, name);
            return null;
          }
          final implementation = targetType.lookUpMethod(name, library);
          final member = implementation == null
              ? null
              : _proxyMethod(implementation, method, declaring);
          if (member == null) {
            _proxyFailure =
                'the method $typeName.$name cannot be forwarded by a proxy: '
                'a parameter default value is not a public constant, or a '
                'signature uses a private type.';
            return null;
          }
          members.add(member);
        }
        for (final getter in type.getters) {
          final name = getter.name;
          if (getter.isStatic ||
              name == null ||
              getter.isPrivate ||
              name == 'hashCode' ||
              name == 'runtimeType' ||
              !seen.add('g:$name')) {
            continue;
          }
          if (_advisedMembers.contains(name)) {
            _proxyFailure = _reservedMessage(typeName, name);
            return null;
          }
          final implementation = targetType.lookUpGetter(name, library);
          if (implementation == null ||
              !_isEmittable(implementation.returnType)) {
            _proxyFailure =
                'the getter $typeName.$name uses a private type, which '
                'generated code cannot name.';
            return null;
          }
          members.add(
            ProxyMember(
              kind: ProxyMemberKind.getter,
              name: name,
              declaringType: declaring,
              returnType: implementation.returnType,
              typeParameters: const [],
              parameters: const [],
              annotations: [
                ..._userAnnotations(implementation),
                ..._userAnnotations(getter),
              ],
            ),
          );
        }
        for (final setter in type.setters) {
          final name = setter.name;
          if (setter.isStatic ||
              name == null ||
              setter.isPrivate ||
              !seen.add('s:$name')) {
            continue;
          }
          final implementation = targetType.lookUpSetter(name, library);
          final parameterType = implementation?.formalParameters.single.type;
          if (parameterType == null || !_isEmittable(parameterType)) {
            _proxyFailure =
                'the setter $typeName.$name uses a private type, which '
                'generated code cannot name.';
            return null;
          }
          members.add(
            ProxyMember(
              kind: ProxyMemberKind.setter,
              name: name,
              declaringType: declaring,
              returnType: parameterType,
              typeParameters: const [],
              parameters: [
                ProxyParameter(
                  name: 'value',
                  type: parameterType,
                  isNamed: false,
                  isRequired: true,
                ),
              ],
              annotations: _userAnnotations(implementation!),
            ),
          );
        }
      }
    }
    final allTypes = {
      for (final interface in interfaces) ...[
        interface,
        ...interface.allSupertypes,
      ],
    }.where((t) => !t.isDartCoreObject).toList();
    final withDeclaring = _withDeclaringTypes(members, allTypes, targetType);
    final toString = targetType.lookUpMethod('toString', library);
    return ProxyModel(
      className: module.uniqueClassName(className),
      customToString: toString != null && toString.formalParameters.isNotEmpty,
      targetType: targetType,
      interfaces: interfaces,
      members: withDeclaring,
      classAnnotations: _userAnnotations(targetType.element),
      targetTypeNames: [
        targetType.element.name!,
        for (final supertype in targetType.allSupertypes)
          if (!supertype.isDartCoreObject) supertype.element.name!,
      ],
    );
  }

  // For each member: every type of [allTypes] that declares it (for
  // pointcuts such as `execution(* Api.*(..))`), as `declaringType` the
  // first abstract declaring type other than the target, and the
  // annotations of every declaration (interface and class).
  List<ProxyMember> _withDeclaringTypes(
    List<ProxyMember> members,
    List<InterfaceType> allTypes,
    InterfaceType targetType,
  ) {
    Iterable<Element> declarations(InterfaceType type, ProxyMember member) =>
        switch (member.kind) {
          ProxyMemberKind.method => type.element.methods.where(
            (m) => m.name == member.name,
          ),
          ProxyMemberKind.getter => type.element.getters.where(
            (g) => g.name == member.name,
          ),
          ProxyMemberKind.setter => type.element.setters.where(
            (x) => x.name == member.name,
          ),
        };
    return [
      for (final member in members)
        () {
          final names = [
            for (final type in allTypes)
              if (declarations(type, member).isNotEmpty) type.element.name!,
          ];
          final abstract = [
            for (final type in allTypes)
              if (names.contains(type.element.name) &&
                  _isAbstract(type) &&
                  type != targetType)
                type.element.name!,
          ];
          final annotations = <DartObject>[...member.annotations];
          for (final type in allTypes) {
            for (final declaration in declarations(type, member)) {
              for (final annotation in _userAnnotations(declaration)) {
                if (!annotations.contains(annotation)) {
                  annotations.add(annotation);
                }
              }
            }
          }
          return ProxyMember(
            kind: member.kind,
            name: member.name,
            declaringType: abstract.firstOrNull ?? member.declaringType,
            declaringTypes: names,
            returnType: member.returnType,
            typeParameters: member.typeParameters,
            parameters: member.parameters,
            annotations: annotations,
          );
        }(),
    ];
  }

  // A forwarded method, or `null` if its types or default values cannot be
  // written in the generated library.
  ProxyMember? _proxyMethod(
    MethodElement implementation,
    MethodElement declaration,
    String declaringType,
  ) {
    if (!_isEmittable(implementation.returnType)) {
      return null;
    }
    final parameters = <ProxyParameter>[];
    final declared = {
      for (final parameter in declaration.formalParameters)
        parameter.name: parameter,
    };
    for (final parameter in implementation.formalParameters) {
      final type = parameter.type;
      if (!_isEmittable(type)) {
        return null;
      }
      // A literal default is copied as source; another constant is
      // re-created from its value, which must be public all the way down.
      var defaultCode = parameter.defaultValueCode;
      DartObject? defaultValue;
      if (defaultCode != null && !_literalDefault.hasMatch(defaultCode)) {
        defaultValue = parameter.computeConstantValue();
        if (defaultValue == null || !_isRevivable(defaultValue)) {
          return null;
        }
        defaultCode = null;
      }
      // Constraints and @Valid of the parameter (implementation and
      // interface), for method validation.
      final annotations = _parameterAnnotations(
        parameter,
        declared[parameter.name],
      );
      _checkConstraints(
        annotations,
        type,
        '${implementation.enclosingElement?.name}.${implementation.name}'
        '(${parameter.name})',
        parameter,
      );
      parameters.add(
        ProxyParameter(
          name: parameter.name!,
          type: type,
          isNamed: parameter.isNamed,
          isRequired: parameter.isRequired,
          defaultValueCode: defaultCode,
          defaultValue: defaultValue,
          annotations: annotations,
        ),
      );
    }
    for (final typeParameter in implementation.typeParameters) {
      final bound = typeParameter.bound;
      if (bound != null && !_isEmittable(bound)) {
        return null;
      }
    }
    return ProxyMember(
      kind: ProxyMemberKind.method,
      name: implementation.name!,
      declaringType: declaringType,
      returnType: implementation.returnType,
      typeParameters: implementation.typeParameters,
      parameters: parameters,
      annotations: _checkedReturnAnnotations(implementation, declaration),
    );
  }

  // ---------------------------------------------------------------------
  // Method validation and constraint types
  // ---------------------------------------------------------------------

  // Annotations of a parameter and of the same parameter of the interface
  // declaration (without duplicates).
  List<DartObject> _parameterAnnotations(
    FormalParameterElement parameter,
    FormalParameterElement? declared,
  ) {
    final annotations = _userAnnotations(parameter);
    if (declared != null && !identical(declared, parameter)) {
      for (final annotation in _userAnnotations(declared)) {
        if (!annotations.contains(annotation)) {
          annotations.add(annotation);
        }
      }
    }
    return annotations;
  }

  // The method's annotations; constraints among them apply to the return
  // value, so they must fit the return type.
  List<DartObject> _checkedReturnAnnotations(
    MethodElement implementation,
    MethodElement declaration,
  ) {
    final annotations = [
      ..._userAnnotations(implementation),
      if (!identical(implementation, declaration))
        ..._userAnnotations(declaration),
    ];
    _checkConstraints(
      annotations,
      implementation.returnType,
      '${implementation.enclosingElement?.name}.${implementation.name} '
      '(return value)',
      implementation,
    );
    return annotations;
  }

  // Built-in constraints must fit the type they validate, like Hibernate
  // Validator's UnexpectedTypeException (see constraint_checker.dart).
  static void _checkConstraints(
    List<DartObject> annotations,
    DartType type,
    String target,
    Element element,
  ) {
    for (final annotation in annotations) {
      if (unsupportedConstraint(annotation, type, target) case final problem?) {
        _fail(problem, element);
      }
    }
  }

  /// Whether generated code can name [type].
  // Whether generated code can re-create the constant [value] (public
  // types, constructors and constants only).
  static bool _isRevivable(DartObject value) {
    final reader = ConstantReader(value);
    if (reader.isNull ||
        reader.isBool ||
        reader.isInt ||
        reader.isDouble ||
        reader.isString) {
      return true;
    }
    if (reader.isType) {
      return _isEmittable(reader.typeValue);
    }
    if (reader.isList) {
      return reader.listValue.every(_isRevivable);
    }
    if (reader.isSet) {
      return reader.setValue.every(_isRevivable);
    }
    if (reader.isMap) {
      return reader.mapValue.entries.every(
        (e) => _isRevivable(e.key!) && _isRevivable(e.value!),
      );
    }
    if (value.toFunctionValue() case final function?) {
      return function.isPublic;
    }
    try {
      final revivable = reader.revive();
      return !revivable.isPrivate &&
          revivable.positionalArguments.every(_isRevivable) &&
          revivable.namedArguments.values.every(_isRevivable);
    } on Object {
      return false;
    }
  }

  static bool _isEmittable(DartType type) => switch (type) {
    VoidType() || DynamicType() || NeverType() || TypeParameterType() => true,
    InterfaceType() =>
      type.element.isPublic && type.typeArguments.every(_isEmittable),
    FunctionType() =>
      type.typeParameters.isEmpty &&
          _isEmittable(type.returnType) &&
          type.formalParameters.every((p) => _isEmittable(p.type)),
    RecordType() =>
      type.positionalFields.every((f) => _isEmittable(f.type)) &&
          type.namedFields.every((f) => _isEmittable(f.type)),
    _ => false,
  };

  // Abstract classes and mixins count as "interfaces" for
  // `ProxyMode.interfaces`.
  static bool _isAbstract(InterfaceType type) => switch (type.element) {
    ClassElement(:final isAbstract) => isAbstract,
    MixinElement() => true,
    _ => false,
  };

  /// Whether a class in another library can `implements` [type].
  static bool _canImplement(InterfaceType type) {
    final element = type.element;
    if (!element.isPublic ||
        element.library.isInSdk ||
        !type.typeArguments.every(_isEmittable)) {
      return false;
    }
    final implementable = switch (element) {
      ClassElement() => element.isImplementableOutside && !element.isSealed,
      MixinElement() => element.isImplementableOutside,
      _ => false,
    };
    if (!implementable) {
      return false;
    }
    // Private instance members cannot be implemented from another library
    // (the generated file), so any of them in the hierarchy rules the type
    // out.
    for (final current in [
      element,
      for (final t in element.allSupertypes) t.element,
    ]) {
      if (current.library.isInSdk) {
        continue;
      }
      final hasPrivate =
          current.fields.any((f) => !f.isStatic && f.isPrivate) ||
          current.methods.any((m) => !m.isStatic && m.isPrivate) ||
          current.getters.any((g) => !g.isStatic && g.isPrivate) ||
          current.setters.any((x) => !x.isStatic && x.isPrivate);
      if (hasPrivate) {
        return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // Construction and injection
  // ---------------------------------------------------------------------

  // Spring Boot's constructor binding: a `@ConfigurationProperties` class
  // whose only public generative constructor has parameters (and is not
  // `@Autowired`). The bean is created by `ConstructorBound.from`, which
  // binds the parameters from properties through the introspection's
  // `BeanConstructor` (this same constructor, see _dataConstructor).
  ConstructorElement? _boundConstructor(ClassElement element) {
    if (!_configurationProperties.hasAnnotationOf(element)) {
      return null;
    }
    final generative = [
      for (final constructor in element.constructors)
        if (constructor.isPublic && !constructor.isFactory) constructor,
    ];
    if (generative.length != 1) {
      return null;
    }
    final constructor = generative.single;
    return constructor.formalParameters.isEmpty ||
            _autowired.hasAnnotationOf(constructor)
        ? null
        : constructor;
  }

  // Constructor selection, like Spring's: the single `@Autowired`
  // constructor, else the public unnamed constructor, else the only public
  // constructor; otherwise the choice is ambiguous and generation fails.
  ConstructorElement _selectConstructor(ClassElement element) {
    final annotated = [
      for (final constructor in element.constructors)
        if (_autowired.hasAnnotationOf(constructor)) constructor,
    ];
    if (annotated.length > 1) {
      _fail('Only one constructor may be @Autowired.', annotated[1]);
    }
    final public = [
      for (final constructor in element.constructors)
        if (constructor.isPublic) constructor,
    ];
    final unnamed = element.unnamedConstructor;
    final selected = annotated.isNotEmpty
        ? annotated.single
        : (unnamed != null && unnamed.isPublic)
        ? unnamed
        : public.length == 1
        ? public.single
        : null;
    if (selected == null) {
      _fail(
        'Cannot choose a constructor for ${element.name}: '
        'mark one public constructor with @Autowired.',
        element,
      );
    }
    if (selected.isPrivate) {
      _fail('@Autowired constructor must be public.', selected);
    }
    return selected;
  }

  // `null` for the unnamed constructor (the analyzer may report it as
  // '' or 'new').
  String? _constructorName(ConstructorElement constructor) {
    final name = constructor.name;
    return name == null || name.isEmpty || name == 'new' ? null : name;
  }

  // One argument per parameter; named parameters keep their name.
  //
  // For constructors and `@Bean` methods ([creation]) a parameter's Dart
  // default value is kept when nothing is found, and a required collection
  // may be empty (Spring's single-constructor fallback).
  List<Argument> _arguments(
    List<FormalParameterElement> parameters, {
    bool creation = false,
  }) => [
    for (final parameter in parameters)
      Argument(
        _injectionPoint(parameter, parameter.type).forParameter(
          defaultValue: parameter.hasDefaultValue
              ? _publicConstant(
                  parameter.computeConstantValue() ??
                      _fail(
                        'Cannot evaluate the default value of '
                        '${parameter.displayName}.',
                        parameter,
                      ),
                  parameter,
                )
              : null,
          collectionsMayBeEmpty: creation,
        ),
        namedAs: parameter.isNamed ? _requireName(parameter) : null,
      ),
  ];

  /// Public `@Autowired` / `@Value` fields and setters of the class and its
  /// supertypes, in injection order (see [injectionRank]).
  List<PropertyInjection> _propertyInjections(InterfaceType type) {
    final seen = <String>{};
    final result = <PropertyInjection>[];
    final depths = _injectionDepths(type);
    // Members are read through the instantiated supertypes, so a field
    // `Repo<R>` of `BaseService<R>` is injected as `Repo<User>`.
    for (final current in _hierarchyTypes(type)) {
      final depth = depths[current.element] ?? 0;
      for (final field in current.element.fields) {
        // A field declared by a primary constructor parameter
        // (`class A(@Value('x') final String a)`) shares the parameter's
        // annotations; it is injected through the constructor.
        if (field.isStatic ||
            field.isOriginDeclaringFormalParameter ||
            !_isInjected(field)) {
          continue;
        }
        final name = _requireName(field);
        if (field.isPrivate) {
          _fail('Injected field $name must be public.', field);
        }
        if (field.setter == null) {
          _fail(
            'Injected field $name must be settable: '
            'declare it `late final` or non-final.',
            field,
          );
        }
        if (seen.add(name)) {
          result.add(
            PropertyInjection(
              name,
              _injectionPoint(
                field,
                current.getGetter(name)?.returnType ?? field.type,
              ),
              rank: injectionRank(depth, field: true),
            ),
          );
        }
      }
      for (final setter in current.setters) {
        final variable = setter.variable;
        if (setter.isStatic ||
            (variable is FieldElement &&
                variable.isOriginDeclaringFormalParameter) ||
            !_isInjected(setter)) {
          continue;
        }
        final name = _requireName(setter);
        if (setter.isPrivate) {
          _fail('Injected setter $name must be public.', setter);
        }
        if (seen.add(name)) {
          result.add(
            PropertyInjection(
              name,
              _injectionPoint(setter, setter.formalParameters.single.type),
              rank: injectionRank(depth, field: false),
            ),
          );
        }
      }
    }
    return sortedByRank(result, (p) => p.rank);
  }

  /// Depth of each class of [type]'s hierarchy for [injectionRank]: 0 for
  /// the topmost one. The superclass chain is linearized like Dart does
  /// (`class C extends B with M1, M2`: B, M1, M2, C); interfaces count as
  /// above it.
  Map<InterfaceElement, int> _injectionDepths(InterfaceType type) {
    final chain = [for (final t in _linearization(type)) t.element];
    final top = [
      for (final supertype in type.allSupertypes)
        if (!supertype.isDartCoreObject && !chain.contains(supertype.element))
          supertype.element,
      ...chain.reversed,
    ];
    return {for (final (depth, element) in top.indexed) element: depth};
  }

  // Fields and setters are injected only when annotated.
  bool _isInjected(Element element) =>
      _autowired.hasAnnotationOf(element) || _value.hasAnnotationOf(element);

  /// Public `@Autowired` methods of the class and its supertypes, in
  /// injection order (see [injectionRank]).
  List<MethodInjection> _methodInjections(InterfaceType type) {
    final seen = <String>{};
    final result = <MethodInjection>[];
    final depths = _injectionDepths(type);
    for (final current in _hierarchyTypes(type)) {
      final depth = depths[current.element] ?? 0;
      for (final method in current.methods) {
        if (method.isStatic || !_autowired.hasAnnotationOf(method)) {
          continue;
        }
        final name = _requireName(method);
        if (method.isPrivate) {
          _fail('@Autowired method $name must be public.', method);
        }
        _rejectAsync(method, '@Autowired method $name');
        if (seen.add(name)) {
          result.add(
            MethodInjection(
              name,
              _arguments(method.formalParameters),
              rank: injectionRank(depth, field: false),
            ),
          );
        }
      }
    }
    return sortedByRank(result, (m) => m.rank);
  }

  /// `@PostConstruct` / `@PreDestroy` method names; superclass and mixin
  /// methods first for init, last for destroy (like Spring).
  List<String> _lifecycleMethods(
    InterfaceType type,
    TypeChecker checker, {
    required bool superFirst,
    bool allowAsync = true,
  }) {
    final hierarchy = [for (final t in _linearization(type)) t.element];
    final ordered = superFirst ? hierarchy.reversed : hierarchy;
    final seen = <String>{};
    final result = <String>[];
    for (final element in ordered) {
      for (final method in element.methods) {
        if (!checker.hasAnnotationOf(method)) {
          continue;
        }
        final name = _requireName(method);
        if (method.isStatic ||
            method.isPrivate ||
            method.formalParameters.any((p) => p.isRequired)) {
          _fail(
            'Lifecycle method $name must be a public instance method '
            'without required parameters.',
            method,
          );
        }
        if (!allowAsync) {
          _rejectAsync(method, 'Lifecycle method $name');
        }
        if (seen.add(name)) {
          result.add(name);
        }
      }
    }
    return result;
  }

  // The methods among [names] of [type] that return a `Future` (or are
  // `async`): their lifecycle callbacks are awaited.
  Set<String> _asyncMethods(InterfaceType type, Iterable<String> names) => {
    for (final name in names)
      if (type.lookUpMethod(name, type.element.library) case final method?
          when method.firstFragment.isAsynchronous ||
              method.returnType.isDartAsyncFuture ||
              method.returnType.isDartAsyncFutureOr)
        name,
  };

  // The superclass chain (no interfaces or mixins), without `Object`.
  Iterable<InterfaceElement> _superclasses(InterfaceType type) sync* {
    var current = type.superclass;
    while (current != null && !current.isDartCoreObject) {
      yield current.element;
      current = current.superclass;
    }
  }

  /// The class first, then its supertypes (subclass declarations win).
  Iterable<InterfaceElement> _hierarchy(InterfaceType type) => [
    type.element,
    for (final supertype in type.allSupertypes)
      if (!supertype.isDartCoreObject) supertype.element,
  ];

  // A nullable declared type makes the point optional. `@Value` wins over
  // everything else; otherwise the kind follows from the type (see
  // `_pointKind`). The element name is kept for single beans so the
  // runtime can fall back to matching it against bean names.
  InjectionPoint _injectionPoint(Element element, DartType type) {
    final valueAnnotation = _value.firstAnnotationOf(element);
    final optional = type.nullabilitySuffix == NullabilitySuffix.question;
    _requirePublicType(type, element, '${_describe(element)} has');
    if (valueAnnotation != null) {
      if (_isLazy(element) ?? false) {
        _fail(
          '@Lazy on ${element.displayName}: @Value is resolved at creation; '
          'only beans can be injected lazily.',
          element,
        );
      }
      return InjectionPoint(
        kind: PointKind.value,
        type: _requireInterfaceType(type, element, stripNullable: true),
        optional: optional,
        expression: ConstantReader(valueAnnotation).read('value').stringValue,
      );
    }
    final interfaceType = _requireInterfaceType(
      type,
      element,
      stripNullable: true,
    );
    if (interfaceType.isDartAsyncFuture || interfaceType.isDartAsyncFutureOr) {
      _fail('Cannot inject a Future into ${element.displayName}.', element);
    }
    final qualifier = _qualifierOf(element);
    final (kind, beanType) = _pointKind(interfaceType, element);
    final lazy = _isLazy(element) ?? false;
    if (lazy) {
      _checkLazyPoint(element, kind, beanType, optional: optional);
    }
    return InjectionPoint(
      kind: kind,
      type: beanType,
      optional: optional,
      qualifier: qualifier,
      // Providers resolve like a single bean of the injecting bean, so
      // they get the name too.
      name: kind == PointKind.single || kind == PointKind.provider
          ? element.name
          : null,
      lazy: lazy ? _lazyProxy(beanType, element) : null,
    );
  }

  void _checkLazyPoint(
    Element element,
    PointKind kind,
    InterfaceType type, {
    required bool optional,
  }) {
    final name = element.displayName;
    if (kind != PointKind.single) {
      _fail(
        '@Lazy on $name: only a single bean can be injected lazily '
        '(ObjectProvider is lazy already; collections are not supported).',
        element,
      );
    }
    if (optional) {
      _fail(
        '@Lazy on $name: a lazy dependency cannot be nullable; use '
        'ObjectProvider<${type.element.name}> for an optional lazy bean.',
        element,
      );
    }
  }

  /// The lazy proxy class for `@Lazy` injection of [type], shared by all
  /// injection points of that type in the module.
  ProxyModel _lazyProxy(InterfaceType type, Element element) {
    final typeName = type.element.name!;
    final key = '${type.element.library.uri}#$typeName';
    final existing = module.lazyProxies[key];
    if (existing != null) {
      return existing;
    }
    final hint =
        'Inject an interface it implements, or use '
        'ObjectProvider<$typeName> and call getObject().';
    if (type.typeArguments.isNotEmpty) {
      _fail(
        '@Lazy on ${element.displayName}: generic types ($typeName<...>) '
        'cannot be injected lazily yet. $hint',
        element,
      );
    }
    if (type.element.library.isInSdk || !_canImplement(type)) {
      _fail(
        '@Lazy on ${element.displayName}: the lazy proxy must implement '
        '$typeName, which is not possible from generated code (SDK type, '
        'private members, or a final/base/sealed class). $hint',
        element,
      );
    }
    final className = '_\$${typeName}Lazy';
    final proxy = _proxyModel(
      type,
      className,
      implementSelf: true,
      mode: ProxyMode.all,
    );
    if (proxy == null || proxy.unavailableReason != null) {
      _fail(
        '@Lazy on ${element.displayName}: no lazy proxy can be generated: '
        '${proxy?.unavailableReason ?? '$typeName is an SDK type.'} $hint',
        element,
      );
    }
    return module.lazyProxies[key] = proxy;
  }

  // `List`/`Iterable`, `Set`, `Map<String, T>` and `ObjectProvider<T>`
  // inject all (or lazily one) bean(s) of the element type; any other type
  // is a single bean.
  (PointKind, InterfaceType) _pointKind(InterfaceType type, Element element) {
    InterfaceType argument(int index) => _requireInterfaceType(
      type.typeArguments[index],
      element,
      stripNullable: false,
    );
    if (type.isDartCoreList || type.isDartCoreIterable) {
      return (PointKind.list, argument(0));
    }
    if (type.isDartCoreSet) {
      return (PointKind.set, argument(0));
    }
    if (type.isDartCoreMap) {
      if (!type.typeArguments.first.isDartCoreString) {
        _fail(
          'Map injection needs String keys (bean names): '
          '${element.displayName}.',
          element,
        );
      }
      return (PointKind.map, argument(1));
    }
    // An ObjectFactory<T> point receives the same provider (Spring's
    // DependencyObjectProvider serves both).
    if (_objectProvider.isExactlyType(type) ||
        _objectFactory.isExactlyType(type)) {
      return (PointKind.provider, argument(0));
    }
    return (PointKind.single, type);
  }

  // Only class types can be looked up by type at runtime. With
  // [stripNullable] the `?` is removed (nullability is tracked as
  // `optional`); otherwise a nullable type is an error.
  InterfaceType _requireInterfaceType(
    DartType type,
    Element element, {
    required bool stripNullable,
  }) {
    if (type is! InterfaceType) {
      _fail(
        'Cannot inject ${type.getDisplayString()} into '
        '${element.displayName}: only class types can be injected.',
        element,
      );
    }
    if (type.nullabilitySuffix == NullabilitySuffix.question &&
        !stripNullable) {
      _fail(
        'Collection and provider element types must not be nullable: '
        '${element.displayName}.',
        element,
      );
    }
    return type.nullabilitySuffix == NullabilitySuffix.none
        ? type
        : type.element.instantiate(
            typeArguments: type.typeArguments,
            nullabilitySuffix: NullabilitySuffix.none,
          );
  }

  // ---------------------------------------------------------------------
  // Types
  // ---------------------------------------------------------------------

  // The types a bean can be looked up by: its own type and every public
  // supertype (a private type cannot be written in generated code).
  // Supertypes from internal SDK libraries (`EfficientLengthIterable` of
  // `dart:_internal`) are left out: generated code cannot import them.
  //
  // A generic type is also exposed in its raw form, instantiated to bounds
  // (`Store<User>` also as `Store<dynamic>`, what a raw `Store` means in
  // Dart): `List<Store>` gets every store, like a raw type in Spring.
  List<InterfaceType> _exposedTypes(InterfaceType type) {
    final types = [
      type,
      for (final supertype in type.allSupertypes)
        if (!supertype.isDartCoreObject &&
            _isPublicType(supertype) &&
            !isInternalSdkType(supertype))
          supertype,
    ];
    final seen = {for (final t in types) (t.element, t.getDisplayString())};
    return [
      ...types,
      for (final t in types)
        if (t.typeArguments.isNotEmpty)
          if (t.element.library.typeSystem.instantiateInterfaceToBounds(
                element: t.element,
                nullabilitySuffix: NullabilitySuffix.none,
              )
              case final raw
              when _isWritableType(raw) &&
                  seen.add((raw.element, raw.getDisplayString())))
            raw,
    ];
  }

  // For a `FactoryBean<T>`, the exposed types of the product `T`; `null`
  // for other beans.
  List<InterfaceType>? _factoryObjectTypes(InterfaceType type) {
    for (final supertype in [type, ...type.allSupertypes]) {
      if (_factoryBean.isExactlyType(supertype)) {
        final product = supertype.typeArguments.single;
        if (product is! InterfaceType) {
          _fail('FactoryBean product must be a class type.', type.element);
        }
        return _exposedTypes(product);
      }
    }
    return null;
  }

  // Public, including all class type arguments.
  bool _isPublicType(InterfaceType type) =>
      type.element.isPublic &&
      type.typeArguments.every((t) => t is! InterfaceType || _isPublicType(t));

  // ---------------------------------------------------------------------
  // Declaration annotations
  // ---------------------------------------------------------------------

  // `@Scope('...')` value, `singleton` by default.
  String _scopeOf(Element element) {
    final annotation = _scope.firstAnnotationOf(element);
    return annotation == null
        ? 'singleton'
        : ConstantReader(annotation).read('value').stringValue;
  }

  // `null` when there is no `@Lazy`, so `@Lazy(false)` on a `@Bean` method
  // can override `@Lazy()` on its configuration class.
  bool? _isLazy(Element element) {
    final annotation = _lazy.firstAnnotationOf(element);
    return annotation == null
        ? null
        : ConstantReader(annotation).read('value').boolValue;
  }

  int? _orderOf(Element element) {
    final annotation = _order.firstAnnotationOf(element);
    return annotation == null
        ? null
        : ConstantReader(annotation).read('value').intValue;
  }

  String? _descriptionOf(Element element) {
    final annotation = _description.firstAnnotationOf(element);
    return annotation == null
        ? null
        : ConstantReader(annotation).read('value').stringValue;
  }

  List<String> _dependsOnOf(Element element) => [
    for (final annotation in _dependsOn.annotationsOf(element))
      for (final name in ConstantReader(annotation).read('value').listValue)
        name.toStringValue()!,
  ];

  Set<String> _qualifiersOf(Element element) => {
    for (final annotation in _qualifier.annotationsOf(element))
      ConstantReader(annotation).read('value').stringValue,
  };

  /// `@Qualifier` or `@Named` value at an injection point.
  String? _qualifierOf(Element element) {
    final qualifier = _qualifier.firstAnnotationOf(element);
    if (qualifier != null) {
      return ConstantReader(qualifier).read('value').stringValue;
    }
    final named = _named.firstAnnotationOf(element);
    return named == null
        ? null
        : ConstantReader(named).peek('name')?.stringValue ?? element.name;
  }

  // Three kinds of conditions: `@Profile`, `@Conditional([Type])` and any
  // const annotation whose class implements `Condition` (re-emitted as a
  // const expression, see `ModuleEmitter`).
  List<ConditionModel> _conditions(Element element) {
    final result = <ConditionModel>[];
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (value == null || type is! InterfaceType) {
        continue;
      }
      if (_profile.isExactlyType(type)) {
        result.add(
          ProfileConditionModel([
            for (final p in ConstantReader(value).read('value').listValue)
              p.toStringValue()!,
          ]),
        );
      } else if (_conditional.isExactlyType(type)) {
        for (final conditionType in ConstantReader(
          value,
        ).read('value').listValue) {
          final type = conditionType.toTypeValue();
          if (type is! InterfaceType ||
              !_condition.isAssignableFromType(type) ||
              type.element.unnamedConstructor?.formalParameters.any(
                    (p) => p.isRequired,
                  ) !=
                  false) {
            _fail(
              '@Conditional types must implement Condition and have a '
              'no-argument constructor.',
              element,
            );
          }
          result.add(TypeConditionModel(type));
        }
      } else if (_condition.isAssignableFromType(type)) {
        result.add(AnnotationConditionModel(value));
      }
    }
    return result;
  }

  Iterable<ClassElement> _importedClasses(ClassElement element) sync* {
    for (final annotation in _import.annotationsOf(element)) {
      for (final value in ConstantReader(annotation).read('value').listValue) {
        final imported = value.toTypeValue()?.element;
        if (imported is! ClassElement) {
          _fail('@Import accepts class types only.', element);
        }
        yield imported;
      }
    }
  }

  List<PropertySourceModel> _propertySources(
    ClassElement element,
    List<ConditionModel> conditions,
  ) => [
    for (final annotation in _propertySource.annotationsOf(element))
      () {
        final reader = ConstantReader(annotation);
        final factory = reader.peek('factory')?.typeValue;
        if (factory != null &&
            (factory is! InterfaceType ||
                factory.element.unnamedConstructor?.formalParameters.any(
                      (p) => p.isRequired,
                    ) !=
                    false)) {
          _fail(
            '@PropertySource factory must have a no-argument constructor.',
            element,
          );
        }
        return PropertySourceModel(
          [
            for (final location in reader.read('value').listValue)
              location.toStringValue()!,
          ],
          name: reader.peek('name')?.stringValue,
          ignoreResourceNotFound:
              reader.peek('ignoreResourceNotFound')?.boolValue ?? false,
          conditions: conditions,
          element: element,
          factoryType: factory as InterfaceType?,
        );
      }(),
  ];

  // ---------------------------------------------------------------------
  // Init / destroy methods
  // ---------------------------------------------------------------------

  // Validates `@Bean(initMethod:/destroyMethod:)` against the bean type.
  String _requireNoArgMethod(
    InterfaceType type,
    String name,
    Element element,
    String attribute,
  ) {
    final method = type.lookUpMethod(name, type.element.library);
    if (method == null ||
        method.isStatic ||
        method.formalParameters.any((p) => p.isRequired)) {
      _fail(
        "@Bean $attribute '$name' must be a no-argument instance method of "
        '${type.getDisplayString()}.',
        element,
      );
    }
    return name;
  }

  // The destroy method of a `@Bean`, unless the same method is already a
  // `@PreDestroy` method of the returned type (it must run only once).
  String? _beanDestroyMethod(
    InterfaceType type,
    String? name,
    Element element,
  ) {
    final destroy = _destroyMethod(type, name, element);
    return destroy != null &&
            _lifecycleMethods(
              type,
              _preDestroy,
              superFirst: false,
            ).contains(destroy)
        ? null
        : destroy;
  }

  // `''` disables the destroy method; `'(inferred)'` (Spring's
  // `AbstractBeanDefinition.INFER_METHOD`) picks the first public
  // `close`, `shutdown` or `dispose` method without required parameters.
  String? _destroyMethod(InterfaceType type, String? name, Element element) {
    if (name == null || name.isEmpty) {
      return null;
    }
    if (name != '(inferred)') {
      return _requireNoArgMethod(type, name, element, 'destroyMethod');
    }
    for (final candidate in const ['close', 'shutdown', 'dispose']) {
      final method = type.lookUpMethod(candidate, type.element.library);
      if (method != null &&
          !method.isStatic &&
          method.isPublic &&
          !method.formalParameters.any((p) => p.isRequired)) {
        return candidate;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------

  // `ApplicationListener<E>` implementations first, then `@EventListener`
  // methods of the class and its supertypes (subclass first, one listener
  // per method name).
  List<ListenerModel> _listeners(ClassElement element) {
    final className = _requireName(element);
    final result = <ListenerModel>[];
    for (final supertype in element.allSupertypes) {
      if (_applicationListener.isExactlyType(supertype)) {
        final eventType = supertype.typeArguments.single;
        if (eventType is InterfaceType) {
          result.add(
            ListenerModel(
              id: '$className.onApplicationEvent',
              methodName: 'onApplicationEvent',
              eventTypes: [eventType],
              parameterType: eventType,
              returnsValue: false,
              order: _orderOf(element),
            ),
          );
        }
      }
    }
    for (final interface in _hierarchyTypes(element.thisType)) {
      for (final method in interface.methods) {
        final annotation = _eventListener.firstAnnotationOf(method);
        if (annotation == null) {
          continue;
        }
        final methodName = _requireName(method);
        if (result.any((l) => l.methodName == methodName)) {
          continue;
        }
        result.add(_listener(className, method, ConstantReader(annotation)));
      }
    }
    return result;
  }

  // The event types come from `classes:` or else the single parameter.
  // A non-void, non-Future result is published as a new event.
  ListenerModel _listener(
    String className,
    MethodElement method,
    ConstantReader annotation,
  ) {
    final methodName = _requireName(method);
    if (method.isStatic || method.isPrivate) {
      _fail('@EventListener method $methodName must be public.', method);
    }
    final parameters = method.formalParameters;
    if (parameters.length > 1 ||
        parameters.any((p) => p.isNamed && p.isRequired)) {
      _fail(
        '@EventListener method $methodName must have at most one parameter.',
        method,
      );
    }
    final parameterType = parameters.isEmpty
        ? null
        : _requireInterfaceType(
            parameters.single.type,
            method,
            stripNullable: true,
          );
    final classes = [
      for (final value in annotation.read('classes').listValue)
        if (value.toTypeValue() case final InterfaceType type) type,
    ];
    for (final type in [?parameterType, ...classes]) {
      _requirePublicType(type, method, '${_describe(method)} listens to');
    }
    if (classes.isEmpty && parameterType == null) {
      _fail(
        '@EventListener method $methodName needs an event parameter or '
        '`classes`.',
        method,
      );
    }
    final returnType = method.returnType;
    final conditionValue = annotation.peek('condition');
    final condition = conditionValue?.objectValue.toFunctionValue();
    if (conditionValue != null && condition == null) {
      _fail('@EventListener condition must be a function.', method);
    }
    return ListenerModel(
      id: annotation.peek('id')?.stringValue ?? '$className.$methodName',
      methodName: methodName,
      eventTypes: classes.isEmpty ? [parameterType!] : classes,
      parameterType: parameterType,
      returnsValue:
          returnType is! VoidType &&
          !returnType.isDartAsyncFuture &&
          !returnType.isDartAsyncFutureOr,
      order: _orderOf(method),
      condition: condition,
    );
  }

  // ---------------------------------------------------------------------
  // Interface proxies (`@InterfaceProxy`)
  // ---------------------------------------------------------------------

  // `primary` of the `@InterfaceProxy()` on the class of one of
  // [element]'s annotations, or `null` when it has none. A `bool primary`
  // field of the annotation itself wins (`@FeignClient(primary: false)`).
  bool? _interfaceProxyPrimary(ClassElement element) {
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (type is! InterfaceType) {
        continue;
      }
      final marker = _interfaceProxy.firstAnnotationOf(type.element);
      if (marker != null) {
        final own = ConstantReader(value).peek('primary');
        if (own != null && own.isBool) {
          return own.boolValue;
        }
        return ConstantReader(marker).peek('primary')?.boolValue ?? false;
      }
    }
    return null;
  }

  // The `List<String> qualifiers` field of [element]'s annotation marked
  // `@InterfaceProxy()`, if it has one (`@FeignClient(qualifiers: [...])`).
  Set<String> _interfaceProxyQualifiers(ClassElement element) {
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (type is InterfaceType &&
          _interfaceProxy.firstAnnotationOf(type.element) != null) {
        final qualifiers = ConstantReader(value).peek('qualifiers');
        if (qualifiers != null && qualifiers.isList) {
          return {
            for (final item in qualifiers.listValue) ?item.toStringValue(),
          };
        }
      }
    }
    return const {};
  }

  // The interface becomes a bean created by `_$XImpl.create(r)`; every
  // method forwards to the `InvocationHandler` of a factory bean.
  void _scanInterfaceProxy(ClassElement element, {required bool primary}) {
    final name = _requireName(element);
    final source = '${element.library.uri}#$name';
    if (!module.markScanned(source)) {
      return;
    }
    if (element.isPrivate) {
      _fail('Interface $name must be public.', element);
    }
    if (element.typeParameters.isNotEmpty) {
      _fail('Generic interface $name is not supported.', element);
    }
    if (!element.isAbstract) {
      _fail(
        '$name must be abstract (an interface) to get a generated '
        'implementation.',
        element,
      );
    }
    final type = element.thisType;
    final className = module.uniqueClassName('_\$${name}Impl');
    final signatures = _proxyModel(
      type,
      className,
      implementSelf: true,
      mode: ProxyMode.all,
    );
    if (signatures == null || signatures.unavailableReason != null) {
      _fail(
        'Cannot implement $name: '
        '${signatures?.unavailableReason ?? 'unsupported type'}',
        element,
      );
    }
    final methods = <InterfaceMethodModel>[];
    for (final member in signatures.members) {
      final method = _hierarchy(type)
          .expand((e) => e.methods)
          .where((m) => m.name == member.name)
          .firstOrNull;
      if (member.kind != ProxyMemberKind.method || method == null) {
        _fail(
          '$name.${member.name}: only methods are supported in an interface '
          'with a generated implementation (no getters or setters).',
          element,
        );
      }
      if (!method.isAbstract) {
        _fail(
          '$name.${member.name} has a body: every method of the interface is '
          'implemented by the generated class.',
          method,
        );
      }
      if (member.typeParameters.isNotEmpty) {
        _fail('$name.${member.name} must not be generic.', method);
      }
      final returnType = member.returnType;
      final isFuture =
          returnType is InterfaceType &&
          returnType.isDartAsyncFuture &&
          returnType.nullabilitySuffix == NullabilitySuffix.none;
      final valueType = isFuture ? returnType.typeArguments.single : returnType;
      final parameterElements = {
        for (final parameter in method.formalParameters)
          parameter.name: parameter,
      };
      final parameters = [
        for (final parameter in member.parameters)
          ConstructorParameterModel(
            name: parameter.name,
            type: parameter.type,
            isNamed: parameter.isNamed,
            isRequired: parameter.isRequired,
            annotations: [
              if (parameterElements[parameter.name] case final element?)
                ..._userAnnotations(element),
            ],
          ),
      ];
      methods.add(
        InterfaceMethodModel(
          name: member.name,
          valueType: valueType,
          isFuture: isFuture,
          isVoid: valueType is VoidType,
          parameters: parameters,
          annotations: member.annotations,
        ),
      );
      // Request and response classes of the same package are introspected,
      // so they can be (de)serialized without annotations of their own.
      _introspectUsed(valueType, element);
      for (final parameter in parameters) {
        _introspectUsed(parameter.type, element);
      }
    }
    final model = InterfaceProxyModel(
      className: className,
      type: type,
      signatures: signatures,
      methods: methods,
      annotations: _userAnnotations(element),
    );
    module.beans.add(
      BeanModel(
        element: element,
        source: source,
        name: _decapitalize(name),
        type: type,
        exposedTypes: _exposedTypes(type),
        creation: InterfaceProxyCreation(model),
        primary: primary || _primary.hasAnnotationOf(element),
        qualifiers: {
          ..._qualifiersOf(element),
          ..._interfaceProxyQualifiers(element),
        },
        annotations: _beanAnnotations(element),
        conditions: [
          if (_conditions(element) case final own when own.isNotEmpty)
            GroupConditionModel(source, own),
        ],
        // Advice (e.g. @Cacheable on interface methods) wraps the client.
        proxy: proxyMode == ProxyMode.none
            ? null
            : _proxyModel(type, '_\$${name}Proxy', implementSelf: true),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Annotated methods (`@BeanMethodAnnotation`)
  // ---------------------------------------------------------------------

  // Methods of the class and its supertypes carrying an annotation whose
  // class is marked `@BeanMethodAnnotation()` (subclass declarations win,
  // one per method name).
  List<AnnotatedMethodModel> _annotatedMethods(InterfaceType type) {
    final result = <String, AnnotatedMethodModel>{};
    for (final element in _hierarchy(type)) {
      for (final method in element.methods) {
        final name = method.name;
        if (name == null || result.containsKey(name)) {
          continue;
        }
        final marked = [
          for (final annotation in method.metadata.annotations)
            if (annotation.computeConstantValue()?.type
                case final InterfaceType annotationType
                when _beanMethodAnnotation.hasAnnotationOf(
                  annotationType.element,
                ))
              annotationType.element.name,
        ];
        if (marked.isEmpty) {
          continue;
        }
        final what = '@${marked.first} method ${element.name}.$name';
        if (method.isStatic || method.isPrivate) {
          _fail('$what must be a public instance method.', method);
        }
        if (method.formalParameters.any((p) => p.isNamed && p.isRequired)) {
          _fail('$what must not have required named parameters.', method);
        }
        result[name] = AnnotatedMethodModel(
          name: name,
          parameterTypes: [
            for (final parameter in method.formalParameters)
              if (parameter.isPositional)
                switch (parameter.type) {
                  final InterfaceType t => _requireInterfaceType(
                    t,
                    method,
                    stripNullable: true,
                  ),
                  _ => null,
                },
          ],
          annotations: _userAnnotations(method),
        );
      }
    }
    return result.values.toList();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  // The container calls these methods synchronously, so a Future would be
  // silently dropped.
  void _rejectAsync(MethodElement method, String description) {
    final returnType = method.returnType;
    if (method.firstFragment.isAsynchronous ||
        returnType.isDartAsyncFuture ||
        returnType.isDartAsyncFutureOr) {
      _fail('$description must not be async.', method);
    }
  }

  // Analyzer elements may be unnamed (e.g. while code is incomplete).
  String _requireName(Element element) =>
      element.name ?? _fail('Unnamed element.', element);

  /// Spring's rule: `AuthService` → `authService`, `URLService` stays.
  static String _decapitalize(String name) {
    if (name.length > 1 &&
        name[0].toUpperCase() == name[0] &&
        name[1].toUpperCase() == name[1] &&
        name[1].toLowerCase() != name[1]) {
      return name;
    }
    return name[0].toLowerCase() + name.substring(1);
  }

  // ---------------------------------------------------------------------
  // Private declarations
  // ---------------------------------------------------------------------

  /// Fails when [type] (or a type argument) is private to its library: the
  /// generated module is another library and cannot name it. [use] says
  /// what references it ("constructor parameter dep of Cache has"),
  /// [alternative] a second way out besides making the type public.
  void _requirePublicType(
    DartType type,
    Element element,
    String use, [
    String? alternative,
  ]) {
    final private = _privateType(type);
    if (private == null) {
      return;
    }
    final name = private.element.name;
    _fail(
      '${_capitalize(use)} the private type $name (declared in '
      '${private.element.library.uri}), which the generated module cannot '
      'reference: make $name public'
      '${alternative == null ? '' : ', $alternative'}.',
      element,
    );
  }

  /// The private class [type] mentions (itself, a type argument, a
  /// function or record part), or `null`.
  static InterfaceType? _privateType(DartType type) => switch (type) {
    InterfaceType() when type.element.isPrivate => type,
    InterfaceType() => _firstPrivateType(type.typeArguments),
    FunctionType() => _firstPrivateType([
      type.returnType,
      for (final parameter in type.formalParameters) parameter.type,
    ]),
    RecordType() => _firstPrivateType([
      for (final field in type.positionalFields) field.type,
      for (final field in type.namedFields) field.type,
    ]),
    _ => null,
  };

  static InterfaceType? _firstPrivateType(Iterable<DartType> types) {
    for (final type in types) {
      if (_privateType(type) case final private?) {
        return private;
      }
    }
    return null;
  }

  /// [value], the default of [parameter], when the generated module can
  /// write it; fails when it refers to a private function, class or
  /// constant.
  DartObject _publicConstant(
    DartObject value,
    FormalParameterElement parameter,
  ) {
    final private = _privateConstantPart(value);
    if (private != null) {
      _fail(
        'The default value of ${_describe(parameter)} uses the private '
        '$private, which the generated module cannot reference: make it '
        'public, or declare the parameter without a default.',
        parameter,
      );
    }
    return value;
  }

  // The private declaration [value] refers to (`_f`, `_Opts`, `_Mode.a`,
  // `Opts._()`) as "name (declared in library)", or `null`.
  String? _privateConstantPart(DartObject value) {
    final reader = ConstantReader(value);
    if (reader.isNull ||
        reader.isBool ||
        reader.isInt ||
        reader.isDouble ||
        reader.isString ||
        reader.isSymbol) {
      return null;
    }
    String describe(Element element) =>
        '${element.name} (declared in ${element.library?.uri})';
    if (reader.isType) {
      return switch (_privateType(reader.typeValue)) {
        final type? => describe(type.element),
        null => null,
      };
    }
    if (reader.isList || reader.isSet || reader.isMap) {
      final items = reader.isList
          ? reader.listValue
          : reader.isSet
          ? reader.setValue
          : [...reader.mapValue.keys, ...reader.mapValue.values].nonNulls;
      return items.map(_privateConstantPart).nonNulls.firstOrNull;
    }
    if (value.toFunctionValue() case final function?) {
      final enclosing = function.enclosingElement;
      return function.isPrivate
          ? describe(function)
          : enclosing is InterfaceElement && enclosing.isPrivate
          ? describe(enclosing)
          : null;
    }
    if (value.type case final type?) {
      if (_privateType(type) case final private?) {
        return describe(private.element);
      }
    }
    try {
      final revivable = reader.revive();
      if (revivable.isPrivate) {
        final type = revivable.source.fragment;
        final name = [
          if (type.isNotEmpty) type,
          if (revivable.accessor.isNotEmpty) revivable.accessor,
        ].join('.');
        // A private constructor of a public class: its library is the
        // class's (the revivable source is an `asset:` URI).
        final library =
            value.type?.element?.library?.uri ??
            revivable.source.removeFragment();
        return '$name (declared in $library)';
      }
      return [
        ...revivable.positionalArguments,
        ...revivable.namedArguments.values,
      ].map(_privateConstantPart).nonNulls.firstOrNull;
    } on Object {
      // Not re-creatable at all: the emitter reports that.
      return null;
    }
  }

  // "constructor parameter dep of Cache", "field repo of UserService",
  // "@Bean method Config.pool", "parameter x of method Config.wire".
  String _describe(Element element) {
    final owner = element.enclosingElement;
    final ownerName = owner is InterfaceElement
        ? owner.name ?? ''
        : owner?.displayName ?? '';
    return switch (element) {
      FormalParameterElement() =>
        owner is ConstructorElement
            ? 'constructor parameter ${element.name} of '
                  '${owner.displayName.replaceFirst(RegExp(r'\.new$'), '')}'
            : 'parameter ${element.name} of ${_describe(owner!)}',
      FieldElement() => 'field ${element.name} of $ownerName',
      SetterElement() => 'setter ${element.name} of $ownerName',
      MethodElement() =>
        '${_bean.hasAnnotationOf(element) ? '@Bean ' : ''}method '
            '$ownerName.${element.name}',
      _ => element.displayName,
    };
  }

  static String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  // [element] may be a member of an instantiated supertype: the error
  // points at its declaration.
  static Never _fail(String message, Element element) =>
      throw InvalidGenerationSource(message, element: element.baseElement);
}
