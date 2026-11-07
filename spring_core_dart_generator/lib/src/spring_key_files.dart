import 'dart:convert';

import 'package:build/build.dart' hide Resource;
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/generated_path.dart';
import 'package:spring_core_dart_generator/src/theme_references.dart';
import 'package:spring_core_dart_generator/src/typed_message_keys.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:yaml/yaml.dart';

/// The Dart code of the key files a package gets, without header and
/// `part of`: `null` for a file that is not written.
typedef KeyParts = ({String? theme, String? messages});

/// A `.dart` file with a `@ComponentScan` or `@SpringBootApplication`, and
/// whether it has the second.
typedef ScanLibrary = ({AssetId id, bool boot});

/// What the two builders agree on about the typed key files
/// (`lib/spring_gen/theme.spring.dart`, `lib/spring_gen/messages.spring.dart`): which of them
/// exist for the resources of a package, and which library is their
/// parent, so the main builder writes the `part` directives of exactly the
/// files the keys builder writes.
abstract final class SpringKeyFiles {
  /// The part with `context.theme`.
  static const themeFile = 'lib/spring_gen/theme.spring.dart';

  /// The part with `context.messages`.
  static const messagesFile = 'lib/spring_gen/messages.spring.dart';

  /// The imports the parts need, which the parent writes for them.
  static const imports = [
    'package:flutter/widgets.dart',
    'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart',
  ];

  /// The code of the parts for the resources [texts] (paths below
  /// `lib/resources/`); problems go to [diagnostics], and a part with an
  /// error is `null`.
  static KeyParts generate(
    Map<String, String> texts,
    KeysDiagnostics diagnostics, {
    LoaderKinds loaderKinds = LoaderKinds.none,
  }) {
    final properties = readProperties(texts, diagnostics);
    final theme = TypedThemeKeys.generate(
      properties,
      diagnostics,
      kinds: loaderKinds,
    );
    final messages = TypedMessageKeys.generate(texts, properties, diagnostics);
    if (diagnostics.errors.isNotEmpty) {
      return (theme: null, messages: null);
    }
    return (
      theme: theme == null
          ? null
          : '${theme.hasTheme ? '$_themeExtension\n' : ''}${theme.code}',
      messages: messages == null ? null : '$_messagesExtension\n$messages',
    );
  }

  static const _themeExtension = '''
/// Typed access to `spring.flutter.theme.*` from any widget.
extension SpringThemeKeys on BuildContext {
  /// The values `spring.flutter.theme.*` declares, from the active
  /// Spring theme; the widget rebuilds when it changes.
  AppTheme get theme => AppTheme._(
    ThemeKeyReader(
      SpringTheme.of(this),
      reduceMotion: MediaQuery.maybeDisableAnimationsOf(this) ?? false,
    ),
  );
}
''';

  static const _messagesExtension = '''
/// Typed access to the messages from any widget.
extension SpringMessageKeys on BuildContext {
  /// The messages, in the current language; the widget rebuilds when it
  /// changes.
  AppMessages get messages => AppMessages._(this);
}
''';

  /// The loader kinds the keys know: the `@ThemeLoaderKind` classes of
  /// the package's own `lib/` (found in the source text, as
  /// [scanLibraries] finds its annotations) and the `loaderKinds` of the
  /// `spring_metadata.json` of the packages it depends on.
  static Future<LoaderKinds> loaderKinds(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final own = <String, ({String name, String className})>{};
    final assets = await buildStep
        .findAssets(Glob('lib/**.dart'))
        .where((asset) => asset.package == package)
        .where((asset) => !asset.path.endsWith('.spring.dart'))
        .toList();
    assets.sort((a, b) => a.path.compareTo(b.path));
    for (final asset in assets) {
      final text = await buildStep.readAsString(asset);
      if (!text.contains('@ThemeLoaderKind')) {
        continue;
      }
      for (final kind in scanLoaderKinds(text)) {
        own.putIfAbsent(
          canonicalName(kind.name),
          () => (name: kind.name, className: kind.className),
        );
      }
    }
    final foreign = <String, String>{};
    final pubspecId = AssetId(package, 'pubspec.yaml');
    if (await buildStep.canRead(pubspecId)) {
      try {
        final pubspec = loadYaml(await buildStep.readAsString(pubspecId));
        final dependencies = pubspec is YamlMap
            ? pubspec['dependencies']
            : null;
        if (dependencies is YamlMap) {
          for (final name in dependencies.keys) {
            final id = AssetId('$name', 'lib/spring_gen/spring_metadata.json');
            if (!await buildStep.canRead(id)) {
              continue;
            }
            final kinds = _kindsOfMetadata(await buildStep.readAsString(id));
            for (final kind in kinds) {
              foreign.putIfAbsent(canonicalName(kind), () => kind);
            }
          }
        }
      } on YamlException {
        // The pubspec is the build's concern, not ours.
      }
    }
    return LoaderKinds(own: own, foreign: foreign);
  }

