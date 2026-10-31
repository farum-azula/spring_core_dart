// Regression tests of the third review before 0.5.0 over real sockets:
// WebSocket sessions whose output backs up (a reset, two peers sending at
// once), server.connection-timeout of 0 or less, and what dart:io does to
// a raw request target before the server sees it.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_web_dart/io.dart' show IoWebSocketTransport;
import 'package:test/test.dart';

import 'server_review_test.dart' show raw, rawWebSocket, serve, statusOf, until;
import 'support.dart';

void main() {
  group('WebSocket: output that backs up', () {
    test('a client that resets while the server waits to send: the handler '
        'gets afterConnectionClosed (1006), the session leaves the registry '
        'and the server', () async {
      final registry = WebSocketSessionRegistry();
      final handler = _Flooding();
      final mapping = WebSocketHandlerMapping(
        beanFactory: DefaultListableBeanFactory(),
        mapper: ObjectMapper(),
        sessions: registry,
        configurers: [_Configurer(handler)],
      )..initialize();
      final server = await serve(
        (request, response) => mapping
            .getHandler(request)!
            .handle(
              request,
              response,
            ),
        const ServerProperties(
          webSocketSendBufferSizeLimit: 256 << 20,
          webSocketSendTimeLimit: Duration(minutes: 1),
        ),
      );
      try {
        final (socket, _) = await rawWebSocket(server.port, path: '/ws/flood');
        await handler.established.future.timeout(const Duration(seconds: 10));
        // The 32 MB message fills the kernel's buffers; the rest waits.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(registry.sessions('/ws/flood'), hasLength(1));
        socket.destroy(); // with data unread: a reset
        final status = await handler.closed.future.timeout(
          const Duration(seconds: 10),
        );
        expect(status.code, CloseStatus.noCloseFrame.code);
        expect(registry.sessions('/ws/flood'), isEmpty);
      } finally {
        // Nothing left to close: the stop does not wait.
        final watch = Stopwatch()..start();
        await server.stop(timeout: const Duration(seconds: 5));
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      }
    });

    test('a Dart client and the server that both send 16 MB at once both '
        'get everything', () async {
      const total = 2000 * 8000;
      final serverGot = Completer<int>();
      final server = await serve(
        (request, response) async {
          final session = await request.upgradeToWebSocket();
          var got = 0;
          session.messages.listen((message) {
            if (message == 'go') {
              for (var sent = 0; sent < total; sent += 8000) {
                session.sendMessage('s' * 8000);
              }
              return;
            }
            got += (message as String).length;
            if (got == total) {
              serverGot.complete(got);
            }
          });
        },
        const ServerProperties(
          webSocketSendBufferSizeLimit: 64 << 20,
          webSocketSendTimeLimit: Duration(seconds: 5),
        ),
      );
      try {
        final session = await IoWebSocketTransport(
          sendBufferSizeLimit: 64 << 20,
          sendTimeLimit: const Duration(seconds: 5),
        ).connect(Uri.parse('ws://127.0.0.1:${server.port}/ws'));
        var got = 0;
        final all = Completer<void>();
        session.messages.listen((message) {
          got += (message as String).length;
          if (got == total) {
            all.complete();
          }
        }, onDone: () => all.isCompleted ? null : all.complete());
        session.sendMessage('go');
        for (var sent = 0; sent < total; sent += 8000) {
          session.sendMessage('c' * 8000);
        }
        await all.future.timeout(const Duration(seconds: 30));
        expect(session.closeStatus, isNull);
        expect(got, total);
        expect(
          await serverGot.future.timeout(const Duration(seconds: 30)),
          total,
        );
        await session.close();
      } finally {
        await server.stop(timeout: Duration.zero);
      }
    });
  });

  group('server.connection-timeout of 0 or less is no limit, as in Tomcat', () {
    test('read from the properties', () {
      Duration? timeout(String value) => ServerProperties.of(
        StandardEnvironment()
          ..propertySources.addFirst(
            MapPropertySource('t', {'server.connection-timeout': value}),
          ),
      ).connectionTimeout;
      expect(timeout('0'), isNull);
      expect(timeout('0s'), isNull);
      expect(timeout('-1'), isNull);
      expect(timeout('-5s'), isNull);
      expect(timeout('30s'), const Duration(seconds: 30));
      expect(
        const ServerProperties(
          connectionTimeout: Duration.zero,
        ).effectiveConnectionTimeout,
        isNull,
      );
      expect(
        const ServerProperties(
          connectionTimeout: Duration(seconds: -1),
        ).effectiveConnectionTimeout,
        isNull,
      );
    });

    for (final value in ['0', '-5s']) {
      test('$value: a stalled body is not cut, an idle connection stays '
          'open', () async {
        await webRunner(['server.connection-timeout=$value']).runAsync((
          context,
        ) async {
          final client = await Client.of(context.context);
          final socket = await io.Socket.connect('127.0.0.1', client.port);
          final received = StringBuffer();
          socket.listen((chunk) => received.write(latin1.decode(chunk)));
          Future<String> reply() async {
            await until(() => received.toString().contains('\r\n\r\n'));
            await Future<void>.delayed(const Duration(milliseconds: 50));
            final text = received.toString();
            received.clear();
            return text;
          }

          // Half of the body, then a pause: no 408.
          socket.add(
            latin1.encode(
              'POST /api/books/form HTTP/1.1\r\nHost: localhost\r\n'
              'Content-Type: application/x-www-form-urlencoded\r\n'
              'Content-Length: 15\r\n\r\ntitle=a',
            ),
          );
          await Future<void>.delayed(const Duration(seconds: 1));
          expect(received.toString(), isEmpty);
          socket.add(latin1.encode('&count=2'));
          var response = await reply();
          expect(statusOf(response), 200);
          expect(response, endsWith('a x2'));

          // The connection is idle for a while, then used again.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          socket.add(
            latin1.encode(
              'GET /api/books/sample/defaults HTTP/1.1\r\n'
              'Host: localhost\r\n\r\n',
            ),
          );
          response = await reply();
          expect(statusOf(response), 200);
          socket.destroy();
          client.close();
        });
      });
    }
  });

  test('dart:io parses the request target before the server sees it: a raw '
      r'"\" is a "/", raw bytes past ASCII are Latin-1', () async {
    final server = await serve(
      (request, response) => response.send(200, request.path),
    );
    try {
      var response = await raw(
        server.port,
        'GET /misc/files/..\\..\\secret HTTP/1.1\r\nHost: localhost\r\n'
        'Connection: close\r\n\r\n',
      );
      expect(statusOf(response), 200);
      // Resolved by dart:io: a proxy in front must refuse "\" itself.
      expect(response, endsWith('\r\n\r\n/secret'));
      response = await raw(
        server.port,
        'GET /cafÃ© HTTP/1.1\r\nHost: localhost\r\n'
        'Connection: close\r\n\r\n', // the UTF-8 bytes of "café"
      );
      expect(response, endsWith('\r\n\r\n/caf%C3%83%C2%A9'));
    } finally {
      await server.stop(timeout: Duration.zero);
    }
  });
}

final class _Configurer implements WebSocketConfigurer {
  _Configurer(this.handler);

  final WebSocketHandler handler;

  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(handler, ['/ws/flood']);
}

// Sends one message far larger than the kernel's buffers to each client.
final class _Flooding extends AbstractWebSocketHandler {
  final established = Completer<void>();
  final closed = Completer<CloseStatus>();

  @override
  void afterConnectionEstablished(ServerWebSocketSession session) {
    session.sendMessage(Uint8List(32 << 20));
    established.complete();
  }

  @override
  void afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) => closed.complete(status);
}
