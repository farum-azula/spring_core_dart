/// The answer of one link of a chain of responsibility (a string role, a
/// symbol resolver, a value role of a config file) that handles what it is
/// asked about: [value] may be `null` when it has nothing to offer there,
/// and the links after it are then not asked. A link that does not handle
/// the question answers `null` instead of a [Handled].
final class Handled<T> {
  /// The answer [value].
  const Handled(this.value);

  /// What the link found; `null` for nothing.
  final T? value;
}
