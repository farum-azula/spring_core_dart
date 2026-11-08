## Unreleased

- The documents are read once and the index of a language is built when that language is first searched: a search waits for its own language only (`SearchService.isIndexed(language)`, `prepare(language:)`).
- `spring.search.indexing: background`: the indexes build right after the start, while the app runs, the default language first.
- `spring.search.indexing` (`first-search` by default, `start`): `start` builds the indexes while the application starts (the `searchIndexRunner`, an `ApplicationRunner`), so a Flutter app builds them behind its splash. `SearchService.prepare()` starts the build now (when the search opens) and `prepared` tells whether it started; a search waits for the same build.
- The indexes build a few dozen documents at a time with a pause between (`SearchIndex.buildAsync`), so an app keeps drawing its frames while they build: the first search no longer freezes the screen. Reading the documents pauses the same way, since resources held in memory give their text without a real pause.
- `SearchRanker.rank` gets the `SearchQuery` searched (`rank(hit, score, query)`): a ranker can put the page whose name the query is first, which the hit alone cannot tell.

## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- Not published yet (`tool/publish.dart` skips it): a git dependency of this repository. The `SearchService` bean searches the documents of the `SearchDocumentSource` beans and of `spring.search.markdown` (Markdown resources cut into sections with GitHub's anchors, translations `name.ja.md` next to the file). Analyzers per language (`SearchAnalyzer` beans, `spring.search.analyzers`): words in any script and Chinese, Japanese and Korean in pairs of characters, camel-case parts, accents, English stop words and endings. BM25 per field (`spring.search.fields`), every word or one of them (`spring.search.operator`), the word being typed as a prefix, typos (`spring.search.fuzzy`), phrases in double quotes, `SearchRanker` beans, one hit per page (`spring.search.collapse-by`), highlights and snippets. `SearchIndexInvalidatedEvent` builds the index again.
