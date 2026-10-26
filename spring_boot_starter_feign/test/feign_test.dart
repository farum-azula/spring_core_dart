import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'catalog.dart';

final class TraceInterceptor implements RequestInterceptor {
  @override
  void apply(RequestTemplate template) =>
      template.header('X-Client', template.clientName);
}

final class _TransportRegistrar implements BeanRegistrar {
  _TransportRegistrar(this.transport);
  final HttpTransport transport;

  @override
  void register(BeanRegistry registry, Environment environment) => registry
      .registerBean<HttpTransport>((_) => transport, name: 'appTransport');
}

void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withPropertyValues(['catalog.url=https://api.neon.test'])
        .withBean<HttpTransport>(() => server);
  });

  test('backs off for an HttpTransport of a registrar the application '
      '@Imports', () {
    // What the generator emits for `@Configuration()
    // @Import([TransportRegistrar]) class AppConfig {}`.
    final app = BeanModule(
      'imports',
      [
        BeanDefinition<Object>(
          name: 'appConfig',
          source: 'package:app/app.dart#AppConfig',
          annotations: const [Configuration()],
          create: (_) => Object(),
        ),
      ],
      registrars: [
        ImportDeclaration(
          () => _TransportRegistrar(server),
          importer: 'package:app/app.dart#AppConfig',
        ),
      ],
    );
    const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withUserConfiguration(app)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withPropertyValues(['catalog.url=https://api.neon.test'])
        .run((context) {
          expect(context, hasSingleBean<HttpTransport>());
          expect(context.getBean<HttpTransport>(), same(server));
          expect(context.getBean<CatalogClient>(), isNotNull);
        });
  });

  test('GET with a path variable, JSON into an immutable class', () async {
    server
        .when(HttpMethod.get, '/v1/books/978-0')
        .respond(200, json: {'isbn': '978-0', 'title': 'Dune'});
    await runner.runAsync((context) async {
      final book = await context.getBean<CatalogClient>().find('978-0');
      expect(book.title, 'Dune');
      final request = server.lastRequest;
      expect('${request.url}', 'https://api.neon.test/v1/books/978-0');
      expect(
        request.headers[HttpHeaders.acceptHeader],
        MediaType.applicationJson,
      );
    });
  });

  test('query parameters, headers and lists', () async {
    server
        .when(HttpMethod.get, '/v1/books')
        .respond(
          200,
          json: [
            {'isbn': '1', 'title': 'A'},
            {'isbn': '2', 'title': 'B'},
          ],
        );
    await runner.runAsync((context) async {
      final client = context.getBean<CatalogClient>();
      final books = await client.search('dune & co', page: 2, trace: 't-1');
      expect(books, isA<List<Book>>());
      expect([for (final b in books) b.title], ['A', 'B']);
      final request = server.lastRequest;
      expect(request.url.queryParameters, {'q': 'dune & co', 'page': '2'});
      expect(request.headers['X-Trace'], 't-1');
      // Null arguments are left out.
      await client.search('x');
      expect(server.lastRequest.url.queryParameters, {'q': 'x'});
      expect(server.lastRequest.headers.contains('X-Trace'), isFalse);
    });
  });

  test(
    'POST with a JSON body, ResponseEntity with status and headers',
    () async {
      server
          .when(HttpMethod.post, '/v1/books')
          .respond(
            201,
            json: {'isbn': '3', 'title': 'Ubik'},
            headers: {'Location': '/v1/books/3'},
          );
      await runner.runAsync((context) async {
        final entity = await context.getBean<CatalogClient>().create(
          const Book(isbn: '3', title: 'Ubik'),
        );
        expect(entity, isA<ResponseEntity<Book>>());
        expect(entity.statusCode, 201);
        expect(entity.body!.title, 'Ubik');
        expect(entity.headers['location'], '/v1/books/3');
        final request = server.lastRequest;
        expect(jsonDecode(utf8.decode(request.body!)), {
          'isbn': '3',
          'title': 'Ubik',
        });
        expect(
          request.headers[HttpHeaders.contentTypeHeader],
          MediaType.applicationJson,
        );
      });
    },
  );

  test('void results, static headers with placeholders, plain text', () async {
    server.when(HttpMethod.delete, '/v1/books/7').respond(204);
    server.when(HttpMethod.get, '/v1/ping').respond(200, body: 'pong');
    await runner.runAsync((context) async {
      final client = context.getBean<CatalogClient>();
      await client.delete('7');
      expect(server.lastRequest.method, HttpMethod.delete);
      expect(await client.ping(), 'pong');
      expect(server.lastRequest.headers['X-Shop'], 'neon');
    });
  });

  test('error responses become FeignException subclasses', () async {
    server
        .when(HttpMethod.get, '/v1/books/0')
        .respond(404, body: 'no such book');
    server.when(HttpMethod.get, '/v1/books/9').respond(503);
    await runner.runAsync((context) async {
      final client = context.getBean<CatalogClient>();
      await expectLater(
        client.find('0'),
        throwsA(
          isA<FeignNotFound>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.responseBody, 'body', 'no such book')
              .having(
                (e) => e.message,
                'message',
                contains('CatalogClient#find(String)'),
              ),
        ),
      );
      await expectLater(
        client.find('9'),
        throwsA(isA<FeignServiceUnavailable>()),
      );
    });
  });

  test('dismiss404 turns a 404 into null for nullable results', () async {
    server.when(HttpMethod.get, '/v1/books/0/details').respond(404);
    await runner
        .withPropertyValues([
          'spring.cloud.openfeign.client.config.catalog.dismiss404=true',
        ])
        .runAsync((context) async {
          expect(await context.getBean<CatalogClient>().maybe('0'), isNull);
        });
  });

  test('configuration: default headers, read timeout, interceptors', () async {
    server
        .when(HttpMethod.get, '/v1/books/1')
        .respond(200, json: {'isbn': '1', 'title': 'A'});
    await runner
        .withPropertyValues([
          'spring.cloud.openfeign.client.config.default.read-timeout=3s',
          'spring.cloud.openfeign.client.config.catalog.default-request-headers.X-Shop=neon',
        ])
        .withBean<RequestInterceptor>(() => TraceInterceptor())
        .runAsync((context) async {
          await context.getBean<CatalogClient>().find('1');
          final request = server.lastRequest;
          expect(request.readTimeout, const Duration(seconds: 3));
          expect(request.headers['X-Shop'], 'neon');
          expect(request.headers['X-Client'], 'catalog');
        });
  });

  test('connection errors are retried by a Retryer bean', () async {
    final expectation = server.when(HttpMethod.get, '/v1/books/1');
    var calls = 0;
    expectation.respondWith((request) {
      calls++;
      if (calls < 3) {
        throw HttpTransportException('connection reset', request: request);
      }
      return HttpResponse(
        200,
        body: utf8.encode('{"isbn":"1","title":"A"}'),
        request: request,
      );
    });
    await runner
        .withBean<Retryer>(
          () => const DefaultRetryer(
            period: Duration(milliseconds: 1),
            maxAttempts: 3,
          ),
        )
        .runAsync((context) async {
          expect((await context.getBean<CatalogClient>().find('1')).title, 'A');
          expect(calls, 3);
        });
  });

  test('without a Retryer, a connection error fails at once', () async {
    server
        .when(HttpMethod.get, '/v1/books/1')
        .fail(HttpTransportException('connection refused'));
    await runner.runAsync((context) async {
      await expectLater(
        context.getBean<CatalogClient>().find('1'),
        throwsA(
          isA<RetryableException>().having((e) => e.status, 'status', -1),
        ),
      );
    });
  });

  test('a fallback bean answers when the call fails', () async {
    server.when(HttpMethod.get, '/motd').respond(500);
    await runner.runAsync((context) async {
      expect(await context.getBean<BackupClient>().motd(), 'offline');
      // The client is primary: injecting BackupClient is not ambiguous.
      expect(context.getBean<BackupClient>(), isNot(isA<BackupFallback>()));
    });
  });

  test('basic logging', () async {
    final logs = <String>[];
    final cancel = SpringLog.listen((record) => logs.add(record.message));
    final saved = SpringLog.level;
    SpringLog.level = SpringLogLevel.debug;
    addTearDown(() {
      cancel();
      SpringLog.level = saved;
    });
    server.when(HttpMethod.get, '/v1/ping').respond(200, body: 'pong');
    await runner
        .withPropertyValues([
          'spring.cloud.openfeign.client.config.catalog.logger-level=basic',
        ])
        .runAsync((context) async {
          await context.getBean<CatalogClient>().ping();
        });
    expect(logs, contains('---> GET https://api.neon.test/v1/ping'));
    expect(logs.any((l) => l.startsWith('<--- 200 OK')), isTrue);
  });

  test('an invalid client stops the application with the reasons', () {
    const ApplicationContextRunner()
        .withUserConfiguration(brokenModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => MockHttpTransport())
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid Feign client BrokenClient'));
          expect(failure, contains('path variable {isbn}'));
          expect(failure, contains('@PathVariable "id" is not in the path'));
          expect(
            failure,
            contains('BrokenClient.noMapping needs exactly one of'),
          );
        });
  });

  test('a client without a URL is reported', () {
    const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => MockHttpTransport())
        .run((context) {
          expect('${context.startupFailure}', contains('catalog.url'));
        });
  });
}
