import 'dart:convert';
import 'dart:math' as math;

import 'package:spring_core_dart/src/core/env/cloud_platform.dart';
import 'package:spring_core_dart/src/core/env/config/config_data_exceptions.dart';
import 'package:spring_core_dart/src/core/env/config/property_source_loader.dart';
import 'package:spring_core_dart/src/core/env/config/yaml_property_source_loader.dart';
import 'package:spring_core_dart/src/core/env/configuration_property_name.dart';
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
import 'package:spring_core_dart/src/core/io/url_resource.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/log_format.dart';

/// Reads the application's config files (`application.properties`,
/// `application.yml` and their profile variants, imports, config trees)
/// into an environment and sets the active profiles they name.
///
/// This is what makes `lib/resources/application.yml` and
/// `--spring.profiles.active=prod` work. `SpringApplication` runs it on
/// every start, so applications with `spring_boot_dart` only write the
/// files. Run it yourself when you start an `ApplicationContext` without
/// `SpringApplication`, or in a tool or test that needs the configuration
/// without a context. Run it once, after the command line and other
/// sources are in the environment and before any bean reads a property.
///
/// What it reads, with Spring Boot's rules:
///
/// - Files `<name>.<ext>` and `<name>-<profile>.<ext>` in each location.
///   Locations come in groups: in `spring.config.location` and
///   `spring.config.additional-location`, `,` separates groups and `;`
///   joins locations into one group. The defaults are two groups,
///   `optional:classpath:/;optional:classpath:/config/` and
///   `optional:file:./;optional:file:./config/;optional:file:./config/*/`
///   (`*/` searches every subdirectory, in alphabetical order). Within a
///   group, later locations override earlier ones and profile files
///   override plain ones; a later group overrides an earlier one entirely,
///   so `./application.properties` beats a packaged
///   `application-prod.properties`. With several active profiles the last
///   one wins. In one location `.properties` beats `.yml` and `.yaml`. A
///   file named at several places is read once, at the place Boot keeps:
///   the later item of a list (`x,y,x` puts `x` above `y`), the command
///   line's `spring.config.import` before `additional-location` before
///   `location`, the first of two identical entries of a `;` group; the
///   encoding hint written there applies (the file is not read at the
///   other places).
/// - `.properties` ([PropertiesPropertySourceLoader]) and YAML
///   ([YamlPropertySourceLoader]: nested keys become `a.b`, list items
///   `a.hosts[0]`) are built in; other formats need a
///   [PropertySourceLoader].
/// - `spring.profiles.active`, `spring.profiles.include` and
///   `spring.profiles.group.<name>` in config files activate profiles (a
///   group's `<name>` matched exactly, as Boot's map keys are). A
///   higher source (command line, environment variables) wins over a
///   file's `spring.profiles.active`; profiles set in code
///   (`setActiveProfiles`) are kept and the file's are added after them;
///   `include` always adds; [additionalProfiles] come first.
///   `spring.profiles.default` (from the environment, the command line or
///   a non-profile document) picks the profile files while no profile is
///   active, groups expanded. Profile names are checked like Boot's
///   (letters, digits, `-_.+@`, starting and ending with a letter or
///   digit); `spring.profiles.validate=false` turns the check off. The
///   profiles are decided before the profile files are read: a
///   `-{profile}` file may not set the active, default or included
///   profiles, and an on-profile document read before them may set none
///   of the four keys ([InvalidConfigDataPropertyException]), under any
///   relaxed spelling (`spring.profiles.Active`); in the files read later
///   (imported by a profile file or an on-profile document) they are
///   ignored, like a profile file's groups.
/// - A file can hold several documents, separated by `#---` or `!---`
///   (`---` in YAML; [PropertiesPropertySourceLoader] says what counts as
///   a separator). Each can be limited with `spring.config.activate.on-profile`
///   (an empty guard is no guard) and
///   `spring.config.activate.on-cloud-platform` (the [CloudPlatform]
///   detected from the environment or set by `spring.main.cloud-platform`;
///   `none` matches when there is none). The legacy `spring.profiles` key
///   is rejected.
/// - `spring.config.import` imports more files (relative to the importing
///   file) or directories (`file:./config/`: `application*` files, like a
///   search location). Imported files override the file that imports them
///   and get their `-{profile}` variants too, which win over the profile
///   files of the importing file (Boot's order: with `application.yml`
///   importing `x.yml`, `x-dev.yml` beats `application-dev.yml`). On the
///   command line or as `SPRING_CONFIG_IMPORT` it imports above every
///   location, the variants of all its files above all its plain files.
/// - `spring.config.name`, `spring.config.location` and
///   `spring.config.additional-location` change what is searched; they are
///   read from the sources present before the files.
/// - `optional:` locations never fail when missing, and none does with
///   `spring.config.on-not-found=ignore`. Otherwise a missing file fails,
///   and so does a location that finds nothing (a missing directory, a
///   wildcard without a match), wherever it is written. As in Boot, that
///   is decided once the profile files are read: a location whose
///   `-{profile}` variant is found counts as found, and a `classpath:`
///   directory counts only when a file is found in it. The variants are
///   the only files that may always be missing. A `;` group of locations
///   (in `spring.config.import` too, in a file or not) is one location:
///   optional when its first entry is, found when any entry finds
///   something; a location that is not found is reported as written (the
///   whole group, a relative import as it is, an extension hint kept). A
///   location without a known extension needs a trailing `/` (a
///   directory) or an extension hint (`file:./conf[.yml]`). Extensions
///   and hints are matched without case, and the loader's spelling names
///   the file (`x.YAML` reads `x.yaml`), as in Boot. A file location also
///   takes Boot 4.1's encoding hint, `x.properties[encoding=iso-8859-1]`
///   ([fileHints]; [PropertySourceLoader.encodingFor] decides whether a
///   format uses it: `.properties` does, YAML does not). XML properties
///   files (Boot's `application.xml`) are not read.
/// - `configtree:` locations read a directory tree, one file per property
///   ([configTreePrefix]).
///
/// The config sources go below the sources already present (command line,
/// environment variables) and above a `defaultProperties` source
/// (`SpringApplication`'s default properties). Last, relaxed names are
/// switched on ([ConfigurationPropertySources.attach]), so
/// `app.read-timeout` also finds `app.readTimeout`, `app.read_timeout` or
/// `APP_READTIMEOUT`.
///
/// Errors fail with [ConfigDataResourceNotFoundException],
/// [ConfigDataLocationNotFoundException],
/// [InvalidConfigDataPropertyException] or [ConfigDataLoadException].
///
/// ```dart
/// // An application on spring_core_dart alone, without SpringApplication.
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
/// Spring (Java):
/// ```java
/// // Spring Boot runs config data processing inside SpringApplication.run,
/// // via ConfigDataEnvironmentPostProcessor:
/// public static void main(String[] args) {
///   SpringApplication.run(App.class, args);
/// }
/// ```
///
/// Differences from Spring Boot: without `SpringApplication`, run it
/// yourself before creating the context. The classpath is `lib/resources/`
/// (custom resource loaders, such as Flutter assets, work too). Boot 4.1.2
/// reads `spring.profiles.active`, `.default` and `.group.*` from
/// on-profile documents and documents of another cloud platform, which its
/// documentation forbids; here such a document fails when it applies and
/// is ignored when it does not. Of the profile keys ignored in files read
/// after the profiles are decided, `spring.profiles.active` is hidden from
/// the environment when no profile is active, and `spring.profiles.default`
/// when the default profile is `default`: `StandardEnvironment` would read
/// them then (Boot's environment never does). In a `;` group, spaces
/// around an entry are trimmed and empty entries skipped; Boot keeps the
/// spaces in the location and reads an empty entry as the importing
/// file's directory. Each entry of a group is read by its own prefix, so
/// `x.yml;configtree:/run/secrets/` reads the tree; Boot picks the
/// resolver of the whole group from its first entry (reading that tree
/// entry as a plain directory, and failing on
/// `configtree:/run/secrets/;x.yml` as a config tree location not ending
/// in `/`). A relative import in a file found through a wildcard location
/// is relative to that file; Boot resolves it against the wildcard
/// pattern (reading it from every subdirectory, and failing on a path with
/// a directory). A directory location ends with `/`, also on Windows
/// (Boot also takes `\` there).
class ConfigDataEnvironment {
  /// Creates a loader that will fill [environment]; nothing is read until
  /// [processAndApply] or [processAndApplySync].
  ///
  /// [resourceLoader] finds the files (a `DefaultResourceLoader` unless
  /// given; pass one with a `ProtocolResolver` for Flutter assets or files
  /// held in memory). [loaders] read the file formats, picked by
  /// extension. [defaultLocations] replaces [defaultSearchLocations], each
  /// entry a group of `;`-separated locations; `spring.config.location`
  /// still overrides it. [additionalProfiles] are activated on top of the
  /// configured ones.
  ///
  /// ```dart
  /// // Config files held in memory, for a test.
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
    List<String> additionalProfiles = const [],
  }) : resourceLoader = resourceLoader ?? DefaultResourceLoader(),
       loaders = List.unmodifiable(loaders),
       defaultLocations = List.unmodifiable(defaultLocations),
       additionalProfiles = List.unmodifiable(additionalProfiles);

  /// The name of the property source that holds `SpringApplication`'s
  /// default properties: `defaultProperties`. Config files are added just
  /// above it, so they override the defaults, as in Spring Boot's
  /// `DefaultPropertiesPropertySource`.
  static const defaultPropertiesSourceName = 'defaultProperties';

  /// Where config files are looked for unless configured otherwise, as in
  /// Spring Boot: two groups of `;`-separated locations, the packaged one
  /// first and the working directory second (which wins). `classpath:` is
  /// `lib/resources/` (see `ClasspathResources`); `config/*/` searches each
  /// subdirectory of `./config/`.
  static const defaultSearchLocations = [
    'optional:classpath:/;optional:classpath:/config/',
    'optional:file:./;optional:file:./config/;optional:file:./config/*/',
  ];

  /// The property with the base names of the config files,
  /// comma-separated: `spring.config.name` (`application` when unset; a
  /// later name wins).
  static const configNameProperty = 'spring.config.name';

  /// The property whose locations replace [defaultSearchLocations]:
  /// `spring.config.location` (`,` separates groups, `;` joins locations
  /// into one group).
  static const locationProperty = 'spring.config.location';

  /// The property with locations searched after the default ones, and so
  /// winning over them: `spring.config.additional-location`.
  static const additionalLocationProperty = 'spring.config.additional-location';

  /// The property that imports more files from a config document,
  /// relative to that document: `spring.config.import`.
  static const importProperty = 'spring.config.import';

  /// The property that limits a document to profiles:
  /// `spring.config.activate.on-profile`, a profile expression or a comma
  /// list meaning "any of".
  static const onProfileProperty = 'spring.config.activate.on-profile';

  /// The property that limits a document to a [CloudPlatform]:
  /// `spring.config.activate.on-cloud-platform`.
  static const onCloudPlatformProperty =
      'spring.config.activate.on-cloud-platform';

  /// The property with profiles always added to the active ones,
  /// comma-separated: `spring.profiles.include`.
  static const includeProfilesProperty = 'spring.profiles.include';

  /// The prefix of profile group properties:
  /// `spring.profiles.group.prod=db,mq` activates `db` and `mq` whenever
  /// `prod` is active.
  static const profileGroupPrefix = 'spring.profiles.group.';

  /// The property that turns the check of profile names off when `false`:
  /// `spring.profiles.validate` (default `true`).
  static const validateProfilesProperty = 'spring.profiles.validate';

  /// The pre-2.4 document guard `spring.profiles`, rejected as Spring Boot
  /// rejects it; write [onProfileProperty] instead.
  static const legacyProfilesProperty = 'spring.profiles';

  /// The prefix that makes a location optional: `optional:`.
  static const optionalPrefix = 'optional:';

  /// The prefix of a config tree location, `configtree:`, for secrets and
  /// settings mounted as files (Kubernetes volumes, Docker secrets).
  ///
  /// In `configtree:/etc/config/` every file below the directory is a
  /// property named by its path (`a/b` is `a.b`) whose value is the file's
  /// content, one trailing newline removed. Entries whose name starts with
  /// `..` are skipped; `configtree:/etc/*/` reads each subdirectory (also
  /// written `configtree:file:/etc/*/`). As in Boot, the location must end
  /// with `/` (even an `optional:` one), and a required one fails when the
  /// directory is missing or, with a wildcard, has no subdirectory. The
  /// directory is one of the file system that the resource loader's
  /// `file:` locations read: with a protocol resolver that serves `file:`
  /// from elsewhere, there is none.
  static const configTreePrefix = 'configtree:';

  /// The property that decides what a missing required location does:
  /// `spring.config.on-not-found`, `fail` (default) or `ignore`. Any other
  /// value fails with [ConfigDataLoadException].
  static const onNotFoundProperty = 'spring.config.on-not-found';

  /// A file location as Spring Boot 4.1's file hints read it: [location]
  /// without its bracketed parts (`path`, wherever they are:
  /// `conf[x]/app.yml` is `conf/app.yml`), the extension an extension hint
  /// names, without its dot (`x.conf[.yml]`: `yml`), and the encoding an
  /// encoding hint names (`[encoding=iso-8859-1]`: `latin1`); several
  /// hints in any order, the last of a kind winning. A bracketed part of
  /// another form names nothing.
  ///
  /// [location] is one location, as written in `spring.config.import` or
  /// `spring.config.location` (a relative one already joined to the
  /// directory of the file that imports it, as the app joins it before
  /// reading the hints). An `optional:` prefix stays on `path`. Only a
  /// file location has hints: a directory location (ending with `/`) or a
  /// `configtree:` one is returned unchanged, without hints, as its
  /// brackets are part of the path. Throws [ArgumentError] for a `;` group
  /// of locations: split it first, each entry is read on its own.
  ///
  /// The encodings are UTF-8, ISO-8859-1 and US-ASCII, named as Java names
  /// them (canonical names and aliases, such as `utf8`, `latin1` or
  /// `ascii`), without case. Throws [ConfigDataLoadException] for another
  /// charset, as Boot fails on a charset Java does not know. Config data
  /// locations are read this way; use it to read a location as they are,
  /// in a build tool for example.
  ///
  /// ```dart
  /// final hints = ConfigDataEnvironment.fileHints(
  ///   'classpath:dev.conf[.properties][encoding=latin1]',
  /// );
  /// hints.path; // 'classpath:dev.conf'
  /// hints.extension; // 'properties'
  /// hints.encoding; // latin1
  /// ConfigDataEnvironment.fileHints('conf[x]/').path; // 'conf[x]/'
  /// ```
  static ({String path, String? extension, Encoding? encoding}) fileHints(
    String location,
  ) {
    if (location.contains(';')) {
      throw ArgumentError.value(
        location,
        'location',
        "a ';' group of locations: pass each entry on its own",
      );
    }
    final value = location.startsWith(optionalPrefix)
        ? location.substring(optionalPrefix.length)
        : location;
    if (value.endsWith('/') || value.startsWith(configTreePrefix)) {
      return (path: location, extension: null, encoding: null);
    }
    return _FileHint.read(location, location);
  }

  // Properties that may only appear in non-profile documents.
  static const List<String> _profileProperties = [
    StandardEnvironment.activeProfilesPropertyName,
    StandardEnvironment.defaultProfilesPropertyName,
    includeProfilesProperty,
  ];

  /// The environment the config files are read into and whose profiles
  /// are set.
  final ConfigurableEnvironment environment;

  /// Finds the resource behind each location.
  final ResourceLoader resourceLoader;

  /// The file format readers; for each extension the first that handles
  /// it is used.
  final List<PropertySourceLoader> loaders;

  /// The location groups searched when `spring.config.location` is not
  /// set; each entry is a group of `;`-separated locations.
  final List<String> defaultLocations;

  /// Profiles activated on top of the configured ones, as Spring Boot's
  /// `SpringApplication.setAdditionalProfiles` does. They come first, so
  /// their files lose to those of the other profiles.
  final List<String> additionalProfiles;

  /// Reads the config files into [environment] and sets its active and
  /// default profiles. Call it once, before the application context is
  /// created.
  ///
  /// Resources that can only be read asynchronously, such as Flutter
  /// assets and `http:` imports, are awaited; use this form whenever such
  /// resources may be involved. Throws the config data exceptions listed
  /// on the class.
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
        // A URL is asked with a HEAD request first, so a 404 is a missing
        // resource (skipped when optional or a profile variant), like
        // Boot's UrlResource.exists().
        final exists = resource is UrlResource
            ? await resource.existsAsync()
            : resource.isReadable;
        try {
          cache[needed.key] = exists
              ? await resource.readAsString(encoding: needed.encoding)
              : null;
        } on FormatException catch (error) {
          throw _Run._notDecodable(
            needed.location,
            needed.loader,
            needed.encoding,
            error,
          );
        }
      }
    }
  }

  /// Does what [processAndApply] does, without waiting, for a synchronous
  /// start (`SpringApplication.run` uses it). Every resource must be
  /// readable synchronously: files and the generated classpath are.
  ///
  /// Throws [ConfigDataLoadException] for a resource that can only be read
  /// asynchronously.
  ///
  /// ```dart
  /// ConfigDataEnvironment(environment).processAndApplySync();
  /// ```
  void processAndApplySync() =>
      _apply(_Run(this, <String, String?>{}, allowAsync: false).process());

  // Config sources go below everything already present (command line, OS
  // environment) but above `defaultProperties`, keeping their relative
  // order; then relaxed names are attached, as SpringApplication does in
  // Spring Boot.
  void _apply(_Result result) {
    final sources = environment.propertySources;
    final belowDefaults = sources.containsSource(defaultPropertiesSourceName);
    for (final source in result.sources) {
      if (belowDefaults) {
        sources.addBefore(defaultPropertiesSourceName, source);
      } else {
        sources.addLast(source);
      }
    }
    if (result.activeProfiles.isNotEmpty) {
      environment.setActiveProfiles(result.activeProfiles);
    }
    environment.setDefaultProfiles(result.defaultProfiles);
    ConfigurationPropertySources.attach(environment);
  }
}

