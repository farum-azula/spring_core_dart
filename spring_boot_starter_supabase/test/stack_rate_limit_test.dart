@Tags(['supabase', 'supabase-stack'])
library;

// Level 4, the rate limiter's store: the database function of the
// package's sql/rate_limit.sql in the project's own database, called
// through the gateway (/rest/v1/rpc) as the service role; closed to anon
// and to a signed-in user.
//
// The table and the function are made for this run, under names of its
// own, through the database address of the project, and dropped after.
import 'dart:io';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'spring_gen/sql_app/sql_app.spring.dart' as sql;
import 'stack_support.dart';

void main() {
  group(
    "the rate limiter's database function",
    skip: Stack.skip ?? Stack.skipDb,
    () {
      // The names of this run: the table, and `<table>_acquire`.
      final table = Stack.skip == null ? Stack.unique('rl_test_') : '';
      final function = '${table}_acquire';
      const signature =
          '(text, double precision, double precision, double precision)';

      late StackApp server;
      late StackApp ada;
      late StackApp nobody;
      late RateLimitStore store;

      final sslMode = Stack.skip == null && Stack.isLocal
          ? 'disable'
          : 'require';

      // SQL as the owner of the project's database.
      Future<void> asOwner(String statements) async {
        final database = await StackApp.start(
          runner: () => supabaseRunner(sql.$application),
          properties: [
            'spring.supabase.db.url=${Stack.dbUrl}',
            'spring.datasource.postgresql.sslmode=$sslMode',
            'spring.data.jdbc.schema=none',
          ],
        );
        try {
          final source = database.bean<DataSource>();
          final connection = await source.getConnection();
          try {
            await connection.execute(statements);
          } finally {
            await source.releaseConnection(connection);
          }
        } finally {
          await database.close();
        }
      }

      var run = 0;
      String newKey() => 'test:${Stack.unique('')}:${run++}';

      setUpAll(() async {
        Stack.require();
        final shipped = File('lib/sql/rate_limit.sql').readAsStringSync();
        await asOwner(
          '${shipped.replaceAll('rate_limit', table)}\n'
          "notify pgrst, 'reload schema';",
        );
        // A server on the REST path with the rate limiter on: the store is
        // the default of that.
        server = await StackApp.start(
          properties: [
            'spring.web.rate-limit.enabled=true',
            'spring.supabase.rate-limit.function=$function',
          ],
        );
        ada = await StackApp.start();
        nobody = await StackApp.start();
        await ada.signInAsNewUser();
        store = server.bean<RateLimitStore>();
        // The REST API learns of the function a moment after the notify.
        const limit = RateLimit(1000, Duration(seconds: 1));
        for (var attempt = 0; ; attempt++) {
          try {
            await store.tryAcquire(newKey(), limit);
            break;
          } on Object {
            if (attempt >= 60) {
              rethrow;
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      });

      tearDownAll(() async {
        await ada.close();
        await nobody.close();
        await server.close();
        await asOwner(
          'drop function if exists public.$function$signature;\n'
          'drop table if exists public.$table;\n'
          "notify pgrst, 'reload schema';",
        );
      });

      test('it is the store of a server on the REST path', () {
        expect(store, isA<SupabaseRateLimitStore>());
        expect((store as SupabaseRateLimitStore).function, function);
      });

      test(
        'a burst of the capacity, then a refusal with retry-after',
        () async {
          const limit = RateLimit(5, Duration(hours: 1));
          final key = newKey();
          for (var left = 4; left >= 0; left--) {
            final decision = await store.tryAcquire(key, limit);
            expect(decision.allowed, isTrue);
            expect(decision.remaining, left);
          }
          final refused = await store.tryAcquire(key, limit);
          expect(refused.allowed, isFalse);
          expect(refused.remaining, 0);
          expect(refused.retryAfter.inSeconds, inInclusiveRange(700, 720));
          expect((await store.tryAcquire(newKey(), limit)).remaining, 4);
        },
      );

      test('the bucket is filled again by the clock of the database', () async {
        const fast = RateLimit(10, Duration(seconds: 1), burst: 2);
        final key = newKey();
        expect((await store.tryAcquire(key, fast, permits: 2)).allowed, isTrue);
        final refused = await store.tryAcquire(key, fast);
        expect(refused.allowed, isFalse);
        expect(refused.retryAfter.inMilliseconds, inInclusiveRange(1, 100));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect((await store.tryAcquire(key, fast)).remaining, 1);
      });

      test('100 acquisitions at once never pass the limit', () async {
        const ten = RateLimit(10, Duration(hours: 1));
        final key = newKey();
        final decisions = await Future.wait([
          for (var i = 0; i < 100; i++) store.tryAcquire(key, ten),
        ]);
        expect(decisions.where((d) => d.allowed), hasLength(10));
        expect(
          decisions.where((d) => d.allowed).map((d) => d.remaining).toSet(),
          {for (var i = 0; i < 10; i++) i},
        );
      });

      test('on the SQL path the store is the SQL one, unless the function '
          'is asked for', () async {
        Future<StackApp> sqlPath(List<String> more) => StackApp.start(
          runner: () => supabaseRunner(sql.$application),
          properties: [
            'spring.supabase.db.url=${Stack.dbUrl}',
            'spring.datasource.postgresql.sslmode=$sslMode',
            'spring.data.jdbc.schema=none',
            'spring.web.rate-limit.enabled=true',
            ...more,
          ],
        );
        final bySql = await sqlPath([
          'spring.data.jdbc.rate-limit.table=$table',
        ]);
        try {
          final sqlStore = bySql.bean<RateLimitStore>();
          expect(sqlStore, isA<JdbcRateLimitStore>());
          expect(bySql.context.containsBean('supabaseRateLimitStore'), isFalse);
          // The same table serves both stores: one set of counters.
          const two = RateLimit(2, Duration(hours: 1));
          final key = newKey();
          expect((await sqlStore.tryAcquire(key, two)).remaining, 1);
          expect((await store.tryAcquire(key, two)).remaining, 0);
          expect((await sqlStore.tryAcquire(key, two)).allowed, isFalse);
        } finally {
          await bySql.close();
        }
        final byFunction = await sqlPath([
          'spring.web.rate-limit.store=procedure',
          'spring.supabase.rate-limit.function=$function',
        ]);
        try {
          expect(
            byFunction.bean<RateLimitStore>(),
            isA<SupabaseRateLimitStore>(),
          );
          expect(
            byFunction.context.containsBean('jdbcRateLimitStore'),
            isFalse,
          );
        } finally {
          await byFunction.close();
        }
      });

      test('the store counts as the service role, whoever the request is '
          'from', () async {
        const one = RateLimit(1, Duration(hours: 1));
        final key = newKey();
        final decision = await ada.run(
          () => server.run(() => store.tryAcquire(key, one)),
        );
        expect(decision.allowed, isTrue);
      });

      test('anon and a signed-in user can neither call the function, nor '
          'read the counters, nor reset them', () async {
        const one = RateLimit(1, Duration(hours: 1));
        final key = newKey();
        expect((await store.tryAcquire(key, one)).allowed, isTrue);
        expect((await store.tryAcquire(key, one)).allowed, isFalse);

        for (final (who, app) in [('a user', ada), ('anon', nobody)]) {
          await app.run(() async {
            final call = await app.rest(
              HttpMethod.post,
              '/rpc/$function',
              json: {
                'p_key': key,
                'p_capacity': 1000,
                'p_refill_per_second': 1000,
                'p_permits': 1,
              },
            );
            expect(call.statusCode, anyOf(401, 403, 404), reason: who);
            final read = await app.rest(HttpMethod.get, '/$table');
            expect(read.statusCode, anyOf(401, 403, 404), reason: who);
            expect(read.bodyText, isNot(contains(key)), reason: who);
            final delete = await app.rest(
              HttpMethod.delete,
              '/$table',
              query: {'key': 'eq.$key'},
            );
            expect(delete.statusCode, anyOf(401, 403, 404), reason: who);
            final update = await app.rest(
              HttpMethod.patch,
              '/$table',
              query: {'key': 'eq.$key'},
              json: {'tokens': 1000},
            );
            expect(update.statusCode, anyOf(401, 403, 404), reason: who);
          });
        }
        // Nothing of it moved the counter.
        expect((await store.tryAcquire(key, one)).allowed, isFalse);
      });
    },
  );
}
