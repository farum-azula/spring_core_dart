// The property strings are lists of independent entries, each one a single
// string; a long key cannot be split in two (adjacent strings in a list).
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'orders.dart';

final class TokenInterceptor implements RequestInterceptor {
  int calls = 0;

  @override
  void apply(RequestTemplate template) =>
      template.header('Authorization', 'Bearer t-${++calls}');
}

void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(ordersModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withPropertyValues([
          'spring.cloud.openfeign.client.config.default.event-stream.reconnect-delay=10ms',
        ])
        .withBean<HttpTransport>(() => server);
  });

  test('typed events with await for, Accept and Cache-Control', () async {
    server
      ..when(HttpMethod.get, '/shops/neon/orders/events').respondEvents([
        const ServerSentEvent({'id': 1, 'status': 'NEW'}, id: '1'),
        const ServerSentEvent({'id': 2, 'status': 'PAID'}, id: '2'),
      ])
      ..when(HttpMethod.get, '/shops/neon/orders/events').respond(204);
    await runner.runAsync((context) async {
      final orders = context.getBean<OrdersClient>().events('neon');
      expect(orders, isA<EventStream<OrderEvent>>());
      final statuses = [await for (final order in orders) order.status];
      expect(statuses, ['NEW', 'PAID']);
      final request = server.requests.first;
      expect('${request.url}', 'http://orders.test/shops/neon/orders/events');
      expect(
        request.headers[HttpHeaders.acceptHeader],
        MediaType.textEventStream,
      );
      expect(request.headers['Cache-Control'], 'no-cache');
    });
  });

  test('.events gives id, event and retry', () async {
    server
      ..when(HttpMethod.get, '/shops/neon/orders/events').respondEvents([
        const ServerSentEvent(
          {'id': 1, 'status': 'NEW'},
          id: '7',
          event: 'order-created',
          retry: Duration(milliseconds: 5),
        ),
      ])
      ..when(HttpMethod.get, '/shops/neon/orders/events').respond(204);
    await runner.runAsync((context) async {
      final stream = context.getBean<OrdersClient>().events('neon');
      final events = await stream.events.toList();
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.id, '7');
      expect(event.event, 'order-created');
      expect(event.retry, const Duration(milliseconds: 5));
      expect(event.data.status, 'NEW');
      expect(stream.lastEventId, '7');
    });
  });

  test('Stream<T> return type with String data', () async {
    server
      ..when(HttpMethod.get, '/ticks').respondEvents([
        const ServerSentEvent('a'),
        const ServerSentEvent('b\nc'),
      ])
      ..when(HttpMethod.get, '/ticks').respond(204);
    await runner.runAsync((context) async {
      final ticks = context.getBean<OrdersClient>().ticks();
      expect(ticks, isA<EventStream<String>>());
      expect(await ticks.toList(), ['a', 'b\nc']);
    });
  });

  test('reconnects after the response ends, with Last-Event-ID and fresh '
      'interceptors', () async {
    final tokens = TokenInterceptor();
    server
      ..when(
        HttpMethod.get,
        '/ticks',
      ).respondEvents([const ServerSentEvent('one', id: '1')])
      ..when(
        HttpMethod.get,
        '/ticks',
      ).respondEvents([const ServerSentEvent('two', id: '2')])
      ..when(HttpMethod.get, '/ticks').respond(204);
    await runner.withBean<RequestInterceptor>(() => tokens).runAsync((
      context,
    ) async {
      final ticks = await context.getBean<OrdersClient>().ticks().toList();
      expect(ticks, ['one', 'two']);
      final requests = server.requests;
      expect(requests, hasLength(3));
      expect(requests[0].headers['Last-Event-ID'], isNull);
      expect(requests[1].headers['Last-Event-ID'], '1');
      expect(requests[2].headers['Last-Event-ID'], '2');
      expect(
        [for (final r in requests) r.headers['Authorization']],
        ['Bearer t-1', 'Bearer t-2', 'Bearer t-3'],
      );
    });
  });

  test(
    'connection errors reconnect; reconnect=false ends the stream',
    () async {
      server
        ..when(HttpMethod.get, '/ticks').fail(HttpTransportException('down'))
        ..when(
          HttpMethod.get,
          '/ticks',
        ).respondEvents([const ServerSentEvent('up')])
        ..when(HttpMethod.get, '/ticks').respond(204);
      await runner.runAsync((context) async {
        expect(await context.getBean<OrdersClient>().ticks().toList(), ['up']);
      });

      final once = MockHttpTransport()
        ..when(
          HttpMethod.get,
          '/ticks',
        ).respondEvents([const ServerSentEvent('only')]);
      await runner
          .withBeanOverride<HttpTransport>(once) // replaces `server`
          .withPropertyValues([
            'spring.cloud.openfeign.client.config.orders.event-stream.reconnect=false',
          ])
          .runAsync((context) async {
            expect(await context.getBean<OrdersClient>().ticks().toList(), [
              'only',
            ]);
            expect(once.requests, hasLength(1));
          });
    },
  );

  test('an error status ends the stream with a FeignException', () async {
    server.when(HttpMethod.get, '/ticks').respond(404, body: 'gone');
    await runner.runAsync((context) async {
      await expectLater(
        context.getBean<OrdersClient>().ticks().toList(),
        throwsA(
          isA<FeignNotFound>().having((e) => e.responseBody, 'body', 'gone'),
        ),
      );
      expect(server.requests, hasLength(1));
    });
  });

  test('a bad event is an error, the stream goes on', () async {
    server
      ..when(HttpMethod.get, '/shops/neon/orders/events').respondEvents([
        const ServerSentEvent('not json'),
        const ServerSentEvent({'id': 3, 'status': 'SHIPPED'}),
      ])
      ..when(HttpMethod.get, '/shops/neon/orders/events').respond(204);
    await runner.runAsync((context) async {
      final errors = <Object>[];
      final statuses = <String>[];
      final done = Completer<void>();
      context
          .getBean<OrdersClient>()
          .events('neon')
          .listen(
            (order) => statuses.add(order.status),
            onError: errors.add,
            onDone: done.complete,
          );
      await done.future;
      expect(statuses, ['SHIPPED']);
      expect(errors.single, isA<DecodeException>());
    });
  });

  test('cancelling closes the connection; nothing reconnects', () async {
    server.when(HttpMethod.get, '/ticks').respondEvents([
      const ServerSentEvent('first'),
    ], keepOpen: true);
    await runner.runAsync((context) async {
      final first = await context.getBean<OrdersClient>().ticks().first;
      expect(first, 'first');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.requests, hasLength(1));
    });
  });

  test(
    'the fallback stream takes over when the first connection fails',
    () async {
      server.when(HttpMethod.get, '/news').respond(500, body: 'boom');
      await runner.runAsync((context) async {
        expect(await context.getBean<NewsClient>().news().toList(), [
          'offline',
        ]);
      });
    },
  );

  test('a Future of a stream or a sync result stops the application', () {
    const ApplicationContextRunner()
        .withUserConfiguration(badStreamModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => MockHttpTransport())
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid Feign client BadStreamClient'));
          expect(failure, contains('return EventStream<T> directly'));
          expect(failure, contains('BadStreamClient.now must return a Future'));
        });
  });
}