// Outcome of one processing pass.
final class _Result {
  _Result(this.sources, this.activeProfiles, this.defaultProfiles);

  // Highest precedence first.
  final List<AbstractPropertySource<Object>> sources;
  final List<String> activeProfiles;
  final List<String> defaultProfiles;
}

// Signals that [resource] (the file at [location], read by [loader] and
// decoded with [encoding]) must be read asynchronously, into the cache
// under [key], before retrying.
final class _NeedsContent implements Exception {
  _NeedsContent(
    this.resource,
    this.location,
    this.loader,
    this.encoding,
    this.key,
  );

  final Resource resource;
  final String location;
  final PropertySourceLoader loader;
  final Encoding encoding;
  final String key;
}

// A location value of `spring.config.location`,
// `spring.config.additional-location` or `spring.config.import` (one of
// its comma-separated values, in a file or not): a group of locations
// joined with `;`, which is one location to Boot (its ConfigDataLocation,
// resolved through ConfigDataLocation.split). The group is required
// unless its first entry is `optional:`; it is found when any entry finds
// something, and a missing required entry fails at once (unless the group
// is optional). Errors name the group as written ([key]).
final class _Group {
  _Group._(this.locations, this.key, {required this.optional});

  // The group of [value]; `null` when it has no entry. Entries are
  // trimmed and empty ones dropped (Boot keeps the spaces, so
  // `a.yaml; b.yaml` names ` b.yaml` there).
  static _Group? of(String value) {
    final locations = _Run._split(value, ';');
    if (locations.isEmpty) {
      return null;
    }
    return _Group._(
      locations,
      _Run._withoutOptional(value.trim()),
      optional: locations.first.startsWith(
        ConfigDataEnvironment.optionalPrefix,
      ),
    );
  }

