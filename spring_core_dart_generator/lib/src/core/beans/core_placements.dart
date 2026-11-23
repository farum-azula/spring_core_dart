import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/annotation_placement.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';

// Where the container's own annotations may go, declared as a part
// declares its own (PackageGeneration.placements); they are asked after
// the parts', so a part's narrower placement of a method annotation wins.

TypeChecker _spring(String name) =>
    TypeChecker.typeNamedLiterally(name, inPackage: 'spring_core_dart');

final TypeChecker _beanMethodAnnotation = _spring('BeanMethodAnnotation');
final TypeChecker _proxyTargetClass = _spring('ProxyTargetClass');
final TypeChecker _bean = _spring('Bean');
final TypeChecker _eventListener = _spring('EventListener');
final TypeChecker _autowired = _spring('Autowired');
final TypeChecker _resource = _spring('Resource');
final TypeChecker _value = _spring('Value');
final TypeChecker _validated = _spring('Validated');
final TypeChecker _aspect = _spring('Aspect');
final TypeChecker _lookup = _spring('Lookup');
final TypeChecker _condition = _spring('Condition');
final TypeChecker _configurable = _spring('Configurable');
final TypeChecker _introspected = _spring('Introspected');

final List<TypeChecker> _injection = [_autowired, _resource, _value];

/// The core's placements: the advice of `@Observed` and `@Validated`, the
/// methods the container calls (lifecycle, listeners, every
/// `@BeanMethodAnnotation` no part places itself), the injection
/// annotations, the definition annotations of a class or `@Bean` method,
/// `@Log`, `@Introspected` and the aspects' annotations.
final List<AnnotationPlacement> corePlacements = [
  AdvicePlacement([
    _spring('Observed'),
  ], effect: 'no observation would be recorded'),
  // Spring Boot's binding of a third-party class: on a class, or on the
  // @Bean method that returns it. It implements `Introspected`, so it comes
  // before the placement of that annotation.
  const _ConfigurationPropertiesPlacement(),
  const _ValidatedPlacement(),
  MethodPlacement(
    [_eventListener, _spring('Async')],
    does: 'the context calls it with each event it listens to',
  ),
  MethodPlacement(
    [_spring('PostConstruct'), _spring('PreDestroy')],
    does: 'the container calls it when the bean starts or stops',
  ),
  const _InjectionPlacement(),
  const _ValuePlacement(),
  const _QualifierPlacement(),
  const _LazyPlacement(),
  const _OrderPlacement(),
  _DefinitionPlacement([
    _spring('Scope'),
    _spring('Primary'),
    _spring('Fallback'),
    _spring('DependsOn'),
    _spring('Description'),
    _spring('Profile'),
    _spring('Conditional'),
  ], beanMethods: true),
  const _ConditionPlacement(),
  _DefinitionPlacement(
    [_spring('Import'), _spring('PropertySource')],
    beanOwner: PlacementOwner.componentItself,
    instead: 'Put it on a @Configuration or @Component class',
  ),
  _ConfigurablePlacement([_configurable]),
  _ComponentScanPlacement([_spring('ComponentScan')]),
  _StereotypePlacement([_component]),
  _LookupPlacement([_lookup]),
  _PointcutPlacement([_spring('Pointcut')]),
  ClassPlacement(
    [_spring('Log')],
    instead:
        'The `log` getter is generated for classes; put it on a class (one '
        'that mixes the mixin in, for a mixin)',
  ),
  ClassPlacement([_spring('Introspected')]),
  const _AspectPlacement(),
  MethodPlacement(
    [
      _spring('Around'),
      _spring('Before'),
      _spring('After'),
      _spring('AfterReturning'),
      _spring('AfterThrowing'),
    ],
    does: 'the aspect runs it around the methods its pointcut matches',
    methodOwner: AnnotatedOwner([_aspect]),
    ownerNoun: '@Aspect class',
    ownerFix: '@Aspect()',
  ),
  const _ConstraintPlacement(),
  const _JsonMemberPlacement(),
  const _JsonClassPlacement(),
  const _BeanMethodAnnotationPlacement(),
];

// `@Validated`: advice on the class, method validation's groups on a
// method of a validated class, the validation of an argument on a
// parameter (a web body).
final class _ValidatedPlacement extends AnnotationPlacement {
  const _ValidatedPlacement();

