import 'dart:math' as math;

import 'package:spring_core_dart/src/core/env/config/config_data_exceptions.dart';
import 'package:spring_core_dart/src/core/env/config/property_source_loader.dart';
import 'package:spring_core_dart/src/core/env/config/yaml_property_source_loader.dart';
import 'package:spring_core_dart/src/core/env/configuration_property_sources.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
import 'package:spring_core_dart/src/core/env/profiles.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/classpath_resources.dart';
import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// Loads `application.properties` and `application.yml` config files into
/// an environment, like Spring Boot's config data support.
///
/// - Files `<name>.<ext>` and `<name>-<profile>.<ext>` are searched in each
///   location. Locations come in groups: in `spring.config.location` and
///   `spring.config.additional-location`, `,` separates groups and `;`
///   joins locations into one group. The defaults are two groups,
///   `optional:classpath:/;optional:classpath:/config/` and
///   `optional:file:./;optional:file:./config/;optional:file:./config/*/`
///   (`*/` searches every subdirectory, in alphabetical order). Within a
///   group, later locations override earlier ones and profile-specific
///   files override the non-profile ones; a later group overrides an
///   earlier one entirely, so `./application.properties` beats a packaged
///   `application-prod.properties`. With several active profiles the last
///   one wins. In one location `.properties` beats `.yml` / `.yaml`.
/// - `.properties` ([PropertiesPropertySourceLoader]) and YAML
///   ([YamlPropertySourceLoader]: nested keys become `a.b`, list items
///   `a.hosts[0]`) are built in; other formats need a
///   [PropertySourceLoader].
/// - `spring.profiles.active` / `spring.profiles.include` /
///   `spring.profiles.group.<name>` in config files activate profiles
///   (unless profiles were already set programmatically or by a
///   higher-precedence source such as command-line arguments). Profile
///   names are validated like Boot's (letters, digits, `-_.+@`, starting
///   and ending with a letter or digit; `spring.profiles.validate=false`
///   turns this off).
/// - Multi-document files: documents separated by `#---` (`---` in YAML),
///   each optionally guarded by `spring.config.activate.on-profile` (an
///   empty guard is no guard). The legacy `spring.profiles` key is
///   rejected.
/// - `spring.config.import` imports more files (relative to the importing
///   file); imported files override the file that imports them.
/// - `spring.config.name`, `spring.config.location` and
///   `spring.config.additional-location` change what is searched.
/// - `optional:` locations never fail when missing.
/// - Relaxed names: the environment gets Boot's
///   [ConfigurationPropertySources] attached, so `app.read-timeout` also
///   finds `app.readTimeout`, `app.read_timeout` or `APP_READTIMEOUT`.
///
/// Config sources are added below the sources already present (command
/// line, OS environment).
///
/// ```dart
/// Future<void> main(List<String> args) async {
///   final environment = StandardEnvironment()
///     ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
///   // Reads application.yml / application.properties from lib/resources/,
///   // then ./application.properties, ./config/application-dev.yml...
///   await ConfigDataEnvironment(environment).processAndApply();
///   final context = ApplicationContext.run(
///     [appBeans],
///     environment: environment,
///   );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring Boot runs config data processing inside SpringApplication.run,
/// // via ConfigDataEnvironmentPostProcessor:
/// public static void main(String[] args) {
///   SpringApplication.run(App.class, args);
/// }
/// ```
///
/// ```yaml
/// # application.yml
/// spring:
///   profiles:
///     active: dev
///   config:
///     import: optional:file:./secrets.yml
/// ---
/// spring.config.activate.on-profile: dev
/// app:
///   debug: true
/// ```
///
/// Differences from Spring Boot: without `SpringApplication`, run it
/// explicitly before creating the context; the classpath is `lib/resources/`
/// (custom resource loaders, such as Flutter assets, work too).
class ConfigDataEnvironment {
  /// Creates a processor for [environment].
  ///
  /// [resourceLoader] resolves locations (default: `DefaultResourceLoader`),
  /// [loaders] parse files by extension, and [defaultLocations] replaces
  /// [defaultSearchLocations] (each entry is a group of `;`-separated
  /// locations; still overridable by `spring.config.location`).
  ///
  /// ```dart
  /// ConfigDataEnvironment(
  ///   environment,
  ///   resourceLoader: DefaultResourceLoader(
  ///     protocolResolvers: [InMemoryProtocolResolver('memory:', files)],
  ///   ),
  ///   loaders: const [
  ///     PropertiesPropertySourceLoader(),
  ///     YamlPropertySourceLoader(),
  ///   ],
  ///   defaultLocations: const ['optional:memory:;optional:memory:config/'],
  /// );
  /// ```
  ConfigDataEnvironment(
    this.environment, {
    ResourceLoader? resourceLoader,
    List<PropertySourceLoader> loaders = const [
      PropertiesPropertySourceLoader(),
      YamlPropertySourceLoader(),
    ],
    List<String> defaultLocations = defaultSearchLocations,
  }) : resourceLoader = resourceLoader ?? DefaultResourceLoader(),
       loaders = List.unmodifiable(loaders),
       defaultLocations = List.unmodifiable(defaultLocations);

