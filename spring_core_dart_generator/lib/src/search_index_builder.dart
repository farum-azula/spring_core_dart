import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:build/build.dart' hide Resource;
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';
import 'package:spring_search_dart/spring_search_dart.dart';

/// Writes the search index of `spring.search.markdown`, a file per
/// language in `lib/resources/spring_gen/search/` ([SearchIndexFiles]),
/// which the `SearchService` reads instead of reading every page and
/// building the index while the app runs: on the web, one download and no
/// work on the thread that draws.
///
/// The documents are those the app's `MarkdownSearchSource`s would read,
/// cut and analyzed by the same code (the app's `spring_search_dart`),
/// with the analyzers of `spring.search.analyzers`; a language whose
/// analyzer is an app's own bean gets no file. A location other than
/// `resources:` writes none. The build never embeds the files: a Flutter
/// app lists the directory under `flutter: assets:`, which is warned about
/// when missing.
///
/// `spring.search.prebuilt=false` (or `spring.search.enabled=false`)
/// writes none and deletes those written before.
final class SearchIndexBuilder implements Builder {
  /// The builder; [output] writes and deletes the files (on disk unless
  /// given; tests pass their own).
  SearchIndexBuilder({SearchIndexOutput? output})
    : _output = output ?? const _DiskOutput();

  final SearchIndexOutput _output;

  /// The directory of the files below the package.
  static const directory = 'lib/resources/${SearchIndexFiles.directory}';

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
    if (!texts.values.any((t) => t.contains('search'))) {
      return const {};
    }
    final String? Function(String key) property;
    try {
      property = readPlatformEnvironment(texts, profiles: const []).getProperty;
    } on Object {
      return const {};
    }
    bool off(String key) =>
        property('spring.search.$key')?.trim().toLowerCase() == 'false';
    if (off('enabled') || off('prebuilt')) {
      return const {};
    }
    final defaultLanguage =
        property('spring.search.default-language')?.trim() ?? 'en';
    final resolver = _Texts(texts);
    final sources = <MarkdownSearchSource>[];
    for (var i = 0; ; i++) {
      final prefix = 'spring.search.markdown[$i]';
      final location = property('$prefix.location')?.trim();
      if (location == null) {
        break;
      }
      if (!location.startsWith(RegExp(r'resources\*?:'))) {
        log.info(
          'No search index is written: $prefix.location is not in '
          'resources: ($location).',
        );
        return const {};
      }
      sources.add(
        MarkdownSearchSource(
          resolver,
          location: location,
          exclude: _list(property, '$prefix.exclude'),
          link: property('$prefix.link')?.trim() ?? '/{path}',
          defaultLanguage: defaultLanguage,
        ),
      );
    }
    if (sources.isEmpty) {
      return const {};
    }
    final languages = {for (final source in sources) ...source.languages};
    final written = <String>{};
    for (final language in languages.toList()..sort()) {
      final name =
          property('spring.search.analyzers.$language')?.trim() ??
          property(
            'spring.search.analyzers.${language.split(RegExp('[-_]')).first}',
          )?.trim();
      final SearchAnalyzer analyzer;
      try {
        analyzer = SearchAnalyzers(
          languages: {language: ?name},
        ).of(language);
      } on ArgumentError {
        // An app's own analyzer, which only the running app has.
        continue;
      }
      final documents = [
        for (final source in sources)
          if (source.languages.contains(language))
            ...await source.documentsIn(language).toList(),
      ];
      final index = SearchIndex.build(documents, analyzer);
      final path = '$directory$language.json';
      await _output.write(
        package,
        path,
        SearchIndexFiles.encode(
          language: language,
          analyzer: analyzer,
          sources: sources,
          index: index,
        ),
      );
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

  static List<String> _list(String? Function(String) property, String key) => [
    ...?property(
      key,
    )?.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty),
    for (var i = 0; property('$key[$i]') != null; i++)
      property('$key[$i]')!.trim(),
  ];
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

// The text files of lib/resources/ as resources: locations, for the
// Markdown sources.
final class _Texts implements ResourcePatternResolver {
  _Texts(this._texts);

  final Map<String, String> _texts;
  final _matcher = AntPathMatcher();

  static String _path(String location) =>
      location.replaceFirst(RegExp(r'^resources\*?:/?'), '');

  @override
  Resource getResource(String location) {
    final path = _path(location);
    final text = _texts[path];
    return text == null
        ? DescriptiveResource('resources:$path')
        : _Text(path, text);
  }

  @override
  List<Resource> getResources(String locationPattern) {
    final pattern = _path(locationPattern);
    return [
      for (final MapEntry(:key, :value) in _texts.entries)
        if (_matcher.match(pattern, key)) _Text(key, value),
    ];
  }
}

final class _Text extends AbstractResource implements ContextResource {
  _Text(this.pathWithinContext, this._text);

  @override
  final String pathWithinContext;

  final String _text;

  @override
  bool exists() => true;

  @override
  String get description => 'resources:$pathWithinContext';

  @override
  String? get filename => pathWithinContext.split('/').last;

  @override
  bool get supportsSyncRead => true;

  @override
  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  @override
  Uint8List readAsBytesSync() => utf8.encode(_text);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async => _text;
}
