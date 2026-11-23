import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';

/// What kind of declaration an annotation is on.
enum PlaceKind {
  /// A class.
  classDeclaration,

  /// A mixin.
  mixin,

  /// An enum.
  enumDeclaration,

  /// An extension.
  extension,

  /// An extension type.
  extensionType,

  /// A top-level function, variable, getter or setter.
  topLevel,

  /// A member of an enum, an extension or an extension type.
  foreignMember,

  /// A constructor.
  constructor,

  /// A method that is no operator.
  method,

  /// An operator.
  operator,

  /// A getter written as one.
  getter,

  /// A setter written as one.
  setter,

  /// A field.
  field,

  /// A parameter of a method, constructor, setter or function.
  parameter,

  /// A value of an enum; only a declared `@Target` is checked here.
  enumValue,

  /// A typedef; only a declared `@Target` is checked here.
  typedefDeclaration,

  /// A type parameter; only a declared `@Target` is checked here.
  typeParameter,

  /// The library; only a declared `@Target` is checked here.
  library,
}

String _withoutNew(String name) => name.replaceFirst(RegExp(r'\.new$'), '');

/// One annotation where the build found it: the declaration, what kind of
/// declaration it is, and the class or mixin around it.
final class AnnotationSite {
  /// [annotation] (of [annotationType]) on [element], a [kind].
  AnnotationSite({
    required this.element,
    required this.annotation,
    required this.annotationType,
    required this.kind,
    this.owner,
    this.place,
    this.executable,
  });

  /// The annotated declaration.
  final Element element;

  /// The annotation's value.
  final DartObject annotation;

  /// The annotation's class.
  final InterfaceType annotationType;

  /// What [element] is.
  final PlaceKind kind;

  /// The class, mixin, enum or extension around [element] (for a
  /// parameter, around its method); `null` at the top level.
  final InstanceElement? owner;

  /// Where a member outside a class is, for messages: `the enum Mode`,
  /// `the top level of package:app/src/jobs.dart`.
  final String? place;

  /// For a parameter: the method, constructor or function it belongs to.
  final ExecutableElement? executable;

  /// `@Transactional`.
  String get name => '@${annotationType.element.name}';

  /// The owner's name (`Orders`), or the empty text.
  String get ownerName =>
      owner?.displayName ??
      (kind == PlaceKind.classDeclaration ? element.displayName : '');

  /// The annotated declaration as messages name it: `Orders.save`, `the
  /// getter Orders.total`, `parameter id of Api.find`, `migrate, in the
  /// top level of ...`.
  String get subject {
    final member = '$ownerName.${element.displayName}';
    final parameterOwner = switch (executable) {
      final ConstructorElement constructor =>
        'the constructor ${_withoutNew(constructor.displayName)}',
      final ExecutableElement method
          when method.enclosingElement is InstanceElement =>
        '$ownerName.${method.displayName}',
      _ => '${executable?.displayName}',
    };
    return switch (kind) {
      PlaceKind.classDeclaration => 'class ${element.displayName}',
      PlaceKind.mixin => 'mixin ${element.displayName}',
      PlaceKind.enumDeclaration => 'enum ${element.displayName}',
      PlaceKind.extension => 'extension ${element.displayName}',
      PlaceKind.extensionType => 'extension type ${element.displayName}',
      PlaceKind.topLevel ||
      PlaceKind.foreignMember => '${element.displayName}, in $place',
      PlaceKind.constructor =>
        'the constructor ${_withoutNew(element.displayName)}',
      PlaceKind.method => member,
      PlaceKind.operator => 'the operator $member',
      PlaceKind.getter => 'the getter $member',
      PlaceKind.setter => 'the setter $member',
      PlaceKind.field => 'the field $member',
      PlaceKind.parameter =>
        'parameter ${element.displayName} of '
            '$parameterOwner',
      PlaceKind.enumValue => 'the enum value $member',
      PlaceKind.typedefDeclaration => 'typedef ${element.displayName}',
      PlaceKind.typeParameter => 'type parameter ${element.displayName}',
      PlaceKind.library => 'the library ${element.library?.uri}',
    };
  }