  /// Default search locations, Spring Boot's: two groups (lowest
  /// precedence first) of `;`-separated locations. `classpath:` is
  /// `lib/resources/` (see `ClasspathResources`); `config/*/` searches
  /// each subdirectory of `./config/`.
  static const defaultSearchLocations = [
    'optional:classpath:/;optional:classpath:/config/',
    'optional:file:./;optional:file:./config/;optional:file:./config/*/',
  ];

  /// Base names of config files, comma-separated (default `application`).
  static const configNameProperty = 'spring.config.name';

  /// Locations that replace [defaultSearchLocations] (`,` separates
  /// groups, `;` joins locations into one group).
  static const locationProperty = 'spring.config.location';

  /// Locations searched in addition to (and after) the default ones.
  static const additionalLocationProperty = 'spring.config.additional-location';

  /// Files to import from a config document, relative to that document.
  static const importProperty = 'spring.config.import';

  /// Profile expressions that must match for a document to be used.
  static const onProfileProperty = 'spring.config.activate.on-profile';

  /// Profiles to add to the active ones, comma-separated.
  static const includeProfilesProperty = 'spring.profiles.include';

  /// Prefix of profile group properties: `spring.profiles.group.prod=db,mq`
  /// activates `db` and `mq` whenever `prod` is active.
  static const profileGroupPrefix = 'spring.profiles.group.';

  /// `false` turns off the validation of profile names (Boot's
  /// `spring.profiles.validate`, default `true`).
  static const validateProfilesProperty = 'spring.profiles.validate';

  /// The legacy profile guard, rejected like Boot does since 2.4.
  static const legacyProfilesProperty = 'spring.profiles';

  /// Prefix marking a location that may be missing.
  static const optionalPrefix = 'optional:';

  // Properties that may only appear in non-profile documents.
  static const _profileProperties = [
    StandardEnvironment.activeProfilesPropertyName,
    StandardEnvironment.defaultProfilesPropertyName,
    includeProfilesProperty,
  ];

  /// The environment that receives the config sources and profiles.
  final ConfigurableEnvironment environment;

  /// Resolves config locations to resources.
  final ResourceLoader resourceLoader;

  /// File format loaders; the first one handling an extension is used.
  final List<PropertySourceLoader> loaders;

  /// Search location groups used when `spring.config.location` is not
  /// set; each entry is a group of `;`-separated locations.
  final List<String> defaultLocations;

  /// Loads the config files, reading async-only resources (such as Flutter
  /// assets) asynchronously, and adds them to [environment].
  ///
  /// Also sets the resulting active profiles on [environment]. Call it once
  /// before creating the application context.
  ///
  /// ```dart
  /// await ConfigDataEnvironment(environment).processAndApply();
  /// ```
  Future<void> processAndApply() async {
    // Processing itself is synchronous: whenever it hits a resource that
    // can only be read asynchronously, it aborts with _NeedsContent; the
    // content is then read into the cache and the whole pass is re-run.
    final cache = <String, String?>{};
    while (true) {
      try {
        _apply(_Run(this, cache, allowAsync: true).process());
        return;
      } on _NeedsContent catch (needed) {
        final resource = needed.resource;
        cache[resource.description] = resource.exists()
            ? await resource.readAsString()
            : null;
      }
    }
  }

