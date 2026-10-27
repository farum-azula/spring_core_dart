// Data access stand-in: there is no database package yet, so the books
// live in memory behind a repository interface, where a Spring Data
// repository would be. (No @Transactional either: it does not exist.)
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class BookRepository {
  List<Book> findAll();

  Book? findByIsbn(String isbn);

  Book save(Book book);

  bool delete(String isbn);

  int count();
}

/// `@Repository`: a stereotype, registered under its own type and its
/// interface (`BookRepository`).
@Repository()
@Log()
class InMemoryBookRepository implements BookRepository {
  final _books = <String, Book>{};

  @PostConstruct()
  void ready() => log.debug('in-memory book repository ready');

  @override
  List<Book> findAll() =>
      _books.values.toList()..sort((a, b) => a.title.compareTo(b.title));

  @override
  Book? findByIsbn(String isbn) => _books[isbn];

  @override
  Book save(Book book) => _books[book.isbn] = book;

  @override
  bool delete(String isbn) => _books.remove(isbn) != null;

  @override
  int count() => _books.length;
}