  static final _advice = AdvicePlacement([
    _validated,
  ], effect: 'the arguments would not be checked');

  @override
  bool covers(InterfaceType type) => _validated.isExactlyType(type);

  @override
  bool get isAdvice => true;

  @override
  String? problem(AnnotationSite site) {
    // On a parameter it validates a web body; with @ConfigurationProperties
    // on a @Bean method it validates the values bound to the result.
    if (site.kind == PlaceKind.parameter ||
        (site.kind == PlaceKind.method &&
            site.has([_bean]) &&
            site.has([_configurationProperties]))) {
      return null;
    }
    return _advice.problem(site);
  }

  @override
  bool get checksBases => true;

  @override
  String? generatedBeanProblem(AnnotationSite site) {
    final owner = site.owner;
    return site.kind == PlaceKind.classDeclaration ||
            owner is! InterfaceElement ||
            _validatedInHierarchy(owner)
        ? null
        : '@Validated on ${site.subject}: method validation runs on classes '
              'with @Validated(), and ${site.ownerName} has none. Add '
              '@Validated() to ${site.ownerName}, or remove it.';
  }

  // A method's groups count on a class with `@Validated`, or on a base of
  // one (`Books extends BaseCatalog`, `@Validated` on `Books`).
  @override
  PlacementOwner? owner(AnnotationSite site) => switch (site.kind) {
    PlaceKind.parameter when _readsItsArguments(site) => null,
    PlaceKind.method when site.has([_bean]) => null,
    PlaceKind.parameter ||
    PlaceKind.method ||
    PlaceKind.getter ||
    PlaceKind.setter => const PredicateOwner(_isValidatedClass),
    _ => PlacementOwner.bean,
  };

  // A method the framework calls (a web handler validates its body) or the
  // abstract method of an interface whose implementation is generated.
  static bool _readsItsArguments(AnnotationSite site) {
    final executable = site.executable;
    return executable == null ||
        executable is ConstructorElement ||
        executable.isAbstract ||
        calledByFramework(executable);
  }

  @override
  String ownerProblem(AnnotationSite site) =>
      const {
        PlaceKind.method,
        PlaceKind.getter,
        PlaceKind.setter,
        PlaceKind.parameter,
      }.contains(site.kind)
      ? '@Validated on ${site.kind == PlaceKind.method ? 'the method ' : ''}'
            '${site.subject}: method validation runs on '
            'classes with @Validated(), as in Spring (a method-level '
            '@Validated only picks the groups). Add @Validated() to '
            '${site.ownerName}.'
      : _advice.ownerProblem(site);
}

bool _isValidatedClass(ClassElement element, ModuleModel module) =>
    _validatedInHierarchy(element);

bool _validatedInHierarchy(InterfaceElement element) =>
    _validated.hasAnnotationOf(element) ||
    element.allSupertypes.any(
      (type) => _validated.hasAnnotationOf(type.element),
    );

// `@Autowired`, `@Inject`, `@Resource`: a constructor, an instance field
// or setter, an instance method of a bean (or of a `@Configurable`
// class).
final class _InjectionPlacement extends AnnotationPlacement {
  const _InjectionPlacement();

  @override
  bool covers(InterfaceType type) =>
      _autowired.isAssignableFromType(type) ||
      (_resource.isExactlyType(type) && type.element is ClassElement);

