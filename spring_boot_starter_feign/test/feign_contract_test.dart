// The property strings are lists of independent entries, each one a single
// string; a long key cannot be split in two (adjacent strings in a list).
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'catalog.dart';
import 'contract.dart';

/// A token that changes on every call, like a refreshed access token.
final class RotatingToken implements RequestInterceptor {
  int calls = 0;

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

  group('dot segments in path variables', () {
    test('"." and ".." are refused: they would change the path', () async {
      server.when(HttpMethod.get, '/files/...').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        final client = context.getBean<ContractClient>();
        for (final value in [
          '..',
          '.',
          'docs/../admin',
          '../../admin',
          './a',
        ]) {
          await expectLater(
            client.file(value),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.message,
                'message',
                contains('must not be "." or ".."'),
              ),
            ),
            reason: value,
          );
        }
        expect(server.requests, isEmpty);
        await client.file('...'); // an ordinary name
        expect('${server.lastRequest.url}', 'https://api.neon.test/files/...');
      });
    });

    test('with decode-slash=false, "../a" is one encoded segment', () async {
      server.when(HttpMethod.get, '/files/..%2Fa').respond(200, body: 'ok');
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.decode-slash=false',
          ])
          .runAsync((context) async {
            final client = context.getBean<ContractClient>();
            await client.file('../a');
            expect(
              '${server.lastRequest.url}',
              'https://api.neon.test/files/..%2Fa',
            );
            await expectLater(client.file('..'), throwsArgumentError);
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
    test("Feign's default timeouts: connect 10 s, read 60 s", () async {
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

    test('negative or signed seconds: not retryable, like Feign', () {
      for (final value in ['-5', '+5', '-1', '1e3', '0x10']) {
        expect(
          const DefaultErrorDecoder().decode('X#y()', unavailable(value)),
          isA<FeignServiceUnavailable>(),
          reason: value,
        );
      }
    });

    test('"120.0" like Feign; a huge number waits a year, never 0', () {
      Duration wait(String value) {
        final error = const DefaultErrorDecoder().decode(
          'X#y()',
          unavailable(value),
        );
        return (error as RetryableException).retryAfter!.difference(
          DateTime.now(),
        );
      }

      expect(wait('120.0').inSeconds, inInclusiveRange(118, 120));
      expect(wait('0').inSeconds, lessThanOrEqualTo(0));
      for (final huge in [
        '9223372036854775807',
        '99999999999999999999999999',
        '31536000000',
      ]) {
        expect(wait(huge).inDays, inInclusiveRange(364, 365), reason: huge);
      }
      // The retryer then waits its maxPeriod, not 0.
      final error = const DefaultErrorDecoder().decode(
        'X#y()',
        unavailable('99999999999999999999999999'),
      ) as RetryableException;
      expect(
        const DefaultRetryer().nextDelay(1, error),
        const DefaultRetryer().maxPeriod,
      );
    });
  });

  group('FeignException.toString', () {
    FeignException error(String body) => FeignException.errorStatus(
      'X#y()',
      HttpResponse(
        500,
        body: utf8.encode(body),
        request: HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('https://api.neon.test/books'),
        ),
      ),
    );

    test('a short body whole', () {
      final short = 'é' * 199; // 398 bytes
      expect('${error(short)}', endsWith(': $short'));
    });

    test("a long body as Feign's preview: 200 characters and the size", () {
      final body = '${'a' * 200}${'b' * 4800}';
      final exception = error(body);
      expect(
        '$exception',
        'FeignInternalServerError: [500 Internal Server Error] during [GET] '
            'to [https://api.neon.test/books] [X#y()]: ${'a' * 200}... '
            '(5000 bytes)',
      );
      expect(exception.responseBody, body);
      // 200 characters, not 200 bytes; a character is not cut in two.
      final emoji = error('😀' * 150);
      expect('$emoji', endsWith(': ${'😀' * 150}... (600 bytes)'));
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
      'headers: every value on its own line, Authorization and DPoP masked',
      () async {
        server.when(HttpMethod.get, '/headers').respond(200, body: 'ok');
        await runner
            .withPropertyValues([
              'spring.cloud.openfeign.client.config.contract-v2.logger-level=headers',
            ])
            .runAsync((context) async {
              await context.getBean<ContractClient>().headers({
                'Authorization': 'Bearer secret',
                'DPoP': 'proof-secret',
                'X-Tag': ['a', 'b'],
              });
            });
        final request = logs.firstWhere((l) => l.startsWith('---> GET'));
        expect(request, contains('X-Tag: a\nX-Tag: b'));
        expect(request, contains('Authorization: ***'));
        expect(request, contains('DPoP: ***'));
        expect(request, isNot(contains('secret')));
      },
    );

    test('headers: cookies, proxy credentials and sensitive-headers masked, '
        'in responses too', () async {
      server
          .when(HttpMethod.get, '/headers')
          .respond(
            200,
            body: 'ok',
            headers: {
              'Set-Cookie': 'SESSION=cookie-secret',
              'X-Request-Id': 'r-1',
            },
          );
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.contract-v2.logger-level=headers',
            'spring.cloud.openfeign.client.config.default.sensitive-headers=X-Api-Key',
            'spring.cloud.openfeign.client.config.contract-v2.sensitive-headers[0]=x-partner-token',
          ])
          .runAsync((context) async {
            await context.getBean<ContractClient>().headers({
              'Cookie': 'SESSION=cookie-secret',
              'Proxy-Authorization': 'Basic proxy-secret',
              'X-API-KEY': 'key-secret',
              'X-Partner-Token': 'partner-secret',
              'X-Tag': 'visible',
            });
          });
      final request = logs.firstWhere((l) => l.startsWith('---> GET'));
      final response = logs.firstWhere((l) => l.startsWith('<--- 200'));
      expect(request, contains('X-Tag: visible'));
      expect(request, contains('Cookie: ***'));
      expect(request, contains('Proxy-Authorization: ***'));
      expect(
        request,
        contains(RegExp(r'X-API-KEY: \*\*\*', caseSensitive: false)),
      );
      expect(
        request,
        contains(RegExp(r'X-Partner-Token: \*\*\*', caseSensitive: false)),
      );
      expect(
        response,
        contains(RegExp(r'set-cookie: \*\*\*', caseSensitive: false)),
      );
      expect(
        response,
        contains(RegExp('x-request-id: r-1', caseSensitive: false)),
      );
      expect('$request$response', isNot(contains('secret')));
    });
  });
}
