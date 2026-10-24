import 'dart:async';

import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'chat.dart';

void main() {
  late MockWebSocketTransport sockets;
  late ApplicationContextRunner runner;

  setUp(() {
    sockets = MockWebSocketTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withPropertyValues([
          'chat.url=ws://chat.test/ws',
          'spring.websocket.client.config.chat.reconnect.delay=5ms',
          'spring.websocket.client.config.chat.reconnect.max-delay=20ms',
        ])
        .withBean<WebSocketTransport>(() => sockets);
  });

  test('a server that accepts and closes at once still reaches '
      'max-retries', () async {
    await runner
        .withPropertyValues([
          'spring.websocket.client.config.chat.reconnect.max-retries=2',
          // Longer than the test: only a message makes it stable.
          'spring.websocket.client.config.chat.reconnect.max-delay=10s',
        ])
        .runAsync((context) async {
          final errors = <Object>[];
          final done = Completer<void>();
          context.getBean<ChatSocket>().raw().listen(
            null,
            onError: errors.add,
            onDone: done.complete,
          );
          var accepted = 0;
          while (!done.isCompleted) {
            final server = await Future.any([
              sockets.nextConnection,
              done.future.then((_) => null),
            ]);
            if (server == null) {
              break;
            }
            accepted++;
            await server.closeFromServer(CloseStatus.serviceRestarted);
          }
          expect(accepted, 3); // the first connection and two retries
          expect(errors.single, isA<WebSocketException>());
        });
  });

  test('a message resets the retry count', () async {
    await runner
        .withPropertyValues([
          'spring.websocket.client.config.chat.reconnect.max-retries=1',
          'spring.websocket.client.config.chat.reconnect.max-delay=10s',
        ])
        .runAsync((context) async {
          final received = <String>[];
          context.getBean<ChatSocket>().raw().listen(received.add);
          for (var i = 0; i < 3; i++) {
            final server = await sockets.nextConnection;
            server.push('hi $i');
            await Future<void>.delayed(Duration.zero);
            await server.closeFromServer(CloseStatus.goingAway);
          }
          expect(await sockets.nextConnection, isNotNull);
          expect(received, ['hi 0', 'hi 1', 'hi 2']);
        });
  });

  test('a send fails with the next failed attempt, while listeners keep '
      'reconnecting (no max-retries)', () async {
    await runner.runAsync((context) async {
      final chat = context.getBean<ChatSocket>();
      for (var i = 0; i < 4; i++) {
        sockets.failNextConnect(WebSocketException('refused $i'));
      }
      chat.raw().listen(null, onError: (_) {});
      await expectLater(
        chat.sendText('x').timeout(const Duration(seconds: 5)),
        throwsA(isA<WebSocketException>()),
      );
      await expectLater(
        chat.connect().timeout(const Duration(seconds: 5)),
        throwsA(isA<WebSocketException>()),
      );
      // The listener's client connects in the end.
      final server = await sockets.nextConnection;
      await chat.sendText('y');
      await Future<void>.delayed(Duration.zero);
      expect(server.sent, ['y']);
    });
  });

  test('closeAsync waits until the connections are closed', () async {
    late MockWebSocket server;
    await runner.runAsync((context) async {
      await context.getBean<ChatSocket>().connect();
      server = sockets.lastConnection;
    });
    expect(server.isClosed, isTrue);
  });

  test("a client's header replaces default's in any case", () async {
    await runner
        .withPropertyValues([
          'spring.websocket.client.config.default.default-request-headers.X-Shop=neon',
          'spring.websocket.client.config.chat.default-request-headers.x-shop=books',
        ])
        .runAsync((context) async {
          await context.getBean<ChatSocket>().connect();
          expect(sockets.lastConnection.headers.getAll('X-Shop'), ['books']);
        });
  });

  test('reconnect.enabled: true / false in any case, others fail', () async {
    WebSocketClientConfig config(String value) => WebSocketClientConfig.of(
      StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(
          MapPropertySource('p', {
            'spring.websocket.client.config.chat.reconnect.enabled': value,
          }),
        ),
      'chat',
    );
    expect(config('FALSE').reconnect.enabled, isFalse);
    expect(config('Off').reconnect.enabled, isFalse);
    expect(config('TRUE').reconnect.enabled, isTrue);
    expect(() => config('nope'), throwsFormatException);
    runner
        .withPropertyValues([
          'spring.websocket.client.config.chat.reconnect.enabled=nope',
        ])
        .run((context) {
          expect(context, hasFailed());
          expect(
            '${context.startupFailure}',
            contains('chat.reconnect.enabled'),
          );
        });
  });

  test('after giving up, the next listener gets every retry again', () async {
    await runner
        .withPropertyValues([
          'spring.websocket.client.config.chat.reconnect.max-retries=1',
          'spring.websocket.client.config.chat.reconnect.max-delay=10s',
        ])
        .runAsync((context) async {
          final chat = context.getBean<ChatSocket>();
          final done = Completer<void>();
          chat.raw().listen(null, onError: (_) {}, onDone: done.complete);
          // Accepted and closed at once, twice: max-retries reached.
          await (await sockets.nextConnection).closeFromServer(
            CloseStatus.serviceRestarted,
          );
          await (await sockets.nextConnection).closeFromServer(
            CloseStatus.serviceRestarted,
          );
          await done.future;
          // A new listener: the first attempt fails, one retry is left.
          sockets.failNextConnect();
          final errors = <Object>[];
          chat.raw().listen(null, onError: errors.add);
          final server = await sockets.nextConnection.timeout(
            const Duration(seconds: 2),
          );
          expect(server.isClosed, isFalse);
          expect(errors, isEmpty);
        });
  });

  test('no reconnect once every listener cancelled', () async {
    await runner.runAsync((context) async {
      final subscription = context.getBean<ChatSocket>().raw().listen(null);
      final server = await sockets.nextConnection;
      await server.drop(); // a retry is scheduled (5 ms)
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sockets.connections, hasLength(1));
      // A new listener connects again.
      context.getBean<ChatSocket>().raw().listen(null);
      expect(await sockets.nextConnection, isNotNull);
    });
  });

  group('reconnect settings are checked like RetryPolicy.Builder', () {
    WebSocketClientConfig config(Map<String, String> reconnect) =>
        WebSocketClientConfig.of(
          StandardEnvironment(systemEnvironment: const {})
            ..propertySources.addFirst(
              MapPropertySource('p', {
                for (final MapEntry(:key, :value) in reconnect.entries)
                  'spring.websocket.client.config.chat.reconnect.$key': value,
              }),
            ),
          'chat',
        );

    test('invalid values fail naming the property', () {
      for (final (key, value) in [
        ('multiplier', '0.5'),
        ('delay', '-1s'),
        ('jitter', '-5ms'),
        ('max-retries', '-1'),
        ('max-delay', '0s'),
      ]) {
        expect(
          () => config({key: value}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.name,
              'name',
              'spring.websocket.client.config.chat.reconnect.$key',
            ),
          ),
          reason: key,
        );
      }
    });

    test('a delay above max-delay starts, waiting max-delay', () {
      final policy = config({'delay': '1m'}).reconnect;
      expect(policy.delay, const Duration(minutes: 1));
      expect(policy.delayFor(1), const Duration(seconds: 30));
      expect(policy.delayFor(3), const Duration(seconds: 30));
      final jittered = config({'delay': '1m', 'jitter': '5s'}).reconnect;
      expect(jittered.delayFor(2), const Duration(seconds: 30));
    });

    test('errors show durations readably', () {
      for (final (key, value, shown) in [
        ('delay', '-1500ms', '-1500ms'),
        ('jitter', '-5s', '-5s'),
        ('max-delay', '0s', '0s'),
        ('max-delay', '-2m', '-2m'),
      ]) {
        expect(
          () => config({key: value}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              allOf(contains(shown), isNot(contains('Instance of'))),
            ),
          ),
          reason: key,
        );
      }
    });

    test('limits are accepted', () {
      final policy = config({
        'multiplier': '1',
        'delay': '0s',
        'max-retries': '0',
      }).reconnect;
      expect(policy.multiplier, 1);
      expect(policy.delay, Duration.zero);
      expect(policy.maxRetries, 0);
    });

    test('an invalid setting fails the start', () {
      runner
          .withPropertyValues([
            'spring.websocket.client.config.chat.reconnect.multiplier=0.5',
          ])
          .run((context) {
            expect(context, hasFailed());
            expect(
              '${context.startupFailure}',
              contains('chat.reconnect.multiplier'),
            );
          });
    });
  });
}
