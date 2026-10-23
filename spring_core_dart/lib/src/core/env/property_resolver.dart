import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/core/env/env_exceptions.dart';
import 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
import 'package:spring_core_dart/src/core/env/property_placeholder_helper.dart';

/// Read access to properties, like Spring's `PropertyResolver`.
///
/// Values are resolved (`${...}` placeholders) and converted on read.
///
/// ```dart
/// final PropertyResolver resolver = environment;
/// final host = resolver.getProperty('db.host', defaultValue: 'localhost');
/// final port = resolver.getPropertyAs<int>('db.port', defaultValue: 5432);
/// final url = resolver.resolvePlaceholders(r'jdbc://${db.host}:${db.port}');
/// ```
///
/// Spring (Java):
/// ```java
/// PropertyResolver resolver = environment;
/// String host = resolver.getProperty("db.host", "localhost");
/// int port = resolver.getProperty("db.port", Integer.class, 5432);
/// String url = resolver.resolvePlaceholders("jdbc://${db.host}:${db.port}");
/// ```
///
/// Typed access is `getPropertyAs<T>` instead of an overloaded
/// `getProperty(key, Class)`, as Dart has no overloading.
abstract interface class PropertyResolver {
  /// Whether [key] is defined (its value may still be an empty string).
  bool containsProperty(String key);

  /// The value of [key] as a string, or [defaultValue].
  ///
  /// ```dart
  /// resolver.getProperty('app.name', defaultValue: 'demo');
  /// ```
  String? getProperty(String key, {String? defaultValue});

  /// The value of [key] converted to [T], or [defaultValue].
  ///
  /// Conversion uses the resolver's `ConversionService`; [defaultValue] is
  /// also used when the value converts to `null` (e.g. a blank string).
  ///
  /// ```dart
  /// final timeout = resolver.getPropertyAs<Duration>('http.timeout');
  /// final hosts = resolver.getPropertyAs<List<String>>('cluster.hosts');
  /// ```
  T? getPropertyAs<T>(String key, {T? defaultValue});

  /// The value of [key]; throws `MissingPropertyException` if undefined.
  String getRequiredProperty(String key);

  /// The value of [key] converted to [T]; throws `MissingPropertyException`
  /// if undefined.
  ///
  /// ```dart
  /// final port = resolver.getRequiredPropertyAs<int>('server.port');
  /// ```
  T getRequiredPropertyAs<T>(String key);

  /// Resolves `${...}` in [text]; unresolvable placeholders stay as they
  /// are.
  ///
  /// ```dart
  /// resolver.resolvePlaceholders(r'Hello ${user:guest}'); // 'Hello guest'
  /// ```
  String resolvePlaceholders(String text);

  /// Resolves `${...}` in [text]; throws `PlaceholderResolutionException`
  /// for unresolvable placeholders without a default.
  String resolveRequiredPlaceholders(String text);
}

/// A [PropertyResolver] with configuration, like Spring's
/// `ConfigurablePropertyResolver`.
///
/// ```dart
/// final ConfigurablePropertyResolver resolver = StandardEnvironment()
///   ..conversionService = (DefaultConversionService()..addEnum(Level.values))
///   ..ignoreUnresolvableNestedPlaceholders = true
///   ..setRequiredProperties(['app.name']);
/// resolver.validateRequiredProperties();
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurableEnvironment resolver = new StandardEnvironment();
/// resolver.setConversionService(new DefaultConversionService());
/// resolver.setIgnoreUnresolvableNestedPlaceholders(true);
/// resolver.setRequiredProperties("app.name");
/// resolver.validateRequiredProperties();
/// ```
abstract interface class ConfigurablePropertyResolver
    implements PropertyResolver {
  /// Converts property values in [PropertyResolver.getPropertyAs].
  ///
  /// Defaults to `DefaultConversionService.sharedInstance`.
  ConversionService get conversionService;

  /// Replaces the service used for typed property access.
  set conversionService(ConversionService value);

  /// Start of a placeholder; defaults to `${`.
  set placeholderPrefix(String value);

  /// End of a placeholder; defaults to `}`.
  set placeholderSuffix(String value);

  /// Separator between key and default (`:` by default); `null` disables
  /// defaults.
  set valueSeparator(String? value);

  /// Escape for prefix and separator (`\` by default); `null` disables
  /// escaping.
  set escapeCharacter(String? value);

  /// When `true`, unresolvable placeholders inside property values are
  /// kept instead of throwing.
  set ignoreUnresolvableNestedPlaceholders(bool value);

  /// Keys that [validateRequiredProperties] checks; adds to the keys set
  /// earlier.
  void setRequiredProperties(List<String> keys);

  /// Throws `MissingRequiredPropertiesException` listing every required
  /// key that is not defined.
  void validateRequiredProperties();
}

