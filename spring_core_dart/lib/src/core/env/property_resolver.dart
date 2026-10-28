import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/core/env/env_exceptions.dart';
import 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
import 'package:spring_core_dart/src/core/env/property_placeholder_helper.dart';

/// Reading properties by key: as text or as a typed value, with or without
/// a default, and resolving `${...}` placeholders in any text.
///
/// `Environment` is the property resolver an application meets; this
/// interface only names the reading part of it, so code that needs nothing
/// else (no profiles) can ask for less. On every read, placeholders in the
/// value are resolved (`url=${host}:8080`) and the text is converted to the
/// requested type.
///
/// ```dart
/// // The environment is the resolver beans get.
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
  /// Whether some source has the property [key], even with an empty
  /// value. Use it to tell "set to empty" from "not set".
  bool containsProperty(String key);

  /// The value of the property [key] as text, placeholders resolved, or
  /// [defaultValue] (`null` unless given) when no source has it.
  ///
  /// Throws `PlaceholderResolutionException` when the value contains a
  /// placeholder that cannot be resolved and has no default.
  ///
  /// ```dart
  /// resolver.getProperty('app.name', defaultValue: 'demo');
  /// ```
  String? getProperty(String key, {String? defaultValue});

  /// The value of the property [key] converted to [T], or [defaultValue]
  /// when no source has it.
  ///
  /// The resolver's `ConversionService` converts, so every type it knows
  /// works (`int`, `bool`, `Duration`, `List<String>`, ...). [defaultValue]
  /// is also used when the value converts to `null`, as a blank string
  /// does. Throws a `ConversionException` when the text cannot be
  /// converted (`port=abc` read as `int`).
  ///
  /// ```dart
  /// final timeout = resolver.getPropertyAs<Duration>('http.timeout');
  /// final hosts = resolver.getPropertyAs<List<String>>('cluster.hosts');
  /// ```
  T? getPropertyAs<T>(String key, {T? defaultValue});

  /// The value of the property [key] as text, for settings the application
  /// cannot run without. Throws `MissingPropertyException` when no source
  /// has it.
  String getRequiredProperty(String key);

  /// The value of the property [key] converted to [T]. Throws
  /// `MissingPropertyException` when no source has it (or it converts to
  /// `null`), and a `ConversionException` when it cannot be converted.
  ///
  /// ```dart
  /// final port = resolver.getRequiredPropertyAs<int>('server.port');
  /// ```
  T getRequiredPropertyAs<T>(String key);

  /// Replaces every `${key}` and `${key:default}` in [text] with the
  /// property's value, for text written by someone else, such as a
  /// message template. A placeholder that cannot be resolved and has no
  /// default stays as it is.
  ///
  /// ```dart
  /// resolver.resolvePlaceholders(r'Hello ${user:guest}'); // 'Hello guest'
  /// ```
  String resolvePlaceholders(String text);

  /// Replaces every `${key}` and `${key:default}` in [text] like
  /// [resolvePlaceholders], but throws `PlaceholderResolutionException`
  /// for a placeholder that cannot be resolved and has no default. Use it
  /// when a missing value is an error.
  String resolveRequiredPlaceholders(String text);
}

