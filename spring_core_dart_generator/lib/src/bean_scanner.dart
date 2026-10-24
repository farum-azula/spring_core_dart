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
import 'package:spring_core_dart_generator/src/json_annotation_checker.dart';

part 'bean_type_inference.dart';
part 'configuration_scanning.dart';
part 'lookup_scanning.dart';

// Annotations are matched by name in `package:spring_core_dart` (the
// generator depends on the runtime only for its pointcut parser, see
// aop_analysis.dart).
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
final _lookup = _spring('Lookup');
final _value = _spring('Value');
final _postConstruct = _spring('PostConstruct');
final _preDestroy = _spring('PreDestroy');
final _profile = _spring('Profile');
final _conditional = _spring('Conditional');
final _condition = _spring('Condition');
final _import = _spring('Import');
final _async = _spring('Async');
// `@Import`ed classes the runtime instantiates instead of scanning.
final _importRegistrars = [
  _spring('BeanRegistrar'),
  _spring('ImportSelector'),
  _spring('ImportBeanDefinitionRegistrar'),
];
final _propertySource = _spring('PropertySource');
final _configurable = _spring('Configurable');
final _eventListener = _spring('EventListener');
final _beanMethodAnnotation = _spring('BeanMethodAnnotation');
final _jsonCreator = _spring('JsonCreator');
final _jsonSubTypes = _spring('JsonSubTypes');
final _jsonTypeInfo = _spring('JsonTypeInfo');
final _jsonView = _spring('JsonView');

// `@ConfigurationProperties` from spring_boot_dart (matched by URL, so the
// generator does not depend on that package): constructor binding.
const _configurationProperties = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#ConfigurationProperties',
);
final _interfaceProxy = _spring('InterfaceProxy');
final _factoryBean = _spring('FactoryBean');
final _applicationListener = _spring('ApplicationListener');
final _objectProvider = _spring('ObjectProvider');
final _objectFactory = _spring('ObjectFactory');
final _provider = _spring('Provider');
final _resource = _spring('Resource');
final _introspected = _spring('Introspected');
final _aspectAnnotation = _spring('Aspect');
final _constraint = _spring('Constraint');
final _valid = _spring('Valid');
final _pointcutAnnotation = _spring('Pointcut');
final _adviceAnnotations = {
  'around': _spring('Around'),
  'before': _spring('Before'),
  'after': _spring('After'),
  'afterReturning': _spring('AfterReturning'),
  'afterThrowing': _spring('AfterThrowing'),
};
final _declareParents = _spring('DeclareParents');
final _advisor = _spring('Advisor');
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
const _advisedMembers = {
  'aopTarget',
  'aopAdvisors',
  'addAdvisor',
  'removeAdvisor',
  'addAdvice',
  'removeAdvice',
};

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
  r'(?<![@\w.])(@annotation|@within|@target|@args|this|target|args)\s*\(([^()]*)\)',
);

// `args(...)` / `@args(...)` and their bodies.
final _argsDesignator = RegExp(r'(?<![\w.])(@?args)\s*\(([^()]*)\)');

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
  'Resource',
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

/// Several independent validation errors of one build, reported together
/// (each with its message, library URI and location) instead of one per
/// build.
///
/// ```dart
/// // Two broken classes in one scanned directory:
/// // 2 problems in this build:
/// //
/// // 1. Bean class Broken must not be abstract.
/// //    package:app/src/broken.dart:3:16
/// //    ...
/// // 2. Only one constructor may be @Autowired ...
/// ```
class BuildErrors implements Exception {
  /// Wraps [errors] (at least two).
  BuildErrors(List<InvalidGenerationSource> errors)
    : errors = List.unmodifiable(errors);

  /// The errors, in scan order.
  final List<InvalidGenerationSource> errors;

  @override
  String toString() => [
    '${errors.length} problems in this build:',
    for (final (index, error) in errors.indexed)
      '${index + 1}. ${describeBuildError(error)}',
  ].join('\n\n');
}

