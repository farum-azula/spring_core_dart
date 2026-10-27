// The catalog's model: what the API reads and writes as JSON. One
// @Introspected() per model is enough; the classes they use (BookFormat)
// are introspected with them, so there is no fromJson / toJson.
import 'package:spring_core_dart/spring_core_dart.dart';

/// How a book is sold. JSON uses the upper-case names Spring writes for
/// Java enums (`"PAPERBACK"`), through `@JsonValue`.
enum BookFormat {
  paperback('PAPERBACK'),
  hardcover('HARDCOVER'),
  ebook('EBOOK');

  BookFormat(this.json);

  @JsonValue()
  final String json;
}

/// A book of the catalog, with the copies in stock.
@Introspected()
class Book {
  const Book({
    required this.isbn,
    required this.title,
    required this.author,
    required this.price,
    this.year,
    this.tags = const [],
    this.format = BookFormat.paperback,
    this.available = 0,
  });

  final String isbn;
  final String title;
  final String author;
  final double price;
  final int? year;
  final List<String> tags;
  final BookFormat format;

  /// Copies in stock.
  final int available;

  Book withAvailable(int copies) => Book(
    isbn: isbn,
    title: title,
    author: author,
    price: price,
    year: year,
    tags: tags,
    format: format,
    available: copies,
  );

  @override
  String toString() => '$title ($isbn)';
}

/// One page of the catalog: `{"items": [...], "page": 0, "size": 10,
/// "total": 8}`.
@Introspected()
class BookPage {
  const BookPage({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
  });

  final List<Book> items;

  /// The page number, from 0.
  final int page;

  /// Books per page.
  final int size;

  /// Books matching the query, on all pages.
  final int total;
}

/// A validation group: the constraints a book must meet to be taken from
/// the supplier's catalog (chapter 10), on top of the default ones.
abstract final class Catalogued {}

/// The body of `POST /api/books`, validated with `@Valid()`: a violation
/// is a 400 listing the fields. Missing JSON properties keep the defaults
/// here, so they are reported as field errors, not as unreadable JSON.
@Introspected()
class NewBook {
  const NewBook({
    this.isbn = '',
    this.title = '',
    this.author = '',
    this.price = 0,
    this.year,
    this.tags = const [],
    this.format = BookFormat.paperback,
    this.stock = 0,
  });

  @Matches(r'^97[89]\d{10}$')
  final String isbn;

  @NotBlank()
  @Size(max: 120)
  final String title;

  @NotBlank()
  final String author;

  @Positive()
  final double price;

  @NotNull(groups: [Catalogued])
  @Max(2100)
  final int? year;

  @NotEmpty(groups: [Catalogued])
  final List<String> tags;

  final BookFormat format;

  /// Copies in stock to start with.
  @PositiveOrZero()
  final int stock;

  Book toBook() => Book(
    isbn: isbn,
    title: title.trim(),
    author: author.trim(),
    price: price,
    year: year,
    tags: tags,
    format: format,
    available: stock,
  );
}

/// No book with [isbn]: a 404 (see `ApiErrors`).
class BookNotFoundException implements Exception {
  BookNotFoundException(this.isbn);

  final String isbn;

  @override
  String toString() => 'BookNotFoundException: no book $isbn';
}
