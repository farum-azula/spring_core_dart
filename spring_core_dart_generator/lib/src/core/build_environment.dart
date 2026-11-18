// The application's configuration as the build reads it: the files of
// lib/resources/ for a platform's profiles, as the running app would read
// them, without what only the device has (its disk, the network). The
// builders that write files from the configuration read it through
// [readPlatformEnvironment]: the web dev server's config, the page loader,
// the SEO pages, the deep links, the search index, the JSON Schemas.
import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart' hide Resource;
import 'package:spring_core_dart/core.dart';

/// The environment the app reads on the platform of [profiles] (`['ios',
/// 'mobile']`) from the config files [texts] of `lib/resources/` (and the
/// [binary] ones an import names with an encoding), read at build time
/// the way `web_dev_config.yaml` is read for the browser: placeholders only
/// the running app resolves are left out with a warning, a `file:` import
/// (the device's disk, not the build machine's) is skipped.
///
/// Throws [BuildConfigException] when the files cannot be read.
StandardEnvironment readPlatformEnvironment(
  Map<String, String> texts, {
  required List<String> profiles,
  Map<String, Uint8List> binary = const {},
}) {
  final reading = BuildConfigReading(
    texts,
    binary,
    StaticBuildConfig(texts, binary),
    profiles,
  );
  final environment = reading.read();
  reading.warnings.forEach(log.warning);
  return environment;
}

/// The keys of the Flutter web dev server, `spring.flutter.web.dev-server.*`.
/// The reading was made for its `web_dev_config.yaml` first, which is why
/// the reading itself watches them and its messages name them.
const webDevServerPrefix = 'spring.flutter.web.dev-server';

/// The file the Flutter web dev server reads, `web_dev_config.yaml`.
const webDevConfigFileName = 'web_dev_config.yaml';

/// A property read at build time that cannot be read or is invalid; the
/// message names it.
final class BuildConfigException implements Exception {
  /// Creates the exception with [message].
  BuildConfigException(this.message);

  /// What is wrong, starting with the property's name.
  final String message;

  @override
  String toString() => message;
}

// What a location of the config finds when the app runs in a browser, as
// far as the build knows it:
// - `memory:` (the default locations), `resources:` and plain paths: the
//   build's own files of lib/resources/, as the app reads its embedded
//   ones, not a lib/resources/ on disk below the working directory
//   (another package's in a workspace build);
// - `file:` and `package:` (also a plain absolute path and a
//   `configtree:` directory, which are read through `file:`, wildcards
//   included): nothing, as a browser has no file system and no package
//   files; an optional one is skipped, a required one is not found
//   (BuildConfigReading then loads the files again with every location
//   optional, and a warning names it when there is a file to write);
// - a missing file of lib/resources/ and any other location (`asset:`,
//   `http:`): an empty file, so even a required one is skipped. It may
//   exist at run time only, and the build must not depend on what it
//   cannot read.
final class _BrowserResources implements ProtocolResolver {
  _BrowserResources(Map<String, String> files, this._binary)
    : _resolvers = [
        InMemoryProtocolResolver('memory:', files),
        InMemoryProtocolResolver(Resources.prefix, files),
      ];

  final List<InMemoryProtocolResolver> _resolvers;

  // The files that are not UTF-8, by path below lib/resources/.
  final Map<String, Uint8List> _binary;

