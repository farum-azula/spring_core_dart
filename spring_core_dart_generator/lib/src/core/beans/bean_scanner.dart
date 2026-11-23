import 'package:analyzer/dart/ast/ast.dart'
    show
        AstNode,
        BlockFunctionBody,
        Expression,
        ExpressionFunctionBody,
        FunctionDeclarationStatement,
        FunctionExpression,
        InstanceCreationExpression,
        MethodDeclaration,
        NamedArgument,
        ReturnStatement,
        StringLiteral;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart' show log;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/annotation_target.dart';
import 'package:spring_core_dart_generator/src/core/beans/annotation_values.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/core_placements.dart';
import 'package:spring_core_dart_generator/src/core/beans/log_scanning.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/introspection/constraint_checker.dart';
import 'package:spring_core_dart_generator/src/core/introspection/introspection_model.dart';
import 'package:spring_core_dart_generator/src/core/introspection/introspection_scanner.dart';

part '../aop/advisor_pointcuts.dart';
part '../builder/module_scan.dart';
part 'bean_type_inference.dart';
part 'configuration_scanning.dart';
part 'introspection_needs.dart';
part 'lookup_scanning.dart';

// Annotations are matched by name in `package:spring_core_dart` (the
// generator depends on the runtime only for its pointcut parser, see
// aop_analysis.dart).
TypeChecker _spring(String name) =>
    TypeChecker.typeNamedLiterally(name, inPackage: 'spring_core_dart');

final TypeChecker _component = _spring('Component');
final TypeChecker _configuration = _spring('Configuration');
final TypeChecker _named = _spring('Named');
final TypeChecker _bean = _spring('Bean');
final TypeChecker _scope = _spring('Scope');
final TypeChecker _lazy = _spring('Lazy');
final TypeChecker _primary = _spring('Primary');
final TypeChecker _fallback = _spring('Fallback');
final TypeChecker _qualifier = _spring('Qualifier');
final TypeChecker _dependsOn = _spring('DependsOn');
final TypeChecker _description = _spring('Description');
final TypeChecker _order = _spring('Order');
final TypeChecker _autowired = _spring('Autowired');
final TypeChecker _lookup = _spring('Lookup');
final TypeChecker _value = _spring('Value');
final TypeChecker _postConstruct = _spring('PostConstruct');
final TypeChecker _preDestroy = _spring('PreDestroy');
final TypeChecker _profile = _spring('Profile');
final TypeChecker _conditional = _spring('Conditional');
final TypeChecker _condition = _spring('Condition');
final TypeChecker _import = _spring('Import');
final TypeChecker _async = _spring('Async');
// `@Import`ed classes the runtime instantiates instead of scanning.
final List<TypeChecker> _importRegistrars = [
  _spring('BeanRegistrar'),
  _spring('ImportSelector'),
  _spring('ImportBeanDefinitionRegistrar'),
];
final TypeChecker _propertySource = _spring('PropertySource');
final TypeChecker _configurable = _spring('Configurable');
final TypeChecker _eventListener = _spring('EventListener');
final TypeChecker _beanMethodAnnotation = _spring('BeanMethodAnnotation');
final TypeChecker _proxyTargetClass = _spring('ProxyTargetClass');

// `@ConfigurationProperties` from spring_core_dart (matched by URL, so the
// generator does not depend on that package): constructor binding.
const _configurationProperties = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/property_annotations.dart#ConfigurationProperties',
);
final TypeChecker _interfaceProxy = _spring('InterfaceProxy');
final TypeChecker _factoryBean = _spring('FactoryBean');
final TypeChecker _applicationListener = _spring('ApplicationListener');
final TypeChecker _objectProvider = _spring('ObjectProvider');
final TypeChecker _objectFactory = _spring('ObjectFactory');
final TypeChecker _provider = _spring('Provider');
final TypeChecker _resource = _spring('Resource');

final TypeChecker _aspectAnnotation = _spring('Aspect');
final TypeChecker _constraint = _spring('Constraint');
final TypeChecker _valid = _spring('Valid');
final TypeChecker _pointcutAnnotation = _spring('Pointcut');
final Map<String, TypeChecker> _adviceAnnotations = {
  'around': _spring('Around'),
  'before': _spring('Before'),
  'after': _spring('After'),
  'afterReturning': _spring('AfterReturning'),
  'afterThrowing': _spring('AfterThrowing'),
};
final TypeChecker _declareParents = _spring('DeclareParents');
final TypeChecker _advisor = _spring('Advisor');
final TypeChecker _joinPoint = _spring('JoinPoint');
final TypeChecker _proceedingJoinPoint = _spring('ProceedingJoinPoint');

/// The members every generated AOP proxy declares (from `Advised`, and the
/// invoker of `AdvisedWrapper` / `AdvisedSubclass`). A proxied class must
/// not declare a member with one of these names, since the proxy's member
/// would replace it.
const _advisedMembers = {
  'aopTarget',
  'aopAdvisors',
  'aopInvoker',
  'addAdvisor',
  'removeAdvisor',
  'addAdvice',
  'removeAdvice',
};

String _reservedMessage(String? type, String member) =>
    '$type.$member has the name of a member every proxy declares '
    '(Advised.$member). Rename it.';

/// Infrastructure types whose beans never get a proxy: they set up the
/// container and AOP itself, and advising them could make AOP advise its
/// own machinery.
///
/// Like Spring's `AbstractAutoProxyCreator.isInfrastructureClass`, which
/// skips `Advice`, `Pointcut`, `Advisor` and `AopInfrastructureBean`.
final List<TypeChecker> _notProxied = [
  _spring('BeanPostProcessor'),
  _spring('BeanFactoryPostProcessor'),
  _spring('Advisor'),
  _spring('FactoryBean'),
];

/// Which beans get a generated AOP proxy class, the class that runs advice
/// (`@Around`, `@Transactional`, `@Cacheable`...) around the bean's
/// methods.
///
/// Dart cannot create classes at runtime, so every proxy a bean might need
/// is generated at build time, and a bean without matching advice is used
/// unwrapped. More proxies mean more generated code. Applications choose a
/// mode with the `aop_proxies` build option; the default, [all], suits
/// most of them.
///
/// A proxy can only be generated for a type that another library may
/// `implements`: public, not sealed, final or base, without private
/// members or operators, with member types and default values the
/// generated code can write.
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
  /// A proxy for every bean whose class, or one of its interfaces, can be
  /// implemented. The default.
  all,

  /// Proxies only through the bean's abstract supertypes, like JDK dynamic
  /// proxies; a bean without one gets no proxy.
  interfaces,

  /// No proxies: AOP cannot advise the beans of this module.
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

/// Annotations of the container itself that are not kept in the runtime
/// annotation metadata of members (introspection, proxies): they only
/// configure injection, and advice or user code has no use for them.
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
  'EqualsAndHashCode',
  'ToString',
  'CopyWith',
  'Builder',
};

/// Recognises `@ComponentScan`, the annotation that marks a scan root: the
/// top-level variable whose file's directory is scanned for beans.
///
/// It matches `@ComponentScan` of `package:spring_core_dart` by name, like
/// every annotation the scanner reads.
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
final TypeChecker componentScanChecker = _spring('ComponentScan');

/// The error thrown when a build finds several independent problems.
///
/// Fixing errors one build at a time is slow, so the scanner keeps going
/// after a bad declaration and reports all of them at once, each with its
/// message, library URI and location. A build with a single problem
/// throws that `InvalidGenerationSource` itself.
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
  /// Wraps [errors], which should hold at least two.
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

/// The text of [error] for a [BuildErrors] list: its message and location,
/// plus the library URI of its element when the text lacks it (when no
/// source span could be computed).
String describeBuildError(InvalidGenerationSource error) {
  final text = error.toString();
  final uri = error.element?.library?.uri;
  return uri == null || text.contains('$uri') ? text : '$text\n($uri)';
}

/// Reads the options of the `@ComponentScan` [annotation] on [element]:
/// `includeFilters`, `excludeFilters`, `useDefaultFilters` and `lazyInit`.
///
/// The filters are evaluated at build time, so they must be read from the
/// annotation as data. A filter without the argument its type uses, or
/// with an invalid regular expression, fails the build.
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

