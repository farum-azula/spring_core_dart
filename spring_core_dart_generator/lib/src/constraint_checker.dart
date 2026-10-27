import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
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
/// Invalid attributes are reported too (`@Size(min: -1)`, `min > max`,
/// negative `@Digits`, malformed `@DecimalMin` values and regular
/// expressions), as are `@Each` / `@EachKey` element constraints that do
/// not fit the element type or a declared type that is no collection.
///
/// `dynamic` and type parameters are not checked (their values are only
/// known at runtime); `Future<T>` and `FutureOr<T>` (method return values)
/// are checked as `T`. Custom constraints are never checked.
String? unsupportedConstraint(
  DartObject annotation,
  DartType declared,
  String target,
) {
  final annotationType = annotation.type;
  if (annotationType is InterfaceType &&
      _isSpring(annotationType.element) &&
      (annotationType.element.name == 'Each' ||
          annotationType.element.name == 'EachKey')) {
    return _elementConstraints(
      annotation,
      annotationType.element.name!,
      declared,
      target,
    );
  }
  final constraint = _builtIn(annotationType);
  if (constraint == null) {
    return null;
  }
  final (name, base, kinds) = constraint;
  if (_invalidParameters(base, annotation, target) case final problem?) {
    return problem;
  }
  final type = _awaited(declared);
  if (type is DynamicType || type is TypeParameterType || type is InvalidType) {
    return null;
  }
  final checked = type;
  if (checked is InterfaceType && kinds.any((k) => _isKind(checked, k))) {
    return null;
  }
  final shown = type.getDisplayString().replaceAll('?', '');
  return '@$name on $target: it validates ${kinds.join(', ')} values, not '
      "$shown (like Hibernate Validator's UnexpectedTypeException). Remove "
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

// The annotation's own name, the name of its built-in constraint class
// (itself or a superclass from spring_core_dart) and the kinds that class
// supports.
(String, String, List<String>)? _builtIn(DartType? type) {
  if (type is! InterfaceType) {
    return null;
  }
  for (final candidate in [type, ...type.allSupertypes]) {
    final element = candidate.element;
    final kinds = _supported[element.name];
    if (kinds != null && _isSpring(element)) {
      return (type.element.name ?? element.name!, element.name!, kinds);
    }
  }
  return null;
}

bool _isSpring(Element element) =>
    element.library?.uri.pathSegments.firstOrNull == 'spring_core_dart';

// Whether [type] is (or implements) the `dart:core` class [kind].
bool _isKind(InterfaceType type, String kind) => [
  type,
  ...type.allSupertypes,
].any((t) => t.element.name == kind && t.element.library.isDartCore);

// `@Each` / `@EachKey`: the container fits, and every element constraint
// fits the element (or key) type.
String? _elementConstraints(
  DartObject annotation,
  String kind,
  DartType declared,
  String target,
) {
  final type = _awaited(declared);
  if (type is DynamicType || type is TypeParameterType || type is InvalidType) {
    return null;
  }
  DartType? element;
  if (type is InterfaceType) {
    final map = _asCore(type, 'Map');
    final iterable = _asCore(type, 'Iterable');
    if (map != null) {
      element = map.typeArguments[kind == 'EachKey' ? 0 : 1];
    } else if (iterable != null && kind == 'Each') {
      element = iterable.typeArguments.single;
    }
  }
  if (element == null) {
    final shown = type.getDisplayString().replaceAll('?', '');
    final constrained = kind == 'EachKey'
        ? 'keys of a Map'
        : 'elements of an Iterable or the values of a Map';
    return '@$kind on $target: it constrains the $constrained'
        ', not $shown. Remove it or change the type.';
  }
  final constraints = _field(annotation, 'constraints')?.toListValue() ?? [];
  for (final constraint in constraints) {
    final problem = unsupportedConstraint(
      constraint,
      element,
      '$target (${kind == 'EachKey' ? 'key' : 'element'})',
    );
    if (problem != null) {
      return problem;
    }
  }
  return null;
}

// Hibernate Validator's checks of constraint attributes (done there when
// the validator is initialized): `@Size(min: -1)`, `min > max`, negative
// `@Digits`, malformed `@DecimalMin` values and regular expressions.
String? _invalidParameters(String kind, DartObject annotation, String target) {
  int? integer(String name) => _field(annotation, name)?.toIntValue();
  String? text(String name) => _field(annotation, name)?.toStringValue();
  final problem = switch (kind) {
    'Size' => switch ((integer('min'), integer('max'))) {
      (final min?, _) when min < 0 => 'the min parameter cannot be negative',
      (_, final max?) when max < 0 => 'the max parameter cannot be negative',
      (final min?, final max?) when max < min =>
        'min ($min) is greater than max ($max)',
      _ => null,
    },
    'Digits' => switch ((integer('integer'), integer('fraction'))) {
      (final integer?, _) when integer < 0 =>
        'the length of the integer part cannot be negative',
      (_, final fraction?) when fraction < 0 =>
        'the length of the fraction part cannot be negative',
      _ => null,
    },
    'DecimalMin' || 'DecimalMax' => switch (text('value')) {
      final value? when !_decimal.hasMatch(value.trim()) =>
        '"$value" is not a decimal number',
      _ => null,
    },
    'Matches' || 'Email' => switch (text('regexp')) {
      final regexp? when _invalidRegExp(regexp) =>
        'invalid regular expression "$regexp"',
      _ => null,
    },
    _ => null,
  };
  if (problem == null) {
    return null;
  }
  return 'Invalid @${annotation.type?.element?.name ?? kind} on $target: '
      '$problem (Hibernate Validator rejects it when validating).';
}

final _decimal = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

bool _invalidRegExp(String regexp) {
  try {
    RegExp(regexp);
    return false;
  } on FormatException {
    return true;
  }
}

// The field [name] of [object] or of one of its superclass parts.
DartObject? _field(DartObject object, String name) {
  for (
    DartObject? part = object;
    part != null;
    part = part.getField('(super)')
  ) {
    if (part.getField(name) case final value?) {
      return value;
    }
  }
  return null;
}

// [type] without `Future` / `FutureOr` (method return values).
DartType _awaited(DartType declared) {
  var type = declared;
  while (type is InterfaceType &&
      (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
      type.typeArguments.isNotEmpty) {
    type = type.typeArguments.single;
  }
  return type;
}

// [type] as the `dart:core` class [name] (with its type arguments).
InterfaceType? _asCore(InterfaceType type, String name) {
  for (final candidate in [type, ...type.allSupertypes]) {
    if (candidate.element.name == name &&
        candidate.element.library.isDartCore) {
      return candidate;
    }
  }
  return null;
}
