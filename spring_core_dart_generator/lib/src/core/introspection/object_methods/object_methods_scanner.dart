// `@EqualsAndHashCode`, `@ToString` and `@CopyWith` (spring_core_dart):
// the object methods of a data class, read from the class and checked,
// like Lombok's annotations. Introspection describes the annotated classes;
// this file reads what their descriptions and the module's
// `<library>.spring.introspection.dart` get.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart/core.dart' show SecretNames;
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/builder/closest_name.dart';
import 'package:spring_core_dart_generator/src/core/introspection/object_methods/object_methods_model.dart';

/// Recognises `@EqualsAndHashCode` of `spring_core_dart`.
const equalsAndHashCodeChecker = TypeChecker.typeNamedLiterally(
  'EqualsAndHashCode',
  inPackage: 'spring_core_dart',
);

/// Recognises `@ToString` of `spring_core_dart`.
const toStringChecker = TypeChecker.typeNamedLiterally(
  'ToString',
  inPackage: 'spring_core_dart',
);

/// Recognises `@CopyWith` of `spring_core_dart`.
const copyWithChecker = TypeChecker.typeNamedLiterally(
  'CopyWith',
  inPackage: 'spring_core_dart',
);

/// Recognises the mixin `IntrospectedObject` of `spring_core_dart`.
const introspectedObjectChecker = TypeChecker.typeNamedLiterally(
  'IntrospectedObject',
  inPackage: 'spring_core_dart',
);

const _configurationChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/annotations.dart#Configuration',
);
const _aspectChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/annotations.dart#Aspect',
);

const List<(String, TypeChecker)> _annotationCheckers = [
  ('EqualsAndHashCode', equalsAndHashCodeChecker),
  ('ToString', toStringChecker),
  ('CopyWith', copyWithChecker),
];

const _annotationNames = {'EqualsAndHashCode', 'ToString', 'CopyWith'};

/// Reads the `@EqualsAndHashCode`, `@ToString` and `@CopyWith` of the
/// scanned classes into [ObjectMethodsModel]s, and fails the build
/// for every misuse, through [_scan] (each problem on its own, so one build
/// reports them all).
///
/// What it refuses: a target that cannot have them (private, abstract,
/// sealed, an interface, a mixin class for the methods, a `@Configuration`
/// class, an aspect; a mixin, an enum, an extension, an extension type, a
/// typedef or a member), a class whose `==`, `hashCode` or `toString` is
/// not `IntrospectedObject`'s, the names of `include`, `exclude`, `mask`
/// and `reveal`, `callSuper` without a superclass whose part means
/// something, and the constructor of `copyWith`. Its warnings (private
/// fields left out, a field of `hashCode` that is not final) are kept in
/// [warnings], which the module's build logs once.
///
/// ```dart
/// // Input:
/// @EqualsAndHashCode()
/// @ToString(mask: ['card'])
/// class Payment with IntrospectedObject {
///   const Payment(this.id, this.card);
///   final int id;
///   final String card;
/// }
/// // Result: an ObjectMethodsModel with the fields id and card, card
/// // masked; the class's description gets its ObjectMethods.
/// ```
///
/// Spring (Java), with Lombok: the annotation processor that writes
/// `equals`, `hashCode`, `toString` and `withX` into the class.
final class ObjectMethodsScanner {
  /// A scanner reporting through [_scan].
  ObjectMethodsScanner(this._scan);

  final ModuleScan _scan;

  /// The warnings of the scan, logged by the module's build.
  final warnings = <String>[];

