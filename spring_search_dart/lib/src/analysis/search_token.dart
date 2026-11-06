/// A word of a text as the index keeps it: its [term] (lower case,
/// stemmed: what is compared), the word before a stemmer shortened it
/// ([surface], for a word still being typed) and where the word is in the
/// original text ([start], [end]), for highlights.
final class SearchToken {
  /// The token [term] of the text from [start] to [end]; [surface] is the
  /// term when not given.
  const SearchToken(this.term, this.start, this.end, {this._surface});

  /// What is compared.
  final String term;

  final String? _surface;

  /// The word before a stemmer changed it (`binding` for `bind`).
  String get surface => _surface ?? term;

  /// The offset of the word in the text.
  final int start;

  /// The offset after the word.
  final int end;

  /// The same word with another [term] (lower case, without accents).
  SearchToken withTerm(String term) => SearchToken(term, start, end);

  /// The same word shortened to its [stem]; the [surface] stays.
  SearchToken stemmed(String stem) =>
      SearchToken(stem, start, end, surface: surface);

  @override
  bool operator ==(Object other) =>
      other is SearchToken &&
      other.term == term &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(term, start, end);

  @override
  String toString() => '$term@$start-$end';
}