  /// The declaration an error points at: [element], or for an unnamed
  /// constructor, which has no name of its own to point at, its class.
  Element get location => switch (element) {
    ConstructorElement(name: 'new' || null) when owner != null => owner!,
    _ => element,
  };

  /// Whether [element] is private.
  bool get isPrivate => element.isPrivate;

  /// Whether [element] is a static member.
  bool get isStatic => switch (element) {
    final ExecutableElement executable => executable.isStatic,
    final FieldElement field => field.isStatic,
    _ => false,
  };

  /// Whether the owner is a class that can be created (no mixin, no
  /// abstract class): one that must itself be what a placement asks.
  bool get ownerIsConcreteClass => switch (owner) {
    ClassElement(isAbstract: false, isSealed: false) => true,
    _ => false,
  };

  /// Whether [element] (for a parameter: its method) carries an
  /// annotation one of [checkers] matches.
  bool has(List<TypeChecker> checkers, {Element? on}) {
    final target = on ?? element;
    return checkers.any((checker) => checker.hasAnnotationOf(target));
  }

  /// Whether the owner carries an annotation one of [checkers] matches.
  bool ownerHas(List<TypeChecker> checkers) {
    final owner = this.owner;
    return owner != null &&
        checkers.any((checker) => checker.hasAnnotationOf(owner));
  }
}

/// What the class around an annotation must be, which the build knows only
/// once every library of the module is scanned: a bean, or a class with one
/// of some annotations (a controller). A class that can be created and is
/// neither it nor a base of one fails the build; an abstract class or a
/// mixin may be the base of one in another module, and is not checked.
sealed class PlacementOwner {
  const PlacementOwner();

  /// A bean of the module, or a base of one.
  static const PlacementOwner bean = BeanOwner._();

  /// The class itself is a bean of the module: what is read from the
  /// definition of a bean is not inherited from a base.
  static const PlacementOwner beanItself = BeanItselfOwner._(products: true);

  /// As [beanItself], or a class the package exports: a `@Bean` method of
  /// another package may return it, and what it reads there counts.
  static const PlacementOwner beanItselfOrExported = BeanItselfOwner._(
    products: true,
    exported: true,
  );

  /// The class itself is a component of the module; the class a `@Bean`
  /// method returns is not one.
  static const PlacementOwner componentItself = BeanItselfOwner._(
    products: false,
  );
}

/// A bean of the module, or a base of one ([PlacementOwner.bean]).
final class BeanOwner extends PlacementOwner {
  const BeanOwner._();
}

/// The annotated class itself is a bean ([PlacementOwner.beanItself],
/// [PlacementOwner.componentItself]). An abstract class is checked too, and
/// so is a class with a const constructor: an annotation of the application
/// passes nothing on to the classes it marks. It composes by extending the
/// annotation (`class Dev extends Profile`).
final class BeanItselfOwner extends PlacementOwner {
  const BeanItselfOwner._({required this.products, this.exported = false});

  /// Whether the class a `@Bean` method returns counts.
  final bool products;

  /// Whether a class the package exports counts.
  final bool exported;
}

/// A class of the module that [test] accepts, or a base of one; with
/// [abstractToo] an abstract class is checked too (it must be one of
/// those, or a base of one), not left to another module.
final class PredicateOwner extends PlacementOwner {
  /// The classes [test] accepts.
  const PredicateOwner(this.test, {this.abstractToo = false});

  /// Whether a class of the module is an owner, once the module is
  /// scanned.
  final bool Function(ClassElement element, ModuleModel module) test;

  /// Whether an abstract class around the annotation is checked too.
  final bool abstractToo;
}

/// A class carrying an annotation one of [checkers] matches, or a base of
/// one.
final class AnnotatedOwner extends PlacementOwner {
  /// A class annotated by one of [checkers].
  const AnnotatedOwner(this.checkers);

  /// The class annotations that make a class the owner.
  final List<TypeChecker> checkers;
}