/// Shared logic of resolvers; subclasses supply [getRawProperty].
///
/// Handles placeholder resolution, conversion, defaults and required
/// properties, like Spring's `AbstractPropertyResolver`.
///
/// ```dart
/// class MapResolver extends AbstractPropertyResolver {
///   MapResolver(this.values);
///
///   final Map<String, String> values;
///
///   @override
///   Object? getRawProperty(String key) => values[key];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class MapResolver extends AbstractPropertyResolver {
///   private final Map<String, String> values;
///
///   MapResolver(Map<String, String> values) { this.values = values; }
///
///   @Override
///   protected String getPropertyAsRawString(String key) {
///     return values.get(key);
///   }
///
///   @Override
///   public <T> T getProperty(String key, Class<T> type) {
///     String value = values.get(key);
///     return value == null ? null
///         : convertValueIfNecessary(resolveNestedPlaceholders(value), type);
///   }
/// }
/// ```
abstract class AbstractPropertyResolver
    implements ConfigurablePropertyResolver {
  @override
  ConversionService conversionService = DefaultConversionService.sharedInstance;

  String _prefix = r'${';
  String _suffix = '}';
  String? _separator = ':';
  String? _escape = r'\';
  bool _ignoreNested = false;
  final _required = <String>{};
  // Helpers are built lazily and dropped whenever the syntax changes.
  PropertyPlaceholderHelper? _strictHelper;
  PropertyPlaceholderHelper? _lenientHelper;

  /// The unresolved value of [key], or `null`.
  ///
  /// String values may still contain placeholders; they are resolved by
  /// [getPropertyAs].
  Object? getRawProperty(String key);

  @override
  set placeholderPrefix(String value) => _reconfigure(() => _prefix = value);

  @override
  set placeholderSuffix(String value) => _reconfigure(() => _suffix = value);

  @override
  set valueSeparator(String? value) => _reconfigure(() => _separator = value);

  @override
  set escapeCharacter(String? value) => _reconfigure(() => _escape = value);

  @override
  set ignoreUnresolvableNestedPlaceholders(bool value) => _ignoreNested = value;

  void _reconfigure(void Function() change) {
    change();
    _strictHelper = null;
    _lenientHelper = null;
  }

  @override
  void setRequiredProperties(List<String> keys) => _required.addAll(keys);

  @override
  void validateRequiredProperties() {
    final missing = [
      for (final key in _required)
        if (getProperty(key) == null) key,
    ];
    if (missing.isNotEmpty) {
      throw MissingRequiredPropertiesException(missing);
    }
  }

  @override
  bool containsProperty(String key) => getRawProperty(key) != null;

  @override
  String? getProperty(String key, {String? defaultValue}) =>
      getPropertyAs<String>(key, defaultValue: defaultValue);

  @override
  T? getPropertyAs<T>(String key, {T? defaultValue}) {
    // Only string values can contain placeholders; whether an unresolvable
    // nested placeholder throws depends on
    // `ignoreUnresolvableNestedPlaceholders`.
    var value = getRawProperty(key);
    if (value == null) {
      return defaultValue;
    }
    if (value is String) {
      value = _ignoreNested
          ? resolvePlaceholders(value)
          : resolveRequiredPlaceholders(value);
    }
    return conversionService.convert<T?>(value) ?? defaultValue;
  }

  @override
  String getRequiredProperty(String key) => getRequiredPropertyAs<String>(key);

  @override
  T getRequiredPropertyAs<T>(String key) {
    final value = getPropertyAs<T>(key);
    if (value == null) {
      throw MissingPropertyException(key);
    }
    return value;
  }

  @override
  String resolvePlaceholders(String text) => (_lenientHelper ??= _helper(
    ignoreUnresolvable: true,
  )).replacePlaceholders(text, _rawString);

  @override
  String resolveRequiredPlaceholders(String text) => (_strictHelper ??= _helper(
    ignoreUnresolvable: false,
  )).replacePlaceholders(text, _rawString);

  // Placeholders look up raw values; nested placeholders inside them are
  // resolved recursively by the helper.
  String? _rawString(String key) => getRawProperty(key)?.toString();

  PropertyPlaceholderHelper _helper({required bool ignoreUnresolvable}) =>
      PropertyPlaceholderHelper(
        prefix: _prefix,
        suffix: _suffix,
        valueSeparator: _separator,
        escapeCharacter: _escape,
        ignoreUnresolvablePlaceholders: ignoreUnresolvable,
      );
}

/// Resolves properties from [propertySources] in order, like Spring's
/// `PropertySourcesPropertyResolver`.
///
/// The first source that defines a key (non-`null` value) wins.
///
/// ```dart
/// final resolver = PropertySourcesPropertyResolver(
///   MutablePropertySources([MapPropertySource('app', {'port': '8080'})]),
/// );
/// final port = resolver.getPropertyAs<int>('port'); // 8080
/// ```
///
/// Spring (Java):
/// ```java
/// MutablePropertySources sources = new MutablePropertySources();
/// sources.addFirst(new MapPropertySource("app", Map.of("port", "8080")));
/// var resolver = new PropertySourcesPropertyResolver(sources);
/// Integer port = resolver.getProperty("port", Integer.class);
/// ```
class PropertySourcesPropertyResolver extends AbstractPropertyResolver {
  /// Creates a resolver over [propertySources] (not copied).
  PropertySourcesPropertyResolver(this.propertySources);

  /// The sources searched in order, first wins.
  final MutablePropertySources propertySources;

  /// Whether any source defines [key], even with a `null` or empty value,
  /// like Spring's `PropertySourcesPropertyResolver.containsProperty`.
  @override
  bool containsProperty(String key) =>
      propertySources.any((source) => source.containsProperty(key));

  @override
  Object? getRawProperty(String key) {
    for (final source in propertySources) {
      final value = source.getProperty(key);
      if (value != null) {
        return value;
      }
    }
    return null;
  }
}