/// [error] as text with the library URI of its element, also when no
/// source span can be computed for it.
String describeBuildError(InvalidGenerationSource error) {
  final text = error.toString();
  final uri = error.element?.library?.uri;
  return uri == null || text.contains('$uri') ? text : '$text\n($uri)';
}

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
  ///
  /// A problem with one declaration does not stop the scan: it is added to
  /// [errors] and the next declaration is scanned, so one build reports
  /// every independent problem (see [throwErrors]).
  void scanLibrary(LibraryElement library) {
    for (final element in library.classes) {
      if (element.isPublic) {
        module.classes.add(element);
      }
      collectErrors(() {
        if (_configurable.hasAnnotationOf(element)) {
          _scanConfigurable(element);
        }
        if (_introspected.hasAnnotationOf(element)) {
          _scanIntrospected(element);
        }
        if (_interfaceProxyPrimary(element) case final primary?) {
          _scanInterfaceProxy(element, primary: primary);
          return;
        }
        final annotation = _component.firstAnnotationOf(element);
        // Like Spring's scan (isCandidateComponent), an abstract class is
        // no candidate unless it has @Lookup methods: it is skipped, not
        // an error.
        if (element.isAbstract && !hasLookupMethods(element)) {
          return;
        }
        if (scan.isCandidate(element, isComponent: annotation != null)) {
          scanClass(element, annotation: annotation);
        }
      });
    }
    _rejectUnsupportedTargets(library);
  }

  /// Adds the aspects and advisor beans of [library] (a library of another
  /// module of the application) to [into], for proxy pruning; nothing is
  /// added to [module]. A class the scanner cannot read marks [into]
  /// unknown (its own build reports the error).
  ///
  /// ```dart
  /// final foreign = ForeignAdvice();
  /// scanner.collectAdvice(nestedLibrary, foreign);
  /// ```
  void collectAdvice(LibraryElement library, ForeignAdvice into) {
    for (final element in library.classes) {
      try {
        if (_aspectModel(element) case final aspect?) {
          into.aspects.add((element.name!, aspect));
        }
        // `@Bean AuditAspect audit() => AuditAspect();`
        if (_component.hasAnnotationOf(element)) {
          for (final (method, _) in _beanMethods(element.thisType)) {
            if (method.returnType
                case InterfaceType(element: final ClassElement returned)
                when returned != element) {
              if (_aspectModel(returned) case final aspect?) {
                into.aspects.add((returned.name!, aspect));
              }
            }
          }
        }
        if (_component.hasAnnotationOf(element) &&
            (_advisor.isAssignableFrom(element) ||
                _beanMethods(element.thisType).any(
                  (entry) => _advisor.isAssignableFromType(entry.$1.returnType),
                ))) {
          into.advisors = true;
        }
      } on InvalidGenerationSource {
        into.unknown = true;
      }
    }
  }

  /// Validation errors of the declarations scanned so far, in scan order.
  final errors = <InvalidGenerationSource>[];

  /// Runs [action], adding an `InvalidGenerationSource` it throws to
  /// [errors] instead of stopping the build.
  void collectErrors(void Function() action) {
    try {
      action();
    } on InvalidGenerationSource catch (error) {
      errors.add(error);
    }
  }

  /// Throws the collected [errors]: the single error itself, or a
  /// [BuildErrors] listing all of them; does nothing without errors.
  void throwErrors() {
    switch (errors) {
      case []:
        return;
      case [final error]:
        throw error;
      default:
        throw BuildErrors(errors);
    }
  }

  // Only classes are beans: `@Component` on a mixin, enum, extension or
  // extension type, and `@Bean` on a top-level function, would otherwise be
  // ignored silently (Spring's annotations cannot be put there at all).
  void _rejectUnsupportedTargets(LibraryElement library) {
    final targets = <(Element, String, String)>[
      for (final mixin in library.mixins)
        (
          mixin,
          'mixin',
          'annotate a class that mixes it in '
              '(`class ${mixin.name}Bean with ${mixin.name}`)',
        ),
      for (final enumElement in library.enums)
        (enumElement, 'enum', 'return the value from a @Bean method'),
      for (final extension in library.extensions)
        (
          extension,
          'extension',
          'annotate the extended class, or declare a @Bean method',
        ),
      for (final extensionType in library.extensionTypes)
        (
          extensionType,
          'extension type',
          'use a class: extension types are erased at runtime, so the '
              'container cannot tell them from their representation type',
        ),
    ];
    for (final (element, kind, instead) in targets) {
      collectErrors(() {
        if (_component.firstAnnotationOf(element) case final annotation?) {
          _fail(
            '@${annotation.type!.element!.name} on $kind '
            '${element.displayName} of ${library.uri}: only classes can be '
            'beans; $instead.',
            element,
          );
        }
      });
    }
    for (final function in library.topLevelFunctions) {
      collectErrors(() {
        if (_bean.hasAnnotationOf(function)) {
          _fail(
            '@Bean on top-level function ${function.displayName} of '
            '${library.uri}: @Bean methods belong to a class with '
            '@Configuration or @Component; move it there (as an instance '
            'or static method).',
            function,
          );
        }
      });
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
    if (element.isAbstract && !hasLookupMethods(element)) {
      _fail(
        'Bean class $className must not be abstract (an abstract class is '
        'a bean only when it has @Lookup methods for the container to '
        'implement).',
        element,
      );
    }

    // Evaluated once for the class, its @Bean methods, its property
    // sources and the classes it imports (Spring: all or nothing).
    final ownConditions = [...inheritedConditions, ..._conditions(element)];
    final classConditions = ownConditions.isEmpty
        ? const <ConditionModel>[]
        : [GroupConditionModel(source, ownConditions)];
    for (final imported in _importedClasses(element)) {
      if (_importRegistrars.any((c) => c.isAssignableFrom(imported))) {
        _addRegistrar(imported, element, classConditions);
        continue;
      }
      scanClass(
        imported,
        annotation: _component.firstAnnotationOf(imported),
        inheritedConditions: classConditions,
      );
    }
    module.propertySources.addAll(_propertySources(element, classConditions));

    // A generic class is registered under its raw type (type arguments
    // instantiated to their bounds), like Spring's definition of the raw
    // class; its members are read through that type.
    final type = element.typeParameters.isEmpty
        ? element.thisType
        : element.library.typeSystem.instantiateInterfaceToBounds(
            element: element,
            nullabilitySuffix: NullabilitySuffix.none,
          );
    final explicitName = annotation == null
        ? null
        : ConstantReader(annotation).peek('name')?.stringValue;
    final name = explicitName == null
        ? _decapitalize(className)
        : _checkBeanName(
            explicitName,
            'The bean name of $className',
            element,
            orDefault: _decapitalize(className),
          );
    // A constructor-bound @ConfigurationProperties class is created from
    // properties, not beans (see _boundConstructor).
    final constructors = _boundConstructor(element) == null
        ? [
            for (final constructor in _selectConstructors(element))
              List<ConstructorElement>.of(type.constructors).firstWhere(
                (c) => c.name == constructor.name,
                orElse: () => constructor,
              ),
          ]
        : const <ConstructorElement>[];
    final constructor = constructors.firstOrNull;
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
        ? configurationClassModel(element, type, constructor)
        : null;
    final lookup = lookupClassModel(
      element,
      type,
      constructor,
      fullConfiguration: configuration != null,
    );
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
              lookup: lookup,
              alternatives: [
                for (final alternative in constructors.skip(1))
                  ConstructorAlternative(
                    _constructorName(alternative),
                    _arguments(alternative.formalParameters, creation: true),
                  ),
              ],
            ),
      scope: _scopeOf(element),
      scopedProxy: _scopedProxyOf(element, type),
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
    if (constructors.length > 1 &&
        (configuration != null ||
            lookup != null ||
            owner.proxy?.subclass != null)) {
      final kind = configuration != null
          ? 'full-mode @Configuration'
          : lookup != null
          ? '@Lookup methods'
          : 'AOP proxy';
      _fail(
        '$className is created as a generated subclass ($kind), which '
        'calls one constructor: mark that one @Autowired() instead of '
        'several @Autowired(required: false).',
        element,
      );
    }
    module.beans.add(owner);

    // `@Lazy` on a class is the default for its `@Bean` methods, full or
    // lite configuration (Spring's processCommonDefinitionAnnotations
    // falls back to the configuration class's `@Lazy`).
    for (final (method, beanAnnotation) in beanMethods) {
      module.beans.add(
        _scanBeanMethod(
          owner,
          method,
          ConstantReader(beanAnnotation),
          classConditions: classConditions,
          classLazy: classLazy,
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
  // cannot be introspected. A generic class (`Page<T>`) is described with
  // its type parameters erased, plus a `specialize` callback the emitter
  // writes for `Page<Book>` (see ModuleEmitter._introspection).
  void _scanIntrospected(ClassElement element, {bool automatic = false}) {
    final name = _requireName(element);
    if (element.isPrivate) {
      if (automatic) {
        return;
      }
      _fail('@Introspected class $name must be public.', element);
    }
    if (!_introspectedClasses.add(element)) {
      return;
    }
    checkJsonAnnotations(element);
    final type = element.thisType;
    // Subclass first, then its mixins and superclasses (with theirs), so
    // overriding declarations win (first one kept).
    // Only fields with a getter and an interface type, and methods callable
    // with positional arguments only, can be described by BeanProperty and
    // BeanMethod; anything else is skipped silently.
    final hierarchy = [
      for (final current in [element, ..._superclasses(type)]) ...[
        current,
        // Applied mixins, the last one first (it overrides the others).
        for (final mixin in current.mixins.reversed) mixin.element,
      ],
    ];
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
        // A type parameter of the class itself (`T content`) too.
        final ownTypeParameter =
            fieldType is TypeParameterType &&
            element.typeParameters.contains(fieldType.element);
        if ((fieldType is! InterfaceType && !ownTypeParameter) ||
            field.getter == null) {
          continue;
        }
        properties[fieldName] = IntrospectedProperty(
          name: fieldName,
          type: fieldType is TypeParameterType
              ? fieldType.element.instantiate(
                  nullabilitySuffix: NullabilitySuffix.none,
                )
              : _requireInterfaceType(fieldType, field, stripNullable: true),
          declaredType: fieldType,
          // `T` may be nullable (`Page<Book?>`).
          nullable:
              ownTypeParameter ||
              fieldType.nullabilitySuffix == NullabilitySuffix.question,
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
    _introspectJsonTypes(element, [
      ..._userAnnotations(element),
      for (final property in properties.values) ...property.annotations,
      for (final parameter
          in dataConstructor?.parameters ?? const <ConstructorParameterModel>[])
        ...parameter.annotations,
    ]);
  }

  // The classes JSON annotations name are needed at runtime: the subtypes
  // of `@JsonSubTypes` and the `defaultImpl` of `@JsonTypeInfo` (to read
  // them), and the view classes of `@JsonView` (to compare views that
  // extend other views).
  void _introspectJsonTypes(ClassElement user, List<DartObject> annotations) {
    void scan(DartObject? type, {required bool automatic}) {
      if (type?.toTypeValue() case final InterfaceType listed
          when listed.element is ClassElement) {
        _scanIntrospected(listed.element as ClassElement, automatic: automatic);
      }
    }

    for (final annotation in annotations) {
      final reader = ConstantReader(annotation);
      if (_jsonSubTypes.isExactlyType(annotation.type!)) {
        for (final subType in reader.read('value').listValue) {
          scan(subType.getField('value'), automatic: false);
        }
      } else if (_jsonTypeInfo.isExactlyType(annotation.type!)) {
        scan(annotation.getField('defaultImpl'), automatic: false);
      } else if (_jsonView.isExactlyType(annotation.type!)) {
        for (final view in reader.read('value').listValue) {
          scan(view, automatic: true);
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
            hasDefault: parameter.hasDefaultValue,
            defaultValue: switch (parameter.hasDefaultValue
                ? parameter.computeConstantValue()
                : null) {
              final value? when _isRecreatable(value) => value,
              _ => null,
            },
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

  /// [_userAnnotations] of a getter or setter; for the implicit accessors of
  /// a field, also those of the field (`@Timed() int count = 0;` advises
  /// `count` like an annotated explicit getter). Constraints and `@Valid`
  /// stay out: on a field they validate the field, while on an accessor
  /// method validation would check the return value of the getter and of
  /// every setter call.
  List<DartObject> _accessorAnnotations(PropertyAccessorElement accessor) => [
    ..._userAnnotations(accessor),
    if (accessor.isOriginVariable)
      for (final annotation in _userAnnotations(accessor.variable))
        if (annotation.type case final type?
            when !_constraint.isAssignableFromType(type) &&
                !_valid.isExactlyType(type))
          annotation,
  ];

  /// Const annotations worth keeping at runtime: user annotations and
  /// constraints, not `dart:` ones or Spring's DI annotations.
  ///
  /// An annotation the generated library cannot re-create (a private
  /// constant or function among its values, `@Audit(_level)`) is left out;
  /// a constraint or `@Valid` fails the build instead, since leaving it
  /// out would skip the validation.
  List<DartObject> _userAnnotations(Element element) => [
    for (final annotation in element.metadata.annotations)
      if (annotation.computeConstantValue() case final value?)
        if (value.type case final InterfaceType type
            when !type.element.library.isInSdk &&
                type.element.isPublic &&
                !(_isSpringType(type) &&
                    _diAnnotations.contains(type.element.name)) &&
                _recreatableOrFail(value, type, element))
          value,
  ];

  bool _recreatableOrFail(
    DartObject value,
    InterfaceType type,
    Element element,
  ) {
    if (_isRecreatable(value)) {
      return true;
    }
    if (_constraint.isAssignableFromType(type) || _valid.isExactlyType(type)) {
      _fail(
        '@${type.element.name} on ${_describe(element)} uses a private '
        'constant or function, which the generated code cannot reference, '
        'so the constraint could not be checked. Make the value public.',
        element,
      );
    }
    return false;
  }

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
    final returned = method.returnType;
    _requireDefinedType(returned, method, '${_describe(method)} returns');
    // Like Spring, a @Bean method may return null (the bean is a NullBean)
    // and any type: a function or record type is registered as it is,
    // with `Function` / `Record` as its class.
    final nullable = returned.nullabilitySuffix == NullabilitySuffix.question;
    final nonNull = method.library.typeSystem.promoteToNonNull(returned);
    final valueType = nonNull is FunctionType || nonNull is RecordType
        ? nonNull
        : null;
    final typeProvider = method.library.typeProvider;
    final declaredType = switch (nonNull) {
      FunctionType() => typeProvider.functionType,
      RecordType() => typeProvider.recordType,
      _ => nonNull,
    };
    if (declaredType is! InterfaceType) {
      _fail(
        '@Bean method $methodName must return a class, function or record '
        'type.',
        method,
      );
    }
    if (declaredType.isDartAsyncFuture || declaredType.isDartAsyncFutureOr) {
      _fail('@Bean method $methodName must not be async.', method);
    }
    if (declaredType.element case ExtensionTypeElement(:final name)) {
      _fail(
        '@Bean method $methodName returns extension type $name: extension '
        'types are erased at runtime, so the container cannot tell them '
        'from their representation type. Return a class instead.',
        method,
      );
    }
    final returnType = valueType == null
        ? inferredBeanType(method, declaredType)
        : declaredType;
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
    final explicitName = annotation.peek('name')?.stringValue;
    final name = explicitName == null
        ? methodName
        : _checkBeanName(
            explicitName,
            'The bean name of ${_describe(method)}',
            method,
            orDefault: methodName,
          );
    final scope = _scopeOf(method);
    final arguments = _arguments(method.formalParameters, creation: true);
    final factoryObjectTypes = _factoryObjectTypes(returnType);
    // `@ConfigurationProperties` on a `@Bean` method binds the returned
    // object (also a class of another package): it needs introspection.
    if (_configurationProperties.hasAnnotationOf(method)) {
      if (returnType.element case final ClassElement element) {
        _scanIntrospected(element, automatic: true);
      }
    }
    return BeanModel(
      element: method,
      source: '${owner.source}.$methodName',
      name: name,
      aliases: [
        for (final alias
            in annotation.peek('aliases')?.listValue ?? const <DartObject>[])
          _checkBeanName(
            alias.toStringValue()!,
            'An alias of ${_describe(method)}',
            method,
          ),
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
                declaredType: returned,
                isFactoryBean: factoryObjectTypes != null,
                isSingleton: scope == 'singleton',
                arguments: arguments,
              ),
        declaredType: inferred ? declaredType : null,
      ),
      scope: scope,
      scopedProxy: _scopedProxyOf(method, returnType),
      valueType: valueType,
      nullable: nullable,
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
      // Like Spring, an `@Aspect` class registered through a `@Bean`
      // method is an aspect too (its advice applies to the other beans).
      aspect: switch (returnType.element) {
        final ClassElement element => _aspectModel(element),
        _ => null,
      },
      // The proxy class is named after owner and method, because two
      // `@Bean` methods may return the same type.
      proxy:
          _notProxied.any((c) => c.isAssignableFromType(returnType)) ||
              _aspectAnnotation.hasAnnotationOf(returnType.element) ||
              _configuration.hasAnnotationOf(returnType.element)
          ? null
          : _proxyModel(
              returnType,
              '_\$${owner.type.element.name}\$${_capitalize(methodName)}Proxy',
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
    final expressions = [
      for (final item in advice) item.pointcut,
      ...pointcuts.values,
    ];
    final (typeTests, annotationNames) = _argumentTypes(
      element,
      expressions,
      advice,
    );
    return AspectModel(
      advice,
      pointcuts,
      perClause: _perClause(element),
      typeTests: typeTests,
      argumentAnnotations: annotationNames,
      introductions: _introductions(element),
    );
  }

  // `@Aspect('perthis(...)')` / `@Aspect('pertarget(...)')`; `null` for a
  // singleton aspect. Like Spring, such an aspect must be a prototype
  // bean, and percflow / percflowbelow / pertypewithin are rejected.
  String? _perClause(ClassElement element) {
    final annotation = _aspectAnnotation.firstAnnotationOf(element);
    final value = annotation == null
        ? null
        : ConstantReader(annotation).peek('value')?.stringValue.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final kind = RegExp(r'^(\w+)\s*\(').firstMatch(value)?[1];
    if (kind == 'percflow' ||
        kind == 'percflowbelow' ||
        kind == 'pertypewithin') {
      _fail(
        "@Aspect('$value') on ${element.name}: $kind is not supported by "
        'Spring AOP (nor here); use perthis(...) or pertarget(...).',
        element,
      );
    }
    if ((kind != 'perthis' && kind != 'pertarget') || !value.endsWith(')')) {
      _fail(
        "@Aspect('$value') on ${element.name}: the instantiation model must "
        "be perthis(pointcut) or pertarget(pointcut), or '' for a singleton.",
        element,
      );
    }
    if (_scopeOf(element) != 'prototype') {
      _fail(
        "Bean with name '${_decapitalize(element.name!)}' is a singleton, but "
        "aspect instantiation model is not singleton (@Aspect('$value')): add "
        "@Scope('prototype') to ${element.name}.",
        element,
      );
    }
    return value;
  }

  // Types written in `args(...)` (tested against the runtime argument, as
  // AspectJ does) and annotation names in `@args(...)` of [expressions],
  // looked up in [element]'s library; a bound name in `@args` contributes
  // the type of the advice parameter it binds.
  (Map<String, InterfaceType>, Set<String>) _argumentTypes(
    ClassElement element,
    List<String> expressions,
    List<AdviceModel> advice,
  ) {
    final types = <String, InterfaceType>{};
    final annotations = <String>{};
    final bound = {
      for (final item in advice)
        for (final parameter in item.parameters)
          if (parameter case BoundParameter(:final name, :final type))
            name: type,
    };
    for (final expression in expressions) {
      for (final match in _argsDesignator.allMatches(expression)) {
        final isAnnotation = match[1] == '@args';
        for (final raw in _splitTopLevel(match[2]!)) {
          final item = raw.trim().replaceAll('?', '');
          if (item.isEmpty || item == '..' || item.contains('*')) {
            continue;
          }
          final generic = item.indexOf('<');
          final name = (generic < 0 ? item : item.substring(0, generic))
              .split('.')
              .last;
          if (_bindingName.hasMatch(name) && !_lowercaseTypes.contains(name)) {
            if (bound[name] case final InterfaceType type when isAnnotation) {
              annotations.add(type.element.name!);
            }
            continue;
          }
          if (isAnnotation) {
            annotations.add(name);
          } else if (_lookUpType(element.library, name) case final type?) {
            types[name] = type;
          }
        }
      }
    }
    return (types, annotations);
  }

  // [text] split at commas outside `<...>`.
  static List<String> _splitTopLevel(String text) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      switch (text[i]) {
        case '<':
          depth++;
        case '>':
          depth--;
        case ',' when depth == 0:
          parts.add(text.substring(start, i));
          start = i + 1;
      }
    }
    parts.add(text.substring(start));
    return parts;
  }

  // The public class named [name] that [library] sees (its own or an
  // imported one), as a raw type (type arguments to bounds).
  static InterfaceType? _lookUpType(LibraryElement library, String name) {
    for (final candidate in [
      library,
      for (final fragment in library.fragments) ...fragment.importedLibraries,
    ]) {
      final found = candidate.exportNamespace.get2(name);
      if (found is InterfaceElement && found.isPublic) {
        return library.typeSystem.instantiateInterfaceToBounds(
          element: found,
          nullabilitySuffix: NullabilitySuffix.none,
        );
      }
    }
    return null;
  }

  // `@DeclareParents('Pattern+', defaultImpl: Impl) static I? field;` of
  // [element] (and its superclasses): proxies of matching beans implement
  // `I` and forward it to an `Impl()` (Spring's introductions).
  List<IntroductionModel> _introductions(ClassElement element) {
    final result = <IntroductionModel>[];
    for (final current in _classChain(element)) {
      for (final field in current.fields) {
        final annotation = _declareParents.firstAnnotationOf(field);
        if (annotation == null) {
          continue;
        }
        final reader = ConstantReader(annotation);
        final where = '@DeclareParents ${element.name}.${field.name}';
        if (!field.isStatic) {
          _fail('$where must be a static field (as in AspectJ).', field);
        }
        final declared = element.library.typeSystem.promoteToNonNull(
          field.type,
        );
        if (declared is! InterfaceType ||
            !_canImplement(declared) ||
            declared.element is! ClassElement &&
                declared.element is! MixinElement) {
          _fail(
            '$where: the field type ${field.type.getDisplayString()} is the '
            'introduced interface; it must be a public class or interface '
            'that another library can implement.',
            field,
          );
        }
        final defaultImpl = reader.read('defaultImpl').typeValue;
        final implElement = defaultImpl.element;
        if (defaultImpl is! InterfaceType ||
            implElement is! ClassElement ||
            implElement.isAbstract ||
            !implElement.isPublic ||
            !element.library.typeSystem.isSubtypeOf(defaultImpl, declared)) {
          _fail(
            '$where: defaultImpl ${defaultImpl.getDisplayString()} must be a '
            'public, non-abstract class implementing ${declared.element.name}.',
            field,
          );
        }
        final constructor = implElement.unnamedConstructor;
        if (constructor == null ||
            constructor.formalParameters.any((p) => p.isRequired)) {
          _fail(
            '$where: defaultImpl ${implElement.name} needs an unnamed '
            'constructor without required parameters (one instance is '
            'created per proxy).',
            field,
          );
        }
        result.add(
          IntroductionModel(
            aspectType: element.name!,
            typePattern: reader.read('value').stringValue,
            interfaceType: declared,
            defaultImpl: defaultImpl,
            members: _introducedMembers(declared, field),
          ),
        );
      }
    }
    return result;
  }

  // The members a proxy forwards for the introduced interface [type].
  List<ProxyMember> _introducedMembers(InterfaceType type, Element element) {
    final members = <ProxyMember>[];
    final seen = <String>{};
    final library = type.element.library;
    for (final current in [type, ...type.allSupertypes]) {
      if (current.isDartCoreObject) {
        continue;
      }
      final declaring = current.element.name!;
      for (final method in current.methods) {
        final name = method.name;
        if (method.isStatic ||
            name == null ||
            method.isOperator ||
            const {'toString', 'noSuchMethod'}.contains(name) ||
            !seen.add('m:$name')) {
          continue;
        }
        final implementation = type.lookUpMethod(name, library) ?? method;
        final member = _proxyMethod(implementation, method, declaring);
        if (member == null) {
          _fail(
            'The introduced method $declaring.$name cannot be forwarded by a '
            'proxy: a parameter default value is not a public constant, or a '
            'signature uses a private type.',
            element,
          );
        }
        members.add(member);
      }
      for (final getter in current.getters) {
        final name = getter.name;
        if (getter.isStatic ||
            name == null ||
            const {'hashCode', 'runtimeType'}.contains(name) ||
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
            annotations: const [],
          ),
        );
      }
      for (final setter in current.setters) {
        final name = setter.name;
        if (setter.isStatic || name == null || !seen.add('s:$name')) {
          continue;
        }
        final valueType = setter.formalParameters.single.type;
        members.add(
          ProxyMember(
            kind: ProxyMemberKind.setter,
            name: name,
            declaringType: declaring,
            returnType: valueType,
            typeParameters: const [],
            parameters: [
              ProxyParameter(
                name: 'value',
                type: valueType,
                isNamed: false,
                isRequired: true,
              ),
            ],
            annotations: const [],
          ),
        );
      }
    }
    return members;
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
      _requireDefinedType(
        type,
        parameter,
        'parameter $parameterName of $annotationName advice $name has',
      );
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
        final items = match[1]!.endsWith('args')
            ? match[2]!.split(',')
            : [match[2]!];
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
      return _withImplementations(_rejectCachedStreams(model));
    }
    if (constructor != null && (mode ?? proxyMode) == ProxyMode.all) {
      return _withImplementations(
        _rejectCachedStreams(
          _subclassProxyModel(targetType, className, constructor, failure),
        ),
      );
    }
    return _withImplementations(
      _rejectCachedStreams(_signatureOnlyModel(targetType, className, failure)),
    );
  }

  // Records, per member of [model], the class whose body runs when it is
  // inherited (for `within` / `@within`, which AspectJ matches against the
  // type declaring the code) and whether it is `@protected` (for
  // `execution(protected ...)`).
  ProxyModel? _withImplementations(ProxyModel? model) {
    if (model == null) {
      return null;
    }
    final target = model.targetType;
    final library = target.element.library;
    bool isProtected(Element? element) =>
        element != null &&
        (element.metadata.hasProtected ||
            (element is PropertyAccessorElement &&
                element.variable.metadata.hasProtected));
    for (final member in model.members) {
      final name = member.name;
      final ExecutableElement? implementation = switch (member.kind) {
        ProxyMemberKind.method => target.lookUpMethod(name, library),
        ProxyMemberKind.getter => target.lookUpGetter(name, library),
        ProxyMemberKind.setter => target.lookUpSetter(name, library),
      };
      member.isProtected =
          isProtected(implementation) ||
          [target, ...target.allSupertypes].any(
            (type) => isProtected(switch (member.kind) {
              ProxyMemberKind.method => type.getMethod(name),
              ProxyMemberKind.getter => type.getGetter(name),
              ProxyMemberKind.setter => type.getSetter(name),
            }),
          );
      final owner = implementation?.enclosingElement;
      if (owner is! InterfaceElement || owner == target.element) {
        continue;
      }
      member.implementingTypes = [
        owner.name!,
        for (final supertype in owner.allSupertypes)
          if (!supertype.isDartCoreObject) supertype.element.name!,
      ];
      member.implementingTypeAnnotations = _userAnnotations(owner);
    }
    return model;
  }

  // A subclass proxy (see `SubclassProxy`) of a component class that no
  // generated class can implement ([implementFailure]); when the class
  // cannot be extended either, only its signatures (like any type that
  // cannot be proxied): the context fails at startup, saying what to
  // change, only if advice matches the bean.
  ProxyModel? _subclassProxyModel(
    InterfaceType targetType,
    String className,
    ConstructorElement constructor,
    String implementFailure,
  ) {
    final element = targetType.element;
    final typeName = element.name!;
    ProxyModel unavailable(String problem, String change) =>
        _signatureOnlyModel(
          targetType,
          className,
          '$implementFailure A subclass proxy (the bean created as a '
          'generated subclass of $typeName) is not possible either, because '
          '$typeName $problem. $change, or add an interface with the advised '
          'methods and inject the bean by it.',
        );
    if (element is! ClassElement) {
      return unavailable('is not a class', 'Make it a class');
    }
    final modifier = element.isSealed
        ? 'sealed'
        : element.isFinal
        ? 'final'
        : element.isInterface
        ? 'interface'
        : null;
    if (modifier != null || !element.isExtendableOutside) {
      return unavailable(
        'cannot be extended${modifier == null ? '' : ' (it is $modifier)'}',
        modifier == null ? 'Make it extendable' : 'Remove `$modifier`',
      );
    }
    if (targetType.typeArguments.isNotEmpty) {
      return unavailable('is generic', 'Remove its type parameters');
    }
    if (constructor.isFactory) {
      return unavailable(
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
    // `@nonVirtual` (package:meta) on any declaration of the member.
    bool nonVirtual(
      String name,
      ExecutableElement? Function(InterfaceType) of,
    ) => [targetType, ...targetType.allSupertypes].any((type) {
      final declaration = of(type);
      return declaration != null &&
          (declaration.metadata.hasNonVirtual ||
              (declaration is PropertyAccessorElement &&
                  declaration.variable.metadata.hasNonVirtual));
    });
    const nonVirtualReason = 'it is @nonVirtual';
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
        if (nonVirtual(name, (type) => type.getMethod(name))) {
          skip('method', name, nonVirtualReason);
          continue;
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
        if (nonVirtual(name, (type) => type.getGetter(name))) {
          skip('getter', name, nonVirtualReason);
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
              ..._accessorAnnotations(implementation),
              if (getter != implementation) ..._accessorAnnotations(getter),
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
        if (nonVirtual(name, (type) => type.getSetter(name))) {
          skip('setter', name, nonVirtualReason);
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
            annotations: _accessorAnnotations(implementation),
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
            annotations: _accessorAnnotations(getter),
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
                ..._accessorAnnotations(implementation),
                if (getter != implementation) ..._accessorAnnotations(getter),
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
              annotations: _accessorAnnotations(implementation!),
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

  // Constructor selection, like Spring's AutowiredAnnotationBeanPostProcessor
  // and ConstructorResolver. Candidates, greediest first:
  // - a required `@Autowired` constructor (no other may be `@Autowired`);
  // - several `@Autowired(required: false)` constructors, plus the one
  //   callable without arguments: the generated code calls the first whose
  //   beans exist (see ModuleEmitter);
  // - otherwise the only public constructor (generative ones count first),
  //   the primary constructor (like Kotlin's in Spring) or the one callable
  //   without arguments; anything else is ambiguous and fails the build.
  List<ConstructorElement> _selectConstructors(ClassElement element) {
    final className = element.name!;
    String label(ConstructorElement constructor) =>
        _constructorName(constructor) == null
        ? className
        : '$className.${constructor.name}';
    final annotated = [
      for (final constructor in element.constructors)
        if (_autowired.hasAnnotationOf(constructor)) constructor,
    ];
    for (final constructor in annotated) {
      if (constructor.isPrivate) {
        _fail(
          '@Autowired constructor ${label(constructor)} must be public: the '
          'generated module cannot call a private constructor.',
          constructor,
        );
      }
    }
    final required = [
      for (final constructor in annotated)
        if (ConstantReader(_autowired.firstAnnotationOf(constructor))
                .peek('required')
                ?.boolValue ??
            true)
          constructor,
    ];
    if (required.isNotEmpty) {
      if (annotated.length > 1) {
        _fail(
          'Only one constructor may be @Autowired when one of them is '
          'required: ${label(required.first)} is required, but '
          '${annotated.map(label).join(', ')} are @Autowired. Keep one, or '
          'mark each candidate @Autowired(required: false) to use the one '
          'with the most parameters whose beans exist.',
          annotated.firstWhere((c) => c != required.first),
        );
      }
      return required;
    }
    final noArgument = _noArgumentConstructor(element);
    if (annotated.isNotEmpty) {
      final candidates = [
        ...annotated,
        if (noArgument != null && !annotated.contains(noArgument)) noArgument,
      ];
      // Stable: declaration order among constructors of the same size.
      final order = [...candidates];
      return candidates..sort((a, b) {
        final bySize = b.formalParameters.length.compareTo(
          a.formalParameters.length,
        );
        return bySize != 0 ? bySize : order.indexOf(a) - order.indexOf(b);
      });
    }
    final generative = [
      for (final constructor in element.constructors)
        if (constructor.isPublic && !constructor.isFactory) constructor,
    ];
    final candidates = generative.isNotEmpty
        ? generative
        : [
            for (final constructor in element.constructors)
              if (constructor.isPublic) constructor,
          ];
    if (candidates.isEmpty) {
      _fail(
        'Bean class $className has no public constructor: the generated '
        'module cannot create it. Add a public constructor.',
        element,
      );
    }
    if (candidates.length == 1) {
      return candidates;
    }
    if (candidates.where((c) => c.isPrimary).firstOrNull case final primary?) {
      return [primary];
    }
    if (noArgument != null) {
      return [noArgument];
    }
    _fail(
      'Cannot choose a constructor for $className: it has several public '
      'constructors (${candidates.map(label).join(', ')}), neither a '
      'primary one nor a single one callable without arguments. Mark the '
      'one to use with '
      '@Autowired(), or several with @Autowired(required: false).',
      element,
    );
  }

  // Spring's default constructor: here the public one callable without
  // arguments (no required parameters), generative ones first; `null` when
  // there is none or several (`A.one()` and `A.two()`).
  ConstructorElement? _noArgumentConstructor(ClassElement element) {
    final callable = [
      for (final constructor in element.constructors)
        if (constructor.isPublic &&
            constructor.formalParameters.every((p) => !p.isRequired))
          constructor,
    ];
    final generative = [
      for (final constructor in callable)
        if (!constructor.isFactory) constructor,
    ];
    final preferred = generative.isNotEmpty ? generative : callable;
    return preferred.length == 1 ? preferred.single : null;
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
          _fail(
            'Injected field $name must be public: the generated code is '
            'another library and cannot reach a private member; inject it '
            'through a constructor parameter (`this.$name` keeps the field '
            'private) or make it public.',
            field,
          );
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
          _fail(
            'Injected setter $name must be public: the generated code is '
            'another library and cannot reach a private member; use a '
            'constructor parameter or a public setter.',
            setter,
          );
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
  bool _isInjected(Element element) {
    if (_resource.hasAnnotationOf(element)) {
      if (_value.hasAnnotationOf(element) ||
          _autowired.hasAnnotationOf(element)) {
        _fail(
          '@Resource on ${_describe(element)} cannot be combined with '
          '@Autowired, @Inject or @Value.',
          element,
        );
      }
      return true;
    }
    if (_value.hasAnnotationOf(element)) {
      return true;
    }
    if (!_autowired.hasAnnotationOf(element)) {
      return false;
    }
    _rejectOptionalAutowired(element);
    return true;
  }

  // `@Autowired(required: false)` chooses among constructors only; on a
  // field, setter or method a nullable type says the same in Dart.
  void _rejectOptionalAutowired(Element element) {
    final required = ConstantReader(_autowired.firstAnnotationOf(element))
        .peek('required')
        ?.boolValue;
    if (required == false) {
      _fail(
        '@Autowired(required: false) on ${_describe(element)}: `required` '
        'only chooses among constructors. Make the type nullable (`T?`) '
        'for an optional dependency.',
        element,
      );
    }
  }

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
        _rejectOptionalAutowired(method);
        final name = _requireName(method);
        if (method.isPrivate) {
          _fail(
            '@Autowired method $name must be public: the generated code is '
            'another library and cannot call a private member.',
            method,
          );
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

  /// The element whose `@Value` / `@Qualifier` / `@Named` / `@Lazy`
  /// annotations apply to the injection point [element]: a super parameter
  /// (`B(super.url)`) without any of them carries those of the super
  /// constructor's parameter (`A(@Value('\${url}') this.url)`).
  Element _injectionAnnotationSource(Element element) {
    var current = element;
    while (current is SuperFormalParameterElement &&
        !_value.hasAnnotationOf(current) &&
        !_qualifier.hasAnnotationOf(current) &&
        !_named.hasAnnotationOf(current) &&
        !_lazy.hasAnnotationOf(current)) {
      final parameter = current.superConstructorParameter;
      if (parameter == null) {
        break;
      }
      current = parameter;
    }
    return current;
  }

  // A nullable declared type makes the point optional. `@Value` wins over
  // everything else; otherwise the kind follows from the type (see
  // `_pointKind`). The element name is kept for single beans so the
  // runtime can fall back to matching it against bean names.
  InjectionPoint _injectionPoint(Element element, DartType type) {
    _requireDefinedType(type, element, '${_describe(element)} has');
    final annotated = _injectionAnnotationSource(element);
    final valueAnnotation = _value.firstAnnotationOf(annotated);
    final optional = type.nullabilitySuffix == NullabilitySuffix.question;
    _requirePublicType(type, element, '${_describe(element)} has');
    if (type case InterfaceType(element: ExtensionTypeElement(:final name))) {
      _fail(
        'Cannot inject extension type $name into ${_describe(element)}: '
        'extension types are erased at runtime, so the container cannot '
        'tell them from their representation type. Use a class instead.',
        element,
      );
    }
    if (valueAnnotation != null) {
      if (_isLazy(annotated) ?? false) {
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
    // A function or record bean, injected by its exact type (single beans
    // only, like any other value type).
    final library = element.library!;
    final nonNull = library.typeSystem.promoteToNonNull(type);
    if (nonNull is FunctionType || nonNull is RecordType) {
      if ((_isLazy(annotated) ?? false) ||
          _resource.firstAnnotationOf(element) != null) {
        _fail(
          '${_describe(element)}: a ${nonNull.getDisplayString()} can only be '
          'injected directly (not @Lazy or @Resource).',
          element,
        );
      }
      return InjectionPoint(
        kind: PointKind.single,
        type: nonNull is FunctionType
            ? library.typeProvider.functionType
            : library.typeProvider.recordType,
        exactType: nonNull,
        optional: optional,
        qualifier: _qualifierOf(annotated),
        name: element.name,
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
    final qualifier = _qualifierOf(annotated);
    final (kind, beanType) = _pointKind(interfaceType, element);
    if (_resource.firstAnnotationOf(element) case final resource?) {
      return _resourcePoint(
        element,
        resource,
        kind,
        beanType,
        optional: optional,
      );
    }
    final lazy = _isLazy(annotated) ?? false;
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

  // JSR-250 `@Resource` on a field or setter: the bean named like the
  // member (falling back to the type) or as `name:` says.
  InjectionPoint _resourcePoint(
    Element element,
    DartObject resource,
    PointKind kind,
    InterfaceType type, {
    required bool optional,
  }) {
    final what = '@Resource on ${_describe(element)}';
    if (element is FormalParameterElement) {
      _fail(
        '$what: @Resource applies to fields and setters only (like '
        'Spring); use @Autowired / @Qualifier on parameters.',
        element,
      );
    }
    if (kind != PointKind.single) {
      _fail(
        '$what: @Resource injects one bean by name; use @Autowired for '
        'collections and providers.',
        element,
      );
    }
    if (_qualifier.hasAnnotationOf(element) ||
        _named.hasAnnotationOf(element) ||
        _lazy.hasAnnotationOf(element)) {
      _fail(
        '$what: @Resource selects the bean by name; @Qualifier, @Named and '
        '@Lazy do not apply.',
        element,
      );
    }
    final explicit = ConstantReader(resource).peek('name')?.stringValue;
    return InjectionPoint(
      kind: PointKind.resource,
      type: type,
      optional: optional,
      name: explicit == null
          ? _requireName(element)
          : _checkBeanName(explicit, 'The name of $what', element),
      fallbackToType: explicit == null,
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
  ProxyModel _lazyProxy(InterfaceType type, Element element, {String? what}) {
    final typeName = type.element.name!;
    final subject = what ?? '@Lazy on ${element.displayName}';
    final kind = what == null ? 'lazy proxy' : 'proxy';
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
        '$subject: generic types ($typeName<...>) cannot be '
        '${what == null ? 'injected lazily' : 'proxied'} yet. '
        '$hint',
        element,
      );
    }
    if (type.element.library.isInSdk || !_canImplement(type)) {
      _fail(
        '$subject: the $kind must implement '
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
        '$subject: no $kind can be generated: '
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
    // ObjectFactory<T> and JSR-330 Provider<T> points receive the same
    // provider (Spring's DependencyObjectProvider serves both).
    if (_objectProvider.isExactlyType(type) ||
        _objectFactory.isExactlyType(type) ||
        _provider.isExactlyType(type)) {
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

  // `@Scope(proxyMode:)` other than `no` on a custom or prototype scope:
  // the lazy proxy class of [type] (shared with `@Lazy` points), which
  // `BeanDefinition.scopedProxy` wraps around the scope lookup.
  ProxyModel? _scopedProxyOf(Element element, InterfaceType type) {
    final annotation = _scope.firstAnnotationOf(element);
    final mode = annotation == null
        ? null
        : ConstantReader(annotation)
              .peek('proxyMode')
              ?.revive()
              .accessor
              .split('.')
              .last;
    if (mode == null || mode == 'no') {
      return null;
    }
    final what =
        '@Scope(proxyMode: ScopedProxyMode.$mode) on ${_describe(element)}';
    if (_scopeOf(element) == 'singleton') {
      _fail(
        '$what: a singleton needs no scoped proxy; give the scope name '
        "(`@Scope('session', proxyMode: ...)`).",
        element,
      );
    }
    if (_factoryObjectTypes(type) != null) {
      _fail('$what: a FactoryBean cannot have a scoped proxy.', element);
    }
    return _lazyProxy(type, element, what: what);
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

  // Three kinds of conditions: `@Profile`, `@Conditional([Type])` (or a
  // subclass of either) and any const annotation whose class implements
  // `Condition` (re-emitted as a const expression, see `ModuleEmitter`).
  List<ConditionModel> _conditions(Element element) {
    final result = <ConditionModel>[];
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (value == null || type is! InterfaceType) {
        continue;
      }
      // A subclass (`class Dev extends Profile`) counts like the base
      // annotation, as Spring's meta-annotations do.
      if (_profile.isAssignableFromType(type)) {
        result.add(
          ProfileConditionModel([
            for (final p in ConstantReader(value).read('value').listValue)
              p.toStringValue()!,
          ]),
        );
      } else if (_conditional.isAssignableFromType(type)) {
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

  // A registrar or selector of `@Import`: created at runtime with its
  // no-argument constructor when the importing class is registered (once
  // per module; the first importer's conditions win).
  void _addRegistrar(
    ClassElement imported,
    ClassElement importer,
    List<ConditionModel> conditions,
  ) {
    final name = _requireName(imported);
    if (!module.markScanned('${imported.library.uri}#$name')) {
      return;
    }
    final constructor = imported.unnamedConstructor;
    if (imported.isPrivate ||
        imported.isAbstract ||
        imported.typeParameters.isNotEmpty ||
        constructor == null ||
        constructor.isPrivate ||
        constructor.formalParameters.any((p) => p.isRequired)) {
      _fail(
        '@Import of $name: a BeanRegistrar, ImportSelector or '
        'ImportBeanDefinitionRegistrar must be a public, non-abstract, '
        'non-generic class with a no-argument constructor.',
        importer,
      );
    }
    module.registrars.add(
      RegistrarModel(imported.thisType, importer, conditions: conditions),
    );
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
          encoding: reader.peek('encoding')?.stringValue,
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
  // The type a listener's results are published as: the return type, or
  // the element type of an Iterable; `null` for `Object`, `dynamic`,
  // private or generic types (published as `Object`).
  static InterfaceType? _listenerResultType(DartType returnType) {
    var type = returnType;
    if (type is InterfaceType) {
      final iterable = type.isDartCoreIterable
          ? type
          : type.allSupertypes.where((s) => s.isDartCoreIterable).firstOrNull;
      if (iterable != null) {
        type = iterable.typeArguments.single;
      }
    }
    if (type is! InterfaceType ||
        type.isDartCoreObject ||
        type.isDartCoreNull ||
        type.element.name == null ||
        type.element.name!.startsWith('_') ||
        type.typeArguments.any((a) => a is! InterfaceType)) {
      return null;
    }
    // `R?` is published as `R` (null results are not published).
    return type.element.instantiate(
      typeArguments: type.typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

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
          if (_async.hasAnnotationOf(method)) {
            _fail(
              '@Async is supported on @EventListener methods only: '
              '${_requireName(method)} would run synchronously.',
              method,
            );
          }
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
    final asyncAnnotation = _async.firstAnnotationOf(method);
    final conditionValue = annotation.peek('condition');
    final condition = conditionValue?.objectValue.toFunctionValue();
    if (conditionValue != null && condition == null) {
      _fail('@EventListener condition must be a function.', method);
    }
    final returnsValue =
        returnType is! VoidType &&
        !returnType.isDartAsyncFuture &&
        !returnType.isDartAsyncFutureOr;
    return ListenerModel(
      id: annotation.peek('id')?.stringValue ?? '$className.$methodName',
      methodName: methodName,
      eventTypes: classes.isEmpty ? [parameterType!] : classes,
      parameterType: parameterType,
      returnsValue: returnsValue,
      resultType: returnsValue ? _listenerResultType(returnType) : null,
      order: _orderOf(method),
      condition: condition,
      async: asyncAnnotation != null,
      asyncExecutor: asyncAnnotation == null
          ? null
          : ConstantReader(asyncAnnotation).peek('value')?.stringValue,
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
  // An explicit bean name or alias: Spring's registry rejects empty and
  // blank names; surrounding whitespace is a typo no lookup would match.
  String _checkBeanName(
    String name,
    String what,
    Element element, {
    String? orDefault,
  }) {
    final remove = orDefault == null
        ? 'remove it'
        : "remove it to use the default name '$orDefault'";
    if (name.trim().isEmpty) {
      _fail(
        "$what is ${name.isEmpty ? 'empty' : 'blank'}: give a name, or "
        '$remove.',
        element,
      );
    }
    if (name.trim() != name) {
      _fail(
        "$what '$name' starts or ends with whitespace: use '${name.trim()}'.",
        element,
      );
    }
    return name;
  }

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
  /// Public types of the scanned libraries and of the runtime, by name:
  /// where to import a type from when the analyzer cannot resolve it (a
  /// missing import). Filled by the builder before scanning.
  final Map<String, Uri> knownTypes = {};

  // A type the analyzer could not resolve (`InvalidType`, usually a
  // missing import) fails with its name as written and, when a scanned
  // library or the runtime declares it, the import to add.
  void _requireDefinedType(DartType type, Element element, String use) {
    if (!_mentionsInvalidType(type)) {
      return;
    }
    // A setter's type is written in its parameter.
    final name = _writtenTypeName(switch (element) {
      SetterElement(formalParameters: [final parameter]) => parameter,
      _ => element,
    });
    final source = knownTypes[name];
    final where = element.library?.uri;
    _fail(
      '${_capitalize(use)} the type '
      '${name ?? type.getDisplayString()}, which is not defined in $where '
      '(a missing import or a typo)'
      '${source == null ? '' : ": add import '$source';"}.',
      element,
    );
  }

  static bool _mentionsInvalidType(DartType type) => switch (type) {
    InvalidType() => true,
    InterfaceType() => type.typeArguments.any(_mentionsInvalidType),
    FunctionType() =>
      _mentionsInvalidType(type.returnType) ||
          type.formalParameters.any((p) => _mentionsInvalidType(p.type)),
    RecordType() =>
      type.positionalFields.any((f) => _mentionsInvalidType(f.type)) ||
          type.namedFields.any((f) => _mentionsInvalidType(f.type)),
    _ => false,
  };

  // The first type name written in the declaration of [element] (a
  // parameter, field or method; for `this.x` the field), read from the
  // source before the declared name: the identifier the analyzer could not
  // resolve when it is the only one.
  static String? _writtenTypeName(Element element) {
    var declaration = element;
    if (declaration is FieldFormalParameterElement) {
      declaration = declaration.field ?? declaration;
    }
    final fragment = declaration.firstFragment;
    final offset = fragment.nameOffset;
    final unit = fragment.libraryFragment;
    if (offset == null || unit == null) {
      return null;
    }
    final text = unit.source.contents.data;
    // Back from the name to the start of the declaration.
    var start = offset;
    var depth = 0;
    while (start > 0) {
      final char = text[start - 1];
      if (char == '>' || char == ')') {
        depth++;
      } else if (char == '<' || char == '(') {
        if (depth == 0) {
          break;
        }
        depth--;
      } else if (depth == 0 && ',;{}['.contains(char)) {
        break;
      }
      start--;
    }
    final written = text
        .substring(start, offset)
        .replaceAll(RegExp(r'@\w+(\.\w+)*(\([^)]*\))?'), ' ')
        .replaceAll(
          RegExp(r'\b(required|final|covariant|late|static|const|var|this)\b'),
          ' ',
        );
    // The first name the library cannot resolve (`Clock` in
    // `List<Clock>`), else the first name written.
    final typeParameters = {
      for (
        Element? current = declaration;
        current != null;
        current = current.enclosingElement
      )
        if (current case TypeParameterizedElement(:final typeParameters))
          for (final typeParameter in typeParameters) ?typeParameter.name,
    };
    final names = [
      for (final match in RegExp(r'[A-Za-z_$][\w$]*').allMatches(written))
        if (!const {'Function', 'dynamic', 'void'}.contains(match[0]))
          match[0]!,
    ];
    return names
            .where(
              (name) =>
                  !typeParameters.contains(name) &&
                  unit.scope.lookup(name).getter == null,
            )
            .firstOrNull ??
        names.firstOrNull;
  }

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