  /// The model of [element], or `null` when it has none of the three
  /// annotations (or none of them could be read). A concrete class that
  /// mixes in `IntrospectedObject` without any of them, and without a
  /// described superclass, fails the build: its methods would throw.
  ObjectMethodsModel? scanClass(ClassElement element) {
    if (!_mayHaveObjectMethodsAnnotation(element)) {
      _scan.collectErrors(
        () => _rejectIntrospectedObjectWithoutDescription(element),
      );
      return null;
    }
    final equalsAndHashCodeAnnotation = equalsAndHashCodeChecker
        .firstAnnotationOfExact(element);
    final toStringAnnotation = toStringChecker.firstAnnotationOfExact(element);
    final copyWithAnnotation = copyWithChecker.firstAnnotationOfExact(element);
    if (equalsAndHashCodeAnnotation == null &&
        toStringAnnotation == null &&
        copyWithAnnotation == null) {
      _scan.collectErrors(
        () => _rejectIntrospectedObjectWithoutDescription(element),
      );
      return null;
    }
    final annotationNames = [
      if (equalsAndHashCodeAnnotation != null) '@EqualsAndHashCode',
      if (toStringAnnotation != null) '@ToString',
      if (copyWithAnnotation != null) '@CopyWith',
    ];
    if (!_isSupportedClass(element, annotationNames)) {
      return null;
    }
    final model = ObjectMethodsModel(element);
    final mixinMethodAnnotationNames = [
      if (equalsAndHashCodeAnnotation != null) '@EqualsAndHashCode',
      if (toStringAnnotation != null) '@ToString',
    ];
    var mixesInIntrospectedObject = false;
    if (mixinMethodAnnotationNames.isEmpty) {
      _scan.collectErrors(
        () => _rejectIntrospectedObjectWithoutDescription(element),
      );
    } else {
      _scan.collectErrors(() {
        _checkMixesInIntrospectedObject(
          element,
          mixinMethodAnnotationNames,
          generatesEquals: equalsAndHashCodeAnnotation != null,
        );
        mixesInIntrospectedObject = true;
      });
    }
    if (mixesInIntrospectedObject) {
      final describedSuperclass = model.describedSuperclass =
          _describedSuperclass(element);
      model
        ..equalsFromSuperclass =
            equalsAndHashCodeAnnotation == null &&
            describedSuperclass != null &&
            _definesEquals(describedSuperclass)
        ..toStringFromSuperclass =
            toStringAnnotation == null &&
            describedSuperclass != null &&
            _definesToString(describedSuperclass);
      if (equalsAndHashCodeAnnotation != null) {
        _scan.collectErrors(() {
          model.equalsAndHashCodeModel = _readEqualsAndHashCode(
            element,
            ConstantReader(equalsAndHashCodeAnnotation),
          );
        });
      }
      if (toStringAnnotation != null) {
        _scan.collectErrors(() {
          model.toStringModel = _readToString(
            element,
            ConstantReader(toStringAnnotation),
          );
        });
      }
    }
    if (copyWithAnnotation != null) {
      _scan.collectErrors(() {
        model.copyWithModel = _readCopyWith(
          element,
          ConstantReader(copyWithAnnotation),
        );
      });
    }
    if (!model.hasObjectMethods && !model.hasCopyWith) {
      return null;
    }
    return model;
  }

  // Whether [element] can have the annotations of [annotationNames]; when
  // it cannot, the build fails with the reason.
  bool _isSupportedClass(ClassElement element, List<String> annotationNames) {
    final reason = _unsupportedClassReason(element);
    if (reason == null) {
      return true;
    }
    _scan.collectErrors(() {
      throw InvalidGenerationSource(
        '${_joinedWithAnd(annotationNames)} on ${element.name ?? '?'}: '
        '$reason',
        element: element,
      );
    });
    return false;
  }

  /// Fails the build for `@EqualsAndHashCode`, `@ToString` or `@CopyWith`
  /// on a declaration of [library] that is no class (a mixin,
  /// an enum, an extension, an extension type, a typedef, a function, a
  /// variable), and on a member (a field, a method, a constructor): they
  /// belong on a class, and their options are the annotation's parameters.
  void rejectMisplaced(LibraryElement library) {
    void reject(Element element, String what, String instead, {String? label}) {
      if (!_mayHaveObjectMethodsAnnotation(element)) {
        return;
      }
      for (final (annotation, checker) in _annotationCheckers) {
        _scan.collectErrors(() {
          if (checker.firstAnnotationOfExact(element) != null) {
            throw InvalidGenerationSource(
              '@$annotation on $what ${label ?? element.displayName} of '
              '${library.uri}: $instead',
              element: element,
            );
          }
        });
      }
    }

    void members(InstanceElement container) {
      final owner = container.displayName;
      const instead =
          'the annotation belongs on the class; leave a field out with '
          "exclude: ['name'], or name the fields with include: [...].";
      for (final field in container.fields) {
        if (!field.isOriginGetterSetter) {
          reject(
            field,
            'the field',
            instead,
            label: '$owner.${field.displayName}',
          );
        }
      }
      for (final getter in container.getters) {
        if (!getter.isOriginVariable) {
          reject(
            getter,
            'the getter',
            instead,
            label: '$owner.${getter.displayName}',
          );
        }
      }
      for (final setter in container.setters) {
        if (!setter.isOriginVariable) {
          reject(
            setter,
            'the setter',
            instead,
            label: '$owner.${setter.displayName}',
          );
        }
      }
      for (final method in container.methods) {
        reject(
          method,
          'the method',
          instead,
          label: '$owner.${method.displayName}',
        );
      }
      if (container is InterfaceElement) {
        for (final constructor in container.constructors) {
          reject(
            constructor,
            'the constructor',
            'the annotation belongs on the class '
                "(@CopyWith(constructor: '...') names the constructor).",
            label: _constructorCall(constructor, owner),
          );
        }
      }
    }

    library.classes.forEach(members);
    for (final element in library.mixins) {
      reject(
        element,
        'mixin',
        'a mixin has no instances of its own; annotate the classes that mix '
            'it in.',
      );
      members(element);
    }
    for (final element in library.enums) {
      reject(
        element,
        'enum',
        'the values of an enum are constants, equal only to themselves and '
            'named by `.name`; an enum cannot override == or hashCode.',
      );
      members(element);
    }
    for (final element in library.extensions) {
      reject(
        element,
        'extension',
        "an extension cannot override Object's members; annotate the "
            'extended class.',
      );
      members(element);
    }
    for (final element in library.extensionTypes) {
      reject(
        element,
        'extension type',
        'an extension type is its representation at run time, whose own ==, '
            'hashCode and toString() are used; use a class.',
      );
      members(element);
    }
    for (final element in library.typeAliases) {
      reject(
        element,
        'typedef',
        'a typedef is no class (a record already compares and prints its '
            'fields); annotate a class.',
      );
    }
    for (final function in library.topLevelFunctions) {
      reject(function, 'the function', 'the annotation belongs on a class.');
    }
    for (final variable in library.topLevelVariables) {
      reject(variable, 'the variable', 'the annotation belongs on a class.');
    }
  }

