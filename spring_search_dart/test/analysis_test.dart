// How texts become terms: words in any script, Chinese/Japanese/Korean in
// pairs, camel-case parts, lower case, accents, English stop words and
// endings, and the analyzer of each language.
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

List<String> _terms(SearchAnalyzer analyzer, String text) => [
  for (final token in analyzer.analyze(text)) token.term,
];

void main() {
  test('words, with their offsets in the text', () {
    final tokens = const StandardTokenizer().tokenize(
      "Spring's beans, 2 of them",
    );
    expect(
      [for (final t in tokens) t.term],
      ["Spring's", 'beans', '2', 'of', 'them'],
    );
    expect((tokens[1].start, tokens[1].end), (9, 14));
  });

  test('Japanese and Chinese in pairs of characters, Latin words apart', () {
    expect(
      _terms(SearchAnalyzer.standard, '依存性注入とBean'),
      ['依存', '存性', '性注', '注入', '入と', 'bean'],
    );
    expect(_terms(SearchAnalyzer.standard, '字'), ['字']);
  });

  test('camel case gives its parts too; lower case; no accents', () {
    expect(
      _terms(SearchAnalyzer.standard, 'ApplicationContext Café'),
      ['applicationcontext', 'application', 'context', 'cafe'],
    );
  });

  test('English: no stop words, endings removed, the word kept for typing', () {
    final tokens = SearchAnalyzer.english.analyze(
      'The beans and bindings injected',
    );
    expect([for (final t in tokens) t.term], ['bean', 'bind', 'inject']);
    expect(tokens[1].surface, 'bindings');
    for (final (word, stem) in [
      ('properties', 'property'),
      ('classes', 'class'),
      ('running', 'run'),
      ('status', 'status'),
      ('bus', 'bus'),
      ('red', 'red'),
      ('string', 'string'),
      ('resolve', 'resolv'),
      ('resolves', 'resolv'),
      ('resolved', 'resolv'),
      ('named', 'nam'),
      ('names', 'nam'),
    ]) {
      expect(EnglishStemFilter.stem(word), stem, reason: word);
    }
  });

  test('the analyzer of each language; an unknown name is an error', () {
    final analyzers = SearchAnalyzers(
      analyzers: [
        const SearchAnalyzer('plain', filters: [LowerCaseFilter()]),
      ],
      languages: {'de': 'plain'},
    );
    expect(analyzers.of('en').name, 'english');
    expect(analyzers.of('en-GB').name, 'english');
    expect(analyzers.of('ja').name, 'standard');
    expect(analyzers.of('de').name, 'plain');
    expect(
      () => SearchAnalyzers(languages: {'fr': 'french'}),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('spring.search.analyzers.fr'), contains('english')),
        ),
      ),
    );
  });
}
