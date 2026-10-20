import 'package:spring_core_dart/src/core/env/property_source.dart';

/// An ordered, mutable list of property sources; the first one has the
/// highest precedence. Like Spring's `MutablePropertySources`.
///
/// Adding a source whose name is already present removes the old one first.
///
/// ```dart
/// final sources = MutablePropertySources()
///   ..addLast(MapPropertySource('defaults', {'port': '8080'}))
///   ..addFirst(MapPropertySource('overrides', {'port': '9090'}))
///   ..addAfter('overrides', MapPropertySource('test', {}));
/// sources.map((s) => s.name); // (overrides, test, defaults)
/// ```
///
/// Spring (Java):
/// ```java
/// MutablePropertySources sources = new MutablePropertySources();
/// sources.addLast(new MapPropertySource("defaults", Map.of("port", "8080")));
/// sources.addFirst(
///     new MapPropertySource("overrides", Map.of("port", "9090")));
/// sources.addAfter("overrides", new MapPropertySource("test", Map.of()));
/// ```
class MutablePropertySources extends Iterable<AbstractPropertySource<Object>> {
  /// Creates the list with [sources] added in order (first = highest
  /// precedence).
  MutablePropertySources([
    Iterable<AbstractPropertySource<Object>> sources = const [],
  ]) {
    sources.forEach(addLast);
  }

  final _sources = <AbstractPropertySource<Object>>[];

  /// Iterates over a snapshot, so sources may be added or removed while
  /// iterating.
  @override
  Iterator<AbstractPropertySource<Object>> get iterator =>
      List<AbstractPropertySource<Object>>.unmodifiable(_sources).iterator;

  /// Whether a source named [name] is present.
  bool containsSource(String name) => _indexOf(name) >= 0;

  /// The source named [name], or `null`.
  AbstractPropertySource<Object>? get(String name) {
    final index = _indexOf(name);
    return index < 0 ? null : _sources[index];
  }

  /// Adds [source] with the highest precedence.
  void addFirst(AbstractPropertySource<Object> source) {
    _removeIfPresent(source.name);
    _sources.insert(0, source);
  }

  /// Adds [source] with the lowest precedence.
  void addLast(AbstractPropertySource<Object> source) {
    _removeIfPresent(source.name);
    _sources.add(source);
  }

  /// Adds [source] just before (higher precedence than) [relativeName].
  ///
  /// Throws [ArgumentError] if [relativeName] is absent or is the name of
  /// [source] itself.
  void addBefore(String relativeName, AbstractPropertySource<Object> source) {
    _checkNotSelf(relativeName, source);
    _removeIfPresent(source.name);
    _sources.insert(_requireIndex(relativeName), source);
  }

  /// Adds [source] just after (lower precedence than) [relativeName].
  ///
  /// Throws [ArgumentError] if [relativeName] is absent or is the name of
  /// [source] itself.
  void addAfter(String relativeName, AbstractPropertySource<Object> source) {
    _checkNotSelf(relativeName, source);
    _removeIfPresent(source.name);
    _sources.insert(_requireIndex(relativeName) + 1, source);
  }

  /// Precedence of [source]: 0 is highest; -1 if absent.
  int precedenceOf(AbstractPropertySource<Object> source) =>
      _sources.indexOf(source);

  /// Removes and returns the source named [name], if present.
  AbstractPropertySource<Object>? remove(String name) {
    final index = _indexOf(name);
    return index < 0 ? null : _sources.removeAt(index);
  }

  /// Replaces the source named [name] with [source] at the same position.
  ///
  /// Throws [ArgumentError] if there is no source named [name].
  void replace(String name, AbstractPropertySource<Object> source) {
    _sources[_requireIndex(name)] = source;
  }

  @override
  String toString() => _sources.toString();

  int _indexOf(String name) => _sources.indexWhere((s) => s.name == name);

  int _requireIndex(String name) {
    final index = _indexOf(name);
    if (index < 0) {
      throw ArgumentError.value(
        name,
        'name',
        'AbstractPropertySource does not exist',
      );
    }
    return index;
  }

  void _removeIfPresent(String name) {
    final index = _indexOf(name);
    if (index >= 0) {
      _sources.removeAt(index);
    }
  }

  void _checkNotSelf(
    String relativeName,
    AbstractPropertySource<Object> source,
  ) {
    if (relativeName == source.name) {
      throw ArgumentError.value(
        relativeName,
        'relativeName',
        'AbstractPropertySource cannot be added relative to itself',
      );
    }
  }
}