/// Where an annotation may go. A package's part declares one for each of
/// its annotations (`PackageGeneration.placements`), the core for its own;
/// the build walks every declaration of a scanned library once and asks
/// the first placement that [covers] an annotation whether its place is
/// one ([problem]), and, once the module is scanned, whether the class
/// around it is what the annotation needs ([owner]). An annotation no
/// placement covers is not checked.
///
/// The ones below cover what most annotations need: advice the bean's
/// proxy runs ([AdvicePlacement]), a method the framework calls on a bean
/// ([MethodPlacement]), a parameter of such a method
/// ([ParameterPlacement]), a class ([ClassPlacement]). A part writes its
/// own subclass for anything else.
///
/// ```dart
/// @override
/// List<AnnotationPlacement> get placements => const [
///   MethodPlacement([_tick], does: 'the clock calls it every second'),
/// ];
/// ```
abstract base class AnnotationPlacement {
  /// A placement.
  const AnnotationPlacement();

  /// Whether this placement is the one of annotations of [type].
  bool covers(InterfaceType type);

  /// Whether this placement decides [site] (an annotation it [covers]);
  /// when not, the next placement covering it is asked. A part reads
  /// another part's annotation in a place of its own so (the navigation
  /// reads `@PreAuthorize` on a screen).
  bool claims(AnnotationSite site) => true;

  /// What is wrong with [site], with what to change; `null` when the
  /// annotation may be there.
  String? problem(AnnotationSite site);

  /// What the class around [site] must be, checked once the module is
  /// scanned; `null` when it need not be anything.
  PlacementOwner? owner(AnnotationSite site) => null;

  /// The problem when the class around [site] is not its [owner].
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}, and ${site.ownerName} is no bean '
      '(no @Component or @Service, and no @Bean method of the module '
      'returns it), so it would do nothing. Add @Component() to '
      '${site.ownerName}, return it from a @Bean method, or make it '
      'abstract when it is only a base of beans.';

  /// What is wrong with [site] when the class around it is a bean whose
  /// implementation the build generates (an HTTP client, a repository);
  /// `null` when the annotation may be there.
  String? generatedBeanProblem(AnnotationSite site) => null;

  /// Whether an abstract class or a mixin around the annotation is checked
  /// against [owner] when classes of the module extend it: at least one of
  /// them must be the owner.
  bool get checksBases => false;

  /// Whether the annotation is advice the bean's proxy runs around its
  /// members: the build then also fails when the proxy cannot run it (a
  /// bean the container does not proxy, a member the proxy cannot
  /// override).
  bool get isAdvice => false;
}

/// A placement covering the annotations [checkers] match (by their class
/// or a subclass of it).
abstract base class CheckedPlacement extends AnnotationPlacement {
  /// The placement of the annotations of [checkers].
  const CheckedPlacement(this.checkers);

  /// The annotations covered.
  final List<TypeChecker> checkers;

  @override
  bool covers(InterfaceType type) =>
      checkers.any((checker) => checker.isAssignableFromType(type));
}

// The problem of a member outside a class, or of a constructor, for an
// annotation that goes on a member of a class.
String? _outsideClass(AnnotationSite site, String goesOn) =>
    switch (site.kind) {
      PlaceKind.topLevel || PlaceKind.foreignMember =>
        '${site.name} on ${site.subject}: it goes on $goesOn. Move '
            '${site.element.displayName} into one.',
      PlaceKind.mixin ||
      PlaceKind.enumDeclaration ||
      PlaceKind.extension ||
      PlaceKind.extensionType =>
        '${site.name} on ${site.subject}: it goes on $goesOn.',
      _ => null,
    };