  // A concrete class whose `==`, `hashCode` or `toString` is
  // IntrospectedObject's needs a description: its own annotation, or a
  // superclass's.
  void _rejectIntrospectedObjectWithoutDescription(ClassElement element) {
    if (element.isAbstract ||
        element.isSealed ||
        !element.allSupertypes.any(
          (type) => _belongsToIntrospectedObject(type.element),
        )) {
      return;
    }
    if (!['==', 'hashCode', 'toString'].any(
      (member) =>
          _belongsToIntrospectedObject(_concreteMember(element, member)),
    )) {
      return;
    }
    for (
      var type = element.supertype;
      type != null && !type.isDartCoreObject;
      type = type.superclass
    ) {
      if (equalsAndHashCodeChecker.hasAnnotationOfExact(type.element) ||
          toStringChecker.hasAnnotationOfExact(type.element)) {
        return;
      }
    }
    final name = element.name ?? '?';
    throw InvalidGenerationSource(
      '$name mixes in IntrospectedObject, but neither it nor a class above '
      'it has @EqualsAndHashCode or @ToString: its ==, hashCode and '
      'toString() would find no description and throw. Annotate $name '
      '(@EqualsAndHashCode(), @ToString()), or remove `with '
      'IntrospectedObject`.',
      element: element,
    );
  }

  // `==`, `hashCode` or `toString` as [element] has it: its own, a mixin's
  // or a superclass's.
  static ExecutableElement? _concreteMember(
    ClassElement element,
    String member,
  ) => _concreteMemberOf(element.thisType, member, element.library);

  static ExecutableElement? _concreteMemberOf(
    InterfaceType type,
    String member,
    LibraryElement library,
  ) => member == 'hashCode'
      ? type.lookUpGetter(member, library, concrete: true)
      : type.lookUpMethod(member, library, concrete: true);

  static bool _belongsToIntrospectedObject(Element? element) =>
      switch (element) {
        InterfaceElement() => introspectedObjectChecker.isExactly(element),
        ExecutableElement(:final enclosingElement?) =>
          _belongsToIntrospectedObject(
            enclosingElement,
          ),
        _ => false,
      };

