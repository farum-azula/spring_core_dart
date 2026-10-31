import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../support/app.dart';

void main() {
  group('save and load', () {
    test('a new entity gets a generated id and version 1', () async {
      await withExample((app) async {
        final first = await app.books.save(Book(title: 'Dune', year: 1965));
        final second = await app.books.save(Book(title: 'Emma', year: 1815));
        expect(first.id, 1);
        expect(second.id, 2);
        expect(first.version, 1);
        expect(await app.books.count(), 2);
      });
    });

    test('ids are generated per table, each from 1', () async {
      await withExample((app) async {
        await app.books.save(Book(title: 'Dune', year: 1965));
        final author = await app.authors.save(Author(name: 'Herbert'));
        expect(author.id, 1);
      });
    });

    test('an id that is set moves the counter past it', () async {
      await withExample((app) async {
        // Version 0 or null: new, so inserted with its own id.
        await app.books.save(Book(id: 10, title: 'Dune', year: 1965));
        final next = await app.books.save(Book(title: 'Emma', year: 1815));
        expect(next.id, 11);
      });
    });

    test('a loaded entity is a fresh copy', () async {
      await withExample((app) async {
        final saved = await app.books.save(Book(title: 'Dune', year: 1965));
        final one = (await app.books.findById(saved.id!))!;
        final two = (await app.books.findById(saved.id!))!;
        expect(one, isNot(same(saved)));
        expect(one, isNot(same(two)));
        one.title = 'Changed';
        expect((await app.books.findById(saved.id!))!.title, 'Dune');
        // Changing the saved instance changes nothing either, until saved.
        saved.title = 'Edited';
        expect((await app.books.findById(saved.id!))!.title, 'Dune');
        await app.books.save(saved);
        expect((await app.books.findById(saved.id!))!.title, 'Edited');
      });
    });

    test('findById gives null for an unknown id', () async {
      await withExample((app) async {
        expect(await app.books.findById(99), isNull);
      });
    });

    test(
      'a save of the loaded entity updates it and raises the version',
      () async {
        await withExample((app) async {
          final saved = await app.books.save(Book(title: 'Dune', year: 1965));
          saved.title = 'Dune!';
          final updated = await app.books.save(saved);
          expect(updated.version, 2);
          expect(updated.id, saved.id);
          expect(await app.books.count(), 1);
        });
      },
    );

    test('saveAll saves each and returns them in order', () async {
      await withExample((app) async {
        final saved = await app.books.saveAll([
          Book(title: 'a', year: 1),
          Book(title: 'b', year: 2),
        ]);
        expect(saved, hasLength(2));
        expect(ids(saved), [1, 2]);
        expect(saved, isA<List<Book>>());
      });
    });

    test('findAll, findAllById, existsById and count', () async {
      await withExample((app) async {
        await seedBooks(app.books);
        expect(ids(await app.books.findAll()), [1, 2, 3, 4, 5, 6, 7, 8]);
        expect(ids(await app.books.findAllById([5, 2, 99])), [2, 5]);
        expect(await app.books.existsById(3), isTrue);
        expect(await app.books.existsById(30), isFalse);
        expect(await app.books.count(), 8);
      });
    });

    test('findAllSorted and findAllPaged', () async {
      await withExample((app) async {
        await seedBooks(app.books);
        final byYear = await app.books.findAllSorted(
          Sort.byOrders([const SortOrder.desc('year')]),
        );
        expect(ids(byYear), [8, 7, 6, 5, 4, 3, 2, 1]);
        final page = await app.books.findAllPaged(
          PageRequest.of(1, 3, Sort.by(['id'])),
        );
        expect(ids(page.content), [4, 5, 6]);
        expect(page.totalElements, 8);
        expect(page.totalPages, 3);
        expect(page.hasNext, isTrue);
        expect(page, isA<Page<Book>>());
        final unpaged = await app.books.findAllPaged(
          const Pageable.unpaged(),
        );
        expect(unpaged.content, hasLength(8));
      });
    });
  });

  group('delete', () {
    test('deleteById, delete, deleteAllById, deleteAllOf, deleteAll', () async {
      await withExample((app) async {
        await seedBooks(app.books);
        await app.books.deleteById(1);
        expect(await app.books.existsById(1), isFalse);
        // A missing id is no error.
        await app.books.deleteById(1);

        final two = (await app.books.findById(2))!;
        await app.books.delete(two);
        expect(await app.books.existsById(2), isFalse);

        await app.books.deleteAllById([3, 4, 99]);
        expect(ids(await app.books.findAll()), [5, 6, 7, 8]);

        final loaded = await app.books.findAllById([5, 6]);
        await app.books.deleteAllOf(loaded);
        expect(ids(await app.books.findAll()), [7, 8]);

        await app.books.deleteAll();
        expect(await app.books.count(), 0);
      });
    });

    test('deleting an entity without an id fails', () async {
      await withExample((app) async {
        await expectLater(
          app.books.delete(Book(title: 'x', year: 1)),
          throwsA(isA<InvalidDataAccessApiUsageException>()),
        );
      });
    });
  });

  group('optimistic locking', () {
    test('two loads, two saves: the second fails', () async {
      await withExample((app) async {
        final saved = await app.books.save(Book(title: 'Dune', year: 1965));
        final a = (await app.books.findById(saved.id!))!;
        final b = (await app.books.findById(saved.id!))!;
        a.title = 'A';
        b.title = 'B';
        await app.books.save(a);
        await expectLater(
          app.books.save(b),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
        expect((await app.books.findById(saved.id!))!.title, 'A');
      });
    });

    test('concurrent saves of one version: one wins', () async {
      await withExample((app) async {
        final saved = await app.books.save(Book(title: 'Dune', year: 1965));
        final a = (await app.books.findById(saved.id!))!..title = 'A';
        final b = (await app.books.findById(saved.id!))!..title = 'B';
        final results = await Future.wait([
          app.books
              .save(a)
              .then<Object>((_) => 'ok')
              .catchError(
                (Object e) => e,
              ),
          app.books
              .save(b)
              .then<Object>((_) => 'ok')
              .catchError(
                (Object e) => e,
              ),
        ]);
        expect(results.where((r) => r == 'ok'), hasLength(1));
        expect(
          results.whereType<OptimisticLockingFailureException>(),
          hasLength(1),
        );
        expect((await app.books.findById(saved.id!))!.version, 2);
      });
    });

    test('an update of a deleted entity fails', () async {
      await withExample((app) async {
        final saved = await app.books.save(Book(title: 'Dune', year: 1965));
        await app.books.deleteById(saved.id!);
        await expectLater(
          app.books.save(saved),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
      });
    });

    test(
      'delete with a stale version fails, deleteById does not care',
      () async {
        await withExample((app) async {
          final saved = await app.books.save(Book(title: 'Dune', year: 1965));
          final stale = (await app.books.findById(saved.id!))!;
          saved.title = 'Newer';
          await app.books.save(saved);
          await expectLater(
            app.books.delete(stale),
            throwsA(isA<OptimisticLockingFailureException>()),
          );
          expect(await app.books.existsById(saved.id!), isTrue);
          await app.books.deleteById(saved.id!);
          expect(await app.books.existsById(saved.id!), isFalse);
        });
      },
    );

    test('a version that is a DateTime changes at each write', () async {
      await withExample((app) async {
        final saved = await app.tickets.save(Ticket(subject: 'Bug'));
        final first = saved.stamp!;
        final a = (await app.tickets.findById(saved.id!))!;
        final b = (await app.tickets.findById(saved.id!))!;
        a.subject = 'A';
        final updated = await app.tickets.save(a);
        expect(updated.stamp!.isAfter(first), isTrue);
        b.subject = 'B';
        await expectLater(
          app.tickets.save(b),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
      });
    });
  });

  group('ids the application gives', () {
    test(
      'an immutable entity: save returns the copy with its version',
      () async {
        await withExample((app) async {
          const account = Account(iban: 'DE01', owner: 'Ada');
          final saved = await app.accounts.save(account);
          expect(saved, isNot(same(account)));
          expect(saved.version, 1);
          expect(saved.iban, 'DE01');
          final loaded = (await app.accounts.findById('DE01'))!;
          expect(loaded.owner, 'Ada');
          expect(loaded.version, 1);

          final renamed = await app.accounts.save(
            Account(iban: 'DE01', owner: 'Grace', version: loaded.version),
          );
          expect(renamed.version, 2);
          expect(await app.accounts.findByOwner('Grace'), hasLength(1));
          expect(await app.accounts.findByOwner('Ada'), isEmpty);
        });
      },
    );

    test('a duplicate id on insert is a DuplicateKeyException', () async {
      await withExample((app) async {
        await app.accounts.save(const Account(iban: 'DE01', owner: 'Ada'));
        await expectLater(
          app.accounts.save(const Account(iban: 'DE01', owner: 'Eve')),
          throwsA(isA<DuplicateKeyException>()),
        );
      });
    });

    test('an int id that is set, without a version, is an update', () async {
      await withExample((app) async {
        // Authors have no @Version: an id means update; no row means error.
        await expectLater(
          app.authors.save(Author(name: 'Ghost', id: 5)),
          throwsA(isA<IncorrectUpdateSemanticsDataAccessException>()),
        );
      });
    });
  });

  group('auditing', () {
    test('dates and auditor are set on create and on update', () async {
      var now = DateTime.utc(2024);
      final runner = exampleRunner.withBean<DateTimeProvider>(
        () => DateTimeProvider(() => now),
      );
      await withExample(runner: runner, (app) async {
        final saved = await app.books.save(Book(title: 'Dune', year: 1965));
        expect(saved.createdAt, DateTime.utc(2024));
        expect(saved.modifiedAt, DateTime.utc(2024));
        expect(saved.createdBy, 'librarian');
        expect(saved.modifiedBy, 'librarian');

        now = DateTime.utc(2024, 6);
        final loaded = (await app.books.findById(saved.id!))!..title = 'Dune!';
        final updated = await app.books.save(loaded);
        expect(updated.createdAt, DateTime.utc(2024));
        expect(updated.modifiedAt, DateTime.utc(2024, 6));
        final stored = (await app.books.findById(saved.id!))!;
        expect(stored.createdAt, DateTime.utc(2024));
        expect(stored.modifiedAt, DateTime.utc(2024, 6));
      });
    });
  });

  group('mapped collections', () {
    test('are saved, loaded in order and deleted with the root', () async {
      await withExample((app) async {
        final saved = await app.orders.save(
          PurchaseOrder(
            customer: 'Ada',
            lines: [
              OrderLine(sku: 'b', quantity: 2),
              OrderLine(sku: 'a', quantity: 1),
            ],
            notes: {'gift': OrderNote(text: 'wrap it')},
          ),
        );
        expect(saved.id, 1);
        final loaded = (await app.orders.findById(1))!;
        expect([for (final l in loaded.lines) l.sku], ['b', 'a']);
        expect(loaded.lines.first.quantity, 2);
        expect(loaded.notes['gift']!.text, 'wrap it');
        expect(loaded.lines, isA<List<OrderLine>>());
        expect(loaded.notes, isA<Map<String, OrderNote>>());

        // Fresh copies, children included.
        loaded.lines.first.quantity = 99;
        expect((await app.orders.findById(1))!.lines.first.quantity, 2);

        await app.orders.deleteById(1);
        expect(await app.orders.findById(1), isNull);
        expect(app.store.size(app.entity<PurchaseOrder>()), 0);
      });
    });

    test('are replaced when the root is saved again', () async {
      await withExample((app) async {
        final saved = await app.orders.save(
          PurchaseOrder(
            customer: 'Ada',
            lines: [
              OrderLine(sku: 'a', quantity: 1),
              OrderLine(sku: 'b', quantity: 1),
            ],
          ),
        );
        final loaded = (await app.orders.findById(saved.id!))!
          ..lines = [OrderLine(sku: 'c', quantity: 3)]
          ..notes = {'n': OrderNote(text: 'hi')};
        await app.orders.save(loaded);

        final again = (await app.orders.findById(saved.id!))!;
        expect([for (final l in again.lines) l.sku], ['c']);
        expect(again.notes.keys, ['n']);

        again
          ..lines = []
          ..notes = {};
        await app.orders.save(again);
        final empty = (await app.orders.findById(saved.id!))!;
        expect(empty.lines, isEmpty);
        expect(empty.notes, isEmpty);
      });
    });

    test('derived queries on the root, deleteAll with children', () async {
      await withExample((app) async {
        await app.orders.saveAll([
          PurchaseOrder(
            customer: 'Ada',
            lines: [OrderLine(sku: 'a', quantity: 1)],
          ),
          PurchaseOrder(
            customer: 'Bob',
            lines: [OrderLine(sku: 'b', quantity: 1)],
          ),
          PurchaseOrder(customer: 'Ada'),
        ]);
        final found = await app.orders.findByCustomer('Ada');
        expect(found, hasLength(2));
        expect(found.first.lines, hasLength(1));
        await app.orders.deleteAll();
        expect(await app.orders.count(), 0);
      });
    });
  });

  group('aggregate references', () {
    test('are stored as ids and read back as references', () async {
      await withExample((app) async {
        final saved = await app.books.save(
          Book(title: 'Dune', year: 1965, author: author(7)),
        );
        final loaded = (await app.books.findById(saved.id!))!;
        expect(loaded.author, author(7));
        expect(loaded.author!.id, 7);
        expect(loaded.author, isA<AggregateReference<Author, int>>());
      });
    });
  });

  group('stores', () {
    test(
      '@UseStore(memory) with @UseDataSource has a store of its own',
      () async {
        await withExample((app) async {
          await app.authors.save(Author(name: 'Herbert'));
          expect(await app.authors.count(), 1);
          // The default store never saw it.
          expect(app.store.size(app.entity<Author>()), 0);
          expect(await app.authors.findByNameStartingWith('Her'), hasLength(1));
        });
      },
    );
  });
}
