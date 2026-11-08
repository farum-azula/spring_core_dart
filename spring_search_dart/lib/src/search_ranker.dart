import 'package:spring_search_dart/src/search_hit.dart';
import 'package:spring_search_dart/src/search_query.dart';

/// Changes the score of a hit after the index ranked it: newer pages
/// higher, a section of the reference before the guides, a sold-out
/// product lower, the page whose name the query is first. The
/// `SearchRanker` beans run in `@Order`, each on the score the one before
/// gave, with the [SearchQuery] searched.
///
/// ```dart
/// @Component()
/// class ReferenceFirst implements SearchRanker {
///   @override
///   double rank(SearchHit hit, double score, SearchQuery query) =>
///       hit.document.attributes['section'] == 'reference'
///           ? score * 1.5
///           : score;
/// }
/// ```
abstract interface class SearchRanker {
  /// The new score of [hit], from [score], for [query].
  double rank(SearchHit hit, double score, SearchQuery query);
}
