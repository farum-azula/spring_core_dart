@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_web_dart/io.dart';
import 'package:test/test.dart';

import 'chat.dart';

// End to end through dart:io: a real WebSocket server echoes chat
// messages and drops the first connection to show the reconnection.
void main() {
  late io.HttpServer server;
  final handshakes = <io.HttpHeaders>[];
  final sockets = <io.WebSocket>[];

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
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
          'spring.websocket.client.config.chat.default-request-headers.X-Shop=neon',
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
}
