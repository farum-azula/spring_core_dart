// The server side in memory: handshakes through WebSocketHandlerMapping
// with spring_web_dart's mock requests (the web starter's dispatcher asks
// the same mapping; its tests run it over real sockets).
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

import 'server/app.dart';
import 'server/chat.dart';

final class _Handshake {
  _Handshake(this.response, this.client);

  final MockServerHttpResponse response;
  final WebSocketSession? client;
}

Future<_Handshake?> _connect(
  WebSocketHandlerMapping mapping,
  String target, {
  Map<String, String> headers = const {},
  bool upgrade = true,
}) async {
  final request = MockServerHttpRequest(HttpMethod.get, target);
  if (upgrade) {
    request.headers
      ..set('Upgrade', 'websocket')
      ..set('Connection', 'Upgrade');
  }
  headers.forEach(request.headers.set);
  final handler = mapping.getHandler(request);
  if (handler == null) {
    return null;
  }
  final response = MockServerHttpResponse();
  await handler.handle(request, response);
  final client = await request.webSocketClient
      .then<WebSocketSession?>((c) => c)
      .timeout(const Duration(milliseconds: 50), onTimeout: () => null);
  return _Handshake(response, client);
}

void main() {
  final runner = const ApplicationContextRunner()
      .withUserConfiguration(wsServerBeans)
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration);

  Future<void> withMapping(
    Future<void> Function(
      WebSocketHandlerMapping mapping,
      ApplicationContext context,
    )
    body,
  ) => runner.runAsync((context) async {
    expect(context.startupFailure, isNull);
    await body(
      context.context.getBean<WebSocketHandlerMapping>(),
      context.context,
    );
  });

  test(
    'maps the endpoint and the configurer\'s handler',
    () => withMapping((mapping, _) async {
      expect(mapping.paths, containsAll(['/ws/rooms/{room}', '/ws/echo']));
      expect(await _connect(mapping, '/ws/other'), isNull);
    }),
  );

  test(
    'an endpoint: path variables, JSON in and out, replies, close',
    () => withMapping((mapping, context) async {
      final handshake = await _connect(mapping, '/ws/rooms/neon');
      final client = handshake!.client!;
      final log = context.getBean<ChatLog>();
      final replies = StreamIterator(client.messages);
      client.sendMessage(jsonEncode({'user': 'ann', 'text': 'hi'}));
      // The broadcast to the room (this session too), then the reply.
      expect(await replies.moveNext(), isTrue);
      expect(jsonDecode(replies.current as String), {
        'user': 'ann',
        'text': 'hi',
      });
      expect(await replies.moveNext(), isTrue);
      expect(jsonDecode(replies.current as String), {
        'room': 'neon',
        'received': 'hi',
      });
      expect(log.opened, ['neon']);
      final registry = context.getBean<WebSocketSessionRegistry>();
      expect(registry.sessions('/ws/rooms/{room}'), hasLength(1));
      await client.close(CloseStatus.goingAway);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(log.closed, [1001]);
      expect(registry.sessions('/ws/rooms/{room}'), isEmpty);
    }),
  );

  test(
    '@OnError gets what a handler threw; the connection stays',
    () => withMapping((mapping, context) async {
      final client = (await _connect(mapping, '/ws/rooms/a'))!.client!;
      final replies = StreamIterator(client.messages);
      client.sendMessage(jsonEncode({'user': 'ann', 'text': 'fail'}));
      expect(await replies.moveNext(), isTrue);
      expect(replies.current, contains('failing on purpose'));
      client.sendMessage('not json');
      expect(await replies.moveNext(), isTrue);
      expect(replies.current, contains('cannot read the message'));
      expect(context.getBean<ChatLog>().errors, hasLength(2));
      expect(client.isOpen, isTrue);
      await client.close();
    }),
  );

  test(
    'origins: same origin and allowed ones pass, others are refused',
    () => withMapping((mapping, _) async {
      var handshake = await _connect(
        mapping,
        '/ws/rooms/a',
        headers: {'Origin': 'https://evil.example'},
      );
      expect(handshake!.client, isNull);
      expect(handshake.response.statusCode, 403);
      handshake = await _connect(
        mapping,
        '/ws/rooms/a',
        headers: {'Origin': 'https://chat.example'},
      );
      expect(handshake!.client, isNotNull);
      handshake = await _connect(
        mapping,
        '/ws/rooms/a',
        headers: {'Origin': 'http://localhost'},
      );
      expect(handshake!.client, isNotNull);
    }),
  );

  test(
    'not an upgrade: 400',
    () => withMapping((mapping, _) async {
      final handshake = await _connect(mapping, '/ws/echo', upgrade: false);
      expect(handshake!.response.statusCode, 400);
    }),
  );

  test(
    'a WebSocketConfigurer handler with a handshake interceptor',
    () => withMapping((mapping, _) async {
      final refused = await _connect(mapping, '/ws/echo');
      expect(refused!.client, isNull);
      expect(refused.response.statusCode, 403);
      final client = (await _connect(mapping, '/ws/echo?token=t1'))!.client!;
      final replies = StreamIterator(client.messages);
      client.sendMessage('ping');
      expect(await replies.moveNext(), isTrue);
      expect(replies.current, 'echo: ping (t1)');
      await client.close();
    }),
  );
}
