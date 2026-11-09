import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';

/// Makes the index files from a request (the pages and the
/// `spring.search.*` settings); by language, `null` when it failed.
typedef SearchIndexRunner = Future<Map<String, String>?> Function(
  String package,
  Map<String, Object?> request,
);

/// Writes the search index of `spring.search.markdown`, a file per
/// language in `lib/resources/spring_gen/search/` (`SearchIndexFiles` of
/// `spring_search_dart`), which the `SearchService` reads instead of
/// reading every page and building the index while the app runs: on the
/// web, one download and no work on the thread that draws.
///
/// The index is made by the app's own `spring_search_dart` (`dart run
/// spring_search_dart:search_index` in the app's package), so it is cut and
/// analyzed by the code that searches it, and the generator does not depend
/// on the search. A package without `spring_search_dart` gets nothing. A
/// language whose analyzer is an app's own bean gets no file, nor does any
/// when a location is not `resources:`. The build never embeds the files:
/// a Flutter app lists the directory under `flutter: assets:`, which is
/// warned about when missing.
///
/// `spring.search.prebuilt=false` (or `spring.search.enabled=false`)
/// writes none and deletes those written before.
final class SearchIndexBuilder implements Builder {
  /// The builder; [output] writes and deletes the files (on disk unless
  /// given), [runner] makes them (`dart run spring_search_dart:search_index`
  /// unless given; tests pass their own).
  SearchIndexBuilder({SearchIndexOutput? output, SearchIndexRunner? runner})
    : _output = output ?? const _DiskOutput(),
      _runner = runner ?? _run;

  final SearchIndexOutput _output;
  final SearchIndexRunner _runner;

  /// The directory of the files below the package.
  static const directory = 'lib/resources/spring_gen/search/';

