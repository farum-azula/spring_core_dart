import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/analysis/search_analyzer.dart';
import 'package:spring_search_dart/src/index/search_index.dart';
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
/// after a `SearchIndexInvalidatedEvent`. A search in a language without
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

  // The documents, read once, by language; the index of each language,
  // built when that language is first searched (or prepared).
  Future<Map<String, List<SearchDocument>>>? _documents;
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
    final documents = await (_documents ??= _read());
    final key = documents.containsKey(language)
        ? language
        : documents.containsKey(language.split(RegExp('[-_]')).first)
        ? language.split(RegExp('[-_]')).first
        : defaultLanguage;
    final texts = documents[key];
    if (texts == null) {
      return null;
    }
    return await _indexes.putIfAbsent(key, () => _build(key, texts));
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
    final documents = await (_documents ??= _read());
    for (final key in [
      if (documents.containsKey(defaultLanguage)) defaultLanguage,
      ...documents.keys.where((key) => key != defaultLanguage),
    ]) {
      await index(key);
    }
  }

  /// Whether the documents are read (or being read): a build started.
  bool get prepared => _documents != null;

  /// Whether the index of [language] (as the documents name it) is built
  /// or being built.
  bool isIndexed(String language) => _indexes.containsKey(language);

  /// Forgets the documents and the indexes: the next search reads and
  /// builds them again.
  void invalidate() {
    _documents = null;
    _indexes.clear();
  }

  Future<Map<String, List<SearchDocument>>> _read() async {
    final watch = Stopwatch()..start();
    final byLanguage = <String, List<SearchDocument>>{};
    // A source may give its documents without a real pause (resources read
    // from memory): a turn of the event loop every few milliseconds lets
    // the app draw its frames meanwhile.
    final slice = Stopwatch()..start();
    for (final source in sources) {
      await for (final document in source.documents()) {
        byLanguage
            .putIfAbsent(document.language ?? defaultLanguage, () => [])
            .add(document);
        if (slice.elapsed >= _slice) {
          await Future<void>.delayed(Duration.zero);
          slice.reset();
        }
      }
    }
    _log.debug(() {
      final counts = [
        for (final MapEntry(:key, :value) in byLanguage.entries)
          '$key: ${value.length}',
      ];
      return 'Search documents read in ${watch.elapsedMilliseconds} ms '
          '(${counts.join('; ')})';
    });
    return byLanguage;
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