/// Reads the annotated declarations of the scanned libraries and turns
/// them into the models the emitter writes.
///
/// This is the part of the generator that understands the annotations. It
/// fills a [ModuleModel] with one [BeanModel] per component class and
/// `@Bean` method (with its injection points, conditions, lifecycle
/// methods, listeners and proxy), plus `@Configurable`, `@Introspected`,
/// `@PropertySource` and `@Log` metadata; the packages' parts
/// ([generations]) read their own annotations along. The builder creates
/// one scanner per output file.
///
/// It also validates every declaration, because a mistake the scanner lets
/// through would show up as generated code that does not compile. A
/// problem throws an `InvalidGenerationSource` pointing at the element:
/// private or abstract bean classes, ambiguous constructors, async
/// lifecycle methods, nullable collection elements, and more. The scan
/// goes on after an error, so one build reports every independent problem
/// (see [collectErrors] and [throwErrors]).
///
/// ```dart
/// // Input:
/// @Configuration(proxyBeanMethods: false)
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
/// // Registered under the type the method returns, and the declared one:
/// BeanDefinition<SystemClock>(
///   name: r'clock',
///   types: const [SystemClock, Clock],
///   factoryBeanName: r'config',
///   factoryMethodName: r'clock',
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
  /// [proxyMode] decides which beans get a proxy model (default
  /// [ProxyMode.all]). [scan] holds the `@ComponentScan` filters and
  /// `lazyInit`; the default accepts every component.
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
    this.generations = const [],
  });

  /// The model being filled; the emitter writes it once the scan is done.
  final ModuleModel module;

  /// The packages' parts of the build, asked in turn about every class and
  /// mixin [scanLibrary] reads, about the classes whose initial values they
  /// read, and about the mixins of every proxy.
  final List<PackageGeneration> generations;

  // What the parts' scan hooks get: the module, this scanner's errors, and
  // its readings of a class.
  late final _packageScan = ModuleScan(this);

  /// Where the annotations of the parts ([PackageGeneration.placements])
  /// and of the core may go, the parts' asked first.
  late final placements = AnnotationPlacements([
    _declaredTargets,
    for (final generation in generations) ...generation.placements,
    ...corePlacements,
  ]);

  // `@Target` of the annotation classes: asked before every other
  // placement, and alone on what only it reads.
  final _declaredTargets = DeclaredTargetPlacement();

  /// Whether an annotation class gives a value by a getter: reading it
  /// would crash, so no library is scanned ([checkAnnotationValues]).
  bool get hasUnreadableValues => _hasUnreadableValues;
  bool _hasUnreadableValues = false;

  // The annotations whose class must be what their placement asks
  // (a bean, a controller), known once every library is scanned.
  final _ownerChecks =
      <
        (AnnotationSite, AnnotationPlacement, PlacementOwner, InterfaceElement)
      >[];

  /// The classes the package's public libraries (`lib/*.dart`) export: a
  /// `@Bean` method of another package may return them.
  final exportedClasses = <InterfaceElement>{};

  // What is wrong with an annotation if the abstract class around it turns
  // out to be a bean whose implementation the build generates.
  final _generatedBeanChecks = <(AnnotationSite, String, ClassElement)>[];

  // The classes of the scanned libraries.
  final _scannedClasses = <ClassElement>[];

  // The classes scanned as beans, also those whose scan failed (their
  // problem is reported already).
  final _beanClassesScanned = <ClassElement>[];

  /// Which beans get a [ProxyModel] (build option `aop_proxies`).
  final ProxyMode proxyMode;

  /// The `@ComponentScan` filters and `lazyInit` of the module, which
  /// decide which classes become beans and whether they start lazily.
  final ComponentScanModel scan;

  /// The introspection of the module's classes: the scanner hands it each
  /// library and class it reads, and tells it what the beans do with the
  /// classes of their methods ([IntrospectionRequests]).
  late final introspection = IntrospectionScanner(
    module,
    _packageScan,
    generations: generations,
  );

  // Resolved `@Bean` method declarations by `library#Class.method`, for
  // the bean type inferred from the method body (bean_type_inference.dart).
  final _beanMethodDeclarations = <String, MethodDeclaration>{};

  /// Resolves the bodies of the `@Bean` methods of [library]'s classes
  /// and of the classes they `@Import`, so that [scanLibrary] can register
  /// each bean under the type its method really returns.
  ///
  /// Call it before [scanLibrary]; [astNodeFor] is the build resolver's
  /// `astNodeFor(fragment, resolve: true)`. Without this step, beans are
  /// registered under the declared return type only.
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

  /// Adds to [module] everything [library] declares: beans, configurables,
  /// interface proxies and `@Log` classes, what the packages' parts
  /// ([generations]) read of its classes and mixins, and what
  /// [introspection] reads of them (its `@Introspected` classes).
  ///
  /// A class annotated with `@Component` (or a stereotype such as
  /// `@Service`, `@Repository`, `@Configuration`, `@Named`) that the
  /// `@ComponentScan` filters accept is passed to [scanClass]. An abstract
  /// class is skipped unless it has `@Lookup` methods, as in Spring.
  /// `@Configurable` and `@Introspected` classes are recorded too, and a
  /// class may be several of these at once. `@Component` on a mixin, enum,
  /// extension or extension type, and `@Bean` on a top-level function, fail
  /// the build instead of being ignored.
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
    if (_hasUnreadableValues) {
      return;
    }
    _checkPlacements(library);
    collectErrors(() => introspection.scanLibrary(library));
    for (final element in library.classes) {
      _scannedClasses.add(element);
      if (element.isPublic) {
        module.classes.add(element);
      }
      collectErrors(() {
        if (_configurable.hasAnnotationOf(element)) {
          _scanConfigurable(element);
        }
        // Introspection finds the `@Introspected` classes itself.
        introspection.scanClass(element);
        // What the packages' parts read of the class before the core
        // decides which bean it is (the data starter's entities).
        for (final generation in generations) {
          generation.describeClass(element, _packageScan);
        }
        if (_interfaceProxyPrimary(element) case final primary?) {
          _scanInterfaceProxy(element, primary: primary);
          return;
        }
        // A class whose bean a package's part makes itself (the data
        // starter's repositories).
        for (final generation in generations) {
          if (generation.claimClass(element, _packageScan)) {
            return;
          }
        }
        final annotation = _component.firstAnnotationOf(element);
        // Like Spring's scan (isCandidateComponent), an abstract class is
        // no candidate unless it has @Lookup methods. Spring skips it
        // without a word; a stereotype on it is a mistake the build names.
        if (element.isAbstract && !hasLookupMethods(element)) {
          if (annotation?.type?.element?.name case final stereotype?) {
            _fail(
              '@$stereotype on the ${_classKind(element)} class '
              '${element.name}: it cannot be created, so it is no bean and '
              'every annotation on it is lost. Make it concrete, put the '
              'annotation on a subclass, or declare a @Lookup method.',
              element,
            );
          }
          return;
        }
        if (scan.isCandidate(element, isComponent: annotation != null)) {
          scanClass(element, annotation: annotation);
        }
      });
      // The starters' annotations: Flutter's widgets, the navigation's
      // screens, the signals.
      for (final generation in generations) {
        generation.scanClass(element, _packageScan);
      }
      collectErrors(() => scanLog(element, module));
    }
    for (final mixin in library.mixins) {
      for (final generation in generations) {
        generation.scanMixin(mixin, _packageScan);
      }
    }
    _rejectUnsupportedTargets(library);
    _rejectTargetClassOutsideBeans(library);
  }

  /// Adds the aspects and advisor beans of [library], a library of another
  /// module of the application, to [into]; nothing is added to [module].
  ///
  /// The `@SpringBootApplication` output uses it to learn every pointcut
  /// of the application before it prunes proxies. A class the scanner
  /// cannot read marks [into] as unknown, which turns pruning off; that
  /// module's own build reports the error.
  ///
  /// ```dart
  /// // The libraries of a nested @ComponentScan module.
  /// final foreign = ForeignAdvice();
  /// scanner.collectAdvice(nestedLibrary, foreign);
  /// ```
  void collectAdvice(LibraryElement library, ForeignAdvice into) {
    final seen = <ClassElement>{};
    for (final element in library.classes) {
      try {
        _collectClassAdvice(element, into, seen);
      } on InvalidGenerationSource {
        into.unknown = true;
      }
    }
  }

  // The advice of [element] and of the classes it `@Import`s, for
  // [collectAdvice].
  void _collectClassAdvice(
    ClassElement element,
    ForeignAdvice into,
    Set<ClassElement> seen,
  ) {
    if (!seen.add(element)) {
      return;
    }
    final source = '${element.library.uri}#${element.name}';
    if (_aspectModel(element) case final aspect?) {
      into.aspects.add((element.name!, aspect));
      into.knownSources.add(source);
    }
    if (!_component.hasAnnotationOf(element)) {
      return;
    }
    if (_advisor.isAssignableFrom(element)) {
      into.advisors = true;
    }
    for (final (method, _) in _beanMethods(element.thisType)) {
      final returnType = method.returnType;
      // `@Bean AuditAspect audit() => AuditAspect();`
      if (returnType case InterfaceType(element: final ClassElement returned)
          when returned != element) {
        if (_aspectModel(returned) case final aspect?) {
          into.aspects.add((returned.name!, aspect));
          into.knownSources.add('$source.${method.name}');
        }
      }
      if (!_advisor.isAssignableFromType(returnType)) {
        continue;
      }
      into.knownSources.add('$source.${method.name}');
      switch (_advisorPointcutOf(method)) {
        case AdvisorPointcut(:final expression?):
          into.expressions.add(expression);
        case AdvisorPointcut(:final annotations):
          into.advisedAnnotations.addAll(annotations);
        case null:
          into.advisors = true;
      }
    }
    // An imported configuration class is part of the module. Advice a
    // registrar or selector registers in code is not read: the pruned
    // proxies carry the advisors the build knew, and the startup fails when
    // another one turns up.
    for (final imported in _importedClasses(element)) {
      if (!_importRegistrars.any((c) => c.isAssignableFrom(imported))) {
        _collectClassAdvice(imported, into, seen);
      }
    }
  }

  /// The validation errors of the declarations scanned so far, in scan
  /// order; [throwErrors] reports them.
  final errors = <InvalidGenerationSource>[];

  /// Runs [action], adding an `InvalidGenerationSource` it throws to
  /// [errors] instead of stopping the build. Other exceptions pass
  /// through.
  ///
  /// The builder also wraps its own checks in it (unique bean names, the
  /// packages' parts' checks of the module), so they are reported together
  /// with the scan's errors.
  void collectErrors(void Function() action) {
    try {
      action();
    } on InvalidGenerationSource catch (error) {
      errors.add(error);
    }
  }

  /// Throws the collected [errors], once everything is scanned: the error
  /// itself when there is one, a [BuildErrors] listing them when there are
  /// several. Does nothing without errors.
  ///
  /// It first checks what needs the whole application: the classes that
  /// declare a member for advice that follows the bean's own calls and
  /// are no bean (see [_checkTargetClassDeclarers]); and logs the
  /// introspection's warnings.
  void throwErrors() {
    _checkTargetClassDeclarers();
    _checkPlacementOwners();
    introspection.warnings.forEach(log.warning);
    switch (errors) {
      case []:
        return;
      case [final error]:
        throw error;
      default:
        throw BuildErrors(errors);
    }
  }

  static String _classKind(ClassElement element) => element.isSealed
      ? 'sealed'
      : element.isInterface
      ? 'interface'
      : 'abstract';

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

  /// Adds the beans of the class [element]: a scanned component, or a
  /// class reached through `@Import`.
  ///
  /// The class becomes one bean and each of its `@Bean` methods another.
  /// Every class in `@Import([...])` is scanned the same way, recursively,
  /// and registered only when its importer is. A class reached several
  /// times is added once. [annotation] is the component annotation, which
  /// may give the bean name (`@Component('x')`); without one the name is
  /// the decapitalized class name (`AuthService` → `authService`,
  /// `URLService` stays).
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
    _beanClassesScanned.add(element);
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
    // properties, not beans (see boundConstructor).
    final constructors = boundConstructor(element) == null
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
          : _withoutProxy(type),
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

  /// The `@Bean` methods of [type], its superclasses and mixins, each with
  /// its `@Bean` annotation; Spring scans the class hierarchy the same way.
  ///
  /// A method is taken from its most derived declaration, with the type
  /// arguments of [type] substituted, so an override runs. The annotation
  /// may sit on an overridden declaration only.
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

  /// [type] and its superclasses and mixins, most derived first, in the
  /// order Dart looks members up (`class C extends B with M1, M2`: C, M2,
  /// M1, B). Interfaces are not included.
  ///
  /// Each type has the type arguments substituted, so the members of
  /// `BaseService<R>` seen through `UserService extends BaseService<User>`
  /// mention `User`.
  List<InterfaceType> _linearization(InterfaceType type) {
    final chain = <InterfaceType>[];
    InterfaceType? current = type;
    while (current != null && !current.isDartCoreObject) {
      chain
        ..add(current)
        ..addAll(current.mixins.reversed);
      current = current.superclass;
    }
    return chain;
  }

  /// [type] first, then every supertype including interfaces, with the
  /// type arguments substituted (see [_linearization]). Callers keep the
  /// first declaration of a name, so subclass declarations win.
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

  /// The annotations a proxy sees on [accessor]: its [_userAnnotations],
  /// and for the implicit accessors of a field also those of the field, so
  /// `@Timed() int count = 0;` advises `count` like an annotated explicit
  /// getter.
  ///
  /// The field's constraints and `@Valid` stay out. On a field they
  /// validate the field; on an accessor, method validation would check the
  /// getter's return value and every setter call.
  List<DartObject> _accessorAnnotations(PropertyAccessorElement accessor) => [
    ..._userAnnotations(accessor),
    if (accessor.isOriginVariable)
      for (final annotation in _userAnnotations(accessor.variable))
        if (annotation.type case final type?
            when !_constraint.isAssignableFromType(type) &&
                !_valid.isExactlyType(type))
          annotation,
  ];

  /// The annotations of [element] that are kept in the generated metadata,
  /// where pointcuts, validation and user code read them at runtime: user
  /// annotations and constraints. SDK annotations, private ones and the
  /// container's own injection annotations are dropped.
  ///
  /// An annotation the generated library cannot re-create (a private
  /// constant or function among its values, `@Audit(_level)`) is left out.
  /// A constraint or `@Valid` fails the build instead, since leaving it
  /// out would silently skip the validation.
  List<DartObject> _userAnnotations(Element element) => [
    for (final annotation in element.metadata.annotations)
      if (annotation.computeConstantValue() case final value?)
        if (value.type case final InterfaceType type
            when !type.element.library.isInSdk &&
                type.element.isPublic &&
                !(_isSpringType(type) &&
                    _diAnnotations.contains(type.element.name)) &&
                _recreatableOrFail(value, type, element))
          _keepingSource(value, annotation),
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
  /// `BeanDefinition.annotations`, which `findAnnotationOnBean` and
  /// `getBeansWithAnnotation` read at runtime: every public annotation not
  /// from the SDK that generated code can re-create. Others are left out
  /// silently.
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
    if (reader.isSymbol) {
      return _isPublicSymbol(value);
    }
    if (value.toRecordValue() case final record?) {
      return record.positional.every(_isRecreatable) &&
          record.named.values.every(_isRecreatable);
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
  // `void` (see [isWritableType]).
  bool _isWritableType(DartType type) => isWritableType(type);

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
    _rejectProductDefinitionAnnotations(method, returnType);
    final scope = _scopeOf(method);
    final arguments = _arguments(method.formalParameters, creation: true);
    final factoryObjectTypes = _factoryObjectTypes(returnType);
    // `@ConfigurationProperties` on a `@Bean` method binds the returned
    // object (also a class of another package): it needs introspection.
    if (_configurationProperties.hasAnnotationOf(method)) {
      if (returnType.element case final ClassElement element) {
        introspection.needClass(
          element,
          IntrospectionNeed.configuration,
          binding: true,
        );
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
            ? (method.enclosingElement! as InterfaceElement).thisType
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
      // Like Spring's AnnotationAwareOrderComparator, which reads @Order
      // from the instance's class when the @Bean method has none.
      order: _orderOf(method) ?? _orderOf(returnType.element),
      description: _descriptionOf(method),
      dependsOn: _dependsOnOf(method),
      qualifiers: _qualifiersOf(method),
      conditions: [
        ...classConditions,
        ..._withDeclaredType(
          _conditions(method),
          inferred ? declaredType : null,
        ),
      ],
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
      advisorPointcut: _advisorPointcutOf(method),
      // The proxy class is named after owner and method, because two
      // `@Bean` methods may return the same type.
      proxy:
          _notProxied.any((c) => c.isAssignableFromType(returnType)) ||
              _aspectAnnotation.hasAnnotationOf(returnType.element) ||
              _configuration.hasAnnotationOf(returnType.element)
          ? _withoutProxy(returnType)
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
    final hierarchy = [type, ...type.allSupertypes];
    for (final current in hierarchy) {
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
        final member = _proxyMethod(implementation, hierarchy, declaring);
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
        '$annotationName advice $name names the $valueField parameter '
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

  // The bean of an interface whose implementation is generated (an HTTP
  // client, a repository) is a singleton the starter makes, with its
  // `@Primary`, qualifiers and conditions; the other definition
  // annotations would be ignored without a word.
  void _rejectUnreadDefinitionAnnotations(ClassElement element) {
    for (final checker in _generatedBeanIgnored) {
      if (checker.firstAnnotationOf(element)?.type?.element?.name
          case final name?) {
        collectErrors(
          () => _fail(
            '@$name on ${element.name}: its bean is made by the starter '
            'that generates its implementation, as a singleton with its '
            '@Primary, qualifiers and conditions; @$name does not apply. '
            'Remove it, or declare the bean with a @Bean method that '
            'carries it.',
            element,
          ),
        );
      }
    }
  }

  static final List<TypeChecker> _generatedBeanIgnored = [
    _scope,
    _lazy,
    _fallback,
    _dependsOn,
    _description,
    _order,
    _import,
    _propertySource,
    _configurable,
  ];

  // The definition annotations of the class a `@Bean` method returns,
  // which Spring ignores there (the method's own decide): one on a class
  // that is no component of its own fails the build with the way out.
  // `@Order` is read from the class, as Spring does.
  void _rejectProductDefinitionAnnotations(
    MethodElement method,
    InterfaceType returnType,
  ) {
    final element = returnType.element;
    if (element.library.isInSdk || _component.hasAnnotationOf(element)) {
      return;
    }
    for (final checker in _productIgnored) {
      if (checker.firstAnnotationOf(element)?.type?.element?.name
          case final name?) {
        _fail(
          '@$name on ${element.name}: ${element.name} is the result of the '
          '@Bean method ${_describe(method).replaceFirst('@Bean method ', '')}'
          ', whose own annotations decide (Spring ignores @$name on the '
          'class here). Put @$name on that method.',
          element,
        );
      }
    }
  }

  static final List<TypeChecker> _productIgnored = [
    _scope,
    _lazy,
    _primary,
    _fallback,
    _dependsOn,
    _description,
    _profile,
    _conditional,
    _condition,
  ];

  // Spring Boot deduces the type of a bare `@ConditionalOnMissingBean()`
  // (`@ConditionalOnBean()`) on a `@Bean` method from the method's return
  // type; the definition knows only the type of the value. With
  // [declaredType] (when it differs from the inferred one), such a
  // condition is written with the declared type.
  List<ConditionModel> _withDeclaredType(
    List<ConditionModel> conditions,
    InterfaceType? declaredType,
  ) => declaredType == null
      ? conditions
      : [
          for (final condition in conditions)
            if (condition case AnnotationConditionModel(:final value)
                when _deducesType(value))
              DeclaredTypeConditionModel(value, declaredType)
            else
              condition,
        ];

  static final List<TypeChecker> _deducingConditions = [
    const TypeChecker.typeNamedLiterally(
      'ConditionalOnMissingBean',
      inPackage: 'spring_boot_dart',
    ),
    const TypeChecker.typeNamedLiterally(
      'ConditionalOnBean',
      inPackage: 'spring_boot_dart',
    ),
  ];

  static bool _deducesType(DartObject value) {
    final type = value.type;
    if (type == null ||
        !_deducingConditions.any((c) => c.isExactlyType(type))) {
      return false;
    }
    bool empty(String field) =>
        value.getField(field)?.toListValue()?.isEmpty ?? true;
    return value.getField('type')?.toTypeValue() == null &&
        value.getField('name')?.toStringValue() == null &&
        empty('types') &&
        empty('names') &&
        empty('annotations');
  }

  // Aspects, configuration classes (their `@Bean` methods are called
  // directly) and infrastructure beans are never proxied, as in Spring.
  bool _isProxyCandidate(ClassElement element) =>
      proxyMode != ProxyMode.none &&
      !_aspectAnnotation.hasAnnotationOf(element) &&
      !_configuration.hasAnnotationOf(element) &&
      !_notProxied.any((c) => c.isAssignableFromType(element.thisType));

  /// The model of the wrapper proxy of [type], a bean class of a library
  /// package whose module left the proxy to the application
  /// (`AopProxyFactory.deferred`); the class name is made unique in the
  /// module. `null` when proxies are off.
  ProxyModel? foreignProxyModel(InterfaceType type) =>
      _proxyModel(type, '_\$${type.element.name}Proxy', implementSelf: true);

  /// The proxy model of [targetType], to be generated as [className];
  /// `null` when proxies are off or the type is from the SDK.
  ///
  /// A component class that no generated class can implement (private
  /// members, `final`, `base`, `sealed`) gets a subclass proxy in `all`
  /// mode, created through [constructor]. When it cannot be extended
  /// either, or for any other type that cannot be proxied, the model only
  /// has the signatures and [ProxyModel.unavailableReason]. The build then
  /// goes on, and the context fails at startup, saying what to change,
  /// only if advice matches the bean.
  ProxyModel? _proxyModel(
    InterfaceType targetType,
    String className, {
    required bool implementSelf,
    ProxyMode? mode,
    ConstructorElement? constructor,
  }) {
    final model = _proxyModelOf(
      targetType,
      className,
      implementSelf: implementSelf,
      mode: mode,
      constructor: constructor,
    );
    if (model != null) {
      for (final generation in generations) {
        model.mixins.addAll(generation.proxyMixins(model));
      }
    }
    // The expressions on its methods (cache keys, security conditions)
    // read the classes of their arguments and results.
    _introspectSpelTypes(model);
    return model;
  }

  ProxyModel? _proxyModelOf(
    InterfaceType targetType,
    String className, {
    required bool implementSelf,
    ProxyMode? mode,
    ConstructorElement? constructor,
  }) {
    _proxyFailure = null;
    // A component class that cannot be implemented but has supertypes that
    // can: a proxy implementing only those would hide the class (advice
    // matched on it, or on its private-state members, would not run, and
    // the bean could not be injected by its class). CGLIB subclasses it,
    // so a subclass proxy is preferred; implementing the supertypes is the
    // fallback when the class cannot be extended either.
    // A member annotated for advice that follows the bean's own calls
    // (`@ProxyTargetClass()` on the annotation's class): only a subclass
    // sees them, and it is not an advice-mode choice.
    final targetClassBy = implementSelf && !targetType.element.library.isInSdk
        ? _targetClassAnnotation(targetType)
        : null;
    if (targetClassBy != null) {
      final typeName = targetType.element.name;
      _targetClassBeans.addAll(_hierarchy(targetType));
      if (constructor == null || (mode ?? proxyMode) != ProxyMode.all) {
        final element = targetType.element;
        _fail(
          element is ClassElement && element.isAbstract
              ? '@$targetClassBy on a member of $typeName, whose '
                    'implementation is generated (a repository, an HTTP '
                    'client): the annotation works on the members of a '
                    'component class, whose proxy extends it. Put it on a '
                    'member of a component that calls $typeName.'
              : '@$targetClassBy on a member of $typeName needs a proxy '
                    'that extends $typeName: declare $typeName as a '
                    'component class with one constructor (not as the '
                    'result of a @Bean method), and leave aop_proxies at '
                    '`all`.',
          element,
        );
      }
      final subclass = _subclassProxyModel(
        targetType,
        className,
        constructor,
        '@$targetClassBy on a member of $typeName needs a proxy that '
        'extends $typeName.',
        interfaceAlternative: false,
      );
      if (subclass?.subclass == null) {
        _fail(
          subclass?.unavailableReason ??
              '@$targetClassBy on a member of $typeName needs a proxy that '
                  'extends $typeName, which cannot be made.',
          targetType.element,
        );
      }
      subclass!.targetClass = true;
      _checkTargetClassMembers(targetType, subclass);
      return _withImplementations(_checkedProxy(subclass));
    }
    if (constructor != null &&
        implementSelf &&
        (mode ?? proxyMode) == ProxyMode.all &&
        !targetType.element.library.isInSdk &&
        !_canImplement(targetType)) {
      final subclass = _subclassProxyModel(
        targetType,
        className,
        constructor,
        '${targetType.element.name} cannot be implemented by a generated '
        'class (it has private members, or is final, base or sealed).',
      );
      if (subclass?.subclass != null) {
        return _withImplementations(_checkedProxy(subclass));
      }
    }
    final model = _buildProxyModel(
      targetType,
      className,
      implementSelf: implementSelf,
      mode: mode,
    );
    final failure = _proxyFailure;
    if (model != null || failure == null) {
      return _withImplementations(_checkedProxy(model));
    }
    if (constructor != null && (mode ?? proxyMode) == ProxyMode.all) {
      return _withImplementations(
        _checkedProxy(
          _subclassProxyModel(targetType, className, constructor, failure),
        ),
      );
    }
    return _withImplementations(
      _checkedProxy(_signatureOnlyModel(targetType, className, failure)),
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
    final superclassAnnotations = <Element?, List<List<DartObject>>>{};
    bool isProtected(Element? element) =>
        element != null &&
        (element.metadata.hasProtected ||
            (element is PropertyAccessorElement &&
                element.variable.metadata.hasProtected));
    for (final member in model.members) {
      final name = member.name;
      final implementation = switch (member.kind) {
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
      member.superclassAnnotations = superclassAnnotations[owner] ??=
          _superclassAnnotations(
            owner is InterfaceElement ? owner : target.element,
          );
      if (owner is! InterfaceElement || owner == target.element) {
        continue;
      }
      member
        ..implementingTypes = [
          owner.name!,
          for (final supertype in owner.allSupertypes)
            if (!supertype.isDartCoreObject) supertype.element.name!,
        ]
        ..implementingTypeAnnotations = _userAnnotations(owner);
    }
    return model;
  }

  // The annotations of each superclass and mixin of [element] that has
  // some, nearest first (the order members are looked up in), like the
  // class hierarchy Spring's `AnnotationUtils.findAnnotation` searches.
  List<List<DartObject>> _superclassAnnotations(InterfaceElement element) {
    final levels = <List<DartObject>>[];
    void add(InterfaceElement type) {
      if (_userAnnotations(type) case final annotations
          when annotations.isNotEmpty) {
        levels.add(annotations);
      }
    }

    InterfaceElement? current = element;
    while (current != null) {
      current.mixins.reversed.map((mixin) => mixin.element).forEach(add);
      final supertype = current.supertype;
      if (supertype == null || supertype.isDartCoreObject) {
        break;
      }
      add(supertype.element);
      current = supertype.element;
    }
    return levels;
  }

  // A subclass proxy (see `SubclassProxy`) of a component class that no
  // generated class can implement ([implementFailure]); when the class
  // cannot be extended either, only its signatures (like any type that
  // cannot be proxied): the context fails at startup, saying what to
  // change, only if advice matches the bean.
  // The name of the first annotation on a member of [type] (or of a
  // class it inherits from) whose class is marked `@ProxyTargetClass()`;
  // `null` when there is none.
  String? _targetClassAnnotation(InterfaceType type) {
    for (final element in _hierarchy(type)) {
      if (_targetClassMembers(element).firstOrNull case (final by, _)?) {
        return by;
      }
    }
    return null;
  }

  // The members that [element] itself declares with an annotation whose
  // class is marked `@ProxyTargetClass()`, each with the annotation's name.
  Iterable<(String, Element)> _targetClassMembers(InstanceElement element) =>
      _targetClassAnnotated([
        ...element.fields,
        ...element.getters,
        ...element.setters,
        ...element.methods,
      ]);

  Iterable<(String, Element)> _targetClassAnnotated(
    Iterable<Element> members,
  ) sync* {
    for (final member in members) {
      for (final annotation in member.metadata.annotations) {
        if (annotation.computeConstantValue()?.type
            case final InterfaceType annotationType
            when _proxyTargetClass.hasAnnotationOf(annotationType.element)) {
          yield (annotationType.element.name!, member);
          break;
        }
      }
    }
  }

  // The classes and mixins of the beans whose proxy extends them for such
  // a member, and of the beans told why they get none.
  final _targetClassBeans = <InterfaceElement>{};

  // The classes that declare such a member and could be created (they are
  // not abstract): each must be a bean, or a base of one.
  final _targetClassDeclarers = <ClassElement, (String, Element)>{};

  // A public member annotated for a target-class proxy that the subclass
  // could not override would be left out of the advice without a word.
  void _checkTargetClassMembers(InterfaceType targetType, ProxyModel proxy) {
    final overridden = {for (final member in proxy.members) member.name};
    final typeName = targetType.element.name;
    for (final element in _hierarchy(targetType)) {
      for (final (by, member) in _targetClassMembers(element)) {
        final name = member.name;
        if (name == null ||
            member.isPrivate ||
            (member is ExecutableElement && member.isStatic) ||
            (member is FieldElement && member.isStatic) ||
            overridden.contains(name)) {
          continue;
        }
        _fail(
          '@$by on ${element.name}.$name: the proxy of $typeName cannot '
          'override it (it is an operator or @nonVirtual, its type is '
          'private, or a default value of a parameter is not a public '
          'constant), so it would not be followed.',
          member,
        );
      }
    }
  }

  // No proxy for a bean the container does not proxy (an aspect, a
  // post-processor), which must have no member annotated for a
  // target-class proxy.
  ProxyModel? _withoutProxy(DartType type) {
    if (type is InterfaceType && !type.element.library.isInSdk) {
      _rejectTargetClassWithoutProxy(type);
    }
    return null;
  }

  void _rejectTargetClassWithoutProxy(InterfaceType type) {
    _rejectAdviceWithoutProxy(type);
    final by = _targetClassAnnotation(type);
    if (by == null) {
      return;
    }
    _targetClassBeans.addAll(_hierarchy(type));
    final element = type.element;
    if (_configuration.hasAnnotationOf(element)) {
      // The starter of the annotation says it in its own words.
      return;
    }
    final typeName = element.name;
    _fail(
      proxyMode == ProxyMode.none
          ? '@$by on a member of $typeName needs a proxy that extends '
                '$typeName, and aop_proxies is `none`: leave it at `all`.'
          : '@$by on a member of $typeName, a bean the container does not '
                'proxy (an @Aspect, a post-processor, an Advisor or a '
                'FactoryBean): the annotation would do nothing. Move the '
                'member into a component of its own.',
      element,
    );
  }

  // Advice on a bean the container does not proxy would never run. Spring
  // advises a @Configuration class (a CGLIB subclass); here its @Bean
  // methods are called on a generated subclass that runs no advice, so it
  // fails the build with the way out. Aspects and post-processors are not
  // advised in Spring either ("not eligible for auto-proxying").
  void _rejectAdviceWithoutProxy(InterfaceType type) {
    if (proxyMode == ProxyMode.none) {
      return;
    }
    final (annotation, member) = _adviceOn(type) ?? (null, null);
    if (annotation == null || member == null) {
      return;
    }
    final element = type.element;
    final typeName = element.name;
    final name = '@${annotation.type!.element!.name}';
    final site = member == element
        ? typeName
        : '$typeName.${member.displayName}';
    _fail(
      _configuration.hasAnnotationOf(element)
          ? '$name on $site'
                ', a @Configuration class: the container does not proxy a '
                'configuration class, so the advice would not run (Spring '
                'proxies it, this generator calls its @Bean methods on a '
                'subclass that runs no advice). Move the method into a '
                '@Service and inject that.'
          : '$name on $site'
                ', a bean the container does not proxy (an @Aspect, a '
                'post-processor, an Advisor or a FactoryBean): the advice '
                'would not run, as in Spring ("not eligible for '
                'auto-proxying"). Move the method into a component of its '
                'own.',
      member,
    );
  }

  // `@ProxyTargetClass` annotations where no bean's proxy can follow them:
  // a member of an enum, an extension or an extension type, a top-level
  // variable or function. Like a stereotype there, they would be ignored
  // without a word.
  void _rejectTargetClassOutsideBeans(LibraryElement library) {
    final places = <(String, Iterable<Element>)>[
      for (final element in library.enums)
        (
          'the enum ${element.name}',
          [
            ...element.fields,
            ...element.getters,
            ...element.setters,
            ...element.methods,
          ],
        ),
      for (final element in library.extensions)
        (
          'the extension ${element.name ?? 'on ${element.extendedType}'}',
          [
            ...element.fields,
            ...element.getters,
            ...element.setters,
            ...element.methods,
          ],
        ),
      for (final element in library.extensionTypes)
        (
          'the extension type ${element.name}',
          [
            ...element.fields,
            ...element.getters,
            ...element.setters,
            ...element.methods,
          ],
        ),
      (
        'the top level of ${library.uri}',
        [
          ...library.topLevelVariables,
          ...library.getters,
          ...library.setters,
          ...library.topLevelFunctions,
        ],
      ),
    ];
    for (final (place, members) in places) {
      for (final (by, member) in _targetClassAnnotated(members)) {
        collectErrors(
          () => _fail(
            '@$by on ${member.displayName}, in $place: it goes on a member '
            'of a component class (@Component, @Service), whose proxy '
            'follows it. Move ${member.displayName} into one.',
            member,
          ),
        );
      }
    }
    for (final element in library.classes) {
      if (element.isAbstract) {
        continue;
      }
      if (_targetClassMembers(element).firstOrNull case final found?) {
        _targetClassDeclarers[element] = found;
      }
    }
  }

  // Once every library is scanned: a class that can be created and
  // declares such a member, and is neither a bean nor a base of one.
  void _checkTargetClassDeclarers() {
    for (final MapEntry(key: element, value: (by, member))
        in _targetClassDeclarers.entries) {
      if (_targetClassBeans.contains(element)) {
        continue;
      }
      collectErrors(
        () => _fail(
          '@$by on ${element.name}.${member.displayName}, and '
          '${element.name} is no bean: the annotation works on the members '
          'of a component class (@Component, @Service), whose proxy '
          'follows them, and would do nothing here. Annotate '
          '${element.name} as a component, or make it abstract when it is '
          'only a base of components.',
          member,
        ),
      );
    }
  }

  /// Reports each annotation class used in [libraries] that supplies a
  /// value of a framework annotation through a getter. Call it before
  /// [scanLibrary]: a scan reads an annotation on a class's supertypes too,
  /// in a library it may not have checked yet, so with one of these nothing
  /// is scanned and [throwErrors] reports them.
  ///
  /// ```dart
  /// class Dev extends Component implements Profile {
  ///   const Dev();
  ///   @override
  ///   List<String> get value => const ['dev']; // this build error
  /// }
  /// ```
  void checkAnnotationValues(Iterable<LibraryElement> libraries) {
    final seen = <InterfaceElement>{};
    for (final library in libraries) {
      for (final site in [
        ...AnnotationPlacements.sitesOf(library),
        ...AnnotationPlacements.targetOnlySitesOf(library),
      ]) {
        if (!seen.add(site.annotationType.element)) {
          continue;
        }
        if (getterValueOf(site.annotationType) case final value?) {
          _hasUnreadableValues = true;
          collectErrors(() => _fail(value.problem(site.subject), value.getter));
        }
      }
    }
  }

  // Every annotation of [library] that a placement covers, in its place:
  // what is wrong there fails the build; what the class around it must be
  // is checked once the module is scanned ([_checkPlacementOwners]).
  void _checkPlacements(LibraryElement library) {
    for (final site in AnnotationPlacements.sitesOf(library)) {
      final type = site.annotationType;
      if (type.element.library.isInSdk) {
        continue;
      }
      final placement = placements.of(site);
      if (placement == null) {
        continue;
      }
      if (placement.problem(site) case final problem?) {
        collectErrors(() => _fail(problem, site.location));
        continue;
      }
      final ownerClass = site.kind == PlaceKind.classDeclaration
          ? site.element
          : site.owner;
      if (ownerClass is ClassElement && ownerClass.isAbstract) {
        if (placement.generatedBeanProblem(site) case final problem?) {
          _generatedBeanChecks.add((site, problem, ownerClass));
        }
      }
      final owner = placement.owner(site);
      if (owner != null &&
          ownerClass is InterfaceElement &&
          _ownerIsChecked(placement, owner, ownerClass)) {
        _ownerChecks.add((site, placement, owner, ownerClass));
      }
    }
    for (final site in AnnotationPlacements.targetOnlySitesOf(library)) {
      if (_declaredTargets.forbids(site)) {
        collectErrors(
          () => _fail(_declaredTargets.problem(site)!, site.location),
        );
      }
    }
  }

  static bool _isBase(InterfaceElement element) => switch (element) {
    ClassElement(:final isAbstract, :final isSealed) => isAbstract || isSealed,
    _ => true,
  };

  // A class that can be created is always checked; a base when the owner
  // says so, or when the placement looks at the classes extending it.
  static bool _ownerIsChecked(
    AnnotationPlacement placement,
    PlacementOwner owner,
    InterfaceElement ownerClass,
  ) =>
      !_isBase(ownerClass) ||
      placement.checksBases ||
      (ownerClass is ClassElement &&
          (owner is BeanItselfOwner ||
              (owner is PredicateOwner && owner.abstractToo)));

  // The bean classes of the module: with [products], those a `@Bean` method
  // returns too. A class with a stereotype counts even when a scan filter
  // left it out.
  bool _isBeanItself(
    InterfaceElement element,
    BeanItselfOwner owner,
    Set<InterfaceElement> declared,
    Set<InterfaceElement> returned,
  ) =>
      _component.hasAnnotationOf(element) ||
      declared.contains(element) ||
      (owner.products && returned.contains(element)) ||
      (owner.exported && exportedClasses.contains(element));

  void _checkGeneratedBeans(Set<InterfaceElement> declared) {
    for (final (site, problem, ownerClass) in _generatedBeanChecks) {
      if (declared.contains(ownerClass) && !hasLookupMethods(ownerClass)) {
        collectErrors(() => _fail(problem, site.location));
      }
    }
  }

  // Once every library is scanned: the class around each annotation that
  // must be a bean (or a class with some annotation) is one, or a base of
  // one.
  void _checkPlacementOwners() {
    final declaredBeans = <InterfaceElement>{
      for (final bean in module.beans)
        if (identical(bean.element, bean.type.element)) bean.type.element,
    };
    final returnedBeans = <InterfaceElement>{
      for (final bean in module.beans) bean.type.element,
    };
    _checkGeneratedBeans(declaredBeans);
    if (_ownerChecks.isEmpty) {
      return;
    }
    final beanClasses = <InterfaceElement>{
      for (final bean in module.beans) ..._hierarchy(bean.type),
      for (final element in _beanClassesScanned)
        ..._hierarchy(element.thisType),
      for (final element in _scannedClasses)
        if (_configurable.hasAnnotationOf(element)) element,
    };
    final annotated = <TypeChecker, Set<InterfaceElement>>{};
    Set<InterfaceElement> annotatedBy(List<TypeChecker> checkers) {
      final result = <InterfaceElement>{};
      for (final checker in checkers) {
        result.addAll(
          annotated.putIfAbsent(
            checker,
            () => {
              for (final element in _scannedClasses)
                if (checker.hasAnnotationOf(element))
                  ..._hierarchy(element.thisType),
            },
          ),
        );
      }
      return result;
    }

    final reported = <(Element, InterfaceType)>{};
    for (final (site, placement, owner, ownerClass) in _ownerChecks) {
      if (owner is BeanItselfOwner) {
        if (!_isBeanItself(ownerClass, owner, declaredBeans, returnedBeans) &&
            reported.add((site.element, site.annotationType))) {
          collectErrors(
            () => _fail(placement.ownerProblem(site), site.location),
          );
        }
        continue;
      }
      if (_isBase(ownerClass) &&
          placement.checksBases &&
          !(owner is PredicateOwner && owner.abstractToo) &&
          !_scannedClasses.any(
            (element) =>
                !_isBase(element) &&
                _hierarchy(element.thisType).contains(ownerClass),
          )) {
        continue;
      }
      final owners = switch (owner) {
        BeanItselfOwner() => const <InterfaceElement>{},
        BeanOwner() => beanClasses,
        AnnotatedOwner(:final checkers) => annotatedBy(checkers),
        PredicateOwner(:final test) => {
          for (final element in _scannedClasses)
            if (test(element, module)) ..._hierarchy(element.thisType),
        },
      };
      if (owners.contains(ownerClass) ||
          !reported.add((site.element, site.annotationType))) {
        continue;
      }
      collectErrors(() => _fail(placement.ownerProblem(site), site.location));
    }
  }

  // The advice (`@Transactional`, `@PreAuthorize`) on [type] or its
  // members, for a bean the container does not proxy: the first found.
  (DartObject, Element)? _adviceOn(InterfaceType type) {
    for (final element in _hierarchy(type)) {
      // `@Validated` on a `@ConfigurationProperties` class checks the
      // bound values, not calls.
      final bound = _configurationProperties.hasAnnotationOf(element);
      for (final annotation in element.metadata.annotations) {
        if (annotation.computeConstantValue() case final value?
            when placements.isAdvice(value) &&
                !(bound && value.type?.element?.name == 'Validated')) {
          return (value, element);
        }
      }
      for (final member in <Element>[
        ...element.fields,
        ...element.getters,
        ...element.setters,
        // A `@Bean` method's advice is reported where it is.
        ...element.methods.where((method) => !_bean.hasAnnotationOf(method)),
      ]) {
        for (final annotation in member.metadata.annotations) {
          if (annotation.computeConstantValue() case final value?
              when placements.isAdvice(value)) {
            return (value, member);
          }
        }
      }
    }
    return null;
  }

  // Whether [member] (a declaration of a proxied type's member) or the
  // class declaring it carries advice.
  bool _carriesAdvice(Element member) {
    bool advised(Element element) => element.metadata.annotations.any(
      (annotation) => switch (annotation.computeConstantValue()) {
        final value? => placements.isAdvice(value),
        null => false,
      },
    );
    final owner = member.enclosingElement;
    return advised(member) ||
        (member is PropertyAccessorElement && advised(member.variable)) ||
        (owner != null && advised(owner));
  }

  ProxyModel? _subclassProxyModel(
    InterfaceType targetType,
    String className,
    ConstructorElement constructor,
    String implementFailure, {
    bool interfaceAlternative = true,
  }) {
    final element = targetType.element;
    final typeName = element.name!;
    ProxyModel unavailable(String problem, String change) =>
        _signatureOnlyModel(
          targetType,
          className,
          interfaceAlternative
              ? '$implementFailure A subclass proxy (the bean created as a '
                    'generated subclass of $typeName) is not possible '
                    'either, because $typeName $problem. $change, or add an '
                    'interface with the advised methods and inject the bean '
                    'by it.'
              : '$implementFailure It cannot be made, because $typeName '
                    '$problem. $change.',
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
    // A member the proxy cannot override stays inherited and unadvised; one
    // that carries advice (or whose class does) fails the build, since a
    // `@PreAuthorize` that does not run is worse than none.
    void skip(String kind, String name, String reason, Element declaration) {
      if (_carriesAdvice(declaration)) {
        _fail(
          'The $kind $typeName.$name carries advice, but the subclass proxy '
          'of $typeName cannot override it ($reason), so the advice would '
          'not run. Remove what stops the override, or move the advised '
          'work into a member the proxy can override.',
          declaration,
        );
      }
      log.warning(
        'The $kind $typeName.$name is not advised: the subclass proxy of '
        '$typeName cannot override it ($reason).',
      );
    }

    // `@nonVirtual` (package:meta) on any declaration of the member.
    final hierarchy = [targetType, ...targetType.allSupertypes];
    bool nonVirtual(
      String name,
      ExecutableElement? Function(InterfaceType) of,
    ) => hierarchy.any((type) {
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
          skip('method', name, nonVirtualReason, method);
          continue;
        }
        final member = _proxyMethod(implementation, hierarchy, declaring);
        if (member == null) {
          skip(
            'method',
            name,
            'a parameter default value is not a public constant, or a '
                'signature uses a private type',
            method,
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
          skip('getter', name, 'its type is private', getter);
          continue;
        }
        if (nonVirtual(name, (type) => type.getGetter(name))) {
          skip('getter', name, nonVirtualReason, getter);
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
          skip('setter', name, 'its type is private', setter);
          continue;
        }
        if (nonVirtual(name, (type) => type.getSetter(name))) {
          skip('setter', name, nonVirtualReason, setter);
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
          for (final (index, parameter) in constructor.formalParameters.indexed)
            ProxyParameter(
              name: forwardedParameterName(constructor.formalParameters, index),
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

  // [model], once each part has checked it
  // ([PackageGeneration.checkProxy]): what a part's annotations cannot do on
  // its members fails the build.
  ProxyModel? _checkedProxy(ProxyModel? model) {
    if (model == null) {
      return null;
    }
    for (final generation in generations) {
      generation.checkProxy(model);
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
              for (final (index, parameter) in method.formalParameters.indexed)
                ProxyParameter(
                  name: forwardedParameterName(method.formalParameters, index),
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
    final hierarchy = [targetType, ...targetType.allSupertypes];
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
              : _proxyMethod(implementation, hierarchy, declaring);
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
  // annotations of its interface declarations plus the constraints and
  // `@Valid` of every declaration (see [_inheritedAnnotations]).
  List<ProxyMember> _withDeclaringTypes(
    List<ProxyMember> members,
    List<InterfaceType> allTypes,
    InterfaceType targetType,
  ) {
    final chain = _runningClasses(targetType);
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
          final all = [
            for (final type in allTypes) ...declarations(type, member),
          ];
          for (final declaration in all) {
            for (final annotation in _inheritedAnnotations(
              declaration,
              chain,
            )) {
              if (!annotations.contains(annotation)) {
                annotations.add(annotation);
              }
            }
          }
          final merged = <DartObject>[...member.mergedAnnotations];
          for (final annotation in _mergedAnnotations(all, chain)) {
            if (!merged.contains(annotation)) {
              merged.add(annotation);
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
            mergedAnnotations: merged,
          );
        }(),
    ];
  }

  // A forwarded method, or `null` if its types or default values cannot be
  // written in the generated library. Constraints and `@Valid` of every
  // declaration of the method in [hierarchy] (the target type and its
  // supertypes: implemented interfaces, superclasses, mixins) apply, like
  // Hibernate Validator's method constraint inheritance; other annotations
  // (what `@annotation(...)` matches) only of the implementation and of
  // interface declarations (see [_inheritedAnnotations]).
  ProxyMember? _proxyMethod(
    MethodElement implementation,
    List<InterfaceType> hierarchy,
    String declaringType,
  ) {
    if (!_isEmittable(implementation.returnType)) {
      return null;
    }
    final name = implementation.name!;
    final declarations = <MethodElement>[
      implementation,
      for (final type in hierarchy)
        for (final method in type.element.methods)
          if (method.name == name &&
              !method.isStatic &&
              method.baseElement != implementation.baseElement)
            method,
    ];
    final chain = _runningClasses(hierarchy.first);
    final parameters = <ProxyParameter>[];
    // The annotations of the parameters of the other declarations matching
    // one of the implementation: by name when named, else by position
    // (wildcards have no usable name; positional parameters come first, so
    // [index] is the position).
    Iterable<List<DartObject>> declared(
      int index,
      FormalParameterElement parameter,
    ) sync* {
      for (final declaration in declarations.skip(1)) {
        final FormalParameterElement? other;
        if (parameter.isNamed) {
          other = declaration.formalParameters
              .where((p) => p.isNamed && p.name == parameter.name)
              .firstOrNull;
        } else {
          final positional = [
            for (final p in declaration.formalParameters)
              if (p.isPositional) p,
          ];
          other = index < positional.length ? positional[index] : null;
        }
        if (other != null) {
          yield _inheritedAnnotations(declaration, chain, other);
        }
      }
    }

    for (final (index, parameter) in implementation.formalParameters.indexed) {
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
        declared(index, parameter),
      );
      final parameterName = forwardedParameterName(
        implementation.formalParameters,
        index,
      );
      checkConstraints(
        annotations,
        type,
        '${implementation.enclosingElement?.name}.$name($parameterName)',
        parameter,
      );
      parameters.add(
        ProxyParameter(
          name: parameterName,
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
      name: name,
      declaringType: declaringType,
      returnType: implementation.returnType,
      typeParameters: implementation.typeParameters,
      parameters: parameters,
      annotations: _checkedReturnAnnotations(
        implementation,
        declarations,
        chain,
      ),
      mergedAnnotations: _mergedAnnotations(declarations, chain),
    );
  }

  // Every user annotation of [declarations] (the implementation first),
  // most specific first: the implementation, the superclass and mixin
  // members it overrides (nearest first), then the interface declarations,
  // like Spring's `AnnotatedElementUtils` find semantics. Annotation-driven
  // advisors (`@Cacheable` on an overridden superclass method) read these;
  // `@annotation(...)` matches only the filtered set (see
  // [_inheritedAnnotations]).
  List<DartObject> _mergedAnnotations(
    List<Element> declarations,
    Set<InterfaceElement> chain,
  ) {
    final classes = chain.toList();
    int rank(int index) {
      final position = classes.indexOf(
        declarations[index].enclosingElement as InterfaceElement? ??
            classes.first,
      );
      return position < 0 ? classes.length : position;
    }

    final order = [for (var i = 0; i < declarations.length; i++) i]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    final annotations = <DartObject>[];
    for (final index in order) {
      for (final annotation in _userAnnotations(declarations[index])) {
        if (!annotations.contains(annotation)) {
          annotations.add(annotation);
        }
      }
    }
    return annotations;
  }

  // The classes whose members a bean of [type] runs, most specific first:
  // the class, the mixins it applies (the last one first), then its
  // superclass and so on.
  static Set<InterfaceElement> _runningClasses(InterfaceType type) => {
    for (
      InterfaceType? current = type;
      current != null;
      current = current.superclass
    ) ...[
      current.element,
      for (final mixin in current.mixins.reversed) mixin.element,
    ],
  };

  // The annotations of [declaration] (or of its parameter [parameter]), a
  // declaration of a proxied member other than its implementation, that
  // the member carries. AspectJ's `@annotation(...)` sees the method that
  // runs, not a superclass (or mixin) method it overrides, so such a
  // declaration gives only its constraints and `@Valid` (Hibernate
  // Validator's method constraint inheritance); an interface declaration
  // (an abstract member, or one of a type the class only implements) gives
  // all of its annotations, as documented for `@annotation`.
  List<DartObject> _inheritedAnnotations(
    Element declaration,
    Set<InterfaceElement> chain, [
    FormalParameterElement? parameter,
  ]) {
    final annotations = _userAnnotations(parameter ?? declaration);
    if (declaration is ExecutableElement && declaration.isAbstract ||
        !chain.contains(declaration.enclosingElement)) {
      return annotations;
    }
    return [
      for (final annotation in annotations)
        if (annotation.type case final InterfaceType type
            when _constraint.isAssignableFromType(type) ||
                _valid.isExactlyType(type))
          annotation,
    ];
  }

  // ---------------------------------------------------------------------
  // Method validation and constraint types
  // ---------------------------------------------------------------------

  // Annotations of a parameter and of the same parameter of the overridden
  // declarations (without duplicates).
  List<DartObject> _parameterAnnotations(
    FormalParameterElement parameter,
    Iterable<List<DartObject>> declared,
  ) {
    final annotations = _userAnnotations(parameter);
    for (final other in declared) {
      for (final annotation in other) {
        if (!annotations.contains(annotation)) {
          annotations.add(annotation);
        }
      }
    }
    return annotations;
  }

  // The annotations of the method's declarations; constraints among them
  // apply to the return value, so they must fit the return type.
  List<DartObject> _checkedReturnAnnotations(
    MethodElement implementation,
    List<MethodElement> declarations,
    Set<InterfaceElement> chain,
  ) {
    final annotations = _userAnnotations(implementation);
    for (final declaration in declarations.skip(1)) {
      for (final annotation in _inheritedAnnotations(declaration, chain)) {
        if (!annotations.contains(annotation)) {
          annotations.add(annotation);
        }
      }
    }
    checkConstraints(
      annotations,
      implementation.returnType,
      '${implementation.enclosingElement?.name}.${implementation.name} '
      '(return value)',
      implementation,
    );
    return annotations;
  }

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
    if (reader.isSymbol) {
      return _isPublicSymbol(value);
    }
    if (value.toRecordValue() case final record?) {
      return record.positional.every(_isRevivable) &&
          record.named.values.every(_isRevivable);
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

  // A symbol another library can write (`#name`, `#a.b`); `#_name` is
  // private to its library.
  static bool _isPublicSymbol(DartObject value) =>
      value
          .toSymbolValue()
          ?.split('.')
          .every((part) => part.isNotEmpty && !part.startsWith('_')) ??
      false;

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

  /// Whether a class in another library can `implements` [type]: it is
  /// public, not `final`, `base` or `sealed`, and has no private members a
  /// generated class would have to implement.
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

  /// The field and setter injections of a bean of [type]: its
  /// `@Autowired` (or `@Inject`), `@Resource` and `@Value` fields and
  /// setters, inherited ones included, in injection order (see
  /// [injectionRank]).
  ///
  /// The generated code is another library, so an injected field must be
  /// public and settable; otherwise the build fails.
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

  /// The depth of each class of [type]'s hierarchy for [injectionRank], 0
  /// for the topmost one, so superclass members are injected first.
  ///
  /// The superclass chain is linearized like Dart does
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

  /// The method injections of a bean of [type]: its `@Autowired`
  /// methods, inherited ones included, in injection order (see
  /// [injectionRank]).
  ///
  /// A private or asynchronous `@Autowired` method fails the build: the
  /// generated code cannot call the first and would not await the second.
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

  /// The names of the `@PostConstruct` or `@PreDestroy` methods of
  /// [type]: superclass and mixin methods first for init, last for
  /// destroy, as in Spring. A name inherited from several levels runs
  /// once.
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

  /// The class of [type] first, then the classes of all its supertypes
  /// except `Object`. Callers keep the first declaration of a name, so
  /// subclass declarations win.
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

  /// The lazy proxy class for `@Lazy` injection of [type]: an object
  /// injected in place of the bean that resolves the bean on first use. It
  /// is shared by all injection points of that type in the module.
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

  // The types a bean can be looked up by (see [exposedBeanTypes]).
  List<InterfaceType> _exposedTypes(InterfaceType type) =>
      exposedBeanTypes(type);

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

  /// The `@Qualifier` or `@Named` value at the injection point [element],
  /// or `null` when it has neither.
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
      RegistrarModel(
        imported.thisType,
        importer,
        importer: '${importer.library.uri}#${_requireName(importer)}',
        conditions: conditions,
      ),
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
    _rejectUnreadDefinitionAnnotations(element);
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
      // In declaration order (a wildcard `_` has no usable name).
      final parameterElements = method.formalParameters;
      final parameters = [
        for (final (index, parameter) in member.parameters.indexed)
          ConstructorParameterModel(
            name: parameter.name,
            type: parameter.type,
            isNamed: parameter.isNamed,
            isRequired: parameter.isRequired,
            annotations: [
              if (index < parameterElements.length)
                ..._userAnnotations(parameterElements[index]),
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
      // so they can be (de)serialized without annotations of their own (a
      // Feign client's bodies): the answer is read in, the arguments are
      // written out.
      final spel = _spelUse(member.annotations);
      if (spel.target) {
        introspection.needClass(element, IntrospectionNeed.spel);
      }
      introspection.need(
        valueType,
        element,
        IntrospectionNeed.write |
            (spel.result ? IntrospectionNeed.spel : IntrospectionNeed.none),
      );
      for (final parameter in parameters) {
        introspection.need(
          parameter.type,
          element,
          IntrospectionNeed.read |
              (spel.arguments
                  ? IntrospectionNeed.spel
                  : IntrospectionNeed.none),
        );
      }
    }
    final model = InterfaceProxyModel(
      className: className,
      type: type,
      signatures: signatures,
      methods: methods,
      annotations: _userAnnotations(element),
    );
    final explicitName = ConstantReader(
      _component.firstAnnotationOf(element),
    ).peek('name')?.stringValue;
    module.beans.add(
      BeanModel(
        element: element,
        source: source,
        name: explicitName ?? _decapitalize(name),
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

  // The bean of [element], whose implementation a package's part
  // generates (see `ModuleScan.addGeneratedBean`).
  void _addGeneratedBean(ClassElement element, PackageCreation creation) {
    final name = _requireName(element);
    _rejectUnreadDefinitionAnnotations(element);
    final source = '${element.library.uri}#$name';
    final type = element.thisType;
    final explicitName = ConstantReader(
      _component.firstAnnotationOf(element),
    ).peek('name')?.stringValue;
    module.beans.add(
      BeanModel(
        element: element,
        source: source,
        name: explicitName ?? _decapitalize(name),
        type: type,
        exposedTypes: _exposedTypes(type),
        creation: creation,
        primary: _primary.hasAnnotationOf(element),
        qualifiers: _qualifiersOf(element),
        annotations: _beanAnnotations(element),
        conditions: [
          if (_conditions(element) case final own when own.isNotEmpty)
            GroupConditionModel(source, own),
        ],
        // Advice (e.g. @Transactional on its methods) wraps it.
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
        final markedTypes = [
          for (final annotation in method.metadata.annotations)
            if (annotation.computeConstantValue()?.type
                case final InterfaceType annotationType
                when _beanMethodAnnotation.hasAnnotationOf(
                  annotationType.element,
                ))
              annotationType,
        ];
        if (markedTypes.isEmpty) {
          continue;
        }
        final what =
            '@${markedTypes.first.element.name} method ${element.name}.$name';
        if (method.isStatic || method.isPrivate) {
          _fail('$what must be a public instance method.', method);
        }
        if (method.typeParameters.isNotEmpty) {
          _fail('$what must not be generic.', method);
        }
        final returnType = method.returnType;
        final isFuture =
            returnType is InterfaceType &&
            returnType.isDartAsyncFuture &&
            returnType.nullabilitySuffix == NullabilitySuffix.none;
        final valueType = isFuture
            ? returnType.typeArguments.single
            : returnType;
        final parameters = [
          for (final parameter in method.formalParameters)
            ConstructorParameterModel(
              name: parameter.name ?? '_',
              type: parameter.type,
              isNamed: parameter.isNamed,
              isRequired: parameter.isRequired,
              hasDefault: parameter.hasDefaultValue,
              // For a direct call that passes it when an argument is absent.
              defaultValue: switch (parameter.hasDefaultValue
                  ? parameter.computeConstantValue()
                  : null) {
                final value? when _isRecreatable(value) => value,
                _ => null,
              },
              annotations: _userAnnotations(parameter),
            ),
        ];
        // The classes of the bean's package the method's types are made of
        // are introspected for what its annotations do with them (a
        // controller's bodies are read in, its answers written out).
        final owner = type.element;
        if (owner is ClassElement) {
          final needs = _annotatedMethodNeeds(method, markedTypes);
          introspection.need(valueType, owner, needs.result);
          for (final (index, parameter) in parameters.indexed) {
            introspection.need(
              parameter.type,
              owner,
              needs.parameters[index],
            );
          }
        }
        result[name] = AnnotatedMethodModel(
          name: name,
          parameters: parameters,
          valueType: valueType,
          isFuture: isFuture,
          isVoid: valueType is VoidType,
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

  /// The default bean name of a class, by Spring's rule: the first letter
  /// in lower case (`AuthService` → `authService`), except when the first
  /// two letters are capitals (`URLService` stays).
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

  /// The public types of the scanned libraries and of the runtime, by
  /// name, with the library that declares them.
  ///
  /// When the analyzer cannot resolve a type (usually a missing import),
  /// the build error names the import to add from here. The builder fills
  /// it before scanning.
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

  /// Fails when [type], or a type it mentions, is private to its library:
  /// the generated module is another library and cannot name it.
  ///
  /// [use] says what references it ("constructor parameter dep of Cache
  /// has"), [alternative] a second way out besides making the type public.
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

  /// The first private class [type] mentions (itself, a type argument, a
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

  /// Returns [value], the default of [parameter], when the generated
  /// module can write it. Fails the build when it refers to a private
  /// function, class or constant.
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
    if (value.toRecordValue() case final record?) {
      return [
        ...record.positional,
        ...record.named.values,
      ].map(_privateConstantPart).nonNulls.firstOrNull;
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

// [value], the constant of [annotation], after keeping the annotation's
// source for the comments of the generated proxies ([annotationSources]).
DartObject _keepingSource(DartObject value, ElementAnnotation annotation) {
  annotationSources[value] ??= annotation.toSource();
  return value;
}