  /// Synchronous variant of [processAndApply]; every resource must support
  /// synchronous reading.
  ///
  /// Throws `ConfigDataLoadException` for an async-only resource.
  ///
  /// ```dart
  /// ConfigDataEnvironment(environment).processAndApplySync();
  /// ```
  void processAndApplySync() =>
      _apply(_Run(this, <String, String?>{}, allowAsync: false).process());

  // Config sources go below everything already present (command line, OS
  // environment), keeping their relative order; then relaxed names are
  // attached, as SpringApplication does in Spring Boot.
  void _apply(_Result result) {
    for (final source in result.sources) {
      environment.propertySources.addLast(source);
    }
    if (result.activeProfiles.isNotEmpty) {
      environment.setActiveProfiles(result.activeProfiles);
    }
    ConfigurationPropertySources.attach(environment);
  }
}

// Outcome of one processing pass.
final class _Result {
  _Result(this.sources, this.activeProfiles);

  // Highest precedence first.
  final List<AbstractPropertySource<Object>> sources;
  final List<String> activeProfiles;
}

// Signals that [resource] must be read asynchronously before retrying.
final class _NeedsContent implements Exception {
  _NeedsContent(this.resource);

  final Resource resource;
}

// One loaded document (a file, or one `#---` section of it).
final class _Document {
  _Document(this.source, this.location, {required this.profileSpecific})
    : onProfile = _guard(
        _Run._value(
          source.getProperty,
          ConfigDataEnvironment.onProfileProperty,
        ),
      );

  // An empty on-profile is no guard at all, as in Boot (an empty array).
  static String? _guard(String? text) =>
      text == null || text.trim().isEmpty ? null : text;

  final AbstractPropertySource<Object> source;
  final String location;
  final bool profileSpecific;
  // The raw on-profile guard; placeholders are resolved on activation.
  final String? onProfile;
  // Whether its on-profile guard matched; inactive documents are dropped.
  bool active = false;
  bool importsProcessed = false;
}

// A single processing pass; re-run after async content arrives.
final class _Run {
  _Run(this.owner, this.cache, {required this.allowAsync});

  final ConfigDataEnvironment owner;
  final Map<String, String?> cache;
  final bool allowAsync;

  // The documents of each location group, lowest precedence first (both
  // the groups and the documents in a group).
  final _groups = <List<_Document>>[];
  // Locations already loaded; guards against import cycles and duplicates.
  final _loaded = <String>{};

  ConfigurableEnvironment get _env => owner.environment;

  _Result process() {
    final names =
        _list(
          _value(_env.getProperty, ConfigDataEnvironment.configNameProperty),
        ) ??
        const ['application'];
    // Like Boot: `,` separates groups, `;` joins locations into a group.
    List<List<String>> groupsOf(Iterable<String> values) => [
      for (final value in values)
        if (_split(value, ';') case final group when group.isNotEmpty) group,
    ];
    final locations = [
      ...groupsOf(
        _list(
              _value(_env.getProperty, ConfigDataEnvironment.locationProperty),
            ) ??
            owner.defaultLocations,
      ),
      ...groupsOf(
        _list(
              _value(
                _env.getProperty,
                ConfigDataEnvironment.additionalLocationProperty,
              ),
            ) ??
            const [],
      ),
    ];

    // 1. Non-profile files.
    for (final group in locations) {
      _groups.add([
        for (final location in group)
          ..._loadLocation(location, names, profile: null),
      ]);
    }
    // Documents guarded by on-profile stay inactive until the profiles are
    // known (like Spring Boot), so `!prod` is not applied before we know
    // whether prod is active.
    _activate(const [], profilesKnown: false);

    // 2. Profiles from the environment and the active documents.
    final profiles = _resolveProfiles();
    final effective = profiles.isEmpty ? _env.defaultProfiles : profiles;

    // 3. Profile-specific files, then documents guarded by on-profile. In
    // a group they override its non-profile files (and their imports); a
    // later group still overrides an earlier one entirely.
    for (var i = 0; i < locations.length; i++) {
      for (final profile in effective) {
        for (final location in locations[i]) {
          _groups[i].addAll(_loadLocation(location, names, profile: profile));
        }
      }
    }
    _activate(effective);

    return _Result([
      for (final document in _documents.toList().reversed)
        if (document.active) document.source,
    ], profiles);
  }

