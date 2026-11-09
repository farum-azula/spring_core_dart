import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/analysis/search_analyzer.dart';
import 'package:spring_search_dart/src/index/search_index.dart';
import 'package:spring_search_dart/src/markdown/markdown_search_source.dart';

/// The indexes the build writes for `spring.search.markdown`, one file per
/// language (`lib/resources/spring_gen/search/en.json`): the
/// `SearchService` reads the one of a language instead of reading every
/// page and building its index, a download of one file on the web.
///
/// A file is used only when it was built with the same analyzer and from
/// the same `spring.search.markdown` entries as the app has; otherwise the
/// service builds the index itself, as without a file. The build leaves the
/// files out of the binary: a Flutter app lists their directory under
/// `flutter: assets:`.
///
/// `spring.search.prebuilt=false` writes and reads none.
///
/// Spring has no counterpart.
final class SearchIndexFiles {
  /// The files read through [resources].
  const SearchIndexFiles(this.resources);

  /// The version of the files' format; a file of another is not read.
  static const format = 2;

  /// The directory of the files below `lib/resources/`.
  static const directory = 'spring_gen/search/';

  static const _log = SpringLog('spring_search_dart.SearchIndexFiles');

  /// Reads the files.
  final ResourceLoader resources;

  /// The `resources:` location of the file of [language].
  static String locationOf(String language) =>
      'resources:$directory$language.json';

  /// The file of [index], the index of [language] built with [analyzer]
  /// from the documents of [sources].
  static String encode({
    required String language,
    required SearchAnalyzer analyzer,
    required List<MarkdownSearchSource> sources,
    required SearchIndex index,
  }) {
    // A line per piece, so the app reads it a piece at a time.
    final json = index.toJson();
    final documents = json['documents']! as List;
    final lengths = json['lengths']! as List;
    final terms = (json['terms']! as Map).entries.toList();
    final surfaces = (json['surfaces']! as Map).entries.toList();
    return [
      jsonEncode({
        'format': format,
        'language': language,
        'analyzer': analyzer.name,
        'sources': [for (final source in sources) _signature(source)],
      }),
      jsonEncode({'fields': json['fields']}),
      for (var i = 0; i < documents.length; i += _documents)
        jsonEncode({
          'documents': documents.sublist(
            i,
            (i + _documents).clamp(0, documents.length),
          ),
          'lengths': lengths.sublist(
            i,
            (i + _documents).clamp(0, lengths.length),
          ),
        }),
      for (var i = 0; i < terms.length; i += _terms)
        jsonEncode({
          'terms': Map.fromEntries(
            terms.sublist(i, (i + _terms).clamp(0, terms.length)),
          ),
        }),
      for (var i = 0; i < surfaces.length; i += _terms)
        jsonEncode({
          'surfaces': Map.fromEntries(
            surfaces.sublist(i, (i + _terms).clamp(0, surfaces.length)),
          ),
        }),
    ].join('\n');
  }

  // The documents and the terms of a line: a few milliseconds to read.
  static const _documents = 100;
  static const _terms = 1000;

  /// The index of [language] from its file, when there is one built with
  /// [analyzer] from [sources]; `null` otherwise.
  Future<SearchIndex?> read(
    String language, {
    required SearchAnalyzer analyzer,
    required List<MarkdownSearchSource> sources,
  }) async {
    final location = locationOf(language);
    final resource = resources.getResource(location);
    if (!resource.exists()) {
      return null;
    }
    final List<String> lines;
    final Map<String, Object?> json;
    try {
      lines = const LineSplitter().convert(await resource.readAsString());
      json = jsonDecode(lines.first) as Map<String, Object?>;
    } on Object catch (error) {
      _log.warning('$location is not read: $error');
      return null;
    }
    final reason = _mismatch(json, analyzer, sources);
    if (reason != null) {
      _log.info(
        '$location is not used ($reason): the index is built from the '
        'pages. Build again (dart run build_runner build).',
      );
      return null;
    }
    try {
      return await SearchIndex.fromJsonParts(lines.skip(1), analyzer);
    } on Object catch (error) {
      _log.warning('$location is not read: $error');
      return null;
    }
  }

  static String? _mismatch(
    Map<String, Object?> json,
    SearchAnalyzer analyzer,
    List<MarkdownSearchSource> sources,
  ) {
    if (json['format'] != format) {
      return 'format ${json['format']}, not $format';
    }
    if (json['analyzer'] != analyzer.name) {
      return 'analyzer ${json['analyzer']}, not ${analyzer.name}';
    }
    final expected = jsonEncode([
      for (final source in sources) _signature(source),
    ]);
    if (jsonEncode(json['sources']) != expected) {
      return 'other spring.search.markdown entries';
    }
    return null;
  }

  static Map<String, Object?> _signature(MarkdownSearchSource source) => {
    'location': source.location,
    'exclude': source.exclude,
    'link': source.link,
    'defaultLanguage': source.defaultLanguage,
  };
}