  static final _loaderKind = RegExp(
    r'@ThemeLoaderKind\(\s*([\x27"])([^\x27"]+)\1\s*\)\s*'
    r'(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:final|base|abstract|interface)\s+)*'
    r'class\s+(\w+)',
  );

  /// The `@ThemeLoaderKind('name') class X` declarations in the source
  /// [text], with the 1-based line of each.
  static List<({String name, String className, int line})> scanLoaderKinds(
    String text,
  ) => [
    for (final match in _loaderKind.allMatches(text))
      (
        name: match[2]!,
        className: match[3]!,
        line: '\n'.allMatches(text.substring(0, match.start)).length + 1,
      ),
  ];

  // The names in `loaderKinds` of a spring_metadata.json.
  static List<String> _kindsOfMetadata(String json) {
    try {
      final data = jsonDecode(json);
      final kinds = data is Map ? data['loaderKinds'] : null;
      return [
        if (kinds is List)
          for (final kind in kinds)
            if (kind is Map && kind['name'] is String) kind['name'] as String,
      ];
    } on FormatException {
      return const [];
    }
  }

  /// The `.dart` files of `lib/` with a `@ComponentScan` or a
  /// `@SpringBootApplication` (the two annotations that make the main
  /// builder write a `.spring.dart`), sorted by path; `boot`
  /// tells the second. `parentLibrary` picks the parent of the key files.
  static Future<List<ScanLibrary>> scanLibraries(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final scan = RegExp(
      r'^\s*@(ComponentScan|SpringBootApplication)\b',
      multiLine: true,
    );
    final boot = RegExp(r'^\s*@SpringBootApplication\b', multiLine: true);
    final result = <ScanLibrary>[];
    final assets = await buildStep
        .findAssets(Glob('lib/**.dart'))
        .where((asset) => asset.package == package)
        .where((asset) => !asset.path.endsWith('.spring.dart'))
        .toList();
    assets.sort((a, b) => a.path.compareTo(b.path));
    for (final asset in assets) {
      final text = await buildStep.readAsString(asset);
      if (scan.hasMatch(text)) {
        result.add((id: asset, boot: boot.hasMatch(text)));
      }
    }
    return result;
  }

  /// The library whose `.spring.dart` the key files are part of: the
  /// `@SpringBootApplication` library if there is one, else the outermost
  /// `@ComponentScan` (the one whose directory holds the others, as nested
  /// scans are supported). Unrelated roots (two applications, or scans in
  /// sibling directories) give an `error` and no parent; no library gives
  /// neither.
  static ({AssetId? parent, String? error}) parentLibrary(
    List<ScanLibrary> scans,
  ) {
    if (scans.isEmpty) {
      return (parent: null, error: null);
    }
    String names(Iterable<ScanLibrary> list) =>
        list.map((s) => s.id.path).join(' and ');
    final boots = scans.where((s) => s.boot).toList();
    if (boots.length > 1) {
      return (
        parent: null,
        error:
            'A package has one @SpringBootApplication library for the typed '
            'keys, found ${names(boots)}: remove one, or move it into its '
            'own package.',
      );
    }
    if (boots.length == 1) {
      return (parent: boots.single.id, error: null);
    }
    String dir(ScanLibrary s) => p.url.dirname(s.id.path);
    for (final candidate in scans) {
      if (scans.every(
        (other) =>
            other == candidate || p.url.isWithin(dir(candidate), other.id.path),
      )) {
        // Same directory is not "within": two scans there are unrelated.
        if (scans.where((s) => dir(s) == dir(candidate)).length == 1) {
          return (parent: candidate.id, error: null);
        }
      }
    }
    return (
      parent: null,
      error:
          'A package has one outermost @ComponentScan library for the typed '
          'keys, found unrelated ${names(scans)}: nest one scan inside the '
          "other's directory, or move one into its own package.",
    );
  }

  /// The generated parent of a scan library: `lib/main.dart` is
  /// `lib/spring_gen/main.spring.dart`.
  static String parentOf(AssetId scanLibrary) =>
      generatedPath(scanLibrary.path);

  /// The path of [file] (below the package) seen from [parent], for a
  /// `part` directive.
  static String partPath(String parent, String file) =>
      p.url.relative(file, from: p.url.dirname(parent));

  /// The path of [parent] seen from the key files (in `lib/spring_gen/`),
  /// for `part of`.
  static String parentPath(String parent) =>
      p.url.relative(parent, from: 'lib/$generatedFolder');

  /// Whether the package of [buildStep] depends on the Flutter starter.
  static Future<bool> usesFlutterStarter(BuildStep buildStep) async {
    final id = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    if (!await buildStep.canRead(id)) {
      return false;
    }
    try {
      final pubspec = loadYaml(await buildStep.readAsString(id));
      if (pubspec is! YamlMap) {
        return false;
      }
      for (final section in const ['dependencies', 'dev_dependencies']) {
        final dependencies = pubspec[section];
        if (dependencies is YamlMap &&
            dependencies.keys.any(
              (name) => '$name'.startsWith('spring_boot_starter_flutter'),
            )) {
          return true;
        }
      }
    } on YamlException {
      return false;
    }
    return false;
  }

