import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
import 'package:spring_core_dart/src/core/env/platform_environment_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/env/platform_environment_io.dart';
import 'package:spring_core_dart/src/core/env/profiles.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/log_format.dart';

/// The application's configuration as code sees it: every property from
/// every source (config files, command line, environment variables), and
/// the active profiles.
///
/// Most beans never need it: `@Value` and `@ConfigurationProperties` read
/// properties for them, and `@Profile` switches beans on profiles. Take
/// the environment when the key is only known at run time, when a
/// decision depends on the active profiles in code, or to resolve
/// `${...}` placeholders in text. It is a bean, so a constructor
/// parameter of type `Environment` receives it (`EnvironmentAware` works
/// too). It is read-only; [ConfigurableEnvironment] is the side that
/// changes it.
///
/// ```dart
/// @Service()
/// class Banner {
///   Banner(this.environment);
///   final Environment environment;
///
///   // The key depends on the language, so `@Value` cannot name it.
///   String text(String language) =>
///       environment.getProperty('shop.banner.$language') ??
///       environment.resolvePlaceholders(r'Welcome to ${shop.title}');
///
///   bool get showDebugInfo => environment.matchesProfiles(['dev & !test']);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Banner {
///   private final Environment environment;
///   Banner(Environment environment) { this.environment = environment; }
///
///   String text(String language) {
///     String text = environment.getProperty("shop.banner." + language);
///     return text != null ? text
///         : environment.resolvePlaceholders("Welcome to ${shop.title}");
///   }
///
///   boolean showDebugInfo() {
///     return environment.matchesProfiles("dev & !test");
///   }
/// }
/// ```
abstract interface class Environment implements PropertyResolver {
  /// The profiles switched on for this run, such as `['prod', 'eu']`;
  /// empty when none is.
  ///
  /// They come from `setActiveProfiles`, or else from the property
  /// `spring.profiles.active` (read on first use, so a source added later
  /// still counts). The default profiles are not included.
  ///
  /// ```dart
  /// environment.activeProfiles; // ['dev']
  /// ```
  List<String> get activeProfiles;

  /// The profiles that count as active while [activeProfiles] is empty:
  /// `['default']` unless changed with `setDefaultProfiles` or the property
  /// `spring.profiles.default`. This is why `application-default.yml` and
  /// `@Profile('default')` apply to a run without profiles.
  List<String> get defaultProfiles;

  /// Whether the profile condition [profiles] holds for the active
  /// profiles, or for the default profiles while none is active.
  ///
  /// Use it with a [Profiles] built once; [matchesProfiles] takes the
  /// expressions directly.
  ///
  /// ```dart
  /// environment.acceptsProfiles(Profiles.of(['prod', 'staging']));
  /// ```
  bool acceptsProfiles(Profiles profiles);

  /// Whether any of [profileExpressions] holds for the active profiles
  /// (or the default ones while none is active).
  ///
  /// An expression is a profile name or a combination with `!`, `&`, `|`
  /// and parentheses. Same as
  /// `acceptsProfiles(Profiles.of(profileExpressions))`.
  ///
  /// ```dart
  /// environment.matchesProfiles(['dev & (eu | us)']);
  /// ```
  bool matchesProfiles(List<String> profileExpressions);
}

