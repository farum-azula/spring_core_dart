// The store against a real PostgREST over a real PostgreSQL, with the
// roles and the row-level security of a Supabase project: what the unit
// tests assume about the REST API is checked here.
@Tags(['supabase', 'supabase-docker'])
library;

import 'dart:async';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/containers.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';
import 'jwt_support.dart';

const _secret = 'a-test-secret-of-at-least-32-bytes!!';
const _ada = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

String _token(String role, {String? subject, int lifetime = 3600}) =>
    hs256Token(_secret, {
      'role': role,
      'sub': ?subject,
      'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime,
    });

/// Who the next call is made as, set by the test.
final class _Caller implements SupabaseCredentials {
  String? user;
  int lifetime = 3600;

  @override
  String get apiKey => _token('anon');

  @override
  Future<String> accessToken() async => _service > 0
      ? _token('service_role')
      : user == null
      ? _token('anon')
      : _token('authenticated', subject: user, lifetime: lifetime);

  @override
  SupabaseCaller get caller =>
      user == null ? const SupabaseCaller.anon() : SupabaseCaller.user(user!);

  // How many bodies of asServiceRole run now: their calls go as the
  // service role.
  int _service = 0;

  @override
  Future<T> asServiceRole<T>(FutureOr<T> Function() body) async {
    _service++;
    try {
      return await body();
    } finally {
      _service--;
    }
  }
}

/// A bare PostgREST serves at `/` what a project serves at `/rest/v1`.
final class _WithoutGateway implements HttpTransport {
  _WithoutGateway(this.delegate);

  final HttpTransport delegate;

  HttpRequest _strip(HttpRequest request) => HttpRequest(
    method: request.method,
    url: request.url.replace(
      path: request.url.path.replaceFirst('/rest/v1', ''),
    ),
    headers: request.headers,
    body: request.body,
    timeout: request.timeout,
    readTimeout: request.readTimeout,
    followRedirects: request.followRedirects,
  );

  @override
  Future<HttpResponse> send(HttpRequest request) =>
      delegate.send(_strip(request));

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      delegate.stream(_strip(request));

  @override
  void close() => delegate.close();
}

