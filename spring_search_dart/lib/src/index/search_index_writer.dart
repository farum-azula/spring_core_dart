import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/analysis/search_analyzer.dart';
import 'package:spring_search_dart/src/index/search_index.dart';
import 'package:spring_search_dart/src/index/search_index_files.dart';
import 'package:spring_search_dart/src/markdown/markdown_search_source.dart';

/// One `spring.search.markdown[n]` entry, as the build reads it.
typedef MarkdownEntry = ({String location, List<String> exclude, String link});

/// Makes the files of [SearchIndexFiles] at build time, from the text files
/// of `lib/resources/`: the generator runs it (`dart run
/// spring_search_dart:search_index`) in the app's own package, so the
/// index is cut and analyzed by the code that searches it.
///
/// Spring has no counterpart.
abstract final class SearchIndexWriter {
  /// The file of each language of [markdown] by language, the pages read
  /// from [texts] (paths below `lib/resources/`), analyzed as
  /// `spring.search.analyzers` ([analyzers]) says. A language whose
  /// analyzer is no built-in one (an app's own bean) gets no file; nor
  /// does any language when a location is not `resources:`.
  static Future<Map<String, String>> build({
    required Map<String, String> texts,
    required List<MarkdownEntry> markdown,
    Map<String, String> analyzers = const {},
    String defaultLanguage = 'en',
  }) async {
    if (markdown.any((e) => !e.location.startsWith(RegExp(r'resources\*?:')))) {
      return const {};
    }
    final resolver = _Texts(texts);
    final sources = [
      for (final entry in markdown)
        MarkdownSearchSource(
          resolver,
          location: entry.location,
          exclude: entry.exclude,
          link: entry.link,
          defaultLanguage: defaultLanguage,
        ),
    ];
    final languages = {for (final source in sources) ...source.languages};
    final files = <String, String>{};
    for (final language in languages.toList()..sort()) {
      final name =
          analyzers[language] ??
          analyzers[language.split(RegExp('[-_]')).first];
      final SearchAnalyzer analyzer;
      try {
        analyzer = SearchAnalyzers(
          languages: {language: ?name},
        ).of(language);
      } on ArgumentError {
        continue;
      }
      final documents = [
        for (final source in sources)
          if (source.languages.contains(language))
            ...await source.documentsIn(language).toList(),
      ];
      files[language] = SearchIndexFiles.encode(
        language: language,
        analyzer: analyzer,
        sources: sources,
        index: SearchIndex.build(documents, analyzer),
      );
    }
    return files;
  }
}

// The text files of lib/resources/ as resources: locations.
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
