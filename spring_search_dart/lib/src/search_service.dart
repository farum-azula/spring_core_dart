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

  Future<Map<String, SearchIndex>>? _indexes;

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
            rankers.fold(hit.score, (score, ranker) => ranker.rank(hit, score)),
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
  /// documents; `null` when there are none at all.
  Future<SearchIndex?> index(String language) async {
    final indexes = await (_indexes ??= _build());
    return indexes[language] ??
        indexes[language.split(RegExp('[-_]')).first] ??
        indexes[defaultLanguage];
  }

  /// Forgets the indexes: the next search builds them again.
  void invalidate() => _indexes = null;

  Future<Map<String, SearchIndex>> _build() async {
    final watch = Stopwatch()..start();
    final byLanguage = <String, List<SearchDocument>>{};
    for (final source in sources) {
      await for (final document in source.documents()) {
        byLanguage
            .putIfAbsent(document.language ?? defaultLanguage, () => [])
            .add(document);
      }
    }
    final indexes = {
      for (final MapEntry(key: language, value: documents)
          in byLanguage.entries)
        language: SearchIndex.build(documents, analyzers.of(language)),
    };
    _log.debug(() {
      final sizes = [
        for (final MapEntry(key: language, value: index) in indexes.entries)
          _size(language, index),
      ];
      return 'Search index built in ${watch.elapsedMilliseconds} ms '
          '(${sizes.join('; ')})';
    });
    return indexes;
  }

  static String _size(String language, SearchIndex index) =>
      '$language: ${index.documents.length} documents, '
      '${index.termCount} terms';

  @override
  bool supportsEvent(Object event) => event is SearchIndexInvalidatedEvent;

  @override
  void onApplicationEvent(Object event) => invalidate();
}