  // The class mixes in IntrospectedObject, and the members its annotations
  // write are IntrospectedObject's (nothing overrides them, nothing it
  // overrides forbids it).
  void _checkMixesInIntrospectedObject(
    ClassElement element,
    List<String> annotations, {
    required bool generatesEquals,
  }) {
    final name = element.name!;
    final members = [
      if (generatesEquals) ...['==', 'hashCode'],
      if (annotations.contains('@ToString')) 'toString',
    ];
    if (element.isMixinClass) {
      throw InvalidGenerationSource(
        '${_joinedWithAnd(annotations)} on $name: a mixin class cannot mix '
        'in IntrospectedObject, whose ${_joinedWithAnd(members)} call the '
        'generated ones; declare $name as a class '
        '(`class $name with IntrospectedObject`).',
        element: element,
      );
    }
    if (!element.allSupertypes.any(
      (type) => _belongsToIntrospectedObject(type.element),
    )) {
      final import = _importDirectiveBringing(
        element,
        annotations.first.substring(1),
      );
      throw InvalidGenerationSource(
        '${_joinedWithAnd(annotations)} on $name: $name does not mix in '
        'IntrospectedObject, whose ${_joinedWithAnd(members)} call the '
        'generated ${members.length == 1 ? 'one' : 'ones'}. Declare the '
        'class as '
        '`class $name with IntrospectedObject` (after its `extends`, before '
        'its `implements`); IntrospectedObject comes with the import of '
        '${annotations.first}: $import',
        element: element,
      );
    }
    for (final member in members) {
      final effective = _concreteMember(element, member);
      if (_belongsToIntrospectedObject(effective)) {
        continue;
      }
      final owner = effective?.enclosingElement;
      final annotation = member == 'toString'
          ? '@ToString'
          : '@EqualsAndHashCode';
      final ownerName = owner?.name ?? '?';
      throw InvalidGenerationSource(switch (owner) {
        _ when owner == element =>
          '$annotation on $name: $name declares $member itself, which wins '
              "over IntrospectedObject's (the one that calls the generated "
              '$member); remove it or the annotation.',
        MixinElement() =>
          '$annotation on $name: the mixin $ownerName, applied after '
              'IntrospectedObject, declares $member, which wins over '
              "IntrospectedObject's; put IntrospectedObject last in the "
              "class's `with` clause, or leave the annotation out.",
        _ =>
          '$annotation on $name: $name inherits $member from $ownerName, '
              'which declares its own below IntrospectedObject, so '
              "IntrospectedObject's is never called; mix it in on $name "
              '(`class $name extends ... with IntrospectedObject`), or leave '
              'the annotation out.',
      }, element: element);
    }
    // What IntrospectedObject overrides must allow it.
    for (final supertype in element.allSupertypes) {
      final declaring = supertype.element;
      if (supertype.isDartCoreObject ||
          _belongsToIntrospectedObject(declaring)) {
        continue;
      }
      for (final member in members) {
        final declared = member == 'hashCode'
            ? declaring.getGetter(member)
            : declaring.getMethod(member);
        if (declared == null) {
          continue;
        }
        final annotation = member == 'toString'
            ? '@ToString'
            : '@EqualsAndHashCode';
        final nonVirtual =
            declared.metadata.hasNonVirtual ||
            (declared is GetterElement &&
                declared.variable.metadata.hasNonVirtual);
        if (nonVirtual) {
          throw InvalidGenerationSource(
            '$annotation on $name: ${declaring.name} declares $member '
            '@nonVirtual, so no subclass may override it (a Flutter widget '
            'is compared by identity); leave the annotation out.',
            element: element,
          );
        }
        if (member == 'toString' &&
            declared is MethodElement &&
            declared.formalParameters.isNotEmpty) {
          throw InvalidGenerationSource(
            '$annotation on $name: the toString it would override, '
            "${declaring.name}'s, takes parameters, which "
            "IntrospectedObject's toString() cannot; leave the annotation "
            'out.',
            element: element,
          );
        }
      }
    }
  }

  // `import '...';` of [element]'s library that brings [name] (an
  // annotation of spring_core_dart, exported with IntrospectedObject).
  static String _importDirectiveBringing(ClassElement element, String name) {
    for (final fragment in element.library.fragments) {
      for (final import in fragment.libraryImports) {
        if (import.prefix != null || import.namespace.get2(name) == null) {
          continue;
        }
        if (import.uri case DirectiveUriWithRelativeUriString(
          :final relativeUriString,
        )) {
          return "import '$relativeUriString';";
        }
      }
    }
    return "import 'package:spring_core_dart/spring_core_dart.dart';";
  }

  EqualsAndHashCodeModel _readEqualsAndHashCode(
    ClassElement element,
    ConstantReader reader,
  ) {
    final name = element.name!;
    final callSuper = reader.peek('callSuper')?.boolValue ?? false;
    final selection = _selectedFields(element, 'EqualsAndHashCode', reader);
    final superclassPart = callSuper
        ? _superclassPart(element, 'EqualsAndHashCode')
        : SuperclassPart.none;
    final mutable = [
      for (final field in selection.fields)
        if (!field.isFinal && !field.isConst) field.name!,
    ];
    if (mutable.isNotEmpty) {
      final quoted = mutable.map((field) => "'$field'").join(', ');
      final one = mutable.length == 1;
      warnings.add(
        '@EqualsAndHashCode on $name: the field${one ? '' : 's'} '
        '${mutable.join(', ')} of hashCode ${one ? 'is' : 'are'} not final, '
        'so a $name in a Set or as a Map key is lost when '
        '${one ? 'it changes' : 'they change'}. Make ${one ? 'it' : 'them'} '
        'final, or exclude ${one ? 'it' : 'them'} (exclude: [$quoted]).',
      );
    }
    return EqualsAndHashCodeModel(
      [
        for (final field in selection.fields)
          ObjectField(
            field,
            comparedByContent: _comparesByContent(field.type),
          ),
      ],
      superclassPart: superclassPart,
    );
  }

