// The property strings are lists of independent entries, each one a single
// string; a long key cannot be split in two (adjacent strings in a list).
// ignore_for_file: no_adjacent_strings_in_list, lines_longer_than_80_chars

import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'client_configuration.dart';

void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(clientConfigurationModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => server)
        .withBean<RequestInterceptor>(TraceInterceptor.new, name: 'trace');
  });

  group('@FeignClient(configuration:)', () {
    test('its interceptors apply to its client only, with the '
        "application's", () async {
      server
        ..when(
          HttpMethod.get,
          'http://inventory.test/ping',
        ).respond(200, body: 'ok')
        ..when(
          HttpMethod.get,
          'http://plain.test/ping',
        ).respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<InventoryClient>().ping();
        final inventory = server.lastRequest.headers;
        expect(inventory['X-Trace'], 'inventory');
        // Feign's BasicAuthRequestInterceptor: ISO-8859-1.
        expect(
          inventory[HttpHeaders.authorizationHeader],
          'Basic ${base64Encode(latin1.encode('stock:pässword'))}',
        );

        await context.getBean<PlainClient>().ping();
        final plain = server.lastRequest.headers;
        expect(plain['X-Trace'], 'plain');
        expect(plain.contains(HttpHeaders.authorizationHeader), isFalse);
      });
    });

    test('its Retryer and ErrorDecoder win for its client only', () async {
      var inventoryCalls = 0;
      server.when(HttpMethod.get, 'http://inventory.test/ping').respondWith((
        request,
      ) {
        inventoryCalls++;
        throw HttpTransportException('reset', request: request);
      });
      server.when(HttpMethod.get, 'http://plain.test/ping').respond(503);
      await runner.runAsync((context) async {
        await expectLater(
          context.getBean<InventoryClient>().ping(),
          throwsA(isA<RetryableException>()),
        );
        expect(inventoryCalls, 2); // DefaultRetryer(maxAttempts: 2)

        // The plain client: no retries, the default ErrorDecoder.
        await expectLater(
          context.getBean<PlainClient>().ping(),
          throwsA(isA<FeignServiceUnavailable>()),
        );
        expect(
          server.requests.where((r) => r.url.host == 'plain.test'),
          hasLength(1),
        );
      });
    });

    test('the ErrorDecoder of the configuration decodes errors', () async {
      server.when(HttpMethod.get, 'http://inventory.test/ping').respond(404);
      await runner.runAsync((context) async {
        await expectLater(
          context.getBean<InventoryClient>().ping(),
          throwsA(
            isA<InventoryException>().having((e) => e.status, 'status', 404),
          ),
        );
      });
    });
  });

  group('retryer / error-decoder / request-interceptors properties', () {
    test('name beans by bean name or class name and win over the '
        'configuration classes', () async {
      var calls = 0;
      server.when(HttpMethod.get, 'http://plain.test/ping').respondWith((
        request,
      ) {
        calls++;
        throw HttpTransportException('reset', request: request);
      });
      server
          .when(HttpMethod.get, 'http://inventory.test/ping')
          .respond(200, body: 'ok');
      await runner
          .withBean<RequestInterceptor>(AuditInterceptor.new, name: 'audit')
          .withBean<Retryer>(FastRetryer.new, name: 'fast')
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.plain.retryer='
                'com.example.FastRetryer',
            'spring.cloud.openfeign.client.config.plain.request-interceptors[0]='
                'audit',
            'spring.cloud.openfeign.client.config.inventory.error-decoder='
                'inventoryErrors',
          ])
          .runAsync((context) async {
            await expectLater(
              context.getBean<PlainClient>().ping(),
              throwsA(isA<RetryableException>()),
            );
            expect(calls, 3); // FastRetryer: 3 attempts
            expect(server.lastRequest.headers['X-Audit'], 'yes');
          });
    });

    test('an unknown bean stops the application', () {
      runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.plain.retryer=nope',
          ])
          .run((context) {
            expect(context, hasFailed());
            expect(
              '${context.startupFailure}',
              contains(
                'spring.cloud.openfeign.client.config.plain.retryer=nope',
              ),
            );
          });
    });
  });

  group('URLs', () {
    test('a url without a scheme gets http://', () async {
      server.when(HttpMethod.get, '/ping').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<PlainClient>().ping();
        expect('${server.lastRequest.url}', 'http://plain.test/ping');
      });
    });

    test("url: '' falls back to the url property", () async {
      server.when(HttpMethod.get, '/ping').respond(200, body: 'ok');
      await const ApplicationContextRunner()
          .withUserConfiguration(propertyUrlModule)
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
          .withBean<HttpTransport>(() => server)
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.fromProperty.url='
                'https://api.test',
          ])
          .runAsync((context) async {
            await context.getBean<PropertyUrlClient>().ping();
            expect('${server.lastRequest.url}', 'https://api.test/ping');
          });
    });

    test('a static query in the mapping path is kept as written', () async {
      server.when(HttpMethod.get, '/items').respond(200, body: 'ok');
      await runner
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.plain.'
                'default-query-parameters.lang=en,de',
          ])
          .runAsync((context) async {
            await context.getBean<PlainClient>().items(2);
            expect(
              '${server.lastRequest.url}',
              'http://plain.test/items?type=a%20b&flag&page=2&lang=en&lang=de',
            );
          });
    });
  });

  test('default-request-headers: comma lists and YAML lists are several '
      'values', () async {
    server.when(HttpMethod.get, '/ping').respond(200, body: 'ok');
    await runner
        .withPropertyValues([
          'spring.cloud.openfeign.client.config.plain.'
              'default-request-headers.X-Tags=a,b',
          'spring.cloud.openfeign.client.config.plain.'
              'default-request-headers.X-List[0]=one',
          'spring.cloud.openfeign.client.config.plain.'
              'default-request-headers.X-List[1]=two',
          'spring.cloud.openfeign.client.config.default.'
              'default-query-parameters.q[0]=x',
        ])
        .runAsync((context) async {
          await context.getBean<PlainClient>().ping();
          final request = server.lastRequest;
          expect(request.headers.getAll('X-Tags'), ['a', 'b']);
          expect(request.headers.getAll('X-List'), ['one', 'two']);
          expect(request.headers.contains('X-List.0'), isFalse);
          expect(request.url.queryParametersAll['q'], ['x']);
          final config = FeignClientConfig.of(
            context.getBean<Environment>(),
            'plain',
          );
          expect(config.defaultRequestHeaders, {
            'X-Tags': ['a', 'b'],
            'X-List': ['one', 'two'],
          });
        });
  });

  group('DefaultRetryer', () {
    final error = RetryableException(-1, 'reset');

    test('waits 150 ms first, × 1.5 after, like Feign', () {
      const retryer = DefaultRetryer();
      expect(retryer.nextDelay(1, error), const Duration(milliseconds: 150));
      expect(retryer.nextDelay(2, error), const Duration(milliseconds: 225));
      expect(retryer.nextDelay(3, error), const Duration(microseconds: 337500));
      expect(retryer.nextDelay(5, error), isNull); // 5 attempts in total
      expect(
        const DefaultRetryer(maxAttempts: 20).nextDelay(10, error),
        const Duration(seconds: 1),
      );
    });
  });

  test('BasicAuthRequestInterceptor takes another charset', () {
    final template = RequestTemplate(
      method: HttpMethod.get,
      url: Uri.parse('http://a.test'),
      methodKey: 'A#b()',
      clientName: 'a',
    );
    BasicAuthRequestInterceptor('名前', 'pw', encoding: utf8).apply(template);
    expect(
      template.headers[HttpHeaders.authorizationHeader],
      'Basic ${base64Encode(utf8.encode('名前:pw'))}',
    );
    expect(() => BasicAuthRequestInterceptor('名前', 'pw'), throwsArgumentError);
  });

  group('on/off properties bind like Boot booleans', () {
    FeignClientConfig config(Map<String, Object> properties) =>
        FeignClientConfig.of(
          StandardEnvironment(systemEnvironment: const {})
            ..propertySources.addFirst(MapPropertySource('p', properties)),
          'plain',
        );
    const prefix = 'spring.cloud.openfeign.client.config.';

    test('on / yes / 1 and off / no / 0 in any case', () {
      final on = config({
        '${prefix}plain.dismiss404': 'ON',
        '${prefix}default.follow-redirects': 'no',
        'spring.cloud.openfeign.client.decode-slash': '0',
        '${prefix}plain.event-stream.reconnect': 'off',
      });
      expect(on.dismiss404, isTrue);
      expect(on.followRedirects, isFalse);
      expect(on.decodeSlash, isFalse);
      expect(on.eventStreamReconnect, isFalse);
      final yes = config({
        '${prefix}default.dismiss404': 'yes',
        '${prefix}plain.follow-redirects': '1',
        'spring.cloud.openfeign.client.decode-slash': 'True',
      });
      expect(yes.dismiss404, isTrue);
      expect(yes.followRedirects, isTrue);
      expect(yes.decodeSlash, isTrue);
      final defaults = config({});
      expect(defaults.dismiss404, isFalse);
      expect(defaults.followRedirects, isTrue);
      expect(defaults.decodeSlash, isTrue);
      expect(defaults.eventStreamReconnect, isTrue);
    });

    test('anything else fails naming the key', () {
      for (final (key, value) in [
        ('${prefix}plain.dismiss404', 'sure'),
        ('${prefix}default.follow-redirects', 'nope'),
        ('spring.cloud.openfeign.client.decode-slash', 'maybe'),
        ('${prefix}plain.event-stream.reconnect', '2'),
      ]) {
        expect(
          () => config({key: value}),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(key),
            ),
          ),
          reason: key,
        );
      }
    });
  });
}