  // Its entries, each with its own `optional:` prefix, if any.
  final List<String> locations;

  // The group as written, without the `optional:` prefix of its first
  // entry: what Boot's ConfigDataLocation holds and its errors name.
  final String key;

  final bool optional;
}

// One loaded document (a file, or one `#---` section of it).
final class _Document {
  _Document(
    this.source,
    this.location, {
    required this.profileSpecific,
    required this.readAfterProfiles,
  }) : onProfile = _guard(
         _Run._sourceValue(source, ConfigDataEnvironment.onProfileProperty),
       ),
       // A scalar only, as Boot binds it (a CloudPlatform): a list form
       // (`on-cloud-platform[0]`) is no guard there.
       onCloudPlatform = _guard(
         _Run._sourceValue(
           source,
           ConfigDataEnvironment.onCloudPlatformProperty,
           scalar: true,
         ),
       ) {
    // Boot binds the imports of every document it loads, applied or not,
    // so a malformed list (`spring.config.import[x]`) fails the start
    // wherever it is.
    _Run._sourceValue(source, ConfigDataEnvironment.importProperty);
  }

  // An empty on-profile is no guard at all, as in Boot (an empty array).
  static String? _guard(String? text) =>
      text == null || text.trim().isEmpty ? null : text;

  final AbstractPropertySource<Object> source;
  final String location;
  // Whether it comes from a `-{profile}` variant searched by name (Boot's
  // isFromProfileSpecificImport); a file such a variant imports is not.
  final bool profileSpecific;
  // Whether it was read once the profiles were decided, so its profile
  // keys cannot change them.
  final bool readAfterProfiles;
  // The raw on-profile guard; placeholders are resolved on activation.
  final String? onProfile;
  // The raw on-cloud-platform guard.
  final String? onCloudPlatform;
  // Whether its guards matched; inactive documents are dropped.
  bool active = false;
  // The number of activations when its guards last did not match: they
  // are not evaluated again until another document is activated (their
  // placeholders resolve against the active documents).
  int checkedAt = -1;
}

// A node of Spring Boot's contributor tree (its
// ConfigDataEnvironmentContributor): an initial import (the
// `spring.config.import` locations set outside the config files, or one
// location of `spring.config.additional-location` or
// `spring.config.location`) or a loaded document. The documents a node
// imports are its children, kept per phase as Boot keeps them, highest
// precedence first; they all win over the node itself.
final class _Node {
  _Node.initial(List<_Group> this.imports)
    : document = null,
      profileSpecific = false;

  _Node.of(_Document this.document, {required this.profileSpecific});

  final _Document? document;

  // The locations it imports; a document's are read when first needed.
  List<_Group>? imports;

  // Boot's ConfigData.Option.PROFILE_SPECIFIC: a `-{profile}` variant
  // that has not been moved up yet (see _Run._moveProfileSpecific).
  bool profileSpecific;

  // The children imported before and after the profiles were decided
  // (Boot's ImportPhase); `null` until the node is processed in that
  // phase.
  List<_Node>? before;
  List<_Node>? after;

  // The node's subtree in Boot's order (ContributorIterator), highest
  // precedence first: the subtrees of the children imported after the
  // profiles were decided, then of those imported before, then the node.
  Iterable<_Node> get contributors sync* {
    for (final child in after ?? const <_Node>[]) {
      yield* child.contributors;
    }
    for (final child in before ?? const <_Node>[]) {
      yield* child.contributors;
    }
    yield this;
  }
}

// A resource that Boot's resolver found for a location: [load] reads its
// documents (`null` when nothing is there, none when it was read before),
// marking the location found. [profileSpecific] for a `-{profile}`
// variant searched by name.
final class _Candidate {
  _Candidate(this.load, {required this.profileSpecific});

  final List<_Document>? Function() load;
  final bool profileSpecific;
}

// A single processing pass; re-run after async content arrives.
final class _Run {
  _Run(this.owner, this.cache, {required this.allowAsync});

  final ConfigDataEnvironment owner;
  final Map<String, String?> cache;
  final bool allowAsync;

  // Boot's contributor tree below its root: the initial imports, highest
  // precedence first (see [process]).
  var _initial = const <_Node>[];
  // Resources already loaded (Boot's ConfigDataImporter.loaded), so a file
  // is read once: guards against import cycles, and decides which of the
  // places a file is listed at counts (the first one loaded).
  final _loaded = <String>{};
  // The profiles documents are activated for and `-{profile}` variants
  // searched for (the active ones, else the default ones), once decided.
  List<String>? _accepted;
  // How many documents were activated so far ([_Document.checkedAt]).
  var _activations = 0;
  // Config file base names (`spring.config.name`).
  late final List<String> _names;
  // The cloud platform, deduced once the unguarded documents are active
  // (Boot's ConfigDataActivationContext); on-cloud-platform documents wait
  // for it.
  CloudPlatform? _platform;
  bool _platformKnown = false;
  // Set once the profiles are decided; documents read later cannot change
  // them.
  bool _profilesDecided = false;
  // For Boot's checkMandatoryLocations, run once every phase is done: the
  // locations that loaded something, in any phase, profile variants
  // included. A location is keyed as Boot's ConfigDataLocation: a whole
  // `;` group as written ([_Group.key]), whatever file imports it.
  final _found = <String>{};

  ConfigurableEnvironment get _env => owner.environment;

  // `spring.config.on-not-found=ignore`: missing locations are skipped as
  // if they were `optional:` (Boot's ConfigDataNotFoundAction).
  late final bool _ignoreNotFound;

  bool _readOnNotFound() {
    final value = _bind(
      _env.propertySources,
      ConfigDataEnvironment.onNotFoundProperty,
      _env,
      scalar: true,
    )?.trim().toLowerCase();
    return switch (value) {
      null || 'fail' => false,
      'ignore' => true,
      _ => throw ConfigDataLoadException(
        ConfigDataEnvironment.onNotFoundProperty,
        "invalid value '$value' (use 'fail' or 'ignore')",
      ),
    };
  }

