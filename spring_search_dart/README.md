# spring_search_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-search-dart](https://farum-azula.org/components/spring-search-dart)

Full-text search for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications, on the VM, in Flutter and on the web: the pages of a
documentation site, the products of a shop, the notes of an app. Pure
Dart, no server, no native code.

Add the dependency, say where the documents come from, and ask the
`SearchService` bean:

Not on pub.dev yet; take it from the repository:

```yaml
dependencies:
  spring_search_dart:
    git:
      url: https://github.com/farum-azula/spring_core_dart.git
      path: spring_search_dart
```

```yaml
spring:
  search:
    markdown:
      - location: resources:content/**/*.md
        exclude: ['**/contents*.md']
        link: /docs/{path}
    collapse-by: page
```

```dart
final hits = await context.getBean<SearchService>().search(
  'bean factory',
  language: 'en',
);
for (final hit in hits) {
  final snippet = hit.snippet('body');
  print('${hit.document.title} ${hit.document.link}: ${snippet.text}');
}
```

## What it finds

- Every word of the query (`spring.search.operator: or` for one of
  them), ranked with BM25; a field weighs as `spring.search.fields` says
  (`title` 8, `heading` 4, `body` 1 by default).
- The last word while it is being typed, as the start of longer ones:
  `bea` finds `bean`.
- Words with a typo: `contxet` finds `context` (`spring.search.fuzzy`).
- Phrases: `"bean factory"` finds the two words next to each other.
- Words of any script. Chinese, Japanese and Korean are cut in pairs of
  characters, so `依存性` finds `依存性注入` without a dictionary.
- The parts of camel-case names: `context` finds `ApplicationContext`.
- In English, the forms of a word: `binding` finds `binds`.

Each hit has its document, its score, the stretches of each field that
matched (`highlights`) and `snippet(field)`, a piece of the text around
the first match (160 characters by default, `length:`). `search(query,
language:, limit:)` takes at most `limit` hits (`spring.search.max-hits`
by default).

## Documents

A document has an `id`, searched `fields`, a `language`, a `link` and
`attributes` shown with it. They come from:

- `spring.search.markdown[n]`: Markdown files cut into one document per
  section, with the page's `title`, the section's `heading` and `body`,
  and the link of the section (`/docs/beans#scope`), and the attributes
  `page` (the page's link, for `collapse-by: page`), `section` and
  `path`. `name.ja.md` is the Japanese of `name.md`; a page without a
  translation is searched in the other languages too, in its own.
- Any bean that implements `SearchDocumentSource`:

```dart
@Component()
class BookDocuments implements SearchDocumentSource {
  BookDocuments(this.books);
  final BookRepository books;

  @override
  Stream<SearchDocument> documents() async* {
    for (final book in await books.findAll()) {
      yield SearchDocument(
        id: 'book-${book.id}',
        fields: {'title': book.title, 'body': book.summary},
        link: '/books/${book.id}',
      );
    }
  }
}
```

The index is built at the first search, one per language. Publish a
`SearchIndexInvalidatedEvent` when the documents change.

## Extending it

Everything is a bean, asked in `@Order`:

| Bean | What it does |
|---|---|
| `SearchDocumentSource` | Gives documents |
| `SearchAnalyzer` | Cuts the text of a language into terms: a `SearchTokenizer` then `SearchTokenFilter`s. Name it in `spring.search.analyzers.<language>` |
| `SearchRanker` | Changes the score of each hit, after the index |

The filters that come with it: `WordPartsFilter` (camel-case parts),
`LowerCaseFilter`, `AsciiFoldingFilter` (accents removed),
`StopWordFilter` (`StopWordFilter.english`, or your own words) and
`EnglishStemFilter`; the tokenizer is `StandardTokenizer`. The built-in
analyzers are `standard` and `english`; a bean of the same name replaces
one. A filter of your own implements `SearchTokenFilter` (a German
stemmer, say).

```dart
@Bean()
SearchAnalyzer german() => const SearchAnalyzer(
  'german',
  filters: [
    WordPartsFilter(),
    LowerCaseFilter(),
    AsciiFoldingFilter(),
    StopWordFilter({'der', 'die', 'das', 'und', 'ist'}),
  ],
);
```

```yaml
spring:
  search:
    analyzers:
      de: german
```

## Properties

| Key | Default | Meaning |
|---|---|---|
| `spring.search.enabled` | `true` | `false`: no `SearchService` |
| `spring.search.default-language` | `en` | The language of documents and searches that name none |
| `spring.search.fields.<field>` | `title` 8, `heading` 4, `body` 1 | The weight of a field |
| `spring.search.fuzzy` | `1` | Typos per word of Latin letters (at most one below eight letters, none below five); `0` for none |
| `spring.search.max-hits` | `20` | The most hits of a search |
| `spring.search.operator` | `and` | `and`: every word; `or`: one of them |
| `spring.search.analyzers.<language>` | `english` for `en`, `standard` otherwise | The analyzer of a language |
| `spring.search.collapse-by` | none | Keep the best hit per value of this attribute (`page`) |
| `spring.search.markdown[n].location` | — | The Markdown files, a `resources:` pattern |
| `spring.search.markdown[n].exclude` | none | Files left out, relative to the location's directory |
| `spring.search.markdown[n].link` | `/{path}` | A page's link; `{path}` is the file's path without `.md`, its language and a last `index` |

Spring has no counterpart; it plays the part of Hibernate Search or a
search server's client, inside the application.
