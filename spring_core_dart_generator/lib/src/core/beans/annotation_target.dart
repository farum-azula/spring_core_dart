import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/annotation_placement.dart';

const TypeChecker _target = TypeChecker.typeNamedLiterally(
  'Target',
  inPackage: 'meta',
);

/// One value of `TargetKind` (`package:meta`): how messages name it and
/// which declarations it allows, by the analyzer's rules for
/// `invalid_annotation_target`.
final class _TargetRule {
  const _TargetRule(this.label, this.allows);

  final String label;
  final bool Function(Element element) allows;
}

bool _isClass(Element e) => e is ClassElement;
bool _isConstructor(Element e) => e is ConstructorElement;
bool _isEnum(Element e) => e is EnumElement;
bool _isEnumValue(Element e) => e is FieldElement && e.isEnumConstant;
bool _isExtension(Element e) => e is ExtensionElement;
bool _isExtensionType(Element e) => e is ExtensionTypeElement;
bool _isField(Element e) => e is FieldElement && !e.isEnumConstant;
bool _isFunction(Element e) =>
    e is TopLevelFunctionElement || e is LocalFunctionElement;
bool _isGetter(Element e) => e is GetterElement;
bool _isLibrary(Element e) => e is LibraryElement;
bool _isMethod(Element e) => e is MethodElement;
bool _isMixin(Element e) => e is MixinElement;
bool _isOptionalParameter(Element e) =>
    e is FormalParameterElement && e.isOptional;
bool _isParameter(Element e) => e is FormalParameterElement;
bool _isSetter(Element e) => e is SetterElement;
bool _isTopLevelVariable(Element e) => e is TopLevelVariableElement;
bool _isTypedef(Element e) => e is TypeAliasElement;
bool _isTypeParameter(Element e) => e is TypeParameterElement;
bool _isType(Element e) =>
    _isClass(e) || _isEnum(e) || _isMixin(e) || _isTypedef(e);

bool _isOverridableMember(Element e) => switch (e) {
  FieldElement(isStatic: false) ||
  GetterElement(isStatic: false) ||
  MethodElement(isStatic: false) ||
  SetterElement(isStatic: false) => _isOverridableContainer(e.enclosingElement),
  _ => false,
};

bool _isOverridableContainer(Element? e) =>
    e is ClassElement || e is ExtensionTypeElement || e is MixinElement;

// An annotation on the first directive is on the library's element, so a
// directive kind accepts a library: valid code is never refused.
const Map<String, _TargetRule> _rules = {
  'classType': _TargetRule('classes', _isClass),
  'constructor': _TargetRule('constructors', _isConstructor),
  'directive': _TargetRule('directives', _isLibrary),
  'enumType': _TargetRule('enums', _isEnum),
  'enumValue': _TargetRule('enum values', _isEnumValue),
  'exportDirective': _TargetRule('export directives', _isLibrary),
  'extension': _TargetRule('extensions', _isExtension),
  'extensionType': _TargetRule('extension types', _isExtensionType),
  'field': _TargetRule('fields', _isField),
  'function': _TargetRule('top-level functions', _isFunction),
  'getter': _TargetRule('getters', _isGetter),
  'importDirective': _TargetRule('import directives', _isLibrary),
  'library': _TargetRule('libraries', _isLibrary),
  'method': _TargetRule('methods', _isMethod),
  'mixinType': _TargetRule('mixins', _isMixin),
  'optionalParameter': _TargetRule('optional parameters', _isOptionalParameter),
  'overridableMember': _TargetRule('overridable members', _isOverridableMember),
  'parameter': _TargetRule('parameters', _isParameter),
  'partOfDirective': _TargetRule('part-of directives', _isLibrary),
  'setter': _TargetRule('setters', _isSetter),
  'topLevelVariable': _TargetRule('top-level variables', _isTopLevelVariable),
  'type': _TargetRule('types (classes, enums, mixins or typedefs)', _isType),
  'typedefType': _TargetRule('typedefs', _isTypedef),
  'typeParameter': _TargetRule('type parameters', _isTypeParameter),
};

/// `@Target` of `package:meta` on an annotation class, as a build error: the
/// first placement asked, it decides a site only where the annotation may
/// not be, so its message comes before what another placement would say of
/// that place.
///
/// A class with no `@Target` of its own takes those of the classes it
/// extends, implements or mixes in; with several, a place must suit each.
/// A place keeps the analyzer's rules, so what `invalid_annotation_target`
/// accepts builds, and a line with `// ignore: invalid_annotation_target`
/// (as code generated for `@JsonKey` on a parameter needs) is left alone.
///
/// ```dart
/// @Target({TargetKind.method})
/// class DevBean extends Bean implements Profile { ... }
///
/// @DevBean(['dev']) class Orders {}
/// // @DevBean on class Orders: it can only be used on methods.
/// ```
final class DeclaredTargetPlacement extends AnnotationPlacement {
  /// The placement; it remembers the kinds of each annotation class.
  DeclaredTargetPlacement();