  @override
  String? problem(AnnotationSite site) {
    final what = site.name;
    final subject = site.subject;
    return switch (site.kind) {
      PlaceKind.topLevel || PlaceKind.foreignMember =>
        '$what on $subject: only the members of a bean are injected. Move '
            'it into a component class, or read the bean from the context.',
      PlaceKind.parameter when site.executable is ConstructorElement =>
        '$what on $subject: a constructor parameter is injected anyway (as '
            'in Spring, the annotation there is ignored). Remove it, or put '
            'it on the constructor to choose it.',
      PlaceKind.parameter =>
        '$what on $subject: it goes on the method, the field or the setter '
            'to inject.',
      PlaceKind.getter =>
        '$what on $subject: a getter cannot receive a bean. Annotate the '
            'field or a setter.',
      PlaceKind.field || PlaceKind.setter || PlaceKind.method
          when site.isStatic =>
        '$what on $subject: a static member is not injected (Spring '
            'ignores it too). Make it an instance member.',
      PlaceKind.operator =>
        '$what on $subject: it goes on a field, a setter or a method.',
      PlaceKind.method
          when _resource.isExactlyType(site.annotationType) &&
              (site.has([_bean]) ||
                  (site.element as MethodElement).formalParameters.length !=
                      1) =>
        '@Resource on $subject: it injects the one parameter of a method (as '
            'in Jakarta), and a @Bean method makes a bean instead of receiving '
            'one. Annotate a method with one parameter, or a field.',
      PlaceKind.mixin ||
      PlaceKind.enumDeclaration ||
      PlaceKind.extension ||
      PlaceKind.extensionType ||
      PlaceKind.classDeclaration =>
        '$what on $subject: it goes on a constructor, a field, a setter or '
            'a method.',
      _ => null,
    };
  }

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      site.owner != null && _configurable.hasAnnotationOf(site.owner!)
      ? null
      : PlacementOwner.bean;

  @override
  String? generatedBeanProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}: the build writes the implementation '
      'of ${site.ownerName}, and nothing is injected into its methods. '
      'Remove ${site.name}.';

  @override
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}, and ${site.ownerName} is no bean '
      '(no @Component or @Service, no @Bean method of the module returns '
      'it, and it is no @Configurable class), so nothing injects it. Add '
      '@Component() to ${site.ownerName}, return it from a @Bean method, or '
      'make it abstract when it is only a base of beans.';
}

// `@Qualifier` and `@Named`: a class, a `@Bean` method, a parameter, an
// injected field or setter.
final class _QualifierPlacement extends AnnotationPlacement {
  const _QualifierPlacement();

  static final _named = _spring('Named');
  static final _qualifier = _spring('Qualifier');

  @override
  bool covers(InterfaceType type) =>
      _qualifier.isAssignableFromType(type) || _named.isExactlyType(type);

  @override
  String? problem(AnnotationSite site) =>
      _injectionPointProblem(site, 'chooses the bean to inject');

  @override
  PlacementOwner? owner(AnnotationSite site) => _injectionPointOwner(site);

  @override
  String ownerProblem(AnnotationSite site) => _injectionPointOwnerProblem(site);
}

// `@Lazy`: a class, a `@Bean` method, an injection point.
final class _LazyPlacement extends AnnotationPlacement {
  const _LazyPlacement();

  static final _lazy = _spring('Lazy');

  @override
  bool covers(InterfaceType type) => _lazy.isExactlyType(type);

  @override
  String? problem(AnnotationSite site) =>
      _injectionPointProblem(site, 'makes the bean or the injection lazy');

  @override
  PlacementOwner? owner(AnnotationSite site) => _injectionPointOwner(site);

  @override
  String ownerProblem(AnnotationSite site) => _injectionPointOwnerProblem(site);
}

String? _injectionPointProblem(AnnotationSite site, String does) {
  final what = site.name;
  final subject = site.subject;
  return switch (site.kind) {
    PlaceKind.classDeclaration => null,
    PlaceKind.parameter when _isInjectedParameter(site) => null,
    PlaceKind.parameter =>
      '$what on $subject: only the parameters of a bean\'s constructor, of '
          'a @Bean method and of an @Autowired method are injected, and '
          'nothing passes this one. Annotate the method, or remove $what.',
    PlaceKind.method when site.has([_bean, _autowired, _lookup]) => null,
    PlaceKind.field || PlaceKind.setter when site.has(_injection) => null,
    PlaceKind.field || PlaceKind.setter =>
      '$what on $subject: only an @Autowired (or @Inject, @Resource) member '
          'is injected, so it would never get a bean (Spring leaves it null '
          'too). Add @Autowired().',
    _ =>
      '$what on $subject: it $does on a class, a @Bean method, an injected '
          'field, setter or method, or a parameter; here it would do '
          'nothing.',
  };
}

// Whether the container passes the parameter of [site]: a constructor's
// (the class is checked to be a bean), a `@Bean` or `@Autowired` method's,
// one the framework calls, or an abstract method's, whose implementation
// says.
bool _isInjectedParameter(AnnotationSite site) {
  final executable = site.executable;
  return executable != null &&
      (executable is ConstructorElement ||
          executable.isAbstract ||
          calledByFramework(executable) ||
          site.has([_bean, ..._injection], on: executable));
}

