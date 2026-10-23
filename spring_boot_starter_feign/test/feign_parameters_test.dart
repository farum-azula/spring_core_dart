import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'parameters.dart';

void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(parametersModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(server);
  });

  group('a mapping without a path', () {
    test('@GetMapping() is the base path of the client', () async {
      server.when(HttpMethod.get, '/api').respond(200, body: 'root');
      await runner.runAsync((context) async {
        expect(await context.getBean<ParamsClient>().root(), 'root');
        expect('${server.lastRequest.url}', 'https://api.neon.test/api');
      });
    });

    test('without a client path it is the url', () async {
      server
        ..when(HttpMethod.get, '/').respond(200, body: 'index')
        ..when(HttpMethod.post, '/').respond(200, body: 'created');
      await runner.runAsync((context) async {
        final client = context.getBean<RootClient>();
        expect(await client.index(), 'index');
        expect('${server.lastRequest.url}', 'https://api.neon.test');
        expect(await client.create('hi'), 'created');
        expect(server.lastRequest.method, HttpMethod.post);
      });
    });
  });

  group('defaultValue', () {
    test('is sent for a null argument, an argument wins', () async {
      server.when(HttpMethod.get, '/api/search').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        final client = context.getBean<ParamsClient>();
        await client.search('dune');
        var request = server.lastRequest;
        expect(request.url.queryParametersAll, {
          'q': ['dune'],
          'sort': ['asc'],
        });
        expect(request.headers.getAll('X-Tenant'), ['public']);

        await client.search('dune', sort: 'desc', tenant: 'acme');
        request = server.lastRequest;
        expect(request.url.queryParametersAll['sort'], ['desc']);
        expect(request.headers.getAll('X-Tenant'), ['acme']);
      });
    });
  });

  group('not required', () {
    test('a null query parameter or header is left out', () async {
      server.when(HttpMethod.get, '/api/search').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        final client = context.getBean<ParamsClient>();
        await client.search('dune');
        final request = server.lastRequest;
        // page: required false; lang and trace: nullable parameters.
        expect(request.url.queryParametersAll.keys, ['q', 'sort']);
        expect(request.headers.contains('X-Trace'), isFalse);

        await client.search('dune', page: 2, lang: 'en', trace: 't');
        expect(server.lastRequest.url.queryParametersAll, {
          'q': ['dune'],
          'sort': ['asc'],
          'page': ['2'],
          'lang': ['en'],
        });
        expect(server.lastRequest.headers['X-Trace'], 't');
      });
    });

    test('a null path variable is an empty string', () async {
      server
        ..when(HttpMethod.get, '/api/books/42/pages').respond(200, body: 'p')
        ..when(HttpMethod.get, '/api/books//pages').respond(200, body: 'none');
      await runner.runAsync((context) async {
        final client = context.getBean<ParamsClient>();
        expect(await client.pages('42'), 'p');
        expect(await client.pages(null), 'none');
        expect(server.lastRequest.url.path, '/api/books//pages');
      });
    });

    test('required: false lets a non-nullable parameter be null', () async {
      server.when(HttpMethod.get, '/api/lenient').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        final client = context.getBean<ParamsClient>() as dynamic;
        // Not reachable with the typed interface; the proxy accepts null.
        await client.lenient(null, null);
        expect(server.lastRequest.url.hasQuery, isFalse);
        expect(server.lastRequest.headers.contains('X-Q'), isFalse);
      });
    });
  });

  group('required', () {
    // The type system keeps null away from generated code; the handler
    // still checks, naming the parameter.
    Future<Object?> call(
      AssertableApplicationContext context,
      String? id,
      String? query,
      String? requestId,
    ) => (context.getBean<ParamsClient>() as dynamic).strict(
      id,
      query,
      requestId,
    ) as Future<Object?>;

    test('a null path variable is an error naming it', () async {
      await runner.runAsync((context) async {
        await expectLater(
          call(context, null, 'dune', 'r-1'),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'id')
                .having(
                  (e) => '${e.message}',
                  'message',
                  allOf(contains('@PathVariable "id"'), contains('strict')),
                ),
          ),
        );
      });
    });

    test('a null path variable is required whatever its type', () async {
      await runner.runAsync((context) async {
        await expectLater(
          context.getBean<ParamsClient>().loose(null),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'id')),
        );
      });
    });

    test('a null query parameter is an error naming it', () async {
      await runner.runAsync((context) async {
        await expectLater(
          call(context, '1', null, 'r-1'),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'query')
                .having(
                  (e) => '${e.message}',
                  'message',
                  contains('@RequestParam "q"'),
                ),
          ),
        );
        expect(server.requests, isEmpty);
      });
    });

    test('a null header is an error naming it', () async {
      await runner.runAsync((context) async {
        await expectLater(
          call(context, '1', 'dune', null),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'requestId')
                .having(
                  (e) => '${e.message}',
                  'message',
                  contains('@RequestHeader "X-Id"'),
                ),
          ),
        );
        expect(server.requests, isEmpty);
      });
    });

    test('values are sent', () async {
      server.when(HttpMethod.get, '/api/strict/1').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await call(context, '1', 'dune', 'r-1');
        expect(server.lastRequest.url.queryParameters, {'q': 'dune'});
        expect(server.lastRequest.headers['X-Id'], 'r-1');
      });
    });
  });
}
