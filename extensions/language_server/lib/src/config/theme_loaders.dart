import 'dart:io';

import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/config/theme_references.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// The keys each built-in loader kind takes (the starter's
/// `ThemeLoaderSpec`), besides the keys every loader has.
const _builtInLoaderKeys = {
  'spinner': ['color', 'size', 'stroke', 'track', 'animation'],
  'dots': ['color', 'size', 'count', 'gap', 'animation'],
  'pulse': ['color', 'size', 'animation'],
  'bar': ['color', 'track', 'height', 'width', 'radius', 'animation'],
  'skeleton': ['base', 'highlight', 'radius', 'shimmer'],
};

/// The keys every loader has, as the generator's `loaderOwnKeys`.
const loaderCommonKeys = ['kind', 'phases', 'tracks', 'web', 'web-sha256'];

/// What the editor knows of the loaders and the splash of the themes: the
/// keys a kind takes, the names `splash.loader` and `splash.animation`
/// refer to, and the `web:` file of a loader.
final class ThemeLoaders {
  /// Loaders over [model].
  const ThemeLoaders(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  /// The keys a loader of [kind] takes, or `null` when the kind is unknown
  /// or does not list them (a kind of the app's own without `props`).
  List<String>? keysOfKind(String path, String kind) {
    final canon = canonicalName(kind);
    if (_builtInLoaderKeys[canon] case final keys?) {
      return keys;
    }
    for (final custom in model.metadataFor(path).loaderKinds) {
      if (canonicalName(custom.name) == canon) {
        return custom.props;
      }
    }
    return null;
  }

  /// The `loaders.<name>.kind` of each theme of [keys], by `theme|name`.
  static Map<String, String> kindsOf(List<ConfigKey> keys) {
    final result = <String, String>{};
    for (final key in keys) {
      final relative = themeRelative(key.segments);
      if (relative == null ||
          key.value == null ||
          relative.rest.length != 3 ||
          canonicalName(relative.rest[0]) != 'loaders' ||
          canonicalName(relative.rest[2]) != 'kind') {
        continue;
      }
      result['${relative.theme}|${canonicalName(relative.rest[1])}'] =
          key.value!;
    }
    return result;
  }

  /// The names declared below [section] (`loaders`, `animations`) in any
  /// theme of the package and its dependencies.
  List<String> declaredNames(String path, String section) {
    final names = <String>{};
    for (final (_, _, rest) in ThemeReferences(
      model.properties,
      path,
    ).declarations) {
      if (rest.length >= 2 && canonicalName(rest[0]) == section) {
        names.add(rest[1]);
      }
    }
    return names.toList()..sort();
  }

  /// The file of a `web:` path: in the app's directory, else in
  /// `lib/resources/` of a dependency (a library shipping its loader).
  String? webFile(String path, String value) {
    final view = model.metadataFor(path);
    for (final root in [
      model.packages.packageRootOf(path),
      for (final root in view.packageRoots.values) '$root/lib/resources',
    ]) {
      final file = File('$root/$value');
      if (file.existsSync()) {
        return file.path;
      }
    }
    return null;
  }

  /// The `.html` files below `web/` of the app and below `lib/resources/`
  /// of its dependencies, as `web:` paths.
  List<String> webFiles(String path) {
    final result = <String>{};
    final root = model.packages.packageRootOf(path);
    void scan(String base) {
      final directory = Directory(base);
      if (!directory.existsSync()) {
        return;
      }
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.html')) {
          final relative = entity.path.substring(base.length + 1);
          if (relative.startsWith('web/') ||
              relative.startsWith(r'web\') ||
              base != root) {
            result.add(relative.replaceAll(r'\', '/'));
          }
        }
      }
    }

    scan(root);
    for (final dependency in model.metadataFor(path).packageRoots.values) {
      scan('$dependency/lib/resources');
    }
    return result.where((p) => !p.startsWith('build/')).toList()..sort();
  }

  /// Where `splash.loader` / `splash.animation` ([key]) leads: the
  /// `loaders.<name>` or `animations.<name>` it names, of the key's theme
  /// first, then of the root, then of any; for `web:`, the file.
  List<SourceRange> definition(String path, ConfigKey key) {
    final relative = themeRelative(key.segments);
    if (relative == null || key.value == null) {
      return const [];
    }
    final rest = relative.rest.map(canonicalName).toList();
    final value = key.value!.trim();
    if (rest.length == 3 && rest[0] == 'loaders' && rest[2] == 'web') {
      final file = webFile(path, value);
      return file == null ? const [] : [SourceRange(file, 0, 0, 0, 0)];
    }
    final section = sectionNamedBy(rest);
    if (section == null) {
      return const [];
    }
    final wanted = canonicalName(value);
    final matches = [
      for (final (entry, theme, rest) in ThemeReferences(
        model.properties,
        path,
      ).declarations)
        if (rest.length >= 2 &&
            canonicalName(rest[0]) == section &&
            canonicalName(rest[1]) == wanted)
          (entry, theme),
    ];
    List<(PropertyEntry, String?)> pick(bool Function(String?) test) => [
      for (final m in matches)
        if (test(m.$2)) m,
    ];
    var chosen = pick(
      (t) =>
          t != null &&
          relative.theme != null &&
          canonicalName(t) == canonicalName(relative.theme!),
    );
    if (chosen.isEmpty) {
      chosen = pick((t) => t == null);
    }
    if (chosen.isEmpty) {
      chosen = matches;
    }
    // One place per file and theme: the first line of the loader.
    final first = <String, PropertyEntry>{};
    for (final (entry, theme) in chosen) {
      final id = '${entry.path}|$theme';
      final known = first[id];
      if (known == null || entry.line < known.line) {
        first[id] = entry;
      }
    }
    return [
      for (final entry in first.values)
        SourceRange(
          entry.path,
          entry.line,
          entry.keyStart,
          entry.line,
          entry.keyEnd,
        ),
    ];
  }

  /// The section whose names the theme key [rest] (canonical, without the
  /// theme's prefix) refers to: `loaders` for `splash.loader`,
  /// `animations` for `splash.animation`.
  static String? sectionNamedBy(List<String> rest) {
    if (rest.length != 2 || rest[0] != 'splash') {
      return null;
    }
    return switch (rest[1]) {
      'loader' => 'loaders',
      'animation' => 'animations',
      _ => null,
    };
  }
}
