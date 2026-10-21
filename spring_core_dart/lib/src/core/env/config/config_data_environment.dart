import 'dart:math' as math;

import 'package:spring_core_dart/src/core/env/config/config_data_exceptions.dart';
import 'package:spring_core_dart/src/core/env/config/property_source_loader.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
import 'package:spring_core_dart/src/core/env/profiles.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// Loads `application.properties` style config files into an environment,
/// like Spring Boot's config data support.
///
/// - Files `<name>.<ext>` and `<name>-<profile>.<ext>` are searched in each
///   location (`file:./`, `file:./config/` by default); later locations
///   override earlier ones and profile-specific files override all
///   non-profile files. With several active profiles the last one wins.
/// - `spring.profiles.active` / `spring.profiles.include` /
///   `spring.profiles.group.<name>` in config files activate profiles
///   (unless profiles were already set programmatically or by a
///   higher-precedence source such as command-line arguments).
/// - Multi-document files: documents separated by `#---`, each optionally
///   guarded by `spring.config.activate.on-profile`.
/// - `spring.config.import` imports more files (relative to the importing
///   file); imported files override the file that imports them.
/// - `spring.config.name`, `spring.config.location` and
///   `spring.config.additional-location` change what is searched.
/// - `optional:` locations never fail when missing.
///
/// Config sources are added below the sources already present (command
/// line, OS environment). The file format is chosen by extension through
/// [loaders]; add a YAML [PropertySourceLoader] to support YAML files.
///
/// ```dart
/// Future<void> main(List<String> args) async {
///   final environment = StandardEnvironment()
///     ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
///   // Reads ./application.properties, ./config/application-dev.properties…
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
/// ```properties
/// # application.properties
/// spring.profiles.active=dev
/// spring.config.import=optional:file:./secrets.properties
/// #---
/// spring.config.activate.on-profile=dev
/// app.debug=true
/// ```
///
/// Differences from Spring Boot: run it explicitly before creating the
/// context; there is no classpath (use `file:` or custom resource loaders
/// such as Flutter assets); only `.properties` is built in.
class ConfigDataEnvironment {
  /// Creates a processor for [environment].
  ///
  /// [resourceLoader] resolves locations (default: `DefaultResourceLoader`),
  /// [loaders] parse files by extension, and [defaultLocations] replaces
  /// [defaultSearchLocations] (still overridable by
  /// `spring.config.location`).
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
  ///   defaultLocations: const ['optional:memory:config/'],
  /// );
  /// ```
  ConfigDataEnvironment(
    this.environment, {
    ResourceLoader? resourceLoader,
    List<PropertySourceLoader> loaders = const [
      PropertiesPropertySourceLoader(),
    ],
    List<String> defaultLocations = defaultSearchLocations,
  }) : resourceLoader = resourceLoader ?? DefaultResourceLoader(),
       loaders = List.unmodifiable(loaders),
       defaultLocations = List.unmodifiable(defaultLocations);

  /// Default search locations, lowest precedence first.
  ///
  /// Spring Boot also searches `classpath:/` and `classpath:/config/`;
  /// Dart has no classpath.
  static const defaultSearchLocations = [
    'optional:file:./',
    'optional:file:./config/',
  ];

  /// Base names of config files, comma-separated (default `application`).
  static const configNameProperty = 'spring.config.name';

  /// Locations that replace [defaultSearchLocations].
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