  /// The files `spring.config.import` names with `resources:` that are not
  /// in [texts] (the package's own `lib/resources/`): a theme a library
  /// ships, imported as `resources:themes/neon.yml`. They are looked for in
  /// `lib/resources/` of the packages in `dependencies` of the pubspec (a
  /// library embeds its resources in its auto-configuration, so the
  /// application finds them at run time) and added to the result, keyed by
  /// the path as written. What they import goes on the same way. A file
  /// nobody has is skipped here: the application stops on it at start.
  static Future<Map<String, String>> withImports(
    BuildStep buildStep,
    Map<String, String> texts,
  ) async {
    final result = {...texts};
    final pending = importedResourcePaths(result, KeysDiagnostics());
    if (pending.isEmpty) {
      return result;
    }
    final pubspecId = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    final packages = <String>[];
    if (await buildStep.canRead(pubspecId)) {
      try {
        final pubspec = loadYaml(await buildStep.readAsString(pubspecId));
        if (pubspec is YamlMap && pubspec['dependencies'] is YamlMap) {
          packages.addAll(
            [
              for (final name in (pubspec['dependencies'] as YamlMap).keys)
                '$name',
            ],
          );
        }
      } on YamlException {
        // The pubspec is the build's concern, not ours.
      }
    }
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final path = pending.removeAt(0);
      if (!seen.add(path)) {
        continue;
      }
      for (final package in packages) {
        final id = AssetId(package, 'lib/resources/$path');
        if (await buildStep.canRead(id)) {
          result[path] = await buildStep.readAsString(id);
          pending.addAll(importedResourcePaths(result, KeysDiagnostics()));
          break;
        }
      }
    }
    return result;
  }

  /// The paths below `lib/resources/` that `spring.config.import` of [texts]
  /// names with the `resources:` prefix (`optional:` allowed, a `[hint]`
  /// dropped) and that [texts] does not hold. Globs (`*`) and other
  /// prefixes are not followed.
  static List<String> importedResourcePaths(
    Map<String, String> texts,
    KeysDiagnostics diagnostics,
  ) {
    final result = <String>[];
    for (final property in readProperties(texts, diagnostics)) {
      if (property.name != 'spring.config.import' &&
          !property.name.startsWith('spring.config.import[')) {
        continue;
      }
      for (var item in property.value.split(',')) {
        item = item.trim();
        if (item.startsWith('optional:')) {
          item = item.substring('optional:'.length);
        }
        if (!item.startsWith('resources:')) {
          continue;
        }
        var path = item.substring('resources:'.length);
        final hint = path.indexOf('[');
        if (hint != -1) {
          path = path.substring(0, hint);
        }
        path = path.replaceFirst(RegExp('^/+'), '');
        if (path.isEmpty ||
            path.contains('*') ||
            path.endsWith('/') ||
            texts.containsKey(path) ||
            result.contains(path)) {
          continue;
        }
        result.add(path);
      }
    }
    return result;
  }

  static const List<PropertySourceLoader> _loaders = [
    PropertiesPropertySourceLoader(),
    YamlPropertySourceLoader(),
  ];

  /// Every property of the `.properties`, `.yml` and `.yaml` files in
  /// [texts], in the order of the files (sorted by path), whatever their
  /// profile. A file that does not parse is a warning and is skipped.
  static List<ConfigProperty> readProperties(
    Map<String, String> texts,
    KeysDiagnostics diagnostics, {
    bool profilesLast = false,
  }) {
    final result = <ConfigProperty>[];
    // With [profilesLast], a profile's file (`application-web.yml`) comes
    // after the files without one, so its value is the later one, as in
    // the app; else by path.
    int rank(String path) =>
        profilesLast &&
            RegExp(r'(^|/)application-[^./]+\.[^./]+$').hasMatch(path)
        ? 1
        : 0;
    final paths = texts.keys.toList()
      ..sort((a, b) {
        final byRank = rank(a) - rank(b);
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    for (final path in paths) {
      final dot = path.lastIndexOf('.');
      final extension = dot == -1 ? '' : path.substring(dot + 1);
      final loader = _loaders
          .where((loader) => loader.fileExtensions.contains(extension))
          .firstOrNull;
      if (loader == null) {
        continue;
      }
      final List<AbstractPropertySource<Object>> sources;
      try {
        sources = loader.load(path, texts[path]!);
      } on FormatException catch (e) {
        if (!_isMessageFile(path)) {
          diagnostics.warnings.add(
            'lib/resources/$path does not parse (${e.message}): its keys '
            'are not typed.',
          );
        }
        continue;
      }
      for (final source in sources) {
        if (source is! EnumerablePropertySource<Object>) {
          continue;
        }
        for (final name in source.propertyNames) {
          if (source.getProperty(name) case final value?) {
            result.add((file: path, name: name, value: '$value'));
          }
        }
      }
    }
    return result;
  }

  // Message files are read as properties too, but only for their keys.
  static bool _isMessageFile(String path) =>
      path.split('/').last.startsWith('messages');
}