  final _kinds = <InterfaceElement, Set<String>?>{};

  @override
  bool covers(InterfaceType type) => _kindsOf(type.element) != null;

  @override
  bool claims(AnnotationSite site) =>
      !_allowed(_kindsOf(site.annotationType.element)!, site.element) &&
      !_isIgnored(site.element);

  @override
  String? problem(AnnotationSite site) {
    final kinds = _kindsOf(site.annotationType.element)!;
    if (kinds.isEmpty) {
      return '${site.name} on ${site.subject}: the classes it inherits '
          '@Target from have no place in common. Give '
          '${site.annotationType.element.name} a @Target of its own.';
    }
    final labels = [for (final kind in kinds) _rules[kind]!.label]..sort();
    return '${site.name} on ${site.subject}: it can only be used on '
        '${_joined(labels)}.';
  }

  /// Whether a declared `@Target` forbids [site], whichever placement
  /// would otherwise read it.
  bool forbids(AnnotationSite site) =>
      covers(site.annotationType) && claims(site);

  Set<String>? _kindsOf(InterfaceElement element) {
    if (_kinds.containsKey(element)) {
      return _kinds[element];
    }
    return _kinds[element] = _ownKinds(element) ?? _inheritedKinds(element);
  }

  static Set<String>? _ownKinds(InterfaceElement element) {
    final annotation = _target.firstAnnotationOfExact(element);
    if (annotation == null) {
      return null;
    }
    final kinds = {
      for (final kind
          in ConstantReader(annotation).peek('kinds')?.setValue ??
              const <Never>{})
        ?_nameOf(ConstantReader(kind)),
    }.where(_rules.containsKey).toSet();
    return kinds.isEmpty ? null : kinds;
  }

  // `TargetKind` is a class with a `name` in recent versions of meta and
  // an enum in older ones.
  static String? _nameOf(ConstantReader kind) =>
      (kind.peek('name') ?? kind.peek('_name'))?.stringValue;

  Set<String>? _inheritedKinds(InterfaceElement element) {
    final inherited = [
      for (final type in [
        ?element.supertype,
        ...element.interfaces,
        ...element.mixins,
      ])
        ?_kindsOf(type.element),
    ];
    return inherited.isEmpty
        ? null
        : inherited.reduce((a, b) => a.intersection(b));
  }

  static bool _allowed(Set<String> kinds, Element element) {
    final places = [
      element,
      if (element case FieldFormalParameterElement(
        isDeclaring: true,
        :final field?,
      ))
        field,
    ];
    return kinds.any(
      (kind) => places.any((place) => _rules[kind]!.allows(place)),
    );
  }

  static String _joined(List<String> labels) => switch (labels) {
    [final only] => only,
    [...final first, final last] => '${first.join(', ')} or $last',
    _ => '',
  };

  static final _ignoreForFile = RegExp(
    r'//\s*ignore_for_file:.*\binvalid_annotation_target\b',
  );
  static final _ignoreLine = RegExp(
    r'//\s*ignore:.*\binvalid_annotation_target\b',
  );

  // Whether the analyzer's warning is switched off for the file, or for an
  // annotation of the declaration (on its line or the line above).
  static bool _isIgnored(Element element) {
    final fragment = element.firstFragment;
    final source = fragment.libraryFragment?.source;
    if (source == null) {
      return false;
    }
    final text = source.contents.data;
    if (_ignoreForFile.hasMatch(text)) {
      return true;
    }
    if (!_ignoreLine.hasMatch(text)) {
      return false;
    }
    final parsed = parseString(content: text, throwIfDiagnostics: false);
    final annotations = _AnnotationsOfDeclaration(fragment.offset);
    parsed.unit.accept(annotations);
    final lines = text.split('\n');
    return annotations.found.any((annotation) {
      final line = parsed.lineInfo.getLocation(annotation.offset).lineNumber;
      return [
        lines[line - 1],
        if (line > 1) lines[line - 2],
      ].any(_ignoreLine.hasMatch);
    });
  }
}

// The annotations of the innermost declaration around [offset].
final class _AnnotationsOfDeclaration extends RecursiveAstVisitor<void> {
  _AnnotationsOfDeclaration(this.offset);

  final int offset;
  final found = <Annotation>[];
  int _length = -1;

  @override
  void visitAnnotation(Annotation node) {
    final parent = node.parent;
    if (parent.offset <= offset && offset < parent.end) {
      if (_length < 0 || parent.length < _length) {
        _length = parent.length;
        found.clear();
      }
      if (parent.length == _length) {
        found.add(node);
      }
    }
    super.visitAnnotation(node);
  }
}
