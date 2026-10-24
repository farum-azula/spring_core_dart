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

final _jsonValue = TypeChecker.typeNamedLiterally(
  'JsonValue',
  inPackage: 'spring_core_dart',
);
final _jsonProperty = TypeChecker.typeNamedLiterally(
  'JsonProperty',
  inPackage: 'spring_core_dart',
);

/// Checks the `@JsonValue` members of the `@Introspected` class [element]
/// and of the classes it extends: at most one per class, public, and an
/// instance field, getter or method without required parameters.
void checkJsonAnnotations(InterfaceElement element) {
  for (final current in [
    element,
    for (final supertype in element.allSupertypes)
      if (!supertype.isDartCoreObject) supertype.element,
  ]) {
    _jsonValueMember(current, enumConstants: false);
  }
}

/// The name of the `@JsonValue` field or getter of [element] (checked), or
/// `null`.
String? enumJsonValueMember(EnumElement element) =>
    _jsonValueMember(element, enumConstants: true);

/// The `jsonValue` function of an `EnumType` for [element], whose type is
/// written as [enumType]: `(value) => value.<field>` for a `@JsonValue`
/// field or getter, a lookup of the `@JsonProperty` names of its constants
/// (`(value) => const {Color.red: 'RED'}[value] ?? value.name`), or `null`
/// when the enum has neither (the JSON form is the name).
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
