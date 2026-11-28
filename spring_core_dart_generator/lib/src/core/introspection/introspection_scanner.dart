import 'package:analyzer/dart/ast/ast.dart'
    show
        AstNode,
        BooleanLiteral,
        CollectionElement,
        DoubleLiteral,
        Expression,
        Identifier,
        IntegerLiteral,
        ListLiteral,
        MapLiteralEntry,
        MethodInvocation,
        NullLiteral,
        ParenthesizedExpression,
        PrefixExpression,
        PropertyAccess,
        SetOrMapLiteral,
        StringLiteral,
        VariableDeclaration;
import 'package:analyzer/dart/ast/token.dart' show TokenType;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/introspection/constraint_checker.dart';
import 'package:spring_core_dart_generator/src/core/introspection/introspection_model.dart';
import 'package:spring_core_dart_generator/src/core/introspection/json_annotation_checker.dart';
import 'package:spring_core_dart_generator/src/core/introspection/object_methods/object_methods_scanner.dart';

part 'field_initializers.dart';
part 'mapper_calls.dart';

// Annotations are matched by name in `package:spring_core_dart`, as the
// bean scanner matches its own.
TypeChecker _spring(String name) =>
    TypeChecker.typeNamedLiterally(name, inPackage: 'spring_core_dart');

final TypeChecker _introspected = _spring('Introspected');
final TypeChecker _autowired = _spring('Autowired');
final TypeChecker _constraint = _spring('Constraint');
final TypeChecker _valid = _spring('Valid');
final TypeChecker _each = _spring('Each');
final TypeChecker _eachKey = _spring('EachKey');
final TypeChecker _jsonCreator = _spring('JsonCreator');
final TypeChecker _jsonSubTypes = _spring('JsonSubTypes');
final TypeChecker _jsonTypeInfo = _spring('JsonTypeInfo');
final TypeChecker _jsonView = _spring('JsonView');
final TypeChecker _jsonInclude = _spring('JsonInclude');
final TypeChecker _jsonValue = _spring('JsonValue');
final TypeChecker _jsonAnyGetter = _spring('JsonAnyGetter');
final TypeChecker _jsonAnySetter = _spring('JsonAnySetter');

// `@ConfigurationProperties` from spring_core_dart (matched by URL, so the
// generator does not depend on that package): the binder's classes.
const _configurationProperties = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/property_annotations.dart#ConfigurationProperties',
);

/// How the scan of the beans and the packages' parts tell introspection
/// what the application does with a class, so that the class is described
/// for that use and no other (see [IntrospectionNeed]): a controller's
/// result is written out as JSON, a `@RequestBody` read in, a method an
/// expression calls invoked, an HTTP client's answer read in, an entity's
/// JSON column written and read. Introspection finds the `@Introspected`
/// classes itself; the others ask through this interface, in
/// `ModuleScan.introspection` for the parts.
///
/// ```dart
/// // A part's annotation whose framework writes the method's result out:
/// scan.introspection.need(method.returnType, owner, IntrospectionNeed.read);
/// ```
///
/// Spring (Java): no counterpart; reflection describes any class when it is
/// used.
abstract interface class IntrospectionRequests {
  /// The classes of [user]'s package that [type] is made of (its type
  /// arguments too: `Future<Page<Book>>`) are used for [need]; a class of
  /// another package, of the SDK, or one that cannot be described (a
  /// private class) is left out silently.
  void need(DartType type, ClassElement user, IntrospectionNeed need);

  /// The class [element] itself, whatever its package, is used for
  /// [need]: the bean an expression calls (`target`), the result of a
  /// `@ConfigurationProperties` `@Bean` method. [binding]: the use is the
  /// binder's of configuration properties, whose descriptions the module
  /// writes apart (`<library>.spring.properties.dart`).
  void needClass(
    ClassElement element,
    IntrospectionNeed need, {
    bool binding = false,
  });
}