  _Result process() {
    _ignoreNotFound = _readOnNotFound();
    _names =
        _list(
          _bind(
            _env.propertySources,
            ConfigDataEnvironment.configNameProperty,
            _env,
          ),
        ) ??
        const ['application'];
    // Like Boot: `,` separates groups, `;` joins locations into a group.
    List<_Group> groupsOf(String property, List<String> defaults) => [
      for (final value
          in _list(_bind(_env.propertySources, property, _env)) ?? defaults)
        ?_Group.of(value),
    ];
    // Boot's initial imports (ConfigDataEnvironment
    // .getInitialImportContributors), highest precedence first:
    // `spring.config.import` from the environment (command line,
    // `SPRING_CONFIG_IMPORT`) as one node, then each `additional-location`
    // and each `location` as a node of its own, from the last.
    final imports = groupsOf(ConfigDataEnvironment.importProperty, const []);
    final additional = groupsOf(
      ConfigDataEnvironment.additionalLocationProperty,
      const [],
    );
    final locations = groupsOf(
      ConfigDataEnvironment.locationProperty,
      owner.defaultLocations,
    );
    _initial = [
      if (imports.isNotEmpty) _Node.initial(imports),
      for (final group in additional.reversed) _Node.initial([group]),
      for (final group in locations.reversed) _Node.initial([group]),
    ];

    // 1. The plain files and what they import. Documents guarded by
    // on-profile stay inactive until the profiles are known (like Spring
    // Boot), so `!prod` is not applied before we know whether prod is
    // active. The cloud platform is deduced from the environment and the
    // unguarded documents, then the documents guarded by on-cloud-platform
    // alone are activated.
    _processImports(afterProfiles: false);
    _platform = _deducePlatform();
    _platformKnown = true;
    _activations++;
    _processImports(afterProfiles: false);

    // 2. Profiles from the environment and the active documents.
    final (:active, :defaults) = _resolveProfiles();
    _accepted = active.isEmpty ? defaults : active;
    _profilesDecided = true;
    _activations++;

    // 3. The profile files, the documents guarded by on-profile and the
    // profile variants of imports. A location's variants win over its
    // plain files (and their imports); a later location still wins over an
    // earlier one entirely.
    _processImports(afterProfiles: true);

    // Boot's applyToEnvironment: checkForInvalidProperties, then
    // checkMandatoryLocations.
    _checkProfileSpecific();
    _checkMandatoryLocations();

    // The profile keys of documents read after the profiles were decided
    // are ignored, as in Boot, whose environment never reads them again.
    // StandardEnvironment reads `spring.profiles.active` while no profile
    // is set, and `spring.profiles.default` while the default is
    // `default`; in those cases they are hidden.
    final hidden = [
      if (active.isEmpty) StandardEnvironment.activeProfilesPropertyName,
      if (defaults case [StandardEnvironment.reservedDefaultProfileName])
        StandardEnvironment.defaultProfilesPropertyName,
    ];
    return _Result(
      [
        for (final document in _documents)
          if (document.active && document.readAfterProfiles)
            _without(document.source, hidden)
          else if (document.active)
            document.source,
      ],
      active,
      defaults,
    );
  }

  // Boot's InvalidConfigDataPropertyException.throwIfPropertyFound: a
  // `-{profile}` variant may not set the included, active or default
  // profiles (checked in that order), in any of its documents (also one
  // for another profile), under any spelling Boot's relaxed names allow
  // (`spring.profiles.Active`, `spring.profiles.de-fault`). Its groups are
  // just ignored, like the profile keys of every file read after the
  // profiles were decided.
  void _checkProfileSpecific() {
    for (final document in _documents) {
      if (!document.profileSpecific) {
        continue;
      }
      for (final property in const [
        ConfigDataEnvironment.includeProfilesProperty,
        StandardEnvironment.activeProfilesPropertyName,
        StandardEnvironment.defaultProfilesPropertyName,
      ]) {
        for (final name in [property, '$property[0]']) {
          if (_has(document.source, name)) {
            throw InvalidConfigDataPropertyException(
              name,
              document.source.name,
              'not allowed in a profile-specific document',
            );
          }
        }
      }
    }
  }

  // Boot's checkMandatoryLocations: a required location that found
  // nothing fails, the first one in precedence order (of the active
  // documents and initial imports, then their imports in order) named.
  void _checkMandatoryLocations() {
    if (_ignoreNotFound) {
      return;
    }
    for (final node in _nodes) {
      if (node.document case final document? when !document.active) {
        continue;
      }
      for (final group in _importsOf(node)) {
        if (!group.optional && !_found.contains(group.key)) {
          throw ConfigDataLocationNotFoundException(group.key);
        }
      }
    }
  }

  // Whether [source] sets the property [name] under any spelling of
  // Boot's relaxed names (its ConfigurationPropertySource
  // .getConfigurationProperty): `spring.profiles.Active` and
  // `spring.profiles.ACTIVE` are `spring.profiles.active`, while
  // `SPRING_PROFILES_ACTIVE` is so only in environment variables.
  static bool _has(AbstractPropertySource<Object> source, String name) =>
      source.containsProperty(name) ||
      source is EnumerablePropertySource<Object> &&
          ConfigurationPropertySources.propertyNames(
            source,
          ).containsKey(ConfigurationPropertyName.of(name));

  // [source] without the keys that spell one of [names], or [source]
  // itself when it has none.
  static AbstractPropertySource<Object> _without(
    AbstractPropertySource<Object> source,
    List<String> names,
  ) {
    final keys = <String>{
      for (final name in names) ...[
        if (source.containsProperty(name)) name,
        if (source is EnumerablePropertySource<Object>)
          ...?ConfigurationPropertySources.propertyNames(
            source,
          )[ConfigurationPropertyName.of(name)],
      ],
    };
    return keys.isEmpty ? source : _HidingPropertySource(source, keys);
  }

  // Every node of the tree, highest precedence first.
  Iterable<_Node> get _nodes => _initial.expand((node) => node.contributors);

  // All documents, highest precedence first.
  Iterable<_Document> get _documents =>
      _nodes.map((node) => node.document).nonNulls;

  // Boot's ConfigDataEnvironmentContributors.withProcessedImports for one
  // phase: until none is left, the first node in precedence order that is
  // active and has imports not processed in this phase loads them as its
  // children. So the imports of a document are read right after it, deep
  // first, the stronger ones first; documents whose guards match are
  // activated on the way.
  void _processImports({required bool afterProfiles}) {
    while (true) {
      _Node? next;
      for (final node in _nodes.toList()) {
        if (_isActive(node) &&
            next == null &&
            (afterProfiles ? node.after : node.before) == null &&
            _importsOf(node).isNotEmpty) {
          next = node;
        }
      }
      if (next == null) {
        return;
      }
      final children = _resolveAndLoad(next);
      if (afterProfiles) {
        next.after = children;
        _moveProfileSpecific(next);
      } else {
        next.before = children;
      }
    }
  }

  // Whether [node] is active: an initial import always, a document when
  // its guards match. A guard waits until what it tests is known (the
  // cloud platform, the profiles); a document that matches is validated.
  bool _isActive(_Node node) {
    final document = node.document;
    if (document == null || document.active) {
      return true;
    }
    if ((_accepted == null && document.onProfile != null) ||
        (!_platformKnown && document.onCloudPlatform != null) ||
        document.checkedAt == _activations) {
      return false;
    }
    document.checkedAt = _activations;
    if (!_matchesCloudPlatform(document) ||
        !_matchesProfiles(document, _accepted ?? const [])) {
      return false;
    }
    document.active = true;
    _activations++;
    _validate(document);
    return true;
  }

  // Boot's ConfigDataImporter.resolveAndLoad for the imports of [node]:
  // each location is resolved, in order (with its `-{profile}` variants
  // once the profiles are decided), then the resources are read from the
  // last, a resource read before skipped. So of a file listed twice, the
  // later occurrence, which wins, is the one read (with its encoding
  // hint), as in Boot. The children come highest precedence first: the
  // last resource first, the documents of a file from its last.
  List<_Node> _resolveAndLoad(_Node node) {
    final document = node.document;
    final parent = document == null ? null : _parent(document.location);
    final candidates = <_Candidate>[
      for (final group in _importsOf(node)) ...[
        ..._resolve(group, parent, profiles: null),
        if (_accepted case final profiles?)
          ..._resolve(group, parent, profiles: profiles),
      ],
    ];
    final children = <_Node>[];
    for (final candidate in candidates.reversed) {
      final documents = candidate.load() ?? const <_Document>[];
      for (final document in documents.reversed) {
        children.add(
          _Node.of(document, profileSpecific: candidate.profileSpecific),
        );
      }
    }
    return children;
  }

  // Boot's resolution of one location ([group], a `;` group): the
  // references of its entries, without repeats of a resource location (the
  // first counts, as in Boot's LinkedHashSet), each with the resources it
  // finds. Without [profiles] the plain files; with them the `-{profile}`
  // variants, for each profile each entry.
  List<_Candidate> _resolve(
    _Group group,
    String? parent, {
    required List<String>? profiles,
  }) {
    final references = <String, List<_Candidate>>{};
    for (final profile in profiles ?? const <String?>[null]) {
      for (final location in group.locations) {
        for (final (key, candidates) in _references(
          location,
          profile: profile,
          group: group,
          parent: parent,
        )) {
          references.putIfAbsent(key, () => candidates);
        }
      }
    }
    return [for (final candidates in references.values) ...candidates];
  }

