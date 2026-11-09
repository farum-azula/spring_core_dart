/// Full-text search for Spring for Dart: documents from
/// `SearchDocumentSource` beans and Markdown resources, analyzers per
/// language, BM25 ranking with prefixes and typos, highlights and
/// snippets. Ask the `SearchService` bean.
///
/// ```dart
/// final hits = await context.getBean<SearchService>().search('bean');
/// ```
library;

export 'src/analysis/search_analyzer.dart';
export 'src/analysis/search_token.dart';
export 'src/analysis/search_token_filter.dart';
export 'src/analysis/search_tokenizer.dart';
export 'src/config/search_properties.dart';
export 'src/index/search_index.dart';
export 'src/index/search_index_files.dart';
export 'src/markdown/markdown_search_source.dart';
export 'src/markdown/markdown_sections.dart';
export 'src/search_document.dart';
export 'src/search_document_source.dart';
export 'src/search_hit.dart';
export 'src/search_index_invalidated_event.dart';
export 'src/search_index_runner.dart';
export 'src/search_query.dart';
export 'src/search_ranker.dart';
export 'src/search_service.dart';