/// Reads the classes the application describes: the `@Introspected` ones
/// (and the classes `@ConfigurationProperties` binds), and every class the
/// scan of the beans and the packages' parts ask for
/// ([IntrospectionRequests]), each for the uses found
/// ([IntrospectionNeed]). It fills the module's
/// [ModuleModel.introspections], which `IntrospectionEmitter` writes.
///
/// The bean scanner hands it each scanned library ([scanLibrary]) and
/// class ([scanClass]) in its one pass over them, as it hands them to the
/// packages' parts; it reads them through the same [ModuleScan].
///
/// ```dart
/// // Input:
/// @Introspected()
/// class Address {
///   String city = '';
/// }
/// // Result: module.introspections gets Address, with every part.
/// ```
///
/// Spring (Java): no counterpart; `BeanUtils` and Jackson reflect over a
/// class when they first use it.
final class IntrospectionScanner implements IntrospectionRequests {
  /// The scanner of the classes of [_module], read through [_scan];
  /// [generations] are the packages' parts of the build, asked for the
  /// classes whose initial values they read and the methods of theirs that
  /// write JSON.
  IntrospectionScanner(
    this._module,
    this._scan, {
    this.generations = const [],
  });

  final ModuleModel _module;

  final ModuleScan _scan;

  /// The packages' parts of the build.
  final List<PackageGeneration> generations;

  // Classes introspected so far (explicitly or automatically), with their
  // model in `module.introspections`: each request for a class adds to its
  // `need` (see [_scanIntrospected]).
  final _introspections = <ClassElement, IntrospectionModel>{};

  // The classes the calls of the `ObjectMapper` in each library name, found
  // by [resolveMapperCalls] (mapper_calls.dart).
  final _mapperUses = <LibraryElement, List<MapperUse>>{};

  // The index of the argument each starter's writer writes out as JSON
  // (`PackageGeneration.jsonWriters`), by its library's URL and its name.
  late final Map<(String, String), int> _jsonWriters = {
    for (final generation in generations)
      for (final writer in generation.jsonWriters)
        (writer.library, writer.method): writer.argument,
  };

  // Resolved initializers of the fields of introspected classes by
  // `library#Class.field`, for `IntrospectedProperty.initialValue`
  // (field_initializers.dart).
  final _fieldInitializers = <String, Expression>{};

  // The description passing its need on to the classes it is made of
  // ([_addNeed]); `null` for a request of the scan's own.
  IntrospectionModel? _passing;

  // Whether the request of the scan's own being handled is the binder's.
  bool _binding = false;

  // `@EqualsAndHashCode`, `@ToString` and `@CopyWith`.
  late final _objectMethods = ObjectMethodsScanner(_scan);

  /// The warnings of the scan (a private field an object method leaves
  /// out, a field of `hashCode` that is not final), which the module's
  /// build logs once.
  List<String> get warnings => _objectMethods.warnings;

  /// Resolves the initializers of the fields of the introspected classes
  /// of [library], so that [scanClass] can describe the constant initial
  /// value of each (`IntrospectedProperty.initialValue`).
  ///
  /// Call it before the library is scanned; [astNodeFor] is the build
  /// resolver's `astNodeFor(fragment, resolve: true)`. Without it, no
  /// field has an initial value.
  Future<void> resolveFieldInitializers(
    LibraryElement library,
    Future<AstNode?> Function(Fragment fragment) astNodeFor,
  ) => _resolveFieldInitializerDeclarations(library, astNodeFor);

  /// Finds the calls of the `ObjectMapper` in [library] whose static types
  /// name classes (`mapper.readValue<Book>(json)`), so that [scanLibrary]
  /// describes those classes for what the call does with them: read in
  /// (`readValue`, `treeToValue`, `readList`, `readMap`, `convertValue`'s
  /// type) or written out (`writeValueAsString`, `valueToTree`,
  /// `convertValue`'s value).
  ///
  /// Call it before the library is scanned, like
  /// [resolveFieldInitializers]. A library that names none of those
  /// methods is not resolved. Without this step a class used only through
  /// such calls needs `@Introspected()`.
  Future<void> resolveMapperCalls(
    LibraryElement library,
    Future<AstNode?> Function(Fragment fragment) astNodeFor,
  ) => _resolveMapperCallDeclarations(library, astNodeFor);

