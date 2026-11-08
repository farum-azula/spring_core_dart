import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/index/search_index.dart';

/// The `spring.search.*` properties.
///
/// ```yaml
/// spring:
///   search:
///     fields: { title: 8, heading: 4, body: 1 }
///     fuzzy: 1
///     max-hits: 20
///     analyzers: { de: german }
///     collapse-by: page
///     markdown:
///       - location: resources:content/**/*.md
///         exclude: ['**/contents*.md']
///         link: /docs/{path}
/// ```
@ConfigurationProperties('spring.search')
class SearchProperties {
  /// `false`: no `SearchService`.
  bool enabled = true;

  /// The language of the documents that name none, and of a search that
  /// names none or one without documents.
  String defaultLanguage = 'en';

  /// The weight of each field; a field not named weighs 1. Empty: `title`
  /// 8, `heading` 4, `body` 1.
  Map<String, double> fields = {};

  /// The typos a word of the query may have: one for a word of five to
  /// seven letters, up to this many for a longer one. `0`: none.
  int fuzzy = 1;

  /// The most hits a search gives.
  int maxHits = 20;

  /// `and`: a document has every word of the query; `or`: one of them.
  SearchOperator operator = SearchOperator.and;

  /// The analyzer of each language (`ja: standard`); `en` is `english`,
  /// every other language `standard`, unless named here.
  Map<String, String> analyzers = {};

  /// The attribute that groups the hits: only the best of each value
  /// stays (`page`: one section per page). None by default.
  String? collapseBy;

  /// The Markdown files to search.
  List<MarkdownSearchProperties> markdown = [];

  /// When the indexes are built: at the first search (`first-search`, the
  /// default), while the application starts (`start`: an
  /// `ApplicationRunner`, so a Flutter app builds them behind its splash),
  /// or right after it, behind the running app (`background`).
  SearchIndexing indexing = SearchIndexing.firstSearch;
}

/// When `spring.search.indexing` builds the indexes.
enum SearchIndexing {
  /// At the first search, or when the app calls `SearchService.prepare`.
  firstSearch,

  /// While the application starts, before it is shown.
  start,

  /// Right after the application starts, a little at a time while it runs:
  /// the start does not wait, and the first search most likely finds the
  /// index of its language ready.
  background,
}

/// One `spring.search.markdown[n]` entry: the Markdown files of a
/// location, each cut into its sections.
@Introspected()
class MarkdownSearchProperties {
  /// The files: a `resources:` pattern (`resources:content/**/*.md`).
  String location = '';

  /// Patterns of files to leave out, relative to the location's
  /// directory (`**/contents*.md`).
  List<String> exclude = [];

  /// The link of a page: `{path}` is the file's path from the location's
  /// directory, without `.md`, its language and a last `index`.
  String link = '/{path}';
}
