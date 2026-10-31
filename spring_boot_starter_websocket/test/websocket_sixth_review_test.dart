// Regression tests of the sixth review before 0.5.0: handshake origins
// checked as Spring's OriginHandshakeInterceptor does (CorsConfiguration
// .checkOrigin, WebUtils.isSameOrigin), and the reason of a connection
// reset that the write side meets first.
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_web_dart/io.dart';
import 'package:test/test.dart';

void main() {
  group('handshake origins, as Spring', () {
    final mapping = WebSocketHandlerMapping(
      beanFactory: DefaultListableBeanFactory(),
      mapper: ObjectMapper(),
      sessions: WebSocketSessionRegistry(),
      configurers: [_Origins()],
    )..initialize();

    // The status of a handshake to [target] from [origin]: 403 when the
    // origin is refused.
    Future<int> handshake(String target, String origin) async {
      final request = MockServerHttpRequest(HttpMethod.get, target)
        ..headers.set('Upgrade', 'websocket')
        ..headers.set('Connection', 'Upgrade')
        ..headers.set('Origin', origin);
      final response = MockServerHttpResponse();
      await mapping.getHandler(request)!.handle(request, response);
      return response.statusCode;
    }

    // Each case was run through Spring 7.0.10's OriginHandshakeInterceptor
    // checks (WebUtils.isSameOrigin, CorsConfiguration.checkOrigin): true
    // where Spring accepts the handshake. The server is
    // https://server.test, another origin than all of them. Spring fails
    // the handshake on http://localhost:3000.evil.example (a 500: the
    // port does not parse) where this answers 403.
    for (final (path, origin, allowed) in [
      ('/ports', 'http://localhost:3000', true),
      ('/ports', 'http://localhost', true),
      ('/ports', 'http://localhost:3000.evil.example', false),
      ('/ports', 'http://localhost.evil.example', false),
      ('/ports', 'https://localhost:3000', false),
      ('/portlist', 'http://localhost:3000', true),
      ('/portlist', 'http://localhost:3002', false),
      ('/portlist', 'http://localhost', false),
      ('/slash', 'https://shop.example', true),
      ('/plain', 'https://shop.example/', true),
      ('/plain', 'HTTPS://SHOP.EXAMPLE', true),
      ('/plain', 'https://shop.example:443', false),
      ('/plain', 'http://shop.example', false),
      ('/plain', 'https://shop.example.evil', false),
      ('/commas', 'https://b.example', true),
      ('/commas', 'http://localhost:3001', true),
      ('/sub', 'https://a.shop.example', true),
      ('/sub', 'https://a.b.shop.example', true),
      ('/sub', 'https://shop.example', false),
      ('/sub', 'https://a.shop.example.evil', false),
      ('/sub', 'http://a.shop.example', false),
      ('/sub', 'https://A.SHOP.EXAMPLE', false), // patterns: with case
      // As in Spring, a * matches any text (the eighth review); no
      // browser sends such an origin.
      ('/sub', 'https://evil.example/.shop.example', true),
      ('/sub', 'https://evil.example@a.shop.example', true),
    ]) {
      test('$path from $origin: ${allowed ? 'accepted' : '403'}', () async {
        expect(
          await handshake('https://server.test$path', origin),
          allowed ? isNot(403) : 403,
        );
      });
    }

    test("the server's own origin (scheme, host, port) is accepted, others "
        'are not', () async {
      for (final (target, origin, allowed) in [
        ('https://chat.example/plain', 'https://chat.example', true),
        ('https://chat.example/plain', 'https://chat.example:443', true),
        ('https://chat.example/plain', 'https://chat.example/', true),
        ('https://chat.example/plain', 'http://chat.example', false),
        ('https://chat.example/plain', 'wss://chat.example', false),
        ('https://chat.example/plain', 'https://chat.example.evil', false),
        ('http://localhost:8080/plain', 'http://localhost:8080', true),
        ('http://localhost:8080/plain', 'http://localhost', false),
        ('http://localhost/plain', 'http://localhost:80', true),
        ('http://localhost/plain', 'null', false),
      ]) {
        expect(
          await handshake(target, origin),
          allowed ? isNot(403) : 403,
          reason: '$target from $origin',
        );
      }
    });
  });

  group('a reset the write meets first', () {
    const reset = io.SocketException(
      'Connection reset by peer',
      osError: io.OSError('Connection reset by peer', 54),
    );

    test(
      'afterConnectionClosed gets 1006 with the error as the reason',
      () async {
        final handler = _Closing();
        final mapping = WebSocketHandlerMapping(
          beanFactory: DefaultListableBeanFactory(),
          mapper: ObjectMapper(),
          sessions: WebSocketSessionRegistry(),
          configurers: [_Single(handler)],
        )..initialize();
        final socket = _FailingSocket();
        final request = _Upgrade(
          MockServerHttpRequest(HttpMethod.get, '/ws/reset')
            ..headers.set('Upgrade', 'websocket')
            ..headers.set('Connection', 'Upgrade'),
          IoWebSocketSession.fromUpgradedSocket(
            socket,
            Uri.parse('ws://localhost/ws/reset'),
            serverSide: true,
          ),
        );
        final handled = mapping
            .getHandler(request)!
            .handle(request, MockServerHttpResponse());
        await handler.established.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        socket.failWrite(reset);
        expect(
          await handler.closed.future.timeout(const Duration(seconds: 5)),
          CloseStatus.noCloseFrame.withReason('Connection reset by peer'),
        );
        await handled.timeout(const Duration(seconds: 5));
      },
    );

    test("the client's log line has the reason", () async {
      final records = <SpringLogRecord>[];
      final previous = SpringLog.handler;
      SpringLog.handler = records.add;
      SpringLog.setLevel('websocket.reset', SpringLogLevel.debug);
      addTearDown(() {
        SpringLog.handler = previous;
        SpringLog.setLevel('websocket.reset', null);
      });
      final socket = _FailingSocket();
      final manager = WebSocketConnectionManager(
        clientName: 'reset',
        url: Uri.parse('ws://chat.test/ws'),
        config: const WebSocketClientConfig(
          reconnect: WebSocketReconnectPolicy(enabled: false),
        ),
        transport: _Transport(
          IoWebSocketSession.fromUpgradedSocket(
            socket,
            Uri.parse('ws://chat.test/ws'),
            serverSide: false,
          ),
        ),
        log: const SpringLog('websocket.reset'),
      );
      final ended = manager.messages().drain<void>().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await manager.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      socket.failWrite(reset);
      final error = await ended.timeout(const Duration(seconds: 5));
      expect(
        records.map((r) => r.message),
        contains('connection closed (1006 Connection reset by peer)'),
      );
      expect(
        error,
        isA<WebSocketException>().having(
          (e) => e.message,
          'message',
          contains('code 1006: Connection reset by peer'),
        ),
      );
      await manager.dispose();
    });
  });
}

