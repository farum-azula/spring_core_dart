import 'dart:io';

import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/index/confined_files.dart';
import 'package:dart_spring_language_server/src/index/message_index.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/properties/property_values.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/test_properties.dart';

/// A property key matched the relaxed way the framework binds names:
/// `my-key`, `myKey`, `my_key` and `MY_KEY` are one key, and an
/// environment variable (from a test's `@TestEnvironment`) matches the way
/// the framework maps property names to variables (`SHOP_MAX_BASKET_SIZE`
/// for `shop.max-basket-size`).
final class PropertyName {
  /// The name [key].
  PropertyName(this.key)
    : _canonical = canonicalName(key),
      _variables = _environmentNames(key);

  /// The key as written.
  final String key;

  final String _canonical;
  final Set<String> _variables;

  /// Whether [entry] defines this property.
  bool matches(PropertyEntry entry) => entry.environment
      ? _variables.contains(entry.key)
      : entry.key == key || canonicalName(entry.key) == _canonical;

  // The environment variables that give the property [key], as the
  // framework's SystemEnvironmentPropertySource looks them up:
  // `shop.max-basket-size` → `SHOP_MAX_BASKET_SIZE`, `SHOP_MAXBASKETSIZE`,
  // `shop_max_basket_size`, ...
  static Set<String> _environmentNames(String key) {
    final variants = [
      key,
      key.replaceAll('.', '_'),
      key.replaceAll('-', '_'),
      key.replaceAll('.', '_').replaceAll('-', '_'),
    ];
    return {
      ...variants,
      ...variants.map((v) => v.toUpperCase()),
      key.replaceAll('-', '').replaceAll('.', '_').toUpperCase(),
    };
  }
}

/// The properties the config files of the workspace define (message
/// bundles left out), and where a value read in a file can come from.
///
/// A value read in a file comes from the config files of that file's
/// package, and in a test also from the properties the test sets for its
/// own context ([testProperties]): definitions, hovers, checks and the
/// values shown inline all look a key up that way. A workspace holds many
/// packages, and another package's config is not read by this one.
final class PropertyIndex {
  /// The properties of [files]; [messages] tells which files are message
  /// bundles, [metadata] the profiles the packages declare.
  PropertyIndex(this.files, this.packages, this.messages, this.metadata);

  /// The files of the workspace.
  final ProjectFiles files;

  /// The packages of the workspace.
  final PackageLayout packages;

  /// The message bundles, whose keys are no properties.
  final MessageIndex messages;

  /// The metadata of the packages.
  final MetadataStore metadata;

  final _dependencyFiles = <String, _DependencyConfig>{};

  /// The definitions of the property [key] for a value read in [from]: the
  /// properties a test sets for its own context first (when [from] is a
  /// test), then the config files of [from]'s package, `application.*`
  /// first, then by file name and line. Without [from], those of every
  /// config file of the workspace.
  List<PropertyEntry> property(String key, {String? from}) {
    final name = PropertyName(key);
    if (from == null) {
      return _inConfig(name, null)..sort(_byFile);
    }
    return [..._inTest(from, name), ..._inConfig(name, from)..sort(_byFile)];
  }

  /// The entries of [key] a value read in [path] can come from, as
  /// [property] finds them but in the order of the index, which decides
  /// between entries that stand equal ([PropertyValues]).
  List<PropertyEntry> propertyEntriesIn(String path, String key) {
    final name = PropertyName(key);
    return [..._inTest(path, name), ..._inConfig(name, path)];
  }

  /// The definitions whose key starts with [prefix] and a dot, with relaxed
  /// names as in [property]: the keys a `@ConfigurationProperties('shop')`
  /// class binds. With [from], only those of its package.
  List<PropertyEntry> propertiesWithPrefix(String prefix, {String? from}) {
    final wanted = '${canonicalName(prefix)}.';
    return [
      for (final MapEntry(value: entries) in _configFiles(from))
        for (final entry in entries)
          if (canonicalName(entry.key).startsWith(wanted)) entry,
    ]..sort(_byFile);
  }

  // The properties a test file [path] sets for its context that are [name].
  List<PropertyEntry> _inTest(String path, PropertyName name) {
    final dartFile = path.endsWith('.dart') ? files.dartFile(path) : null;
    return [
      if (dartFile != null)
        for (final entry in testProperties(dartFile))
          if (name.matches(entry)) entry,
    ];
  }

  // The entries of the config files of [from]'s package (every package
  // without [from]) that are [name].
  List<PropertyEntry> _inConfig(PropertyName name, String? from) => [
    for (final MapEntry(value: entries) in _configFiles(from))
      for (final entry in entries)
        if (name.matches(entry)) entry,
  ];

  /// The paths of the config files of [path]'s package (message bundles
  /// left out).
  List<String> configFilesOf(String path) => [
    for (final file in _configFiles(path)) file.key,
  ];

  // The config files, message bundles left out: those of [from]'s package,
  // or all without [from].
  Iterable<MapEntry<String, List<PropertyEntry>>> _configFiles(
    String? from,
  ) sync* {
    final package = from == null ? null : packages.packageRootOf(from);
    final bundles = messages.bundlePaths;
    for (final file in files.configFiles.entries) {
      if (!bundles.contains(file.key) &&
          (package == null || packages.packageRootOf(file.key) == package)) {
        yield file;
      }
    }
  }