  /// Describes the classes of [library]'s package that its calls of the
  /// `ObjectMapper` name (found by [resolveMapperCalls]), before its
  /// classes are scanned.
  ///
  /// Fails the build for the object methods' annotations on a declaration
  /// of [library] that is no class.
  void scanLibrary(LibraryElement library) {
    _objectMethods.rejectMisplaced(library);
    _introspectMapperUses(library);
  }

  /// Describes [element], a class of a scanned library, when it is
  /// `@Introspected` (or has an annotation that extends it): everything,
  /// except that `@ConfigurationProperties` asks for what its binder uses
  /// (see [IntrospectionNeed.configuration]). `@EqualsAndHashCode`,
  /// `@ToString` and `@CopyWith` describe the class too, with
  /// what they ask for ([IntrospectionModel.objectMethods]) and no other
  /// part.
  ///
  /// Throws `InvalidGenerationSource` when the class cannot be described
  /// (a private class, a constraint that does not fit its type); the
  /// problems of the object methods' annotations are added to the build's
  /// errors one by one.
  void scanClass(ClassElement element) {
    if (_objectMethods.scanClass(element) case final methods?) {
      _request(
        false,
        () => _scanIntrospected(element, IntrospectionNeed.none),
      );
      _introspections[element]?.objectMethods = methods;
    }
    if (!_introspected.hasAnnotationOf(element)) {
      return;
    }
    var need = IntrospectionNeed.none;
    var binding = true;
    for (final annotation in _introspected.annotationsOf(element)) {
      final type = annotation.type;
      if (type != null && _configurationProperties.isAssignableFromType(type)) {
        need |= IntrospectionNeed.configuration;
      } else {
        need |= IntrospectionNeed.all;
        binding = false;
      }
    }
    _request(binding, () => _scanIntrospected(element, need));
  }

  @override
  void need(DartType type, ClassElement user, IntrospectionNeed need) =>
      _request(false, () => _introspectUsed(type, user, need: need));

  @override
  void needClass(
    ClassElement element,
    IntrospectionNeed need, {
    bool binding = false,
  }) => _request(
    binding,
    () => _scanIntrospected(element, need, automatic: true),
  );

  /// The constant initial value of [field], or `null` when it has none the
  /// generated code can write. The initializers are those of the classes
  /// the build resolved before the scan ([resolveFieldInitializers]): the
  /// introspected ones, and those a part asked for
  /// (`PackageGeneration.initialValueClasses`).
  ///
  /// An `int` initializer of a `double` field (`double rate = 1`) is
  /// converted to `1.0`, as Dart does.
  InitialValue? initialValueOf(FieldElement field) => _initialValueOf(field);

  // Runs [action], a request of the scan's own (not a description passing
  // its need on), as the binder's when [binding].
  void _request(bool binding, void Function() action) {
    final passing = _passing;
    final before = _binding;
    _passing = null;
    _binding = binding;
    try {
      action();
    } finally {
      _passing = passing;
      _binding = before;
    }
  }

  // Runs [action], in which [model] passes its need on to the classes it
  // is made of: what they are asked for is reached from it.
  void _passingOn(IntrospectionModel model, void Function() action) {
    final passing = _passing;
    _passing = model;
    try {
      action();
    } finally {
      _passing = passing;
    }
  }

  // Records who asked for [model]: the description passing its need on, or
  // the scan's own request, the binder's or another one.
  void _recordUse(IntrospectionModel model) {
    if (_passing case final passing?) {
      passing.reaches.add(model);
    } else if (_binding) {
      model.forBinding = true;
    } else {
      model.forOtherUses = true;
    }
  }

  // [type], a class type, without `?`.
  static InterfaceType _nonNullable(DartType type) {
    final interface = type as InterfaceType;
    return interface.nullabilitySuffix == NullabilitySuffix.none
        ? interface
        : interface.element.instantiate(
            typeArguments: interface.typeArguments,
            nullabilitySuffix: NullabilitySuffix.none,
          );
  }

  static Never _fail(String message, Element element) =>
      throw InvalidGenerationSource(message, element: element);