  static final _scheme = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]+:');

  @override
  Resource resolve(String location, ResourceLoader resourceLoader) {
    for (final prefix in ['memory:', Resources.prefix]) {
      if (location.startsWith(prefix)) {
        // InMemoryProtocolResolver's path cleaning.
        final path = FileSystemResource(
          location.substring(prefix.length),
        ).path.replaceFirst(RegExp('^/'), '');
        if (_binary[path] case final bytes?) {
          return ByteArrayResource(
            bytes,
            description: 'resource [$prefix$path]',
          );
        }
      }
    }
    for (final resolver in _resolvers) {
      if (resolver.resolve(location, resourceLoader) case final resource?) {
        return resource.exists() ? resource : _empty(resource.description);
      }
    }
    if (location.startsWith(ResourceLoader.filePrefix) ||
        location.startsWith(DefaultResourceLoader.packagePrefix)) {
      return DescriptiveResource(
        'resource [$location] (not readable in a browser)',
      );
    }
    if (_scheme.hasMatch(location)) {
      return _empty('resource [$location]');
    }
    return resolve('${Resources.prefix}$location', resourceLoader);
  }

  static Resource _empty(String description) =>
      ByteArrayResource.fromString('', description: description);

  // Whether a location (a `;` group as written) has an entry of the file
  // system or of a package: what a browser can never read. Any other
  // location that is not found (a `resources:` directory without config
  // files) may be provided at run time and is skipped silently.
  static bool notInBrowser(String location) {
    for (var entry in location.split(';')) {
      entry = entry.trim();
      if (entry.startsWith(ConfigDataEnvironment.optionalPrefix)) {
        entry = entry.substring(ConfigDataEnvironment.optionalPrefix.length);
      }
      if (entry.startsWith(ResourceLoader.filePrefix) ||
          entry.startsWith(DefaultResourceLoader.packagePrefix) ||
          entry.startsWith(ConfigDataEnvironment.configTreePrefix) ||
          entry.startsWith('/') ||
          entry.startsWith(r'\') ||
          RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(entry)) {
        return true;
      }
    }
    return false;
  }
}

/// ` (in lib/resources/application-web.yaml)` for the property source of
/// a config file of lib/resources/ (named `Config resource
/// 'memory:/application-web.yaml'`, or `'resources:...'` when imported).
String configSourceOrigin(String sourceName) {
  final match = RegExp(
    "'(?:memory|resources):/?([^']+)'",
  ).firstMatch(sourceName);
  return match == null ? '' : ' (in lib/resources/${match[1]})';
}

