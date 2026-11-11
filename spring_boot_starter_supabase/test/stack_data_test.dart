@Tags(['supabase', 'supabase-stack'])
library;

// Level 4, the data: the repositories through the gateway (/rest/v1) as a
// signed-in user of the project, with its row-level security and its
// roles; and the SQL path against the project's own database, where
// auth.uid() must see the caller.
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'spring_gen/sql_app/sql_app.spring.dart' as sql;
import 'sql_app/sql_app.dart';
import 'stack_support.dart';

void main() {
  group('the REST API behind the gateway', skip: Stack.skip, () {
    late StackApp ada;
    late StackApp bob;
    // Nobody signs in here: the anon key.
    late StackApp nobody;

    setUpAll(() async {
      Stack.require();
      ada = await StackApp.start();
      bob = await StackApp.start();
      nobody = await StackApp.start();
      await ada.signInAsNewUser();
      await bob.signInAsNewUser();
    });

    tearDownAll(() async {
      // Whatever a failed test left behind.
      for (final app in [ada, bob]) {
        await app.credentials.asServiceRole(
          () => app.rest(
            HttpMethod.delete,
            '/todos',
            query: {'owner': 'eq.${app.userId}'},
          ),
        );
        await app.close();
      }
      await nobody.close();
    });

    test('a repository as the signed-in user: save, read back, update '
        'with its version, delete', () async {
      await ada.run(() async {
        final todos = ada.todos;
        final listId = Stack.unique('l');
        final saved = await todos.save(
          Todo(
            title: 'Buy milk',
            listId: listId,
            priority: Priority.high,
            createdAt: DateTime.utc(2026, 3, 4, 5, 6, 7),
          ),
        );
        expect(saved.id, isNotNull);
        expect(saved.version, 1);
        expect(saved.priority, Priority.high);
        expect(saved.createdAt?.toUtc(), DateTime.utc(2026, 3, 4, 5, 6, 7));

        final found = await todos.findById(saved.id!);
        expect(found?.title, 'Buy milk');
        final changed = await todos.save(found!..done = true);
        expect(changed.version, 2);
        await expectLater(
          todos.save(
            Todo(title: 'stale', listId: listId, id: saved.id, version: 1),
          ),
          throwsA(isA<OptimisticLockingFailureException>()),
        );

        expect(
          (await todos.findFirstByListIdOrderByIdDesc(listId))?.id,
          saved.id,
        );
        await todos.deleteById(saved.id!);
        expect(await todos.findById(saved.id!), isNull);
      });
    });

    test('a page with its exact count comes through the gateway', () async {
      await ada.run(() async {
        final listId = Stack.unique('l');
        await ada.todos.saveAll([
          for (var i = 1; i <= 5; i++) Todo(title: 'todo $i', listId: listId),
        ]);
        try {
          final page = await ada.todos.findByListId(
            listId,
            PageRequest.of(1, 2),
          );
          expect(page.totalElements, 5);
          expect(page.totalPages, 3);
          expect(page.content.map((t) => t.title), ['todo 3', 'todo 4']);
        } finally {
          await ada.todos.deleteAllById([
            for (final todo
                in await ada.todos
                    .findByListId(
                      listId,
                      PageRequest.of(0, 10),
                    )
                    .then((page) => page.content))
              todo.id!,
          ]);
        }
      });
    });

    test('row-level security: another user neither sees nor changes the '
        'rows', () async {
      final listId = Stack.unique('l');
      final mine = await ada.run(
        () => ada.todos.save(Todo(title: "Ada's", listId: listId)),
      );
      try {
        await bob.run(() async {
          expect(await bob.todos.findById(mine.id!), isNull);
          expect(
            (await bob.todos.findByListId(
              listId,
              PageRequest.of(0, 10),
            )).totalElements,
            0,
          );
          // Not theirs to update: as if someone else had changed it.
          await expectLater(
            bob.todos.save(
              Todo(title: 'taken', listId: listId, id: mine.id, version: 1),
            ),
            throwsA(isA<OptimisticLockingFailureException>()),
          );
          expect(await bob.todos.deleteByDone(false), 0);
        });
        expect(
          (await ada.run(() => ada.todos.findById(mine.id!)))?.title,
          "Ada's",
        );
      } finally {
        await ada.run(() => ada.todos.deleteById(mine.id!));
      }
    });

    test('the anon key alone is refused by the database', () async {
      await nobody.run(() async {
        expect(nobody.credentials.caller, const SupabaseCaller.anon());
        await expectLater(
          nobody.todos.findAll(),
          throwsA(isA<PermissionDeniedDataAccessException>()),
        );
        await expectLater(
          nobody.todos.save(Todo(title: 'x', listId: Stack.unique('l'))),
          throwsA(isA<PermissionDeniedDataAccessException>()),
        );
      });
    });

    test('inside asServiceRole a call sees the rows of every user', () async {
      final listId = Stack.unique('l');
      final hers = await ada.run(
        () => ada.todos.save(Todo(title: "Ada's", listId: listId)),
      );
      final his = await bob.run(
        () => bob.todos.save(Todo(title: "Bob's", listId: listId)),
      );
      try {
        await ada.run(() async {
          Future<List<String>> titles() async => [
            for (final todo in (await ada.todos.findByListId(
              listId,
              PageRequest.of(0, 10),
            )).content)
              todo.title,
          ];
          expect(await titles(), ["Ada's"]);
          final all = await ada.credentials.asServiceRole(() {
            expect(ada.credentials.caller, const SupabaseCaller.service());
            return titles();
          });
          expect(all.toSet(), {"Ada's", "Bob's"});
          // And afterwards the user again.
          expect(ada.credentials.caller, SupabaseCaller.user(ada.userId));
          expect(await titles(), ["Ada's"]);
        });
      } finally {
        await ada.run(() => ada.todos.deleteById(hers.id!));
        await bob.run(() => bob.todos.deleteById(his.id!));
      }
    });

    test('a database function runs as the user: @Procedure and '
        'callFunction', () async {
      final listId = Stack.unique('l');
      await ada.run(
        () => ada.todos.saveAll([
          Todo(title: 'a', listId: listId),
          Todo(title: 'b', listId: listId),
        ]),
      );
      final his = await bob.run(
        () => bob.todos.save(Todo(title: 'c', listId: listId)),
      );
      try {
        await ada.run(() async {
          expect(await ada.todos.closeAll(listId), 2);
          expect(
            await ada.store.callFunction('close_all', {'list_id': listId}),
            [
              {'close_all': 0},
            ],
          );
          final mine = (await ada.todos.findByListId(
            listId,
            PageRequest.of(0, 10),
          )).content;
          expect(mine.map((t) => t.done), [true, true]);
          await ada.todos.deleteAllById([for (final todo in mine) todo.id!]);
        });
        // The function saw only the caller's rows.
        expect(
          (await bob.run(() => bob.todos.findById(his.id!)))?.done,
          isFalse,
        );
      } finally {
        await bob.run(() => bob.todos.deleteById(his.id!));
      }
    });

    test('the project refuses a delete without a condition, which is why '
        'deleteAll sends one', () async {
      final his = await bob.run(
        () => bob.todos.save(Todo(title: "Bob's", listId: Stack.unique('l'))),
      );
      try {
        await ada.run(() async {
          await ada.todos.saveAll([
            Todo(title: 'one', listId: Stack.unique('l')),
            Todo(title: 'two', listId: Stack.unique('l')),
          ]);
          final before = await ada.todos.count();
          expect(before, greaterThanOrEqualTo(2));
          final bare = await ada.rest(HttpMethod.delete, '/todos');
          expect(bare.isSuccess, isFalse, reason: 'a bare DELETE was taken');
          expect(bare.bodyText, contains('WHERE'));
          expect(await ada.todos.count(), before);

          await ada.todos.deleteAll();
          expect(await ada.todos.count(), 0);
        });
        // Every row the caller may delete, not every row of the table.
        expect(await bob.run(() => bob.todos.findById(his.id!)), isNotNull);
      } finally {
        await bob.run(() => bob.todos.deleteById(his.id!));
      }
    });

    test("the errors of the database are the data starter's "
        'exceptions', () async {
      await ada.run(() async {
        final notes = ada.context
            .getBean<RelationalMappingContext>()
            .getRequiredPersistentEntity<Note>();
        final id = Stack.unique('n');
        await ada.store.insert(notes, Note(text: 'first', id: id));
        try {
          await expectLater(
            ada.store.insert(notes, Note(text: 'again', id: id)),
            throwsA(isA<DuplicateKeyException>()),
          );
          expect((await ada.notes.findById(id))?.text, 'first');
        } finally {
          await ada.notes.deleteById(id);
        }
        await expectLater(
          ada.notes.save(Note(text: 'x', id: Stack.unique('missing'))),
          throwsA(isA<IncorrectUpdateSemanticsDataAccessException>()),
        );
        await expectLater(
          ada.store.callFunction('no_such_function', const {}),
          throwsA(isA<InvalidDataAccessResourceUsageException>()),
        );
      });
    });
  });

  group(
    'SQL over the database of the project',
    skip: Stack.skip ?? Stack.skipDb,
    () {
      late StackApp ada;
      late StackApp bob;
      late StackApp nobody;

      // The application of the SQL path (test/sql_app), every statement as
      // the caller.
      final sslMode = Stack.skip == null && Stack.isLocal
          ? 'disable'
          : 'require';
      Future<StackApp> start() => StackApp.start(
        runner: () => supabaseRunner(sql.$application),
        properties: [
          'spring.supabase.db.url=${Stack.dbUrl}',
          'spring.supabase.db.rls=user',
          'spring.datasource.postgresql.sslmode=$sslMode',
          'spring.data.jdbc.schema=none',
        ],
      );

      setUpAll(() async {
        Stack.require();
        ada = await start();
        bob = await start();
        nobody = await start();
        await ada.signInAsNewUser();
        await bob.signInAsNewUser();
      });

      tearDownAll(() async {
        for (final app in [ada, bob]) {
          await app.credentials.asServiceRole(
            () => app
                .bean<JdbcClient>()
                .sql('delete from todos where owner::text = ?')
                .param(app.userId)
                .update(),
          );
          await app.close();
        }
        await nobody.close();
      });

      test('the repositories use SQL over the address of the '
          'database', () async {
        expect(ada.bean<SupabaseStartup>().dataPath, startsWith('SQL'));
      });

      test('auth.uid() and auth.role() of the project see the '
          'caller', () async {
        Future<Map<String, Object?>> who(StackApp app) => app.run(
          () => app
              .bean<JdbcClient>()
              .sql(
                'select auth.uid()::text as uid, auth.role()::text as role, '
                'current_user::text as db_user',
              )
              .query<Map<String, Object?>>()
              .single(),
        );

        final her = await who(ada);
        expect(her['uid'], ada.userId);
        expect(her['role'], 'authenticated');
        expect(her['db_user'], 'authenticated');

        final his = await who(bob);
        expect(his['uid'], bob.userId);

        final none = await who(nobody);
        expect(none['uid'], isNull);
        expect(none['db_user'], 'anon');

        // The service role: the user of the address, as it is.
        final service = await ada.run(
          () => ada.credentials.asServiceRole(() => who(ada)),
        );
        expect(service['db_user'], isNot(anyOf('authenticated', 'anon')));
      });

      test('a user reads and writes only their rows; the owner is the '
          "database's auth.uid()", () async {
        final listId = Stack.unique('l');
        await ada.run(() async {
          final todos = ada.bean<SqlTodos>();
          final mine = await todos.save(
            SqlTodo(title: "Ada's", listId: listId),
          );
          expect(mine.id, isNotNull);
          expect(await todos.visible(), 1);
          final owner = await ada
              .bean<JdbcClient>()
              .sql('select owner::text from todos where id = ?')
              .param(mine.id)
              .query<String>()
              .single();
          expect(owner, ada.userId);
        });

        await bob.run(() async {
          final todos = bob.bean<SqlTodos>();
          expect(await todos.findByListIdOrderById(listId), isEmpty);
          expect(await todos.visible(), 0);
          await todos.save(SqlTodo(title: "Bob's", listId: listId));
          expect(await todos.visible(), 1);
          // In a transaction too, and past the policies as the service
          // role.
          await bob.bean<TodoLists>().addTwo(listId, 'one', 'two');
          expect(await todos.visible(), 3);
          expect(
            await bob.credentials.asServiceRole(todos.visible),
            greaterThanOrEqualTo(4),
          );
        });

        expect(
          await ada.run(
            () async => [
              for (final todo
                  in await ada.bean<SqlTodos>().findByListIdOrderById(listId))
                todo.title,
            ],
          ),
          ["Ada's"],
        );
      });

      test('nobody signed in: the role anon, which may do nothing', () async {
        await nobody.run(() async {
          await expectLater(
            nobody.bean<SqlTodos>().findAll(),
            throwsA(isA<PermissionDeniedDataAccessException>()),
          );
        });
      });
    },
  );
}
