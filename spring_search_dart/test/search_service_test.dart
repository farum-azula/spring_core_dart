// The searchService bean: its documents from the beans and
// spring.search.markdown, the language's index or the default one,
// rankers, one hit per page, the index built again after the event, and
// spring.search.enabled.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/spring_auto_configuration.dart';
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

final class Books implements SearchDocumentSource {
  final titles = ['Dune', 'Solaris'];

  @override
  Stream<SearchDocument> documents() => Stream.fromIterable([
    for (final (i, title) in titles.indexed)
      SearchDocument(
        id: 'book-$i',
        fields: {'title': title},
        link: '/books/$i',
      ),
  ]);
}

final class SolarisLast implements SearchRanker {
  @override
  double rank(SearchHit hit, double score) =>
      hit.document.title == 'Solaris' ? 0 : score;
}

ConfigurableApplicationContext _run(
  Map<String, String> properties, {
  List<BeanDefinition<Object>> beans = const [],
}) => SpringApplication(
  [
    BeanModule(
      'test',
      beans,
      resources: {
        'application.properties': EmbeddedResource.text(
          [
            for (final MapEntry(:key, :value) in properties.entries)
              '$key=$value',
          ].join('\n'),
        ),
        'pages/start.md': const EmbeddedResource.text(
          '# Getting started\n\nInstall the package.\n\n'
          '## Beans\n\nDeclare a bean.',
        ),
        'pages/start.ja.md': const EmbeddedResource.text(
          '# はじめに\n\nパッケージを入れます。',
        ),
        'pages/beans.md': const EmbeddedResource.text(
          '# Beans\n\nA bean is an object of the container.',
        ),
      },
    ),
  ],
  autoConfigurations: [springSearchDartAutoConfiguration],
  bannerMode: BannerMode.off,
).run(const []);

BeanDefinition<Object> _books(Books books) => BeanDefinition<Books>(
  name: 'books',
  types: const [Books, SearchDocumentSource],
  create: (_) => books,
);

void main() {
  test('beans and Markdown, by language; one hit per page', () async {
    final context = _run(
      {
        'spring.search.markdown[0].location': 'resources:pages/*.md',
        'spring.search.markdown[0].link': '/docs/{path}',
        'spring.search.collapse-by': 'page',
      },
      beans: [_books(Books())],
    );
    addTearDown(context.close);
    final search = context.getBean<SearchService>();

    expect(
      [for (final h in await search.search('dune')) h.document.link],
      ['/books/0'],
    );
    expect(
      [for (final h in await search.search('bean ')) h.document.link],
      ['/docs/beans', '/docs/start#beans'],
    );
    expect(
      [
        for (final h in await search.search('パッケージ', language: 'ja'))
          h.document.link,
      ],
      ['/docs/start'],
    );
    // A language without documents searches the default one.
    expect(await search.search('dune', language: 'fr'), hasLength(1));
  });

  test('rankers change the order; the event builds the index again', () async {
    final books = Books();
    final context = _run(
      {'spring.search.operator': 'or'},
      beans: [
        _books(books),
        BeanDefinition<SolarisLast>(
          name: 'solarisLast',
          types: const [SolarisLast, SearchRanker],
          create: (_) => SolarisLast(),
        ),
      ],
    );
    addTearDown(context.close);
    final search = context.getBean<SearchService>();
    expect(
      [for (final h in await search.search('solaris dune ')) h.document.title],
      ['Dune', 'Solaris'],
    );
    books.titles.add('Neuromancer');
    expect(await search.search('neuromancer'), isEmpty);
    context.publishEvent(SearchIndexInvalidatedEvent(books));
    expect(await search.search('neuromancer'), hasLength(1));
  });

  test('spring.search.enabled=false: no service', () {
    final context = _run({'spring.search.enabled': 'false'});
    addTearDown(context.close);
    expect(context.containsBean('searchService'), isFalse);
  });

  test('an unknown analyzer stops the start, naming the property', () {
    expect(
      () => _run({'spring.search.analyzers.fr': 'french'}),
      throwsA(predicate((e) => '$e'.contains('spring.search.analyzers.fr'))),
    );
  });
}