/// Advice the proxy of a bean runs around its methods (`@Transactional`,
/// `@Cacheable`, `@PreAuthorize`): on a public instance method, getter or
/// setter of a bean class, or on the class; [effect] says what would not
/// happen elsewhere (`the transaction would not start`).
///
/// It fails the build on a private or static member (the proxy never sees
/// it, as CGLIB never sees a private method), an operator (a proxy cannot
/// forward it), a field (Java's `@Target` allows methods and types only),
/// a constructor, a `@Bean` method (it applies to the bean's own methods),
/// a member outside a class, a parameter, and in a class that is no bean.
base class AdvicePlacement extends CheckedPlacement {
  /// The advice annotations of [checkers].
  const AdvicePlacement(
    super.checkers, {
    this.effect = 'the advice would not run',
  });

  /// What would not happen if the advice did not run.
  final String effect;

  @override
  bool get isAdvice => true;

  @override
  String? problem(AnnotationSite site) {
    if (_outsideClass(
          site,
          'a method of a component class (@Component, @Service), whose '
          'proxy runs it',
        )
        case final problem?) {
      return problem;
    }
    final subject = site.subject;
    return switch (site.kind) {
      PlaceKind.constructor =>
        '${site.name} on $subject: a constructor is not called through the '
            "bean's proxy, so $effect. Put it on a method, or on the class.",
      PlaceKind.parameter =>
        '${site.name} on $subject: it goes on a method or a class.',
      PlaceKind.field =>
        '${site.name} on $subject: it goes on a method, a getter, a setter '
            "or the class (Java's @Target allows no field), and on a field "
            'it would advise both of its accessors. Write the getter or the '
            'setter it is meant for, and annotate that.',
      PlaceKind.operator =>
        '${site.name} on $subject: a proxy cannot forward an operator, so '
            '$effect. Move the work into a named method and annotate that.',
      PlaceKind.method || PlaceKind.getter || PlaceKind.setter
          when site.isPrivate || site.isStatic =>
        '${site.name} on $subject: a '
            '${site.isPrivate ? 'private' : 'static'} member is not called '
            "through the bean's proxy, so $effect. Make it a public instance "
            '${site.kind == PlaceKind.method ? 'method' : 'member'}.',
      PlaceKind.method when _isBeanMethod(site.element) =>
        '${site.name} on the @Bean method $subject: advice applies to the '
            'methods of the bean it returns, not to the @Bean method. '
            'Annotate the returned class or its methods instead.',
      _ => null,
    };
  }

  @override
  PlacementOwner? owner(AnnotationSite site) => PlacementOwner.bean;

  @override
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}, and ${site.ownerName} is no bean '
      '(no @Component or @Service, and no @Bean method of the module '
      "returns it): only a bean's proxy runs advice, so $effect. Add "
      '@Component() to ${site.ownerName}, return it from a @Bean method, or '
      'make it abstract when it is only a base of beans.';
}

/// A method the framework calls on a bean (`@EventListener`,
/// `@Scheduled`, `@GetMapping`): a public instance method of a class that
/// is a bean, or of the [owner] class ([ownerNoun] names it); getters and
/// setters too when [accessors]. [does] says what the framework does with
/// it (`the scheduler runs it`).
base class MethodPlacement extends CheckedPlacement {
  /// The method annotations of [checkers].
  const MethodPlacement(
    super.checkers, {
    required this.does,
    this.methodOwner = PlacementOwner.bean,
    this.ownerNoun,
    this.ownerFix,
    this.accessors = false,
  });

  /// What the framework does with the method.
  final String does;

  /// What the class around the method must be.
  final PlacementOwner methodOwner;

  /// The owner the method needs, for messages (`@RestController (or
  /// @Controller)`); for a bean `null`.
  final String? ownerNoun;

  /// What to add to the class to make it the owner (`@RestController()`).
  final String? ownerFix;

  /// Whether a getter or setter may carry it.
  final bool accessors;

  @override
  String? problem(AnnotationSite site) {
    final noun = ownerNoun ?? 'component class (@Component, @Service)';
    if (_outsideClass(site, 'a method of a $noun, where $does') case final p?) {
      return p;
    }
    final subject = site.subject;
    return switch (site.kind) {
      PlaceKind.classDeclaration =>
        '${site.name} on $subject: it goes on a method of the class, where '
            '$does.',
      PlaceKind.constructor || PlaceKind.parameter =>
        '${site.name} on $subject: it goes on a method, where $does.',
      PlaceKind.field || PlaceKind.getter || PlaceKind.setter when !accessors =>
        '${site.name} on $subject: it goes on a method, where $does. Write '
            'a method and annotate that.',
      PlaceKind.operator =>
        '${site.name} on $subject: it goes on a named method, where $does.',
      PlaceKind.method || PlaceKind.getter || PlaceKind.setter
          when site.isPrivate || site.isStatic =>
        '${site.name} on $subject: it must be a public instance method, '
            'where $does.',
      _ => null,
    };
  }

  @override
  PlacementOwner? owner(AnnotationSite site) => methodOwner;

  @override
  String ownerProblem(AnnotationSite site) => ownerNoun == null
      ? super.ownerProblem(site)
      : '${site.name} on ${site.subject}: ${site.ownerName} is no '
            '$ownerNoun, and only there $does, so it would do nothing. Add '
            '${ownerFix ?? ownerNoun} to ${site.ownerName}.';
}