/// What the config files of lib/resources/ say without being loaded as the
/// app loads them: whether any of them sets a spring.flutter.web.* key or
/// spring.flutter.security.web.mode (in any document, for any profile),
/// which files do not parse, and every key with its first value (the keys
/// a placeholder may find at build time). Every .properties, .yml and
/// .yaml file counts, as an import may name any of them, and so does a
/// file an import names with file hints (`resources:dev.conf[.yaml]`,
/// `resources:web.properties[encoding=iso-8859-1]`), read in that format
/// and encoding (a file that is not UTF-8 only that way). A placeholder in
/// such an import is resolved with its default or a value of the files
/// (`resources:${ENV:dev}.conf[.yaml]`); one only the running app knows
/// leaves the import unscanned.
final class StaticBuildConfig {
  /// Reads the config [_files] of lib/resources/ (and the [_binary] ones an
  /// import names with an encoding) without loading them.
  StaticBuildConfig(this._files, this._binary) {
    final pending = <_Hinted>[
      for (final path in _files.keys.toList()..sort())
        if (_loaderOf(_extension(path)) case final loader?)
          (path, loader, null),
    ];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      while (pending.isNotEmpty) {
        final (path, loader, encoding) = pending.removeAt(0);
        if (seen.add(
          '${loader.fileExtensions.first}:${encoding?.name}:$path',
        )) {
          pending.addAll(_scan(path, loader, encoding));
        }
      }
      // The imports with placeholders, once every file found so far has
      // given its values; a file they find may give more.
      final resolver = valuesResolver(values);
      for (final (importing, location) in _withPlaceholders.toList()) {
        final String resolved;
        try {
          resolved = resolver.resolveRequiredPlaceholders(location);
        } on Exception {
          continue; // unknown at build time, for now
        }
        _withPlaceholders.remove((importing, location));
        if (_hinted(importing, resolved) case final file?) {
          pending.add(file);
        }
      }
    }
  }

  // The hinted imports with a placeholder not resolved yet: the importing
  // file and the location.
  final _withPlaceholders = <(String, String)>{};

  /// A resolver of placeholders over [values] (key to value), names
  /// relaxed.
  static PropertyResolver valuesResolver(Map<String, Object> values) {
    final source = MapPropertySource('lib/resources', values);
    return PropertySourcesPropertyResolver(
      MutablePropertySources([
        ConfigurationPropertySourcesPropertySource(
          ConfigurationPropertySources.attachedPropertySourceName,
          [source],
        ),
        source,
      ]),
    );
  }

  final Map<String, String> _files;

  // The files that are not UTF-8.
  final Map<String, Uint8List> _binary;

  /// Whether a file sets a key of the web dev server
  /// ([webDevServerPrefix]).
  bool setsWebKeys = false;

  /// The keys of `spring.flutter.web.*` that are neither `dev-server` nor
  /// `seo` (the dev server's keys before 0.7.1), with their files.
  final moved = <String, String>{};

  /// The files that do not parse.
  final unparsed = <String>[];

  /// Every key of every file, with the value of the first file that has
  /// it.
  final values = <String, Object>{};

  static const List<PropertySourceLoader> _loaders = [
    PropertiesPropertySourceLoader(),
    YamlPropertySourceLoader(),
  ];

  static final _web = ConfigurationPropertyName.of(webDevServerPrefix);
  static final _flutterWeb = ConfigurationPropertyName.of('spring.flutter.web');
  static final _spaMode = ConfigurationPropertyName.of(
    'spring.flutter.security.web.mode',
  );
  static final _import = ConfigurationPropertyName.of(
    ConfigDataEnvironment.importProperty,
  );

  static PropertySourceLoader? _loaderOf(String extension) => _loaders
      .where((loader) => loader.fileExtensions.contains(extension))
      .firstOrNull;

  // The loader of an extension hint, matched without case as the config
  // loader does (`[.YAML]`).
  static PropertySourceLoader? _loaderOfHint(String extension) =>
      _loaderOf(extension.toLowerCase());

  static String _extension(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1);
  }

  // The text of the file at [path] as [loader] reads it, decoded with the
  // encoding an import names ([encoding], else UTF-8); `null` when there
  // is no such file, or it does not decode (then it is [unparsed], as the
  // app fails on it).
  String? _text(String path, PropertySourceLoader loader, Encoding? encoding) {
    final text = _files[path];
    if (encoding == null) {
      return text;
    }
    final bytes = _binary[path] ?? (text == null ? null : utf8.encode(text));
    if (bytes == null) {
      return null;
    }
    try {
      return loader.encodingFor(encoding).decode(bytes);
    } on FormatException {
      unparsed.add(path);
      return null;
    }
  }

  // Reads the file at [path] with [loader] (decoded with [encoding] when
  // an import names one); returns the files its imports name with a file
  // hint.
  List<_Hinted> _scan(
    String path,
    PropertySourceLoader loader,
    Encoding? encoding,
  ) {
    final text = _text(path, loader, encoding);
    if (text == null) {
      return const [];
    }
    final List<AbstractPropertySource<Object>> sources;
    try {
      sources = loader.load(path, text);
    } on FormatException {
      unparsed.add(path);
      return const [];
    }
    final hinted = <_Hinted>[];
    for (final source in sources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      final imports = <String>[];
      for (final MapEntry(key: name, value: keys)
          in ConfigurationPropertySources.propertyNames(source).entries) {
        if (_web.isAncestorOf(name) || name == _spaMode) {
          setsWebKeys = true;
        }
        // A key of the dev server before it moved under dev-server.
        if (_flutterWeb.isAncestorOf(name) &&
            !const {'devserver', 'seo', 'page'}.contains(
              name.getElement(3, form: ConfigurationPropertyNameForm.uniform),
            )) {
          moved.putIfAbsent(keys.first, () => path);
        }
        for (final key in keys) {
          if (source.getProperty(key) case final value?) {
            values.putIfAbsent(key, () => value);
            if (name == _import ||
                name.isNumericIndex(name.numberOfElements - 1) &&
                    name.parent == _import) {
              imports.add('$value');
            }
          }
        }
      }
      for (final value in imports) {
        for (final location in value.split(RegExp('[,;]'))) {
          if (location.contains(r'${')) {
            _withPlaceholders.add((path, location));
          } else if (_hinted(path, location) case final file?) {
            hinted.add(file);
          }
        }
      }
    }
    return hinted;
  }

  // The file of lib/resources/ that the import [location] of the file at
  // [importing] names with a file hint (relative, or `resources:`), as the
  // app reads its file hints (ConfigDataEnvironment.fileHints, on the
  // location joined to the importing file's directory, so brackets in that
  // directory's path are taken out too): with the loader of the extension
  // hint or of the file's extension, and the encoding of an encoding hint;
  // `null` for any other location (its placeholders already resolved),
  // and for a charset the app cannot read (its start reports that).
  static _Hinted? _hinted(String importing, String location) {
    var value = location.trim();
    if (value.startsWith(ConfigDataEnvironment.optionalPrefix)) {
      value = value.substring(ConfigDataEnvironment.optionalPrefix.length);
    }
    if (!value.contains('[') || value.endsWith('/')) {
      return null; // no hint: every config file is read anyway
    }
    final relative =
        !value.startsWith(Resources.prefix) &&
        !RegExp('^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(value) &&
        !value.startsWith('/') &&
        !value.startsWith(r'\');
    if (!relative && !value.startsWith(Resources.prefix)) {
      return null;
    }
    final ({String path, String? extension, Encoding? encoding}) hints;
    try {
      hints = ConfigDataEnvironment.fileHints(
        relative
            ? '${importing.substring(0, importing.lastIndexOf('/') + 1)}$value'
            : value,
      );
    } on ConfigDataLoadException {
      return null;
    }
    var file = hints.path;
    final PropertySourceLoader? loader;
    if (hints.extension case final extension?) {
      loader = _loaderOfHint(extension);
    } else {
      // The loader's spelling names the file, as for the app (`x.YAML`
      // reads `x.yaml`).
      final extension = _extension(file);
      loader = _loaderOfHint(extension);
      if (loader != null) {
        final spelling = extension.toLowerCase();
        file = '${file.substring(0, file.length - extension.length)}$spelling';
      }
    }
    if (loader == null) {
      return null;
    }
    if (!relative) {
      file = file.substring(Resources.prefix.length);
    }
    return switch (Resources.normalize(file)) {
      final path? when !path.endsWith('/') => (path, loader, hints.encoding),
      _ => null,
    };
  }
}

// A config file to scan: its path below lib/resources/, its loader, the
// encoding an import names.
typedef _Hinted = (String, PropertySourceLoader, Encoding?);

/// One reading of the config files as the app in a browser reads them: the
/// `web` profile, no environment variables (the build must not depend on
/// them), [_BrowserResources] deciding what each location finds, and
/// [_BuildTimeLoader] taking out of each document the placeholders only the
/// running app can resolve.
final class BuildConfigReading {
  /// A reading of the config files of lib/resources/ (and the binary ones
  /// an import names) that a [StaticBuildConfig] scanned, for the platform
  /// of the profiles given (the browser's, `web`, by default).
  BuildConfigReading(
    this._files,
    this._binary,
    this._config, [
    this._profiles = const ['web'],
  ]);

  final Map<String, String> _files;
  final Map<String, Uint8List> _binary;
  final StaticBuildConfig _config;

  // The platform profiles the app activates where it runs: `web` in a
  // browser, `ios` and `mobile` on an iPhone.
  final List<String> _profiles;

  // Placeholders some config file sets, but only in a document that is not
  // read: unknown at build time as well (found when a read fails on
  // them).
  final _unresolvable = <String>{};

  // The resolver of placeholders over every key of every config file,
  // without [_unresolvable].
  late PropertyResolver _known;

  /// Whether a config file that the app reads does not parse.
  bool unparsed = false;

  /// The first required location a browser cannot read
  /// ([_BrowserResources.notInBrowser]), skipped as if optional.
  String? unreadable;

  /// The warnings about placeholders unknown at build time.
  final warnings = <String>{};

  static const _ignoreNotFoundSource = 'webDevConfigIgnoreNotFound';

  /// The environment the config files are read into; throws
  /// [BuildConfigException] when they cannot be.
  StandardEnvironment read() {
    var ignoreNotFound = false;
    while (true) {
      unparsed = false;
      warnings.clear();
      _known = _resolverWithout(_unresolvable);
      try {
        return _load(ignoreNotFound: ignoreNotFound);
      } on PlaceholderResolutionException catch (e) {
        if (!_unresolvable.add(e.placeholder)) {
          throw _cannotRead(e);
        }
      } on ConfigDataResourceNotFoundException catch (e) {
        if (!_retryWithout(e.location)) {
          ignoreNotFound = _notFound(e, e.location, ignoreNotFound);
        }
      } on ConfigDataLocationNotFoundException catch (e) {
        if (!_retryWithout(e.location)) {
          ignoreNotFound = _notFound(e, e.location, ignoreNotFound);
        }
      } on ConfigDataLoadException catch (e) {
        if (!_retryWithout(e.location)) {
          throw _cannotRead(e);
        }
      } on Exception catch (e) {
        throw _cannotRead(e);
      } on StateError catch (e) {
        // An invalid profile name (Boot's IllegalStateException).
        throw _cannotRead(e);
      } on ArgumentError catch (e) {
        // A malformed profile expression in an on-profile guard
        // (`a & | b`, Boot's IllegalArgumentException), a profile name the
        // environment refuses (`!x` with spring.profiles.validate=false).
        throw _cannotRead(e);
      }
    }
  }

  // A required location that is not found: the app in a browser does not
  // find it either, so every location is read as optional from now on.
  bool _notFound(Object e, String location, bool ignoreNotFound) {
    if (ignoreNotFound) {
      throw _cannotRead(e);
    }
    if (_BrowserResources.notInBrowser(location)) {
      unreadable = location;
    }
    return true;
  }

  static BuildConfigException _cannotRead(Object e) => BuildConfigException(
    'The config files of lib/resources/ cannot be read for the '
    '$webDevServerPrefix.* properties: $e',
  );

  // A location with a placeholder that was not resolved (lenient, as an
  // import's is): its placeholders are unknown at build time; whether
  // that is news, so reading again changes something.
  bool _retryWithout(String location) {
    var added = false;
    for (final (start, end) in _placeholders(location)) {
      final name = _key(location.substring(start + 2, end - 1));
      if (name != null && _unresolvable.add(name)) {
        added = true;
      }
    }
    return added;
  }

  // The config files loaded into a new environment. A required location
  // that is not found throws, unless [ignoreNotFound] makes every
  // location optional (`spring.config.on-not-found=ignore`, a source
  // removed again afterwards).
  StandardEnvironment _load({required bool ignoreNotFound}) {
    final environment = StandardEnvironment(systemEnvironment: const {});
    if (ignoreNotFound) {
      environment.propertySources.addFirst(
        const MapPropertySource(_ignoreNotFoundSource, {
          ConfigDataEnvironment.onNotFoundProperty: 'ignore',
        }),
      );
    }
    ConfigDataEnvironment(
      environment,
      resourceLoader: DefaultResourceLoader(
        protocolResolvers: [_BrowserResources(_files, _binary)],
      ),
      loaders: [
        for (final loader in StaticBuildConfig._loaders)
          _BuildTimeLoader(loader, this),
      ],
      defaultLocations: const ['optional:memory:/;optional:memory:/config/'],
      additionalProfiles: _profiles,
    ).processAndApplySync();
    environment.propertySources.remove(_ignoreNotFoundSource);
    ConfigurationPropertySources.attach(environment);
    return environment;
  }

  PropertyResolver _resolverWithout(Set<String> names) {
    final hidden = {
      for (final name in names) ?ConfigurationPropertyName.ofIfValid(name),
    };
    return StaticBuildConfig.valuesResolver({
      for (final MapEntry(:key, :value) in _config.values.entries)
        if (!hidden.contains(ConfigurationPropertyName.adapt(key, '.')) &&
            !names.contains(key))
          key: value,
    });
  }

  // The keys that decide which files and documents are read, as found in
  // a document: what an unknown placeholder in each makes of it.
  static final _groups = ConfigurationPropertyName.of('spring.profiles.group');
  static final Map<ConfigurationPropertyName, _Decisive> _decisive = {
    for (final name in [
      StandardEnvironment.activeProfilesPropertyName,
      StandardEnvironment.defaultProfilesPropertyName,
      ConfigDataEnvironment.includeProfilesProperty,
    ])
      ConfigurationPropertyName.of(name): _Decisive.profiles,
    for (final name in [
      ConfigDataEnvironment.validateProfilesProperty,
      CloudPlatform.propertyName,
    ])
      ConfigurationPropertyName.of(name): _Decisive.value,
    ConfigurationPropertyName.of(ConfigDataEnvironment.importProperty):
        _Decisive.import,
    ConfigurationPropertyName.of(ConfigDataEnvironment.onProfileProperty):
        _Decisive.guard,
    ConfigurationPropertyName.of(ConfigDataEnvironment.onCloudPlatformProperty):
        _Decisive.guard,
  };

  // What [name] decides, in any form the app reads it in: a group's name
  // dotted or in brackets (`spring.profiles.group.prod`,
  // `spring.profiles.group[my.prod]`), any element in brackets
  // (`spring.profiles[active]` is `spring.profiles.active`, as in Boot),
  // a list item by its index (`spring.profiles.active[0]`).
  static _Decisive? _decisiveOf(ConfigurationPropertyName name) {
    if (name.isEmpty) {
      return null;
    }
    if (_groups.isAncestorOf(name)) {
      return _Decisive.profiles;
    }
    return _decisive[_isListItem(name) ? name.parent : name];
  }

  // Whether the last element of [name] is a list index (`[0]`), not a map
  // key in brackets (`[prod]`).
  static bool _isListItem(ConfigurationPropertyName name) =>
      name.isNumericIndex(name.numberOfElements - 1);

  /// [source], a document as loaded, as far as the build can know it: the
  /// keys that decide which files and documents are read (profiles, cloud
  /// platform, imports) without what has a placeholder only the running
  /// app can resolve, an import with one left out; a document that never
  /// applies (skipped) when its `spring.config.activate.*` guard has one.
  /// Each is warned about.
  ///
  /// A key left without a value stays in the document, and a skipped
  /// document stays loaded, so the checks of where a key may be (a profile
  /// file or an on-profile document may not set the profiles) still see
  /// it, whatever its value.
  AbstractPropertySource<Object> atBuildTime(
    AbstractPropertySource<Object> source,
  ) {
    if (source is! EnumerablePropertySource<Object>) {
      return source;
    }
    Map<String, Object?>? changed;
    for (final MapEntry(key: name, value: keys)
        in ConfigurationPropertySources.propertyNames(source).entries) {
      final decisive = _decisiveOf(name);
      if (decisive == null) {
        continue;
      }
      for (final key in keys) {
        final value = source.getProperty(key);
        if (value is! String || !value.contains(r'${')) {
          continue;
        }
        final unknown = _unknown(value);
        if (unknown.isEmpty) {
          continue;
        }
        // What is left of the value, and what is left out.
        final (String kept, List<String> dropped) = switch (decisive) {
          _Decisive.guard => ('', const []),
          _Decisive.import => _withoutImports(value),
          _Decisive.profiles => _withoutProfiles(value),
          _Decisive.value => ('', [value]),
        };
        warnings.add(
          _warning(key, source.name, value, unknown, decisive, dropped, kept),
        );
        if (decisive == _Decisive.guard) {
          return _neverActive(source);
        }
        // A list item keeps its place (an empty one), so the items after
        // it are still read.
        (changed ??= {})[key] = kept.isEmpty && !_isListItem(name)
            ? null
            : kept;
      }
    }
    return changed == null ? source : _BuildTimeSource(source, changed);
  }

  // [source], whose guard has a placeholder unknown at build time, as a
  // document that never applies: its guards replaced by an on-profile
  // expression no profiles match. Not dropped, so the checks the app makes
  // of every document still see its keys (the legacy `spring.profiles`;
  // `spring.profiles.active` in any document of a profile file).
  static AbstractPropertySource<Object> _neverActive(
    EnumerablePropertySource<Object> source,
  ) {
    final changed = <String, Object?>{
      for (final MapEntry(key: name, value: keys)
          in ConfigurationPropertySources.propertyNames(source).entries)
        if (_decisiveOf(name) == _Decisive.guard)
          for (final key in keys) key: null,
    };
    changed[ConfigDataEnvironment.onProfileProperty] = 'web & !web';
    return _BuildTimeSource(source, changed);
  }

  // The names of the placeholders of [text] (outside nested ones) that do
  // not resolve at build time: each the innermost name that fails.
  List<String> _unknown(String text) => [
    for (final (start, end) in _placeholders(text))
      ?_failing(text.substring(start, end)),
  ];

  String? _failing(String placeholder) {
    try {
      _known.resolveRequiredPlaceholders(placeholder);
      return null;
    } on PlaceholderResolutionException catch (e) {
      return e.placeholder;
    }
  }

  // A comma list of profiles without the names that have a placeholder
  // that does not resolve at build time, whatever else the name holds
  // (`dev,${ENV}-eu` is `dev`); with the names left out.
  (String, List<String>) _withoutProfiles(String value) {
    final kept = <String>[];
    final dropped = <String>[];
    for (final item in _topLevelSplit(value, ',')) {
      if (_unknown(item).isEmpty) {
        kept.add(item);
      } else {
        dropped.add(item.trim());
      }
    }
    return (kept.join(','), dropped);
  }

  // An import value without the locations that have a placeholder that
  // does not resolve at build time (a `;` group keeps its `optional:`);
  // with the locations left out, as written.
  (String, List<String>) _withoutImports(String value) {
    final dropped = <String>[];
    final kept = [
      for (final item in _topLevelSplit(value, ','))
        if (_withoutUnknownEntries(item, dropped) case final group
            when group.isNotEmpty)
          group,
    ];
    return (kept.join(','), dropped);
  }

  String _withoutUnknownEntries(String group, List<String> dropped) {
    final entries = _topLevelSplit(group, ';');
    final optional = entries.first.trim().startsWith(
      ConfigDataEnvironment.optionalPrefix,
    );
    final kept = <String>[];
    for (final entry in entries) {
      if (_unknown(entry).isEmpty) {
        kept.add(entry.trim());
      } else {
        dropped.add(entry.trim());
      }
    }
    if (kept.isEmpty) {
      return '';
    }
    if (optional &&
        !kept.first.startsWith(ConfigDataEnvironment.optionalPrefix)) {
      kept[0] = '${ConfigDataEnvironment.optionalPrefix}${kept.first}';
    }
    return kept.join(';');
  }

  // [text] split at [separator] outside `${...}` placeholders, so a
  // default with a comma (`${A:a,b}`) stays in one part.
  static List<String> _topLevelSplit(String text, String separator) {
    final spans = _placeholders(text);
    final parts = <String>[];
    var last = 0;
    var span = 0;
    for (
      var i = text.indexOf(separator);
      i != -1;
      i = text.indexOf(separator, i + separator.length)
    ) {
      while (span < spans.length && spans[span].$2 <= i) {
        span++;
      }
      if (span < spans.length && spans[span].$1 <= i) {
        continue; // inside a placeholder
      }
      parts.add(text.substring(last, i));
      last = i + separator.length;
    }
    return parts..add(text.substring(last));
  }

  static String _warning(
    String key,
    String sourceName,
    String value,
    List<String> unknown,
    _Decisive decisive,
    List<String> dropped,
    String kept,
  ) {
    final names = unknown.toSet().map((name) => '\${$name}').join(', ');
    final quoted = dropped.map((item) => "'$item'").join(', ');
    final consequence = switch (decisive) {
      _Decisive.guard => 'the document is skipped',
      _Decisive.import when kept.isEmpty =>
        dropped.length == 1
            ? 'the import is not read'
            : 'the imports $quoted are not read',
      _Decisive.import =>
        dropped.length == 1
            ? '$quoted is not read (the rest of the value is)'
            : '$quoted are not read (the rest of the value is)',
      _Decisive.profiles =>
        dropped.length == 1
            ? 'the profile $quoted is left out'
            : 'the profiles $quoted are left out',
      _Decisive.value => 'it is read as if it were not set',
    };
    final origin = configSourceOrigin(sourceName);
    return "$key$origin: '$value' cannot be resolved at build time: only the "
        'running app knows $names (an environment variable or a '
        '--dart-define, which $webDevConfigFileName cannot depend '
        'on), so $consequence. Give it a default in the config files '
        "('\${${unknown.first}:...}') to have "
        '$webDevConfigFileName use that.';
  }

  // The `${...}` placeholders of [text] outside nested ones, as (start,
  // end) offsets; an unclosed one ends the search. An escaped one
  // (`\${X}`, the literal text `${X}`) is none.
  static List<(int, int)> _placeholders(String text) {
    final spans = <(int, int)>[];
    var index = text.indexOf(r'${');
    while (index != -1) {
      if (index > 0 && text[index - 1] == r'\') {
        index = text.indexOf(r'${', index + 2);
        continue;
      }
      var depth = 0;
      var end = -1;
      for (var i = index; i < text.length; i++) {
        if (text.startsWith(r'${', i)) {
          depth++;
          i++;
        } else if (text[i] == '}' && --depth == 0) {
          end = i + 1;
          break;
        }
      }
      if (end == -1) {
        break;
      }
      spans.add((index, end));
      index = text.indexOf(r'${', end);
    }
    return spans;
  }

  // The key of a placeholder's content (before its default), `null` when
  // it is itself made of placeholders.
  static String? _key(String content) {
    final colon = content.indexOf(':');
    final key = (colon == -1 ? content : content.substring(0, colon)).trim();
    return key.isEmpty || key.contains(r'${') ? null : key;
  }
}

// What an unknown placeholder in a key that decides what is read makes of
// it ([BuildConfigReading.atBuildTime]).
enum _Decisive {
  // spring.profiles.active, .default, .include, .group.*: each profile
  // name with one is left out (the property without a value when none is
  // left).
  profiles,
  // spring.profiles.validate, spring.main.cloud-platform: the property is
  // read without a value.
  value,
  // spring.config.import: the location is not read.
  import,
  // spring.config.activate.*: the document is skipped.
  guard,
}

// A document with some of its keys changed ([BuildConfigReading.atBuildTime]):
// a `null` value leaves the key without a value but still in the document
// (in its names, `containsProperty` true), as a map entry with a `null`
// value is in Spring's MapPropertySource.
final class _BuildTimeSource extends EnumerablePropertySource<Object> {
  _BuildTimeSource(this._source, this._changed)
    : super(_source.name, _source.source);

  final EnumerablePropertySource<Object> _source;
  final Map<String, Object?> _changed;

  @override
  Object? getProperty(String name) =>
      _changed.containsKey(name) ? _changed[name] : _source.getProperty(name);

  @override
  bool containsProperty(String name) => _source.containsProperty(name);

  @override
  List<String> get propertyNames => _source.propertyNames;
}

// A config file format, read for the dev server's file: [_delegate]'s
// documents as far as the build can know them
// ([BuildConfigReading.atBuildTime]); a file that does not parse is noted.
final class _BuildTimeLoader extends PropertySourceLoader {
  _BuildTimeLoader(this._delegate, this._reading);

  final PropertySourceLoader _delegate;
  final BuildConfigReading _reading;

  @override
  List<String> get fileExtensions => _delegate.fileExtensions;

  @override
  Encoding get encoding => _delegate.encoding;

  @override
  Encoding encodingFor(Encoding hint) => _delegate.encodingFor(hint);

  @override
  List<AbstractPropertySource<Object>> load(String name, String content) {
    final List<AbstractPropertySource<Object>> sources;
    try {
      sources = _delegate.load(name, content);
    } on FormatException {
      _reading.unparsed = true;
      rethrow;
    }
    return [for (final source in sources) _reading.atBuildTime(source)];
  }
}
