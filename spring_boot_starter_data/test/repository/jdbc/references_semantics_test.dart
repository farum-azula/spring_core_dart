// The semantics of references, foreign keys and unique keys, on the stores:
// the same calls and the same assertions run on the in-memory store, on
// SQLite (whose tables the starter creates from the annotations, with
// `PRAGMA foreign_keys = ON`) and, when SPRING_TEST_POSTGRES_URL names a
// server, on PostgreSQL, so a test that passes in memory does not fail in
// production. Same approach as semantics_test.dart.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../../postgres/support.dart' show postgresSkip;
import 'support.dart';

/// The repositories of the store under test.
final class Refs {
  Refs(
    this.context, {
    required this.books,
    required this.clubs,
    required this.fans,
    required this.sponsors,
    required this.players,
    required this.goals,
    required this.coaches,
    required this.squads,
    required this.employees,
    required this.categories,
    required this.folders,
    required this.citizens,
  });

  factory Refs.memory(Jdbc j) => Refs(
    j,
    books: j.memoryBooks,
    clubs: j.context.getBean<MemoryClubs>(),
    fans: j.context.getBean<MemoryFans>(),
    sponsors: j.context.getBean<MemorySponsors>(),
    players: j.context.getBean<MemoryPlayers>(),
    goals: j.context.getBean<MemoryGoals>(),
    coaches: j.context.getBean<MemoryCoaches>(),
    squads: j.context.getBean<MemorySquads>(),
    employees: j.context.getBean<MemoryEmployees>(),
    categories: j.context.getBean<MemoryCategories>(),
    folders: j.context.getBean<MemoryFolders>(),
    citizens: j.context.getBean<MemoryCitizens>(),
  );

  factory Refs.sql(Jdbc j) => Refs(
    j,
    books: j.sqlBooks,
    clubs: j.context.getBean<SqlClubs>(),
    fans: j.context.getBean<SqlFans>(),
    sponsors: j.context.getBean<SqlSponsors>(),
    players: j.context.getBean<SqlPlayers>(),
    goals: j.context.getBean<SqlGoals>(),
    coaches: j.context.getBean<SqlCoaches>(),
    squads: j.context.getBean<SqlSquads>(),
    employees: j.context.getBean<SqlEmployees>(),
    categories: j.context.getBean<SqlCategories>(),
    folders: j.context.getBean<SqlFolders>(),
    citizens: j.context.getBean<SqlCitizens>(),
  );

  final Jdbc context;
  final BookQueries books;
  final ListCrudRepository<Club, int> clubs;
  final FanQueries fans;
  final ListCrudRepository<Sponsor, int> sponsors;
  final ListCrudRepository<Player, int> players;
  final ListCrudRepository<Goal, int> goals;
  final ListCrudRepository<Coach, int> coaches;
  final ListCrudRepository<Squad, int> squads;
  final EmployeeQueries employees;
  final CategoryQueries categories;
  final ListCrudRepository<Folder, int> folders;
  final CitizenQueries citizens;
}

// A constraint violation that is not a duplicate key.
final Matcher integrityViolation = throwsA(
  isA<DataIntegrityViolationException>().having(
    (e) => e is DuplicateKeyException,
    'is a DuplicateKeyException',
    isFalse,
  ),
);

final Matcher duplicateKey = throwsA(isA<DuplicateKeyException>());

void main() {
  for (final store in const ['memory', 'sqlite', 'postgres']) {
    group(
      store,
      () => _suite(store),
      skip: store == 'postgres' ? postgresSkip : null,
      tags: store == 'postgres' ? 'postgres' : null,
    );
  }
}

