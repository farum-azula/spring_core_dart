import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:spring_core_dart_generator/src/search_index_builder.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';

/// Writes the files of `spring.resources.prefetch.locations` (globs below
/// `lib/resources/`) into one file, `lib/resources/spring_gen/prefetch/
/// resources.json`, which a Flutter web app downloads once after it is
/// shown and keeps in memory, instead of downloading each file when it is
/// read: a site's pages then open at once.
///
/// The file is a line per piece (a JSON object of paths to texts), so the
/// app reads it a piece at a time without holding the thread that draws.
/// Text files only. The build never embeds it: the app lists its directory
/// under `flutter: assets:`, which is warned about when missing. No
/// locations: no file, and the one written before is deleted.
final class PrefetchBuilder implements Builder {
  /// The builder; [output] writes and deletes the file (on disk unless
  /// given; tests pass their own).
  PrefetchBuilder({SearchIndexOutput? output})
    : _output = output ?? SearchIndexOutput.disk;

  final SearchIndexOutput _output;

  /// The directory of the file below the package.
  static const directory = 'lib/resources/spring_gen/prefetch/';

  /// The file.
  static const file = '${directory}resources.json';

  // The texts of a line: a few milliseconds to read.
  static const int _piece = 200 * 1024;

  @override
  Map<String, List<String>> get buildExtensions => const {r'$package$': []};

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final written = await _write(buildStep, package);
    await _output.deleteOthers(package, directory, written);
  }

  Future<Set<String>> _write(BuildStep buildStep, String package) async {
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final texts = {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    };
    if (!texts.values.any((t) => t.contains('prefetch'))) {
      return const {};
    }
    final String? Function(String key) property;
    try {
      property = readPlatformEnvironment(texts, profiles: const []).getProperty;
    } on Object {
      return const {};
    }
    const key = 'spring.resources.prefetch.locations';
    final globs = [
      for (final pattern in [
        ...?property(key)?.split(','),
        for (var i = 0; property('$key[$i]') != null; i++)
          property('$key[$i]')!,
      ])
        if (pattern.trim().isNotEmpty) Glob(pattern.trim()),
    ];
    if (globs.isEmpty) {
      return const {};
    }
    final paths = [
      for (final path in texts.keys)
        if (globs.any((g) => g.matches(path))) path,
    ]..sort();
    final lines = <String>[
      jsonEncode({'format': 1, 'files': paths.length}),
    ];
    var piece = <String, String>{};
    var size = 0;
    for (final path in paths) {
      piece[path] = texts[path]!;
      size += texts[path]!.length;
      if (size >= _piece) {
        lines.add(jsonEncode(piece));
        piece = {};
        size = 0;
      }
    }
    if (piece.isNotEmpty) {
      lines.add(jsonEncode(piece));
    }
    await _output.write(package, file, lines.join('\n'));
    final assets = await SpringBuilder.flutterAssets(buildStep);
    if (assets != null && !assets.contains(directory)) {
      log.warning(
        'spring.resources.prefetch: $directory is no Flutter asset, so the '
        'app downloads the files one by one. Add to pubspec.yaml, under '
        'flutter: assets:\n    - $directory',
      );
    }
    return {file};
  }
}
