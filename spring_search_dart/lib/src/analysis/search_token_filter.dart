import 'package:spring_search_dart/src/analysis/search_token.dart';

/// Changes, drops or adds words after the tokenizer: lower case, accents,
/// stop words, stems. A `SearchAnalyzer` runs its filters in order, and
/// the same ones on the documents and on the query.
abstract interface class SearchTokenFilter {
  /// The words after this filter.
  Iterable<SearchToken> filter(Iterable<SearchToken> tokens);
}

/// Lower case: `Bean` finds `bean`.
final class LowerCaseFilter implements SearchTokenFilter {
  /// The lower-case filter.
  const LowerCaseFilter();

  @override
  Iterable<SearchToken> filter(Iterable<SearchToken> tokens) =>
      tokens.map((t) => t.withTerm(t.term.toLowerCase()));
}

/// Latin letters without their accents: `café` finds `cafe`.
final class AsciiFoldingFilter implements SearchTokenFilter {
  /// The folding filter.
  const AsciiFoldingFilter();

  static const _from = 'àáâãäåāăąçćčďèéêëēęěìíîïīñńňòóôõöøōőùúûüūůűýÿźżžśšşřł';
  static const _to = 'aaaaaaaaacccdeeeeeeeiiiiinnnooooooooouuuuuuuyyzzzsssrl';

  static final Map<String, String> _map = {
    for (var i = 0; i < _from.length; i++) _from[i]: _to[i],
    'ß': 'ss',
    'æ': 'ae',
    'œ': 'oe',
  };

  @override
  Iterable<SearchToken> filter(Iterable<SearchToken> tokens) => tokens.map((t) {
    if (t.term.codeUnits.every((c) => c < 0x80)) {
      return t;
    }
    final out = StringBuffer();
    for (final char in t.term.split('')) {
      out.write(_map[char] ?? char);
    }
    return t.withTerm(out.toString());
  });
}

/// Also the parts of a word written in camel case or with digits:
/// `ApplicationContext` is found by `context` too. The whole word stays.
final class WordPartsFilter implements SearchTokenFilter {
  /// The word-parts filter.
  const WordPartsFilter();

  static final _part = RegExp('[A-Z]?[a-z]+|[A-Z]+(?![a-z])|[0-9]+');

  @override
  Iterable<SearchToken> filter(Iterable<SearchToken> tokens) sync* {
    for (final token in tokens) {
      yield token;
      final parts = _part.allMatches(token.term).toList();
      if (parts.length < 2) {
        continue;
      }
      for (final part in parts) {
        yield SearchToken(
          part[0]!,
          token.start + part.start,
          token.start + part.end,
        );
      }
    }
  }
}

/// Leaves out [words] (`the`, `a`), which are in every document and say
/// nothing of it.
final class StopWordFilter implements SearchTokenFilter {
  /// Leaves out [words].
  const StopWordFilter(this.words);

  /// English's most common words.
  static const english = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'in', //
    'is', 'it', 'of', 'on', 'or', 'that', 'the', 'this', 'to', 'with',
  };

  /// The words left out.
  final Set<String> words;

  @override
  Iterable<SearchToken> filter(Iterable<SearchToken> tokens) =>
      tokens.where((t) => !words.contains(t.term));
}

/// English endings removed, so a word and its forms meet: `beans` and
/// `bean`, `binding` and `bind`, `injected` and `inject`. Light on
/// purpose: a word under four letters stays, and an ending goes only when
/// a vowel is left before it (`string` stays).
final class EnglishStemFilter implements SearchTokenFilter {
  /// The English stemmer.
  const EnglishStemFilter();

  @override
  Iterable<SearchToken> filter(Iterable<SearchToken> tokens) =>
      tokens.map((t) => t.stemmed(stem(t.term)));

  static final _vowel = RegExp('[aeiouy]');

  /// The stem of [word]: the forms of a word give the same stem, not
  /// always a word (`resolve`, `resolves`, `resolved`: `resolv`).
  static String stem(String word) {
    if (word.length < 4 || !word.codeUnits.every((c) => c < 0x80)) {
      return word;
    }
    var w = word;
    if (w.endsWith("'s") || w.endsWith('’s')) {
      w = w.substring(0, w.length - 2);
    }
    if (w.endsWith('ies') && w.length > 4) {
      return '${w.substring(0, w.length - 3)}y';
    }
    if (w.endsWith('sses')) {
      return w.substring(0, w.length - 2);
    }
    for (final ending in ['ches', 'shes', 'xes', 'zes']) {
      if (w.endsWith(ending)) {
        return w.substring(0, w.length - 2);
      }
    }
    if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us')) {
      w = w.substring(0, w.length - 1);
    }
    for (final ending in ['ing', 'ed']) {
      final rest = w.length - ending.length;
      if (w.endsWith(ending) &&
          rest >= 3 &&
          _vowel.hasMatch(w.substring(0, rest))) {
        w = w.substring(0, rest);
        if (w.length > 3 &&
            w[w.length - 1] == w[w.length - 2] &&
            !'lsz'.contains(w[w.length - 1])) {
          w = w.substring(0, w.length - 1);
        }
        break;
      }
    }
    if (w.length >= 4 && w.endsWith('e')) {
      w = w.substring(0, w.length - 1);
    }
    return w;
  }
}
