// The index: BM25 with weighted fields, every word or one of them, the
// word being typed as a prefix, typos, phrases, Japanese, highlights and
// snippets.
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

final _docs = [
  const SearchDocument(
    id: 'bean',
    fields: {
      'title': '@Bean',
      'body': 'A method whose result is a bean of the context.',
    },
  ),
  const SearchDocument(
    id: 'factory',
    fields: {
      'title': 'BeanFactory',
      'body': 'The container that creates beans and binds properties.',
    },
  ),
  const SearchDocument(
    id: 'events',
    fields: {
      'title': 'Events',
      'body': 'Listeners get the events of the application context.',
    },
  ),
  const SearchDocument(
    id: 'value',
    fields: {
      'title': '@Value',
      'body': 'Injects a property: the bean factory resolves it.',
    },
  ),
];

List<String> _ids(
  SearchIndex index,
  String query, {
  SearchOperator operator = SearchOperator.and,
  int fuzzy = 1,
}) => [
  for (final hit in index.search(
    SearchQuery.parse(query),
    weights: const {'title': 8, 'body': 1},
    operator: operator,
    fuzzy: fuzzy,
  ))
    hit.document.id,
];

void main() {
  final index = SearchIndex.build(_docs, SearchAnalyzer.english);

  test('a title outranks the text; every word must match', () {
    expect(_ids(index, 'bean '), ['bean', 'factory', 'value']);
    expect(_ids(index, 'application context '), ['events']);
    expect(_ids(index, 'context bean '), ['bean']);
  });

  test('or: one word is enough, more rank higher', () {
    expect(
      _ids(index, 'listeners container ', operator: SearchOperator.or),
      unorderedEquals(['events', 'factory']),
    );
  });

  test('the word as typed before the longer words it starts', () {
    final words = SearchIndex.build([
      const SearchDocument(
        id: 'long',
        fields: {'title': 'BeanMethodAnnotation'},
      ),
      const SearchDocument(id: 'bean', fields: {'title': 'Bean'}),
      for (var i = 0; i < 5; i++)
        SearchDocument(id: 'text$i', fields: {'body': 'a bean $i'}),
    ], SearchAnalyzer.english);
    expect(_ids(words, 'bean').first, 'bean');
  });

  test('a Japanese word is its characters in order, not anywhere', () {
    final japanese = SearchIndex.build([
      const SearchDocument(id: 'profile', fields: {'body': 'プロファイルを選びます'}),
      const SearchDocument(id: 'apart', fields: {'body': 'プロキシのファイルとロフト'}),
    ], SearchAnalyzer.standard);
    expect(_ids(japanese, 'プロファイル '), ['profile']);
  });

  test('the word being typed is a prefix', () {
    // A stop word while typed: the start of a longer word.
    expect(_ids(index, 'be'), ['bean', 'factory', 'value']);
    expect(_ids(index, 'liste'), ['events']);
    expect(_ids(index, 'liste '), isEmpty);
    // `binds` is kept as `bind`; its word still starts with `bindin`? no:
    // `creat` finds `creates` through the word as written.
    expect(_ids(index, 'creat'), ['factory']);
  });

  test('a typo in a longer word', () {
    expect(_ids(index, 'contxet '), unorderedEquals(['events', 'bean']));
    expect(_ids(index, 'contxet ', fuzzy: 0), isEmpty);
    expect(
      _ids(index, 'evnts '),
      isEmpty,
      reason: 'five letters: one typo, not a swap and a drop',
    );
  });

  test('a phrase finds its words next to each other', () {
    // BeanFactory is `bean` then `factory` too.
    expect(_ids(index, '"bean factory"'), ['factory', 'value']);
    expect(_ids(index, '"factory bean"'), isEmpty);
    expect(_ids(index, 'bean factory '), containsAll(['value', 'factory']));
  });

  test('Japanese: a word inside a longer one, and one character typed', () {
    final japanese = SearchIndex.build([
      const SearchDocument(
        id: 'di',
        fields: {'title': '依存性注入', 'body': 'コンテナが Bean を結び付けます。'},
      ),
      const SearchDocument(
        id: 'events',
        fields: {'title': 'イベント', 'body': 'リスナーがイベントを受け取ります。'},
      ),
    ], SearchAnalyzer.standard);
    expect(_ids(japanese, '依存性 '), ['di']);
    expect(_ids(japanese, '注入 '), ['di']);
    expect(_ids(japanese, '依'), ['di']);
    expect(_ids(japanese, 'イベント '), ['events']);
    expect(_ids(japanese, 'bean '), ['di']);
  });

  test('highlights cover the words as written; the snippet keeps them', () {
    final hit = index.search(SearchQuery.parse('resolved ')).single;
    final body = hit.document.fields['body']!;
    final range = hit.highlights['body']!.single;
    expect(body.substring(range.start, range.end), 'resolves');

    final long = SearchDocument(
      id: 'long',
      fields: {'body': '${'word ' * 60}needle ${'word ' * 60}'},
    );
    final snippet = SearchIndex.build(
      [long],
      SearchAnalyzer.standard,
    ).search(SearchQuery.parse('needle ')).single.snippet('body', length: 60);
    expect(snippet.text, startsWith('…'));
    expect(snippet.text, endsWith('…'));
    expect(snippet.text.length, lessThanOrEqualTo(62));
    final r = snippet.ranges.single;
    expect(snippet.text.substring(r.start, r.end), 'needle');
  });

  test('a query of stop words or nothing finds nothing', () {
    expect(_ids(index, 'the '), isEmpty);
    expect(_ids(index, '   '), isEmpty);
  });

  test(
    'buildAsync: the same index, a pause whenever the budget is spent',
    () async {
      var pauses = 0;
      final built = await SearchIndex.buildAsync(
        _docs,
        SearchAnalyzer.english,
        budget: Duration.zero,
        pause: () async => pauses++,
      );
      // Before every document, then before each of the two sorts.
      expect(pauses, _docs.length + 2);
      for (final query in ['bean', 'scope', 'config', 'beans', 'sco']) {
        List<String> ids(SearchIndex i) => [
          for (final hit in i.search(SearchQuery.parse(query))) hit.document.id,
        ];
        expect(ids(built), ids(index), reason: query);
      }
    },
  );
}