  ToStringModel _readToString(ClassElement element, ConstantReader reader) {
    final name = element.name!;
    final callSuper = reader.peek('callSuper')?.boolValue ?? false;
    final selection = _selectedFields(element, 'ToString', reader);
    final superclassPart = callSuper
        ? _superclassPart(element, 'ToString')
        : SuperclassPart.none;
    final mask = _stringList(reader, 'mask') ?? const [];
    final reveal = _stringList(reader, 'reveal') ?? const [];
    final written = {for (final field in selection.fields) field.name!};
    for (final (option, names) in [('mask', mask), ('reveal', reveal)]) {
      for (final field in names) {
        if (!selection.declared.containsKey(field)) {
          throw _unknownField(element, 'ToString', option, field, selection);
        }
        if (selection.excluded.contains(field)) {
          throw InvalidGenerationSource(
            '@ToString on $name: "$field" is in both $option and exclude; a '
            'field that is not written needs no $option. Remove it from one '
            'of the two.',
            element: element,
          );
        }
        if (!written.contains(field)) {
          throw InvalidGenerationSource(
            '@ToString on $name: $option names "$field", which is not '
            'written (${field.startsWith('_') ? 'private' : 'not included'}); '
            'remove it from $option.',
            element: element,
          );
        }
      }
    }
    final both = [
      for (final field in mask)
        if (reveal.contains(field)) field,
    ];
    if (both.isNotEmpty) {
      throw InvalidGenerationSource(
        '@ToString on $name: ${both.map((f) => '"$f"').join(', ')} '
        '${both.length == 1 ? 'is' : 'are'} in both mask and reveal; keep '
        '${both.length == 1 ? 'it' : 'them'} in one of the two.',
        element: element,
      );
    }
    for (final field in reveal) {
      if (!SecretNames.looksSecret(field)) {
        throw InvalidGenerationSource(
          '@ToString on $name: reveal names "$field", whose name does not '
          'look secret, so it is written as it is already; remove it from '
          'reveal.',
          element: element,
        );
      }
    }
    return ToStringModel(
      [
        for (final field in selection.fields)
          ObjectField(
            field,
            comparedByContent: false,
            masked:
                mask.contains(field.name) ||
                (SecretNames.looksSecret(field.name!) &&
                    !reveal.contains(field.name)),
          ),
      ],
      includeNames: reader.peek('includeNames')?.boolValue ?? true,
      superclassPart: superclassPart,
    );
  }

  // Where the superclass's part of `callSuper: true` comes from: the
  // described superclass's (the superclass's member is IntrospectedObject's,
  // and the closest class above with either annotation defines it), else
  // the superclass's own; fails the build when the class extends only
  // Object, or the superclass's member is Object's or IntrospectedObject's
  // without a description that defines it.
  SuperclassPart _superclassPart(ClassElement element, String annotation) {
    final name = element.name!;
    final superclass = element.supertype;
    final text = annotation == 'ToString';
    final member = text ? 'toString' : '==';
    if (superclass == null || superclass.isDartCoreObject) {
      throw InvalidGenerationSource(
        '@$annotation(callSuper: true) on $name: $name extends no class but '
        "Object, whose members are identity and \"Instance of '...'\"; leave "
        'callSuper out.',
        element: element,
      );
    }
    final superName = superclass.element.name ?? '?';
    final effective = _concreteMemberOf(superclass, member, element.library);
    if (_belongsToIntrospectedObject(effective)) {
      final described = _describedSuperclass(element);
      if (described != null &&
          (text ? _definesToString(described) : _definesEquals(described))) {
        return SuperclassPart.described;
      }
      throw InvalidGenerationSource(
        '@$annotation(callSuper: true) on $name: $superName mixes in '
        'IntrospectedObject, but no class from it up has @$annotation, so '
        'its $member is identity${text ? '' : ' (no two objects equal)'}. '
        'Give $superName @$annotation(), or leave callSuper out.',
        element: element,
      );
    }
    if (effective == null || effective.library.isDartCore) {
      throw InvalidGenerationSource(
        text
            ? '@ToString(callSuper: true) on $name: no class above $name has '
                  "a toString() of its own ($superName's is Object's: "
                  "\"Instance of '$superName'\"), which tells nothing. Give "
                  '$superName @ToString (or a toString() of its own), or '
                  'leave callSuper out.'
            : '@EqualsAndHashCode(callSuper: true) on $name: no class above '
                  "$name has an == of its own ($superName's is Object's: "
                  'identity), so no two ${name}s would be equal. Give '
                  '$superName @EqualsAndHashCode (or an == of its own), or '
                  'leave callSuper out.',
        element: element,
      );
    }
    return SuperclassPart.inherited;
  }

