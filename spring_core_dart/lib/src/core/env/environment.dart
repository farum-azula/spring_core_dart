import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
import 'package:spring_core_dart/src/core/env/platform_environment_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/env/platform_environment_io.dart';
import 'package:spring_core_dart/src/core/env/profiles.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';

/// Properties plus profiles, like Spring's `Environment`.
///
/// Beans usually get it injected (or implement `EnvironmentAware`).
///
/// ```dart
/// if (environment.matchesProfiles(['dev & !test'])) {
///   print(environment.getProperty('app.banner'));
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// if (environment.matchesProfiles("dev & !test")) {
///   System.out.println(environment.getProperty("app.banner"));
/// }
/// ```
abstract interface class Environment implements PropertyResolver {
  /// Explicitly activated profiles (also from `spring.profiles.active`).
  ///
  /// ```dart
  /// environment.activeProfiles; // ['dev']
  /// ```
  List<String> get activeProfiles;

  /// Profiles active when no profile is active explicitly; `['default']`
  /// unless changed (also from `spring.profiles.default`).
  List<String> get defaultProfiles;

  /// Whether [profiles] matches the active (or default) profiles.
  ///
  /// ```dart
  /// environment.acceptsProfiles(Profiles.of(['prod', 'staging']));
  /// ```
  bool acceptsProfiles(Profiles profiles);

  /// Shortcut for `acceptsProfiles(Profiles.of(profileExpressions))`.
  ///
  /// ```dart
  /// environment.matchesProfiles(['dev & (eu | us)']);
  /// ```
  bool matchesProfiles(List<String> profileExpressions);
}

/// A mutable [Environment], like Spring's `ConfigurableEnvironment`.
///
/// ```dart
/// final ConfigurableEnvironment environment = StandardEnvironment()
///   ..setActiveProfiles(['dev'])
///   ..propertySources.addFirst(MapPropertySource('test', {'a': '1'}));
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurableEnvironment environment = new StandardEnvironment();
/// environment.setActiveProfiles("dev");
/// environment.getPropertySources()
///     .addFirst(new MapPropertySource("test", Map.of("a", "1")));
/// ```
abstract interface class ConfigurableEnvironment
    implements Environment, ConfigurablePropertyResolver {
  /// Replaces the active profiles with [profiles].
  ///
  /// Throws [ArgumentError] for a blank profile or one starting with `!`.
  void setActiveProfiles(List<String> profiles);

  /// Adds [profile] to the active profiles (after reading
  /// `spring.profiles.active` if no profile was set yet).
  void addActiveProfile(String profile);

  /// Replaces the default profiles (initially `['default']`).
  void setDefaultProfiles(List<String> profiles);

  /// Sources searched by this environment; first wins.
  MutablePropertySources get propertySources;

  /// The operating-system environment variables.
  Map<String, String> get systemEnvironment;

  /// Adds [parent]'s property sources (lowest precedence, only those not
  /// present here) and its active and default profiles.
  ///
  /// Used when a child application context inherits its parent's
  /// environment.
  void merge(ConfigurableEnvironment parent);
}

/// The default environment, like Spring's `StandardEnvironment`.
///
/// Starts with one property source: [SystemEnvironmentPropertySource]
/// (OS environment variables, empty on the web). Add command-line arguments
/// or config files with `propertySources`.
///
/// Unlike Spring there are no JVM system properties, so command-line
/// arguments are the usual highest-precedence source.
///
/// ```dart
/// Future<void> main(List<String> args) async {
///   final environment = StandardEnvironment()
///     ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
///   await ConfigDataEnvironment(environment).processAndApply();
///   final port = environment.getPropertyAs<int>('server.port');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// var environment = new StandardEnvironment();
/// environment.getPropertySources()
///     .addFirst(new SimpleCommandLinePropertySource(args));
/// Integer port = environment.getProperty("server.port", Integer.class);
/// // Spring Boot's SpringApplication does all of this, plus config data.
/// ```
class StandardEnvironment implements ConfigurableEnvironment {
  /// [systemEnvironment] overrides the process environment (useful in
  /// tests).
  ///
  /// ```dart
  /// final environment = StandardEnvironment(
  ///   systemEnvironment: {'SPRING_PROFILES_ACTIVE': 'test'},
  /// );
  /// environment.activeProfiles; // ['test']
  /// ```
  StandardEnvironment({Map<String, String>? systemEnvironment})
    : systemEnvironment = Map.unmodifiable(
        systemEnvironment ?? platformEnvironment(),
      ) {
    _resolver = PropertySourcesPropertyResolver(propertySources);
    customizePropertySources(propertySources);
  }

  /// Property listing the active profiles, comma-separated
  /// (`spring.profiles.active`).
  static const activeProfilesPropertyName = 'spring.profiles.active';

  /// Property listing the default profiles, comma-separated
  /// (`spring.profiles.default`).
  static const defaultProfilesPropertyName = 'spring.profiles.default';

  /// Name of the profile that is the default unless changed (`default`).
  static const reservedDefaultProfileName = 'default';

  @override
  final MutablePropertySources propertySources = MutablePropertySources();

  @override
  final Map<String, String> systemEnvironment;

  late final PropertySourcesPropertyResolver _resolver;
  final _active = <String>{};
  final _defaults = <String>{reservedDefaultProfileName};

