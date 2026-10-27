// Chapter 10, validation and SpEL: constraints and groups, a class-level
// constraint, messages in two languages; SpEL in annotations.
@TestOn('vm')
library;

import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:neon_books_server/src/shop/startup.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/app.dart';

void main() {
  final app = neonBooks(properties: {'neon.shop.name': 'Night Books'});

  BeanValidator validator() => app.getBean<BeanValidator>();

  group('validation', () {
    const draft = NewBook(
      isbn: '9780141439518',
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      price: 5.99,
    );

    test('the default group: what POST /api/books checks', () {
      expect(validator().validateObject(draft), isEmpty);
      final invalid = validator().validateObject(
        const NewBook(isbn: '978', price: -1),
      );
      expect(invalid.map((v) => v.propertyPath).toSet(), {
        'isbn',
        'title',
        'author',
        'price',
      });
    });

    test('a group on top: books from the supplier must be catalogued', () {
      final violations = validator().validateObject(
        draft,
        groups: [Default, Catalogued],
      );
      expect(violations.map((v) => v.propertyPath).toSet(), {'year', 'tags'});
    });

    test('a class-level constraint', () {
      final violations = validator().validateObject(
        ShopProperties()
          ..opensAt = 22
          ..closesAt = 20,
      );
      expect(violations.single.message, 'the shop must close after it opens');
    });

    test('messages from messages*.properties, by Spring code', () {
      final binder =
          DataBinder(
              ShopProperties(),
              objectName: 'shop',
              introspector: app.getBean<BeanIntrospector>(),
            )
            ..validators.add(validator())
            ..bind({'opensAt': '22', 'closesAt': '20'})
            ..validate();
      final error = binder.bindingResult.globalErrors.single;
      expect(error.codes.first, 'ValidOpeningHours.shop');
      expect(
        app.context.getMessageFromResolvable(error),
        'The shop must close after it opens',
      );
      expect(
        app.context.getMessageFromResolvable(error, locale: 'ja'),
        '閉店時刻は開店時刻より後にしてください',
      );
    });
  });

  group('SpEL in annotations', () {
    test(
      "@Value('#{shopProperties.name.toUpperCase()}'): a bean's property",
      () {
        expect(app.getBean<StartupAnnouncement>().banner, 'NIGHT BOOKS');
      },
    );

    // @PreAuthorize("hasRole('ADMIN')"), @PostFilter, @PostAuthorize:
    // test/security_test.dart. @Cacheable(key: "#query + '|' + #page"):
    // test/cache_scheduling_test.dart. @EventListener takes a function as
    // its condition (Dart has no reflection to evaluate a SpEL string on
    // the event): test/events_aop_test.dart.
    test('expressions are parsed at startup', () {
      expect(app.context.isActive, isTrue);
    });
  });
}