/// A parameter annotation read only on the parameters of a method that
/// carries one of [methodsWith] ([methodNoun] names such a method: `a
/// handler method (@GetMapping, @PostMapping...)`). Without
/// [methodsWith], of a method the framework calls: one with an annotation
/// marked `@BeanMethodAnnotation()`, or an abstract method of an interface
/// whose implementation is generated (an HTTP client's).
base class ParameterPlacement extends CheckedPlacement {
  /// The parameter annotations of [checkers].
  const ParameterPlacement(
    super.checkers, {
    required this.methodNoun,
    this.methodsWith,
  });

  /// The method annotations that make the method one whose parameters
  /// are read; `null` for any method the framework calls.
  final List<TypeChecker>? methodsWith;

  /// Such a method, for messages.
  final String methodNoun;

  @override
  String? problem(AnnotationSite site) {
    if (site.kind != PlaceKind.parameter) {
      return '${site.name} on ${site.subject}: it goes on a parameter of '
          '$methodNoun.';
    }
    final executable = site.executable;
    final methodsWith = this.methodsWith;
    final read =
        executable != null &&
        executable is! ConstructorElement &&
        (methodsWith == null
            ? executable.isAbstract || calledByFramework(executable)
            : site.has(methodsWith, on: executable));
    if (!read) {
      return '${site.name} on ${site.subject}: only $methodNoun gets the '
          'value, and this method is none. Annotate the method, or remove '
          '${site.name}.';
    }
    return null;
  }
}

/// A class annotation (`@Scope`, `@Log`): on a class, and on a `@Bean`
/// method when [beanMethods]; [instead] says what to do elsewhere.
base class ClassPlacement extends CheckedPlacement {
  /// The class annotations of [checkers].
  const ClassPlacement(
    super.checkers, {
    this.beanMethods = false,
    this.instead,
  });

  /// Whether a `@Bean` method may carry it too.
  final bool beanMethods;

  /// What to do instead, for messages.
  final String? instead;

  @override
  String? problem(AnnotationSite site) {
    if (site.kind == PlaceKind.classDeclaration) {
      return null;
    }
    if (beanMethods &&
        site.kind == PlaceKind.method &&
        _isBeanMethod(site.element)) {
      return null;
    }
    // The scan root and an auto-configuration module are top-level
    // variables whose annotations the builder reads.
    if (site.kind == PlaceKind.topLevel && _isModuleVariable(site.element)) {
      return null;
    }
    final where = beanMethods ? 'a class or a @Bean method' : 'a class';
    return '${site.name} on ${site.subject}: it belongs on $where, where '
        'it is read; here it would do nothing'
        '${instead == null ? '' : '. $instead'}.';
  }
}

const TypeChecker _beanChecker = TypeChecker.typeNamedLiterally(
  'Bean',
  inPackage: 'spring_core_dart',
);

