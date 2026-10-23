import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

/// Checks the built-in constraints of `package:spring_core_dart` against
/// the declared type of what they annotate, like Hibernate Validator's
/// `UnexpectedTypeException` (here at build time): `@Size` on an `int` or
/// `@NotBlank` on a `List` would silently pass at runtime.
///
/// ```dart
/// // @Introspected() class Form { @NotBlank() int age = 0; }
/// unsupportedConstraint(notBlank, intType, 'Form.age');
/// // '@NotBlank on Form.age: it validates String values, not int ...'
/// ```
///
/// `dynamic` and type parameters are not checked (their values are only
/// known at runtime); `Future<T>` and `FutureOr<T>` (method return values)
/// are checked as `T`. Custom constraints are never checked.
String? unsupportedConstraint(
  DartObject annotation,
  DartType declared,
  String target,
) {
  final constraint = _builtIn(annotation.type);
  if (constraint == null) {
    return null;
  }
  final (name, kinds) = constraint;
  var type = declared;
  while (type is InterfaceType &&
      (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
      type.typeArguments.isNotEmpty) {
    type = type.typeArguments.single;
  }
  if (type is DynamicType || type is TypeParameterType || type is InvalidType) {
    return null;
  }
  final checked = type;
  if (checked is InterfaceType && kinds.any((k) => _isKind(checked, k))) {
    return null;
  }
  final shown = type.getDisplayString().replaceAll('?', '');
  return '@$name on $target: it validates ${kinds.join(', ')} values, not '
      '$shown (like Hibernate Validator\'s UnexpectedTypeException). Remove '
      'it or change the type.';
}

// Constraint class name (or a subclass's built-in superclass) → supported
// value kinds.
const _supported = <String, List<String>>{
  'NotBlank': ['String'],
  'Matches': ['String'],
  'Email': ['String'],
  'NotEmpty': ['String', 'Iterable', 'Map'],
  'Size': ['String', 'Iterable', 'Map'],
  'Min': _numeric,
  'Max': _numeric,
  'DecimalMin': _numeric,
  'DecimalMax': _numeric,
  'Positive': _numeric,
  'PositiveOrZero': _numeric,
  'Negative': _numeric,
  'NegativeOrZero': _numeric,
  'Digits': _numeric,
  'AssertTrue': ['bool'],
  'AssertFalse': ['bool'],
  'Past': ['DateTime'],
  'PastOrPresent': ['DateTime'],
  'FutureDate': ['DateTime'],
  'FutureOrPresent': ['DateTime'],
};

const _numeric = ['num', 'BigInt', 'String'];

// The annotation's own name and the kinds of its built-in constraint
// class (itself or a superclass from spring_core_dart).
(String, List<String>)? _builtIn(DartType? type) {
  if (type is! InterfaceType) {
    return null;
  }
  for (final candidate in [type, ...type.allSupertypes]) {
    final element = candidate.element;
    final kinds = _supported[element.name];
    if (kinds != null &&
        element.library.uri.pathSegments.firstOrNull == 'spring_core_dart') {
      return (type.element.name ?? element.name!, kinds);
    }
  }
  return null;
}

// Whether [type] is (or implements) the `dart:core` class [kind].
bool _isKind(InterfaceType type, String kind) => [
  type,
  ...type.allSupertypes,
].any((t) => t.element.name == kind && t.element.library.isDartCore);