PlacementOwner? _injectionPointOwner(AnnotationSite site) =>
    switch (site.kind) {
      PlaceKind.classDeclaration => PlacementOwner.beanItself,
      PlaceKind.parameter when site.executable is ConstructorElement =>
        PlacementOwner.bean,
      _ => null,
    };

String _injectionPointOwnerProblem(AnnotationSite site) =>
    site.kind == PlaceKind.classDeclaration
    ? _notABeanProblem(site)
    : '${site.name} on ${site.subject}, and ${site.ownerName} is no bean (no '
          '@Component or @Service, and no @Bean method of the module returns '
          'it), so the container never calls this constructor. Add '
          '@Component() to ${site.ownerName}, or remove ${site.name}.';

// A definition annotation on a class that is no bean itself: the generator
// reads it on the bean's own class (or `@Bean` method), and a subclass
// does not inherit it.
String _notABeanProblem(AnnotationSite site) {
  final name = site.element.displayName;
  final abstract = switch (site.element) {
    ClassElement(:final isAbstract, :final isSealed) => isAbstract || isSealed,
    _ => false,
  };
  final composes = switch (site.element) {
    ClassElement(:final constructors) => constructors.any(
      (constructor) => constructor.isConst && !constructor.isFactory,
    ),
    _ => false,
  };
  if (composes && !abstract) {
    return '${site.name} on class $name, which is no bean: an annotation '
        'passes nothing on to the classes it marks. To compose it, write '
        '`class $name extends ${site.annotationType.element.name}`.';
  }
  return abstract
      ? '${site.name} on abstract class $name: it is read on the class of a '
            'bean and a subclass does not inherit it, so it would do nothing. '
            'Put ${site.name} on each concrete bean class.'
      : '${site.name} on class $name, which is no bean (no @Component or '
            '@Service, and no @Bean method of the module returns it), so it '
            'would do nothing. Add @Component() to $name, or remove '
            '${site.name}.';
}

// A definition annotation (`@Scope`, `@Primary`, `@Profile`, `@Import`):
// as [ClassPlacement], and the class must itself be a bean.
final class _DefinitionPlacement extends ClassPlacement {
  _DefinitionPlacement(
    super.checkers, {
    super.beanMethods,
    super.instead,
    this.beanOwner = PlacementOwner.beanItself,
  });

  final PlacementOwner beanOwner;

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      site.kind == PlaceKind.classDeclaration ? beanOwner : null;

  @override
  String ownerProblem(AnnotationSite site) => _notABeanProblem(site);
}

// `@Configurable`: a class created outside the container. The configurer
// is found by the exact class of the instance, so an abstract class never
// gets one.
final class _ConfigurablePlacement extends ClassPlacement {
  _ConfigurablePlacement(super.checkers);

  @override
  String? problem(AnnotationSite site) {
    if (super.problem(site) case final problem?) {
      return problem;
    }
    return switch (site.element) {
      ClassElement(isAbstract: true) || ClassElement(isSealed: true) =>
        '@Configurable on ${site.subject}: the container finds the injection '
            'by the exact class of the object, so a subclass does not inherit '
            'it. Put @Configurable() on each concrete class.',
      _ => null,
    };
  }
}

// `@ComponentScan`: the top-level variable of a scan root. On a class the
// builder answers itself.
final class _ComponentScanPlacement extends CheckedPlacement {
  _ComponentScanPlacement(super.checkers);

  @override
  String? problem(AnnotationSite site) => switch (site.kind) {
    PlaceKind.classDeclaration => null,
    PlaceKind.topLevel when site.element is TopLevelVariableElement => null,
    _ =>
      '@ComponentScan on ${site.subject}: a scan root is a public top-level '
          'variable (`@ComponentScan() const beans = _Beans();`); here it '
          'would scan nothing.',
  };

  @override
  String? generatedBeanProblem(AnnotationSite site) =>
      '@ComponentScan on ${site.subject}: a scan root is a public top-level '
      'variable; on this interface it would scan nothing.';
}

// A stereotype (`@Component`, `@Service`, `@Configuration`) on a member or
// at the top level: only a class is scanned. On a mixin, an enum or an
// extension the scanner answers itself.
final class _StereotypePlacement extends ClassPlacement {
  _StereotypePlacement(super.checkers)
    : super(instead: 'Annotate the class, or declare a @Bean method');