  // The closest class above [element] with `@EqualsAndHashCode` or
  // `@ToString`: the one whose description its objects would use without
  // their own.
  static InterfaceElement? _describedSuperclass(InterfaceElement element) {
    for (
      var type = element.supertype;
      type != null && !type.isDartCoreObject;
      type = type.superclass
    ) {
      if (equalsAndHashCodeChecker.hasAnnotationOfExact(type.element) ||
          toStringChecker.hasAnnotationOfExact(type.element)) {
        return type.element;
      }
    }
    return null;
  }

  // Whether the description of [element] (a described class) defines `==`
  // and `hashCode`: generated, or its own described superclass's.
  static bool _definesEquals(InterfaceElement element) {
    if (equalsAndHashCodeChecker.hasAnnotationOfExact(element)) {
      return true;
    }
    final above = _describedSuperclass(element);
    return above != null && _definesEquals(above);
  }

  // The same for `toString()`.
  static bool _definesToString(InterfaceElement element) {
    if (toStringChecker.hasAnnotationOfExact(element)) {
      return true;
    }
    final above = _describedSuperclass(element);
    return above != null && _definesToString(above);
  }

  // The instance fields [element] declares (not its getters): those the
  // annotations choose from.
  static List<FieldElement> _declaredFields(ClassElement element) => [
    for (final field in element.fields)
      if (!field.isStatic &&
          field.name != null &&
          (field.isOriginDeclaration || field.isOriginDeclaringFormalParameter))
        field,
  ];

  // The fields of [annotation] on [element]: its `include` exactly, or all
  // public ones but its `exclude`. Fails the build for both at once, a
  // name that is no instance field of the class and a private field in
  // `include`; warns about the private fields left out unless excluded.
  _FieldSelection _selectedFields(
    ClassElement element,
    String annotation,
    ConstantReader reader,
  ) {
    final name = element.name!;
    final include = _stringList(reader, 'include');
    final exclude = _stringList(reader, 'exclude');
    if (include != null && exclude != null) {
      throw InvalidGenerationSource(
        '@$annotation on $name: include and exclude cannot be given '
        'together; name the fields to use (include) or those to leave out '
        '(exclude).',
        element: element,
      );
    }
    final fields = _declaredFields(element);
    final selection = _FieldSelection(
      {for (final field in fields) field.name!: field},
      exclude?.toSet() ?? const {},
    );
    for (final (option, names) in [
      ('include', include),
      ('exclude', exclude),
    ]) {
      for (final field in names ?? const <String>[]) {
        if (!selection.declared.containsKey(field)) {
          throw _unknownField(element, annotation, option, field, selection);
        }
      }
    }
    if (include != null) {
      final private = [
        for (final field in include)
          if (selection.declared[field]!.isPrivate) field,
      ];
      if (private.isNotEmpty) {
        throw InvalidGenerationSource(
          '@$annotation on $name: include names the private field '
          '${private.join(', ')}, which the generated code (another library) '
          'cannot read; make it public or leave it out.',
          element: element,
        );
      }
      selection.fields.addAll([
        for (final field in fields)
          if (include.contains(field.name)) field,
      ]);
      return selection;
    }
    final private = [
      for (final field in fields)
        if (field.isPrivate && !selection.excluded.contains(field.name))
          field.name!,
    ];
    if (private.isNotEmpty) {
      final quoted = private.map((field) => "'$field'").join(', ');
      final one = private.length == 1;
      warnings.add(
        '@$annotation on $name leaves out the private '
        'field${one ? '' : 's'} ${private.join(', ')}: the generated code '
        '(another library) cannot read ${one ? 'it' : 'them'}. Exclude '
        '${one ? 'it' : 'them'} (exclude: [$quoted]) to say so, or make '
        '${one ? 'it' : 'them'} public.',
      );
    }
    selection.fields.addAll([
      for (final field in fields)
        if (!field.isPrivate && !selection.excluded.contains(field.name)) field,
    ]);
    return selection;
  }

  static InvalidGenerationSource _unknownField(
    ClassElement element,
    String annotation,
    String option,
    String field,
    _FieldSelection selection,
  ) {
    final name = element.name!;
    final other = element.getField(field) ?? element.getGetter(field);
    final what = switch (other) {
      FieldElement(isStatic: true) => ' is a static field, not',
      GetterElement(isStatic: true) => ' is a static getter, not',
      GetterElement() || FieldElement() => ' is a getter, not',
      _ => ' is not',
    };
    final names = selection.declared.keys;
    final close = closestName(field, names);
    return InvalidGenerationSource(
      '@$annotation on $name: $option names "$field", which$what an '
      'instance field of $name'
      '${close == null ? '' : ' (did you mean "$close"?)'}. The fields: '
      '${names.isEmpty ? 'none' : names.join(', ')}.',
      element: element,
    );
  }

