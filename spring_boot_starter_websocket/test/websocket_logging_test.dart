// The server's log lines: the handshake, the session, the size of the
// messages; never what a message or a handshake header says.
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

import 'server/app.dart';

void main() {
  final runner = const ApplicationContextRunner()
      .withUserConfiguration(wsServerBeans)
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration);

  late List<SpringLogRecord> records;
  late void Function() stop;
  late SpringLogLevel before;

  setUp(() {
    records = [];
    stop = SpringLog.listen(records.add);
    before = SpringLog.level;
  });
  tearDown(() {
    stop();
    SpringLog.level = before;
  });

  Future<MockServerHttpResponse> connect(
    WebSocketHandlerMapping mapping,
    Map<String, String> headers, {
    void Function(WebSocketSession client)? onOpen,
  }) async {
    final request = MockServerHttpRequest(HttpMethod.get, '/ws/rooms/a')
      ..headers.set('Upgrade', 'websocket')
      ..headers.set('Connection', 'Upgrade');
    headers.forEach(request.headers.set);
    final response = MockServerHttpResponse();
    await mapping.getHandler(request)!.handle(request, response);
    final client = await request.webSocketClient
        .then<WebSocketSession?>((c) => c)
        .timeout(const Duration(milliseconds: 50), onTimeout: () => null);
    if (client != null) {
      onOpen?.call(client);
    }
    return response;
  }

  Future<void> scenario(SpringLogLevel level) => runner.runAsync((
    context,
  ) async {
    SpringLog.level = level;
    final mapping = context.context.getBean<WebSocketHandlerMapping>();
    await connect(mapping, {'Origin': 'https://evil\r\n.example'});
    late WebSocketSession client;
    await connect(
      mapping,
      {
        'Origin': 'https://chat.example',
        'Authorization': 'Bearer ws-token-123',
        'Cookie': 'JSESSIONID=ws-session-456',
      },
      onOpen: (c) => client = c,
    );
    client.sendMessage(jsonEncode({'user': 'ann', 'text': 'message-secret'}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await client.close(CloseStatus.goingAway);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  Iterable<SpringLogRecord> ws() =>
      records.where((r) => r.loggerName.startsWith('spring.websocket'));

  test('at debug: handshake refused and accepted, opened, closed', () async {
    await scenario(SpringLogLevel.debug);
    final messages = ws().map((r) => r.message).toList();
    expect(
      messages,
      contains(
        allOf(
          startsWith('Handshake from origin "https://evil<EOL><EOL>.example"'),
          contains('refused for /ws/rooms/{room}'),
        ),
      ),
    );
    expect(messages, contains('Handshake accepted for /ws/rooms/{room}'));
    expect(
      messages,
      contains(
        allOf(
          startsWith('Opened WebSocket session'),
          endsWith('/ws/rooms/{room}'),
        ),
      ),
    );
    expect(
      messages,
      contains(
        allOf(
          startsWith('Closed WebSocket session'),
          endsWith('with code 1001'),
        ),
      ),
    );
    expect(ws().every((r) => r.level == SpringLogLevel.debug), isTrue);
  });

  test('at trace: sizes of the messages, never their text', () async {
    await scenario(SpringLogLevel.trace);
    final trace = ws().where((r) => r.level == SpringLogLevel.trace);
    expect(
      trace.map((r) => r.message),
      contains(matches(RegExp(r'^Received a text message of \d+ characters$'))),
    );
    final text = records.map((r) => r.message).join('\n');
    for (final secret in ['message-secret', 'ws-token-123', 'ws-session-456']) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });

  test('at info: none of these lines', () async {
    await scenario(SpringLogLevel.info);
    expect(ws(), isEmpty);
  });
}