  // All documents, lowest precedence first.
  Iterable<_Document> get _documents => _groups.expand((group) => group);

  // Activates documents whose on-profile matches and loads their imports
  // until nothing changes. Imports are inserted right after the importing
  // document, i.e. with higher precedence than it.
  void _activate(List<String> profiles, {bool profilesKnown = true}) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final documents in _groups) {
        for (var i = 0; i < documents.length; i++) {
          final document = documents[i];
          if (!document.active) {
            if (!profilesKnown && document.onProfile != null) {
              continue;
            }
            document.active = _matchesProfiles(document, profiles);
            if (!document.active) {
              continue;
            }
            _validate(document);
            changed = true;
          }
          if (!document.importsProcessed) {
            document.importsProcessed = true;
            final imported = _imports(document);
            if (imported.isNotEmpty) {
              documents.insertAll(i + 1, imported);
              changed = true;
            }
          }
        }
      }
    }
  }

  // Whether the on-profile guard of [document] (if any) matches
  // [profiles]. `${...}` in the guard is resolved against the environment
  // and the documents active so far, like Spring Boot's binder does.
  bool _matchesProfiles(_Document document, List<String> profiles) {
    final guard = document.onProfile;
    if (guard == null) {
      return true;
    }
    final resolved = _list(
      _resolver(document).resolveRequiredPlaceholders(guard),
    );
    return resolved == null || Profiles.of(resolved).matches(profiles.contains);
  }

  // Profile-specific files and on-profile documents must not change the
  // profiles themselves (Spring Boot rejects this too).
  void _validate(_Document document) {
    if (!document.profileSpecific && document.onProfile == null) {
      return;
    }
    final names = document.source is EnumerablePropertySource<Object>
        ? (document.source as EnumerablePropertySource<Object>).propertyNames
        : const <String>[];
    for (final name in [
      for (final property in ConfigDataEnvironment._profileProperties) ...[
        property,
        '$property[0]', // A YAML list.
      ],
      ...names.where(
        (n) => n.startsWith(ConfigDataEnvironment.profileGroupPrefix),
      ),
    ]) {
      if (document.source.containsProperty(name)) {
        throw InvalidConfigDataPropertyException(
          name,
          document.source.name,
          'not allowed in a profile-specific document',
        );
      }
    }
  }

  // Loads the `spring.config.import` locations of [document]; relative
  // locations are resolved against the importing file's directory.
  List<_Document> _imports(_Document document) {
    final value = _value(
      document.source.getProperty,
      ConfigDataEnvironment.importProperty,
    );
    final locations = _list(
      value == null
          ? null
          : _resolver(document).resolveRequiredPlaceholders(value),
    );
    if (locations == null) {
      return const [];
    }
    final result = <_Document>[];
    for (final raw in locations) {
      final optional = raw.startsWith(ConfigDataEnvironment.optionalPrefix);
      final location = optional
          ? raw.substring(ConfigDataEnvironment.optionalPrefix.length)
          : raw;
      final absolute = _isRelative(location)
          ? '${_parent(document.location)}$location'
          : location;
      result.addAll(
        _loadFile(
          absolute,
          optional: optional,
          profileSpecific: document.profileSpecific,
        ),
      );
    }
    return result;
  }

  // A resolver over the environment and the documents active so far, with
  // [document] on top. Names are relaxed, as with Boot's binder.
  PropertyResolver _resolver([_Document? document]) {
    final sources = [
      ?document?.source,
      ..._env.propertySources.where(
        (s) => s is! ConfigurationPropertySourcesPropertySource,
      ),
      for (final d in _documents.toList().reversed)
        if (d.active && d != document) d.source,
    ];
    return PropertySourcesPropertyResolver(
      MutablePropertySources([
        ConfigurationPropertySourcesPropertySource(
          ConfigurationPropertySources.attachedPropertySourceName,
          sources,
        ),
        ...sources,
      ]),
    );
  }

  // Active profiles, like Spring Boot's `Profiles`: included profiles
  // first (from every source), then programmatic ones or
  // `spring.profiles.active`, then expanded profile groups. Later profiles
  // win, so `application-{active}` overrides `application-{included}`.
  List<String> _resolveProfiles() {
    final resolver = _resolver();
    final validate =
        resolver.getPropertyAs<bool>(
          ConfigDataEnvironment.validateProfilesProperty,
        ) ??
        true;
    void check(Iterable<String> profiles, String property) {
      if (validate) {
        for (final profile in profiles) {
          _validateProfileName(profile, property);
        }
      }
    }

    check(
      _env.defaultProfiles,
      StandardEnvironment.defaultProfilesPropertyName,
    );
    final active = <String>[];
    // Includes from every source are combined.
    for (final source in [
      ..._env.propertySources.where(
        (s) => s is! ConfigurationPropertySourcesPropertySource,
      ),
      for (final d in _documents)
        if (d.active) d.source,
    ]) {
      final included =
          _list(
            _value(
              source.getProperty,
              ConfigDataEnvironment.includeProfilesProperty,
            ),
          ) ??
          const <String>[];
      check(included, ConfigDataEnvironment.includeProfilesProperty);
      for (final profile in included) {
        if (!active.contains(profile)) {
          active.add(profile);
        }
      }
    }
    final declared = _env.activeProfiles.isNotEmpty
        ? _env.activeProfiles
        : _list(
                _value(
                  resolver.getProperty,
                  StandardEnvironment.activeProfilesPropertyName,
                ),
              ) ??
              const <String>[];
    check(declared, StandardEnvironment.activeProfilesPropertyName);
    for (final profile in declared) {
      if (!active.contains(profile)) {
        active.add(profile);
      }
    }
    // Expand groups (members follow their group; nested groups allowed).
    for (var i = 0; i < active.length; i++) {
      final group = '${ConfigDataEnvironment.profileGroupPrefix}${active[i]}';
      final members = _list(_value(resolver.getProperty, group));
      check(members ?? const [], group);
      var insertAt = i + 1;
      for (final member in members ?? const <String>[]) {
        if (!active.contains(member)) {
          active.insert(insertAt++, member);
        }
      }
    }
    return active;
  }

  // Profile names like Boot's ProfilesValidator: letters, digits and
  // `-_.+@`, starting and ending with a letter or digit.
  static void _validateProfileName(String profile, String property) {
    final chars = profile.runes.map(String.fromCharCode).toList();
    for (var i = 0; i < chars.length; i++) {
      final letterOrDigit = _letterOrDigit.hasMatch(chars[i]);
      if (!letterOrDigit && !'-_.+@'.contains(chars[i])) {
        throw StateError(
          "Invalid profile property value found in '$property': Profile "
          "'$profile' must contain a letter, digit or allowed char "
          "('-', '_', '.', '+', '@')",
        );
      }
      if (!letterOrDigit && (i == 0 || i == chars.length - 1)) {
        throw StateError(
          "Invalid profile property value found in '$property': Profile "
          "'$profile' must start and end with a letter or digit",
        );
      }
    }
  }

  static final _letterOrDigit = RegExp(r'^[\p{L}\p{Nd}]$', unicode: true);

  // A location ending in `/` is a directory searched for every name and
  // extension; otherwise it is a file, whose profile variant is
  // `name-profile.ext`. Files found by search are always optional. A `*/`
  // segment stands for each subdirectory (Boot's wildcard locations).
  List<_Document> _loadLocation(
    String rawLocation,
    List<String> names, {
    required String? profile,
  }) {
    final optional = rawLocation.startsWith(
      ConfigDataEnvironment.optionalPrefix,
    );
    final location = _env.resolveRequiredPlaceholders(
      optional
          ? rawLocation.substring(ConfigDataEnvironment.optionalPrefix.length)
          : rawLocation,
    );
    final suffix = profile == null ? '' : '-$profile';
    final profileSpecific = profile != null;
    if (location.endsWith('/')) {
      // Like Boot's resolver, earlier loaders' extensions take precedence
      // (`.properties` beats `.yml`), so they are loaded last.
      final extensions = <String>[];
      for (final loader in owner.loaders) {
        for (final extension in loader.fileExtensions) {
          if (!extensions.contains(extension)) {
            extensions.insert(0, extension);
          }
        }
      }
      final directories = location.contains('*')
          ? _subdirectories(location, location)
          : [location];
      return [
        for (final name in names)
          for (final extension in extensions)
            for (final directory in directories)
              ..._loadFile(
                '$directory$name$suffix.$extension',
                optional: true,
                profileSpecific: profileSpecific,
              ),
      ];
    }
    var file = location;
    if (profile != null) {
      // No extension in the file name: there is no profile variant.
      final dot = file.lastIndexOf('.');
      if (dot <= file.lastIndexOf('/')) {
        return const [];
      }
      file = '${file.substring(0, dot)}$suffix${file.substring(dot)}';
    }
    if (file.contains('*')) {
      final slash = file.lastIndexOf('/');
      return [
        for (final directory in _subdirectories(
          file.substring(0, slash + 1),
          location,
        ))
          ..._loadFile(
            '$directory${file.substring(slash + 1)}',
            optional: true,
            profileSpecific: profileSpecific,
          ),
      ];
    }
    return _loadFile(
      file,
      optional: optional || profileSpecific,
      profileSpecific: profileSpecific,
    );
  }

  // The subdirectories of a `dir/*/` [pattern] as locations, sorted by
  // name, without hidden `..x` ones (Kubernetes' `..data`), like Boot's
  // LocationResourceLoader. Only file system locations may use `*`.
  List<String> _subdirectories(String pattern, String location) {
    if (location.startsWith(ClasspathResources.prefix)) {
      throw ConfigDataLoadException(
        location,
        'classpath wildcard locations are not supported',
      );
    }
    final star = pattern.indexOf('*');
    if (location.indexOf('*') != location.lastIndexOf('*')) {
      throw ConfigDataLoadException(
        location,
        'a location cannot contain multiple wildcards',
      );
    }
    if (!pattern.endsWith('*/') || star != pattern.length - 2) {
      throw ConfigDataLoadException(
        location,
        "a wildcard location must end with '*/' or '*/<file name>'",
      );
    }
    final base = pattern.substring(0, star);
    final resource = owner.resourceLoader.getResource(
      _isUrl(base) ? base : '${ResourceLoader.filePrefix}$base',
    );
    if (resource is! FileSystemResource) {
      throw ConfigDataLoadException(
        location,
        'wildcard locations must be file system locations',
      );
    }
    return [
      for (final path in FileAccess.listDirectories(resource.path))
        if (path.substring(path.lastIndexOf('/') + 1) case final name
            when !name.startsWith('..'))
          '$base$name/',
    ];
  }

  List<_Document> _loadFile(
    String location, {
    required bool optional,
    required bool profileSpecific,
  }) {
    final extension = location.contains('.')
        ? location.substring(location.lastIndexOf('.') + 1)
        : '';
    final loader = owner.loaders
        .where((l) => l.fileExtensions.contains(extension))
        .firstOrNull;
    if (loader == null) {
      if (optional) {
        return const [];
      }
      throw ConfigDataLoadException(
        location,
        "no PropertySourceLoader for extension '$extension'",
      );
    }
    // A location without a prefix is a file, like Boot's
    // LocationResourceLoader (unlike a plain path in DefaultResourceLoader).
    final resource = owner.resourceLoader.getResource(
      _isUrl(location) ? location : '${ResourceLoader.filePrefix}$location',
    );
    final content = _read(resource, location);
    if (content == null) {
      if (optional) {
        return const [];
      }
      throw ConfigDataResourceNotFoundException(location, resource.description);
    }
    // Deduplicated on the normalized location, so `./application.properties`
    // or `config/../config/a.properties` cannot import themselves forever.
    if (!_loaded.add(_normalized(location))) {
      return const []; // Already loaded (import cycle or duplicate).
    }
    final List<AbstractPropertySource<Object>> sources;
    try {
      sources = loader.load("Config resource '$location'", content);
    } on FormatException catch (error) {
      // Like Boot's "Failed to load property source from location".
      throw ConfigDataLoadException(location, error.toString());
    }
    // Boot rejects the pre-2.4 guard wherever it appears.
    for (final source in sources) {
      for (final legacy in [
        ConfigDataEnvironment.legacyProfilesProperty,
        '${ConfigDataEnvironment.legacyProfilesProperty}[0]',
      ]) {
        if (source.containsProperty(legacy)) {
          throw InvalidConfigDataPropertyException(
            legacy,
            source.name,
            "it should be replaced with '${ConfigDataEnvironment.onProfileProperty}'",
          );
        }
      }
    }
    return [
      for (final source in sources)
        _Document(source, location, profileSpecific: profileSpecific),
    ];
  }

  // Content of [resource] from the cache or a synchronous read; `null` if
  // it does not exist. Cached by description so a re-run after an async
  // read does not touch the resource again.
  String? _read(Resource resource, String location) {
    final key = resource.description;
    if (cache.containsKey(key)) {
      return cache[key];
    }
    if (!resource.exists()) {
      return cache[key] = null;
    }
    if (resource.supportsSyncRead) {
      return cache[key] = resource.readAsStringSync();
    }
    if (allowAsync) {
      throw _NeedsContent(resource);
    }
    throw ConfigDataLoadException(
      location,
      'the resource can only be read asynchronously; use processAndApply()',
    );
  }

  // Comma-separated value as trimmed, non-empty parts; `null` if none.
  static List<String>? _list(Object? value) {
    if (value == null) {
      return null;
    }
    final parts = _split(value.toString(), ',');
    return parts.isEmpty ? null : parts;
  }

  static List<String> _split(String value, String separator) => [
    for (final part in value.split(separator))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  // The value of [key] from [get] as text: the value itself, or the items
  // of a YAML list (`key[0]`, `key[1]`, ...) joined with commas.
  static String? _value(Object? Function(String key) get, String key) {
    final value = get(key);
    if (value != null) {
      return value.toString();
    }
    final items = <String>[];
    for (Object? item; (item = get('$key[${items.length}]')) != null;) {
      items.add(item.toString());
    }
    return items.isEmpty ? null : items.join(',');
  }

  // Absolute: `/x`, `\x`, a Windows drive path (`C:\x`, `C:/x`) or a
  // URL-like location with a scheme of two or more letters (`file:`,
  // `asset:`).
  static bool _isRelative(String location) =>
      !location.startsWith('/') &&
      !location.startsWith(r'\') &&
      !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(location) &&
      !_isUrl(location);

  // A `scheme:` prefix of two or more letters (`file:`, `classpath:`).
  static bool _isUrl(String location) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(location);

  // Directory part of [location] (with trailing `/`), or just its prefix
  // (`file:`) when there is no slash.
  // [location] with `.` and `dir/..` path segments removed (the scheme
  // prefix such as `file:` is kept).
  static String _normalized(String location) {
    final match = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').firstMatch(location);
    final scheme =
        match == null ||
            match.end == 2 && location.length > 2 && location[2] == r'\'
        ? ''
        : match.group(0)!;
    final path = location.substring(scheme.length).replaceAll(r'\', '/');
    final absolute = path.startsWith('/');
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..' && segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else {
        segments.add(segment);
      }
    }
    return '$scheme${absolute ? '/' : ''}${segments.join('/')}';
  }

  static String _parent(String location) {
    final slash = math.max(
      location.lastIndexOf('/'),
      location.lastIndexOf(r'\'),
    );
    if (slash >= 0) {
      return location.substring(0, slash + 1);
    }
    final colon = location.indexOf(':');
    return colon >= 0 ? location.substring(0, colon + 1) : '';
  }
}