  static List<String>? _stringList(ConstantReader reader, String option) {
    final value = reader.peek(option);
    if (value == null || value.isNull) {
      return null;
    }
    return [
      for (final DartObject item in value.listValue) item.toStringValue() ?? '',
    ];
  }

  // A collection, or a type that may hold one.
  static bool _comparesByContent(DartType type) => switch (type) {
    DynamicType() => true,
    TypeParameterType(:final bound) =>
      bound is! InterfaceType || _comparesByContent(bound),
    InterfaceType() =>
      type.isDartCoreObject ||
          [type, ...type.allSupertypes].any(
            (t) => t.isDartCoreIterable || t.isDartCoreMap,
          ),
    _ => false,
  };

  // A member named [member] (of the class or above it) would win over the
  // extension's.
  static void _rejectMemberNamed(
    ClassElement element,
    String annotation,
    String member,
  ) {
    for (final type in [element.thisType, ...element.allSupertypes]) {
      if (type.isDartCoreObject) {
        continue;
      }
      final declaring = type.element;
      if (declaring.getMethod(member) case final method?
          when !method.isStatic) {
        throw _memberWinsOverExtension(element, annotation, declaring, member);
      }
      if (declaring.getGetter(member) case final getter?
          when !getter.isStatic) {
        throw _memberWinsOverExtension(element, annotation, declaring, member);
      }
      if (declaring.getSetter(member) case final setter?
          when !setter.isStatic) {
        throw _memberWinsOverExtension(element, annotation, declaring, member);
      }
    }
  }

  static InvalidGenerationSource _memberWinsOverExtension(
    ClassElement element,
    String annotation,
    InterfaceElement declaring,
    String member,
  ) => InvalidGenerationSource(
    '@$annotation on ${element.name}: ${declaring.name} has a member named '
    '$member, which would win over the generated extension; rename it or '
    'leave the annotation out.',
    element: element,
  );

  // The constructor [annotation] names ([constructorName], the unnamed one
  // when `null`): public, else the build fails.
  static ConstructorElement _constructorNamed(
    ClassElement element,
    String annotation,
    String? constructorName,
  ) {
    final name = element.name!;
    final constructor = constructorName == null
        ? element.unnamedConstructor
        : element.getNamedConstructor(constructorName);
    if (constructor == null) {
      final constructors = [
        for (final candidate in element.constructors)
          if (candidate.isPublic) _constructorCall(candidate, name),
      ];
      final close = constructorName == null
          ? null
          : closestName(constructorName, [
              for (final candidate in element.constructors)
                if (candidate.name case final name? when name != 'new') name,
            ]);
      final missing = constructorName == null
          ? 'unnamed constructor'
          : 'constructor named "$constructorName"';
      final known = constructors.isEmpty
          ? 'none that is public'
          : constructors.join(', ');
      throw InvalidGenerationSource(
        '@$annotation on $name: $name has no $missing'
        '${close == null ? '' : ' (did you mean "$close"?)'}; name the '
        "constructor that makes the copy with @$annotation(constructor: '...')."
        ' Its constructors: $known.',
        element: element,
      );
    }
    if (constructor.isPrivate) {
      throw InvalidGenerationSource(
        '@$annotation on $name: the constructor '
        '${_constructorCall(constructor, name)} is private, so the generated '
        'code (another library) cannot call '
        "it; name a public one with @$annotation(constructor: '...').",
        element: element,
      );
    }
    return constructor;
  }

  // The public instance getter of [element] named [name] whose value fits
  // [parameter]; `null` when there is none.
  static GetterElement? _publicGetterFitting(
    ClassElement element,
    String name,
    FormalParameterElement parameter,
  ) {
    final getter = element.thisType.lookUpGetter(name, element.library);
    if (getter == null || !getter.isPublic || getter.isStatic) {
      return null;
    }
    return element.library.typeSystem.isAssignableTo(
          getter.returnType,
          parameter.type,
        )
        ? getter
        : null;
  }