final List<TypeChecker> _moduleVariableCheckers = [
  const TypeChecker.typeNamedLiterally(
    'ComponentScan',
    inPackage: 'spring_core_dart',
  ),
  const TypeChecker.typeNamedLiterally(
    'AutoConfigurationModule',
    inPackage: 'spring_boot_dart',
  ),
  const TypeChecker.typeNamedLiterally(
    'SpringBootApplication',
    inPackage: 'spring_boot_dart',
  ),
];

bool _isBeanMethod(Element element) => _beanChecker.hasAnnotationOf(element);

const TypeChecker _beanMethodAnnotation = TypeChecker.typeNamedLiterally(
  'BeanMethodAnnotation',
  inPackage: 'spring_core_dart',
);

/// Whether [executable] carries an annotation marked
/// `@BeanMethodAnnotation()`: the framework calls it with its arguments.
bool calledByFramework(ExecutableElement executable) =>
    executable.metadata.annotations.any((annotation) {
      final element = annotation.computeConstantValue()?.type?.element;
      return element != null && _beanMethodAnnotation.hasAnnotationOf(element);
    });

bool _isModuleVariable(Element element) {
  final target = element is PropertyAccessorElement
      ? element.variable
      : element;
  return _moduleVariableCheckers.any(
    (checker) => checker.hasAnnotationOf(target),
  );
}

/// The placements of the core and of the started parts, asked in their
/// order: the first that covers an annotation decides (chain of
/// responsibility), so a part's narrower placement of an annotation the
/// core also covers (a mapping is a `@BeanMethodAnnotation`) comes first.
final class AnnotationPlacements {
  /// The placements, in the order they are asked.
  AnnotationPlacements(this.placements);

  /// The placements.
  final List<AnnotationPlacement> placements;

  final _byType = <InterfaceElement, List<AnnotationPlacement>>{};

  /// The placements covering annotations of [type], in their order.
  List<AnnotationPlacement> covering(InterfaceType type) => _byType.putIfAbsent(
    type.element,
    () => [
      for (final placement in placements)
        if (placement.covers(type)) placement,
    ],
  );

  /// The placement that decides [site], or `null`.
  AnnotationPlacement? of(AnnotationSite site) => covering(
    site.annotationType,
  ).where((placement) => placement.claims(site)).firstOrNull;

  /// Whether [annotation] is advice a bean's proxy runs
  /// ([AnnotationPlacement.isAdvice]).
  bool isAdvice(DartObject annotation) => switch (annotation.type) {
    final InterfaceType type => covering(type).any((p) => p.isAdvice),
    _ => false,
  };

  /// Every annotation of [library]'s declarations with its place, each
  /// one once.
  static Iterable<AnnotationSite> sitesOf(LibraryElement library) sync* {
    for (final element in library.classes) {
      yield* _ofDeclaration(element, PlaceKind.classDeclaration);
      yield* _ofMembers(element);
    }
    for (final element in library.mixins) {
      yield* _ofDeclaration(element, PlaceKind.mixin);
      yield* _ofMembers(element);
    }
    for (final element in library.enums) {
      yield* _ofDeclaration(element, PlaceKind.enumDeclaration);
      yield* _ofMembers(
        element,
        foreign: 'the enum ${element.name}',
        skipConstants: true,
      );
    }
    for (final element in library.extensions) {
      yield* _ofDeclaration(element, PlaceKind.extension);
      yield* _ofMembers(
        element,
        foreign:
            'the extension ${element.name ?? 'on ${element.extendedType}'}',
      );
    }
    for (final element in library.extensionTypes) {
      yield* _ofDeclaration(element, PlaceKind.extensionType);
      yield* _ofMembers(
        element,
        foreign: 'the extension type ${element.name}',
      );
    }
    final top = 'the top level of ${library.uri}';
    for (final variable in library.topLevelVariables) {
      if (variable.isOriginDeclaration) {
        yield* _of(variable, PlaceKind.topLevel, place: top);
      }
    }
    for (final accessor in [...library.getters, ...library.setters]) {
      if (accessor.isOriginDeclaration) {
        yield* _of(accessor, PlaceKind.topLevel, place: top);
        yield* _ofParameters(accessor, null);
      }
    }
    for (final function in library.topLevelFunctions) {
      yield* _of(function, PlaceKind.topLevel, place: top);
      yield* _ofParameters(function, null);
    }
  }

