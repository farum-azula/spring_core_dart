import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/analysis/search_analyzer.dart';
import 'package:spring_search_dart/src/config/search_properties.dart';
import 'package:spring_search_dart/src/markdown/markdown_search_source.dart';
import 'package:spring_search_dart/src/search_document_source.dart';
import 'package:spring_search_dart/src/search_index_runner.dart';
import 'package:spring_search_dart/src/search_ranker.dart';
import 'package:spring_search_dart/src/search_service.dart';

const _source = 'package:spring_search_dart/spring_auto_configuration.dart';

/// The `searchService` bean: the documents of the `SearchDocumentSource`
/// beans and of `spring.search.markdown`, the `SearchAnalyzer` beans by
/// `spring.search.analyzers`, the `SearchRanker` beans in `@Order`.
/// `spring.search.enabled=false` leaves it out. With
/// `spring.search.indexing` set, the `searchIndexRunner` builds the
/// indexes at the start (`start`) or right after it (`background`).
final searchAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<SearchIndexRunner>(
    name: 'searchIndexRunner',
    types: const [SearchIndexRunner, ApplicationRunner],
    source: _source,
    conditions: const [
      ConditionGroup('$_source#searchIndexRunner', [
        ConditionalOnProperty(
          'enabled',
          prefix: 'spring.search',
          havingValue: 'true',
          matchIfMissing: true,
        ),
        ConditionalOnProperty('indexing', prefix: 'spring.search'),
      ]),
    ],
    create: (r) => SearchIndexRunner(
      r.dependency<SearchService>(),
      r.dependency<SearchProperties>().indexing,
    ),
  ),
  BeanDefinition<SearchService>(
    name: 'searchService',
    types: const [SearchService, GenericApplicationListener],
    source: _source,
    conditions: const [
      ConditionGroup(_source, [
        ConditionalOnProperty(
          'enabled',
          prefix: 'spring.search',
          havingValue: 'true',
          matchIfMissing: true,
        ),
      ]),
    ],
    create: (r) {
      final properties = r.dependency<SearchProperties>();
      final loader = r.dependency<ResourceLoader>();
      final resources = switch (loader) {
        final ResourcePatternResolver resolver => resolver,
        _ => PathMatchingResourcePatternResolver(resourceLoader: loader),
      };
      return SearchService(
        [
          ...?r.optionalDependencyList<SearchDocumentSource>(),
          for (final markdown in properties.markdown)
            MarkdownSearchSource(
              resources,
              location: markdown.location,
              exclude: markdown.exclude,
              link: markdown.link,
              defaultLanguage: properties.defaultLanguage,
            ),
        ],
        analyzers: SearchAnalyzers(
          analyzers: r.optionalDependencyList<SearchAnalyzer>() ?? const [],
          languages: properties.analyzers,
        ),
        rankers: r.optionalDependencyList<SearchRanker>() ?? const [],
        defaultLanguage: properties.defaultLanguage,
        weights: properties.fields.isEmpty
            ? SearchService.defaultWeights
            : properties.fields,
        fuzzy: properties.fuzzy,
        maxHits: properties.maxHits,
        operator: properties.operator,
        collapseBy: properties.collapseBy,
      );
    },
  ),
];
