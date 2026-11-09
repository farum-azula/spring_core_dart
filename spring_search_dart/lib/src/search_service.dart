import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/analysis/search_analyzer.dart';
import 'package:spring_search_dart/src/index/search_index.dart';
import 'package:spring_search_dart/src/index/search_index_files.dart';
import 'package:spring_search_dart/src/markdown/markdown_search_source.dart';
import 'package:spring_search_dart/src/search_document.dart';
import 'package:spring_search_dart/src/search_document_source.dart';
import 'package:spring_search_dart/src/search_hit.dart';
import 'package:spring_search_dart/src/search_index_invalidated_event.dart';
import 'package:spring_search_dart/src/search_query.dart';
import 'package:spring_search_dart/src/search_ranker.dart';

/// Searches the documents of the `SearchDocumentSource` beans: the bean an
/// application asks.
///
/// ```dart
/// final hits = await search.search('bean factory', language: 'en');
/// for (final hit in hits) {
///   print('${hit.document.title}: ${hit.snippet('body').text}');
/// }
/// ```
///
/// The index is built at the first search, one per language, and again
/// after a `SearchIndexInvalidatedEvent`; the index the build wrote for a
/// language ([files]) is read instead when the documents are those of
/// `spring.search.markdown` only. A search in a language without
/// documents searches the default language's.
final class SearchService implements GenericApplicationListener {
  /// Searches the documents of [sources], analyzed by [analyzers], ranked
  /// again by [rankers] in order.
  SearchService(
    this.sources, {
    SearchAnalyzers? analyzers,
    this.rankers = const [],
    this.defaultLanguage = 'en',
    this.weights = defaultWeights,
    this.fuzzy = 1,
    this.maxHits = 20,
    this.operator = SearchOperator.and,
    this.collapseBy,
    this.files,
  }) : analyzers = analyzers ?? SearchAnalyzers();

  /// The weights when `spring.search.fields` names none.
  static const defaultWeights = {'title': 8.0, 'heading': 4.0, 'body': 1.0};

  static const _log = SpringLog('spring_search_dart.SearchService');

  static const _slice = Duration(milliseconds: 8);

  /// Where the documents come from.
  final List<SearchDocumentSource> sources;

  /// The analyzer of each language.
  final SearchAnalyzers analyzers;

  /// Change the scores, in order.
  final List<SearchRanker> rankers;

  /// The language of documents and searches that name none.
  final String defaultLanguage;

  /// The weight of each field.
  final Map<String, double> weights;

  /// The typos a word may have.
  final int fuzzy;

  /// The most hits of a search.
  final int maxHits;

  /// Whether every word must match.
  final SearchOperator operator;

  /// The attribute whose value only its best hit keeps.
  final String? collapseBy;

  /// The indexes the build wrote; `null`: none is read.
  final SearchIndexFiles? files;

  // The documents of the sources that do not know their languages, read
  // once, by language; those of each language of the other sources, read
  // when that language is first searched; the index of each language,
  // built then too (or prepared).
  Future<Map<String, List<SearchDocument>>>? _others;
  final _documents = <String, Future<List<SearchDocument>>>{};
  final _indexes = <String, Future<SearchIndex>>{};

  /// The hits of [query] in [language], best first, at most [limit]
  /// (`spring.search.max-hits`).
  Future<List<SearchHit>> search(
    String query, {
    String? language,
    int? limit,
  }) async {
    final parsed = SearchQuery.parse(query);
    if (parsed.isEmpty) {
      return const [];
    }
    final index = await this.index(language ?? defaultLanguage);
    if (index == null) {
      return const [];
    }
    var hits = index.search(
      parsed,
      weights: weights,
      fuzzy: fuzzy,
      operator: operator,
    );
    if (rankers.isNotEmpty) {
      hits = [
        for (final hit in hits)
          hit.withScore(
            rankers.fold(
              hit.score,
              (score, ranker) => ranker.rank(hit, score, parsed),
            ),
          ),
      ]..sort((a, b) => b.score.compareTo(a.score));
    }
    final key = collapseBy;
    if (key != null) {
      final seen = <String>{};
      hits = hits.where((hit) {
        final value = hit.document.attributes[key];
        return value == null || seen.add(value);
      }).toList();
    }
    return hits.take(limit ?? maxHits).toList();
  }

  /// The index of [language], or the default language's when it has no
  /// documents; `null` when there are none at all. Built the first time
  /// it is asked for: a search in one language waits for its index only.
  Future<SearchIndex?> index(String language) async {
    final languages = await _languages();
    final short = language.split(RegExp('[-_]')).first;
    final key = languages.contains(language)
        ? language
        : languages.contains(short)
        ? short
        : defaultLanguage;
    if (!languages.contains(key)) {
      return null;
    }
    return await _indexes.putIfAbsent(
      key,
      () async =>
          await _prebuilt(key) ?? await _build(key, await _documentsOf(key)),
    );
  }

