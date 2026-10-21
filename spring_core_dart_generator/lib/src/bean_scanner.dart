import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';

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
final _factoryBean = _spring('FactoryBean');
final _applicationListener = _spring('ApplicationListener');
final _objectProvider = _spring('ObjectProvider');
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
  BeanScanner(this.module, {this.proxyMode = ProxyMode.all});

  /// The model being filled.
  final ModuleModel module;

  /// Which beans get a [ProxyModel].
  final ProxyMode proxyMode;

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
      final annotation = _component.firstAnnotationOf(element);
      if (annotation != null) {
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
  ///   create: (r) => r.dependency<AppConfig>(qualifier: r'appConfig').pool(),
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
      _fail('Bean class $className must be public.', element);
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
    final constructor = _selectConstructor(element);
    final classLazy = _isLazy(element);
    final owner = BeanModel(
      element: element,
      source: source,
      name: name,
      type: type,
      exposedTypes: _exposedTypes(type),
      factoryObjectTypes: _factoryObjectTypes(type),
      creation: ConstructorCreation(
        _constructorName(constructor),
        _arguments(constructor.formalParameters, creation: true),
      ),
      scope: _scopeOf(element),
      lazy: classLazy ?? false,
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
      listeners: _listeners(element),
      aspect: _aspectModel(element),
      proxy: _isProxyCandidate(element)
          ? _proxyModel(type, '_\$${className}Proxy', implementSelf: true)
          : null,
    );
    module.beans.add(owner);

    // `@Lazy` on a `@Configuration` class is the default for its `@Bean`
    // methods (as in Spring); on other components it only affects the
    // component itself.
    final isConfiguration = _configuration.hasAnnotationOf(element);
    for (final method in element.methods) {
      final beanAnnotation = _bean.firstAnnotationOf(method);
      if (beanAnnotation != null) {
        module.beans.add(
          _scanBeanMethod(
            owner,
            method,
            ConstantReader(beanAnnotation),
            classConditions: classConditions,
            classLazy: isConfiguration ? classLazy : null,
          ),
        );
      }
    }
  }

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
      ),
    );
  }

  void _scanIntrospected(ClassElement element) {
    final name = _requireName(element);
    if (element.isPrivate) {
      _fail('@Introspected class $name must be public.', element);
    }
    if (element.typeParameters.isNotEmpty) {
      _fail('Generic @Introspected class $name is not supported.', element);
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
          nullable: fieldType.nullabilitySuffix == NullabilitySuffix.question,
          writable: field.setter != null,
          annotations: [
            ..._userAnnotations(field),
            if (field.getter case final getter?) ..._userAnnotations(getter),
          ],
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
      ),
    );
  }

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

  // Whether [type] is declared in `package:spring_core_dart`.
  static bool _isSpringType(InterfaceType type) =>
      type.element.library.uri.pathSegments.firstOrNull == 'spring_core_dart';

  // One bean per `@Bean` method. Class conditions are inherited; the bean
  // is created by calling the method on the owner bean (or statically).
  BeanModel _scanBeanMethod(
    BeanModel owner,
    MethodElement method,
    ConstantReader annotation, {
    required List<ConditionModel> classConditions,
    required bool? classLazy,
  }) {
    final methodName = _requireName(method);
    if (method.isPrivate) {
      _fail('@Bean method $methodName must be public.', method);
    }
    if (method.typeParameters.isNotEmpty) {
      _fail('Generic @Bean method $methodName is not supported.', method);
    }
    final returnType = method.returnType;
    if (returnType is! InterfaceType ||
        returnType.nullabilitySuffix != NullabilitySuffix.none) {
      _fail(
        '@Bean method $methodName must return a non-nullable class type.',
        method,
      );
    }
    if (returnType.isDartAsyncFuture || returnType.isDartAsyncFutureOr) {
      _fail('@Bean method $methodName must not be async.', method);
    }
    final initMethod = annotation.peek('initMethod')?.stringValue;
    final destroyMethod = annotation.peek('destroyMethod')?.stringValue;
    return BeanModel(
      element: method,
      source: '${owner.source}.$methodName',
      name: annotation.peek('name')?.stringValue ?? methodName,
      aliases: [
        for (final alias
            in annotation.peek('aliases')?.listValue ?? const <DartObject>[])
          alias.toStringValue()!,
      ],
      type: returnType,
      exposedTypes: _exposedTypes(returnType),
      factoryObjectTypes: _factoryObjectTypes(returnType),
      creation: BeanMethodCreation(
        ownerType: owner.type,
        ownerName: owner.name,
        methodName: methodName,
        isStatic: method.isStatic,
        arguments: _arguments(method.formalParameters, creation: true),
      ),
      scope: _scopeOf(method),
      lazy: _isLazy(method) ?? classLazy ?? false,
      primary: _primary.hasAnnotationOf(method),
      fallback: _fallback.hasAnnotationOf(method),
      autowireCandidate:
          annotation.peek('autowireCandidate')?.boolValue ?? true,
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
      listeners: switch (returnType.element) {
        final ClassElement element => _listeners(element),
        _ => const [],
      },
      initMethod: initMethod == null
          ? null
          : _requireNoArgMethod(returnType, initMethod, method, 'initMethod'),
      destroyMethod: _beanDestroyMethod(returnType, destroyMethod, method),
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
  // of an `@Aspect` class; `null` for other classes.
  AspectModel? _aspectModel(ClassElement element) {
    if (!_aspectAnnotation.hasAnnotationOf(element)) {
      return null;
    }
    final pointcuts = <String, String>{};
    final advice = <AdviceModel>[];
    for (final method in element.methods) {
      final name = _requireName(method);
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
          advice.add(
            _adviceModel(
              method,
              kind,
              ConstantReader(annotation).read('pointcut').stringValue,
            ),
          );
        }
      }
    }
    return AspectModel(advice, pointcuts);
  }

  // Maps advice parameters by type: (Proceeding)JoinPoint by exact type,
  // and for after-returning/after-throwing advice the first other
  // parameter receives the return value or error.
  AdviceModel _adviceModel(MethodElement method, String kind, String pointcut) {
    final name = _requireName(method);
    if (method.isStatic || method.isPrivate) {
      _fail('Advice method $name must be a public instance method.', method);
    }
    final parameters = <AdviceParameter>[];
    DartType? valueType;
    for (final parameter in method.formalParameters) {
      final type = parameter.type;
      if (parameter.isNamed) {
        _fail('Advice method $name must use positional parameters.', method);
      }
      if (_proceedingJoinPoint.isExactlyType(type)) {
        parameters.add(AdviceParameter.proceedingJoinPoint);
      } else if (_joinPoint.isExactlyType(type)) {
        parameters.add(AdviceParameter.joinPoint);
      } else if ((kind == 'afterReturning' || kind == 'afterThrowing') &&
          valueType == null) {
        parameters.add(AdviceParameter.value);
        valueType = type;
      } else {
        _fail(
          'Unexpected parameter ${parameter.name} of @${kind[0].toUpperCase()}'
          '${kind.substring(1)} advice $name.',
          method,
        );
      }
    }
    if (kind == 'around' &&
        !parameters.contains(AdviceParameter.proceedingJoinPoint)) {
      _fail(
        '@Around advice $name needs a ProceedingJoinPoint parameter.',
        method,
      );
    }
    if (kind != 'around' &&
        parameters.contains(AdviceParameter.proceedingJoinPoint)) {
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

  // Aspects, configuration classes (their `@Bean` methods are called
  // directly) and infrastructure beans are never proxied, as in Spring.
  bool _isProxyCandidate(ClassElement element) =>
      proxyMode != ProxyMode.none &&
      !_aspectAnnotation.hasAnnotationOf(element) &&
      !_configuration.hasAnnotationOf(element) &&
      !_notProxied.any((c) => c.isAssignableFromType(element.thisType));

  /// The proxy of [targetType]; `null` when proxies are off or the type is
  /// from the SDK. A type that cannot be proxied gets a signature-only
  /// model with [ProxyModel.unavailableReason].
  ProxyModel? _proxyModel(
    InterfaceType targetType,
    String className, {
    required bool implementSelf,
    ProxyMode? mode,
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
      return model;
    }
    return _signatureOnlyModel(targetType, className, failure);
  }

  String? _proxyFailure;

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
                'a parameter default value is not a literal, or a signature '
                'uses a private type.';
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
    // For each member: every type that declares it (for pointcuts such as
    // `execution(* Api.*(..))`) and, as `declaringType`, the first abstract
    // declaring type other than the target.
    final allTypes = {
      for (final interface in interfaces) ...[
        interface,
        ...interface.allSupertypes,
      ],
    }.where((t) => !t.isDartCoreObject).toList();
    List<String> declaring(ProxyMember member) => [
      for (final type in allTypes)
        if (switch (member.kind) {
          ProxyMemberKind.method => type.element.methods.any(
            (m) => m.name == member.name,
          ),
          ProxyMemberKind.getter => type.element.getters.any(
            (g) => g.name == member.name,
          ),
          ProxyMemberKind.setter => type.element.setters.any(
            (x) => x.name == member.name,
          ),
        })
          type.element.name!,
    ];
    final withDeclaring = [
      for (final member in members)
        () {
          final names = declaring(member);
          final abstract = [
            for (final type in allTypes)
              if (names.contains(type.element.name) &&
                  _isAbstract(type) &&
                  type != targetType)
                type.element.name!,
          ];
          // Annotations of every declaration (interface and class).
          final annotations = <DartObject>[...member.annotations];
          for (final type in allTypes) {
            final Iterable<Element> declarations = switch (member.kind) {
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
            for (final declaration in declarations) {
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
    for (final parameter in implementation.formalParameters) {
      final type = parameter.type;
      final defaultValue = parameter.defaultValueCode;
      if (!_isEmittable(type) ||
          (defaultValue != null && !_literalDefault.hasMatch(defaultValue))) {
        return null;
      }
      parameters.add(
        ProxyParameter(
          name: parameter.name!,
          type: type,
          isNamed: parameter.isNamed,
          isRequired: parameter.isRequired,
          defaultValueCode: defaultValue,
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
      annotations: [
        ..._userAnnotations(implementation),
        if (!identical(implementation, declaration))
          ..._userAnnotations(declaration),
      ],
    );
  }

  /// Whether generated code can name [type].
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
              ? (parameter.computeConstantValue() ??
                    _fail(
                      'Cannot evaluate the default value of '
                      '${parameter.displayName}.',
                      parameter,
                    ))
              : null,
          collectionsMayBeEmpty: creation,
        ),
        namedAs: parameter.isNamed ? _requireName(parameter) : null,
      ),
  ];

  /// Public `@Autowired` / `@Value` fields and setters of the class and its
  /// supertypes.
  List<PropertyInjection> _propertyInjections(InterfaceType type) {
    final seen = <String>{};
    final result = <PropertyInjection>[];
    for (final element in _hierarchy(type)) {
      for (final field in element.fields) {
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
            PropertyInjection(name, _injectionPoint(field, field.type)),
          );
        }
      }
      for (final setter in element.setters) {
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
            ),
          );
        }
      }
    }
    return result;
  }

  // Fields and setters are injected only when annotated.
  bool _isInjected(Element element) =>
      _autowired.hasAnnotationOf(element) || _value.hasAnnotationOf(element);

  /// Public `@Autowired` methods of the class and its supertypes.
  List<MethodInjection> _methodInjections(InterfaceType type) {
    final seen = <String>{};
    final result = <MethodInjection>[];
    for (final element in _hierarchy(type)) {
      for (final method in element.methods) {
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
            MethodInjection(name, _arguments(method.formalParameters)),
          );
        }
      }
    }
    return result;
  }

  /// `@PostConstruct` / `@PreDestroy` method names; superclass methods
  /// first for init, last for destroy (like Spring).
  List<String> _lifecycleMethods(
    InterfaceType type,
    TypeChecker checker, {
    required bool superFirst,
  }) {
    final hierarchy = [type.element, ..._superclasses(type)];
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
        _rejectAsync(method, 'Lifecycle method $name');
        if (seen.add(name)) {
          result.add(name);
        }
      }
    }
    return result;
  }

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
      name: kind == PointKind.single ? element.name : null,
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
    if (_objectProvider.isExactlyType(type)) {
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
  List<InterfaceType> _exposedTypes(InterfaceType type) => [
    type,
    for (final supertype in type.allSupertypes)
      if (!supertype.isDartCoreObject &&
          _isPublicType(supertype) &&
          !isInternalSdkType(supertype))
        supertype,
  ];

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
    for (final interface in _hierarchy(element.thisType)) {
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

  static Never _fail(String message, Element element) =>
      throw InvalidGenerationSource(message, element: element);
}
