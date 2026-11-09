import 'package:spring_search_dart/src/search_document.dart';

/// A stretch of a field's text that matched the query, for a highlight.
final class SearchRange {
  /// The text from [start] to [end].
  const SearchRange(this.start, this.end);

  /// The offset of the first character.
  final int start;

  /// The offset after the last character.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is SearchRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start, $end)';
}

/// A piece of a field around its matches, for a list of results.
final class SearchSnippet {
  /// The [text] with its [ranges] to highlight.
  const SearchSnippet(this.text, this.ranges);

  /// The text, with `…` where it was cut.
  final String text;

  /// The matches in [text].
  final List<SearchRange> ranges;
}

/// A document the query found: its [score] and where each field matched.
final class SearchHit {
  /// The hit of [document].
  const SearchHit({
    required this.document,
    required this.score,
    Map<String, List<SearchRange>> this._highlights = const {},
  }) : _find = null;

  /// The hit of [document], whose highlights [find] gives the first time
  /// they are asked for: an index finds them for the hits shown only.
  SearchHit.lazy({
    required this.document,
    required this.score,
    required Map<String, List<SearchRange>> Function() find,
  }) : _highlights = null,
       _find = _Once(find);

  /// The document found.
  final SearchDocument document;

  /// How well it matches; higher first.
  final double score;

  /// The matches of each field, in order.
  Map<String, List<SearchRange>> get highlights => _highlights ?? _find!.value;

  final Map<String, List<SearchRange>>? _highlights;
  final _Once? _find;

  /// The same hit with another [score] (a `SearchRanker`'s).
  SearchHit withScore(double score) => _find == null
      ? SearchHit(document: document, score: score, highlights: highlights)
      : SearchHit.lazy(
          document: document,
          score: score,
          find: () => _find.value,
        );

  /// About [length] characters of [field] around its first match (from the
  /// start when it has none), cut at spaces, with the matches in it.
  SearchSnippet snippet(String field, {int length = 160}) {
    final text = document.fields[field] ?? '';
    final ranges = highlights[field] ?? const [];
    if (text.length <= length) {
      return SearchSnippet(text, ranges);
    }
    final first = ranges.isEmpty ? 0 : ranges.first.start;
    var start = (first - length ~/ 4).clamp(0, text.length - length);
    var end = start + length;
    if (start > 0) {
      final space = text.indexOf(' ', start);
      if (space >= 0 && space < first) {
        start = space + 1;
      }
    }
    if (end < text.length) {
      final space = text.lastIndexOf(' ', end);
      if (space > start && space > first) {
        end = space;
      }
    }
    final before = start > 0 ? '…' : '';
    final after = end < text.length ? '…' : '';
    final shift = before.length - start;
    return SearchSnippet('$before${text.substring(start, end)}$after', [
      for (final range in ranges)
        if (range.start >= start && range.end <= end)
          SearchRange(range.start + shift, range.end + shift),
    ]);
  }

  @override
  String toString() => 'SearchHit(${document.id}, $score)';
}

// Highlights found once, when first asked for.
final class _Once {
  _Once(this._find);

  final Map<String, List<SearchRange>> Function() _find;
  late final Map<String, List<SearchRange>> value = _find();
}
