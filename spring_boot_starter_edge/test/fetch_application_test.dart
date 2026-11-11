import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:test/test.dart';

import '../../tool/edge_checks/bin/main.dart' show functionProperties;
import '../../tool/edge_checks/bin/spring_gen/main.spring.dart';
import 'support.dart';

void main() {
  late FetchApplication function;
  final pending = <Future<void>>[];

  FetchApplication application({
    String runtime = 'test',
    Map<String, Object?> properties = const {},
  }) => FetchApplication(
    () => springApplication,
    runtime: runtime,
    properties: {
      ...functionProperties,
      'logging.level.root': 'off',
      ...properties,
    },
  );

  Future<FetchResponse> call(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? body,
    String? remoteAddress = '203.0.113.9',
    FetchApplication? on,
    Map<String, String> environment = const {'GREETING': 'from-env'},
  }) => (on ?? function).fetch(
    FetchRequest(
      method,
      Uri.parse('https://fn.example.com$path'),
      headers: [
        for (final MapEntry(:key, :value) in headers.entries) (key, value),
      ],
      body: switch (body) {
        null => null,
        final Stream<Uint8List> stream => stream,
        final String text => Stream.value(utf8.encode(text)),
        final List<int> bytes => Stream.value(Uint8List.fromList(bytes)),
        _ => throw ArgumentError.value(body),
      },
      context: FetchContext(
        platform: 'test',
        remoteAddress: remoteAddress,
        waitUntil: pending.add,
      ),
    ),
    environment: environment,
  );

  Map<String, String> bearer(String value) => {
    'authorization': 'Bearer $value',
  };

  setUpAll(() => function = application());
  tearDownAll(() => function.close());

  group('a request goes through the dispatcher', () {
    test(
      'a controller answers, with the environment of the platform',
      () async {
        final response = await call('GET', '/hello?name=Ada');
        expect(response.status, 200);
        expect(response.header('content-type'), 'application/json');
        expect(response.bytes, isNotNull, reason: 'a complete body');
        expect(response.header('content-length'), '${response.bytes!.length}');
        expect(await jsonOf(response), {
          'message': 'hello Ada',
          'platform': 'test',
          'remote': '203.0.113.9',
          'greeting': 'from-env',
          'path': '/hello',
          'secure': true,
        });
      },
    );

    test('a JSON body and a header reach the method', () async {
      final response = await call(
        'POST',
        '/echo',
        headers: {'content-type': 'application/json', 'x-trace': 't-1'},
        body: '{"a":[1,2]}',
      );
      expect(await jsonOf(response), {
        'body': {
          'a': [1, 2],
        },
        'trace': 't-1',
      });
    });

    test('a multipart upload is read in memory', () async {
      const boundary = 'xBOUNDARYx';
      const body =
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="title"\r\n\r\n'
          'cover\r\n'
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="a.bin"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n'
          '12345\r\n'
          '--$boundary--\r\n';
      final response = await call(
        'POST',
        '/upload',
        headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
        body: body,
      );
      expect(response.status, 200);
      expect(await jsonOf(response), {
        'name': 'a.bin',
        'size': 5,
        'title': 'cover',
      });
    });

    test('bytes come back as they are', () async {
      final response = await call('GET', '/download');
      expect(response.header('content-type'), 'application/octet-stream');
      expect(await response.readBytes(), [0, 159, 146, 150, 255, 1, 2]);
    });

    test('every cookie is a Set-Cookie of its own', () async {
      final response = await call('GET', '/cookies');
      expect(
        [
          for (final (name, value) in response.headers)
            if (name.toLowerCase() == 'set-cookie') value,
        ],
        ['a=1; Path=/; HttpOnly', 'b=2; Path=/'],
      );
    });

    test('a 204 has no body, no length and no type of one', () async {
      final response = await call('GET', '/nothing');
      expect(response.status, 204);
      expect(response.bytes, isNull);
      expect(response.stream, isNull);
      expect(response.header('content-length'), isNull);
    });

    test('a HEAD request gets the headers without the body', () async {
      final response = await call('HEAD', '/hello');
      expect(response.status, 200);
      expect(response.header('content-type'), 'application/json');
      expect(response.bytes, isNull);
      expect(response.stream, isNull);
    });

    test('an event stream is sent while it is written', () async {
      final response = await call('GET', '/events');
      expect(response.status, 200);
      expect(response.header('content-type'), startsWith('text/event-stream'));
      expect(response.stream, isNotNull, reason: 'not a complete body');
      expect(response.header('content-length'), isNull);
      final text = await textOf(response);
      expect(text, contains('data: {"tick":1}'));
      expect(text, contains('data: {"tick":3}'));
    });

    test('a cached value lives as long as the instance', () async {
      final first = await textOf(await call('GET', '/rates/eur'));
      expect(await textOf(await call('GET', '/rates/eur')), first);
      expect(await textOf(await call('GET', '/rates/usd')), isNot(first));
    });

    test('work given to waitUntil reaches the platform and ends', () async {
      pending.clear();
      final before = await jsonOf(await call('GET', '/later'));
      expect(await textOf(await call('POST', '/later')), 'accepted');
      expect(pending, hasLength(1));
      await Future.wait(pending);
      expect(await jsonOf(await call('GET', '/later')), (before! as int) + 1);
    });
  });

  group('what goes wrong is an answer', () {
    test('an error nobody handled: 500 without its message', () async {
      final response = await call('GET', '/boom');
      expect(response.status, 500);
      expect(response.header('content-type'), 'application/problem+json');
      expect(await textOf(response), isNot(contains('secret')));
    });

    test('a header the fetch API cannot send: 500, not a crash', () async {
      final response = await call('GET', '/bad-header');
      expect(response.status, 500);
      expect(response.header('x-bad'), isNull);
    });

    test('a method nobody knows: 501', () async {
      expect((await call('BREW', '/hello')).status, 501);
    });

    test('no mapping: 404', () async {
      expect((await call('GET', '/no-such')).status, 404);
    });

    test('a body over server.max-http-request-body-size: 413', () async {
      final declared = await call(
        'POST',
        '/size',
        headers: {'content-length': '${100 * 1024}'},
        body: Uint8List(100 * 1024),
      );
      expect(declared.status, 413);
      // Without a length: counted while it is read.
      final streamed = await call(
        'POST',
        '/size',
        body: Stream.fromIterable([
          for (var i = 0; i < 10; i++) Uint8List(10 * 1024),
        ]),
      );
      expect(streamed.status, 413);
      final allowed = await call('POST', '/size', body: Uint8List(60 * 1024));
      expect(await jsonOf(allowed), {'bytes': 60 * 1024});
    });

    test('the rate limiter refuses with 429 and Retry-After', () async {
      final statuses = [
        for (var i = 0; i < 3; i++)
          (await call('GET', '/limited', headers: {'x-client': 'c-1'})).status,
      ];
      expect(statuses, [200, 200, 429]);
      final refused = await call(
        'GET',
        '/limited',
        headers: {'x-client': 'c-1'},
      );
      expect(int.parse(refused.header('retry-after')!), greaterThan(0));
      // Another client has its own bucket.
      expect(
        (await call('GET', '/limited', headers: {'x-client': 'c-2'})).status,
        200,
      );
    });
  });

  group('security', () {
    test('no token: 401 with a challenge', () async {
      final response = await call('GET', '/api/me');
      expect(response.status, 401);
      expect(response.header('www-authenticate'), startsWith('Bearer'));
    });

    test("a user's token: the user", () async {
      final response = await call(
        'GET',
        '/api/me',
        headers: bearer(userToken('ada', roles: ['USER'])),
      );
      expect(response.status, 200);
      expect(await jsonOf(response), {
        'name': 'ada',
        'authorities': ['ROLE_USER'],
      });
    });

    test('method security: 403 without the role, 200 with it', () async {
      expect(
        (await call(
          'GET',
          '/api/admin',
          headers: bearer(userToken('ada', roles: ['USER'])),
        )).status,
        403,
      );
      expect(
        await textOf(
          await call(
            'GET',
            '/api/admin',
            headers: bearer(userToken('root', roles: ['ADMIN'])),
          ),
        ),
        'every report',
      );
    });

    test('tokens that must not pass', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final unsigned = token(
        {'sub': 'ada', 'exp': now + 3600},
        header: const {'alg': 'none', 'typ': 'JWT'},
      );
      final forged = {
        'expired': userToken('ada', expired: true),
        'signed with another secret': userToken(
          'ada',
          secret: 'ffffffffffffffffffffffffffffffff',
        ),
        'alg none': unsigned,
        'alg none without a signature':
            '${unsigned.substring(0, unsigned.lastIndexOf('.'))}.',
        'without exp': token({'sub': 'ada'}),
        'not a token': 'ada',
        'empty': '',
      };
      for (final MapEntry(:key, :value) in forged.entries) {
        final response = await call('GET', '/api/me', headers: bearer(value));
        expect(response.status, 401, reason: key);
        // An open path with a bad token is refused too, as on a server.
        if (value.isNotEmpty) {
          expect(
            (await call('GET', '/hello', headers: bearer(value))).status,
            401,
            reason: '$key on an open path',
          );
        }
      }
    });

    test('a protected path cannot be reached under another spelling', () async {
      for (final path in [
        '/api/me/',
        '/api/me;x=1',
        '/api;x/me',
        '//api/me',
        '/API/me',
        '/api/./me',
        '/files/../api/me',
        '/files/%2e%2e/api/me',
        '/api/me%20',
        '/api/me.json',
      ]) {
        final response = await call('GET', path);
        expect(response.status, isNot(200), reason: path);
        expect(response.status, lessThan(500), reason: path);
      }
    });

    test('a target the router must not see: 400', () async {
      for (final path in [
        '/files/a%2Fb',
        '/files/a%5Cb',
        '/files/a%00b',
        '/files/%ff',
        '/hello?name=%ff',
      ]) {
        expect((await call('GET', path)).status, 400, reason: path);
      }
    });

    test(
      "the address of the client is the platform's, never a header's",
      () async {
        final response = await call(
          'GET',
          '/hello',
          headers: {
            'x-forwarded-for': '198.51.100.1',
            'x-real-ip': '198.51.100.1',
            'cf-connecting-ip': '198.51.100.1',
            'forwarded': 'for=198.51.100.1',
          },
        );
        expect(
          (await jsonOf(response))! as Map,
          containsPair('remote', '203.0.113.9'),
        );
        final unknown = await call('GET', '/hello', remoteAddress: null);
        expect((await jsonOf(unknown))! as Map, containsPair('remote', null));
      },
    );

    test('the security headers of a server are there', () async {
      final response = await call('GET', '/hello');
      expect(response.header('x-content-type-options'), 'nosniff');
      expect(response.header('x-frame-options'), 'DENY');
      expect(response.header('cache-control'), contains('no-store'));
    });
  });

  group('the instance', () {
    test('the first requests start one context', () async {
      final fresh = application();
      addTearDown(fresh.close);
      final responses = await Future.wait([
        for (var i = 0; i < 5; i++) call('GET', '/hello', on: fresh),
      ]);
      expect(responses.map((r) => r.status), everyElement(200));
      final context = fresh.context;
      await call('GET', '/hello', on: fresh);
      expect(fresh.context, same(context));
      expect(
        context!.getBean<FetchWebServerFactory>().server!.requestCount,
        6,
      );
    });

    test('an application that cannot start: 500, then tried again', () async {
      var starts = 0;
      final broken = FetchApplication(
        () {
          starts++;
          return springApplication;
        },
        properties: {
          ...functionProperties,
          'logging.level.root': 'off',
          // Too short for HS256: the decoder refuses it at start.
          'spring.security.oauth2.resourceserver.jwt.secret-key': 'short',
        },
      );
      addTearDown(broken.close);
      final first = await call('GET', '/hello', on: broken);
      expect(first.status, 500);
      expect(await textOf(first), isNot(contains('secret')));
      expect((await call('GET', '/hello', on: broken)).status, 500);
      expect(starts, 2);
    });

    test('without a web application: 503', () async {
      final none = application(
        properties: {'spring.main.web-application-type': 'none'},
      );
      addTearDown(none.close);
      expect((await call('GET', '/hello', on: none)).status, 503);
    });

    test('closed, it starts again with the next request', () async {
      final fresh = application();
      addTearDown(fresh.close);
      await call('GET', '/hello', on: fresh);
      final first = fresh.context;
      await fresh.close();
      expect(fresh.context, isNull);
      expect((await call('GET', '/hello', on: fresh)).status, 200);
      expect(fresh.context, isNot(same(first)));
    });

    test('what works differently is listed once, unless turned off', () async {
      await call('GET', '/hello');
      final found = function.context!.getBean<EdgeWarnings>().found;
      expect(
        found,
        containsAll([
          contains('rate limiter counts in memory'),
          // Each scheduled method, with its trigger.
          allOf(
            startsWith('@Scheduled Rates.refresh (PeriodicTrigger(fixedRate'),
            contains('timers do not outlive a request'),
          ),
          // Each bean that keeps its state in memory.
          startsWith("cached values (bean 'cacheManager')"),
        ]),
      );
      // Its own line only: not once more among the beans with state.
      expect(found.where((line) => line.contains('rate limit')), hasLength(1));
      final quiet = application(properties: {'spring.edge.warnings': 'false'});
      addTearDown(quiet.close);
      await call('GET', '/hello', on: quiet);
      expect(
        quiet.context!.getBeanProvider<EdgeWarnings>().getIfAvailable(),
        isNull,
      );
    });

    test('the runtime bean names the platform', () async {
      await call('GET', '/hello');
      final runtime = function.context!.getBean<EdgeRuntime>();
      expect(runtime.platform, 'test');
      expect(runtime.isFunction, isTrue);
      expect(const EdgeRuntime(null).isFunction, isFalse);
    });
  });

  group('on Supabase', () {
    const anonKey = 'anon-key-of-the-project';
    const environment = {
      'SUPABASE_URL': 'https://abcd.supabase.co',
      'SUPABASE_ANON_KEY': anonKey,
      'SUPABASE_SERVICE_ROLE_KEY': 'service-key',
    };

    test('the project comes from the environment of the function', () async {
      final supabase = application(runtime: 'supabase');
      addTearDown(supabase.close);
      await call('GET', '/hello', on: supabase, environment: environment);
      final properties = supabase.context!.getBean<Environment>();
      expect(
        properties.getProperty('spring.supabase.url'),
        'https://abcd.supabase.co',
      );
      expect(properties.getProperty('spring.supabase.anon-key'), anonKey);
      expect(
        properties.getProperty('spring.supabase.service-role-key'),
        'service-key',
      );
    });

    test('the anon key as a bearer token is no token', () async {
      final supabase = application(runtime: 'supabase');
      addTearDown(supabase.close);
      Future<int> status(String path, String value) async => (await call(
        'GET',
        path,
        on: supabase,
        environment: environment,
        headers: {'authorization': value},
      )).status;
      // Open to everyone: answered; protected: still 401.
      expect(await status('/hello', 'Bearer $anonKey'), 200);
      expect(await status('/hello', 'bearer  $anonKey '), 200);
      expect(await status('/api/me', 'Bearer $anonKey'), 401);
      // Everything else reaches the resource server.
      expect(await status('/hello', 'Bearer service-key'), 401);
      expect(await status('/hello', 'Bearer ${anonKey}x'), 401);
      expect(await status('/hello', 'Bearer '), isNot(500));
      expect(
        await status('/api/me', 'Bearer ${userToken('ada')}'),
        200,
      );
    });

    test('unless the application wants the key refused', () async {
      final strict = application(
        runtime: 'supabase',
        properties: {'spring.edge.supabase.anon-key-as-anonymous': 'false'},
      );
      addTearDown(strict.close);
      final response = await call(
        'GET',
        '/hello',
        on: strict,
        environment: environment,
        headers: bearer(anonKey),
      );
      expect(response.status, 401);
    });

    test('elsewhere the key is a token like any other', () async {
      final response = await call(
        'GET',
        '/hello',
        environment: environment,
        headers: bearer(anonKey),
      );
      expect(response.status, 401);
    });
  });
}