  static final _configuration = _spring('Configuration');

  @override
  String? problem(AnnotationSite site) => switch (site.kind) {
    PlaceKind.mixin ||
    PlaceKind.enumDeclaration ||
    PlaceKind.extension ||
    PlaceKind.extensionType => null,
    _ => super.problem(site),
  };

  @override
  String? generatedBeanProblem(AnnotationSite site) =>
      site.kind == PlaceKind.classDeclaration &&
          _configuration.isAssignableFromType(site.annotationType)
      ? '${site.name} on ${site.subject}: the build writes its '
            'implementation, so it cannot declare @Bean methods. Move them '
            'into a @Configuration class of their own.'
      : null;
}

// `@Lookup`: a method of a component, or of a base of one, which the
// container overrides. It cannot override it on the result of a `@Bean`
// method, which the method itself creates.
final class _LookupPlacement extends CheckedPlacement {
  _LookupPlacement(super.checkers);

  @override
  String? problem(AnnotationSite site) => null;

  @override
  PlacementOwner? owner(AnnotationSite site) => AnnotatedOwner([_component]);

  @override
  String ownerProblem(AnnotationSite site) =>
      '@Lookup on ${site.subject}: the container implements it in a subclass '
      'of a component, and ${site.ownerName} is none (a class a @Bean method '
      'returns is created by that method). Add @Component() to '
      '${site.ownerName}, or read the bean from the context.';
}

// `@Pointcut`: a method of an aspect, private ones too, as in Spring.
final class _PointcutPlacement extends CheckedPlacement {
  _PointcutPlacement(super.checkers);

  @override
  String? problem(AnnotationSite site) => site.kind == PlaceKind.method
      ? null
      : '@Pointcut on ${site.subject}: it names a pointcut on a method of an '
            '@Aspect class.';

  @override
  PlacementOwner? owner(AnnotationSite site) => AnnotatedOwner([_aspect]);

  @override
  String ownerProblem(AnnotationSite site) =>
      '@Pointcut on ${site.subject}: ${site.ownerName} is no @Aspect class, '
      'and only an aspect\'s advice reads a pointcut. Add @Aspect() to '
      '${site.ownerName}, or move the method into one.';
}

// `@Value`: an instance field or setter of a bean, a parameter the
// container passes, or an @Autowired method.
final class _ValuePlacement extends AnnotationPlacement {
  const _ValuePlacement();

  @override
  bool covers(InterfaceType type) => _value.isExactlyType(type);

  @override
  String? problem(AnnotationSite site) {
    final subject = site.subject;
    return switch (site.kind) {
      PlaceKind.parameter when _isInjectedParameter(site) => null,
      PlaceKind.parameter =>
        '@Value on $subject: only the parameters of a bean\'s constructor, '
            'of a @Bean method and of an @Autowired method get a value. '
            'Annotate the method, or remove @Value.',
      PlaceKind.field || PlaceKind.setter when site.isStatic =>
        '@Value on $subject: a static member is not injected (Spring ignores '
            'it too). Make it an instance member.',
      PlaceKind.field || PlaceKind.setter => null,
      PlaceKind.method when site.has([_autowired]) => null,
      _ =>
        '@Value on $subject: it goes on a field or setter of a bean, or on a '
            'parameter of its constructor or of a @Bean method; here nothing '
            'would set it.',
    };
  }

  @override
  PlacementOwner? owner(AnnotationSite site) => switch (site.kind) {
    PlaceKind.field || PlaceKind.setter
        when site.owner != null &&
            (_configurable.hasAnnotationOf(site.owner!) ||
                _introspected.hasAnnotationOf(site.owner!)) =>
      null,
    PlaceKind.field || PlaceKind.setter => PlacementOwner.bean,
    PlaceKind.parameter when site.executable is ConstructorElement =>
      PlacementOwner.bean,
    _ => null,
  };

  @override
  String ownerProblem(AnnotationSite site) =>
      '@Value on ${site.subject}, and ${site.ownerName} is no bean (no '
      '@Component or @Service, and no @Bean method of the module returns '
      'it), so nothing sets it. Add @Component() to ${site.ownerName}, return '
      'it from a @Bean method, or make it abstract when it is only a base of '
      'beans.';
}

