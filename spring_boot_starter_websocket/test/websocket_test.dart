import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

import 'chat.dart';

// The properties of the client sockets, for the lines that would not fit.
const _clientConfig = 'spring.websocket.client.config';

final class TokenInterceptor implements WebSocketHandshakeInterceptor {
  int calls = 0;

  @override
  Future<void> apply(WebSocketHandshake handshake) async {
    calls++;
    handshake
      ..queryParameter('token', 't$calls')
      ..headers.set('X-Client', handshake.clientName);
  }
}

/// A `Random` whose `nextDouble` is always [value].
final class FixedRandom implements math.Random {
  FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => (value * max).floor();

  @override
  bool nextBool() => value >= 0.5;
}

Future<void> pump([int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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
          'spring.websocket.client.config.chat.reconnect.delay=10ms',
          'spring.websocket.client.config.chat.reconnect.max-delay=40ms',
        ])
        .withBean<WebSocketTransport>(() => sockets);
  });

  test(
    'typed messages: JSON into a class, text and binary as they are',
    () async {
      await runner.runAsync((context) async {
        final chat = context.getBean<ChatSocket>();
        final messages = <ChatMessage>[];
        final errors = <Object>[];
        final raw = <String>[];
        final binary = <Uint8List>[];
        chat.messages().listen(messages.add, onError: errors.add);
        chat.raw().listen(raw.add);
        chat.binary().listen(binary.add);
        final server = await sockets.nextConnection;
        expect('${server.uri}', 'ws://chat.test/ws');
        expect(server.protocols, ['chat.v1']);
        expect(sockets.connections, hasLength(1), reason: 'one shared socket');
        server
          ..pushJson({'from': 'ann', 'text': 'hi'})
          ..push('not json')
          ..push([1, 2, 3])
          ..pushJson({'from': 'bob', 'text': 'yo'});
        await pump();
        expect(messages, isA<List<ChatMessage>>());
        expect(
          [for (final m in messages) '${m.from}: ${m.text}'],
          ['ann: hi', 'bob: yo'],
        );
        expect(errors.single, isA<MessageConversionException>());
        expect(
          (errors.single as MessageConversionException).message,
          'not json',
        );
        expect(raw, [
          '{"from":"ann","text":"hi"}',
          'not json',
          '{"from":"bob","text":"yo"}',
        ]);
        expect(binary.single, [1, 2, 3]);
        expect(chat.messages(), isA<Stream<ChatMessage>>());
      });
    },
  );

  test('sending JSON, text and bytes opens the connection lazily', () async {
    await runner.runAsync((context) async {
      final chat = context.getBean<ChatSocket>();
      await pump();
      expect(sockets.connections, isEmpty, reason: 'nothing used yet');
      await chat.send(const ChatMessage(from: 'me', text: 'hello'));
      await chat.sendText('plain');
      await chat.sendBytes(Uint8List.fromList([7, 8]));
      final server = sockets.lastConnection;
      expect(sockets.connections, hasLength(1));
      expect(jsonDecode(server.sent[0] as String), {
        'from': 'me',
        'text': 'hello',
      });
      expect(server.sent[1], 'plain');
      expect(server.sent[2], [7, 8]);
      expect(server.sent[2], isA<Uint8List>());
    });
  });

  test(
    'connect() opens at once; close() closes, the next use reopens',
    () async {
      await runner.runAsync((context) async {
        final chat = context.getBean<ChatSocket>();
        await chat.connect();
        final first = sockets.lastConnection;
        var done = false;
        chat.raw().listen(null, onDone: () => done = true);
        await pump();
        await chat.close();
        await pump();
        expect(first.isClosed, isTrue);
        expect(first.closedByClient, isTrue);
        expect(done, isTrue);
        await chat.sendText('again');
        expect(sockets.connections, hasLength(2));
        expect(sockets.lastConnection.sent, ['again']);
      });
    },
  );

  test(
    'a lost connection is opened again with backoff, listeners kept',
    () async {
      final logs = <String>[];
      final cancel = SpringLog.listen((record) => logs.add(record.message));
      final saved = SpringLog.level;
      SpringLog.level = SpringLogLevel.debug;
      addTearDown(() {
        cancel();
        SpringLog.level = saved;
      });
      await runner.runAsync((context) async {
        final chat = context.getBean<ChatSocket>();
        final texts = <String>[];
        var done = false;
        chat.raw().listen(texts.add, onDone: () => done = true);
        final first = await sockets.nextConnection;
        first.push('one');
        await pump();
        sockets
          ..failNextConnect()
          ..failNextConnect();
        await first.drop();
        final second = await sockets.nextConnection;
        second.push('two');
        await pump();
        expect(texts, ['one', 'two']);
        expect(done, isFalse);
        // A send during the outage waits for the connection.
        await second.drop();
        final sent = chat.sendText('queued');
        final third = await sockets.nextConnection;
        await sent;
        expect(third.sent, ['queued']);
      });
      expect(logs.where((l) => l.startsWith('reconnecting in')).take(3), [
        'reconnecting in 10 ms (attempt 1)',
        'reconnecting in 20 ms (attempt 2)',
        'reconnecting in 40 ms (attempt 3)',
      ]);
    },
  );

  group("reconnect policy, named like Spring 7's RetryPolicy", () {
    test('delay × multiplier per attempt, at most max-delay', () {
      const policy = WebSocketReconnectPolicy(
        delay: Duration(milliseconds: 100),
        multiplier: 1.5,
        maxDelay: Duration(milliseconds: 300),
      );
      expect(
        [for (var retry = 1; retry <= 4; retry++) policy.delayFor(retry)],
        const [
          Duration(milliseconds: 100),
          Duration(milliseconds: 150),
          Duration(milliseconds: 225),
          Duration(milliseconds: 300),
        ],
      );
      const fixed = WebSocketReconnectPolicy(multiplier: 1);
      expect(fixed.delayFor(5), const Duration(seconds: 1));
    });

    test('jitter: ± jitter scaled by the multiplier, within delay and '
        'max-delay', () {
      const policy = WebSocketReconnectPolicy(
        delay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 1),
        jitter: Duration(milliseconds: 10),
      );
      Duration at(int retry, double random) =>
          policy.delayFor(retry, FixedRandom(random));
      // Attempt 3: 400 ms ± 10 ms × 4.
      expect(at(3, 0), const Duration(milliseconds: 360));
      expect(at(3, 0.5), const Duration(milliseconds: 400));
      expect(at(3, 1), const Duration(milliseconds: 440));
      // Never below the delay, never above max-delay.
      expect(at(1, 0), const Duration(milliseconds: 100));
      expect(at(1, 1), const Duration(milliseconds: 110));
      expect(at(5, 1), const Duration(seconds: 1));
      final random = math.Random(7);
      for (var i = 0; i < 100; i++) {
        final delay = policy.delayFor(3, random);
        expect(delay.inMilliseconds, inInclusiveRange(360, 440));
      }
    });

    test('no overflow at high attempts, a zero delay keeps reconnecting', () {
      const policy = WebSocketReconnectPolicy(
        delay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 5),
      );
      for (final retry in [1074, 1075, 5000, 1 << 40]) {
        expect(policy.delayFor(retry), const Duration(seconds: 5));
      }
      const jittered = WebSocketReconnectPolicy(
        delay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 5),
        jitter: Duration(milliseconds: 10),
      );
      expect(jittered.delayFor(1074, FixedRandom(0)).inMilliseconds, 4500);
      expect(
        jittered.delayFor(1074, FixedRandom(1)),
        const Duration(seconds: 5),
      );
      const zero = WebSocketReconnectPolicy(delay: Duration.zero);
      for (final retry in [1, 2, 1073, 1074, 1075, 100000]) {
        expect(zero.delayFor(retry), Duration.zero);
      }
      const zeroJittered = WebSocketReconnectPolicy(
        delay: Duration.zero,
        jitter: Duration(milliseconds: 10),
      );
      for (final retry in [1, 1074, 100000]) {
        expect(zeroJittered.delayFor(retry, FixedRandom(0)), Duration.zero);
        expect(
          zeroJittered.delayFor(retry, FixedRandom(1)),
          const Duration(milliseconds: 10),
        );
      }
    });

    test('read from reconnect.* properties', () {
      final config = WebSocketClientConfig.of(
        StandardEnvironment()
          ..propertySources.addFirst(
            const MapPropertySource('test', {
              'spring.websocket.client.config.default.reconnect.delay': '200ms',
              'spring.websocket.client.config.feed.reconnect.multiplier': '1.5',
              'spring.websocket.client.config.feed.reconnect.max-delay': '5s',
              'spring.websocket.client.config.feed.reconnect.jitter': '50ms',
              'spring.websocket.client.config.feed.reconnect.max-retries': '4',
              'spring.websocket.client.config.feed.reconnect.enabled': 'false',
            }),
          ),
        'feed',
      );
      final policy = config.reconnect;
      expect(policy.delay, const Duration(milliseconds: 200));
      expect(policy.multiplier, 1.5);
      expect(policy.maxDelay, const Duration(seconds: 5));
      expect(policy.jitter, const Duration(milliseconds: 50));
      expect(policy.maxRetries, 4);
      expect(policy.enabled, isFalse);
      const defaults = WebSocketReconnectPolicy();
      expect(defaults.delay, const Duration(seconds: 1));
      expect(defaults.multiplier, 2);
      expect(defaults.maxDelay, const Duration(seconds: 30));
      expect(defaults.jitter, Duration.zero);
      expect(defaults.maxRetries, isNull);
    });

    test('the client waits as the policy says', () async {
      final logs = <String>[];
      final cancel = SpringLog.listen((record) => logs.add(record.message));
      final saved = SpringLog.level;
      SpringLog.level = SpringLogLevel.debug;
      addTearDown(() {
        cancel();
        SpringLog.level = saved;
      });
      await runner
          .withPropertyValues([
            'spring.websocket.client.config.chat.reconnect.multiplier=3',
            'spring.websocket.client.config.chat.reconnect.max-delay=100ms',
            'spring.websocket.client.config.chat.reconnect.jitter=2ms',
          ])
          .runAsync((context) async {
            final chat = context.getBean<ChatSocket>();
            chat.raw().listen(null);
            final first = await sockets.nextConnection;
            sockets
              ..failNextConnect()
              ..failNextConnect();
            await first.drop();
            await sockets.nextConnection;
          });
      final delays = [
        for (final line in logs)
          if (RegExp(r'^reconnecting in (\d+) ms').firstMatch(line)
              case final match?)
            int.parse(match[1]!),
      ];
      expect(delays, hasLength(3));
      // 10 ms, 30 ms, 90 ms, each ± 2 ms × (delay / 10 ms).
      expect(delays[0], inInclusiveRange(10, 12));
      expect(delays[1], inInclusiveRange(24, 36));
      expect(delays[2], inInclusiveRange(72, 100));
    });

    test('a zero delay keeps reconnecting', () async {
      await runner
          .withPropertyValues([
            'spring.websocket.client.config.chat.reconnect.delay=0ms',
          ])
          .runAsync((context) async {
            final chat = context.getBean<ChatSocket>();
            chat.raw().listen(null);
            final first = await sockets.nextConnection;
            for (var i = 0; i < 20; i++) {
              sockets.failNextConnect();
            }
            await first.drop();
            final next = await sockets.nextConnection;
            await next.drop();
            await sockets.nextConnection;
          });
    });
  });

  test(
    'a policy violation (1008) ends the streams without reconnecting',
    () async {
      await runner.runAsync((context) async {
        final chat = context.getBean<ChatSocket>();
        final errors = <Object>[];
        final done = Completer<void>();
        chat.raw().listen(null, onError: errors.add, onDone: done.complete);
        final server = await sockets.nextConnection;
        await server.closeFromServer(
          CloseStatus.policyViolation.withReason('no token'),
        );
        await done.future;
        expect(errors.single, isA<WebSocketException>());
        expect('${errors.single}', contains('1008: no token'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(sockets.connections, hasLength(1));
      });
    },
  );

  test('a normal close (1000) ends the streams quietly', () async {
    await runner.runAsync((context) async {
      final chat = context.getBean<ChatSocket>();
      final errors = <Object>[];
      final done = Completer<void>();
      chat.raw().listen(null, onError: errors.add, onDone: done.complete);
      await (await sockets.nextConnection).closeFromServer();
      await done.future;
      expect(errors, isEmpty);
    });
  });

  test('reconnect.enabled=false: a lost connection ends the streams with an '
      'error', () async {
    await runner
        .withPropertyValues([
          'spring.websocket.client.config.chat.reconnect.enabled=false',
        ])
        .runAsync((context) async {
          final chat = context.getBean<ChatSocket>();
          final errors = <Object>[];
          final done = Completer<void>();
          chat.raw().listen(null, onError: errors.add, onDone: done.complete);
          await (await sockets.nextConnection).drop();
          await done.future;
          expect('${errors.single}', contains('1006'));
        });
  });

  test('max-retries gives up and reports the connection error', () async {
    await runner
        .withPropertyValues([
          // The first attempt and one retry.
          'spring.websocket.client.config.chat.reconnect.max-retries=1',
        ])
        .runAsync((context) async {
          final chat = context.getBean<ChatSocket>();
          sockets
            ..failNextConnect()
            ..failNextConnect();
          final errors = <Object>[];
          final done = Completer<void>();
          chat.raw().listen(null, onError: errors.add, onDone: done.complete);
          await done.future;
          expect(errors.single, isA<WebSocketException>());
          expect(sockets.connections, isEmpty);
        });
  });

  test('without listeners a failed connection fails the send', () async {
    await runner.runAsync((context) async {
      sockets.failNextConnect(WebSocketException('refused'));
      await expectLater(
        context.getBean<ChatSocket>().sendText('x'),
        throwsA(isA<WebSocketException>()),
      );
    });
  });

  test('interceptors and default headers apply to every handshake', () async {
    final interceptor = TokenInterceptor();
    await runner
        .withBean<WebSocketHandshakeInterceptor>(() => interceptor)
        .withPropertyValues([
          '$_clientConfig.default.default-request-headers.X-Shop=neon',
        ])
        .runAsync((context) async {
          final chat = context.getBean<ChatSocket>();
          chat.raw().listen(null);
          final first = await sockets.nextConnection;
          expect(first.uri.queryParameters['token'], 't1');
          expect(first.headers['X-Client'], 'chat');
          expect(first.headers['X-Shop'], 'neon');
          await first.drop();
          final second = await sockets.nextConnection;
          expect(second.uri.queryParameters['token'], 't2');
        });
  });

  test('closing the context closes the connection', () async {
    late MockWebSocket server;
    await runner.runAsync((context) async {
      final chat = context.getBean<ChatSocket>();
      await chat.connect();
      server = sockets.lastConnection;
    });
    await pump();
    expect(server.isClosed, isTrue);
    expect(server.closeStatus, CloseStatus.normal);
  });

  test('an invalid client stops the application with the reasons', () {
    const ApplicationContextRunner()
        .withUserConfiguration(brokenModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withBean<WebSocketTransport>(() => MockWebSocketTransport())
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid WebSocket client BrokenSocket'));
          expect(failure, contains('must start with ws:// or wss://'));
          expect(
            failure,
            contains('BrokenSocket.notAStream: an @OnMessage method'),
          );
          expect(failure, contains('BrokenSocket.two: a @SendMessage method'));
          expect(failure, contains('BrokenSocket.other: mark it @OnMessage'));
        });
  });

  test('a client without a URL is reported', () {
    const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withBean<WebSocketTransport>(() => MockWebSocketTransport())
        .run((context) {
          expect('${context.startupFailure}', contains('chat.url'));
        });
  });

  test('the configured url is used when the annotation has none', () {
    final config = WebSocketClientConfig.of(
      StandardEnvironment()
        ..propertySources.addFirst(
          const MapPropertySource('test', {
            'spring.websocket.client.config.default.connect-timeout': '2s',
            'spring.websocket.client.config.feed.url': 'wss://feed.test',
            'spring.websocket.client.config.feed.reconnect.max-retries': '3',
          }),
        ),
      'feed',
    );
    expect(config.url, 'wss://feed.test');
    expect(config.connectTimeout, const Duration(seconds: 2));
    expect(config.reconnect.maxRetries, 3);
    expect(config.reconnect.enabled, isTrue);
    expect(jsonEncode(config.defaultRequestHeaders), '{}');
  });
}
