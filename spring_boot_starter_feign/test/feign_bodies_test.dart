import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'bodies.dart';
import 'catalog.dart';
import 'client_configuration.dart';

void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(bodiesModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => server);
  });

  group('form bodies (SpringFormEncoder)', () {
    test('a Map is sent as name=value pairs, lists repeat, null is left '
        'out', () async {
      server.when(HttpMethod.post, '/login').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<FormClient>().login({
          'user': 'neo & trinity',
          'password': 's3cr?t',
          'roles': ['a', 'b'],
          'missing': null,
          'age': 3,
        });
        final request = server.lastRequest;
        expect(
          request.headers.contentType,
          MediaType.applicationFormUrlencoded,
        );
        expect(
          utf8.decode(request.body!),
          'user=neo+%26+trinity&password=s3cr%3Ft&roles=a&roles=b&age=3',
        );
      });
    });

    test('an object by its properties, in the charset of the type', () async {
      server.when(HttpMethod.post, '/books').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<FormClient>().book(
          const Book(isbn: '978-0', title: 'Café'),
        );
        final request = server.lastRequest;
        expect(
          request.headers.contentType,
          'application/x-www-form-urlencoded; charset=ISO-8859-1',
        );
        expect(utf8.decode(request.body!), 'isbn=978-0&title=Caf%E9');
      });
    });

    test('the Content-Type header of the mapping counts too', () async {
      server.when(HttpMethod.post, '/header').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<FormClient>().header({'a': 'b c'});
        expect(utf8.decode(server.lastRequest.body!), 'a=b+c');
      });
    });

    test('a nested object fails the call', () async {
      await runner.runAsync((context) async {
        await expectLater(
          context.getBean<FormClient>().login({
            'nested': {'a': 1},
          }),
          throwsA(isA<EncodeException>()),
        );
      });
    });
  });

  test('ResponseEntity<void> ignores the body', () async {
    server
        .when(HttpMethod.delete, '/books/1')
        .respond(
          202,
          body: 'deleted, not JSON',
          headers: {'X-Id': '1', 'Content-Type': 'text/plain'},
        );
    await runner.runAsync((context) async {
      final entity = await context.getBean<FormClient>().delete('1');
      expect(entity.statusCode, 202);
      expect(entity.hasBody, isFalse);
      expect(entity.headers['x-id'], '1');
    });
  });

  test('Future<HttpResponse> is the raw response, errors included', () async {
    server.when(HttpMethod.get, '/raw').respond(503, body: 'busy');
    await runner.runAsync((context) async {
      final response = await context.getBean<FormClient>().raw();
      expect(response.statusCode, 503);
      expect(response.bodyText, 'busy');
    });
  });

  test('a request-interceptors bean that is also a context bean runs '
      'once', () async {
    server.when(HttpMethod.get, '/raw').respond(200, body: 'ok');
    await runner
        .withBean<RequestInterceptor>(AuditInterceptor.new, name: 'audit')
        .withPropertyValues([
          'spring.cloud.openfeign.client.config.forms.request-interceptors[0]='
              'audit',
          'spring.cloud.openfeign.client.config.default.request-interceptors[0]='
              'AuditInterceptor',
        ])
        .runAsync((context) async {
          await context.getBean<FormClient>().raw();
          expect(server.lastRequest.headers.getAll('X-Audit'), ['yes']);
        });
  });
}