// `@Order`: a class, a `@Bean` method, an `@EventListener` method, an
// injection point is not ordered.
final class _OrderPlacement extends AnnotationPlacement {
  const _OrderPlacement();

  static final _order = _spring('Order');

  @override
  bool covers(InterfaceType type) => _order.isExactlyType(type);

  @override
  String? problem(AnnotationSite site) => switch (site.kind) {
    PlaceKind.classDeclaration => null,
    PlaceKind.method when site.has([_bean, _eventListener]) => null,
    _ =>
      '@Order on ${site.subject}: it orders a bean (on its class or @Bean '
          'method) or an @EventListener method; here it would do nothing.',
  };

  // A `@Bean` method reads `@Order` from the class it returns, in another
  // package too.
  @override
  PlacementOwner? owner(AnnotationSite site) =>
      site.kind == PlaceKind.classDeclaration
      ? PlacementOwner.beanItselfOrExported
      : null;

  @override
  String ownerProblem(AnnotationSite site) => _notABeanProblem(site);
}

// A condition annotation (`@ConditionalOnProperty`, a class implementing
// `Condition` used as one): a class or a `@Bean` method.
final class _ConditionPlacement extends AnnotationPlacement {
  const _ConditionPlacement();

  static final _classes = ClassPlacement([_condition], beanMethods: true);

  @override
  bool covers(InterfaceType type) =>
      _condition.isAssignableFromType(type) && type.element is ClassElement;

  @override
  String? problem(AnnotationSite site) => _classes.problem(site);

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      site.kind == PlaceKind.classDeclaration
      ? PlacementOwner.beanItself
      : null;

  @override
  String ownerProblem(AnnotationSite site) => _notABeanProblem(site);
}

// `@Aspect`: a class that is a bean (with `@Component`, or returned by a
// `@Bean` method), as `@Aspect` is no stereotype.
final class _AspectPlacement extends AnnotationPlacement {
  const _AspectPlacement();

  static final _classes = ClassPlacement([_aspect]);

  @override
  bool covers(InterfaceType type) => _aspect.isExactlyType(type);

  @override
  String? problem(AnnotationSite site) => _classes.problem(site);

  @override
  PlacementOwner? owner(AnnotationSite site) => PlacementOwner.beanItself;

  @override
  String ownerProblem(AnnotationSite site) =>
      '@Aspect on ${site.element.displayName}: an aspect must be a bean, '
      'and a subclass does not inherit @Aspect (@Aspect is no '
      'stereotype, as in Spring). Add @Component(), or return it from a @Bean '
      'method; on a base class, put @Aspect() on the concrete class.';

  @override
  String? generatedBeanProblem(AnnotationSite site) =>
      '@Aspect on ${site.subject}: the build writes its implementation, so '
      'it cannot hold advice. Put @Aspect() on a @Component class.';
}

// Every annotation marked `@BeanMethodAnnotation()` that no part places
// itself (`@Scheduled`, an application's own): a public instance method of
// a bean. Those marked `@ProxyTargetClass()` have checks of their own.
final class _BeanMethodAnnotationPlacement extends AnnotationPlacement {
  const _BeanMethodAnnotationPlacement();

  static final _method = MethodPlacement(
    const [],
    does: 'the framework calls it',
  );

  @override
  bool covers(InterfaceType type) =>
      _beanMethodAnnotation.hasAnnotationOf(type.element) &&
      !_proxyTargetClass.hasAnnotationOf(type.element);

  // On the class it may say something of every method (an application's
  // own annotation decides).
  @override
  String? problem(AnnotationSite site) =>
      site.kind == PlaceKind.classDeclaration ? null : _method.problem(site);

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      site.kind == PlaceKind.classDeclaration ? null : PlacementOwner.bean;

  @override
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}, and ${site.ownerName} is no bean '
      '(no @Component or @Service, and no @Bean method of the module '
      'returns it), so nothing calls it. Add @Component() to '
      '${site.ownerName}, return it from a @Bean method, or make it '
      'abstract when it is only a base of beans.';
}

final TypeChecker _constraint = _spring('Constraint');
final TypeChecker _valid = _spring('Valid');
final TypeChecker _component = _spring('Component');
const TypeChecker _configurationPropertiesConst =
    TypeChecker.typeNamedLiterally(
      'ConfigurationProperties',
      inPackage: 'spring_core_dart',
    );