final class _Echo extends AbstractWebSocketHandler {}

final class _Origins implements WebSocketConfigurer {
  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
    registry
      ..addHandler(_Echo(), [
        '/ports',
      ]).setAllowedOriginPatterns(['http://localhost:[*]'])
      ..addHandler(_Echo(), [
        '/portlist',
      ]).setAllowedOriginPatterns(['http://localhost:[3000,3001]'])
      ..addHandler(_Echo(), ['/slash']).setAllowedOrigins([
        'https://shop.example/',
      ])
      ..addHandler(_Echo(), ['/plain']).setAllowedOrigins([
        'https://shop.example',
      ])
      ..addHandler(_Echo(), ['/commas'])
          .setAllowedOrigins(['https://a.example, https://b.example'])
          .setAllowedOriginPatterns([
            'http://localhost:[3000,3001], https://*.a.example',
          ])
      ..addHandler(_Echo(), [
        '/sub',
      ]).setAllowedOriginPatterns(['https://*.shop.example']);
  }
}

final class _Single implements WebSocketConfigurer {
  _Single(this.handler);

  final WebSocketHandler handler;

  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(handler, ['/ws/reset']);
}

final class _Closing extends AbstractWebSocketHandler {
  final established = Completer<void>();
  final closed = Completer<CloseStatus>();

  @override
  void afterConnectionEstablished(ServerWebSocketSession session) {
    session.sendMessage('hello'); // dart:io starts its output
    established.complete();
  }

  @override
  void afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) => closed.complete(status);
}

/// Opens [session] on the first connect.
final class _Transport implements WebSocketTransport {
  _Transport(this.session);

  final WebSocketSession session;

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  }) async => session;
}

/// A handshake request whose upgrade gives [connection].
final class _Upgrade extends ServerHttpRequestDecorator {
  _Upgrade(super.delegate, this.connection);

  final WebSocketSession connection;

  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) async =>
      connection;
}

/// A connection whose write fails when the test says ([failWrite]), as
/// when the other side resets it before anything was read.
final class _FailingSocket extends Stream<Uint8List> implements io.Socket {
  final _input = StreamController<Uint8List>();
  final _written = Completer<void>();
  final _done = Completer<void>();

  void failWrite(Object error) => _written.completeError(error);

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    stream.listen((_) {}, onError: (Object _) {});
    return _written.future;
  }

  @override
  void add(List<int> data) {}

  @override
  void destroy() {
    if (!_input.isClosed) {
      unawaited(_input.close());
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> close() async => destroy();

  @override
  Future<void> get done => _done.future;

  @override
  Object? noSuchMethod(Invocation invocation) => null;
}
