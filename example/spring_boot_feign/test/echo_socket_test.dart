// The WebSocket client against MockWebSocketTransport (the mock plays the
// server).
import 'package:spring_boot_feign_example/src/echo_socket.dart';
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner;
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'support/app.dart';

void main() {
  late MockWebSocketTransport sockets;

  setUp(() => sockets = MockWebSocketTransport());

  ApplicationContextRunner app() =>
      appContext().withBean<WebSocketTransport>(() => sockets);

  test('connects on first use to the URL of application.properties', () async {
    await app().runAsync((context) async {
      final socket = context.getBean<EchoSocket>();
      expect(sockets.connections, isEmpty); // nothing until it is used
      final server = sockets.nextConnection;
      final first = socket.messages().first;
      expect('${(await server).uri}', 'wss://ws.postman-echo.com/raw');
      (await server).pushJson({'from': 'ann', 'text': 'hi'});
      final message = await first;
      expect(message, isA<ChatMessage>());
      expect((message.from, message.text), ('ann', 'hi'));
    });
  });

  test('send writes JSON over the same connection', () async {
    await app().runAsync((context) async {
      final socket = context.getBean<EchoSocket>();
      await socket.send(const ChatMessage(from: 'dart', text: 'hello'));
      await socket.send(const ChatMessage(from: 'dart', text: 'spring'));
      expect(sockets.connections, hasLength(1));
      expect(sockets.lastConnection.sentJson, [
        {'from': 'dart', 'text': 'hello'},
        {'from': 'dart', 'text': 'spring'},
      ]);
    });
  });

  test('the connection is closed when the application stops', () async {
    await app().runAsync((context) async {
      await context.getBean<EchoSocket>().send(
        const ChatMessage(from: 'dart', text: 'bye'),
      );
    });
    expect(sockets.lastConnection.isClosed, isTrue);
    expect(sockets.lastConnection.closedByClient, isTrue);
  });
}