final TypeChecker _configurationProperties = _configurationPropertiesConst;

// A constraint (`@NotBlank`) or `@Valid`: on a stored field of a class the
// validator reads, on a parameter or the result of a method of a validated
// bean. Where nothing checks it, Spring is silent too; the build says
// what to add.
final class _ConstraintPlacement extends AnnotationPlacement {
  const _ConstraintPlacement();

  @override
  bool covers(InterfaceType type) =>
      _constraint.isAssignableFromType(type) || _valid.isExactlyType(type);

  @override
  String? problem(AnnotationSite site) {
    final what = '${site.name} on ${site.subject}';
    final owner = site.owner;
    switch (site.kind) {
      case PlaceKind.topLevel || PlaceKind.foreignMember:
        return '$what: constraints are read on the fields of a class, and '
            'on the parameters of a validated bean\'s methods; here nothing '
            'would check it.';
      case PlaceKind.field || PlaceKind.parameter
          when _valid.isExactlyType(site.annotationType) &&
              _isScalar(site.element):
        return '$what: @Valid checks the constraints of the object inside, '
            'and this type has none. Use a constraint (@NotBlank, @Min...), '
            'or remove @Valid.';
      case PlaceKind.field when site.isStatic || site.isPrivate:
        return '$what: a ${site.isStatic ? 'static' : 'private'} field is '
            'not described, so the validator never checks it. Make it a '
            'public instance field.';
      case PlaceKind.field
          when owner is InterfaceElement &&
              _configurationProperties.hasAnnotationOf(owner) &&
              !_validatedInHierarchy(owner):
        return '$what: the values of a @ConfigurationProperties class are '
            'checked when it has @Validated() (as in Spring Boot). Add '
            '@Validated() to ${site.ownerName}.';
      default:
        return null;
    }
  }

  // A parameter of a component's method the framework does not call is
  // checked by method validation: on a class with `@Validated`, or on a
  // base of one.
  @override
  PlacementOwner? owner(AnnotationSite site) {
    final executable = site.executable;
    final owner = site.owner;
    if (site.kind != PlaceKind.parameter ||
        executable == null ||
        executable is ConstructorElement ||
        executable.isAbstract ||
        executable.isStatic ||
        owner is! ClassElement ||
        !_component.hasAnnotationOf(owner) ||
        executable.metadata.annotations.any((annotation) {
          final element = annotation.computeConstantValue()?.type?.element;
          return element != null &&
              _beanMethodAnnotation.hasAnnotationOf(element);
        })) {
      return null;
    }
    return const PredicateOwner(_isValidatedClass);
  }

  @override
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}: method validation runs on beans with '
      '@Validated() (as in Spring), and ${site.ownerName} has none, so the '
      'argument would not be checked. Add @Validated() to ${site.ownerName}.';
}

bool _isScalar(Element element) {
  final type = switch (element) {
    final FieldElement field => field.type,
    final FormalParameterElement parameter => parameter.type,
    _ => null,
  };
  return type != null &&
      (type.isDartCoreString ||
          type.isDartCoreInt ||
          type.isDartCoreDouble ||
          type.isDartCoreNum ||
          type.isDartCoreBool);
}

// `@ConfigurationProperties`: as a class annotation, on a class with
// something to bind (a constructor parameter, a settable field or setter,
// or a final field holding an object bound in place).
final class _ConfigurationPropertiesPlacement extends ClassPlacement {
  const _ConfigurationPropertiesPlacement()
    : super(const [_configurationPropertiesConst], beanMethods: true);

  @override
  String? problem(AnnotationSite site) {
    if (super.problem(site) case final problem?) {
      return problem;
    }
    return switch (site.element) {
      final ClassElement element when !_hasBindable(element) =>
        '@ConfigurationProperties on ${site.subject}: it has nothing to bind '
            '(no constructor parameter, public settable field or setter), so '
            'every value would be ignored. Add a public field or a '
            'constructor parameter.',
      _ => null,
    };
  }

  @override
  String? generatedBeanProblem(AnnotationSite site) =>
      '@ConfigurationProperties on ${site.subject}: the build writes its '
      'implementation, so no value can be bound to it. Bind a class of its '
      'own.';

