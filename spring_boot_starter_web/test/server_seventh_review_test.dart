// Regression tests of the seventh review before 0.5.0 over real sockets:
// a WebSocket session closed while it opens (it crashed the process), a
// huge Origin against patterns with several `*` (it froze the server),
// and the close status of a session reset over wss (TLS).
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

import 'server_review_test.dart' show raw, serve, statusOf, until;

void main() {
  group('a WebSocket session closed while it opens', () {
    late WebSocketSessionRegistry registry;
    late _Gate gate;
    late _Lobby lobby;
    late _Room room;
    late IoWebServer server;

    setUp(() async {
      registry = WebSocketSessionRegistry();
      gate = _Gate();
      lobby = _Lobby();
      room = _Room();
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(_lobbyDefinition(lobby))
        ..registerBeanDefinition(_roomDefinition(room));
      final mapping = WebSocketHandlerMapping(
        beanFactory: factory,
        mapper: ObjectMapper(),
        sessions: registry,
        configurers: [_Configurer(gate)],
      )..initialize();
      server = await serve(
        (request, response) =>
            mapping.getHandler(request)!.handle(request, response),
      );
    });

    tearDown(() => server.stop(timeout: Duration.zero));

    Future<io.WebSocket> connect(String path) =>
        io.WebSocket.connect('ws://127.0.0.1:${server.port}$path');

    // Each next connection is served as usual: the process and the
    // server lived on.
    Future<void> expectEcho(String path) async {
      final socket = await connect(path);
      final replies = StreamIterator(socket);
      socket.add('hi');
      expect(
        await replies.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(replies.current, 'echo: hi');
      await socket.close(CloseStatus.normal.code);
      await replies.cancel();
    }

    test('afterConnectionEstablished closes it (a refused client): the client '
        'gets the status, afterConnectionClosed is called once with it, the '
        'session leaves the registry', () async {
      for (var round = 0; round < 3; round++) {
        gate.refuse = true;
        final socket = await connect('/ws/gate');
        await socket.drain<void>().timeout(const Duration(seconds: 5));
        expect(socket.closeCode, CloseStatus.policyViolation.code);
        expect(socket.closeReason, 'not allowed');
        // Each round: the refused connection, then the echoed one.
        await until(() => gate.closed.length == 2 * round + 1);
        expect(
          gate.closed[2 * round],
          CloseStatus.policyViolation.withReason('not allowed'),
        );
        expect(registry.sessions('/ws/gate'), isEmpty);
        gate.refuse = false;
        await expectEcho('/ws/gate');
      }
      await until(() => gate.closed.length == 6);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(gate.closed.map((s) => s.code), [
        for (var round = 0; round < 3; round++) ...[1008, 1000],
      ], reason: 'once per connection');
    });

    test('an @OnOpen that throws, without @OnError: the client gets 1011, '
        '@OnClose gets it, the session leaves the registry', () async {
      for (var round = 0; round < 3; round++) {
        lobby.full = true;
        final socket = await connect('/ws/lobby');
        await socket.drain<void>().timeout(const Duration(seconds: 5));
        expect(socket.closeCode, CloseStatus.serverError.code);
        await until(() => lobby.closed.length == 2 * round + 1);
        expect(lobby.closed[2 * round].code, CloseStatus.serverError.code);
        expect(registry.sessions('/ws/lobby'), isEmpty);
        lobby.full = false;
        await expectEcho('/ws/lobby');
      }
      await until(() => lobby.closed.length == 6);
      expect(lobby.closed.map((s) => s.code), [
        for (var round = 0; round < 3; round++) ...[1011, 1000],
      ]);
    });

    test(
      'an @OnOpen that throws, with @OnError: @OnError gets the error and '
      'decides; the session stays open, or closes as @OnError says',
      () async {
        // @OnError leaves it open: messages flow.
        room.closeOnError = false;
        await expectEcho('/ws/room');
        expect(room.errors.single, isA<StateError>());
        await until(() => room.closed.length == 1);
        expect(room.closed.single, CloseStatus.normal);
        // @OnError closes it.
        room.closeOnError = true;
        final socket = await connect('/ws/room');
        await socket.drain<void>().timeout(const Duration(seconds: 5));
        expect(socket.closeCode, 4001);
        expect(socket.closeReason, 'room full');
        await until(() => room.closed.length == 2);
        expect(room.closed.last, const CloseStatus(4001, 'room full'));
        expect(registry.sessions('/ws/room'), isEmpty);
      },
    );
  });

  group('a 1 MB Origin against patterns with three `*`', () {
    const patterns = ['https://*-*-*.vercel.app'];
    // Just under dart:io's 1 MB limit for all the headers.
    final huge = 'https://${'-' * 1000000}x';
    late IoWebServer server;

    setUp(() async {
      final mapping = WebSocketHandlerMapping(
        beanFactory: DefaultListableBeanFactory(),
        mapper: ObjectMapper(),
        sessions: WebSocketSessionRegistry(),
        configurers: [_Patterns(patterns)],
      )..initialize();
      final cors = CorsConfiguration(allowedOriginPatterns: patterns)
        ..applyPermitDefaultValues();
      server = await serve((request, response) async {
        if (request.path == '/ws') {
          return await mapping.getHandler(request)!.handle(request, response);
        }
        if (!processCors(
          cors,
          request,
          response,
          preFlight: isPreFlightRequest(request),
        )) {
          return await response.send(403, 'Invalid CORS request');
        }
        response.statusCode = 200;
        await response.close();
      });
    });

    tearDown(() => server.stop(timeout: Duration.zero));

    String request(String path, String origin) =>
        'GET $path HTTP/1.1\r\nHost: 127.0.0.1\r\nOrigin: $origin\r\n'
        'Upgrade: websocket\r\nConnection: Upgrade, close\r\n'
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n';

    test('is refused at once, on CORS and on the WebSocket handshake; the '
        'server goes on answering', () async {
      for (final path in ['/api', '/ws']) {
        final watch = Stopwatch()..start();
        final answer = await raw(server.port, request(path, huge));
        expect(answer, startsWith('HTTP/1.1 403'), reason: path);
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      }
      expect(
        statusOf(
          await raw(server.port, request('/api', 'https://a-b-c.vercel.app')),
        ),
        200,
      );
      expect(
        statusOf(
          // The connection stays open (a WebSocket): what came in 1 s.
          await raw(
            server.port,
            request('/ws', 'https://a-b-c.vercel.app'),
            timeout: const Duration(seconds: 1),
          ),
        ),
        101,
      );
    });
  });

  group('a session reset over wss (TLS)', () {
    io.Directory? certificates;
    late _Flood flood;
    late IoWebServer server;

    setUpAll(() async {
      // A self-signed certificate made for the test; without openssl the
      // group is skipped.
      final directory = await io.Directory.systemTemp.createTemp('wss_test');
      try {
        final made = await io.Process.run('openssl', [
          'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
          '-subj', '/CN=localhost',
          '-keyout', '${directory.path}/key.pem',
          '-out', '${directory.path}/cert.pem',
        ]);
        if (made.exitCode == 0) {
          certificates = directory;
        }
      } on io.ProcessException {
        // No openssl.
      }
    });

    tearDownAll(() async {
      await certificates?.delete(recursive: true);
    });

    setUp(() async {
      final directory = certificates;
      if (directory == null) {
        markTestSkipped('openssl is needed to make a test certificate');
        return;
      }
      flood = _Flood();
      final mapping = WebSocketHandlerMapping(
        beanFactory: DefaultListableBeanFactory(),
        mapper: ObjectMapper(),
        sessions: WebSocketSessionRegistry(),
        configurers: [_FloodConfigurer(flood)],
      )..initialize();
      server = await serve(
        (request, response) =>
            mapping.getHandler(request)!.handle(request, response),
        ServerProperties(
          webSocketSendBufferSizeLimit: -1,
          webSocketSendTimeLimit: null,
          ssl: SslSettings(
            certificate: '${directory.path}/cert.pem',
            privateKey: '${directory.path}/key.pem',
          ),
        ),
      );
    });

    tearDown(() async {
      if (certificates != null) {
        await server.stop(timeout: Duration.zero);
      }
    });

    // A client that opens a wss connection, has the server send far more
    // than the network holds, reads nothing (after [message], when given)
    // and resets the connection: the status afterConnectionClosed got.
    Future<CloseStatus> resetByClient({List<int>? message}) async {
      flood
        ..closed = Completer()
        ..opened = Completer()
        ..closeCalled = Completer();
      final socket = await io.SecureSocket.connect(
        '127.0.0.1',
        server.port,
        onBadCertificate: (_) => true,
      );
      socket.add(
        ascii.encode(
          'GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Upgrade\r\n'
          'Upgrade: websocket\r\n'
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
          'Sec-WebSocket-Version: 13\r\n\r\n',
        ),
      );
      final reading = socket.listen((_) {}, onError: (Object _) {});
      await flood.opened.future.timeout(const Duration(seconds: 10));
      if (message != null) {
        socket.add(message);
        await flood.closeCalled.future.timeout(const Duration(seconds: 10));
      }
      reading.pause();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      socket.destroy(); // with data unread: a reset
      final status = await flood.closed.future.timeout(
        const Duration(seconds: 15),
      );
      await reading.cancel();
      return status;
    }

    test('afterConnectionClosed gets 1006 with the error as the reason, '
        'though TLS often ends the input before the write fails', () async {
      for (var round = 0; round < 6; round++) {
        final status = await resetByClient();
        expect(status.code, CloseStatus.noCloseFrame.code, reason: '$round');
        expect(status.reason, isNotNull, reason: 'round $round: $status');
      }
    });

    test('after close(4001) from the handler, afterConnectionClosed gets '
        '4001, not the 1006 of the reset that follows', () async {
      for (var round = 0; round < 6; round++) {
        // A masked text frame "x": the handler closes with 4001.
        final status = await resetByClient(
          message: [0x81, 0x81, 1, 2, 3, 4, 0x78 ^ 1],
        );
        expect(status, const CloseStatus(4001, 'bye'), reason: '$round');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Refuses the connection in afterConnectionEstablished while [refuse],
/// else echoes.
final class _Gate extends AbstractWebSocketHandler {
  bool refuse = true;
  final closed = <CloseStatus>[];

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
  void handleTextMessage(ServerWebSocketSession session, String message) =>
      session.sendMessage('echo: $message');

  @override
  void afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) => closed.add(status);
}

final class _Configurer implements WebSocketConfigurer {
  _Configurer(this.gate);

  final _Gate gate;

  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(gate, ['/ws/gate']);
}

final class _Patterns implements WebSocketConfigurer {
  _Patterns(this.patterns);

  final List<String> patterns;

  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(_Echo(), ['/ws']).setAllowedOriginPatterns(patterns);
}

final class _Echo extends AbstractWebSocketHandler {}

/// Sends 32 MB when the connection opens; a text message makes it close
/// with 4001.
final class _Flood extends AbstractWebSocketHandler {
  Completer<CloseStatus> closed = Completer();
  Completer<void> opened = Completer();
  Completer<void> closeCalled = Completer();

  @override
  void afterConnectionEstablished(ServerWebSocketSession session) {
    for (var i = 0; i < 64; i++) {
      session.sendMessage(Uint8List(512 << 10));
    }
    opened.complete();
  }

  @override
  void handleTextMessage(ServerWebSocketSession session, String message) {
    unawaited(
      session.close(const CloseStatus(4001, 'bye')).catchError((Object _) {}),
    );
    closeCalled.complete();
  }

  @override
  void afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) => closed.complete(status);
}

final class _FloodConfigurer implements WebSocketConfigurer {
  _FloodConfigurer(this.flood);

  final _Flood flood;

  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(flood, ['/ws']);
}

/// An endpoint whose @OnOpen throws while [full] (no @OnError: the
/// session closes with 1011), else echoes.
final class _Lobby {
  bool full = true;
  final closed = <CloseStatus>[];

  void open(ServerWebSocketSession session) {
    if (full) {
      throw StateError('lobby full');
    }
  }

  String message(String text) => 'echo: $text';

  void close(CloseStatus status) => closed.add(status);
}

/// An endpoint whose @OnOpen always throws, and whose @OnError closes
/// with 4001 when [closeOnError], else leaves the session open.
final class _Room {
  bool closeOnError = false;
  final errors = <Object?>[];
  final closed = <CloseStatus>[];

  void open(ServerWebSocketSession session) => throw StateError('room full');

  String message(String text) => 'echo: $text';

  Future<void> error(ServerWebSocketSession session, Object? error) async {
    errors.add(error);
    if (closeOnError) {
      await session.close(const CloseStatus(4001, 'room full'));
    }
  }

  void close(CloseStatus status) => closed.add(status);
}

// The definitions the generator writes for the two endpoints.

const _session = BeanParameter(
  'session',
  type: ClassType<ServerWebSocketSession>(),
  isRequired: true,
);

BeanMethod<T> _onOpen<T extends Object>(
  void Function(T bean, ServerWebSocketSession s) open,
) => BeanMethod<T>(
  'open',
  parameterTypes: const [ServerWebSocketSession],
  parameters: const [_session],
  isVoid: true,
  invoke: (bean, arguments) =>
      open(bean, arguments.single! as ServerWebSocketSession),
  annotations: const [OnOpen()],
);

BeanMethod<T> _onMessage<T extends Object>(
  String Function(T bean, String text) message,
) => BeanMethod<T>(
  'message',
  parameterTypes: const [String],
  parameters: const [
    BeanParameter('text', type: ClassType<String>(), isRequired: true),
  ],
  invoke: (bean, arguments) => message(bean, arguments.single! as String),
  annotations: const [OnMessage()],
);

BeanMethod<T> _onClose<T extends Object>(
  void Function(T bean, CloseStatus status) close,
) => BeanMethod<T>(
  'close',
  parameterTypes: const [CloseStatus],
  parameters: const [
    BeanParameter('status', type: ClassType<CloseStatus>(), isRequired: true),
  ],
  isVoid: true,
  invoke: (bean, arguments) => close(bean, arguments.single! as CloseStatus),
  annotations: const [OnClose()],
);

BeanDefinition<_Lobby> _lobbyDefinition(_Lobby lobby) => BeanDefinition<_Lobby>(
  name: 'lobbyEndpoint',
  types: const [_Lobby],
  create: (_) => lobby,
  annotatedMethods: [
    _onOpen<_Lobby>((bean, session) => bean.open(session)),
    _onMessage<_Lobby>((bean, text) => bean.message(text)),
    _onClose<_Lobby>((bean, status) => bean.close(status)),
  ],
  annotations: const [WebSocketEndpoint('/ws/lobby')],
);

BeanDefinition<_Room> _roomDefinition(_Room room) => BeanDefinition<_Room>(
  name: 'roomEndpoint',
  types: const [_Room],
  create: (_) => room,
  annotatedMethods: [
    _onOpen<_Room>((bean, session) => bean.open(session)),
    _onMessage<_Room>((bean, text) => bean.message(text)),
    _onClose<_Room>((bean, status) => bean.close(status)),
    BeanMethod<_Room>(
      'error',
      parameterTypes: const [ServerWebSocketSession, Object],
      parameters: const [
        _session,
        BeanParameter('error', type: ClassType<Object>()),
      ],
      isVoid: true,
      invoke: (bean, arguments) => bean.error(
        arguments[0]! as ServerWebSocketSession,
        arguments[1],
      ),
      annotations: const [OnError()],
    ),
  ],
  annotations: const [WebSocketEndpoint('/ws/room')],
);
