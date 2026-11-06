import 'dart:math' as math;

import 'package:spring_search_dart/src/analysis/search_analyzer.dart';
import 'package:spring_search_dart/src/analysis/search_token.dart';
import 'package:spring_search_dart/src/search_document.dart';
import 'package:spring_search_dart/src/search_hit.dart';
import 'package:spring_search_dart/src/search_query.dart';

/// Whether a document must match every word of the query or one of them.
enum SearchOperator {
  /// Every word and phrase (the default).
  and,

  /// One of them; more of them rank higher.
  or,
}

/// The index of the documents of one language: an inverted index of the
/// terms its [analyzer] makes, ranked with BM25 per field.
///
/// A query's words are found as written, as the start of a longer word
/// when the word is the last one and still being typed (`bea` finds
/// `bean`), and with a typo when [search]'s `fuzzy` allows (`contex` finds
/// `context`). A phrase in double quotes finds its words next to each
/// other.
final class SearchIndex {
  SearchIndex._(this.analyzer, this.documents, this._tokens, this._postings)
    : _averages = _averageLengths(_tokens);

  /// The index of [documents], analyzed by [analyzer].
  factory SearchIndex.build(
    Iterable<SearchDocument> documents,
    SearchAnalyzer analyzer,
  ) {
    final docs = documents.toList();
    final tokens = <Map<String, List<SearchToken>>>[];
    final postings = <String, Map<int, Map<String, List<int>>>>{};
    for (final (id, document) in docs.indexed) {
      final fields = <String, List<SearchToken>>{};
      for (final MapEntry(key: field, value: text) in document.fields.entries) {
        final analyzed = analyzer.analyze(text);
        fields[field] = analyzed;
        for (final (position, token) in analyzed.indexed) {
          postings
              .putIfAbsent(token.term, () => {})
              .putIfAbsent(id, () => {})
              .putIfAbsent(field, () => [])
              .add(position);
        }
      }
      tokens.add(fields);
    }
    return SearchIndex._(analyzer, List.unmodifiable(docs), tokens, postings);
  }

  /// How the texts became terms; the query goes through it too.
  final SearchAnalyzer analyzer;

  /// The documents, by their number in the index.
  final List<SearchDocument> documents;

  final List<Map<String, List<SearchToken>>> _tokens;
  final Map<String, Map<int, Map<String, List<int>>>> _postings;
  final Map<String, double> _averages;

  late final List<String> _terms = _postings.keys.toList()..sort();

  late final Map<String, Set<String>> _bySurface = () {
    final result = <String, Set<String>>{};
    for (final fields in _tokens) {
      for (final tokens in fields.values) {
        for (final token in tokens) {
          if (token.surface != token.term) {
            result.putIfAbsent(token.surface, () => {}).add(token.term);
          }
        }
      }
    }
    return result;
  }();

  late final List<String> _surfaces = _bySurface.keys.toList()..sort();

  static const _k1 = 1.2;
  static const _b = 0.75;
  static const _prefixWeight = 0.85;
  static const _fuzzyWeight = 0.6;
  static const _phraseBoost = 1.5;
  static const _maxExpansions = 64;

  static Map<String, double> _averageLengths(
    List<Map<String, List<SearchToken>>> tokens,
  ) {
    final sums = <String, int>{};
    final counts = <String, int>{};
    for (final fields in tokens) {
      for (final MapEntry(key: field, value: list) in fields.entries) {
        sums[field] = (sums[field] ?? 0) + list.length;
        counts[field] = (counts[field] ?? 0) + 1;
      }
    }
    return {
      for (final MapEntry(key: field, value: sum) in sums.entries)
        field: sum / counts[field]!,
    };
  }

  /// The number of distinct terms.
  int get termCount => _postings.length;

