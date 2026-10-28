/// One place property values come from, under a name: a config file, the
/// command line, the environment variables, a map of defaults.
///
/// The environment does not hold properties itself. It holds an ordered
/// list of property sources and asks them in turn, the first one that has
/// a key winning; that is how the command line overrides a config file.
/// Every source the framework adds is a subclass of this class.
///
/// An application rarely touches it. Extend it to read properties from a
/// place the framework does not know, such as a feature flag service or a
/// secrets vault, and add the source to the environment early, from an
/// `EnvironmentPostProcessor`. When the source can list its keys, extend
/// [EnumerablePropertySource] instead, so `@ConfigurationProperties`
/// binding can find keys by prefix. A plain map is [MapPropertySource].
///
/// Two sources are equal when their names are equal, so a
/// `MutablePropertySources` holds at most one source per name. The class
/// is called `AbstractPropertySource` because `@PropertySource` is the
/// annotation.
///
/// ```dart
/// // Flags come from a flag service and override the config files.
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
  /// Creates a source called [name] that reads from [source].
  const AbstractPropertySource(this.name, this.source);

  /// The name of this source, unique within the environment's list. It is
  /// how other code finds, replaces or orders the source, and it appears
  /// in error messages (`Config resource 'classpath:/application.yml'`).
  final String name;

  /// The object the values are read from: a map, the command-line
  /// arguments, a client.
  final T source;

  /// The value of the property [name], or `null` when this source does not
  /// have it (the environment then asks the next source).
  ///
  /// Return the raw value: a string, a number, a list. `${...}`
  /// placeholders in it are resolved, and its type converted, later by
  /// the property resolver.
  Object? getProperty(String name);

  /// Whether this source has the property [name]. By default, whether
  /// [getProperty] returns a value other than `null`.
  bool containsProperty(String name) => getProperty(name) != null;

  /// Whether [other] is a source with the same [name], whatever its
  /// values, as in Spring.
  @override
  bool operator ==(Object other) =>
      other is AbstractPropertySource && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => '$runtimeType {name=$name}';
}

/// A property source that can list every key it has.
///
/// Looking a key up is enough for `@Value('${a.b}')`, but
/// `@ConfigurationProperties` binding of maps and lists, relaxed names and
/// config data must find all keys under a prefix, which needs the list.
/// Extend it instead of [AbstractPropertySource] when your source knows
/// its keys; the framework's map, file and command-line sources all do.
///
/// ```dart
/// // Key=value lines of a `.env` file, already parsed into a map.
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
  /// Creates a source called [name] that reads from [source].
  const EnumerablePropertySource(super.name, super.source);

  /// The keys of all properties this source has, as they are written in
  /// it.
  List<String> get propertyNames;

  /// Whether [propertyNames] contains [name]. Override it with a faster
  /// lookup when the source has one.
  @override
  bool containsProperty(String name) => propertyNames.contains(name);
}

/// A property source over a map of keys to values.
///
/// It is the simplest way to put values into the environment from code:
/// defaults computed at startup, values for a test, a parsed file. Many
/// framework sources build on it (environment variables, `.properties`
/// files, YAML documents). Keys are written in full (`server.port`), not
/// nested; values may be strings, numbers, booleans or lists and are
/// converted on read.
///
/// The map is used as is, not copied, so later changes to it are seen.
///
/// ```dart
/// // Values computed at startup, below every other source.
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
  /// Creates a source called [name] over the map [source], without
  /// copying it.
  const MapPropertySource(super.name, super.source);

  @override
  Object? getProperty(String name) => source[name];

  /// Whether the map has the key [name], even with a `null` value.
  @override
  bool containsProperty(String name) => source.containsKey(name);

  @override
  List<String> get propertyNames => List.unmodifiable(source.keys);
}

/// One property source made of several others, asked in order.
///
/// It lets a group of sources take a single place in the environment's
/// list, for example all the files of one config location, so the group
/// can be moved or removed by one name. Within it, the first nested
/// source with a non-`null` value for a key wins. Applications rarely
/// need it.
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
  /// Creates a composite called [name] with no sources yet.
  CompositePropertySource(String name) : super(name, []);

  /// Adds [source] at the end, where it loses to every source already in
  /// the composite.
  void addPropertySource(AbstractPropertySource<Object> source) =>
      this.source.add(source);

  /// Adds [source] at the front, where it wins over every source already in
  /// the composite.
  void addFirstPropertySource(AbstractPropertySource<Object> source) =>
      this.source.insert(0, source);

  /// The nested sources, the winning one first, as a read-only copy.
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

  /// The keys of all nested sources that can list theirs, each key once.
  /// Nested sources that cannot list their keys are left out.
  @override
  List<String> get propertyNames => List.unmodifiable({
    for (final candidate in source)
      if (candidate is EnumerablePropertySource<Object>)
        ...candidate.propertyNames,
  });
}
