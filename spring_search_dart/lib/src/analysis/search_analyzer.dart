import 'package:spring_search_dart/src/analysis/search_token.dart';
import 'package:spring_search_dart/src/analysis/search_token_filter.dart';
import 'package:spring_search_dart/src/analysis/search_tokenizer.dart';

/// How the text of one language becomes the terms of the index: a
/// [tokenizer], then [filters] in order. The documents and the queries go
/// through the same analyzer, so they meet.
///
/// An application's own is a bean, named by `spring.search.analyzers`:
///
/// ```dart
/// @Bean()
/// SearchAnalyzer german() => const SearchAnalyzer(
///   'german',
///   filters: [LowerCaseFilter(), GermanStemFilter()],
/// );
/// ```
///
/// ```yaml
/// spring:
///   search:
///     analyzers:
///       de: german
/// ```
final class SearchAnalyzer {
  /// The analyzer [name] of [tokenizer] then [filters].
  const SearchAnalyzer(
    this.name, {
    this.tokenizer = const StandardTokenizer(),
    this.filters = const [],
  });

  /// Words, lower case, without accents, with their camel-case parts; for
  /// any language (Chinese, Japanese and Korean in pairs of characters).
  static const standard = SearchAnalyzer(
    'standard',
    filters: [WordPartsFilter(), LowerCaseFilter(), AsciiFoldingFilter()],
  );

  /// [standard], without English's most common words and with English
  /// endings removed.
  static const english = SearchAnalyzer(
    'english',
    filters: [
      WordPartsFilter(),
      LowerCaseFilter(),
      AsciiFoldingFilter(),
      StopWordFilter(StopWordFilter.english),
      EnglishStemFilter(),
    ],
  );

  /// The name `spring.search.analyzers` gives.
  final String name;

  /// Cuts the text into words.
  final SearchTokenizer tokenizer;

  /// Change the words, in order.
  final List<SearchTokenFilter> filters;

  /// The terms of [text].
  List<SearchToken> analyze(String text) {
    Iterable<SearchToken> tokens = tokenizer.tokenize(text);
    for (final filter in filters) {
      tokens = filter.filter(tokens);
    }
    return [
      for (final token in tokens)
        if (token.term.isNotEmpty) token,
    ];
  }
}

/// The analyzers by name, and the one of each language: the built-in
/// `standard` and `english`, then the application's `SearchAnalyzer`
/// beans (a bean of a built-in name replaces it). A language not named
/// in `languages` uses `english` for `en` and `standard` for the others.
final class SearchAnalyzers {
  /// The analyzers of [analyzers] and the languages of [languages]
  /// (language to analyzer name).
  SearchAnalyzers({
    Iterable<SearchAnalyzer> analyzers = const [],
    Map<String, String> languages = const {},
  }) : _byName = {
         for (final analyzer in [
           SearchAnalyzer.standard,
           SearchAnalyzer.english,
           ...analyzers,
         ])
           analyzer.name: analyzer,
       },
       _languages = {'en': 'english', ...languages} {
    for (final MapEntry(key: language, value: name) in _languages.entries) {
      if (!_byName.containsKey(name)) {
        throw ArgumentError.value(
          name,
          'spring.search.analyzers.$language',
          'is no analyzer: ${_byName.keys.join(', ')}',
        );
      }
    }
  }

  final Map<String, SearchAnalyzer> _byName;
  final Map<String, String> _languages;

  /// The analyzer [name]; `null` when there is none.
  SearchAnalyzer? named(String name) => _byName[name];

  /// The analyzer of [language] (`en`, `ja`, `pt-BR`: the part before `-`
  /// or `_` when the whole is not named).
  SearchAnalyzer of(String language) {
    final name =
        _languages[language] ??
        _languages[language.split(RegExp('[-_]')).first] ??
        'standard';
    return _byName[name]!;
  }
}
