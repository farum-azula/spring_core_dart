import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'catalog.dart';
import 'contract.dart';

/// A token that changes on every call, like a refreshed access token.
final class RotatingToken implements RequestInterceptor {
  var calls = 0;

  @override
  void apply(RequestTemplate template) =>
      template.header('Authorization', 'Bearer t-${++calls}');
}

final class Tracing implements RequestInterceptor {
  @override
  void apply(RequestTemplate template) {
    template
      ..header('X-Trace', 'a')
      ..header('X-Trace', 'b')
      ..removeHeader('X-Shop')
      ..header('X-Shop', 'replaced');
    if (template.methodKey.startsWith('ContractClient#filter')) {
      template.query('lang', 'fr');
    }
  }
}

void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(contractModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => server);
  });

  group('Map parameters', () {
    test('@RequestParam Map: one query parameter per entry', () async {
      server.when(HttpMethod.get, '/books').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<ContractClient>().filter({
          'author': 'Frank Herbert',
          'year': 1965,
          'tag': ['sf', 'classic'],
          'missing': null,
          'mood': JsonInclusion.always,
        }, page: 2);
        final url = server.lastRequest.url;
        expect(url.queryParametersAll, {
          'author': ['Frank Herbert'],
          'year': ['1965'],
          'tag': ['sf', 'classic'],
          'mood': ['always'],
          'page': ['2'],
        });
        // Not JSON in one parameter (the name of a Map parameter is unused).
        expect(url.query, isNot(contains('%7B')));
        expect(url.queryParameters.containsKey('filters'), isFalse);
      });
    });

    test('@RequestHeader Map: one header per entry', () async {
      server.when(HttpMethod.get, '/headers').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<ContractClient>().headers({
          'X-Tenant': 'neon',
          'X-Tag': ['a', 'b'],
          'X-None': null,
        });
        final headers = server.lastRequest.headers;
        expect(headers['X-Tenant'], 'neon');
        expect(headers.getAll('X-Tag'), ['a', 'b']);
        expect(headers.contains('X-None'), isFalse);
        expect(headers.contains('ignored'), isFalse);
        expect(headers.contains('all'), isFalse);
      });
    });

    test('object values fail at startup with the reason', () {
      const ApplicationContextRunner()
          .withUserConfiguration(invalidModule)
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
          .withBean<HttpTransport>(() => MockHttpTransport())
          .run((context) {
            final failure = '${context.startupFailure}';
            expect(failure, contains('Invalid Feign client InvalidClient'));
            expect(
              failure,
              contains(
                'InvalidClient.byBook: the @RequestParam parameter book is an '
                'object (Book)',
              ),
            );
            expect(
              failure,
              contains(
                'InvalidClient.byBooks: the @RequestHeader parameter books is '
                'an object',
              ),
            );
            expect(
              failure,
              contains(
                'InvalidClient.byMap: the @RequestParam parameter books is an '
                'object',
              ),
            );
            expect(
              failure,
              contains(
                'InvalidClient.byPathMap: the @PathVariable parameter id is a '
                'Map',
              ),
            );
          });
    });

    test('an object passed as Object fails the call, not as JSON', () async {
      await runner.runAsync((context) async {
        await expectLater(
          context.getBean<ContractClient>().search(
            const Book(isbn: '1', title: 'Dune'),
          ),
          throwsA(
            isA<EncodeException>().having(
              (e) => e.message,
              'message',
              contains('@RequestParam "q" of ContractClient#search'),
            ),
          ),
        );
        expect(server.requests, isEmpty);
      });
    });
  });

  test('headers: Spring\'s "Name=value"; conditions are ignored', () async {
    server.when(HttpMethod.get, '/static').respond(200, body: 'ok');
    await runner.runAsync((context) async {
      await context.getBean<ContractClient>().statics();
      final headers = server.lastRequest.headers;
      expect(headers['X-Shop'], 'neon');
      expect(headers['X-Expr'], 'books');
      expect(headers['X-Token'], 'a=b');
      expect(headers.contains('X-Debug'), isFalse);
      expect(headers.contains('!X-Debug'), isFalse);
      expect(headers.contains('X-Mode'), isFalse);
      expect(headers.contains('X-Present'), isFalse);
    });
    // Feign's "Name: value" is rejected with the reason.
    const ApplicationContextRunner()
        .withUserConfiguration(invalidModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => MockHttpTransport())
        .run((context) {
          expect(
            '${context.startupFailure}',
            contains(
              'InvalidClient.oldHeaders: header "X-Old: syntax" must look '
              'like "Name=value"',
            ),
          );
        });
  });

  test('@CookieValue: one Cookie header, null left out', () async {
    server.when(HttpMethod.get, '/cart').respond(200, body: 'ok');
    await runner.runAsync((context) async {
      final client = context.getBean<ContractClient>();
      await client.cart('s-1', 'dark');
      expect(server.lastRequest.headers['Cookie'], 'SESSION=s-1; theme=dark');
      await client.cart('s-2');
      expect(server.lastRequest.headers.getAll('cookie'), ['SESSION=s-2']);
    });
  });

  group('decode-slash', () {
    test('a / in a path variable stays a / by default', () async {
      server
          .when(HttpMethod.get, '/files/docs/a b.txt')
          .respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<ContractClient>().file('docs/a b.txt');
        expect(
          '${server.lastRequest.url}',
          'https://api.neon.test/files/docs/a%20b.txt',
        );
      });
    });

    test('decode-slash=false encodes it', () async {
      server
          .when(HttpMethod.get, '/files/docs%2Fa.txt')
          .respond(200, body: 'ok');
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.decode-slash=false',
          ])
          .runAsync((context) async {
            await context.getBean<ContractClient>().file('docs/a.txt');
            expect(
              '${server.lastRequest.url}',
              'https://api.neon.test/files/docs%2Fa.txt',
            );
          });
    });
  });

  group('@FeignClient attributes', () {
    test('dismiss404: null for nullable results, void still throws', () async {
      server
        ..when(HttpMethod.get, '/books/0').respond(404)
        ..when(HttpMethod.delete, '/books/0').respond(404);
      await runner.runAsync((context) async {
        final client = context.getBean<ContractClient>();
        expect(await client.find('0'), isNull);
        // Like Feign: dismiss404 does not hide a failed void call.
        await expectLater(client.delete('0'), throwsA(isA<FeignNotFound>()));
      });
    });

    test('the dismiss404 property keeps throwing for void too', () async {
      server.when(HttpMethod.delete, '/v1/books/7').respond(404);
      await const ApplicationContextRunner()
          .withUserConfiguration(appModule)
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
          .withPropertyValues([
            'catalog.url=https://api.neon.test',
            'spring.cloud.openfeign.client.config.catalog.dismiss404=true',
          ])
          .withBean<HttpTransport>(() => server)
          .runAsync((context) async {
            await expectLater(
              context.getBean<CatalogClient>().delete('7'),
              throwsA(isA<FeignNotFound>()),
            );
          });
    });

    test('contextId keys the configuration', () async {
      server.when(HttpMethod.get, '/static').respond(200, body: 'ok');
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.contract-v2.default-request-headers.X-Context=v2',
            'spring.cloud.openfeign.client.config.contract.default-request-headers.X-Name=ignored',
          ])
          .runAsync((context) async {
            await context.getBean<ContractClient>().statics();
            final headers = server.lastRequest.headers;
            expect(headers['X-Context'], 'v2');
            expect(headers.contains('X-Name'), isFalse);
          });
    });
  });

  group('configuration', () {
    test('Feign\'s default timeouts: connect 10 s, read 60 s', () async {
      server.when(HttpMethod.get, '/static').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<ContractClient>().statics();
        final request = server.lastRequest;
        expect(request.readTimeout, const Duration(seconds: 60));
        // A read timeout, not a deadline for the whole call.
        expect(request.timeout, isNull);
        expect(request.followRedirects, isTrue);
        expect(
          FeignClientConfig.connectTimeout(context.getBean<Environment>()),
          const Duration(seconds: 10),
        );
      });
    });

    test('read-timeout=0 means none; follow-redirects=false', () async {
      server.when(HttpMethod.get, '/static').respond(200, body: 'ok');
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.default.read-timeout=0',
            'spring.cloud.openfeign.client.config.contract-v2.follow-redirects=false',
          ])
          .runAsync((context) async {
            await context.getBean<ContractClient>().statics();
            expect(server.lastRequest.readTimeout, isNull);
            expect(server.lastRequest.followRedirects, isFalse);
          });
    });

    test('default-query-parameters: added when the request has none of '
        'the name', () async {
      server
        ..when(HttpMethod.get, '/static').respond(200, body: 'ok')
        ..when(HttpMethod.get, '/books').respond(200, body: 'ok');
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.default.default-query-parameters.lang=en',
            'spring.cloud.openfeign.client.config.contract-v2.default-query-parameters.tag=a,b',
          ])
          .withBean<RequestInterceptor>(() => Tracing())
          .runAsync((context) async {
            final client = context.getBean<ContractClient>();
            await client.statics();
            expect(server.lastRequest.url.queryParametersAll, {
              'lang': ['en'],
              'tag': ['a', 'b'],
            });
            // The method's own value and the interceptor's win.
            await client.filter({'tag': 'x'});
            expect(server.lastRequest.url.queryParametersAll, {
              'tag': ['x'],
              'lang': ['fr'],
            });
          });
    });

    test('default-request-headers come after the interceptors, and may set '
        'Accept', () async {
      server.when(HttpMethod.get, '/static').respond(200, body: 'ok');
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.default.default-request-headers.X-Shop=default',
            'spring.cloud.openfeign.client.config.default.default-request-headers.Accept=text/plain',
          ])
          .withBean<RequestInterceptor>(() => Tracing())
          .runAsync((context) async {
            await context.getBean<ContractClient>().statics();
            final headers = server.lastRequest.headers;
            expect(headers.getAll('X-Shop'), ['replaced']);
            expect(headers[HttpHeaders.acceptHeader], 'text/plain');
          });
    });
  });

  group('RequestTemplate', () {
    test('header appends like Feign; removeHeader then header replaces', () {
      final template =
          RequestTemplate(
              method: HttpMethod.get,
              url: Uri.parse('https://api.neon.test/books'),
              methodKey: 'X#y()',
              clientName: 'x',
            )
            ..header('X-Trace', 'a')
            ..header('x-trace', 'b');
      expect(template.headers.getAll('X-Trace'), ['a', 'b']);
      template
        ..removeHeader('X-TRACE')
        ..header('X-Trace', 'c');
      expect(template.headers.getAll('X-Trace'), ['c']);
    });

    test('interceptors run on every retry, from a fresh template', () async {
      final calls = server.when(HttpMethod.get, '/static');
      var attempt = 0;
      calls.respondWith((request) {
        if (++attempt == 1) {
          throw HttpTransportException('connection reset', request: request);
        }
        return HttpResponse(200, body: utf8.encode('ok'), request: request);
      });
      final token = RotatingToken();
      await runner
          .withBean<RequestInterceptor>(() => token)
          .withBean<Retryer>(
            () => const DefaultRetryer(period: Duration(milliseconds: 1)),
          )
          .runAsync((context) async {
            expect(await context.getBean<ContractClient>().statics(), 'ok');
          });
      expect(server.requests, hasLength(2));
      expect(server.requests[0].headers.getAll('Authorization'), [
        'Bearer t-1',
      ]);
      // The refreshed token, alone.
      expect(server.requests[1].headers.getAll('Authorization'), [
        'Bearer t-2',
      ]);
    });
  });

  group('Retry-After', () {
    HttpResponse unavailable(String retryAfter) => HttpResponse(
      503,
      headers: HttpHeaders({'Retry-After': retryAfter}),
      request: HttpRequest(
        method: HttpMethod.get,
        url: Uri.parse('https://api.neon.test/books'),
      ),
    );

    test('as seconds', () {
      final error = const DefaultErrorDecoder().decode(
        'X#y()',
        unavailable('120'),
      );
      expect(error, isA<RetryableException>());
      final retryAfter = (error as RetryableException).retryAfter!;
      expect(
        retryAfter.difference(DateTime.now()).inSeconds,
        inInclusiveRange(118, 120),
      );
    });

    test('as an HTTP date', () {
      final error = const DefaultErrorDecoder().decode(
        'X#y()',
        unavailable('Wed, 21 Oct 2015 07:28:00 GMT'),
      );
      expect(error, isA<RetryableException>());
      expect(
        (error as RetryableException).retryAfter,
        DateTime.utc(2015, 10, 21, 7, 28),
      );
      expect(
        const DefaultErrorDecoder().decode('X#y()', unavailable('soon')),
        isA<FeignServiceUnavailable>(),
      );
    });
  });

  group('logging', () {
    late List<String> logs;

    setUp(() {
      logs = [];
      final cancel = SpringLog.listen((record) => logs.add(record.message));
      final saved = SpringLog.level;
      SpringLog.level = SpringLogLevel.debug;
      addTearDown(() {
        cancel();
        SpringLog.level = saved;
      });
    });

    Future<void> failOnce(ApplicationContextRunner runner) async {
      var attempt = 0;
      server.when(HttpMethod.get, '/static').respondWith((request) {
        if (++attempt == 1) {
          throw HttpTransportException('connection reset', request: request);
        }
        return HttpResponse(200, body: utf8.encode('ok'), request: request);
      });
      await runner
          .withBean<Retryer>(
            () => const DefaultRetryer(period: Duration(milliseconds: 1)),
          )
          .runAsync((context) async {
            await context.getBean<ContractClient>().statics();
          });
    }

    test('no ERROR or RETRYING lines with logger-level none', () async {
      await failOnce(runner);
      expect(logs.where((l) => l.contains('<--- ERROR')), isEmpty);
      expect(logs.where((l) => l.contains('---> RETRYING')), isEmpty);
    });

    test('ERROR and RETRYING lines above none', () async {
      await failOnce(
        runner.withPropertyValues([
          'spring.cloud.openfeign.client.config.contract-v2.logger-level=basic',
        ]),
      );
      expect(logs.where((l) => l.startsWith('<--- ERROR')), hasLength(1));
      expect(logs.where((l) => l.startsWith('---> RETRYING')), hasLength(1));
    });

    test(
      'headers: every value on its own line, Authorization masked',
      () async {
        server.when(HttpMethod.get, '/headers').respond(200, body: 'ok');
        await runner
            .withPropertyValues([
              'spring.cloud.openfeign.client.config.contract-v2.logger-level=headers',
            ])
            .runAsync((context) async {
              await context.getBean<ContractClient>().headers({
                'Authorization': 'Bearer secret',
                'X-Tag': ['a', 'b'],
              });
            });
        final request = logs.firstWhere((l) => l.startsWith('---> GET'));
        expect(request, contains('X-Tag: a\nX-Tag: b'));
        expect(request, contains('Authorization: ***'));
        expect(request, isNot(contains('secret')));
      },
    );
  });
}
