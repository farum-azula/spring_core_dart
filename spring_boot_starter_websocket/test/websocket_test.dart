import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'chat.dart';

final class TokenInterceptor implements WebSocketHandshakeInterceptor {
  var calls = 0;

  @override
  Future<void> apply(WebSocketHandshake handshake) async {
    calls++;
    handshake
      ..queryParameter('token', 't$calls')
      ..headers.set('X-Client', handshake.clientName);
  }
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
          'spring.websocket.client.config.chat.reconnect-delay=10ms',
          'spring.websocket.client.config.chat.max-reconnect-delay=40ms',
        ])
        .withBean<WebSocketTransport>(sockets);
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
        expect('${server.url}', 'ws://chat.test/ws');
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
          WebSocketStatus.policyViolation,
          'no token',
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

  test(
    'reconnect=false: a lost connection ends the streams with an error',
    () async {
      await runner
          .withPropertyValues([
            'spring.websocket.client.config.chat.reconnect=false',
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
    },
  );

  test('max-attempts gives up and reports the connection error', () async {
    await runner
        .withPropertyValues([
          'spring.websocket.client.config.chat.max-attempts=2',
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
        .withBean<WebSocketHandshakeInterceptor>(interceptor)
        .withPropertyValues([
          'spring.websocket.client.config.default.default-request-headers.X-Shop=neon',
        ])
        .runAsync((context) async {
          final chat = context.getBean<ChatSocket>();
          chat.raw().listen(null);
          final first = await sockets.nextConnection;
          expect(first.url.queryParameters['token'], 't1');
          expect(first.headers['X-Client'], 'chat');
          expect(first.headers['X-Shop'], 'neon');
          await first.drop();
          final second = await sockets.nextConnection;
          expect(second.url.queryParameters['token'], 't2');
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
    expect(server.closeCode, WebSocketStatus.normalClosure);
  });

  test('an invalid client stops the application with the reasons', () {
    const ApplicationContextRunner()
        .withUserConfiguration(brokenModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withBean<WebSocketTransport>(MockWebSocketTransport())
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
        .withBean<WebSocketTransport>(MockWebSocketTransport())
        .run((context) {
          expect('${context.startupFailure}', contains('chat.url'));
        });
  });

  test('the configured url is used when the annotation has none', () {
    final config = WebSocketClientConfig.of(
      StandardEnvironment()
        ..propertySources.addFirst(
          MapPropertySource('test', {
            'spring.websocket.client.config.default.connect-timeout': '2s',
            'spring.websocket.client.config.feed.url': 'wss://feed.test',
            'spring.websocket.client.config.feed.max-attempts': '3',
          }),
        ),
      'feed',
    );
    expect(config.url, 'wss://feed.test');
    expect(config.connectTimeout, const Duration(seconds: 2));
    expect(config.maxAttempts, 3);
    expect(config.reconnect, isTrue);
    expect(jsonEncode(config.defaultRequestHeaders), '{}');
  });
}
