import 'package:spring_core_dart/src/core/env/property_source.dart';

/// The ordered list of property sources an environment reads from; for
/// each key, the first source that has it wins.
///
/// The order is what makes the command line beat a config file and a
/// config file beat the defaults. An application meets this list as
/// `environment.propertySources`, in an `EnvironmentPostProcessor` or a
/// test, when it adds a source of its own and must choose where it goes:
/// [addFirst] to override everything, [addLast] for defaults, or
/// [addBefore] and [addAfter] next to a source named by the framework
/// (such as `systemEnvironment`).
///
/// Sources are identified by name: adding a source whose name is already
/// present removes the old one first.
///
/// ```dart
/// // Values from a vault win over the environment variables but not over
/// // the command line, which comes before them.
/// environment.propertySources.addBefore(
///   SystemEnvironmentPropertySource.defaultName,
///   MapPropertySource('vault', secrets),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// environment.getPropertySources().addBefore(
///     StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME,
///     new MapPropertySource("vault", secrets));
/// ```
class MutablePropertySources extends Iterable<AbstractPropertySource<Object>> {
  /// Creates the list with [sources] in the given order, the first one
  /// winning.
  MutablePropertySources([
    Iterable<AbstractPropertySource<Object>> sources = const [],
  ]) {
    sources.forEach(addLast);
  }

  final _sources = <AbstractPropertySource<Object>>[];

  /// Goes through the sources from the winning one down. It iterates over
  /// a copy, so sources may be added or removed meanwhile.
  @override
  Iterator<AbstractPropertySource<Object>> get iterator =>
      List<AbstractPropertySource<Object>>.unmodifiable(_sources).iterator;

  /// Whether the list has a source called [name].
  bool containsSource(String name) => _indexOf(name) >= 0;

  /// The source called [name], or `null` when there is none.
  AbstractPropertySource<Object>? get(String name) {
    final index = _indexOf(name);
    return index < 0 ? null : _sources[index];
  }

  /// Puts [source] first, so it wins over every other source.
  void addFirst(AbstractPropertySource<Object> source) {
    _removeIfPresent(source.name);
    _sources.insert(0, source);
  }

  /// Puts [source] last, so every other source wins over it.
  void addLast(AbstractPropertySource<Object> source) {
    _removeIfPresent(source.name);
    _sources.add(source);
  }

  /// Puts [source] just before the source called [relativeName], so it
  /// wins over that one.
  ///
  /// Throws [ArgumentError] if [relativeName] is absent or is the name of
  /// [source] itself.
  void addBefore(String relativeName, AbstractPropertySource<Object> source) {
    _checkNotSelf(relativeName, source);
    _removeIfPresent(source.name);
    _sources.insert(_requireIndex(relativeName), source);
  }

  /// Puts [source] just after the source called [relativeName], so that
  /// one wins over it.
  ///
  /// Throws [ArgumentError] if [relativeName] is absent or is the name of
  /// [source] itself.
  void addAfter(String relativeName, AbstractPropertySource<Object> source) {
    _checkNotSelf(relativeName, source);
    _removeIfPresent(source.name);
    _sources.insert(_requireIndex(relativeName) + 1, source);
  }

  /// The position of [source] (matched by name): 0 for the winning source,
  /// -1 when it is not in the list.
  int precedenceOf(AbstractPropertySource<Object> source) =>
      _sources.indexOf(source);

  /// Takes the source called [name] out of the list and returns it, or
  /// returns `null` when there is none.
  AbstractPropertySource<Object>? remove(String name) {
    final index = _indexOf(name);
    return index < 0 ? null : _sources.removeAt(index);
  }

  /// Puts [source] where the source called [name] is, keeping its
  /// position, for example to wrap or refresh a source.
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
