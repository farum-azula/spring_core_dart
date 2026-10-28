/// Finds the value of [values] whose name matches [source] loosely, or
/// `null` when none does.
///
/// Configuration writes enum values in many styles (`ON_SHOW_SELECTED`,
/// `on-show-selected`, `onShowSelected`), so the conversion service and
/// the data binder use this instead of an exact `byName`. The exact name
/// wins first; then names are compared ignoring case and every character
/// that is not a letter or digit. [alias] gives one more name per value
/// (a JSON form, for example) that is compared the same loose way.
///
/// Internal: not exported. Applications get this matching through
/// conversion and binding, never by calling it.
///
/// Spring (Java): Spring Boot's `LenientObjectToEnumConverterFactory`.
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
