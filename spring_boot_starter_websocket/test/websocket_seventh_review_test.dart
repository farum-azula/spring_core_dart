// Regression tests of the seventh review before 0.5.0: a session closed
// during afterConnectionEstablished crashed the process (the handler
// mapping listened to its messages only afterwards, and dart:io had
// drained them), and nothing thrown by the per-connection code may reach
// the server's zone.
import 'dart:async';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

void main() {
  late List<SpringLogRecord> records;
  late SpringLogHandler previous;

  setUp(() {
    records = [];
    previous = SpringLog.handler;
    SpringLog.handler = records.add;
  });

  tearDown(() => SpringLog.handler = previous);

  // Opens [session] through a mapping of [handler] at /ws.
  Future<WebSocketSessionRegistry> open(
    WebSocketHandler handler,
    WebSocketSession session,
  ) async {
    final registry = WebSocketSessionRegistry();
    final mapping = WebSocketHandlerMapping(
      beanFactory: DefaultListableBeanFactory(),
      mapper: ObjectMapper(),
      sessions: registry,
      configurers: [_Single(handler)],
    )..initialize();
    final request = _Upgrade(
      MockServerHttpRequest(HttpMethod.get, '/ws')
        ..headers.set('Upgrade', 'websocket')
        ..headers.set('Connection', 'Upgrade'),
      session,
    );
    await mapping
        .getHandler(request)!
        .handle(request, MockServerHttpResponse());
    return registry;
  }

  test('a session closed in afterConnectionEstablished, whose messages are '
      "drained when closed unheard (as dart:io's WebSocket does): the "
      'mapping listened first; afterConnectionClosed gets the status, once, '
      'and the session leaves the registry', () async {
    final handler = _Refusing();
    final session = _DrainingSession();
    final registry = await open(handler, session);
    final status = await handler.closed.future.timeout(
      const Duration(seconds: 5),
    );
    expect(status, CloseStatus.policyViolation.withReason('not allowed'));
    expect(session.drained, isFalse);
    expect(registry.sessions('/ws'), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(handler.closedCount, 1);
  });

  test('anything else thrown for a connection (here: messages that cannot '
      'be listened to) is logged, the session closed with 1011 and taken '
      'out of the registry; nothing reaches the zone', () async {
    final handler = _Refusing(refuse: false);
    final session = _UnlistenableSession();
    final registry = await open(handler, session);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(session.closeStatus, CloseStatus.serverError);
    expect(registry.sessions('/ws'), isEmpty);
    final record = records.singleWhere(
      (r) => r.level == SpringLogLevel.error,
    );
    expect(record.message, contains('failed'));
    expect(record.error, isA<StateError>());
  });
}

final class _Single implements WebSocketConfigurer {
  _Single(this.handler);

  final WebSocketHandler handler;

  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(handler, ['/ws']);
}

final class _Refusing extends AbstractWebSocketHandler {
  _Refusing({this.refuse = true});

  final bool refuse;
  final closed = Completer<CloseStatus>();
  int closedCount = 0;

  @override
  Future<void> afterConnectionEstablished(
    ServerWebSocketSession session,
  ) async {
    if (refuse) {
      await session.close(
        CloseStatus.policyViolation.withReason('not allowed'),
      );
    }
  }

  @override
  void afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) {
    closedCount++;
    closed.complete(status);
  }
}

/// A handshake request whose upgrade gives [connection].
final class _Upgrade extends ServerHttpRequestDecorator {
  _Upgrade(super.delegate, this.connection);

  final WebSocketSession connection;

  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) async =>
      connection;
}

/// A session whose close drains its messages when nobody listens yet, as
/// dart:io's `WebSocket.close` does; the other side answers at once.
final class _DrainingSession implements WebSocketSession {
  final _incoming = StreamController<Object>();
  CloseStatus? _status;
  bool drained = false;

  @override
  Uri get uri => Uri.parse('ws://localhost/ws');

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  String? get acceptedProtocol => null;

  @override
  bool get isOpen => _status == null;

  @override
  void sendMessage(Object message) {}

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) async {
    _status ??= status;
    if (!_incoming.hasListener) {
      drained = true;
      unawaited(_incoming.stream.drain<void>());
    }
    unawaited(_incoming.close());
  }

  @override
  CloseStatus? get closeStatus => _status;
}

/// A session whose messages were listened to already.
final class _UnlistenableSession implements WebSocketSession {
  CloseStatus? _status;

  @override
  Uri get uri => Uri.parse('ws://localhost/ws');

  @override
  Stream<Object> get messages =>
      throw StateError('Stream has already been listened to.');

  @override
  String? get acceptedProtocol => null;

  @override
  bool get isOpen => _status == null;

  @override
  void sendMessage(Object message) {}

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) async =>
      _status ??= status;

  @override
  CloseStatus? get closeStatus => _status;
}