  // Boot's ConfigDataEnvironmentContributor.moveProfileSpecific, run when
  // [node] gets the children it imports once the profiles are decided:
  // the `-{profile}` variants that its children imported move up in front
  // of those children, so they win over the node's other imports (with an
  // import `x.properties` in `application.properties`, `x-dev.properties`
  // wins over `application-dev.properties`). A variant moves up once.
  static void _moveProfileSpecific(_Node node) {
    final before = node.before ?? const <_Node>[];
    if (!before.any(
      (child) => [
        ...?child.before,
        ...?child.after,
      ].any((grandchild) => grandchild.profileSpecific),
    )) {
      return;
    }
    final moved = <_Node>[];
    for (final child in before) {
      for (final afterProfiles in const [false, true]) {
        final kept = <_Node>[];
        for (final grandchild
            in (afterProfiles ? child.after : child.before) ??
                const <_Node>[]) {
          if (grandchild.profileSpecific) {
            grandchild.profileSpecific = false;
            moved.add(grandchild);
          } else {
            kept.add(grandchild);
          }
        }
        // Boot's withChildren: setting a child's later children moves its
        // own grandchildren's variants up too.
        if (afterProfiles) {
          child.after = kept;
          _moveProfileSpecific(child);
        } else {
          child.before = kept;
        }
      }
    }
    node.after = [...moved, ...?node.after];
  }

  // Boot's deduceCloudPlatform: `spring.main.cloud-platform` from the
  // environment and the active documents, else the platform active in the
  // environment itself.
  CloudPlatform? _deducePlatform() {
    final enforced = _bind(
      _boundSources(),
      CloudPlatform.propertyName,
      _resolver(),
      scalar: true,
    );
    if (enforced != null) {
      if (CloudPlatform.parse(enforced) case final platform?) {
        return platform;
      }
    }
    return CloudPlatform.getActive(_env);
  }

  // Whether the on-cloud-platform guard of [document] (if any) names the
  // deduced platform (`none` when there is none).
  bool _matchesCloudPlatform(_Document document) {
    final guard = document.onCloudPlatform;
    if (guard == null) {
      return true;
    }
    final value = _resolver(document).resolveRequiredPlaceholders(guard).trim();
    final wanted = CloudPlatform.parse(value);
    if (wanted == null) {
      throw ConfigDataLoadException(
        document.location,
        "invalid '${ConfigDataEnvironment.onCloudPlatformProperty}' value "
        "'$value' (one of "
        "${CloudPlatform.values.map((p) => p.name).join(', ')})",
      );
    }
    return wanted == (_platform ?? CloudPlatform.none);
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

  // An on-profile document read while the profiles are being decided must
  // not change them, as Boot's documentation says (Boot 4.1.2 itself only
  // rejects `spring.profiles.include` there and reads the others). The
  // `-{profile}` variants are checked by [_checkProfileSpecific]; the
  // profile keys of documents read later are ignored.
  void _validate(_Document document) {
    if (document.onProfile == null || document.readAfterProfiles) {
      return;
    }
    final source = document.source;
    final found = [
      for (final property in ConfigDataEnvironment._profileProperties)
        for (final name in [property, '$property[0]']) // `[0]`: a YAML list.
          if (_has(source, name)) name,
      if (source is EnumerablePropertySource<Object>)
        for (final name in ConfigurationPropertySources.propertyNames(
          source,
        ).keys)
          if (_groupsName.isAncestorOf(name)) '$name',
    ];
    if (found.isNotEmpty) {
      throw InvalidConfigDataPropertyException(
        found.first,
        source.name,
        'not allowed in a profile-specific document',
      );
    }
  }

  // The locations [node] imports: an initial import's, or a document's
  // `spring.config.import` values, read the first time they are needed.
  // Each value is a `;` group, as an initial location is (Boot resolves
  // every ConfigDataLocation split); relative locations are resolved
  // against the importing file's directory.
  List<_Group> _importsOf(_Node node) => node.imports ??= () {
    final document = node.document!;
    final value = _sourceValue(
      document.source,
      ConfigDataEnvironment.importProperty,
    );
    // Lenient, like Boot: an unresolvable placeholder stays as is, so an
    // `optional:` import of it is just not found.
    final locations =
        _list(
          value == null ? null : _resolver(document).resolvePlaceholders(value),
        ) ??
        const <String>[];
    return [for (final value in locations) ?_Group.of(value)];
  }();

  // The sources bound for profiles, imports and placeholders, highest
  // precedence first: the environment's own, then the documents active so
  // far (and [including], even while inactive), then `defaultProperties`
  // (below config data, as in Boot).
  List<AbstractPropertySource<Object>> _boundSources([_Document? including]) {
    final environment = _env.propertySources.where(
      (s) => s is! ConfigurationPropertySourcesPropertySource,
    );
    const defaults = ConfigDataEnvironment.defaultPropertiesSourceName;
    return [
      ...environment.where((s) => s.name != defaults),
      for (final d in _documents)
        if (d.active || d == including) d.source,
      ...environment.where((s) => s.name == defaults),
    ];
  }

  // A resolver over the environment and the documents active so far, plus
  // [document] at its own precedence (Boot's
  // ConfigDataEnvironmentContributorPlaceholdersResolver), so the command
  // line beats the document's own values. Names are relaxed, as with
  // Boot's binder.
  PropertyResolver _resolver([_Document? document]) {
    final sources = _boundSources(document);
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

  // Active and default profiles, like Spring Boot's `Profiles`: the
  // additional profiles first, then the included ones (from every
  // source), then the active ones (see [_profiles]), each list with its
  // profile groups expanded. Later profiles win, so `application-{active}`
  // overrides `application-{included}`.
  ({List<String> active, List<String> defaults}) _resolveProfiles() {
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

    final included = <String>[];
    for (final source in _boundSources()) {
      final profiles =
          _list(
            _bind(
              [source],
              ConfigDataEnvironment.includeProfilesProperty,
              resolver,
            ),
          ) ??
          const <String>[];
      check(profiles, ConfigDataEnvironment.includeProfilesProperty);
      included.addAll(profiles);
    }
    final active = _profiles(
      resolver,
      StandardEnvironment.activeProfilesPropertyName,
      _env.activeProfiles,
      const [],
      merge: true,
    );
    check(active, StandardEnvironment.activeProfilesPropertyName);
    final defaults = _profiles(
      resolver,
      StandardEnvironment.defaultProfilesPropertyName,
      _env.defaultProfiles,
      const [StandardEnvironment.reservedDefaultProfileName],
      merge: false,
    );
    check(defaults, StandardEnvironment.defaultProfilesPropertyName);

    // Expand groups depth-first like Boot's Profiles.expandProfiles: a
    // group's members follow it (nested groups too), a profile keeps the
    // first position it is reached at.
    List<String> expand(Iterable<String> profiles) {
      final stack = [...profiles].reversed.toList();
      final result = <String>[];
      final seen = <String>{};
      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (!seen.add(current)) {
          continue;
        }
        result.add(current);
        final group = '${ConfigDataEnvironment.profileGroupPrefix}$current';
        String? value;
        for (final source in _boundSources()) {
          if (source is ConfigurationPropertySourcesPropertySource) {
            continue;
          }
          if (_groupMembers(source, current) case final members?) {
            value = resolver.resolveRequiredPlaceholders(members);
            break;
          }
        }
        final members = _list(value);
        check(members ?? const [], group);
        stack.addAll((members ?? const <String>[]).reversed);
      }
      return result;
    }

    return (
      active: expand([...owner.additionalProfiles, ...included, ...active]),
      defaults: expand(defaults),
    );
  }

  // Boot's `Profiles.getProfiles`: [environmentProfiles] set on the
  // environment programmatically (not just read from [property]) win over
  // the property; the active ones are then [merge]d with the bound value
  // (environment and config files), the default ones are not. Otherwise
  // the bound value applies, or [defaultValue].
  List<String> _profiles(
    PropertyResolver resolver,
    String property,
    List<String> environmentProfiles,
    List<String> defaultValue, {
    required bool merge,
  }) {
    bool same(List<String> a, List<String> b) =>
        a.toSet().length == b.toSet().length && a.toSet().containsAll(b);
    final fromProperty =
        _list(_bind(_env.propertySources, property, _env)) ?? const [];
    final bound = _list(_bind(_boundSources(), property, resolver));
    final programmatic =
        !same(environmentProfiles, defaultValue) &&
        (fromProperty.isEmpty || !same(fromProperty, environmentProfiles));
    if (programmatic) {
      return merge && bound != null
          ? _unique([...environmentProfiles, ...bound])
          : environmentProfiles;
    }
    return bound ?? defaultValue;
  }

  static List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
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

  // Boot's references for one entry of a `;` group, each with the
  // resource location Boot tells them apart by and the resources it finds
  // (read later, see [_resolveAndLoad]). A location ending in `/` is a
  // directory searched for every name and extension; otherwise it is a
  // file, whose profile variant is `name-profile.ext`. A `*/` segment
  // stands for each subdirectory (Boot's wildcard locations). A relative
  // location is resolved against [parent] (the directory of an importing
  // file). [group] is the `;` group the location is an entry of, which
  // Boot treats as one location and names in its errors as written
  // ([_Group.key]).
  //
  // As in Boot, a required file that does not exist fails when it is
  // read, and a required wildcard directory without subdirectories fails
  // at once; whether any other required location was found is decided
  // once every phase is done (see [process]), so a location whose profile
  // variants find a file counts as found. Only the `-{profile}` variants
  // searched by name may always be missing (Boot's
  // StandardConfigDataReference.isSkippable).
  List<(String, List<_Candidate>)> _references(
    String rawLocation, {
    required String? profile,
    required _Group group,
    String? parent,
  }) {
    final optional = rawLocation.startsWith(
      ConfigDataEnvironment.optionalPrefix,
    );
    var location = _env.resolvePlaceholders(_withoutOptional(rawLocation));
    final key = group.key;
    if (parent != null && _isRelative(location)) {
      location = '$parent$location';
    }
    final suffix = profile == null ? '' : '-$profile';
    final variant = profile != null;
    final ignoreMissing = optional || group.optional || _ignoreNotFound;
    // The documents a resource of this location loads, marking it found.
    List<_Document>? found(List<_Document>? documents) {
      if (documents != null) {
        _found.add(key);
      }
      return documents;
    }

    if (location.startsWith(ConfigDataEnvironment.configTreePrefix)) {
      if (variant) {
        return const [];
      }
      return [
        (
          location,
          [
            _Candidate(
              () => found(
                _loadConfigTree(
                  location,
                  optional: ignoreMissing,
                  reportedAs: key,
                ),
              ),
              profileSpecific: false,
            ),
          ],
        ),
      ];
    }
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
      final wildcard = location.contains('*');
      final directories = wildcard
          ? _subdirectories(location, location)
          : [location];
      // Boot's resolver fails a required wildcard without subdirectories
      // at once.
      if (wildcard && directories.isEmpty && !ignoreMissing && !variant) {
        throw ConfigDataLocationNotFoundException(
          rawLocation,
          reason: 'contains no subdirectories',
        );
      }
      // An existing directory is found even when empty (Boot's empty
      // directory resources); a classpath one never counts.
      if (!_found.contains(key) &&
          (wildcard ? directories.isNotEmpty : _isDirectory(location))) {
        _found.add(key);
      }
      return [
        for (final name in _names)
          for (final extension in extensions)
            (
              '$location$name$suffix.$extension',
              [
                for (final directory in directories)
                  _Candidate(
                    () => found(
                      _loadFile(
                        '$directory$name$suffix.$extension',
                        optional: true,
                        profileSpecific: variant,
                      ),
                    ),
                    profileSpecific: variant,
                  ),
              ],
            ),
      ];
    }
    // Spring Boot 4.1's file hints: an extension hint names the format of
    // a file without (or with another) extension, `file:./conf[.yml]`, and
    // `[encoding=iso-8859-1]` the charset of a file; several, in any order
    // (`x.conf[.properties][encoding=utf-8]`). Every bracketed part is
    // taken out of the path (Boot's FileHint), and a charset the hint names
    // is checked whatever the loader and even when optional, as Boot's
    // Charset.forName does.
    final hints = _FileHint.read(location, rawLocation);
    var file = hints.path;
    final hint = hints.extension;
    final encoding = hints.encoding;
    final dot = file.lastIndexOf('.');
    final written =
        hint ?? (dot > file.lastIndexOf('/') ? file.substring(dot + 1) : '');
    // As in Boot (StandardConfigDataLocationResolver, endsWithIgnoreCase),
    // an extension or hint is matched without case, and the loader's own
    // spelling names the file: `x.YAML` reads `x.yaml`, `x.conf[.YAML]`
    // reads `x.conf` as YAML.
    final extension = _loaderExtension(written);
    if (extension == null) {
      if (optional) {
        return const [];
      }
      // Boot's PropertiesPropertySourceLoader also reads `.xml`
      // (java.util.Properties.loadFromXML); not this one.
      if (written.toLowerCase() == 'xml') {
        throw ConfigDataLoadException(
          rawLocation,
          'XML properties files are not supported (Spring Boot reads them '
          'with java.util.Properties.loadFromXML): write it as .properties '
          'or YAML',
        );
      }
      // Boot's StandardConfigDataLocationResolver message.
      throw ConfigDataLoadException(
        rawLocation,
        'File extension is not known to any PropertySourceLoader. If the '
        "location is meant to reference a directory, it must end in '/'",
      );
    }
    if (hint == null && extension != written) {
      file = '${file.substring(0, dot + 1)}$extension';
    }
    if (variant) {
      file = hint != null
          ? '$file$suffix'
          : '${file.substring(0, dot)}$suffix${file.substring(dot)}';
    }
    if (file.contains('*')) {
      final slash = file.lastIndexOf('/');
      return [
        (
          file,
          [
            for (final directory in _subdirectories(
              file.substring(0, slash + 1),
              location,
            ))
              _Candidate(
                () => found(
                  _loadFile(
                    '$directory${file.substring(slash + 1)}',
                    optional: true,
                    profileSpecific: variant,
                    extension: hint == null ? null : extension,
                    encoding: encoding,
                  ),
                ),
                profileSpecific: variant,
              ),
          ],
        ),
      ];
    }
    return [
      (
        file,
        [
          _Candidate(
            () => found(
              _loadFile(
                file,
                optional: ignoreMissing || variant,
                profileSpecific: variant,
                extension: hint == null ? null : extension,
                encoding: encoding,
                reportedAs: key,
              ),
            ),
            profileSpecific: variant,
          ),
        ],
      ),
    ];
  }