  CopyWithModel _readCopyWith(ClassElement element, ConstantReader reader) {
    final name = element.name!;
    _rejectMemberNamed(element, 'CopyWith', 'copyWith');
    final fields = _selectedFields(element, 'CopyWith', reader).fields;
    final constructor = _constructorNamed(
      element,
      'CopyWith',
      reader.peek('constructor')?.stringValue,
    );
    final copied = {for (final field in fields) field.name!: field};
    final set = <String>{};
    final arguments = <CopyWithArgument>[];
    for (final parameter in constructor.formalParameters) {
      final parameterName = parameter.name ?? '';
      final field = parameter is FieldFormalParameterElement
          ? parameter.field
          : null;
      if (field != null && field.isPrivate) {
        if (parameter.isRequired) {
          throw InvalidGenerationSource(
            '@CopyWith on $name: the parameter $parameterName of '
            '${_constructorCall(constructor, name)} sets the private field '
            '${field.name}, which the generated code (another library) '
            'cannot read to keep it; make the field public, or name another '
            "constructor with @CopyWith(constructor: '...').",
            element: element,
          );
        }
        continue;
      }
      final fieldName = field?.name ?? parameterName;
      if (copied[fieldName] case final copiedField?) {
        set.add(fieldName);
        arguments.add(
          CopyWithArgument(parameter, changeableField: copiedField),
        );
        continue;
      }
      if (_publicGetterFitting(element, fieldName, parameter) != null) {
        arguments.add(CopyWithArgument(parameter, keptGetter: fieldName));
        continue;
      }
      if (parameter.isRequired) {
        throw InvalidGenerationSource(
          '@CopyWith on $name: the required parameter $parameterName of '
          '${_constructorCall(constructor, name)} sets no field $name has to '
          'read, so copyWith cannot pass it on; add a public field '
          '$parameterName, '
          "or name another constructor with @CopyWith(constructor: '...').",
          element: element,
        );
      }
    }
    for (final field in fields) {
      final fieldName = field.name!;
      if (!set.contains(fieldName)) {
        throw InvalidGenerationSource(
          '@CopyWith on $name: no parameter of '
          '${_constructorCall(constructor, name)} sets the field $fieldName, '
          'so a copy could not take its value; '
          'add one (this.$fieldName), or exclude the field (exclude: '
          "['$fieldName']).",
          element: element,
        );
      }
      if (_scan.privateType(field.type) case final private?) {
        throw InvalidGenerationSource(
          '@CopyWith on $name: the field $fieldName has the private type '
          '${private.element.name}, which copyWith (another library) cannot '
          'name; make the type public, or exclude the field (exclude: '
          "['$fieldName']).",
          element: element,
        );
      }
    }
    return CopyWithModel(fields, constructor, arguments);
  }

  // Why [element] cannot have the annotations, or `null`.
  static String? _unsupportedClassReason(ClassElement element) {
    final name = element.name ?? '?';
    if (element.isPrivate) {
      return 'the class is private, so the generated code (the '
          '.spring.introspection.dart file, another library) cannot name it; '
          'make the class public.';
    }
    if (element.isMixinApplication) {
      return 'a mixin application (`class $name = ...`) declares no fields; '
          'declare a class with a body.';
    }
    if (element.isAbstract || element.isSealed) {
      return 'an abstract class has no instances of its own (an interface '
          'whose implementation the generator writes, a repository or an '
          'HTTP client, included); annotate the class that implements it.';
    }
    if (element.isInterface) {
      return 'an interface class is a type to implement; annotate the '
          'classes that implement it, or drop `interface`.';
    }
    if (_configurationChecker.hasAnnotationOf(element)) {
      return 'a @Configuration class declares beans, it holds no data; '
          'annotate the classes of the data it makes.';
    }
    if (_aspectChecker.hasAnnotationOf(element)) {
      return 'an aspect holds advice, no data; annotate the classes of the '
          'data it handles.';
    }
    return null;
  }
}

// The fields an annotation chose, with what it was given.
final class _FieldSelection {
  _FieldSelection(this.declared, this.excluded);

  // The instance fields the class declares, by name.
  final Map<String, FieldElement> declared;

  // The names of `exclude`.
  final Set<String> excluded;

  // The fields chosen, in their declaration order.
  final fields = <FieldElement>[];
}

// Whether an annotation of [element] calls a constructor of a class named
// as one of the three, or reads a constant of such a class: the annotations
// of every class and member are read so, without evaluating them
// (`@override` everywhere).
bool _mayHaveObjectMethodsAnnotation(Element element) =>
    element.metadata.annotations.any(
      (annotation) => switch (annotation.element) {
        ConstructorElement(:final enclosingElement) =>
          _annotationNames.contains(
            enclosingElement.name,
          ),
        GetterElement(:final returnType) => _annotationNames.contains(
          returnType.element?.name,
        ),
        _ => false,
      },
    );

// `Book(...)` or `Book.of(...)`: a constructor as the code calls it.
String _constructorCall(ConstructorElement constructor, String className) =>
    switch (constructor.name) {
      null || 'new' => '$className(...)',
      final name => '$className.$name(...)',
    };

// "@A", "@A and @B", "@A, @B and @C".
String _joinedWithAnd(List<String> items) => switch (items) {
  [] => '',
  [final only] => only,
  [...final first, final last] => '${first.join(', ')} and $last',
};
