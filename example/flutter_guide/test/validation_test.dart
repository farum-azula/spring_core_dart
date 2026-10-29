// Chapter 9, "Validation": the Admin form binds its texts onto a NewBook
// (DataBinder) and checks its constraints (BeanValidator) before anything
// is sent; the errors carry Spring's codes, the messages files say them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/admin/book_form.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart'
    show SecurityContextHolder;

import 'support/app.dart';
import 'support/fake_server.dart';

void main() {
  final server = FakeServer();
  final app = springBootTest(springApplication, overrides: server.overrides);

  setUp(() {
    app.markDirty();
    server.http.reset();
    server.answerCatalog();
  });
  tearDown(SecurityContextHolder.clearContext);

  test('a valid form gives a NewBook', () {
    final (book, errors) = app.getBean<BookForm>().bind({
      'isbn': '9780441013593',
      'title': ' Dune ',
      'author': 'Frank Herbert',
      'price': '12.50',
    });
    expect(errors.hasErrors, isFalse);
    expect(book!.title, 'Dune');
    expect(book.price, 12.5);
  });

  test("an invalid one: field errors with Spring's codes", () {
    final (book, errors) = app.getBean<BookForm>().bind({
      'isbn': '978-0',
      'title': '',
      'author': 'x' * 81,
      'price': 'twelve',
    });
    expect(book, isNull);
    expect(errors.fieldError('isbn')!.codes, [
      'Pattern.newBook.isbn',
      'Pattern.isbn',
      'Pattern.String',
      'Pattern',
    ]);
    expect(errors.fieldError('title')!.code, 'NotBlank');
    expect(errors.fieldError('author')!.code, 'Size');
    // "twelve" is no double: a binding failure, not a constraint.
    expect(errors.fieldError('price')!.code, 'typeMismatch');
    expect(errors.fieldError('price')!.bindingFailure, isTrue);

    String say(String field, String locale) => app.context
        .getMessageFromResolvable(errors.fieldError(field)!, locale: locale);
    expect(say('isbn', 'en'), 'must be 10 or 13 digits');
    expect(say('author', 'en'), 'must be at most 80 characters');
    expect(say('price', 'en'), 'must be a number');
    expect(say('title', 'ja'), '入力してください');
    expect(say('author', 'ja'), '80 文字以内にしてください');
  });

  testWidgets('the Admin form shows them and sends nothing', (tester) async {
    server.answerLogin('root', roles: ['USER', 'ADMIN']);
    await showPage(tester, app.context, const HomePage());
    await logIn(tester, 'root', 'root-secret');
    await openMore(tester, 'Admin');
    final sent = server.http.requests.length;

    await tester.enterText(find.byKey(const Key('admin-isbn')), '123');
    await tester.enterText(find.byKey(const Key('admin-price')), '-1');
    await tester.tap(find.text('Add the book'));
    await tester.pumpAndSettle();

    expect(find.text('must be 10 or 13 digits'), findsOneWidget);
    expect(find.text('must not be blank'), findsNWidgets(2)); // title, author
    expect(find.text('must be more than 0'), findsOneWidget);
    expect(server.http.requests, hasLength(sent));
  });
}
