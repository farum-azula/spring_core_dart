import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';

// Build-time checks and code for the JSON annotations of
// `package:spring_core_dart` that the runtime cannot check itself:
// `@JsonValue` (one per class; on a field, getter or method without
// parameters) and `@JsonProperty` on enum constants.
//
// ```dart
// // @Introspected() class Isbn { @JsonValue() final String a; @JsonValue() final String b; }
// checkJsonAnnotations(isbnElement);
// // throws: 'Isbn has more than one @JsonValue (a, b) ...'
// ```

const _jsonValue = TypeChecker.typeNamedLiterally(
  'JsonValue',
  inPackage: 'spring_core_dart',
);
const _jsonProperty = TypeChecker.typeNamedLiterally(
  'JsonProperty',
  inPackage: 'spring_core_dart',
);

/// Fails the build when a `@JsonValue` of the `@Introspected` class
/// [element] or of one of its supertypes (`Object` aside) cannot work.
///
/// `@JsonValue` makes the object serialize as the value of one member, so
/// a class may have at most one, and it must be a public instance field,
/// getter or method without required parameters (not a setter). The
/// runtime would only notice a mistake when it serializes the object.
void checkJsonAnnotations(InterfaceElement element) {
  for (final current in [
    element,
    for (final supertype in element.allSupertypes)
      if (!supertype.isDartCoreObject) supertype.element,
  ]) {
    _jsonValueMember(current, enumConstants: false);
  }
}

/// The name of the `@JsonValue` field or getter of the enum [element], or
/// `null` when it has none.
///
/// Fails the build under the rules of [checkJsonAnnotations]; on an enum
/// a method is not accepted either.
String? enumJsonValueMember(EnumElement element) =>
    _jsonValueMember(element, enumConstants: true);

/// The `jsonValue` function of the `EnumType` generated for [element],
/// which writes a constant as JSON; [enumType] is how the generated code
/// names the enum, and [closure] builds the function.
///
/// - With a `@JsonValue` field or getter: `(value) => value.<field>`.
/// - With `@JsonProperty` names on constants: a lookup,
///   `(value) => const {Color.red: 'RED'}[value] ?? value.name`.
/// - With neither: `null`, and the JSON form is the constant's name.
///
/// An enum with both fails the build, since only one can apply.
Expression? enumJsonValue(
  EnumElement element,
  Reference enumType,
  Expression Function(List<String> parameters, Code body) closure,
) {
  final member = enumJsonValueMember(element);
  final names = <String, String>{};
  for (final field in element.fields) {
    final name = field.name;
    if (!field.isEnumConstant || name == null) {
      continue;
    }
    final property = _jsonProperty.firstAnnotationOf(field);
    final json = property?.getField('name')?.toStringValue();
    if (json != null && json.isNotEmpty) {
      names[name] = json;
    }
  }
  if (member != null && names.isNotEmpty) {
    throw InvalidGenerationSource(
      'Enum ${element.name} has both a @JsonValue ($member) and '
      '@JsonProperty names on its constants (${names.keys.join(', ')}); '
      'use one of them.',
      element: element,
    );
  }
  if (member != null) {
    return closure(['value'], refer('value').property(member).code);
  }
  if (names.isEmpty) {
    return null;
  }
  final lookup = literalConstMap({
    for (final MapEntry(:key, :value) in names.entries)
      enumType.property(key): literalString(value, raw: true),
  });
  return closure(
    ['value'],
    lookup
        .index(refer('value'))
        .ifNullThen(refer('value').property('name'))
        .code,
  );
}

// The `@JsonValue` member declared by [element] (fields, getters and, for
// classes, methods), after checking there is at most one and that it can
// be used.
String? _jsonValueMember(
  InterfaceElement element, {
  required bool enumConstants,
}) {
  final marked = <Element>[];
  for (final field in element.fields) {
    if (field.isOriginGetterSetter) {
      // A getter (or setter) declared on its own: checked below.
      continue;
    }
    final getter = field.getter;
    if (_jsonValue.hasAnnotationOf(field) ||
        (getter != null && _jsonValue.hasAnnotationOf(getter))) {
      marked.add(field);
    }
  }
  for (final getter in element.getters) {
    if (getter.isOriginDeclaration && _jsonValue.hasAnnotationOf(getter)) {
      marked.add(getter);
    }
  }
  for (final setter in element.setters) {
    if (setter.isOriginDeclaration && _jsonValue.hasAnnotationOf(setter)) {
      _fail(element, setter, 'is a setter; mark the field or getter');
    }
  }
  for (final method in element.methods) {
    if (_jsonValue.hasAnnotationOf(method)) {
      if (enumConstants) {
        _fail(
          element,
          method,
          'is a method; on an enum, @JsonValue goes on a field or getter',
        );
      }
      if (method.formalParameters.any((p) => p.isRequired)) {
        _fail(element, method, 'has required parameters');
      }
      marked.add(method);
    }
  }
  if (marked.length > 1) {
    throw InvalidGenerationSource(
      '${element.name} has more than one @JsonValue '
      '(${marked.map((m) => m.name).join(', ')}); like Jackson, a class can '
      'be written as one value only.',
      element: marked[1],
    );
  }
  final member = marked.firstOrNull;
  if (member == null) {
    return null;
  }
  if (member.isPrivate) {
    _fail(element, member, 'is private, so generated code cannot read it');
  }
  if (member
      case FieldElement(isStatic: true) ||
          PropertyAccessorElement(isStatic: true) ||
          MethodElement(isStatic: true)) {
    _fail(element, member, 'is static; @JsonValue marks an instance member');
  }
  return member.name;
}

Never _fail(InterfaceElement owner, Element member, String problem) =>
    throw InvalidGenerationSource(
      '@JsonValue on ${owner.name}.${member.name} $problem.',
      element: member,
    );
