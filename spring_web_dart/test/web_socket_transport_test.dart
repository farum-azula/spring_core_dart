@TestOn('vm')
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
      final socket = await transport.connect(
        base.resolve('/echo'),
        headers: HttpHeaders({'Authorization': 'Bearer t'}),
        protocols: ['chat.v1'],
        timeout: const Duration(seconds: 2),
      );
      expect(socket.protocol, 'chat.v1');
      expect(handshakes.last.value('authorization'), 'Bearer t');
      final messages = StreamIterator(socket.messages);
      socket.send('hello');
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, 'hello');
      socket.send([1, 2, 3]);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, isA<Uint8List>());
      expect(messages.current, [1, 2, 3]);
      socket.send('bye');
      expect(await messages.moveNext(), isFalse);
      expect(socket.closeCode, 4000);
      expect(socket.closeReason, 'asked');
      expect(() => socket.send('late'), throwsA(isA<WebSocketException>()));
    });

    test('client close, refused, rejected and slow handshakes', () async {
      final socket = await transport.connect(base.resolve('/echo'));
      await socket.close(WebSocketStatus.normalClosure, 'done');
      expect(socket.closeCode, WebSocketStatus.normalClosure);

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
      expect(client.protocol, 'v1');

      final received = <Object>[];
      final done = Completer<void>();
      client.messages.listen(received.add, onDone: done.complete);
      final sent = server.onSent.first;
      client.send('{"text":"hi"}');
      expect(await sent, '{"text":"hi"}');
      client.send([7]);
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
      expect(client.closeCode, WebSocketStatus.abnormalClosure);
      expect(server.closedByClient, isFalse);
      expect(() => client.send('x'), throwsA(isA<WebSocketException>()));
    });

    test('failures, client close and connection order', () async {
      final sockets = MockWebSocketTransport()..failNextConnect();
      await expectLater(
        sockets.connect(Uri.parse('ws://h/')),
        throwsA(isA<WebSocketException>()),
      );
      final first = await sockets.connect(Uri.parse('ws://h/1'));
      final second = await sockets.connect(Uri.parse('ws://h/2'));
      expect((await sockets.nextConnection).url.path, '/1');
      expect((await sockets.nextConnection).url.path, '/2');
      await first.close(1000, 'bye');
      expect(sockets.connections.first.closedByClient, isTrue);
      expect(first.closeReason, 'bye');
      await (second as MockWebSocket).closeFromServer(1008);
      expect(second.closeCode, 1008);
      expect(second.closedByClient, isFalse);
    });
  });
}
