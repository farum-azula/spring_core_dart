/// The value of [values] named [source], matched like Spring Boot's
/// `LenientObjectToEnumConverterFactory`: the exact name first, then
/// ignoring case and every character that is not a letter or digit, so
/// `my-value`, `MY_VALUE` and `myValue` all find `myValue`. [alias] gives
/// further names of a value (a JSON form, ...). `null` when none matches.
E? findLenientEnum<E extends Enum>(
  List<E> values,
  String source, {
  Object? Function(E value)? alias,
}) {
  for (final value in values) {
    if (value.name == source) {
      return value;
    }
  }
  final canonical = _canonical(source);
  for (final value in values) {
    if (_canonical(value.name) == canonical ||
        (alias != null && _canonical('${alias(value)}') == canonical)) {
      return value;
    }
  }
  return null;
}

final _separators = RegExp('[^A-Za-z0-9]');

String _canonical(String name) =>
    name.replaceAll(_separators, '').toLowerCase();