  @override
  Map<String, List<String>> get buildExtensions => const {r'$package$': []};

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final written = await _write(buildStep, package);
    if (written != null) {
      await _output.deleteOthers(package, directory, written);
    }
  }

  // The files written; `null` when making them failed (those of a build
  // before stay).
  Future<Set<String>?> _write(BuildStep buildStep, String package) async {
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final texts = {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    };
    if (!texts.values.any((t) => t.contains('search'))) {
      return const {};
    }
    final StandardEnvironment environment;
    try {
      environment = readPlatformEnvironment(texts, profiles: const []);
    } on Object {
      return const {};
    }
    final property = environment.getProperty;
    bool off(String key) =>
        property('spring.search.$key')?.trim().toLowerCase() == 'false';
    if (off('enabled') || off('prebuilt')) {
      return const {};
    }
    final markdown = <Map<String, Object?>>[];
    for (var i = 0; ; i++) {
      final prefix = 'spring.search.markdown[$i]';
      final location = property('$prefix.location')?.trim();
      if (location == null) {
        break;
      }
      markdown.add({
        'location': location,
        'exclude': _list(property, '$prefix.exclude'),
        'link': property('$prefix.link')?.trim() ?? '/{path}',
      });
    }
    if (markdown.isEmpty) {
      return const {};
    }
    // spring.search.analyzers.<language>, in any of the files.
    const analyzer = 'spring.search.analyzers.';
    final analyzers = <String, String>{
      for (final source in environment.propertySources)
        if (source is EnumerablePropertySource<Object>)
          for (final name in source.propertyNames)
            if (name.startsWith(analyzer))
              name.substring(analyzer.length): ?property(name)?.trim(),
    };
    final files = await _runner(package, {
      'texts': {
        for (final MapEntry(:key, :value) in texts.entries)
          if (key.endsWith('.md')) key: value,
      },
      'markdown': markdown,
      'analyzers': analyzers,
      'defaultLanguage':
          property('spring.search.default-language')?.trim() ?? 'en',
    });
    if (files == null) {
      return null;
    }
    final written = <String>{};
    for (final MapEntry(key: language, value: content) in files.entries) {
      final path = '$directory$language.json';
      await _output.write(package, path, content);
      written.add(path);
    }
    final assets = await SpringBuilder.flutterAssets(buildStep);
    if (written.isNotEmpty && assets != null && !assets.contains(directory)) {
      log.warning(
        'The search index ($directory) is no Flutter asset, so the app '
        'builds the index itself. Add to pubspec.yaml, under flutter: '
        'assets:\n    - $directory',
      );
    }
    return written;
  }

  static const _timeout = Duration(minutes: 3);
  static const _packages = '.dart_tool/package_config.json';

  static List<String> _list(String? Function(String) property, String key) => [
    ...?property(
      key,
    )?.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty),
    for (var i = 0; property('$key[$i]') != null; i++)
      property('$key[$i]')!.trim(),
  ];

  // Runs the index writer of the app's spring_search_dart in the app's
  // package; nothing for a package without it.
  static Future<Map<String, String>?> _run(
    String package,
    Map<String, Object?> request,
  ) async {
    final directories = PackageDirectories.current;
    final root = directories.directoryOf(package);
    final search = directories.directoryOf('spring_search_dart');
    if (root == null || search == null) {
      return const {};
    }
    final work = io.Directory.fromUri(
      root.resolve('.dart_tool/spring/search_index/'),
    )..createSync(recursive: true);
    final requestFile = io.File(p.join(work.path, 'request.json'))
      ..writeAsStringSync(jsonEncode(request));
    final responseFile = io.File(p.join(work.path, 'response.json'));
    if (responseFile.existsSync()) {
      responseFile.deleteSync();
    }
    // The dart of the SDK running the build (next to dartaotruntime when
    // the build script is compiled ahead of time), on the script itself
    // with the app's packages: no snapshot of `dart run` to make or lock.
    final dart = p.join(
      p.dirname(io.Platform.resolvedExecutable),
      io.Platform.isWindows ? 'dart.exe' : 'dart',
    );
    final process = await io.Process.start(dart, [
      '--packages=${io.File.fromUri(root.resolve(_packages)).path}',
      io.File.fromUri(search.resolve('bin/search_index.dart')).path,
      requestFile.path,
      responseFile.path,
    ], workingDirectory: io.Directory.fromUri(root).path);
    unawaited(process.stdin.close());
    final out = StringBuffer();
    final drained = [
      process.stdout.transform(utf8.decoder).forEach(out.write),
      process.stderr.transform(utf8.decoder).forEach(out.write),
    ];
    final exitCode = await process.exitCode.timeout(
      _timeout,
      onTimeout: () {
        process.kill();
        out.write('no answer in ${_timeout.inMinutes} minutes');
        return -1;
      },
    );
    await Future.wait(drained).timeout(
      const Duration(seconds: 5),
      onTimeout: () => const [],
    );
    final result = (exitCode: exitCode, stderr: out, stdout: '');
    if (result.exitCode != 0 || !responseFile.existsSync()) {
      log.warning(
        'The search index is not written (exit code ${result.exitCode}): '
        '${result.stderr}${result.stdout}',
      );
      return null;
    }
    return (jsonDecode(responseFile.readAsStringSync()) as Map)
        .cast<String, String>();
  }
}

/// Where [SearchIndexBuilder] writes.
abstract interface class SearchIndexOutput {
  /// Writes [content] to [path] below [package]'s directory.
  Future<void> write(String package, String path, String content);

  /// Deletes the files of [directory] but [kept].
  Future<void> deleteOthers(String package, String directory, Set<String> kept);
}

final class _DiskOutput implements SearchIndexOutput {
  const _DiskOutput();

  io.File? _file(String package, String path) =>
      PackageDirectories.current.file(AssetId(package, path));

  @override
  Future<void> write(String package, String path, String content) async {
    final file = _file(package, path);
    if (file == null) {
      log.warning(
        'The directory of $package is not found; $path is not '
        'written.',
      );
      return;
    }
    if (file.existsSync() && await file.readAsString() == content) {
      return;
    }
    await io.Directory(file.parent.path).create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> deleteOthers(
    String package,
    String directory,
    Set<String> kept,
  ) async {
    final marker = _file(package, '${directory}x');
    if (marker == null || !marker.parent.existsSync()) {
      return;
    }
    for (final entity in marker.parent.listSync()) {
      final name = entity.uri.pathSegments.last;
      if (entity is io.File &&
          name.endsWith('.json') &&
          !kept.contains('$directory$name')) {
        await entity.delete();
      }
    }
  }
}