/// A [PropertyResolver] whose behaviour can be set: the conversion
/// service, the placeholder syntax, and keys that must be present.
///
/// `ConfigurableEnvironment` is one, so these settings are made on the
/// environment while the application starts, usually from an
/// `EnvironmentPostProcessor`. Most applications never change them; the
/// most useful part is [setRequiredProperties] with
/// [validateRequiredProperties], which fails the start early and clearly
/// when a key the application needs is missing.
///
/// ```dart
/// // A tool that reads `Level` values and cannot run without `app.name`:
/// // the last call throws, listing every missing key.
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
  /// The service that converts values in [PropertyResolver.getPropertyAs]
  /// and in `@ConfigurationProperties` binding.
  ///
  /// Defaults to `DefaultConversionService.sharedInstance`.
  ConversionService get conversionService;

  /// Replaces the service that converts values, for example with a
  /// `DefaultConversionService` that knows the application's own types.
  /// Do not add converters to the shared default instance.
  set conversionService(ConversionService value);

  /// The text that opens a placeholder; `${` unless changed.
  // Write-only configuration, as Spring's setX methods of this interface;
  // a getter would be a new abstract member for every implementer.
  // ignore: avoid_setters_without_getters
  set placeholderPrefix(String value);

  /// The text that closes a placeholder; `}` unless changed.
  // Write-only configuration, as Spring's setX methods of this interface;
  // a getter would be a new abstract member for every implementer.
  // ignore: avoid_setters_without_getters
  set placeholderSuffix(String value);

  /// The text between a key and its default in `${key:default}`; `:`
  /// unless changed. `null` turns defaults off, so the whole text is the
  /// key.
  // Write-only configuration, as Spring's setX methods of this interface;
  // a getter would be a new abstract member for every implementer.
  // ignore: avoid_setters_without_getters
  set valueSeparator(String? value);

  /// The character that makes a placeholder prefix or separator literal
  /// (`\${` is the text `${`); `\` unless changed. `null` turns escaping
  /// off.
  // Write-only configuration, as Spring's setX methods of this interface;
  // a getter would be a new abstract member for every implementer.
  // ignore: avoid_setters_without_getters
  set escapeCharacter(String? value);

  /// Whether reading a property whose value contains an unresolvable
  /// placeholder keeps the placeholder as text (`true`) instead of
  /// throwing (`false`, the default).
  // Write-only configuration, as Spring's setX methods of this interface;
  // a getter would be a new abstract member for every implementer.
  // ignore: avoid_setters_without_getters
  set ignoreUnresolvableNestedPlaceholders(bool value);

  /// Adds [keys] to the properties [validateRequiredProperties] checks;
  /// keys added earlier stay.
  void setRequiredProperties(List<String> keys);

  /// Checks that every key given to [setRequiredProperties] has a value,
  /// and throws `MissingRequiredPropertiesException` listing all the
  /// missing ones at once. An application context calls it when it
  /// starts, before any bean is created.
  void validateRequiredProperties();
}

/// The common part of property resolvers: placeholder resolution,
/// conversion, defaults and required keys. A subclass only says where raw
/// values come from, in [getRawProperty].
///
/// Applications practically never extend it; the environment's resolver
/// ([PropertySourcesPropertyResolver]) covers property sources. It is for
/// a resolver over some other store that should behave like the
/// environment, placeholders and conversion included.
///
/// ```dart
/// // Placeholders and typed reads over a plain map.
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

  /// The stored value of [key] as it is, or `null` when there is none.
  ///
  /// String values may still contain placeholders; the reading methods
  /// resolve them and convert the result.
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

  // Placeholders look up raw values as strings (through the conversion
  // service, so an enum is its name, like Spring's
  // getPropertyAsRawString); nested placeholders inside them are resolved
  // recursively by the helper.
  String? _rawString(String key) => switch (getRawProperty(key)) {
    null => null,
    final String value => value,
    final value => conversionService.convert<String?>(value),
  };

  PropertyPlaceholderHelper _helper({required bool ignoreUnresolvable}) =>
      PropertyPlaceholderHelper(
        prefix: _prefix,
        suffix: _suffix,
        valueSeparator: _separator,
        escapeCharacter: _escape,
        ignoreUnresolvablePlaceholders: ignoreUnresolvable,
      );
}

/// The property resolver that reads from a list of property sources, the
/// first source with a non-`null` value winning.
///
/// It does the reading for `StandardEnvironment`, which hands every
/// property call to one of these. Create one directly only to read a list
/// of sources that is not an environment's.
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
  /// Creates a resolver over [propertySources]. The list is not copied, so
  /// sources added to it later are read too.
  PropertySourcesPropertyResolver(this.propertySources);

  /// The sources read in order, the first with a value winning.
  final MutablePropertySources propertySources;

  /// Whether any source has [key], even with a `null` or empty value, like
  /// Spring's `PropertySourcesPropertyResolver.containsProperty`.
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
