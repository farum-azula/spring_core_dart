/// A query as written: its words and its phrases (`"bean factory"`), and
/// whether the last word is still being typed, so it is also a prefix.
final class SearchQuery {
  /// A query of [clauses].
  const SearchQuery(this.clauses);

  /// Reads [text]: words, and phrases in double quotes. The last word is a
  /// prefix unless the text ends with a space.
  factory SearchQuery.parse(String text) {
    final clauses = <SearchClause>[];
    final pattern = RegExp(r'"([^"]*)"?|(\S+)');
    final matches = pattern.allMatches(text).toList();
    for (final (i, match) in matches.indexed) {
      final phrase = match[1];
      final last = i == matches.length - 1 && match.end == text.length;
      if (phrase != null) {
        if (phrase.trim().isNotEmpty) {
          clauses.add(
            SearchClause(
              phrase,
              phrase: true,
              prefix: last && !match[0]!.endsWith('"'),
            ),
          );
        }
      } else {
        clauses.add(SearchClause(match[2]!, prefix: last));
      }
    }
    return SearchQuery(clauses);
  }

  /// The words and phrases.
  final List<SearchClause> clauses;

  /// Whether there is nothing to search.
  bool get isEmpty => clauses.isEmpty;
}

/// A word or a phrase of a [SearchQuery].
final class SearchClause {
  /// The clause [text].
  const SearchClause(this.text, {this.phrase = false, this.prefix = false});

  /// The text as written.
  final String text;

  /// Whether its words must be next to each other, in order.
  final bool phrase;

  /// Whether its last word may be the start of a longer one.
  final bool prefix;

  @override
  String toString() => phrase ? '"$text"' : text;
}
