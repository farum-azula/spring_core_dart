/// What a search finds: a page, a section of one, a product, a note. Its
/// [fields] are searched (`title`, `heading`, `body`, or the
/// application's own, weighted by `spring.search.fields`); [link] says
/// where it is shown; [attributes] carry what the application needs to
/// show a hit (a section's name, a price) and are not searched.
///
/// ```dart
/// SearchDocument(
///   id: 'book-42',
///   fields: {'title': book.title, 'body': book.summary},
///   link: '/books/42',
///   language: 'en',
/// )
/// ```
final class SearchDocument {
  /// A document [id] with [fields].
  const SearchDocument({
    required this.id,
    required this.fields,
    this.language,
    this.link,
    this.attributes = const {},
  });

  /// Unique among the documents of its language.
  final String id;

  /// The searched texts by field name.
  final Map<String, String> fields;

  /// The language of the texts (`en`, `ja`); `null` for
  /// `spring.search.default-language`.
  final String? language;

  /// Where the document is shown: a route, a URL; `null` when the
  /// application finds it by [id].
  final String? link;

  /// What the application shows with a hit; not searched.
  final Map<String, String> attributes;

  /// The `title` field; empty when there is none.
  String get title => fields['title'] ?? '';

  @override
  String toString() => 'SearchDocument($id)';
}
