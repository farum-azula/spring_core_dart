// The descriptions the generator writes for the application's classes
// (lib/spring_gen/src/app.spring.introspection.dart), registered without a
// context: a unit test of the JSON the API reads and writes needs no
// application.
@TestOn('vm')
library;

import 'package:neon_books_server/spring_gen/src/app.spring.introspection.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => Introspector.shared.registerAll($appBeansIntrospections));

  const emma = Book(
    isbn: '9780141439587',
    title: 'Emma',
    author: 'Jane Austen',
    price: 6.99,
    format: BookFormat.hardcover,
  );

  test('a book is written out as the API writes it', () {
    final json = ObjectMapper().writeValueAsString(emma);

    expect(json, contains('"title":"Emma"'));
    expect(json, contains('"format":"HARDCOVER"'));
  });

  test('a page of books is read back, the classes it uses too', () {
    final mapper = ObjectMapper();
    final json = mapper.writeValueAsString(
      const BookPage(items: [emma], page: 0, size: 10, total: 1),
    );

    final page = mapper.readValue<BookPage>(json);

    expect(page.items.single.title, 'Emma');
    expect(page.items.single.format, BookFormat.hardcover);
    expect(page.total, 1);
  });
}
