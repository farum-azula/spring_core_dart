import 'package:spring_search_dart/src/search_document.dart';

/// Gives the documents to search. Every bean that implements it is read
/// when the index is built, and read again when it is invalidated
/// (`SearchIndexInvalidatedEvent`): the pages of a site, the products of
/// a repository, the notes of a database.
///
/// ```dart
/// @Component()
/// class BookDocuments implements SearchDocumentSource {
///   BookDocuments(this.books);
///   final BookRepository books;
///
///   @override
///   Stream<SearchDocument> documents() async* {
///     for (final book in await books.findAll()) {
///       yield SearchDocument(
///         id: 'book-${book.id}',
///         fields: {'title': book.title, 'body': book.summary},
///         link: '/books/${book.id}',
///       );
///     }
///   }
/// }
/// ```
abstract interface class SearchDocumentSource {
  /// The documents, in any language.
  Stream<SearchDocument> documents();
}

/// A [SearchDocumentSource] that knows the languages of its documents
/// before reading them (a file `name.ja.md` is Japanese), so the search
/// reads the documents of one language only: a site whose pages are
/// downloaded on the web fetches those of the language searched.
///
/// Spring has no counterpart.
abstract interface class LanguageSearchDocumentSource
    implements SearchDocumentSource {
  /// The languages it has documents in.
  Set<String> get languages;

  /// Its documents in [language] (one of [languages]).
  Stream<SearchDocument> documentsIn(String language);
}
