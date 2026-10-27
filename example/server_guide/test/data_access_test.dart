// Chapter 7, data access stand-ins: the services see repositories through
// interfaces; the in-memory beans can be swapped like a database would be
// (here by a test, with BeanOverride).
@TestOn('vm')
library;

import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/order_repository.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/app.dart';

/// Another storage behind the same interface: two books, read-only.
class ShelfRepository implements BookRepository {
  final Map<String, Book> _books = {
    for (final book in const [
      Book(isbn: '9780000000001', title: 'Alpha', author: 'A', price: 1),
      Book(isbn: '9780000000002', title: 'Beta', author: 'B', price: 2),
    ])
      book.isbn: book,
  };

  @override
  List<Book> findAll() => _books.values.toList();

  @override
  Book? findByIsbn(String isbn) => _books[isbn];

  @override
  Book save(Book book) => throw UnsupportedError('read-only');

  @override
  bool delete(String isbn) => false;

  @override
  int count() => _books.length;
}

void main() {
  group('the in-memory repositories', () {
    final app = neonBooks();

    test('hold the sample data and the orders', () {
      expect(app.getBean<BookRepository>().count(), 8);
      final orders = app.getBean<OrderRepository>();
      expect(orders.findAll(), isEmpty);
      expect(orders.nextId(), 1);
    });
  });

  group('another repository', () {
    // Without the dev profile: no sample data to save into it.
    final app = neonBooks(
      profiles: ['test'],
      overrides: [BeanOverride<BookRepository>(ShelfRepository())],
    );

    test('the services use whatever implements the interface', () {
      final page = app.getBean<Catalog>().search('', 0);
      expect(page.items.map((b) => b.title), ['Alpha', 'Beta']);
    });
  });
}
