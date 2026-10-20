/// A named source of properties, like Spring's `PropertySource` (renamed
/// because `@PropertySource` is the annotation).
///
/// Two sources are equal when their names are equal, so a
/// `MutablePropertySources` holds at most one source per name.
///
/// ```dart
/// class FeatureFlagSource extends AbstractPropertySource<FlagClient> {
///   FeatureFlagSource(FlagClient client) : super('featureFlags', client);
///
///   @override
///   Object? getProperty(String name) => source.valueOf(name);
/// }
///
/// environment.propertySources.addFirst(FeatureFlagSource(client));
/// ```
///
/// Spring (Java):
/// ```java
/// class FeatureFlagSource extends PropertySource<FlagClient> {
///   FeatureFlagSource(FlagClient client) { super("featureFlags", client); }
///
///   @Override
///   public Object getProperty(String name) {
///     return getSource().valueOf(name);
///   }
/// }
/// ```
abstract class AbstractPropertySource<T extends Object> {
  /// Creates a source called [name] backed by [source].
  const AbstractPropertySource(this.name, this.source);

  /// Unique name of this source within a `MutablePropertySources`.
  final String name;

  /// The underlying object (a map, a list of args, ...).
  final T source;

  /// Value of [name], or `null` if this source does not define it.
  ///
  /// Values are returned raw: placeholders are resolved and types are
  /// converted later by the property resolver.
  Object? getProperty(String name);

  /// Whether this source defines [name].
  ///
  /// The default implementation checks for a non-`null` [getProperty].
  bool containsProperty(String name) => getProperty(name) != null;

  /// Sources are equal when their [name]s are equal, as in Spring.
  @override
  bool operator ==(Object other) =>
      other is AbstractPropertySource && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => '$runtimeType {name=$name}';
}

/// A [AbstractPropertySource] that can list its property names, like
/// Spring's `EnumerablePropertySource`.
///
/// Config data and binding code use [propertyNames] to find keys by prefix.
///
/// ```dart
/// class EnvFileSource extends EnumerablePropertySource<Map<String, String>> {
///   EnvFileSource(Map<String, String> values) : super('envFile', values);
///
///   @override
///   List<String> get propertyNames => source.keys.toList();
///
///   @override
///   Object? getProperty(String name) => source[name];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class EnvFileSource extends EnumerablePropertySource<Map<String, String>> {
///   EnvFileSource(Map<String, String> values) { super("envFile", values); }
///
///   @Override
///   public String[] getPropertyNames() {
///     return getSource().keySet().toArray(String[]::new);
///   }
///
///   @Override
///   public Object getProperty(String name) {
///     return getSource().get(name);
///   }
/// }
/// ```
abstract class EnumerablePropertySource<T extends Object>
    extends AbstractPropertySource<T> {
  /// Creates a source called [name] backed by [source].
  const EnumerablePropertySource(super.name, super.source);

  /// Names of all properties this source defines.
  List<String> get propertyNames;

  /// Checks [propertyNames]; subclasses may override with a faster lookup.

  @override
  bool containsProperty(String name) => propertyNames.contains(name);
}

/// Properties from a map, like Spring's `MapPropertySource`.
///
/// The map is used as is (not copied), so later changes are visible.
///
/// ```dart
/// final defaults = MapPropertySource('defaults', {
///   'server.port': 8080,
///   'app.name': 'demo',
/// });
/// environment.propertySources.addLast(defaults);
/// ```
///
/// Spring (Java):
/// ```java
/// var defaults = new MapPropertySource("defaults",
///     Map.of("server.port", 8080, "app.name", "demo"));
/// environment.getPropertySources().addLast(defaults);
/// ```
class MapPropertySource extends EnumerablePropertySource<Map<String, Object?>> {
  /// Creates a source called [name] backed by the map [source].
  const MapPropertySource(super.name, super.source);

  @override
  Object? getProperty(String name) => source[name];

  /// Whether the map has the key [name], even with a `null` value.
  @override
  bool containsProperty(String name) => source.containsKey(name);

  @override
  List<String> get propertyNames => List.unmodifiable(source.keys);
}

/// Several sources searched in order, like Spring's
/// `CompositePropertySource`.
///
/// The first nested source that defines a key wins.
///
/// ```dart
/// final composite = CompositePropertySource('config')
///   ..addPropertySource(MapPropertySource('base', {'a': '1'}))
///   ..addFirstPropertySource(MapPropertySource('override', {'a': '2'}));
/// composite.getProperty('a'); // '2'
/// ```
///
/// Spring (Java):
/// ```java
/// var composite = new CompositePropertySource("config");
/// composite.addPropertySource(
///     new MapPropertySource("base", Map.of("a", "1")));
/// composite.addFirstPropertySource(
///     new MapPropertySource("override", Map.of("a", "2")));
/// composite.getProperty("a"); // "2"
/// ```
class CompositePropertySource
    extends EnumerablePropertySource<List<AbstractPropertySource<Object>>> {
  /// Creates an empty composite called [name].
  CompositePropertySource(String name) : super(name, []);

  /// Adds [source] with the lowest precedence.
  void addPropertySource(AbstractPropertySource<Object> source) =>
      this.source.add(source);

  /// Adds [source] with the highest precedence.
  void addFirstPropertySource(AbstractPropertySource<Object> source) =>
      this.source.insert(0, source);

  /// The nested sources, highest precedence first (read-only view).
  List<AbstractPropertySource<Object>> get propertySources =>
      List.unmodifiable(source);

  @override
  Object? getProperty(String name) {
    for (final candidate in source) {
      final value = candidate.getProperty(name);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  @override
  bool containsProperty(String name) =>
      source.any((candidate) => candidate.containsProperty(name));

  /// Names of all enumerable nested sources (without duplicates);
  /// non-enumerable ones are skipped.
  @override
  List<String> get propertyNames => List.unmodifiable({
    for (final candidate in source)
      if (candidate is EnumerablePropertySource<Object>)
        ...candidate.propertyNames,
  });
}
