// The SQL path against a real PostgreSQL with the roles and the row-level
// security of a Supabase project: spring.supabase.db.url gives the data
// source, spring.supabase.db.rls: user makes every transaction and every
// statement run as the caller.
@Tags(['supabase', 'supabase-docker'])
library;

import 'dart:async';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/containers.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart' show supabaseRunner;
import 'spring_gen/sql_app/sql_app.spring.dart';
import 'sql_app/sql_app.dart';
import 'support.dart';

const _ada = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

/// Who the next call is made as, set by the test.
final class _Caller implements SupabaseCredentials {
  SupabaseCaller who = const SupabaseCaller.user(_ada);

  @override
  String get apiKey => 'anon-key';

  @override
  Future<String> accessToken() async => switch (who.id) {
    final id? => unsignedToken({'sub': id, 'role': 'authenticated'}),
    null => 'anon-key',
  };

  @override
  SupabaseCaller get caller => who;

  @override
  Future<T> asServiceRole<T>(FutureOr<T> Function() body) async {
    final before = who;
    who = const SupabaseCaller.service();
    try {
      return await body();
    } finally {
      who = before;
    }
  }
}

void main() {
  // The user of the address owns the tables and is a superuser, as
  // `postgres` is in a project: only a role set by the hook is held to
  // the policies.
  final database = PostgresContainer()
    ..withInitScript('test/postgrest/init.sql');
  final skip = TestContainers.skipReason();
  final caller = _Caller();

  setUpAll(() async {
    if (skip == null) {
      await database.start();
      // The roles the hook becomes must be the user's to take.
      final granted = await database.execInContainer([
        'psql',
        '-U',
        database.username,
        '-d',
        database.databaseName,
        '-c',
        'grant anon, authenticated to ${database.username}',
      ]);
      expect(granted.exitCode, 0, reason: granted.stderr);
    }
  });

  tearDownAll(() async {
    if (skip == null) {
      await database.stop();
    }
  });

  setUp(() => caller.who = const SupabaseCaller.user(_ada));

  Future<void> withApp(
    Future<void> Function(AssertableApplicationContext context) body, {
    String rls = 'user',
  }) => supabaseRunner($application)
      .withPropertyValues([
        'spring.supabase.url=$projectUrl',
        'spring.supabase.anon-key=anon-key',
        'spring.supabase.db.url=${database.url}',
        'spring.supabase.db.rls=$rls',
        'spring.datasource.postgresql.sslmode=disable',
        'spring.data.jdbc.schema=none',
      ])
      .withBean<SupabaseCredentials>(() => caller)
      .runAsync((context) async {
        expect(context.startupFailure, isNull);
        await caller.asServiceRole(
          () => context.getBean<JdbcClient>().sql('delete from todos').update(),
        );
        await body(context);
      });

  group('SQL over spring.supabase.db.url', skip: skip, () {
    test('the address of the database is the data source', () async {
      await withApp((context) async {
        expect(context, hasSingleBean<DataSource>());
        expect(
          context.getBean<Environment>().getProperty('spring.datasource.url'),
          database.url,
        );
        expect(context.getBean<SupabaseStartup>().dataPath, startsWith('SQL'));
      });
    });

    test('a user reads and writes only their rows', () async {
      await withApp((context) async {
        final todos = context.getBean<SqlTodos>();
        final mine = await todos.save(SqlTodo(title: "Ada's", listId: 'l1'));
        expect(mine.id, isNotNull);
        expect(await todos.visible(), 1);

        caller.who = const SupabaseCaller.user(_bob);
        expect(await todos.findAll(), isEmpty);
        expect(await todos.visible(), 0);
        expect(await todos.findById(mine.id!), isNull);
        await todos.save(SqlTodo(title: "Bob's", listId: 'l1'));
        expect(await todos.visible(), 1);

        caller.who = const SupabaseCaller.user(_ada);
        expect((await todos.findAll()).single.title, "Ada's");
      });
    });

    test('inside asServiceRole the statements pass the policies', () async {
      await withApp((context) async {
        final todos = context.getBean<SqlTodos>();
        await todos.save(SqlTodo(title: "Ada's", listId: 'l1'));
        caller.who = const SupabaseCaller.user(_bob);
        await todos.save(SqlTodo(title: "Bob's", listId: 'l1'));
        expect(await caller.asServiceRole(todos.visible), 2);
        // And the connection that served it is nobody's afterwards.
        expect(await todos.visible(), 1);
      });
    });

    test('nobody signed in: the role anon, which may do nothing', () async {
      await withApp((context) async {
        caller.who = const SupabaseCaller.anon();
        await expectLater(
          context.getBean<SqlTodos>().findAll(),
          throwsA(isA<PermissionDeniedDataAccessException>()),
        );
      });
    });

    test('a transaction is the user too, and rolls back whole', () async {
      await withApp((context) async {
        final lists = context.getBean<TodoLists>();
        final todos = context.getBean<SqlTodos>();
        await lists.addTwo('l1', 'first', 'second');
        expect(await todos.visible(), 2);
        await expectLater(
          lists.addTwo('l2', 'kept?', ''),
          throwsArgumentError,
        );
        expect(await todos.findByListIdOrderById('l2'), isEmpty);

        caller.who = const SupabaseCaller.user(_bob);
        expect(await todos.visible(), 0);
        // Another user cannot insert a row as the first: the policy checks
        // the owner the database took from the claims.
        await lists.addTwo('l1', 'bob 1', 'bob 2');
        expect(await todos.visible(), 2);
      });
    });

    test('a lock is taken in the transaction of the user', () async {
      await withApp((context) async {
        final lists = context.getBean<TodoLists>();
        await lists.addTwo('l1', 'first', 'second');
        final closed = await lists.closeFirst('l1');
        expect(closed?.title, 'first');
        expect(closed?.done, isTrue);
        expect(closed?.version, 2);

        caller.who = const SupabaseCaller.user(_bob);
        expect(await lists.closeFirst('l1'), isNull);
      });
    });

    test('rls: off runs as the user of the address', () async {
      await withApp((context) async {
        final todos = context.getBean<SqlTodos>();
        // No role is set, so no claims either: the owner is given by hand.
        await context
            .getBean<JdbcClient>()
            .sql(
              "insert into todos (title, list_id, owner) values ('x', 'l1', "
              "'$_ada'), ('y', 'l1', '$_bob')",
            )
            .update();
        caller.who = const SupabaseCaller.user(_bob);
        expect(await todos.visible(), 2);
      }, rls: 'off');
    });
  });
}
