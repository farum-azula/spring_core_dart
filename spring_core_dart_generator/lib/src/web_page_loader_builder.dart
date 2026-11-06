import 'dart:convert';

import 'package:build/build.dart' hide Resource;
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/theme_references.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart'
    show readPlatformEnvironment;
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:spring_core_dart_generator/src/web_page_loader.dart';
import 'package:yaml/yaml.dart';

/// Reads and writes the files of the app's own directory (not `lib/`)
/// for [WebPageLoaderBuilder]: `web/index.html` and the `web:` files of
/// loaders. The disk by default; tests pass files held in memory.
abstract interface class WebPageFiles {
  /// The text of [path] below the directory of [package], or `null`.
  Future<String?> read(BuildStep buildStep, String package, String path);

  /// Writes [content] to [path] below the directory of [package].
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  );
}

final class _DiskPageFiles implements WebPageFiles {
  const _DiskPageFiles();

  @override
  Future<String?> read(BuildStep buildStep, String package, String path) async {
    final id = AssetId(package, path);
    // Read as an asset when the build sees it, so a change reruns the step.
    if (await buildStep.canRead(id)) {
      return await buildStep.readAsString(id);
    }
    final file = PackageDirectories.current.file(id);
    return file != null && file.existsSync() ? await file.readAsString() : null;
  }

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async {
    final file = PackageDirectories.current.file(AssetId(package, path));
    if (file == null) {
      log.warning(
        'The directory of package $package is not found in '
        '.dart_tool/package_config.json; $path is not written.',
      );
      return;
    }
    await file.writeAsString(content);
  }
}

// A `web:` file a library ships with its theme, in `lib/resources/` of a
// dependency, when the app has none of that name.
Future<String?> _fromDependency(BuildStep buildStep, String path) async {
  final id = AssetId(buildStep.inputId.package, 'pubspec.yaml');
  if (!await buildStep.canRead(id)) {
    return null;
  }
  try {
    final pubspec = loadYaml(await buildStep.readAsString(id));
    final dependencies = pubspec is YamlMap ? pubspec['dependencies'] : null;
    if (dependencies is! YamlMap) {
      return null;
    }
    for (final name in dependencies.keys) {
      final asset = AssetId('$name', 'lib/resources/$path');
      if (await buildStep.canRead(asset)) {
        return await buildStep.readAsString(asset);
      }
    }
  } on YamlException {
    // The pubspec is the build's concern, not ours.
  }
  return null;
}

/// Writes the page loader of the active theme's `splash` into the app's
/// `web/index.html` (see [WebPageLoader]): a block between
/// `<!-- spring:loader:start -->` and `<!-- spring:loader:end -->`,
/// inserted after `<body>` when the markers are missing, rewritten on
/// every build and removed when the theme has no splash. The rest of the
/// file is never touched; a page that does not exist is not created.
///
/// It runs for a package that depends on `spring_boot_starter_flutter`,
/// reads `lib/resources/` as the keys builder does, and never fails a
/// build: what it cannot use is a warning.
///
/// Spring has no counterpart.
final class WebPageLoaderBuilder implements Builder {
  /// Creates the builder; [files] reads and writes the page (on disk
  /// unless given).
  WebPageLoaderBuilder({WebPageFiles? files})
    : _files = files ?? const _DiskPageFiles();

  final WebPageFiles _files;

  /// The page the block goes into.
  static const pagePath = 'web/index.html';

  // No declared outputs, as for web_dev_config.yaml: the file lives
  // outside lib/ and is the app's own.
  @override
  Map<String, List<String>> get buildExtensions => const {r'$package$': []};

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    if (!await SpringKeyFiles.usesFlutterStarter(buildStep)) {
      return;
    }
    final page = await _files.read(buildStep, package, pagePath);
    if (page == null) {
      return;
    }
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final texts = await SpringKeyFiles.withImports(buildStep, {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    });
    final diagnostics = KeysDiagnostics();
    final set = ThemeSet.read(
      SpringKeyFiles.readProperties(texts, diagnostics),
      diagnostics,
    );
    // Files the loaders name, read before the (synchronous) generation.
    final files = <String, String?>{};
    if (set != null) {
      for (final path in WebPageLoader.webFiles(set)) {
        files[path] =
            await _files.read(buildStep, package, path) ??
            await _fromDependency(buildStep, path);
      }
    }
    final block = set == null
        ? null
        : WebPageLoader.generate(
            set,
            diagnostics,
            readFile: (path) => files[path],
          );
    final problems = <String>[];
    final loaded = WebPageLoader.apply(page, block, problem: problems.add);
    // The head and the manifest from spring.flutter.app.* and the theme.
    final app = _appText(texts);
    final colors = set == null
        ? null
        : WebPageLoader.pageColors(set, diagnostics);
    final updated = loaded == null
        ? null
        : WebPageHead.html(
            loaded,
            title: app.title,
            description: app.description,
            themeColor: colors?.primary,
          );
    await _manifest(buildStep, package, app, colors);
    // Theme errors are the typed keys' to report.
    diagnostics.warnings.forEach(log.warning);
    problems.forEach(log.warning);
    if (updated != null && updated != page) {
      await _files.write(buildStep, package, pagePath, updated);
      log.info(
        block == null
            ? 'Removed the page loader from $pagePath: the active theme has '
                  'no splash.'
            : 'Wrote the page loader of the splash into $pagePath.',
      );
    }
  }

  // spring.flutter.app.title and .description as the app reads them in a
  // browser; none when the config cannot be read (its own builders say
  // why).
  static ({String? title, String? description}) _appText(
    Map<String, String> texts,
  ) {
    try {
      final environment = readPlatformEnvironment(
        texts,
        profiles: const ['web'],
      );
      String? value(String key) {
        final text = environment.getProperty(key)?.trim();
        return text == null || text.isEmpty ? null : text;
      }

      return (
        title: value('spring.flutter.app.title'),
        description: value('spring.flutter.app.description'),
      );
    } on Exception {
      return (title: null, description: null);
    }
  }

  Future<void> _manifest(
    BuildStep buildStep,
    String package,
    ({String? title, String? description}) app,
    ({String primary, String surface})? colors,
  ) async {
    const path = 'web/manifest.json';
    final manifest = await _files.read(buildStep, package, path);
    if (manifest == null) {
      return;
    }
    final updated = WebPageHead.manifest(
      manifest,
      title: app.title,
      description: app.description,
      themeColor: colors?.primary,
      backgroundColor: colors?.surface,
    );
    if (updated == null) {
      log.warning('$path is no JSON object; it is left as it is.');
      return;
    }
    // Only a value of the configuration changes the file (not the layout).
    if (jsonEncode(jsonDecode(updated)) != jsonEncode(jsonDecode(manifest))) {
      await _files.write(buildStep, package, path, updated);
    }
  }
}
