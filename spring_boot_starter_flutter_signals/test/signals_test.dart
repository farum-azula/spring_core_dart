// Followed state in beans, on the example app as generated
// (example/spring_gen/example.spring.dart): a field's readers are told of
// an assignment, a computed value is kept, an effect runs again, an
// asynchronous value loads once and again when what it read changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show springBootTest;

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

void main() {
  group('a basket', () {
    final app = springBootTest(springApplication);
    late Basket basket;
    late BasketStorage storage;

    setUp(() {
      basket = app.getBean<Basket>();
      storage = app.getBean<BasketStorage>();
      basket.clear();
      storage.saved.clear();
    });

    test('a field is a plain field', () {
      expect(basket.coupon, isNull);
      basket.coupon = 'TEN';
      expect(basket.coupon, 'TEN');
      basket.add(const Book('Dune', 10));
      expect(basket.items.single.title, 'Dune');
    });

    test('a computed value follows what it read, and is kept', () {
      final state = app.getBean<SignalBeans>().find(basket)!;
      basket.add(const Book('Dune', 10));
      expect(basket.total, 10);
      final total = state.members['total']! as ComputedMember;
      // Read again: the same value, not computed again.
      final kept = total.peek();
      expect(basket.total, 10);
      expect(identical(total.peek(), kept), isTrue);

      basket.coupon = 'TEN';
      expect(basket.total, 9);
      basket.add(const Book('Ubik', 20));
      expect(basket.total, 27);
    });

    test('an effect ran when the bean was made and runs for a change', () {
      final state = app.getBean<SignalBeans>().find(basket)!;
      final runs = state.effectRuns['save']!;
      expect(runs, greaterThan(0));

      basket.add(const Book('Dune', 10));
      expect(storage.saved, [1]);
      expect(state.effectRuns['save'], runs + 1);
    });

    test('a list tells of a change in place, and stays a plain list', () {
      // `add` changes the list in place: no assignment.
      basket.add(const Book('Dune', 10));
      expect(basket.total, 10);
      expect(storage.saved, [1]);

      // From outside the bean too.
      basket.items.add(const Book('Ubik', 20));
      expect(basket.total, 30);
      expect(storage.saved, [1, 2]);

      // An assignment of another list.
      basket.remove('Dune');
      expect(basket.items.single.title, 'Ubik');
      expect(basket.total, 20);
      expect(storage.saved, [1, 2, 1]);

      // What the getter handed out, assigned back: the same list.
      basket.items = basket.items..add(const Book('Solaris', 5));
      expect(basket.items, hasLength(2));
      expect(basket.total, 25);
      expect(basket.items, isA<List<Book>>());
    });

    test('a value equal to the one there tells nobody', () {
      basket.coupon = 'TEN';
      expect(basket.coupon, 'TEN');
      final state = app.getBean<SignalBeans>().find(basket)!;
      final coupon = state.members['coupon']! as ValueMember;
      final changes = coupon.changes;
      basket.coupon = 'TEN';
      expect(coupon.changes, changes);
    });

    test('a read inside untracked is not followed', () {
      basket.add(const Book('Dune', 10));
      storage.saved.clear();
      basket.coupon = 'TEN';
      expect(storage.saved, isEmpty);
    });

    test('a method is one change, whatever it assigns', () {
      basket
        ..add(const Book('Dune', 10))
        ..coupon = 'TEN';
      storage.saved.clear();
      final state = app.getBean<SignalBeans>().find(basket)!;
      final runs = state.effectRuns['save']!;

      // Two assignments in one method.
      basket.clear();

      expect(storage.saved, [0]);
      expect(state.effectRuns['save'], runs + 1);
      expect(basket.total, 0);
    });
  });

  group('a catalog', () {
    final app = springBootTest(springApplication);

    test(
      'one request for every reader, another when the genre changes',
      () async {
        final catalog = app.getBean<Catalog>();
        final client = app.getBean<CatalogClient>();

        final first = catalog.books;
        expect(identical(catalog.books, first), isTrue);
        expect(first.state.isLoading, isTrue);
        expect(first.state.hasValue, isFalse);

        expect((await first).first.title, 'fiction one');
        expect(client.requests, 1);
        expect(catalog.books.state.requireValue.first.title, 'fiction one');
        expect(catalog.books.state.isLoading, isFalse);

        catalog.genre = 'poetry';
        final second = catalog.books;
        expect(identical(second, first), isFalse);
        // A change of what it depends on starts from nothing.
        expect(second.state.hasValue, isFalse);
        expect((await second).first.title, 'poetry one');
        expect(client.requests, 2);
      },
    );

    test('refresh keeps the last value meanwhile, reload does not', () async {
      final catalog = app.getBean<Catalog>();
      final client = app.getBean<CatalogClient>();
      await catalog.books;
      final before = client.requests;

      final refreshed = catalog.books.refresh();
      expect(catalog.books.state.isRefreshing, isTrue);
      expect(catalog.books.state.hasValue, isTrue);
      await refreshed;
      expect(client.requests, before + 1);
      expect(catalog.books.state.isLoading, isFalse);

      final reloaded = catalog.books.reload();
      expect(catalog.books.state.hasValue, isFalse);
      expect(catalog.books.state.isLoading, isTrue);
      await reloaded;
      expect(catalog.books.state.hasValue, isTrue);
    });

    test('an answer that came after a newer request is dropped', () async {
      final catalog = app.getBean<Catalog>();
      catalog.genre = 'slow';
      final slow = catalog.books;
      catalog.genre = 'fast';
      final fast = catalog.books;
      await Future.wait([slow, fast]);
      expect(catalog.books.state.requireValue.first.title, 'fast one');
    });

    test(
      'a stream: its last event, and a new stream for a new genre',
      () async {
        final catalog = app.getBean<Catalog>()..genre = 'drama';
        final price = catalog.price;
        expect(identical(catalog.price, price), isTrue);
        expect(price.state.isLoading, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(catalog.price.state.requireValue, 10);

        catalog.genre = 'epic';
        expect(identical(catalog.price, price), isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(catalog.price.state.requireValue, 8);
      },
    );

    test('a future that is no computed value has no state', () {
      expect(
        () => Future<int>.value(1).state,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('@Computed'),
          ),
        ),
      );
    });
  });

  test('the state ends with the bean, and its fields still read', () async {
    final context = await springApplication.runAsync(const []);
    final basket = context.getBean<Basket>()..add(const Book('Dune', 10));
    final storage = context.getBean<BasketStorage>();
    final beans = context.getBean<SignalBeans>();
    final state = beans.find(basket)!;
    expect(beans.live, contains(state));

    await context.closeAsync();

    expect(state.closed, isTrue);
    // The field itself kept the value; nothing is followed any more.
    expect(basket.items.single.title, 'Dune');
    expect(basket.total, 10);
    final saved = storage.saved.length;
    basket.add(const Book('Ubik', 20));
    expect(storage.saved.length, saved);
  });
}
