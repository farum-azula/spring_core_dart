@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

void main() {
  group('IoWebSocketTransport', () {
    late io.HttpServer server;
    late Uri base;
    final transport = IoWebSocketTransport();
    final handshakes = <io.HttpHeaders>[];

    setUpAll(() async {
      server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('ws://127.0.0.1:${server.port}');
      server.listen((request) async {
        if (request.uri.path == '/slow') {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        if (request.uri.path != '/echo' ||
            !io.WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = 400;
          await request.response.close();
          return;
        }
        handshakes.add(request.headers);
        final socket = await io.WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) => protocols.first,
        );
        socket.listen((message) {
          if (message == 'bye') {
            socket.close(4000, 'asked');
          } else {
            socket.add(message); // echo
          }
        });
      });
    });

    tearDownAll(() => server.close(force: true));

    test('echoes text and binary, sends headers and protocols', () async {
      final session = await transport.connect(
        base.resolve('/echo'),
        headers: HttpHeaders({'Authorization': 'Bearer t'}),
        protocols: ['chat.v1'],
        timeout: const Duration(seconds: 2),
      );
      expect(session.acceptedProtocol, 'chat.v1');
      expect(session.uri, base.resolve('/echo'));
      expect(session.isOpen, isTrue);
      expect(session.closeStatus, isNull);
      expect(handshakes.last.value('authorization'), 'Bearer t');
      final messages = StreamIterator(session.messages);
      session.sendMessage('hello');
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, 'hello');
      session.sendMessage([1, 2, 3]);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, isA<Uint8List>());
      expect(messages.current, [1, 2, 3]);
      session.sendMessage('bye');
      expect(await messages.moveNext(), isFalse);
      expect(session.closeStatus, const CloseStatus(4000, 'asked'));
      expect(session.isOpen, isFalse);
      expect(
        () => session.sendMessage('late'),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('client close, refused, rejected and slow handshakes', () async {
      final session = await transport.connect(base.resolve('/echo'));
      await session.close(CloseStatus.goingAway.withReason('done'));
      expect(session.closeStatus?.equalsCode(CloseStatus.goingAway), isTrue);
      // Like Spring, close() without a status is a normal closure.
      final other = await transport.connect(base.resolve('/echo'));
      await other.close();
      expect(other.closeStatus, CloseStatus.normal);

      final free = await io.ServerSocket.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      final port = free.port;
      await free.close();
      await expectLater(
        transport.connect(Uri.parse('ws://127.0.0.1:$port/')),
        throwsA(isA<WebSocketException>()),
      );
      await expectLater(
        transport.connect(base.resolve('/missing').replace(scheme: 'ws')),
        throwsA(isA<WebSocketException>()),
      );
      await expectLater(
        transport.connect(
          base.resolve('/slow'),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<WebSocketException>().having(
            (e) => e.isTimeout,
            'isTimeout',
            true,
          ),
        ),
      );
    });

    test('platformWebSocketTransport is the dart:io one here', () {
      expect(platformWebSocketTransport(), isA<IoWebSocketTransport>());
    });
  });

  test('CloseStatus: Spring\'s constants, withReason, equalsCode', () {
    expect(CloseStatus.normal.code, 1000);
    expect(CloseStatus.noCloseFrame.code, 1006);
    expect(CloseStatus.serverError.code, 1011);
    expect(CloseStatus.serviceOverload.code, 1013);
    expect(CloseStatus.sessionNotReliable.code, 4500);
    final status = CloseStatus.policyViolation.withReason('no token');
    expect(status, const CloseStatus(1008, 'no token'));
    expect(status == CloseStatus.policyViolation, isFalse);
    expect(status.equalsCode(CloseStatus.policyViolation), isTrue);
    expect('$status', 'CloseStatus[code=1008, reason=no token]');
  });

  group('MockWebSocketTransport', () {
    test('plays the server side', () async {
      final sockets = MockWebSocketTransport();
      final next = sockets.nextConnection;
      final client = await sockets.connect(
        Uri.parse('wss://chat.test/ws'),
        headers: HttpHeaders({'X-Token': 't'}),
        protocols: ['v1'],
      );
      final server = await next;
      expect(server, same(sockets.lastConnection));
      expect(server.headers['X-Token'], 't');
      expect(client.acceptedProtocol, 'v1');
      expect(client.uri, Uri.parse('wss://chat.test/ws'));

      final received = <Object>[];
      final done = Completer<void>();
      client.messages.listen(received.add, onDone: done.complete);
      final sent = server.onSent.first;
      client.sendMessage('{"text":"hi"}');
      expect(await sent, '{"text":"hi"}');
      client.sendMessage([7]);
      expect(server.sentJson, [
        {'text': 'hi'},
      ]);
      expect(server.sent.last, [7]);

      server
        ..push('text')
        ..pushJson({'n': 1})
        ..push([1, 2]);
      await server.drop();
      await done.future;
      expect(received, [
        'text',
        '{"n":1}',
        [1, 2],
      ]);
      expect(client.closeStatus, CloseStatus.noCloseFrame);
      expect(client.isOpen, isFalse);
      expect(server.closedByClient, isFalse);
      expect(() => client.sendMessage('x'), throwsA(isA<WebSocketException>()));
    });

    test('failures, client close and connection order', () async {
      final sockets = MockWebSocketTransport()..failNextConnect();
      await expectLater(
        sockets.connect(Uri.parse('ws://h/')),
        throwsA(isA<WebSocketException>()),
      );
      final first = await sockets.connect(Uri.parse('ws://h/1'));
      final second = await sockets.connect(Uri.parse('ws://h/2'));
      expect((await sockets.nextConnection).uri.path, '/1');
      expect((await sockets.nextConnection).uri.path, '/2');
      await first.close(CloseStatus.normal.withReason('bye'));
      expect(sockets.connections.first.closedByClient, isTrue);
      expect(first.closeStatus?.reason, 'bye');
      await (second as MockWebSocket).closeFromServer(
        CloseStatus.policyViolation,
      );
      expect(second.closeStatus?.code, 1008);
      expect(second.closedByClient, isFalse);
    });
  });
}
