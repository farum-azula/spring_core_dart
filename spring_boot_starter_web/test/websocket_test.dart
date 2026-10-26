// WebSocket endpoints (spring_boot_starter_websocket) on this server: over
// real sockets, and in memory through MockMvc.
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/io.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('over real sockets', () {
    final app = springBootTest(
      testApplication,
      webEnvironment: WebEnvironment.randomPort,
      properties: {'logging.level.root': 'warn', 'server.address': '127.0.0.1'},
    );

    test(
      'the handshake goes through the dispatcher, messages both ways',
      () async {
        final session = await IoWebSocketTransport().connect(
          Uri.parse('ws://127.0.0.1:${app.localServerPort}/ws/echo/ann'),
        );
        final replies = StreamIterator(session.messages);
        session.sendMessage('hello');
        expect(await replies.moveNext(), isTrue);
        expect(jsonDecode(replies.current as String), {'text': 'ann: HELLO'});
        await session.close();
      },
    );

    test('filters run for the handshake too', () async {
      final client = Client(app.localServerPort);
      try {
        final reply = await client.get('/ws/echo/ann');
        expect(reply.status, 400); // not an upgrade
        expect(reply.headers.value('X-Trace'), 'on');
      } finally {
        client.close();
      }
    });
  });

  group('in memory', () {
    final app = springBootTest(
      testApplication,
      properties: {'logging.level.root': 'warn'},
    );

    test('MockMvc.webSocket opens the endpoint', () async {
      final session = await app.mockMvc.webSocket('/ws/echo/bob');
      final replies = StreamIterator(session.messages);
      session.sendMessage('hey');
      expect(await replies.moveNext(), isTrue);
      expect(jsonDecode(replies.current as String), {'text': 'bob: HEY'});
      await session.close();
    });
  });
}