  // The extension of a loader that matches [extension] without case, in
  // the loader's spelling; `null` when no loader reads it. The first loader
  // wins, as in Boot.
  String? _loaderExtension(String extension) {
    final lower = extension.toLowerCase();
    for (final loader in owner.loaders) {
      for (final known in loader.fileExtensions) {
        if (known.toLowerCase() == lower) {
          return known;
        }
      }
    }
    return null;
  }

  static String _withoutOptional(String location) =>
      location.startsWith(ConfigDataEnvironment.optionalPrefix)
      ? location.substring(ConfigDataEnvironment.optionalPrefix.length)
      : location;

  // A `configtree:` location: one source per directory (each subdirectory
  // for `dir/*/`), like Boot's ConfigTreeConfigDataLocationResolver and
  // ConfigTreeConfigDataLoader; `null` when it finds no directory. A
  // missing one is reported as [reportedAs], the location as written.
  List<_Document>? _loadConfigTree(
    String location, {
    required bool optional,
    required String reportedAs,
  }) {
    final path = location.substring(
      ConfigDataEnvironment.configTreePrefix.length,
    );
    // Boot's resolver asserts it, `optional:` or not.
    if (!path.endsWith('/')) {
      throw ConfigDataLoadException(
        location,
        "Config tree location '$path' must end with '/'",
      );
    }
    final wildcard = path.contains('*');
    final directories = wildcard
        ? [
            // A `file:` base lists `file:` subdirectories
            // (`configtree:file:/etc/*/`); the tree is their path.
            for (final directory in _subdirectories(path, location))
              if (directory.startsWith(ResourceLoader.filePrefix))
                '${FileSystemResource.fromFileUrl(directory).path}/'
              else
                directory,
          ]
        : [path];
    // A required wildcard without subdirectories loads nothing, and fails
    // when every phase is done (Boot's checkMandatoryLocations).
    var found = false;
    final documents = <_Document>[];
    for (final directory in directories) {
      if (!_isFileSystemDirectory(directory)) {
        if (optional || wildcard) {
          continue;
        }
        throw ConfigDataResourceNotFoundException(
          reportedAs,
          'config tree [$directory]',
        );
      }
      found = true;
      if (!_loaded.add(
        '${ConfigDataEnvironment.configTreePrefix}'
        '${_normalized(directory)}',
      )) {
        continue;
      }
      final root = directory.endsWith('/') ? directory : '$directory/';
      final absolute = FileAccess.absolute(root).replaceAll(r'\', '/');
      final properties = <String, Object>{};
      for (final file in FileAccess.listFilesRecursively(directory)) {
        final full = FileAccess.absolute(file).replaceAll(r'\', '/');
        final relative = full.startsWith(absolute)
            ? full.substring(absolute.length)
            : file.substring(root.length);
        final segments = relative.split('/');
        if (segments.any((segment) => segment.startsWith('..'))) {
          continue;
        }
        var value = utf8.decode(
          FileAccess.readBytesSync(file),
          allowMalformed: true,
        );
        // Option.AUTO_TRIM_TRAILING_NEW_LINE: one trailing newline.
        if (value.endsWith('\r\n')) {
          value = value.substring(0, value.length - 2);
        } else if (value.endsWith('\n')) {
          value = value.substring(0, value.length - 1);
        }
        properties[segments.join('.')] = value;
      }
      documents.add(
        _Document(
          MapPropertySource("Config tree '$directory'", properties),
          location,
          profileSpecific: false,
          readAfterProfiles: _profilesDecided,
        ),
      );
    }
    return found ? documents : null;
  }

  // Whether [path] is an existing directory of the file system that the
  // resource loader's `file:` locations read: never when a protocol
  // resolver serves `file:` from elsewhere (the Flutter web dev config
  // builder reads the config as a browser does, without a file system).
  bool _isFileSystemDirectory(String path) =>
      owner.resourceLoader.getResource('${ResourceLoader.filePrefix}$path')
          is FileSystemResource &&
      FileAccess.isDirectory(path);

  // Whether [location] is an existing directory: a file system one, or a
  // resource that reports itself as existing. Never the classpath, like
  // Boot, whose classpath directories cannot be checked (even one that
  // `lib/resources/` on disk holds).
  bool _isDirectory(String location) {
    if (location.startsWith(ClasspathResources.prefix)) {
      return false;
    }
    final resource = owner.resourceLoader.getResource(
      _isUrl(location) ? location : '${ResourceLoader.filePrefix}$location',
    );
    if (resource is FileSystemResource) {
      return FileAccess.isDirectory(resource.path);
    }
    return resource.exists();
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
      // A base that does not exist has no subdirectories, as in Boot's
      // LocationResourceLoader; one that exists elsewhere cannot be
      // listed.
      if (!resource.exists()) {
        return const [];
      }
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

  // The documents of the file at [location]; `null` if it does not exist
  // (and is optional), an empty list if it was already loaded. A missing
  // required one is reported as [reportedAs], the location as written
  // (Boot's ConfigDataResourceNotFoundException.withLocation: the whole
  // `;` group, relative, its extension hint kept).
  List<_Document>? _loadFile(
    String location, {
    required bool optional,
    required bool profileSpecific,
    String? extension,
    Encoding? encoding,
    String? reportedAs,
  }) {
    extension ??= location.contains('.')
        ? location.substring(location.lastIndexOf('.') + 1)
        : '';
    final loader = owner.loaders
        .where((l) => l.fileExtensions.contains(extension))
        .firstOrNull;
    if (loader == null) {
      if (optional) {
        return null;
      }
      throw ConfigDataLoadException(
        location,
        "no PropertySourceLoader for extension '$extension'",
      );
    }
    // Deduplicated on the normalized location, so `./application.properties`
    // or `config/../config/a.properties` cannot import themselves forever.
    // Checked before reading, as Boot's ConfigDataImporter skips a loaded
    // resource: a file listed again elsewhere is not decoded with that
    // place's encoding hint (or none).
    final normalized = _normalized(location);
    if (_loaded.contains(normalized)) {
      return const []; // Already loaded (import cycle or duplicate).
    }
    // A location without a prefix is a file, like Boot's
    // LocationResourceLoader (unlike a plain path in DefaultResourceLoader).
    final resource = owner.resourceLoader.getResource(
      _isUrl(location) ? location : '${ResourceLoader.filePrefix}$location',
    );
    final content = _read(
      resource,
      location,
      loader,
      encoding == null ? loader.encoding : loader.encodingFor(encoding),
    );
    if (content == null) {
      if (optional) {
        _log.trace(
          () =>
              'Skipping missing resource '
              '${LogFormatUtils.formatValue(location)}',
        );
        return null;
      }
      throw ConfigDataResourceNotFoundException(
        reportedAs ?? location,
        resource.description,
      );
    }
    _loaded.add(normalized);
    _log.debug(
      () => 'Loaded config file ${LogFormatUtils.formatValue(location)}',
    );
    final List<AbstractPropertySource<Object>> sources;
    try {
      sources = loader.load("Config resource '$location'", content);
    } on FormatException catch (error) {
      // Like Boot's "Failed to load property source from location".
      throw ConfigDataLoadException(location, error.toString());
    } on StackOverflowError {
      // Not from the built-in loaders (YAML nesting is bounded, `\` lines
      // are read in a loop); a loader of another format may overflow.
      throw ConfigDataLoadException(
        location,
        'reading it overflowed the stack (its content is nested too '
        'deeply)',
      );
    }
    // Boot rejects the pre-2.4 guard wherever it appears, under any relaxed
    // spelling (`spring.Profiles`).
    for (final source in sources) {
      for (final legacy in [
        ConfigDataEnvironment.legacyProfilesProperty,
        '${ConfigDataEnvironment.legacyProfilesProperty}[0]',
      ]) {
        if (_has(source, legacy)) {
          throw InvalidConfigDataPropertyException(
            legacy,
            source.name,
            'it should be replaced with '
            "'${ConfigDataEnvironment.onProfileProperty}'",
          );
        }
      }
    }
    return [
      for (final source in sources)
        _Document(
          source,
          location,
          profileSpecific: profileSpecific,
          readAfterProfiles: _profilesDecided,
        ),
    ];
  }

  // Content of [resource] decoded with [encoding] from the cache or a
  // synchronous read; `null` if it does not exist (or is a directory).
  // Cached by description (and encoding) so a re-run after an async read
  // does not touch the resource again.
  String? _read(
    Resource resource,
    String location,
    PropertySourceLoader loader,
    Encoding encoding,
  ) {
    final key = '${encoding.name} ${resource.description}';
    if (cache.containsKey(key)) {
      return cache[key];
    }
    if (!resource.isReadable) {
      return cache[key] = null;
    }
    if (resource.supportsSyncRead) {
      try {
        return cache[key] = resource.readAsStringSync(encoding: encoding);
      } on FormatException catch (error) {
        throw _notDecodable(location, loader, encoding, error);
      }
    }
    if (allowAsync) {
      throw _NeedsContent(resource, location, loader, encoding, key);
    }
    throw ConfigDataLoadException(
      location,
      'the resource can only be read asynchronously; use processAndApply()',
    );
  }

  // A file at [location] whose bytes are not text in [encoding], the one
  // [loader] decodes it with (a `.properties` file saved as ISO-8859-1,
  // which Boot reads, while the loader decodes UTF-8): named, with the
  // encoding, instead of a bare FormatException.
  static ConfigDataLoadException _notDecodable(
    String location,
    PropertySourceLoader loader,
    Encoding encoding,
    FormatException error,
  ) {
    final name = encoding.name.toUpperCase();
    final advice = loader is PropertiesPropertySourceLoader && name == 'UTF-8'
        ? ': save it as UTF-8, name its charset in the location '
              '(`x.properties[encoding=iso-8859-1]`), or read .properties '
              'files in ISO-8859-1 (as Spring Boot does) with '
              'PropertiesPropertySourceLoader(encoding: latin1)'
        : '';
    return ConfigDataLoadException(
      location,
      'the file is not valid $name ($error); it is read as $name$advice',
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

  // Boot's binder for a value or a list: in each of [sources] (highest
  // precedence first, names relaxed), [key] or its indexed items; the
  // first source that has any wins, so lists are not merged across
  // sources (`--spring.profiles.active[0]=a` replaces a file's whole
  // list). Placeholders are resolved with [resolver]. A [scalar] (an enum
  // or a string in Boot) is the key's own value only.
  static String? _bind(
    Iterable<AbstractPropertySource<Object>> sources,
    String key,
    PropertyResolver resolver, {
    bool scalar = false,
  }) {
    for (final source in sources) {
      if (source is ConfigurationPropertySourcesPropertySource) {
        continue;
      }
      if (_sourceValue(source, key, scalar: scalar) case final value?) {
        return resolver.resolveRequiredPlaceholders(value);
      }
    }
    return null;
  }

  // [key] in [source], with relaxed names: its value, else (unless a
  // [scalar] is wanted) its list items joined with commas
  // (`SPRING_PROFILES_INCLUDE_0_` is `spring.profiles.include[0]`). As
  // with Boot's list binding (IndexedElementsBinder), a source without
  // the value may hold no other `[...]` element right below the key than
  // the items `[0]`, `[1]`... read: `key[x]`, `key[1]` without `key[0]`,
  // `key[0].a` without `key[0]` fail ([InvalidConfigDataPropertyException],
  // Boot's "were left unbound").
  static String? _sourceValue(
    AbstractPropertySource<Object> source,
    String key, {
    bool scalar = false,
  }) {
    Object? get(String name) {
      final relaxed = ConfigurationPropertyName.ofIfValid(name);
      return relaxed == null
          ? source.getProperty(name)
          : ConfigurationPropertySources.getProperty(source, relaxed);
    }

    if (scalar) {
      return get(key)?.toString();
    }
    final value = _value(get, key);
    if (source is EnumerablePropertySource<Object> && get(key) == null) {
      _assertNoUnboundItems(source, key);
    }
    return value;
  }

  // Boot's IndexedElementsBinder.assertNoUnboundChildren for the list
  // [key] in [source]: every bracketed element right below it is one of
  // the items `[0]`, `[1]`... that have a value, without a gap.
  static void _assertNoUnboundItems(
    EnumerablePropertySource<Object> source,
    String key,
  ) {
    final root = ConfigurationPropertyName.of(key);
    final depth = root.numberOfElements;
    final names = ConfigurationPropertySources.propertyNames(source).keys;
    final indexes = <String>{
      for (final name in names)
        if (root.isAncestorOf(name) && name.isIndexed(depth))
          name.getElement(depth),
    };
    for (var i = 0; indexes.isNotEmpty; i++) {
      final item = root.append('[$i]');
      if (ConfigurationPropertySources.getProperty(source, item) == null) {
        break;
      }
      indexes.remove('$i');
    }
    if (indexes.isEmpty) {
      return;
    }
    final left = [
      for (final name in names)
        if (root.isAncestorOf(name) &&
            name.isIndexed(depth) &&
            indexes.contains(name.getElement(depth)))
          '$name',
    ]..sort();
    throw InvalidConfigDataPropertyException(
      left.first,
      source.name,
      'the elements [${left.join(', ')}] were left unbound (the items of '
      "'$key' are [0], [1]... without a gap)",
    );
  }

  static final _groupsName = ConfigurationPropertyName.of(
    ConfigDataEnvironment.profileGroupPrefix.substring(
      0,
      ConfigDataEnvironment.profileGroupPrefix.length - 1,
    ),
  );

  // The members of the profile group [profile] in [source] as text (a
  // list's items joined with commas); `null` when it does not define the
  // group. Boot binds `spring.profiles.group` to a map keyed by the group
  // names as written (Profiles' MultiValueMap), so the prefix matches under
  // any relaxed spelling (`spring.Profiles.GROUP.prod`) and the name only
  // exactly: `group.Prod`, `group.my-prod` and `group.my_prod` are no
  // groups of `prod`, `myprod` and `my-prod`. An environment variable's
  // names are lower case (`SPRING_PROFILES_GROUP_PROD` is `prod`). The
  // value is then looked up relaxed, as Boot's binder does: with two
  // spellings of one name in a source (`group.prod` and `group.Prod`), both
  // groups get the first one's members.
  static String? _groupMembers(
    AbstractPropertySource<Object> source,
    String profile,
  ) {
    if (source is! EnumerablePropertySource<Object>) {
      return _value(
        source.getProperty,
        '${ConfigDataEnvironment.profileGroupPrefix}$profile',
      );
    }
    Object? scalar;
    final items = <int, Object>{};
    for (final MapEntry(key: name, value: keys)
        in ConfigurationPropertySources.propertyNames(source).entries) {
      if (!_groupsName.isAncestorOf(name)) {
        continue;
      }
      for (final key in keys) {
        // The key's own spelling: names that differ only in case, `-` or
        // `_` share one entry.
        var written = ConfigurationPropertyName.adapt(key, '.');
        if (!_groupsName.isAncestorOf(written)) {
          written = name; // an environment variable (`_`-separated)
        }
        final elements = written.numberOfElements;
        final item = elements > 4 && written.isNumericIndex(elements - 1);
        final end = item ? elements - 1 : elements;
        final group = [
          for (var i = 3; i < end; i++) written.getElement(i),
        ].join('.');
        if (group != profile) {
          continue;
        }
        final value = keys.map(source.getProperty).nonNulls.firstOrNull;
        if (value == null) {
          continue;
        }
        if (item) {
          if (int.tryParse(written.getElement(end)) case final index?) {
            items.putIfAbsent(index, () => value);
          }
        } else {
          scalar ??= value;
        }
      }
    }
    if (scalar != null) {
      return scalar.toString();
    }
    final list = <String>[];
    for (Object? item; (item = items[list.length]) != null;) {
      list.add(item.toString());
    }
    return list.isEmpty ? null : list.join(',');
  }

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
      RegExp('^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(location);

  // Directory part of [location] (with trailing `/`), or just its prefix
  // (`file:`) when there is no slash.
  // [location] with `.` and `dir/..` path segments removed (the scheme
  // prefix such as `file:` is kept).
  static String _normalized(String location) {
    final match = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:').firstMatch(location);
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

// A document's source as the environment sees it, without some of its
// keys (the profile keys that config data ignored).
final class _HidingPropertySource extends EnumerablePropertySource<Object> {
  _HidingPropertySource(this._source, this._hidden)
    : super(_source.name, _source.source);

  final AbstractPropertySource<Object> _source;
  final Set<String> _hidden;

  @override
  Object? getProperty(String name) =>
      _hidden.contains(name) ? null : _source.getProperty(name);

  @override
  bool containsProperty(String name) =>
      !_hidden.contains(name) && _source.containsProperty(name);

  @override
  List<String> get propertyNames => [
    if (_source case EnumerablePropertySource<Object>(:final propertyNames))
      for (final name in propertyNames)
        if (!_hidden.contains(name)) name,
  ];
}

// Spring Boot 4.1's FileHint: the bracketed parts of a file location.
// Each `[...]` holds an extension (`[.yml]`, with its dot; other text
// without `=` counts for nothing) or an attribute (`[encoding=utf-8]`,
// name and value trimmed, the name with case; only `encoding` is read),
// a later one winning. The brackets are counted as Boot counts them: a
// `[` inside one is part of its text, a `]` without a `[` is dropped.
final class _FileHint {
  const _FileHint._(this.extension, this.encoding);

  static const _none = _FileHint._(null, null);

  // The extension of an extension hint, with its dot (`.yml`).
  final String? extension;

  // The charset an encoding hint names, as written.
  final String? encoding;

  static bool _hasBrackets(String value) =>
      value.contains('[') && value.contains(']');

  // [location] read for ConfigDataEnvironment.fileHints; an unknown
  // charset is reported for [reportedAs], the location as written.
  static ({String path, String? extension, Encoding? encoding}) read(
    String location,
    String reportedAs,
  ) {
    final hint = from(location);
    return (
      path: removeFrom(location),
      extension: hint.extension?.substring(1),
      encoding: switch (hint.encoding) {
        final name? => _charset(name, reportedAs),
        null => null,
      },
    );
  }

  // The charsets an encoding hint may name: those Dart decodes, by their
  // Java names and aliases (Charset.forName, without case).
  static final Map<String, Encoding> _charsets = {
    for (final name in ['utf-8', 'utf8', 'unicode-1-1-utf-8']) name: utf8,
    for (final name in [
      'iso-8859-1',
      'iso8859-1',
      'iso8859_1',
      'iso_8859-1',
      'iso_8859_1',
      'iso_8859-1:1987',
      '8859_1',
      'iso-ir-100',
      'latin1',
      'l1',
      'ibm819',
      'ibm-819',
      'cp819',
      '819',
      'csisolatin1',
    ])
      name: latin1,
    for (final name in [
      'us-ascii',
      'ascii',
      'ascii7',
      'us',
      'iso646-us',
      'iso_646.irv:1991',
      'iso_646.irv:1983',
      'ansi_x3.4-1968',
      'ansi_x3.4-1986',
      'iso-ir-6',
      'ibm367',
      'cp367',
      '646',
      'csascii',
    ])
      name: ascii,
  };

  // Java's rule for a charset name (Charset.checkName).
  static final _legalCharsetName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9+\-:_.]*$');

  // The encoding a hint names (`[encoding=latin1]`); a name Java would
  // refuse, or a charset Dart cannot decode, fails for [location], as an
  // unknown charset fails Boot's resolution.
  static Encoding _charset(String name, String location) {
    if (!_legalCharsetName.hasMatch(name)) {
      throw ConfigDataLoadException(
        location,
        "'$name' is not a charset name (the location's encoding hint)",
      );
    }
    if (_charsets[name.toLowerCase()] case final encoding?) {
      return encoding;
    }
    throw ConfigDataLoadException(
      location,
      "unsupported charset '$name' in the location's encoding hint: only "
      'UTF-8, ISO-8859-1 and US-ASCII can be read (by their Java names or '
      'aliases, such as utf8, latin1 or ascii; case does not matter)',
    );
  }

  static _FileHint from(String value) {
    if (!_hasBrackets(value)) {
      return _none;
    }
    final attributes = <String, String>{};
    for (final entry in _betweenBrackets(value)) {
      final cleaned = entry.trim();
      if (cleaned.isEmpty) {
        continue;
      }
      final equals = cleaned.indexOf('=');
      if (equals == -1) {
        attributes['extension'] = cleaned;
      } else {
        attributes[cleaned.substring(0, equals).trim()] = cleaned
            .substring(equals + 1)
            .trim();
      }
    }
    final extension = attributes['extension'];
    return _FileHint._(
      extension != null && extension.startsWith('.') ? extension : null,
      attributes['encoding'],
    );
  }

  static List<String> _betweenBrackets(String value) {
    final collected = <String>[];
    final buffer = StringBuffer();
    var brackets = 0;
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == '[') {
        if (brackets > 0) {
          buffer.write(c);
        }
        brackets++;
      } else if (c == ']') {
        brackets--;
        if (brackets > 0) {
          buffer.write(c);
        } else if (brackets == 0 && buffer.isNotEmpty) {
          collected.add(buffer.toString());
          buffer.clear();
        }
      } else if (brackets > 0) {
        buffer.write(c);
      }
    }
    return collected;
  }

  // [value] without its bracketed parts, wherever they are
  // (`conf[x]/app.yml[encoding=utf-8]` is `conf/app.yml`).
  static String removeFrom(String value) {
    if (!_hasBrackets(value)) {
      return value;
    }
    final result = StringBuffer();
    var brackets = 0;
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == '[') {
        brackets++;
      } else if (c == ']') {
        brackets--;
      } else if (brackets <= 0) {
        result.write(c);
      }
    }
    return result.toString();
  }
}

const _log = SpringLog('spring_core_dart.context.config');