  /// Starts building the index of [language] now (every language when
  /// none is named, the default one first), when it is not built or being
  /// built; completes when it is. A search waits for the same build. An
  /// app calls it when its search opens, so the first word typed finds the
  /// index ready; `spring.search.indexing` builds at the start (`start`)
  /// or right after it, behind the app (`background`).
  Future<void> prepare({String? language}) async {
    if (language != null) {
      await index(language);
      return;
    }
    final languages = await _languages();
    for (final key in [
      if (languages.contains(defaultLanguage)) defaultLanguage,
      ...languages.where((key) => key != defaultLanguage),
    ]) {
      await index(key);
    }
  }

  /// Whether the documents are read (or being read): a build started.
  bool get prepared => _others != null;

  /// Whether the index of [language] (as the documents name it) is built
  /// or being built.
  bool isIndexed(String language) => _indexes.containsKey(language);

  /// Forgets the documents and the indexes: the next search reads and
  /// builds them again.
  void invalidate() {
    _others = null;
    _documents.clear();
    _indexes.clear();
  }

  // The languages of the documents: those the sources know, and those of
  // the documents of the others.
  Future<Set<String>> _languages() async {
    final others = await (_others ??= _readOthers());
    return {
      for (final source in sources)
        if (source is LanguageSearchDocumentSource) ...source.languages,
      ...others.keys,
    };
  }

  // The documents in [language]: those of the sources that know their
  // languages, read now, and those of the others.
  Future<List<SearchDocument>> _documentsOf(String language) =>
      _documents.putIfAbsent(language, () async {
        final watch = Stopwatch()..start();
        final documents = [...?(await _others)?[language]];
        final slice = Stopwatch()..start();
        for (final source in sources) {
          if (source is! LanguageSearchDocumentSource ||
              !source.languages.contains(language)) {
            continue;
          }
          await for (final document in source.documentsIn(language)) {
            documents.add(document);
            await _pause(slice);
          }
        }
        _log.debug(
          () =>
              'Search documents read in ${watch.elapsedMilliseconds} ms '
              '($language: ${documents.length})',
        );
        return documents;
      });

  // The index of [language] the build wrote, when its documents all come
  // from the Markdown sources.
  Future<SearchIndex?> _prebuilt(String language) async {
    final files = this.files;
    if (files == null || ((await _others)?[language]?.isNotEmpty ?? false)) {
      return null;
    }
    final markdown = <MarkdownSearchSource>[];
    for (final source in sources) {
      if (source is MarkdownSearchSource) {
        markdown.add(source);
      } else if (source is LanguageSearchDocumentSource &&
          source.languages.contains(language)) {
        return null;
      }
    }
    if (markdown.isEmpty) {
      return null;
    }
    final watch = Stopwatch()..start();
    final index = await files.read(
      language,
      analyzer: analyzers.of(language),
      sources: markdown,
    );
    if (index != null) {
      _log.debug(
        () =>
            'Search index read in ${watch.elapsedMilliseconds} ms '
            '(${_size(language, index)})',
      );
    }
    return index;
  }

  Future<Map<String, List<SearchDocument>>> _readOthers() async {
    final byLanguage = <String, List<SearchDocument>>{};
    final slice = Stopwatch()..start();
    for (final source in sources) {
      if (source is LanguageSearchDocumentSource) {
        continue;
      }
      await for (final document in source.documents()) {
        byLanguage
            .putIfAbsent(document.language ?? defaultLanguage, () => [])
            .add(document);
        await _pause(slice);
      }
    }
    return byLanguage;
  }

  // A source may give its documents without a real pause (resources read
  // from memory): a turn of the event loop every few milliseconds lets the
  // app draw its frames meanwhile.
  static Future<void> _pause(Stopwatch slice) async {
    if (slice.elapsed >= _slice) {
      await Future<void>.delayed(Duration.zero);
      slice.reset();
    }
  }

  Future<SearchIndex> _build(
    String language,
    List<SearchDocument> documents,
  ) async {
    final watch = Stopwatch()..start();
    final index = await SearchIndex.buildAsync(
      documents,
      analyzers.of(language),
    );
    _log.debug(
      () =>
          'Search index built in ${watch.elapsedMilliseconds} ms '
          '(${_size(language, index)})',
    );
    return index;
  }

  static String _size(String language, SearchIndex index) =>
      '$language: ${index.documents.length} documents, '
      '${index.termCount} terms';

  @override
  bool supportsEvent(Object event) => event is SearchIndexInvalidatedEvent;

  @override
  void onApplicationEvent(Object event) => invalidate();
}