  /// Adds the default sources; override to add more.
  ///
  /// Called from the constructor, so subclass fields are not yet
  /// initialized.
  ///
  /// ```dart
  /// class AppEnvironment extends StandardEnvironment {
  ///   @override
  ///   void customizePropertySources(MutablePropertySources sources) {
  ///     sources.addLast(MapPropertySource('defaults', {'port': '8080'}));
  ///     super.customizePropertySources(sources);
  ///   }
  /// }
  /// ```
  void customizePropertySources(MutablePropertySources sources) {
    sources.addLast(
      SystemEnvironmentPropertySource(
        SystemEnvironmentPropertySource.defaultName,
        systemEnvironment,
      ),
    );
  }

  @override
  List<String> get activeProfiles => List.unmodifiable(_doGetActive());

  @override
  List<String> get defaultProfiles => List.unmodifiable(_doGetDefaults());

  // Explicit profiles win; `spring.profiles.active` is read lazily, only
  // while none were set, so later property sources still count.
  Set<String> _doGetActive() {
    if (_active.isEmpty) {
      final property = _resolver.getProperty(activeProfilesPropertyName);
      if (property != null && property.trim().isNotEmpty) {
        setActiveProfiles(_commaDelimited(property));
      }
    }
    return _active;
  }

  // Same for defaults: the property applies while only the reserved
  // `default` profile is configured.
  Set<String> _doGetDefaults() {
    if (_defaults.length == 1 &&
        _defaults.single == reservedDefaultProfileName) {
      final property = _resolver.getProperty(defaultProfilesPropertyName);
      if (property != null && property.trim().isNotEmpty) {
        setDefaultProfiles(_commaDelimited(property));
      }
    }
    return _defaults;
  }

  static List<String> _commaDelimited(String value) => [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  @override
  void setActiveProfiles(List<String> profiles) {
    profiles.forEach(_validateProfile);
    _active
      ..clear()
      ..addAll(profiles);
  }

  @override
  void addActiveProfile(String profile) {
    _validateProfile(profile);
    _doGetActive();
    _active.add(profile);
  }

  @override
  void setDefaultProfiles(List<String> profiles) {
    profiles.forEach(_validateProfile);
    _defaults
      ..clear()
      ..addAll(profiles);
  }

  @override
  bool acceptsProfiles(Profiles profiles) => profiles.matches(isProfileActive);

  @override
  bool matchesProfiles(List<String> profileExpressions) =>
      acceptsProfiles(Profiles.of(profileExpressions));

  /// Whether [profile] is active, or is a default profile while no profile
  /// is active.
  ///
  /// Throws [ArgumentError] for a blank profile or one starting with `!`.
  bool isProfileActive(String profile) {
    _validateProfile(profile);
    final active = _doGetActive();
    return active.contains(profile) ||
        (active.isEmpty && _doGetDefaults().contains(profile));
  }

  void _validateProfile(String profile) {
    if (profile.trim().isEmpty) {
      throw ArgumentError.value(profile, 'profile', 'Invalid profile: blank');
    }
    if (profile.startsWith('!')) {
      throw ArgumentError.value(
        profile,
        'profile',
        "Invalid profile: must not begin with '!'",
      );
    }
  }

  @override
  void merge(ConfigurableEnvironment parent) {
    for (final source in parent.propertySources) {
      if (!propertySources.containsSource(source.name)) {
        propertySources.addLast(source);
      }
    }
    final parentActive = parent.activeProfiles;
    if (parentActive.isNotEmpty) {
      _active.addAll(parentActive);
    }
    final parentDefaults = parent.defaultProfiles;
    if (parentDefaults.isNotEmpty) {
      _defaults
        ..remove(reservedDefaultProfileName)
        ..addAll(parentDefaults);
    }
  }

  // PropertyResolver: delegate to the property-sources resolver.

  @override
  ConversionService get conversionService => _resolver.conversionService;

  @override
  set conversionService(ConversionService value) =>
      _resolver.conversionService = value;

  @override
  set placeholderPrefix(String value) => _resolver.placeholderPrefix = value;

  @override
  set placeholderSuffix(String value) => _resolver.placeholderSuffix = value;

  @override
  set valueSeparator(String? value) => _resolver.valueSeparator = value;

  @override
  set escapeCharacter(String? value) => _resolver.escapeCharacter = value;

  @override
  set ignoreUnresolvableNestedPlaceholders(bool value) =>
      _resolver.ignoreUnresolvableNestedPlaceholders = value;

  @override
  void setRequiredProperties(List<String> keys) =>
      _resolver.setRequiredProperties(keys);

  @override
  void validateRequiredProperties() => _resolver.validateRequiredProperties();

  @override
  bool containsProperty(String key) => _resolver.containsProperty(key);

  @override
  String? getProperty(String key, {String? defaultValue}) =>
      _resolver.getProperty(key, defaultValue: defaultValue);

  @override
  T? getPropertyAs<T>(String key, {T? defaultValue}) =>
      _resolver.getPropertyAs<T>(key, defaultValue: defaultValue);

  @override
  String getRequiredProperty(String key) => _resolver.getRequiredProperty(key);

  @override
  T getRequiredPropertyAs<T>(String key) =>
      _resolver.getRequiredPropertyAs<T>(key);

  @override
  String resolvePlaceholders(String text) =>
      _resolver.resolvePlaceholders(text);

  @override
  String resolveRequiredPlaceholders(String text) =>
      _resolver.resolveRequiredPlaceholders(text);

  @override
  String toString() =>
      'StandardEnvironment {activeProfiles=$_active, '
      'defaultProfiles=$_defaults, propertySources=$propertySources}';
}