void main() {
  final network = Network.newNetwork();
  final database = PostgresContainer()
    ..withNetwork(network)
    ..withNetworkAliases(['db'])
    ..withInitScript('test/postgrest/init.sql');
  final api = GenericContainer('postgrest/postgrest:v12.2.3')
      .withNetwork(network)
      .withEnvironment({
        'PGRST_DB_URI': 'postgres://authenticator:authenticator@db:5432/test',
        'PGRST_DB_SCHEMAS': 'public',
        'PGRST_DB_ANON_ROLE': 'anon',
        'PGRST_JWT_SECRET': _secret,
      })
      .withExposedPorts([3000])
      .waitingFor(Wait.forHttp('/').forPort(3000));
  final skip = TestContainers.skipReason();
  final caller = _Caller();
  late HttpTransport transport;

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    await database.start();
    await api.start();
    transport = _WithoutGateway(platformHttpTransport());
  });

  tearDownAll(() async {
    if (skip != null) {
      return;
    }
    transport.close();
    await api.stop();
    await database.stop();
    await network.close();
  });

  setUp(() {
    caller
      ..user = _ada
      ..lifetime = 3600;
  });

  Future<void> withApp(
    Future<void> Function(AssertableApplicationContext context) body,
  ) => baseRunner()
      .withPropertyValues([
        'spring.supabase.url=${api.baseUrl(3000)}',
        'spring.supabase.anon-key=unused',
      ])
      .withBean<HttpTransport>(() => transport)
      .withBean<SupabaseCredentials>(() => caller)
      .runAsync((context) async {
        expect(context.startupFailure, isNull);
        await body(context);
      });

  Future<void> withTodos(Future<void> Function(Todos todos) body) =>
      withApp((context) async {
        final todos = context.getBean<Todos>();
        await todos.deleteAll();
        await body(todos);
      });

  group('a real REST API', skip: skip, () {
    test('save, read back, update with its version, delete', () async {
      await withTodos((todos) async {
        final saved = await todos.save(
          Todo(title: 'Buy milk', listId: 'l1', priority: Priority.high),
        );
        expect(saved.id, isNotNull);
        expect(saved.version, 1);
        expect(saved.priority, Priority.high);

        final found = await todos.findById(saved.id!);
        expect(found?.title, 'Buy milk');

        final changed = await todos.save(found!..done = true);
        expect(changed.version, 2);
        expect(changed.done, isTrue);

        // The copy read before the update is stale now.
        await expectLater(
          todos.save(
            Todo(
              title: 'stale',
              listId: 'l1',
              id: saved.id,
              version: 1,
            ),
          ),
          throwsA(isA<OptimisticLockingFailureException>()),
        );

        await todos.deleteById(saved.id!);
        expect(await todos.findById(saved.id!), isNull);
        expect(await todos.count(), 0);
      });
    });

    test(
      'derived queries: equality, order, patterns, Or, In, Between',
      () async {
        await withTodos((todos) async {
          await todos.saveAll([
            Todo(
              title: 'a*b(c one',
              listId: 'x,y)"z',
              createdAt: DateTime.utc(2026, 3),
            ),
            Todo(
              title: 'A*B(C two',
              listId: 'l1',
              done: true,
              createdAt: DateTime.utc(2026, 6),
            ),
            Todo(
              title: 'aXb(c three',
              listId: 'l1',
              priority: Priority.high,
              createdAt: DateTime.utc(2027, 6),
            ),
          ]);

          expect(
            (await todos.findByDoneOrderByCreatedAtDesc(
              false,
            )).map((t) => t.title),
            ['aXb(c three', 'a*b(c one'],
          );

          // The `*` and the `(` are text, not syntax; the case is ignored.
          expect(
            (await todos.findByTitleStartingWithIgnoreCase(
              'a*b(c',
            )).map((t) => t.title).toSet(),
            {'a*b(c one', 'A*B(C two'},
          );

          // A value with a comma, a parenthesis and a quote inside an Or.
          expect(
            (await todos.findByListIdAndDoneOrPriority(
              'x,y)"z',
              false,
              Priority.high,
            )).map((t) => t.title).toSet(),
            {'a*b(c one', 'aXb(c three'},
          );

          final all = await todos.findAll();
          expect(
            await todos.findByIdIn([all[0].id!, all[2].id!]),
            hasLength(2),
          );
          expect(
            (await todos.findByCreatedAtBetween(
              DateTime.utc(2026),
              DateTime.utc(2027),
            )).map((t) => t.title).toSet(),
            {'a*b(c one', 'A*B(C two'},
          );
          expect(
            (await todos.findFirstByListIdOrderByIdDesc('l1'))?.title,
            'aXb(c three',
          );
        });
      },
    );

    test(
      'a page with its count, count, exists, delete by a condition',
      () async {
        await withTodos((todos) async {
          await todos.saveAll([
            for (var i = 1; i <= 7; i++)
              Todo(title: 'todo $i', listId: 'l1', done: i.isEven),
          ]);
          final page = await todos.findByListId('l1', PageRequest.of(1, 3));
          expect(page.totalElements, 7);
          expect(page.totalPages, 3);
          expect(page.content.map((t) => t.title), [
            'todo 4',
            'todo 5',
            'todo 6',
          ]);
          expect(await todos.countByDone(true), 3);
          expect(await todos.existsByTitle('todo 1'), isTrue);
          expect(await todos.existsByTitle('nope'), isFalse);
          expect(await todos.deleteByDone(true), 3);
          expect(await todos.count(), 4);
        });
      },
    );

    test(
      'row-level security: a user sees and changes only their rows',
      () async {
        await withTodos((todos) async {
          final mine = await todos.save(Todo(title: "Ada's", listId: 'l1'));

          caller.user = _bob;
          expect(await todos.findAll(), isEmpty);
          expect(await todos.findById(mine.id!), isNull);
          expect(await todos.count(), 0);
          // Not theirs to update: as if someone else had changed it.
          await expectLater(
            todos.save(
              Todo(title: 'taken', listId: 'l1', id: mine.id, version: 1),
            ),
            throwsA(isA<OptimisticLockingFailureException>()),
          );
          expect(await todos.deleteByDone(false), 0);

          caller.user = _ada;
          expect((await todos.findById(mine.id!))?.title, "Ada's");
        });
      },
    );

    test('nobody signed in: the database refuses', () async {
      await withApp((context) async {
        caller.user = null;
        await expectLater(
          context.getBean<Todos>().findAll(),
          throwsA(isA<PermissionDeniedDataAccessException>()),
        );
      });
    });

    test('an expired token is a permission failure', () async {
      await withApp((context) async {
        caller.lifetime = -3600;
        await expectLater(
          context.getBean<Todos>().findAll(),
          throwsA(isA<PermissionDeniedDataAccessException>()),
        );
      });
    });

    test('a duplicate key and an update of a row that is not there', () async {
      await withApp((context) async {
        final store = context.getBean<PostgrestDataStore>();
        final notes = context
            .getBean<RelationalMappingContext>()
            .getRequiredPersistentEntity<Note>();
        await store.deleteWhere(notes);
        await store.insert(notes, Note(text: 'first', id: 'n1'));
        await expectLater(
          store.insert(notes, Note(text: 'again', id: 'n1')),
          throwsA(isA<DuplicateKeyException>()),
        );
        await expectLater(
          context.getBean<Notes>().save(Note(text: 'x', id: 'missing')),
          throwsA(isA<IncorrectUpdateSemanticsDataAccessException>()),
        );
      });
    });

    test('@Json properties in jsonb columns', () async {
      await withApp((context) async {
        final parcels = context.getBean<Parcels>();
        await parcels.deleteAll();
        final saved = await parcels.save(
          Parcel(
            label: 'books',
            packaging: Packaging(
              box: 'L',
              fragile: true,
              size: BoxSize(width: 30, height: 20),
            ),
            stops: [
              Stop(city: 'Ely', day: 1),
              Stop(city: 'Hull'),
            ],
          ),
        );
        expect(saved.id, isNotNull);
        final found = (await parcels.findById(saved.id!))!;
        expect(found.packaging.box, 'L');
        expect(found.packaging.fragile, isTrue);
        expect(found.packaging.size!.width, 30);
        expect([for (final stop in found.stops) stop.city], ['Ely', 'Hull']);
        expect(found.stops.first.day, 1);
        expect(found.stops.last.day, isNull);

        found
          ..packaging.size = null
          ..stops = [];
        await parcels.save(found);
        final again = (await parcels.findByLabel('books')).single;
        expect(again.packaging.size, isNull);
        expect(again.packaging.box, 'L');
        expect(again.stops, isEmpty);
      });
    });

    test('a database function', () async {
      await withTodos((todos) async {
        await todos.saveAll([
          Todo(title: 'a', listId: 'l1'),
          Todo(title: 'b', listId: 'l1'),
          Todo(title: 'c', listId: 'l2'),
        ]);
      });
      await withApp((context) async {
        final rows = await context.getBean<PostgrestDataStore>().callFunction(
          'close_all',
          {'list_id': 'l1'},
        );
        expect(rows, [
          {'close_all': 2},
        ]);
        expect(await context.getBean<Todos>().countByDone(true), 2);
      });
    });

    test('a database function through the repository (@Procedure)', () async {
      await withTodos((todos) async {
        await todos.saveAll([
          Todo(title: 'a', listId: 'l1'),
          Todo(title: 'b', listId: 'l1'),
          Todo(title: 'c', listId: 'l2'),
        ]);
        expect(await todos.closeAll('l1'), 2);
        expect(await todos.countByDone(true), 2);
        // Nothing left to close: the function says so.
        expect(await todos.closeAll('l1'), 0);
        expect(await todos.countByDone(false), 1);
      });
    });

    test('a table the API does not know', () async {
      await withApp((context) async {
        final store = context.getBean<PostgrestDataStore>();
        await expectLater(
          store.callFunction('no_such_function', const {}),
          throwsA(isA<InvalidDataAccessResourceUsageException>()),
        );
      });
    });
  });

  group("the rate limiter's database function", skip: skip, () {
    Future<void> withLimits(
      Future<void> Function(
        RateLimitStore store,
        AssertableApplicationContext context,
      )
      body,
    ) => baseRunner()
        .withPropertyValues([
          'spring.supabase.url=${api.baseUrl(3000)}',
          'spring.supabase.anon-key=unused',
          'spring.web.rate-limit.enabled=true',
        ])
        .withBean<HttpTransport>(() => transport)
        .withBean<SupabaseCredentials>(() => caller)
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          await body(context.getBean<RateLimitStore>(), context);
        });

    var run = 0;
    // A key no other test of this run used.
    String newKey() => 'test:${DateTime.now().microsecondsSinceEpoch}:${run++}';

    test('it is the store of an application on the REST path: a burst, '
        'then a refusal with retry-after', () async {
      await withLimits((store, _) async {
        expect(store, isA<SupabaseRateLimitStore>());
        const limit = RateLimit(5, Duration(hours: 1));
        final key = newKey();
        for (var left = 4; left >= 0; left--) {
          final decision = await store.tryAcquire(key, limit);
          expect(decision.allowed, isTrue);
          expect(decision.remaining, left);
          expect(decision.retryAfter, Duration.zero);
        }
        final refused = await store.tryAcquire(key, limit);
        expect(refused.allowed, isFalse);
        expect(refused.remaining, 0);
        expect(refused.retryAfter.inSeconds, inInclusiveRange(700, 720));
        expect((await store.tryAcquire(newKey(), limit)).remaining, 4);
      });
    });

    test('the bucket is filled again by the clock of the database, never '
        'past its burst', () async {
      await withLimits((store, _) async {
        const fast = RateLimit(20, Duration(seconds: 1), burst: 2);
        final key = newKey();
        expect((await store.tryAcquire(key, fast, permits: 2)).allowed, isTrue);
        final refused = await store.tryAcquire(key, fast);
        expect(refused.allowed, isFalse);
        expect(refused.retryAfter.inMilliseconds, inInclusiveRange(1, 50));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect((await store.tryAcquire(key, fast)).remaining, 1);
        // More than the bucket holds: never, and nothing is taken.
        final never = await store.tryAcquire(key, fast, permits: 3);
        expect(never.allowed, isFalse);
      });
    });

    test('100 acquisitions at once never pass the limit', () async {
      await withLimits((store, _) async {
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
    });

    test('anon and authenticated can neither call the function, nor read '
        'the counters, nor reset them', () async {
      await withLimits((store, context) async {
        const one = RateLimit(1, Duration(hours: 1));
        final key = newKey();
        // The store works whoever the request is from: it calls as the
        // service role.
        caller.user = _ada;
        expect((await store.tryAcquire(key, one)).allowed, isTrue);
        expect((await store.tryAcquire(key, one)).allowed, isFalse);

        final http = context.getBean<SupabaseHttp>();
        for (final user in [_ada, null]) {
          caller.user = user;
          final who = user == null ? 'anon' : 'authenticated';
          final call = await http.send(
            SupabaseService.rest,
            HttpMethod.post,
            '/rpc/rate_limit_acquire',
            json: {
              'p_key': key,
              'p_capacity': 1000,
              'p_refill_per_second': 1000,
              'p_permits': 1,
            },
          );
          expect(call.statusCode, anyOf(401, 403, 404), reason: who);
          final read = await http.send(
            SupabaseService.rest,
            HttpMethod.get,
            '/rate_limit',
          );
          expect(read.statusCode, anyOf(401, 403, 404), reason: who);
          expect(read.bodyText, isNot(contains(key)), reason: who);
          for (final method in [HttpMethod.delete, HttpMethod.patch]) {
            final reset = await http.send(
              SupabaseService.rest,
              method,
              '/rate_limit',
              query: [MapEntry('key', 'eq.$key')],
              json: method == HttpMethod.patch ? {'tokens': 1000} : null,
            );
            expect(reset.statusCode, anyOf(401, 403, 404), reason: who);
          }
          final insert = await http.send(
            SupabaseService.rest,
            HttpMethod.post,
            '/rate_limit',
            json: {
              'key': newKey(),
              'tokens': 1000,
              'allowed': true,
              'updated_at': 0,
              'expires_at': 0,
            },
          );
          expect(insert.statusCode, anyOf(401, 403, 404), reason: who);
        }
        // Nothing of it moved the counter.
        caller.user = _ada;
        expect((await store.tryAcquire(key, one)).allowed, isFalse);
      });
    });
  });
}
