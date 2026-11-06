import 'package:spring_search_dart/src/search_hit.dart';

/// Changes the score of a hit after the index ranked it: newer pages
/// higher, a section of the reference before the guides, a sold-out
/// product lower. The `SearchRanker` beans run in `@Order`, each on the
/// score the one before gave.
///
/// ```dart
/// @Component()
/// class ReferenceFirst implements SearchRanker {
///   @override
///   double rank(SearchHit hit, double score) =>
///       hit.document.attributes['section'] == 'reference'
///           ? score * 1.5
///           : score;
/// }
/// ```
abstract interface class SearchRanker {
  /// The new score of [hit], from [score].
  double rank(SearchHit hit, double score);
}