  /// The documents [query] finds, best first. [weights] weigh the fields
  /// (1 for one not named); [fuzzy] is the number of typos a word of five
  /// letters or more may have (one below eight letters); [operator] says
  /// whether every clause must match.
  List<SearchHit> search(
    SearchQuery query, {
    Map<String, double> weights = const {},
    int fuzzy = 1,
    SearchOperator operator = SearchOperator.and,
  }) {
    final clauses = [
      for (final clause in query.clauses) ?_clause(clause, fuzzy),
    ];
    if (clauses.isEmpty) {
      return const [];
    }
    final scores = <int, double>{};
    final matched = <int, Set<String>>{};
    final counts = <int, int>{};
    for (final clause in clauses) {
      for (final MapEntry(key: doc, value: terms) in clause.docs.entries) {
        final score = _score(clause, doc, weights);
        scores[doc] = (scores[doc] ?? 0) + score;
        matched.putIfAbsent(doc, () => {}).addAll(terms);
        counts[doc] = (counts[doc] ?? 0) + 1;
      }
    }
    final hits = <SearchHit>[];
    for (final MapEntry(key: doc, value: score) in scores.entries) {
      final count = counts[doc]!;
      if (operator == SearchOperator.and && count < clauses.length) {
        continue;
      }
      hits.add(
        SearchHit(
          document: documents[doc],
          score: operator == SearchOperator.and
              ? score
              : score * count / clauses.length,
          highlights: _highlights(doc, matched[doc]!),
        ),
      );
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  _Clause? _clause(SearchClause clause, int fuzzy) {
    var tokens = analyzer.analyze(clause.text);
    if (tokens.isEmpty && clause.prefix) {
      // A word being typed may start a longer one though it is a stop
      // word itself (`be` of `bean`): it is matched as written.
      tokens = [
        for (final token in analyzer.tokenizer.tokenize(clause.text))
          token.withTerm(token.term.toLowerCase()),
      ];
    }
    if (tokens.isEmpty) {
      return null;
    }
    final last = tokens.last;
    final expansions = [
      for (final token in tokens)
        _expand(
          token,
          prefix: clause.prefix && identical(token, last),
          fuzzy: fuzzy,
        ),
    ];
    Map<int, Set<String>>? docs;
    for (final expansion in expansions) {
      final found = <int, Set<String>>{};
      for (final term in expansion.keys) {
        for (final doc in _postings[term]!.keys) {
          if (docs == null || docs.containsKey(doc)) {
            found.putIfAbsent(doc, () => {...?docs?[doc]}).add(term);
          }
        }
      }
      docs = found;
      if (docs.isEmpty) {
        return null;
      }
    }
    // A word of Chinese or Japanese is its pairs of characters in order.
    final phrase =
        clause.phrase ||
        (tokens.length > 1 && !tokens.any((t) => _latin(t.term)));
    if (phrase && expansions.length > 1) {
      docs!.removeWhere((doc, _) => !_adjacent(doc, expansions));
    }
    return docs!.isEmpty ? null : _Clause(expansions, docs, clause.phrase);
  }

  Map<String, double> _expand(
    SearchToken token, {
    required bool prefix,
    required int fuzzy,
  }) {
    final term = token.term;
    final result = <String, double>{
      if (_postings.containsKey(term)) term: 1,
    };
    if (prefix) {
      for (final other in _startingWith(_terms, term)) {
        result.putIfAbsent(other, () => _prefixWeight);
      }
      for (final surface in _startingWith(_surfaces, token.surface)) {
        for (final other in _bySurface[surface]!) {
          result.putIfAbsent(other, () => _prefixWeight);
        }
      }
    }
    if (fuzzy > 0 && term.length >= 5 && _latin(term)) {
      final edits = term.length >= 8 ? fuzzy : 1;
      for (final other in _terms) {
        if ((other.length - term.length).abs() <= edits &&
            !result.containsKey(other) &&
            _distance(term, other, edits) <= edits) {
          result[other] = _fuzzyWeight;
        }
      }
    }
    return result;
  }

  static Iterable<String> _startingWith(List<String> sorted, String prefix) {
    var low = 0;
    var high = sorted.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (sorted[middle].compareTo(prefix) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final result = <String>[];
    for (
      var i = low;
      i < sorted.length && result.length < _maxExpansions;
      i++
    ) {
      if (!sorted[i].startsWith(prefix)) {
        break;
      }
      result.add(sorted[i]);
    }
    return result;
  }

  static bool _latin(String term) => term.codeUnits.every((c) => c < 0x250);

  // The edit distance of [a] and [b] (a swap of two letters is one edit),
  // or [limit] + 1 once it is over [limit].
  static int _distance(String a, String b, int limit) {
    var before = List<int>.generate(b.length + 1, (i) => i);
    var previous = List<int>.filled(b.length + 1, 0);
    var row = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      row[0] = i;
      var best = row[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var value = math.min(
          math.min(before[j] + 1, row[j - 1] + 1),
          before[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          value = math.min(value, previous[j - 2] + 1);
        }
        row[j] = value;
        best = math.min(best, value);
      }
      if (best > limit) {
        return limit + 1;
      }
      final spare = previous;
      previous = before;
      before = row;
      row = spare;
    }
    return before[b.length];
  }

  // Whether the clause's words are next to each other, in order, in one
  // field of [doc].
  bool _adjacent(int doc, List<Map<String, double>> expansions) {
    for (final field in _tokens[doc].keys) {
      final positions = [
        for (final expansion in expansions)
          {
            for (final term in expansion.keys)
              ...?_postings[term]?[doc]?[field],
          },
      ];
      for (final start in positions.first) {
        var all = true;
        for (var i = 1; i < positions.length; i++) {
          if (!positions[i].contains(start + i)) {
            all = false;
            break;
          }
        }
        if (all) {
          return true;
        }
      }
    }
    return false;
  }

  double _score(_Clause clause, int doc, Map<String, double> weights) {
    var total = 0.0;
    for (final expansion in clause.expansions) {
      // A longer word the typed one starts, or one with a typo, is rarer
      // than the word itself: it counts as common as the most common of
      // them, so `bean` finds @Bean before @BeanMethodAnnotation.
      final idf = expansion.keys.map(_idf).reduce(math.min);
      var best = 0.0;
      for (final MapEntry(key: term, value: weight) in expansion.entries) {
        final fields = _postings[term]![doc];
        if (fields == null) {
          continue;
        }
        var sum = 0.0;
        for (final MapEntry(key: field, value: positions) in fields.entries) {
          final tf = positions.length;
          final length = _tokens[doc][field]!.length;
          final average = _averages[field] ?? 1;
          sum +=
              (weights[field] ?? 1) *
              tf *
              (_k1 + 1) /
              (tf + _k1 * (1 - _b + _b * length / average));
        }
        best = math.max(best, weight * idf * sum);
      }
      total += best;
    }
    return clause.phrase ? total * _phraseBoost : total;
  }

  double _idf(String term) {
    final df = _postings[term]!.length;
    return math.log(1 + (documents.length - df + 0.5) / (df + 0.5));
  }

  Map<String, List<SearchRange>> _highlights(int doc, Set<String> terms) {
    final result = <String, List<SearchRange>>{};
    for (final term in terms) {
      for (final MapEntry(key: field, value: positions)
          in (_postings[term]?[doc] ?? const <String, List<int>>{}).entries) {
        final tokens = _tokens[doc][field]!;
        for (final position in positions) {
          final token = tokens[position];
          result
              .putIfAbsent(field, () => [])
              .add(SearchRange(token.start, token.end));
        }
      }
    }
    return {
      for (final MapEntry(key: field, value: ranges) in result.entries)
        field: _merged(ranges),
    };
  }

  static List<SearchRange> _merged(List<SearchRange> ranges) {
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <SearchRange>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add(SearchRange(last.start, math.max(last.end, range.end)));
      } else {
        merged.add(range);
      }
    }
    return merged;
  }
}

final class _Clause {
  const _Clause(this.expansions, this.docs, this.phrase);

  final List<Map<String, double>> expansions;
  final Map<int, Set<String>> docs;
  final bool phrase;
}