  static bool _hasBindable(ClassElement element) {
    if (element.isAbstract ||
        element.constructors.any((c) => c.formalParameters.isNotEmpty)) {
      return true;
    }
    final classes = <InterfaceElement>[
      element,
      for (final type in element.allSupertypes)
        if (!type.isDartCoreObject) type.element,
    ];
    return classes.any(
      (current) =>
          current.setters.any((s) => s.isPublic && !s.isStatic) ||
          current.fields.any(
            (field) =>
                field.isOriginDeclaration &&
                field.isPublic &&
                !field.isStatic &&
                !(field.isFinal && _isScalar(field)),
          ),
    );
  }
}

// The JSON annotations of a class: the description lists those of the
// class itself, so on a mixin nothing reads them.
final class _JsonClassPlacement extends AnnotationPlacement {
  const _JsonClassPlacement();

  static final _classLevel = [
    for (final name in const [
      'JsonNaming',
      'JsonInclude',
      'JsonPropertyOrder',
      'JsonIgnoreProperties',
      'JsonTypeInfo',
      'JsonSubTypes',
      'JsonTypeName',
    ])
      _spring(name),
  ];

  @override
  bool covers(InterfaceType type) =>
      _classLevel.any((checker) => checker.isExactlyType(type));

  @override
  String? problem(AnnotationSite site) => site.kind == PlaceKind.mixin
      ? '${site.name} on ${site.subject}: the ObjectMapper reads it on the '
            'class it describes, not on a mixin. Put it on the class that '
            'mixes ${site.element.displayName} in.'
      : null;
}

final List<TypeChecker> _jsonMembers = [
  for (final name in const [
    'JsonProperty',
    'JsonIgnore',
    'JsonAlias',
    'JsonFormat',
    'JsonUnwrapped',
    'JsonView',
    'JsonAnyGetter',
    'JsonAnySetter',
    'JsonValue',
  ])
    _spring(name),
];
final TypeChecker _jsonCreator = _spring('JsonCreator');
final List<TypeChecker> _jsonOnMethods = [
  _spring('JsonValue'),
  _spring('JsonAnyGetter'),
  _spring('JsonAnySetter'),
];

bool _hasSetter(AnnotationSite site) {
  final owner = site.owner;
  return owner is InterfaceElement &&
      owner.thisType.lookUpSetter(site.element.displayName, owner.library) !=
          null;
}

// The JSON annotations of a class's members: the `ObjectMapper` reads the
// public instance members a class's description lists, and a creator is a
// constructor; elsewhere it would never see them.
final class _JsonMemberPlacement extends AnnotationPlacement {
  const _JsonMemberPlacement();

  @override
  bool covers(InterfaceType type) =>
      _jsonCreator.isExactlyType(type) ||
      _jsonMembers.any((checker) => checker.isExactlyType(type));

  @override
  String? problem(AnnotationSite site) {
    final what = '${site.name} on ${site.subject}';
    if (_jsonCreator.isExactlyType(site.annotationType)) {
      return site.kind == PlaceKind.constructor
          ? null
          : '$what: only a constructor (a factory one too) can be a creator '
                'here; write a factory constructor and annotate that.';
    }
    if (site.kind == PlaceKind.method &&
        !_jsonOnMethods.any(
          (checker) => checker.isExactlyType(site.annotationType),
        )) {
      return '$what: the ObjectMapper reads this annotation on a field, a '
          'getter or a setter, not on a method. Move it there.';
    }
    if (site.kind == PlaceKind.getter &&
        _spring('JsonAlias').isExactlyType(site.annotationType) &&
        !_hasSetter(site)) {
      return '$what: an alias is a name accepted when reading JSON, and a '
          'getter without a setter is never read in. Put it on a field or a '
          'setter.';
    }
    final member =
        site.kind == PlaceKind.field ||
        site.kind == PlaceKind.getter ||
        site.kind == PlaceKind.setter ||
        site.kind == PlaceKind.method;
    if (member && (site.isStatic || site.isPrivate)) {
      return '$what: the ObjectMapper reads and writes the public instance '
          'members of a class, so a ${site.isStatic ? 'static' : 'private'} '
          'one is never seen. Make it a public instance member.';
    }
    return null;
  }
}