  static int _byFile(PropertyEntry a, PropertyEntry b) =>
      _fileOrder(a).compareTo(_fileOrder(b));

  static String _fileOrder(PropertyEntry entry) =>
      '${entry.fileName == 'application' ? 0 : 1}${entry.fileName}'
      '${entry.line.toString().padLeft(6, '0')}';

  /// The profiles values are read under in [path]: [configured] (the
  /// editor's setting) when it names any, else those of a test's
  /// `@ActiveProfiles`, else the `spring.profiles.active` of the package's
  /// config, else the framework's `default`.
  ActiveProfiles activeProfilesOf(String path, List<String> configured) {
    if (configured.isNotEmpty) {
      return ActiveProfiles(configured);
    }
    if (path.endsWith('.dart')) {
      if (files.dartFile(path) case final dartFile?) {
        if (activeProfilesAnnotation(dartFile.unit) case final profiles?) {
          return ActiveProfiles(profiles);
        }
      }
    }
    final active = PropertyValues(
      (key) => propertyEntriesIn(path, key),
      ActiveProfiles(const []),
    ).winner('spring.profiles.active');
    return active == null
        ? ActiveProfiles(const [])
        : ActiveProfiles.parse(active.value);
  }

  /// The entries of the config files that apply to [path]: those of its own
  /// package, and those of the dependencies' `lib/resources` (their themes
  /// are what `$` references may point into).
  List<PropertyEntry> configEntries(String path) {
    final package = packages.packageRootOf(path);
    final view = metadata.viewFor(package);
    final seen = <String>{};
    final result = <PropertyEntry>[];
    for (final MapEntry(key: file, value: entries)
        in files.configFiles.entries) {
      if (packages.packageRootOf(file) == package) {
        seen.add(file);
        result.addAll(entries);
      }
    }
    for (final root in view.packageRoots.values) {
      if (root == package) {
        continue;
      }
      for (final entry in _dependencyConfig(root)) {
        if (!seen.contains(entry.path) ||
            files.configFiles[entry.path] == null) {
          result.add(entry);
        }
      }
    }
    return result;
  }

  // The config files under `lib/resources` of a dependency (only inside
  // the dependency, links not followed), checked for changes at most every
  // few seconds: listed again when a directory changed, a file read again
  // when it changed.
  List<PropertyEntry> _dependencyConfig(String root) {
    final cached = _dependencyFiles[root] ??= _DependencyConfig(
      ConfinedFiles(
        root,
        '$root${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}resources',
      ),
    );
    final now = DateTime.now();
    if (cached.checked case final checked?
        when now.difference(checked).inSeconds < 5) {
      return cached.entries;
    }
    cached.checked = now;
    final byFile = <String, List<PropertyEntry>>{};
    for (final file in cached.listing.files()) {
      if (!ConfigFormat.isConfigFile(file.path)) {
        continue;
      }
      if (files.configFiles[file.path] case final known?) {
        byFile[file.path] = known;
        continue;
      }
      final previous = cached.byFile[file.path];
      final changed = cached.listing.changed(file);
      if (previous != null && !changed) {
        byFile[file.path] = previous;
        continue;
      }
      try {
        byFile[file.path] = ConfigFormat.of(
          file.path,
        ).entries(file.path, file.readAsStringSync());
      } on FileSystemException {
        // A file being rewritten: next time.
      }
    }
    cached
      ..byFile = byFile
      ..entries = [for (final entries in byFile.values) ...entries];
    return cached.entries;
  }

  /// The profile names known to the package of [path]: those the metadata
  /// lists, the `application-<name>` files and the profiles the config
  /// activates.
  Set<String> knownProfiles(String path) {
    final package = packages.packageRootOf(path);
    final result = {...metadata.viewFor(package).profiles};
    for (final file in files.configFiles.keys) {
      if (packages.packageRootOf(file) != package) {
        continue;
      }
      final match = RegExp(
        r'^application-(.+)\.(?:properties|ya?ml)$',
      ).firstMatch(file.split(RegExp(r'[\\/]')).last);
      if (match != null) {
        result.add(match.group(1)!);
      }
    }
    for (final entry in configEntries(path)) {
      if (const {
            'spring.profiles.active',
            'spring.profiles.include',
            'spring.config.activate.on-profile',
          }.contains(entry.key) &&
          !entry.value.contains(r'${')) {
        // `a, b` or an expression such as `!web & (mobile | spa)`.
        for (final match in RegExp(
          r'[A-Za-z0-9_][\w\-.]*',
        ).allMatches(entry.value)) {
          result.add(match.group(0)!);
        }
      }
    }
    return result;
  }
}

/// The config files of a dependency, as last read.
final class _DependencyConfig {
  _DependencyConfig(this.listing);

  final ConfinedFiles listing;
  DateTime? checked;
  Map<String, List<PropertyEntry>> byFile = {};
  List<PropertyEntry> entries = [];
}
