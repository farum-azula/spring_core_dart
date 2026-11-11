@Tags(['supabase'])
library;

// The rate limiter's store over a database function: the call it makes
// (as the service role, whoever asks), what it reads back, and when it is
// the application's store.
import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';
import 'support.dart';

const _limit = RateLimit(5, Duration(minutes: 1));

final class _AppStore implements RateLimitStore {
  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) async => const RateLimitDecision(allowed: true, remaining: 1);
}

void main() {
  late MockHttpTransport transport;

  setUp(() => transport = MockHttpTransport());

  const on = ['spring.web.rate-limit.enabled=true'];

  group('the call', () {
    test('one function call as the service role, with the bucket as its '
        'arguments', () async {
      transport
          .when(HttpMethod.post, '/rest/v1/rpc/rate_limit_acquire')
          .respond(
            200,
            json: [
              {'allowed': true, 'remaining': 4, 'retry_after_ms': 0},
            ],
          );
      await appRunner(transport, on).runAsync((context) async {
        expect(context.startupFailure, isNull);
        final store = context.getBean<RateLimitStore>();
        expect(store, isA<SupabaseRateLimitStore>());
        // Whoever the request is from.
        final decision = await asUser(
          'ada',
          () => store.tryAcquire('login:ip:203.0.113.7', _limit),
        );
        expect(decision.allowed, isTrue);
        expect(decision.remaining, 4);
        expect(decision.retryAfter, Duration.zero);

        final request = transport.requests.single;
        expect(request.headers['apikey'], 'service-key');
        expect(request.headers['Authorization'], 'Bearer service-key');
        expect(jsonDecode(utf8.decode(request.body!)), {
          'p_key': 'login:ip:203.0.113.7',
          'p_capacity': 5,
          'p_refill_per_second': closeTo(5 / 60, 1e-12),
          'p_permits': 1,
        });
      });
    });

    test('a refusal carries retry-after; a burst is the capacity', () async {
      transport
          .when(HttpMethod.post, '/rest/v1/rpc/rate_limit_acquire')
          .respond(
            200,
            json: [
              {'allowed': false, 'remaining': 0.0, 'retry_after_ms': 11800},
            ],
          );
      await appRunner(transport, on).runAsync((context) async {
        final decision = await context.getBean<RateLimitStore>().tryAcquire(
          'k',
          RateLimit.parse('60/1m', burst: 10),
          permits: 2,
        );
        expect(decision.allowed, isFalse);
        expect(decision.remaining, 0);
        expect(decision.retryAfter, const Duration(milliseconds: 11800));
        expect(
          jsonDecode(utf8.decode(transport.requests.single.body!)),
          containsPair('p_capacity', 10),
        );
      });
    });

    test('a function of another name', () async {
      transport
          .when(HttpMethod.post, '/rest/v1/rpc/api_limits_acquire')
          .respond(
            200,
            json: [
              {'allowed': true, 'remaining': 1, 'retry_after_ms': 0},
            ],
          );
      await appRunner(transport, [
        ...on,
        'spring.supabase.rate-limit.function=api_limits_acquire',
      ]).runAsync((context) async {
        final store = context.getBean<SupabaseRateLimitStore>();
        expect(store.function, 'api_limits_acquire');
        expect((await store.tryAcquire('k', _limit)).allowed, isTrue);
      });
      expect(
        () => SupabaseRateLimitStore(
          store: PostgrestDataStore(
            http: http(transport),
            converter: EntityConverter(),
          ),
          credentials: DefaultSupabaseCredentials(properties: properties()),
          function: 'x; drop',
        ),
        throwsArgumentError,
      );
    });

    test('a store that cannot be reached, or answers something else, '
        'fails', () async {
      transport
          .when(HttpMethod.post, '/rest/v1/rpc/rate_limit_acquire')
          .respond(
            404,
            json: {'code': 'PGRST202', 'message': 'no such function'},
          );
      await appRunner(transport, on).runAsync((context) async {
        await expectLater(
          context.getBean<RateLimitStore>().tryAcquire('k', _limit),
          throwsA(isA<DataAccessException>()),
        );
      });
      final other = MockHttpTransport()
        ..when(
          HttpMethod.post,
          '/rest/v1/rpc/rate_limit_acquire',
        ).respond(200, json: 7);
      await appRunner(other, on).runAsync((context) async {
        await expectLater(
          context.getBean<RateLimitStore>().tryAcquire('k', _limit),
          throwsStateError,
        );
      });
    });
  });

  group('asked at startup', () {
    Future<void> verify(MockHttpTransport transport) async {
      late Future<void> asked;
      await appRunner(transport, on).runAsync((context) async {
        final store = context.getBean<SupabaseRateLimitStore>();
        expect(store, isA<VerifiableRateLimitStore>());
        asked = store.verify();
        await asked.then<void>((_) {}, onError: (Object _) {});
      });
      await asked;
    }

    MockHttpTransport answering(int status, Object? json) =>
        MockHttpTransport()
          ..when(
            HttpMethod.post,
            '/rest/v1/rpc/rate_limit_acquire',
          ).respond(status, json: json);

    Matcher setup(String text) => throwsA(
      isA<RateLimitStoreSetupException>().having(
        (e) => e.message,
        'message',
        allOf(
          contains(text),
          contains('sql/rate_limit.sql'),
          contains('rate_limit_acquire'),
        ),
      ),
    );

    test('the function is there: one call for a bucket of its own', () async {
      final transport = answering(200, [
        {'allowed': true, 'remaining': 0, 'retry_after_ms': 0},
      ]);
      await verify(transport);
      final request = transport.requests.single;
      expect(request.headers['Authorization'], 'Bearer service-key');
      expect(
        (jsonDecode(utf8.decode(request.body!)) as Map)['p_key'],
        SupabaseRateLimitStore.verifyKey,
      );
    });

    test('no such function, no table behind it, something else answered, '
        'or not allowed: what to run', () async {
      await expectLater(
        verify(
          answering(404, {'code': 'PGRST202', 'message': 'no such function'}),
        ),
        setup('no such function'),
      );
      await expectLater(
        verify(
          answering(404, {
            'code': '42P01',
            'message': 'relation "public.rate_limit" does not exist',
          }),
        ),
        setup('does not exist'),
      );
      await expectLater(verify(answering(200, 7)), setup('did not answer'));
      await expectLater(
        verify(
          answering(403, {'code': '42501', 'message': 'permission denied'}),
        ),
        setup('permission denied'),
      );
    });

    test('a project that cannot be reached is no setup problem', () async {
      await expectLater(
        verify(answering(503, {'message': 'down'})),
        throwsA(isA<DataAccessResourceFailureException>()),
      );
    });
  });

  group('which store', () {
    test('the database function on the REST path, when the rate limiter '
        'is on (a property or a rule)', () async {
      await appRunner(transport).runAsync((context) async {
        expect(context.startupFailure, isNull);
        expect(context.containsBean('supabaseRateLimitStore'), isFalse);
      });
      await appRunner(transport, [
        'spring.web.rate-limit.rules[0].limit=5/1m',
      ]).runAsync((context) async {
        expect(
          context.getBean<RateLimitStore>(),
          isA<SupabaseRateLimitStore>(),
        );
      });
      await appRunner(transport, [
        ...on,
        'spring.web.rate-limit.enabled=false',
      ]).runAsync((context) async {
        expect(context.containsBean('supabaseRateLimitStore'), isFalse);
      });
    });

    test('another store asked for, or a bean of the application: not '
        'this one', () async {
      await appRunner(transport, [
        ...on,
        'spring.web.rate-limit.store=memory',
      ]).runAsync((context) async {
        expect(context.startupFailure, isNull);
        expect(context.containsBean('supabaseRateLimitStore'), isFalse);
      });
      await appRunner(transport, on)
          .withUserConfiguration(
            BeanModule('appStore', [
              BeanDefinition<_AppStore>(
                name: 'appStore',
                types: const [_AppStore, RateLimitStore],
                create: (_) => _AppStore(),
              ),
            ]),
          )
          .runAsync((context) async {
            expect(context.getBean<RateLimitStore>(), isA<_AppStore>());
          });
    });

    test('without the service role key the start says what to set', () async {
      final failure = await baseRunner()
          .withPropertyValues([
            'spring.supabase.url=$projectUrl',
            'spring.supabase.anon-key=anon-key',
            ...on,
          ])
          .withBean<HttpTransport>(() => transport)
          .runAsync((context) async => context.startupFailure);
      expect('$failure', contains('spring.supabase.service-role-key'));
      expect('$failure', contains('spring.web.rate-limit.store'));
    });
  });

  group('the shipped SQL', () {
    final shipped = File('lib/sql/rate_limit.sql').readAsStringSync();

    test('closes the table and the function to anon and authenticated', () {
      expect(shipped, contains('create unlogged table'));
      expect(shipped, contains('enable row level security'));
      expect(
        shipped,
        contains(
          'revoke all on table public.rate_limit from public, anon, '
          'authenticated',
        ),
      );
      expect(shipped, contains('security definer'));
      expect(shipped, contains("set search_path = ''"));
      expect(shipped, contains('from public, anon, authenticated;'));
      expect(shipped, contains('to service_role;'));
    });

    test('is what the PostgREST test runs', () {
      expect(
        File('test/postgrest/init.sql').readAsStringSync(),
        contains(shipped),
      );
    });
  });
}