void _suite(String store) {
  final sql = store != 'memory';
  late Refs refs;
  late TransactionTemplate tx;

  Future<void> run(Future<void> Function() body) =>
      withJdbc(postgres: store == 'postgres', (j) async {
        refs = sql ? Refs.sql(j) : Refs.memory(j);
        tx = sql
            ? j.transaction()
            : TransactionTemplate(
                InMemoryTransactionManager(
                  j.factory.stores['memory']! as InMemoryDataStore,
                ),
              );
        await body();
      });

  Future<int> club(String name) async => (await refs.clubs.save(
    Club(name: name),
  )).id!;

  group('foreign keys', () {
    test(
      'an insert that references nothing there fails and stores nothing',
      () => run(() async {
        await expectLater(
          refs.fans.save(Fan(name: 'Ann', clubId: 99)),
          integrityViolation,
        );
        // The same for an AggregateReference and for a nullable property.
        await expectLater(
          refs.players.save(
            Player(name: 'Pat', club: const AggregateReference(99)),
          ),
          integrityViolation,
        );
        await expectLater(
          refs.coaches.save(Coach(name: 'Cy', clubId: 99)),
          integrityViolation,
        );
        expect(await refs.fans.count(), 0);
        expect(await refs.players.count(), 0);
        expect(await refs.coaches.count(), 0);
      }),
    );

    test(
      'an insert that references an aggregate there is fine',
      () => run(() async {
        final id = await club('Reds');
        final fan = await refs.fans.save(Fan(name: 'Ann', clubId: id));
        expect((await refs.fans.findById(fan.id!))!.clubId, id);
        final player = await refs.players.save(
          Player(name: 'Pat', club: AggregateReference(id)),
        );
        expect((await refs.players.findById(player.id!))!.club.id, id);
      }),
    );

    test(
      'a null reference is never checked',
      () => run(() async {
        final coach = await refs.coaches.save(Coach(name: 'Cy'));
        expect((await refs.coaches.findById(coach.id!))!.clubId, isNull);
        final boss = await refs.employees.save(Employee(name: 'Eve'));
        expect(boss.bossId, isNull);
      }),
    );

    test(
      'an update to an aggregate that is not there fails and keeps the row',
      () => run(() async {
        final id = await club('Reds');
        final fan = await refs.fans.save(Fan(name: 'Ann', clubId: id));
        fan.clubId = 99;
        await expectLater(refs.fans.save(fan), integrityViolation);
        expect((await refs.fans.findById(fan.id!))!.clubId, id);
      }),
    );

    test(
      'a row may reference itself, and be deleted',
      () => run(() async {
        final eve = await refs.employees.save(Employee(name: 'Eve'));
        eve.bossId = eve.id;
        await refs.employees.save(eve);
        expect((await refs.employees.findById(eve.id!))!.bossId, eve.id);
        // Referencing a row that is not there is still refused.
        eve.bossId = 99;
        await expectLater(refs.employees.save(eve), integrityViolation);
        eve.bossId = eve.id;
        await refs.employees.deleteById(eve.id!);
        expect(await refs.employees.count(), 0);
      }),
    );

    test(
      'the children of an aggregate reference too',
      () => run(() async {
        await expectLater(
          refs.squads.save(
            Squad(
              name: 'A',
              places: [Place(label: 'one', clubId: 99)],
            ),
          ),
          integrityViolation,
        );
        expect(await refs.squads.count(), 0);
        final id = await club('Reds');
        final squad = await refs.squads.save(
          Squad(
            name: 'A',
            places: [Place(label: 'one', clubId: id)],
          ),
        );
        squad.places.add(Place(label: 'two', clubId: 99));
        await expectLater(refs.squads.save(squad), integrityViolation);
        expect(
          (await refs.squads.findById(squad.id!))!.places.map((p) => p.label),
          ['one'],
        );
      }),
    );

    test(
      'a derived query and a @Query work on a plain reference',
      () => run(() async {
        final reds = await club('Reds');
        final blues = await club('Blues');
        await refs.fans.saveAll([
          Fan(name: 'Ann', clubId: reds),
          Fan(name: 'Bob', clubId: blues),
          Fan(name: 'Cat', clubId: reds),
        ]);
        expect(
          (await refs.fans.findByClubId(reds)).map((f) => f.name),
          ['Ann', 'Cat'],
        );
        if (sql) {
          expect(
            (await refs.context.context.getBean<SqlFans>().byClub(blues))
                .map((f) => f.name),
            ['Bob'],
          );
        }
      }),
    );
  });

  group('on delete', () {
    test(
      'noAction (the default): the delete fails while aggregates reference',
      () => run(() async {
        final id = await club('Reds');
        final fan = await refs.fans.save(Fan(name: 'Ann', clubId: id));
        await expectLater(refs.clubs.deleteById(id), integrityViolation);
        expect(await refs.clubs.count(), 1);
        await refs.fans.deleteById(fan.id!);
        await refs.clubs.deleteById(id);
        expect(await refs.clubs.count(), 0);
      }),
    );

    test(
      'a delete of the entity is refused the same way',
      () => run(() async {
        final reds = await refs.clubs.save(Club(name: 'Reds'));
        await refs.fans.save(Fan(name: 'Ann', clubId: reds.id!));
        await expectLater(refs.clubs.delete(reds), integrityViolation);
        expect(await refs.clubs.count(), 1);
      }),
    );

    test(
      'restrict: the same, at once',
      () => run(() async {
        final id = await club('Reds');
        final sponsor = await refs.sponsors.save(
          Sponsor(name: 'Acme', clubId: id),
        );
        await expectLater(refs.clubs.deleteById(id), integrityViolation);
        await refs.sponsors.deleteById(sponsor.id!);
        await refs.clubs.deleteById(id);
        expect(await refs.clubs.count(), 0);
      }),
    );

    test(
      'cascade: the referencing aggregates go, recursively, with children',
      () => run(() async {
        final reds = await club('Reds');
        final blues = await club('Blues');
        final pat = await refs.players.save(
          Player(
            name: 'Pat',
            club: AggregateReference(reds),
            medals: [
              Medal(title: 'gold'),
              Medal(title: 'silver'),
            ],
          ),
        );
        await refs.players.save(
          Player(name: 'Sam', club: AggregateReference(reds)),
        );
        final kim = await refs.players.save(
          Player(
            name: 'Kim',
            club: AggregateReference(blues),
            medals: [Medal(title: 'bronze')],
          ),
        );
        await refs.goals.saveAll([
          Goal(playerId: pat.id!, minute: 10),
          Goal(playerId: pat.id!, minute: 20),
          Goal(playerId: kim.id!, minute: 30),
        ]);
        await refs.clubs.deleteById(reds);
        expect(
          (await refs.players.findAll()).map((p) => p.name),
          ['Kim'],
        );
        expect((await refs.goals.findAll()).map((g) => g.minute), [30]);
        expect(
          (await refs.players.findById(kim.id!))!.medals.map((m) => m.title),
          ['bronze'],
        );
        if (sql) {
          // The database removed the children of the players too.
          expect(
            await refs.context.jdbc.queryForObject<int>(
              'select count(*) from medals',
            ),
            1,
          );
        }
        expect(await refs.clubs.count(), 1);
      }),
    );

    test(
      'cascade removes the child rows that reference; the root stays',
      () => run(() async {
        final reds = await club('Reds');
        final blues = await club('Blues');
        final squad = await refs.squads.save(
          Squad(
            name: 'A',
            places: [
              Place(label: 'one', clubId: reds),
              Place(label: 'two', clubId: blues),
              Place(label: 'three', clubId: reds),
            ],
          ),
        );
        await refs.clubs.deleteById(reds);
        final loaded = (await refs.squads.findById(squad.id!))!;
        expect(loaded.places.map((p) => p.label), ['two']);
      }),
    );

    test(
      'setNull: the reference is cleared, the aggregate stays',
      () => run(() async {
        final reds = await club('Reds');
        final blues = await club('Blues');
        final cy = await refs.coaches.save(Coach(name: 'Cy', clubId: reds));
        final di = await refs.coaches.save(Coach(name: 'Di', clubId: blues));
        await refs.clubs.deleteById(reds);
        expect((await refs.coaches.findById(cy.id!))!.clubId, isNull);
        expect((await refs.coaches.findById(di.id!))!.clubId, blues);
      }),
    );

    test(
      'a delete that fails undoes the cascades it already made',
      () => run(() async {
        final id = await club('Reds');
        await refs.players.save(
          Player(name: 'Pat', club: AggregateReference(id)),
        );
        await refs.coaches.save(Coach(name: 'Cy', clubId: id));
        // The fan blocks the delete after the cascade and the set null.
        await refs.fans.save(Fan(name: 'Ann', clubId: id));
        await expectLater(refs.clubs.deleteById(id), integrityViolation);
        expect(await refs.players.count(), 1);
        expect((await refs.coaches.findAll()).single.clubId, id);
        expect(await refs.clubs.count(), 1);
      }),
    );

    test(
      'cascade and setNull are undone with the transaction',
      () => run(() async {
        final id = await club('Reds');
        final pat = await refs.players.save(
          Player(name: 'Pat', club: AggregateReference(id)),
        );
        await refs.goals.save(Goal(playerId: pat.id!, minute: 1));
        final cy = await refs.coaches.save(Coach(name: 'Cy', clubId: id));
        await expectLater(
          tx.execute((_) async {
            await refs.clubs.deleteById(id);
            // Seen inside the transaction.
            expect(await refs.clubs.count(), 0);
            expect(await refs.players.count(), 0);
            expect(await refs.goals.count(), 0);
            expect((await refs.coaches.findById(cy.id!))!.clubId, isNull);
            throw StateError('stop');
          }),
          throwsStateError,
        );
        expect(await refs.clubs.count(), 1);
        expect(await refs.players.count(), 1);
        expect(await refs.goals.count(), 1);
        expect((await refs.coaches.findById(cy.id!))!.clubId, id);
      }),
    );

    test(
      'cascade and setNull are kept when the transaction commits',
      () => run(() async {
        final id = await club('Reds');
        final pat = await refs.players.save(
          Player(name: 'Pat', club: AggregateReference(id)),
        );
        await refs.goals.save(Goal(playerId: pat.id!, minute: 1));
        final cy = await refs.coaches.save(Coach(name: 'Cy', clubId: id));
        await tx.execute((_) => refs.clubs.deleteById(id));
        expect(await refs.players.count(), 0);
        expect(await refs.goals.count(), 0);
        expect((await refs.coaches.findById(cy.id!))!.clubId, isNull);
      }),
    );

    test(
      'a reference made in a transaction is seen by the check inside it',
      () => run(() async {
        await tx.execute((_) async {
          final id = await club('Reds');
          await refs.fans.save(Fan(name: 'Ann', clubId: id));
        });
        expect(await refs.fans.count(), 1);
      }),
    );

    test(
      'self-reference with noAction: the check is made when the statement '
      'ends',
      () => run(() async {
        final boss = await refs.employees.save(Employee(name: 'E boss'));
        await refs.employees.save(
          Employee(name: 'E report', bossId: boss.id),
        );
        await expectLater(
          refs.employees.deleteById(boss.id!),
          integrityViolation,
        );
        // Both rows in one statement: nothing references what remains.
        expect(await refs.employees.deleteByNameStartingWith('E'), 2);
        expect(await refs.employees.count(), 0);
      }),
    );

    test(
      'self-reference with restrict: row by row, in the order of the table',
      () => run(() async {
        final top = await refs.categories.save(Category(name: 'c top'));
        final sub = await refs.categories.save(
          Category(name: 'c sub', parentId: top.id),
        );
        if (store == 'postgres') {
          // RESTRICT looks when the statement is done, not row by row: both
          // rows are gone by then, whatever the order of the table.
          expect(await refs.categories.deleteByNameStartingWith('c'), 2);
          expect(await refs.categories.count(), 0);
          return;
        }
        // The parent comes first: it is deleted while its child exists.
        await expectLater(
          refs.categories.deleteByNameStartingWith('c'),
          integrityViolation,
        );
        expect(await refs.categories.count(), 2);
        // Now the child comes first in the table.
        top.parentId = sub.id;
        sub.parentId = null;
        await refs.categories.save(sub);
        await refs.categories.save(top);
        expect(await refs.categories.deleteByNameStartingWith('c'), 2);
        expect(await refs.categories.count(), 0);
      }),
    );

    test(
      'self-reference with cascade: the whole tree below goes',
      () => run(() async {
        final root = await refs.folders.save(Folder(name: 'root'));
        final child = await refs.folders.save(
          Folder(name: 'child', parentId: root.id),
        );
        await refs.folders.save(Folder(name: 'leaf', parentId: child.id));
        await refs.folders.save(Folder(name: 'other'));
        await refs.folders.deleteById(root.id!);
        expect((await refs.folders.findAll()).map((f) => f.name), ['other']);
      }),
    );
  });

  group('unique', () {
    test(
      'a duplicate value is a DuplicateKeyException, on insert and update',
      () => run(() async {
        final reds = await refs.clubs.save(Club(name: 'Reds'));
        final blues = await refs.clubs.save(Club(name: 'Blues'));
        await expectLater(refs.clubs.save(Club(name: 'Reds')), duplicateKey);
        blues.name = 'Reds';
        await expectLater(refs.clubs.save(blues), duplicateKey);
        expect((await refs.clubs.findById(blues.id!))!.name, 'Blues');
        // A row never conflicts with itself.
        reds.name = 'Reds';
        await refs.clubs.save(reds);
        expect(await refs.clubs.count(), 2);
      }),
    );

    test(
      'a composite constraint covers all its columns together',
      () => run(() async {
        await refs.citizens.save(
          Citizen(firstName: 'Ada', lastName: 'Lovelace'),
        );
        await refs.citizens.save(Citizen(firstName: 'Ada', lastName: 'Byron'));
        await expectLater(
          refs.citizens.save(Citizen(firstName: 'Ada', lastName: 'Lovelace')),
          duplicateKey,
        );
        final grace = await refs.citizens.save(
          Citizen(firstName: 'Grace', lastName: 'Hopper'),
        );
        grace
          ..firstName = 'Ada'
          ..lastName = 'Byron';
        await expectLater(refs.citizens.save(grace), duplicateKey);
        expect(await refs.citizens.count(), 3);
      }),
    );

    test(
      'null values never conflict',
      () => run(() async {
        // The last name is null in two rows with the same first name.
        await refs.citizens.save(Citizen(firstName: 'Ada'));
        await refs.citizens.save(Citizen(firstName: 'Ada'));
        // So is the passport; a value that is there is unique.
        await refs.citizens.save(
          Citizen(firstName: 'Bo', lastName: 'A', passport: 'X1'),
        );
        await expectLater(
          refs.citizens.save(
            Citizen(firstName: 'Cy', lastName: 'B', passport: 'X1'),
          ),
          duplicateKey,
        );
        expect(await refs.citizens.count(), 3);
        expect(await refs.citizens.findByPassport(null), hasLength(2));
        expect(await refs.citizens.findByPassport('X1'), hasLength(1));
      }),
    );
  });

  group('ignoreCase', () {
    test(
      'compares and sorts letters outside ASCII like the other store',
      () => run(() async {
        await refs.books.save(Book(title: 'ärger', year: 1));
        await refs.books.save(Book(title: 'Ärger', year: 2));
        await refs.books.save(Book(title: 'Zeta', year: 3));
        expect(
          titles(await refs.books.findByTitleIgnoreCase('ÄRGER')),
          ['ärger', 'Ärger'],
        );
        final sorted = await refs.books.findAllSorted(
          Sort.byOrders([
            const SortOrder.asc('title').ignoringCase(),
            const SortOrder.asc('id'),
          ]),
        );
        if (store == 'postgres') {
          // The database's collation orders the letters: bytewise (`C`) as
          // in memory, or the locale's, which puts ä before z.
          expect(
            titles(sorted),
            anyOf(
              equals(['Zeta', 'ärger', 'Ärger']),
              equals(['ärger', 'Ärger', 'Zeta']),
            ),
          );
        } else {
          expect(titles(sorted), ['Zeta', 'ärger', 'Ärger']);
        }
      }),
    );
  });
}