  /// Search locations used when `spring.config.location` is not set.
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
  // environment), keeping their relative order.
  void _apply(_Result result) {
    for (final source in result.sources) {
      environment.propertySources.addLast(source);
    }
    if (result.activeProfiles.isNotEmpty) {
      environment.setActiveProfiles(result.activeProfiles);
    }
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
    : onProfile = source
          .getProperty(ConfigDataEnvironment.onProfileProperty)
          ?.toString();

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

  // Lowest precedence first.
  final _documents = <_Document>[];
  // Locations already loaded; guards against import cycles and duplicates.
  final _loaded = <String>{};

  ConfigurableEnvironment get _env => owner.environment;

  _Result process() {
    final names =
        _list(_env.getProperty(ConfigDataEnvironment.configNameProperty)) ??
        const ['application'];
    final locations = [
      ...(_list(_env.getProperty(ConfigDataEnvironment.locationProperty)) ??
          owner.defaultLocations),
      ...?_list(
        _env.getProperty(ConfigDataEnvironment.additionalLocationProperty),
      ),
    ];

    // 1. Non-profile files.
    for (final location in locations) {
      _documents.addAll(_loadLocation(location, names, profile: null));
    }
    // Documents guarded by on-profile stay inactive until the profiles are
    // known (like Spring Boot), so `!prod` is not applied before we know
    // whether prod is active.
    _activate(const [], profilesKnown: false);

    // 2. Profiles from the environment and the active documents.
    final profiles = _resolveProfiles();
    final effective = profiles.isEmpty ? _env.defaultProfiles : profiles;

    // 3. Profile-specific files, then documents guarded by on-profile.
    for (final profile in effective) {
      for (final location in locations) {
        _documents.addAll(_loadLocation(location, names, profile: profile));
      }
    }
    _activate(effective);

    return _Result([
      for (final document in _documents.reversed)
        if (document.active) document.source,
    ], profiles);
  }

  // Activates documents whose on-profile matches and loads their imports
  // until nothing changes. Imports are inserted right after the importing
  // document, i.e. with higher precedence than it.
  void _activate(List<String> profiles, {bool profilesKnown = true}) {
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < _documents.length; i++) {
        final document = _documents[i];
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
            _documents.insertAll(i + 1, imported);
            changed = true;
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
    final resolved = _resolver(document).resolveRequiredPlaceholders(guard);
    return Profiles.of([
      for (final part in resolved.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ]).matches(profiles.contains);
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
      ...ConfigDataEnvironment._profileProperties,
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
    final value = document.source.getProperty(
      ConfigDataEnvironment.importProperty,
    );
    final locations = _list(
      value == null
          ? null
          : _resolver(document).resolveRequiredPlaceholders(value.toString()),
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
  // [document] on top.
  PropertyResolver _resolver([_Document? document]) =>
      PropertySourcesPropertyResolver(
        MutablePropertySources([
          ?document?.source,
          ..._env.propertySources,
          for (final d in _documents.reversed)
            if (d.active && d != document) d.source,
        ]),
      );

  // Active profiles: programmatic ones, else `spring.profiles.active`; then
  // includes from every source; then expanded profile groups.
  List<String> _resolveProfiles() {
    final resolver = _resolver();
    final active = <String>[..._env.activeProfiles];
    if (active.isEmpty) {
      active.addAll(
        _list(
              resolver.getProperty(
                StandardEnvironment.activeProfilesPropertyName,
              ),
            ) ??
            const [],
      );
    }
    // Includes from every source are combined.
    for (final source in [
      ..._env.propertySources,
      for (final d in _documents)
        if (d.active) d.source,
    ]) {
      final include = source.getProperty(
        ConfigDataEnvironment.includeProfilesProperty,
      );
      for (final profile in _list(include?.toString()) ?? const <String>[]) {
        if (!active.contains(profile)) {
          active.add(profile);
        }
      }
    }
    // Expand groups (members follow their group; nested groups allowed).
    for (var i = 0; i < active.length; i++) {
      final members = _list(
        resolver.getProperty(
          '${ConfigDataEnvironment.profileGroupPrefix}${active[i]}',
        ),
      );
      var insertAt = i + 1;
      for (final member in members ?? const <String>[]) {
        if (!active.contains(member)) {
          active.insert(insertAt++, member);
        }
      }
    }
    return active;
  }

  // A location ending in `/` is a directory searched for every name and
  // extension; otherwise it is a file, whose profile variant is
  // `name-profile.ext`. Files found by search are always optional.
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
    if (location.endsWith('/')) {
      return [
        for (final name in names)
          for (final loader in owner.loaders)
            for (final extension in loader.fileExtensions)
              ..._loadFile(
                '$location$name$suffix.$extension',
                optional: true,
                profileSpecific: profile != null,
              ),
      ];
    }
    if (profile == null) {
      return _loadFile(location, optional: optional, profileSpecific: false);
    }
    // No extension in the file name: there is no profile variant.
    final dot = location.lastIndexOf('.');
    if (dot <= location.lastIndexOf('/')) {
      return const [];
    }
    return _loadFile(
      '${location.substring(0, dot)}$suffix${location.substring(dot)}',
      optional: true,
      profileSpecific: true,
    );
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
    final resource = owner.resourceLoader.getResource(location);
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
    return [
      for (final source in loader.load("Config resource '$location'", content))
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
    final parts = [
      for (final part in value.toString().split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return parts.isEmpty ? null : parts;
  }

  // Absolute: `/x`, `\x`, a Windows drive path (`C:\x`, `C:/x`) or a
  // URL-like location with a scheme of two or more letters (`file:`,
  // `asset:`).
  static bool _isRelative(String location) =>
      !location.startsWith('/') &&
      !location.startsWith(r'\') &&
      !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(location) &&
      !RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(location);

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