  /// The annotations on what no placement but a declared `@Target` reads:
  /// the library, enum values, typedefs and type parameters.
  static Iterable<AnnotationSite> targetOnlySitesOf(
    LibraryElement library,
  ) sync* {
    yield* _of(library, PlaceKind.library);
    for (final alias in library.typeAliases) {
      yield* _of(alias, PlaceKind.typedefDeclaration);
      yield* _ofTypeParameters(alias.typeParameters);
    }
    for (final function in library.topLevelFunctions) {
      yield* _ofTypeParameters(function.typeParameters);
    }
    final instances = <InstanceElement>[
      ...library.classes,
      ...library.mixins,
      ...library.enums,
      ...library.extensions,
      ...library.extensionTypes,
    ];
    for (final instance in instances) {
      yield* _ofTypeParameters(instance.typeParameters);
      for (final method in instance.methods) {
        yield* _ofTypeParameters(method.typeParameters);
      }
      for (final field in instance.fields) {
        if (field.isEnumConstant) {
          yield* _of(field, PlaceKind.enumValue, owner: instance);
        }
      }
    }
  }

  static Iterable<AnnotationSite> _ofTypeParameters(
    List<TypeParameterElement> parameters,
  ) sync* {
    for (final parameter in parameters) {
      yield* _of(parameter, PlaceKind.typeParameter);
    }
  }

  static Iterable<AnnotationSite> _ofDeclaration(
    Element element,
    PlaceKind kind,
  ) => _of(element, kind);

  static Iterable<AnnotationSite> _ofMembers(
    InstanceElement owner, {
    String? foreign,
    bool skipConstants = false,
  }) sync* {
    PlaceKind kindOf(PlaceKind inClass) =>
        foreign == null ? inClass : PlaceKind.foreignMember;
    for (final field in owner.fields) {
      if (!field.isOriginDeclaration ||
          (skipConstants && field.isEnumConstant)) {
        continue;
      }
      yield* _of(field, kindOf(PlaceKind.field), owner: owner, place: foreign);
    }
    for (final getter in owner.getters) {
      if (getter.isOriginDeclaration) {
        yield* _of(
          getter,
          kindOf(PlaceKind.getter),
          owner: owner,
          place: foreign,
        );
      }
    }
    for (final setter in owner.setters) {
      if (setter.isOriginDeclaration) {
        yield* _of(
          setter,
          kindOf(PlaceKind.setter),
          owner: owner,
          place: foreign,
        );
        yield* _ofParameters(setter, owner);
      }
    }
    for (final method in owner.methods) {
      yield* _of(
        method,
        kindOf(method.isOperator ? PlaceKind.operator : PlaceKind.method),
        owner: owner,
        place: foreign,
      );
      yield* _ofParameters(method, owner);
    }
    if (owner is InterfaceElement) {
      for (final constructor in owner.constructors) {
        if (!constructor.isOriginDeclaration) {
          continue;
        }
        yield* _of(constructor, PlaceKind.constructor, owner: owner);
        yield* _ofParameters(constructor, owner);
      }
    }
  }

  static Iterable<AnnotationSite> _ofParameters(
    ExecutableElement executable,
    InstanceElement? owner,
  ) sync* {
    for (final parameter in executable.formalParameters) {
      yield* _of(
        parameter,
        PlaceKind.parameter,
        owner: owner,
        executable: executable,
      );
    }
  }

  static Iterable<AnnotationSite> _of(
    Element element,
    PlaceKind kind, {
    InstanceElement? owner,
    String? place,
    ExecutableElement? executable,
  }) sync* {
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value?.type case final InterfaceType type?) {
        yield AnnotationSite(
          element: element,
          annotation: value!,
          annotationType: type,
          kind: kind,
          owner: owner,
          place: place,
          executable: executable,
        );
      }
    }
  }
}