  // Describes [element] for the use [need] says (see [IntrospectionNeed]);
  // a class asked for again keeps one description, whose need is the union
  // of the requests, passed on to the classes it is made of.
  //
  // [automatic]: a class of the same package used by an introspected class
  // (a property or constructor parameter type), a controller's return
  // type, ...; skipped silently when it cannot be introspected. A generic
  // class (`Page<T>`) is described with its type parameters erased, plus a
  // `specialize` callback the emitter writes for `Page<Book>` (see
  // IntrospectionEmitter.introspection).
  void _scanIntrospected(
    ClassElement element,
    IntrospectionNeed need, {
    bool automatic = false,
  }) {
    final name = _scan.requireName(element);
    if (element.isPrivate) {
      if (automatic) {
        return;
      }
      _fail('@Introspected class $name must be public.', element);
    }
    if (_introspections[element] case final known?) {
      _recordUse(known);
      _addNeed(known, need);
      return;
    }
    checkJsonAnnotations(element);
    final type = element.thisType;
    // Only fields with a getter and an interface type, and methods callable
    // with positional arguments only, can be described by
    // IntrospectedProperty and IntrospectedMethod; anything else is skipped
    // silently.
    final hierarchy = describedClasses(element);
    final properties = <String, IntrospectionPropertyModel>{};
    final methods = <String, IntrospectionMethodModel>{};
    for (final field in describedFields(hierarchy)) {
      final fieldName = field.name!;
      final fieldType = field.type;
      // A type parameter of the class itself (`T content`) too.
      final ownTypeParameter =
          fieldType is TypeParameterType &&
          element.typeParameters.contains(fieldType.element);
      if (fieldType is! InterfaceType && !ownTypeParameter) {
        continue;
      }
      final annotations = [
        ..._scan.userAnnotations(field),
        if (field.getter case final getter?) ..._scan.userAnnotations(getter),
      ];
      properties[fieldName] = IntrospectionPropertyModel(
        name: fieldName,
        type: fieldType is TypeParameterType
            ? fieldType.element.instantiate(
                nullabilitySuffix: NullabilitySuffix.none,
              )
            : _nonNullable(fieldType),
        declaredType: fieldType,
        // `T` may be nullable (`Page<Book?>`).
        nullable:
            ownTypeParameter ||
            fieldType.nullabilitySuffix == NullabilitySuffix.question,
        writable: field.setter != null,
        validated: annotations.any(_isValidation),
        initialValue: initialValueOf(field),
        annotations: annotations,
      );
      checkConstraints(
        properties[fieldName]!.annotations,
        fieldType,
        '$name.$fieldName',
        field,
      );
    }
    for (final current in hierarchy) {
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
        final annotations = _scan.userAnnotations(method);
        methods[methodName] = IntrospectionMethodModel(
          name: methodName,
          returnType: returnType is InterfaceType
              ? _nonNullable(returnType)
              : null,
          parameterTypes: [
            for (final t in parameterTypes) _nonNullable(t),
          ],
          annotations: annotations,
          isFuture:
              returnType.isDartAsyncFuture &&
              returnType.nullabilitySuffix == NullabilitySuffix.none,
          jsonNeed: _jsonMethodNeed(annotations),
        );
      }
    }
    final constructor = element.unnamedConstructor;
    final dataConstructor = _dataConstructor(element);
    final classAnnotations = _scan.userAnnotations(element);
    final model = IntrospectionModel(
      element: element,
      type: type,
      properties: properties.values.toList(),
      methods: methods.values.toList(),
      annotations: classAnnotations,
      instantiable:
          !element.isAbstract &&
          constructor != null &&
          constructor.isPublic &&
          !constructor.isFactory &&
          !constructor.formalParameters.any((p) => p.isRequired),
      nonDefaultInclusion: classAnnotations.any(_isNonDefaultInclusion),
      constructor: dataConstructor,
      fromJson: _fromJson(element),
      hasToJson: _hasToJson(type),
    );
    _introspections[element] = model;
    _module.introspections.add(model);
    _recordUse(model);
    // `@Introspected(classes: [ExternalDto])`: described entirely, as the
    // annotation asks.
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value == null || !_introspected.isAssignableFromType(value.type!)) {
        continue;
      }
      for (final listed
          in ConstantReader(value).peek('classes')?.listValue ??
              const <DartObject>[]) {
        if (listed.toTypeValue() case final InterfaceType listedType
            when listedType.element is ClassElement) {
          _passingOn(
            model,
            () => _scanIntrospected(
              listedType.element as ClassElement,
              IntrospectionNeed.all,
            ),
          );
        }
      }
    }
    _addNeed(model, need);
  }

  // Adds [need] to the description of a class and passes the result on to
  // the classes it is made of; nothing happens when the class has it
  // already (which also ends a cycle of classes).
  void _addNeed(IntrospectionModel model, IntrospectionNeed need) {
    var merged = model.need | need;
    // `nonDefault` compares with a new instance.
    if (merged.includes(IntrospectionNeed.read) && model.nonDefaultInclusion) {
      merged |= IntrospectionNeed.write;
    }
    if (merged == model.need) {
      return;
    }
    model.need = merged;
    final element = model.element as ClassElement;
    _passingOn(model, () {
      // Classes of the same package it is made of are introspected too, so
      // one `@Introspected()` on the root of a model is enough.
      for (final property in model.properties) {
        _introspectUsed(property.declaredType, element, need: merged);
      }
      final parameters =
          model.constructor?.parameters ?? const <ConstructorParameterModel>[];
      for (final parameter in parameters) {
        _introspectUsed(parameter.type, element, need: merged);
      }
      _introspectJsonTypes(element, [
        ...model.annotations,
        for (final property in model.properties) ...property.annotations,
        for (final parameter in parameters) ...parameter.annotations,
      ], merged);
    });
  }

  // Whether the validator looks at an element with [annotation]: a
  // constraint, `@Valid()` or an element constraint.
  static bool _isValidation(DartObject annotation) {
    final type = annotation.type;
    return type != null &&
        (_constraint.isAssignableFromType(type) ||
            _valid.isExactlyType(type) ||
            _each.isExactlyType(type) ||
            _eachKey.isExactlyType(type));
  }

  // `@JsonInclude(JsonInclusion.nonDefault)`.
  static bool _isNonDefaultInclusion(DartObject annotation) {
    final type = annotation.type;
    return type != null &&
        _jsonInclude.isExactlyType(type) &&
        annotation.getField('value')?.getField('_name')?.toStringValue() ==
            'nonDefault';
  }

  // What `ObjectMapper` needs a method for, if it carries a JSON
  // annotation that makes it part of reading or writing an object.
  static IntrospectionNeed _jsonMethodNeed(List<DartObject> annotations) {
    var need = IntrospectionNeed.none;
    for (final annotation in annotations) {
      final type = annotation.type;
      if (type == null) {
        continue;
      }
      if (_jsonValue.isExactlyType(type) ||
          _jsonAnyGetter.isExactlyType(type)) {
        need |= IntrospectionNeed.read;
      } else if (_jsonAnySetter.isExactlyType(type)) {
        need |= IntrospectionNeed.write;
      }
    }
    return need;
  }

  // The classes JSON annotations name are needed at runtime: the subtypes
  // of `@JsonSubTypes` and the `defaultImpl` of `@JsonTypeInfo` (to read
  // or write them, as the base is), and the view classes of `@JsonView`
  // (only compared, to tell views that extend other views).
  void _introspectJsonTypes(
    ClassElement user,
    List<DartObject> annotations,
    IntrospectionNeed need,
  ) {
    void scan(
      DartObject? type,
      IntrospectionNeed need, {
      required bool automatic,
    }) {
      if (type?.toTypeValue() case final InterfaceType listed
          when listed.element is ClassElement) {
        _scanIntrospected(
          listed.element as ClassElement,
          need,
          automatic: automatic,
        );
      }
    }

    for (final annotation in annotations) {
      final reader = ConstantReader(annotation);
      if (_jsonSubTypes.isExactlyType(annotation.type!)) {
        for (final subType in reader.read('value').listValue) {
          scan(subType.getField('value'), need, automatic: false);
        }
      } else if (_jsonTypeInfo.isExactlyType(annotation.type!)) {
        scan(annotation.getField('defaultImpl'), need, automatic: false);
      } else if (_jsonView.isExactlyType(annotation.type!)) {
        for (final view in reader.read('value').listValue) {
          scan(view, IntrospectionNeed.none, automatic: true);
        }
      }
    }
  }

  // Introspects the classes of the same package [type] is made of (its
  // type arguments too: `Future<Page<Book>>`) for [need]. [need] is what
  // the use asks for: everything unless the caller knows better.
  void _introspectUsed(
    DartType type,
    ClassElement user, {
    IntrospectionNeed need = IntrospectionNeed.all,
  }) => _introspectInPackage(type, packageOf(user), need);

  // The same for the classes of the package [package] (`null` for a
  // library that is not in a package).
  void _introspectInPackage(
    DartType type,
    String? package,
    IntrospectionNeed need,
  ) {
    // A use that asks for nothing describes nothing.
    if (type is! InterfaceType || need.isNone) {
      return;
    }
    for (final argument in type.typeArguments) {
      _introspectInPackage(argument, package, need);
    }
    final element = type.element;
    if (element is! ClassElement ||
        element.library.isInSdk ||
        packageOf(element) != package) {
      return;
    }
    _scanIntrospected(element, need, automatic: true);
  }

  /// The package of [element]'s library (`package:` or `asset:`), whose
  /// classes a use of the package's own describes; `null` for a library
  /// that is not in a package.
  static String? packageOf(Element element) {
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
        boundConstructor(element) ??
        constructors.where(_jsonCreator.hasAnnotationOf).firstOrNull ??
        constructors.where((c) => (c.name ?? 'new') == 'new').firstOrNull;
    if (constructor == null) {
      return null;
    }
    for (final parameter in constructor.formalParameters) {
      checkConstraints(
        _scan.userAnnotations(parameter),
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
            name: _scan.requireName(parameter),
            type: parameter.type,
            isNamed: parameter.isNamed,
            isRequired: parameter.isRequired,
            annotations: _scan.userAnnotations(parameter),
            hasDefault: parameter.hasDefaultValue,
            defaultValue: switch (parameter.hasDefaultValue
                ? parameter.computeConstantValue()
                : null) {
              final value? when _scan.isRecreatable(value) => value,
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
    for (final element in [
      type.element,
      for (final supertype in type.allSupertypes)
        if (!supertype.isDartCoreObject) supertype.element,
    ]) {
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
}

// The superclass chain (no interfaces or mixins), without `Object`.
Iterable<InterfaceElement> _superclasses(InterfaceType type) sync* {
  var current = type.superclass;
  while (current != null && !current.isDartCoreObject) {
    yield current.element;
    current = current.superclass;
  }
}

/// The classes whose members describe [element]: itself, its mixins (the
/// last one first, it overrides the others), then each superclass with its
/// own, so overriding declarations come first. Interfaces are left out, and
/// `IntrospectedObject`, whose `hashCode` and `toString` are no data.
List<InterfaceElement> describedClasses(ClassElement element) => [
  for (final current in [element, ..._superclasses(element.thisType)]) ...[
    current,
    for (final mixin in current.mixins.reversed)
      if (!introspectedObjectChecker.isExactly(mixin.element)) mixin.element,
  ],
];

/// The public instance fields with a getter that describe [element], as
/// its introspection lists them: its own, its mixins' (the last one first),
/// then each superclass's with its mixins'; the first declaration of a name
/// wins. Interfaces are left out.
Iterable<FieldElement> describedFieldsOf(ClassElement element) =>
    describedFields(describedClasses(element));

/// The public instance fields with a getter of [classes] (see
/// [describedClasses]); the first declaration of a name wins.
Iterable<FieldElement> describedFields(List<InterfaceElement> classes) sync* {
  final names = <String>{};
  for (final current in classes) {
    for (final field in current.fields) {
      final name = field.name;
      if (field.isStatic ||
          field.isPrivate ||
          name == null ||
          field.getter == null ||
          !names.add(name)) {
        continue;
      }
      yield field;
    }
  }
}

/// Spring Boot's constructor binding: the constructor of [element], a
/// `@ConfigurationProperties` class, whose parameters are bound from
/// properties: its only public generative constructor, when it has
/// parameters and is not `@Autowired`. The bean is created by
/// `ConstructorBound.from`, which binds the parameters through the
/// introspection's `IntrospectedConstructor` (this same constructor); the
/// bean scanner then injects no beans into it. `null` for any other class.
ConstructorElement? boundConstructor(ClassElement element) {
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
