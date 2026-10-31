// A slow handler and a fast client: the server stops reading the
// connection while a message is handled, instead of queueing everything
// the client sends (the web starter's socket then stops reading from the
// network, so the client waits).
import 'dart:async';
import 'dart:typed_data';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a slow handler pauses a fast client: at most one message waits',
    () async {
      final handler = _SlowHandler();
      final mapping = WebSocketHandlerMapping(
        beanFactory: DefaultListableBeanFactory(),
        mapper: ObjectMapper(),
        sessions: WebSocketSessionRegistry(),
        configurers: [_Config(handler)],
      )..initialize();
      final connection = _FastClient(
        total: 100,
        handled: () => handler.handled.length,
      );
      final request = _Upgrade(
        MockServerHttpRequest(HttpMethod.get, '/ws/slow')
          ..headers.set('Upgrade', 'websocket')
          ..headers.set('Connection', 'Upgrade'),
        connection,
      );
      await mapping
          .getHandler(request)!
          .handle(request, MockServerHttpResponse());

      await connection.allSent.future.timeout(const Duration(seconds: 10));
      await handler.closed.future.timeout(const Duration(seconds: 10));
      expect(handler.handled, [for (var i = 0; i < 100; i++) 'm$i']);
      // Sent but not handled yet: the one in the handler, at most one more.
      expect(connection.mostWaiting, lessThanOrEqualTo(2));
      expect(connection.pauses, greaterThanOrEqualTo(99));
    },
  );
}

final class _Config implements WebSocketConfigurer {
  _Config(this.handler);

  final WebSocketHandler handler;

  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(handler, ['/ws/slow']);
}

final class _SlowHandler extends TextWebSocketHandler {
  final handled = <String>[];
  final closed = Completer<void>();

  @override
  Future<void> handleTextMessage(
    ServerWebSocketSession session,
    String message,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    handled.add(message);
  }

  @override
  void afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) => closed.complete();
}

/// The server's end of a connection whose client sends as fast as the
/// server reads: one message per turn of the event loop, none while the
/// server has paused reading (as TCP holds a client back).
final class _FastClient implements WebSocketSession {
  _FastClient({required this.total, required this.handled}) {
    _incoming = StreamController<Object>(
      onListen: _schedule,
      onResume: _schedule,
      onPause: () => pauses++,
    );
  }

  final int total;
  final int Function() handled;
  late final StreamController<Object> _incoming;
  final allSent = Completer<void>();
  var _sent = 0;
  int mostWaiting = 0;
  int pauses = 0;
  var _scheduled = false;

  void _schedule() {
    if (!_scheduled) {
      _scheduled = true;
      Timer.run(_send);
    }
  }

  void _send() {
    _scheduled = false;
    if (_incoming.isPaused || _sent == total) {
      return;
    }
    _incoming.add('m${_sent++}');
    if (_sent - handled() > mostWaiting) {
      mostWaiting = _sent - handled();
    }
    if (_sent == total) {
      allSent.complete();
      unawaited(_incoming.close());
      return;
    }
    _schedule();
  }

  @override
  final uri = Uri.parse('ws://localhost/ws/slow');

  @override
  String? get acceptedProtocol => null;

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  bool get isOpen => !_incoming.isClosed;

  @override
  CloseStatus? get closeStatus => isOpen ? null : CloseStatus.normal;

  @override
  void sendMessage(Object message) {}

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) async {}
}

/// A handshake request whose upgrade gives [connection].
final class _Upgrade implements ServerHttpRequest {
  _Upgrade(this._request, this.connection);

  final MockServerHttpRequest _request;
  final WebSocketSession connection;

  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) async =>
      connection;

  @override
  bool get isWebSocketUpgrade => _request.isWebSocketUpgrade;

  @override
  HttpMethod get method => _request.method;

  @override
  Uri get uri => _request.uri;

  @override
  String get path => _request.path;

  @override
  HttpHeaders get headers => _request.headers;

  @override
  Map<String, List<String>> get queryParameters => _request.queryParameters;

  @override
  Map<String, String> get cookies => _request.cookies;

  @override
  String? get remoteAddress => _request.remoteAddress;

  @override
  bool get isSecure => _request.isSecure;

  @override
  Map<String, Object?> get attributes => _request.attributes;

  @override
  Principal? get principal => _request.principal;

  @override
  set principal(Principal? value) => _request.principal = value;

  @override
  Stream<Uint8List> get body => _request.body;
}
