@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_web_dart/io.dart';
import 'package:test/test.dart';

import 'chat.dart';

// The properties of the client sockets, for the lines that would not fit.
const _clientConfig = 'spring.websocket.client.config';

// End to end through dart:io: a real WebSocket server echoes chat
// messages and drops the first connection to show the reconnection.
void main() {
  late io.HttpServer server;
  final handshakes = <io.HttpHeaders>[];
  final sockets = <io.WebSocket>[];

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        handshakes.add(request.headers);
        final socket = await io.WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) => protocols.first,
        );
        sockets.add(socket);
        socket.listen((message) {
          final json = jsonDecode(message as String) as Map<String, Object?>;
          socket.add(jsonEncode({'from': 'echo', 'text': json['text']}));
        });
      });
  });

  tearDownAll(() => server.close(force: true));

  test('IoWebSocketTransport: send, receive, reconnect', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withPropertyValues([
          'chat.url=ws://127.0.0.1:${server.port}/ws',
          'spring.websocket.client.config.chat.reconnect-delay=10ms',
          '$_clientConfig.chat.default-request-headers.X-Shop=neon',
        ])
        .withBean<WebSocketTransport>(() => IoWebSocketTransport())
        .runAsync((context) async {
          final chat = context.getBean<ChatSocket>();
          final replies = StreamController<ChatMessage>();
          chat.messages().listen(replies.add);
          final incoming = StreamIterator(replies.stream);

          await chat.send(const ChatMessage(from: 'me', text: 'one'));
          expect(await incoming.moveNext(), isTrue);
          expect(incoming.current.from, 'echo');
          expect(incoming.current.text, 'one');
          expect(handshakes.single.value('X-Shop'), 'neon');
          expect(sockets.single.protocol, 'chat.v1');

          // The server goes away: the client connects again by itself.
          await sockets.single.close(io.WebSocketStatus.goingAway);
          while (sockets.length < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          await chat.send(const ChatMessage(from: 'me', text: 'two'));
          expect(await incoming.moveNext(), isTrue);
          expect(incoming.current.text, 'two');
          await incoming.cancel();
        });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sockets.last.closeCode, io.WebSocketStatus.normalClosure);
  }, timeout: const Timeout(Duration(seconds: 30)));

  // A @WebSocketClient whose sends back up on a server that reads
  // nothing: when the connection ends ([resetFirst]: the server resets
  // it; otherwise the client drops it past [sendTimeLimit]), the client
  // connects again.
  Future<void> reconnectsAfter({
    required bool resetFirst,
    required Duration sendTimeLimit,
  }) async {
    final connections = <io.Socket>[];
    final server = await _stuckServer(
      connections,
      resetFirstAfter: resetFirst ? const Duration(milliseconds: 500) : null,
    );
    try {
      await const ApplicationContextRunner()
          .withUserConfiguration(appModule)
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
          .withPropertyValues([
            'chat.url=ws://127.0.0.1:${server.port}/ws',
            '$_clientConfig.chat.reconnect.delay=10ms',
          ])
          .withBean<WebSocketTransport>(
            () => IoWebSocketTransport(
              sendBufferSizeLimit: 256 << 20,
              sendTimeLimit: sendTimeLimit,
            ),
          )
          .runAsync((context) async {
            final chat = context.getBean<ChatSocket>();
            final listening = chat.raw().listen(null, onError: (Object _) {});
            await chat.connect();
            // More than the kernel's buffers: most of it waits to be sent.
            await chat.sendBytes(Uint8List(32 << 20));
            final watch = Stopwatch()..start();
            while (connections.length < 2) {
              if (watch.elapsed > const Duration(seconds: 10)) {
                fail('no new connection');
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            await listening.cancel();
          });
    } finally {
      for (final socket in connections) {
        socket.destroy();
      }
      await server.close();
    }
  }

  test('a server that resets while the client waits to send: the session '
      'ends (1006) and the client connects again', () async {
    await reconnectsAfter(
      resetFirst: true,
      sendTimeLimit: const Duration(minutes: 1),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a server that takes nothing: the client drops the connection '
      '(4500) and connects again', () async {
    await reconnectsAfter(
      resetFirst: false,
      sendTimeLimit: const Duration(milliseconds: 300),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('spring.websocket.client.max-text-message-size and '
      'max-binary-message-size set the default transport', () async {
    final runner = const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withPropertyValues(['chat.url=ws://127.0.0.1:1/ws']);
    await runner.runAsync((context) async {
      final transport =
          context.getBean<WebSocketTransport>() as IoWebSocketTransport;
      expect(transport.maxTextMessageSize, 8192); // Tomcat's default
      expect(transport.maxBinaryMessageSize, 8192);
    });
    await runner
        .withPropertyValues([
          'spring.websocket.client.max-text-message-size=1MB',
          'spring.websocket.client.max-binary-message-size=-1',
        ])
        .runAsync((context) async {
          final transport =
              context.getBean<WebSocketTransport>() as IoWebSocketTransport;
          expect(transport.maxTextMessageSize, 1024 * 1024);
          expect(transport.maxBinaryMessageSize, -1);
        });
  });
}

/// A server that accepts each handshake, then reads nothing; it resets
/// the first connection after [resetFirstAfter] (with the client's data
/// unread), if given. Each connection is added to [connections].
Future<io.ServerSocket> _stuckServer(
  List<io.Socket> connections, {
  Duration? resetFirstAfter,
}) async {
  final server = await io.ServerSocket.bind(
    io.InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((socket) {
    socket.done.ignore();
    final head = StringBuffer();
    // Paused for good; the socket ends it.
    // ignore: cancel_subscriptions
    late final StreamSubscription<Uint8List> subscription;
    subscription = socket.listen((chunk) {
      head.write(latin1.decode(chunk));
      if (!head.toString().contains('\r\n\r\n')) {
        return;
      }
      subscription.pause();
      final key = RegExp(
        r'sec-websocket-key: *(\S+)',
        caseSensitive: false,
      ).firstMatch(head.toString())![1]!;
      socket.add(
        latin1.encode(
          'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Accept: ${webSocketAccept(key)}\r\n\r\n',
        ),
      );
      connections.add(socket);
      if (connections.length == 1 && resetFirstAfter != null) {
        Timer(resetFirstAfter, socket.destroy);
      }
    }, onError: (Object _) {});
  });
  return server;
}
