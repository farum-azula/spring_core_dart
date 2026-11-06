import 'package:spring_search_dart/src/analysis/search_token.dart';

/// Cuts a text into words: the first step of a `SearchAnalyzer`.
abstract interface class SearchTokenizer {
  /// The words of [text], in order.
  List<SearchToken> tokenize(String text);
}

/// Words of letters and digits in any script, and for Chinese, Japanese
/// and Korean, which write no spaces, every two characters next to each
/// other (`依存性` gives `依存`, `存性`): a query cut the same way finds
/// them without a dictionary. A run of one such character is one word.
final class StandardTokenizer implements SearchTokenizer {
  /// The standard tokenizer.
  const StandardTokenizer();

  static final _word = RegExp(r"[\p{L}\p{N}]+(?:['’][\p{L}]+)*", unicode: true);

  static final _cjk = RegExp(
    r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}'
    r'\p{Script=Hangul}ー]+',
    unicode: true,
  );

  @override
  List<SearchToken> tokenize(String text) {
    final tokens = <SearchToken>[];
    for (final match in _word.allMatches(text)) {
      final word = match[0]!;
      final at = match.start;
      var position = 0;
      for (final run in _cjk.allMatches(word)) {
        if (run.start > position) {
          tokens.add(
            SearchToken(
              word.substring(position, run.start),
              at + position,
              at + run.start,
            ),
          );
        }
        _bigrams(run[0]!, at + run.start, tokens);
        position = run.end;
      }
      if (position < word.length) {
        tokens.add(
          SearchToken(word.substring(position), at + position, match.end),
        );
      }
    }
    return tokens;
  }

  static void _bigrams(String run, int start, List<SearchToken> tokens) {
    final units = run.runes.toList();
    var offset = start;
    final offsets = <int>[];
    for (final unit in units) {
      offsets.add(offset);
      offset += unit > 0xFFFF ? 2 : 1;
    }
    offsets.add(offset);
    if (units.length == 1) {
      tokens.add(SearchToken(run, start, offset));
      return;
    }
    for (var i = 0; i + 1 < units.length; i++) {
      tokens.add(
        SearchToken(
          String.fromCharCodes(units.sublist(i, i + 2)),
          offsets[i],
          offsets[i + 2],
        ),
      );
    }
  }
}