/// An [Environment] that can be changed: its list of property sources,
/// its profiles and how it converts and resolves values.
///
/// Changes must happen before beans read the configuration, so this side
/// is for startup code. The framework fills it (config files, command
/// line) while the application starts; an application receives it in an
/// `EnvironmentPostProcessor` to add a property source or switch on a
/// profile, and in tests. Beans should take [Environment] instead.
///
/// ```dart
/// // Passed to SpringApplication(environmentPostProcessors: [...]).
/// class RegionProfile implements EnvironmentPostProcessor {
///   @override
///   void postProcessEnvironment(
///     ConfigurableEnvironment environment,
///     SpringApplication application,
///   ) {
///     // Machines in the EU data centre run with the `eu` profile.
///     if (environment.getProperty('REGION') == 'eu') {
///       environment.addActiveProfile('eu');
///     }
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class RegionProfile implements EnvironmentPostProcessor {
///   @Override
///   public void postProcessEnvironment(
///       ConfigurableEnvironment environment, SpringApplication application) {
///     if ("eu".equals(environment.getProperty("REGION"))) {
///       environment.addActiveProfile("eu");
///     }
///   }
/// }
/// ```
abstract interface class ConfigurableEnvironment
    implements Environment, ConfigurablePropertyResolver {
  /// Makes [profiles] the active profiles, dropping any set before; the
  /// property `spring.profiles.active` is then no longer read.
  ///
  /// Throws [ArgumentError] for a blank profile or one starting with `!`.
  void setActiveProfiles(List<String> profiles);

  /// Adds [profile] to the active profiles, keeping the others. When none
  /// was set yet, `spring.profiles.active` is read first, so the profiles
  /// from the configuration are kept too.
  ///
  /// Throws [ArgumentError] for a blank profile or one starting with `!`.
  void addActiveProfile(String profile);

  /// Makes [profiles] the profiles used while none is active, replacing
  /// `['default']`.
  ///
  /// Throws [ArgumentError] for a blank profile or one starting with `!`.
  void setDefaultProfiles(List<String> profiles);

  /// The ordered list of sources the environment reads properties from;
  /// for each key the first source that has it wins. Add, remove or
  /// reorder sources here.
  MutablePropertySources get propertySources;

  /// The environment variables of the process, as a read-only map; empty
  /// on the web.
  Map<String, String> get systemEnvironment;

  /// Takes over what [parent] has: its property sources go at the end,
  /// below this environment's own (except those whose name is already
  /// here), its active profiles are added, and its default profiles
  /// replace `default`.
  ///
  /// The framework calls it when a child application context is created
  /// under a parent, so the child sees the parent's configuration.
  void merge(ConfigurableEnvironment parent);
}

/// The environment implementation used everywhere: an empty list of
/// property sources except the environment variables, plus profiles.
///
/// `SpringApplication` and `ApplicationContext.run` create one and fill it
/// (command line, config files, defaults), so an application usually only
/// receives it. Create one yourself to read configuration without
/// starting a context, in a command-line tool or a test, or to give a
/// context an environment prepared in advance.
///
/// It starts with one property source, a [SystemEnvironmentPropertySource]
/// (empty on the web). Unlike Spring there are no JVM system properties,
/// so command-line arguments are usually the highest source.
///
/// ```dart
/// // A tool that reads the application's configuration by itself.
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
  /// Creates an environment whose only property source is the environment
  /// variables. [systemEnvironment] replaces the variables of the process,
  /// so a test can set them.
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

  /// The property that lists the active profiles, comma-separated:
  /// `spring.profiles.active`.
  static const activeProfilesPropertyName = 'spring.profiles.active';

  /// The property that lists the default profiles, comma-separated:
  /// `spring.profiles.default`.
  static const defaultProfilesPropertyName = 'spring.profiles.default';

  /// The name of the default profile unless changed: `default`.
  static const reservedDefaultProfileName = 'default';

  @override
  final MutablePropertySources propertySources = MutablePropertySources();

  @override
  final Map<String, String> systemEnvironment;

  late final PropertySourcesPropertyResolver _resolver;
  final _active = <String>{};
  final _defaults = <String>{reservedDefaultProfileName};

  /// Adds the sources a new environment starts with: the environment
  /// variables. Override it in a subclass that should always start with
  /// more sources.
  ///
  /// It runs inside the constructor, before the subclass's own fields are
  /// initialized, so it must not use them.
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
    _log.debug(() => 'Activating profiles ${profiles.map(_quote).toList()}');
    _active
      ..clear()
      ..addAll(profiles);
  }

  @override
  void addActiveProfile(String profile) {
    _validateProfile(profile);
    _doGetActive();
    _log.debug(() => 'Activating profile ${_quote(profile)}');
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

  /// Whether the single profile [profile] is active, or is a default
  /// profile while none is active. For expressions use
  /// [matchesProfiles].
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

const _log = SpringLog('spring_core_dart.core.env');

String _quote(String profile) => LogFormatUtils.formatValue(profile);
