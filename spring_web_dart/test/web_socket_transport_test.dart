@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/src/websocket/io_web_socket_transport.dart'
    show heldIncomingMessage;
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
            unawaited(socket.close(4000, 'asked'));
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
      // No permessage-deflate is offered.
      expect(handshakes.last.value('sec-websocket-extensions'), isNull);
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

    // A server that accepts the handshake (with [accept] as its
    // Sec-WebSocket-Accept, the right one by default), then reads nothing.
    Future<io.ServerSocket> stuckServer({String? accept}) async {
      final server = await io.ServerSocket.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((socket) {
        final head = StringBuffer();
        // Paused for good; closing the server ends it.
        // ignore: cancel_subscriptions
        late final StreamSubscription<Uint8List> subscription;
        subscription = socket.listen((chunk) {
          head.write(latin1.decode(chunk));
          final text = head.toString();
          if (!text.contains('\r\n\r\n')) {
            return;
          }
          subscription.pause(); // reads nothing more
          final key = RegExp(
            r'sec-websocket-key: *(\S+)',
            caseSensitive: false,
          ).firstMatch(text)![1]!;
          socket.add(
            latin1.encode(
              'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
              'Connection: Upgrade\r\n'
              'Sec-WebSocket-Accept: ${accept ?? webSocketAccept(key)}'
              '\r\n\r\n',
            ),
          );
        }, onError: (Object _) {});
      });
      return server;
    }

    test('a server that reads nothing: past sendBufferSizeLimit the '
        'session drops the connection (4500)', () async {
      final server = await stuckServer();
      try {
        final session = await IoWebSocketTransport(
          sendBufferSizeLimit: 64 * 1024,
        ).connect(Uri.parse('ws://127.0.0.1:${server.port}/stuck'));
        final ended = session.messages.drain<void>().catchError((Object _) {});
        final chunk = Uint8List(16384);
        var sent = 0;
        while (session.isOpen && sent < 256 << 20) {
          session.sendMessage(chunk);
          sent += chunk.length;
          await Future<void>.delayed(Duration.zero);
        }
        expect(session.isOpen, isFalse);
        expect(sent, lessThan(64 << 20));
        expect(session.closeStatus?.code, 4500);
        expect(
          () => session.sendMessage('late'),
          throwsA(isA<WebSocketException>()),
        );
        await ended.timeout(const Duration(seconds: 10));
      } finally {
        await server.close();
      }
    });

    test('a server that takes nothing within sendTimeLimit: the session '
        'drops the connection', () async {
      final server = await stuckServer();
      try {
        final session = await IoWebSocketTransport(
          sendTimeLimit: const Duration(milliseconds: 300),
        ).connect(Uri.parse('ws://127.0.0.1:${server.port}/stuck'));
        session.sendMessage(Uint8List(32 << 20));
        await session.messages
            .drain<void>()
            .catchError((Object _) {})
            .timeout(
              const Duration(seconds: 10),
            );
        expect(session.closeStatus?.code, 4500);
        expect(session.closeStatus?.reason, contains('Send time'));
      } finally {
        await server.close();
      }
    });

    test('a wrong Sec-WebSocket-Accept is refused', () async {
      final server = await stuckServer(accept: 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=');
      try {
        await expectLater(
          transport.connect(Uri.parse('ws://127.0.0.1:${server.port}/')),
          throwsA(
            isA<WebSocketException>().having(
              (e) => e.message,
              'message',
              contains('Sec-WebSocket-Accept'),
            ),
          ),
        );
      } finally {
        await server.close();
      }
    });

    test('webSocketAccept follows RFC 6455', () {
      expect(
        webSocketAccept('dGhlIHNhbXBsZSBub25jZQ=='),
        's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
      );
    });

    test('platformWebSocketTransport is the dart:io one here', () {
      expect(platformWebSocketTransport(), isA<IoWebSocketTransport>());
    });
  });

  group('IoWebSocketSession: the third review', () {
    test('two peers that both send more than the network holds both get '
        'everything (no deadlock)', () async {
      const total = 2000 * 8000; // far more than the kernel's buffers
      final received = Completer<int>();
      final server = await _guardedServer(
        sendBufferSizeLimit: 64 << 20,
        sendTimeLimit: const Duration(seconds: 5),
        (session) {
          var got = 0;
          session.messages.listen((message) {
            if (message case final String text when text.startsWith('go')) {
              for (var sent = 0; sent < total; sent += 8000) {
                session.sendMessage('s' * 8000);
              }
              return;
            }
            got += (message as String).length;
            if (got >= total && !received.isCompleted) {
              received.complete(got);
            }
          });
        },
      );
      try {
        final session =
            await IoWebSocketTransport(
                  sendBufferSizeLimit: 64 << 20,
                  sendTimeLimit: const Duration(seconds: 5),
                ).connect(Uri.parse('ws://127.0.0.1:${server.port}/'))
                as IoWebSocketSession;
        var got = 0;
        final all = Completer<void>();
        session.messages.listen((message) {
          got += (message as String).length;
          if (got >= total) {
            all.complete();
          }
        }, onDone: () => all.isCompleted ? null : all.complete());
        session.sendMessage('go');
        for (var sent = 0; sent < total; sent += 8000) {
          session.sendMessage('c' * 8000);
        }
        await all.future.timeout(const Duration(seconds: 30));
        expect(session.closeStatus, isNull); // not 4500 after 5 s
        expect(got, total);
        expect(
          await received.future.timeout(const Duration(seconds: 30)),
          total,
        );
        await session.close();
      } finally {
        await server.close(force: true);
      }
    });

    test('a server that resets while the client waits to send: the session '
        'ends (1006), flush fails', () async {
      final server = await _stuckServer(
        resetAfter: const Duration(milliseconds: 500),
      );
      try {
        final session =
            await IoWebSocketTransport(
                  sendBufferSizeLimit: 256 << 20,
                  sendTimeLimit: const Duration(minutes: 1),
                ).connect(Uri.parse('ws://127.0.0.1:${server.port}/'))
                as IoWebSocketSession;
        final ended = session.messages.drain<void>();
        // More than the kernel's buffers: most of it waits in the session.
        session.sendMessage(Uint8List(32 << 20));
        // Expected before anything else is awaited: the flush may fail
        // before the messages end.
        final flushed = expectLater(
          session.flush(),
          throwsA(isA<WebSocketException>()),
        );
        await ended.timeout(const Duration(seconds: 10));
        await session.done.timeout(const Duration(seconds: 10));
        expect(session.isOpen, isFalse);
        expect(session.closeStatus?.code, CloseStatus.noCloseFrame.code);
        await flushed;
        expect(
          () => session.sendMessage('late'),
          throwsA(isA<WebSocketException>()),
        );
      } finally {
        await server.close();
      }
    });

    test('a client that resets while the server waits to send: the server '
        'session ends (1006)', () async {
      final sessions = <IoWebSocketSession>[];
      final server = await _guardedServer(
        (session) {
          sessions.add(session);
          session.sendMessage(Uint8List(32 << 20));
        },
        sendBufferSizeLimit: 256 << 20,
        sendTimeLimit: const Duration(minutes: 1),
      );
      try {
        final (socket, _) = await _rawClient(server.port);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final session = sessions.single;
        final ended = session.messages.drain<void>();
        expect(session.isOpen, isTrue);
        socket.destroy(); // with unread data: a reset
        await ended.timeout(const Duration(seconds: 10));
        await session.done.timeout(const Duration(seconds: 10));
        expect(session.isOpen, isFalse);
        expect(session.closeStatus?.code, CloseStatus.noCloseFrame.code);
      } finally {
        await server.close(force: true);
      }
    });

    test('flush waits until what was sent has left: a sender that awaits '
        'it stays under sendBufferSizeLimit', () async {
      var received = 0;
      final server = await _guardedServer((session) {
        session.messages.listen(
          (message) => received += (message as Uint8List).length,
        );
      });
      try {
        final transport = IoWebSocketTransport(sendBufferSizeLimit: 64 * 1024);
        final session = await transport.connect(
          Uri.parse('ws://127.0.0.1:${server.port}/'),
        ) as IoWebSocketSession;
        final chunk = Uint8List(8000);
        for (var sent = 0; sent < 8 << 20; sent += chunk.length) {
          session.sendMessage(chunk);
          await session.flush();
        }
        expect(session.closeStatus, isNull);
        await until(() => received >= 8 << 20);
        await session.close();

        // The same burst without flush passes the limit.
        final burst = await transport.connect(
          Uri.parse('ws://127.0.0.1:${server.port}/'),
        ) as IoWebSocketSession;
        final ended = burst.messages.drain<void>();
        for (var sent = 0; sent < 8 << 20 && burst.isOpen; sent += 8000) {
          burst.sendMessage(chunk);
        }
        await ended.timeout(const Duration(seconds: 10));
        expect(burst.closeStatus?.code, 4500);
        await expectLater(burst.flush(), throwsA(isA<WebSocketException>()));
      } finally {
        await server.close(force: true);
      }
    });

    test('a handshake answer with a subprotocol or an extension that was not '
        'offered, or a redirect, is refused', () async {
      Future<void> refused(
        String Function(String key) extra, {
        required String because,
        List<String> protocols = const [],
        String status = '101 Switching Protocols',
      }) async {
        final server = await _fakeServer(
          (key) =>
              'HTTP/1.1 $status\r\nUpgrade: websocket\r\n'
              'Connection: Upgrade\r\n'
              'Sec-WebSocket-Accept: ${webSocketAccept(key)}\r\n'
              '${extra(key)}Content-Length: 0\r\n\r\n',
        );
        try {
          await expectLater(
            IoWebSocketTransport().connect(
              Uri.parse('ws://127.0.0.1:${server.port}/'),
              protocols: protocols,
              timeout: const Duration(seconds: 5),
            ),
            throwsA(
              isA<WebSocketException>().having(
                (e) => e.message,
                'message',
                contains(because),
              ),
            ),
          );
        } finally {
          await server.close();
        }
      }

      await refused(
        (_) => 'Sec-WebSocket-Protocol: evil\r\n',
        because: "subprotocol 'evil'",
      );
      await refused(
        (_) => 'Sec-WebSocket-Protocol: evil\r\n',
        protocols: ['chat.v1'],
        because: "subprotocol 'evil'",
      );
      await refused(
        (_) => 'Sec-WebSocket-Protocol: chat.v1, chat.v2\r\n',
        protocols: ['chat.v1', 'chat.v2'],
        because: 'subprotocol',
      );
      await refused(
        (_) => 'Sec-WebSocket-Extensions: permessage-deflate\r\n',
        because: "extension 'permessage-deflate'",
      );
      final elsewhere = await _fakeServer(
        (key) =>
            'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Accept: ${webSocketAccept(key)}\r\n\r\n',
      );
      try {
        await refused(
          (_) => 'Location: http://127.0.0.1:${elsewhere.port}/\r\n',
          status: '302 Found',
          because: 'not upgraded',
        );
      } finally {
        await elsewhere.close();
      }
      // An offered protocol is taken.
      final good = await _fakeServer(
        (key) =>
            'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
            'Connection: Upgrade\r\nSec-WebSocket-Protocol: chat.v2\r\n'
            'Sec-WebSocket-Accept: ${webSocketAccept(key)}\r\n\r\n',
      );
      try {
        final session = await IoWebSocketTransport().connect(
          Uri.parse('ws://127.0.0.1:${good.port}/'),
          protocols: ['chat.v1', 'chat.v2'],
        );
        expect(session.acceptedProtocol, 'chat.v2');
        await session.close().timeout(
          const Duration(milliseconds: 200),
          onTimeout: () {},
        );
      } finally {
        await good.close();
      }
    });

    test('a message from the server over maxTextMessageSize or '
        'maxBinaryMessageSize (8 KB) closes the session with 1009', () async {
      // The server sends [frames], then answers the client's close frame.
      Future<(List<Object>, CloseStatus?, int?)> receive(
        List<List<int>> frames, {
        IoWebSocketTransport? transport,
      }) async {
        final closeCodes = <int>[];
        final server = await _fakeServer(
          (key) =>
              'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
              'Connection: Upgrade\r\n'
              'Sec-WebSocket-Accept: ${webSocketAccept(key)}\r\n\r\n',
          then: (socket, incoming) {
            frames.forEach(socket.add);
            incoming.listen((frame) {
              if (frame.$1 == 8) {
                closeCodes.add(frame.$2[0] << 8 | frame.$2[1]);
                socket.add(_frame(8, frame.$2));
              }
            });
          },
        );
        try {
          final session = await (transport ?? IoWebSocketTransport()).connect(
            Uri.parse('ws://127.0.0.1:${server.port}/'),
          );
          final messages = await session.messages.toList().timeout(
            const Duration(seconds: 10),
          );
          return (messages, session.closeStatus, closeCodes.firstOrNull);
        } finally {
          await server.close();
        }
      }

      final fits = 'a' * 8192;
      var (messages, status, sent) = await receive([
        _frame(1, utf8.encode(fits)),
        _frame(1, utf8.encode('${fits}b')),
        _frame(1, utf8.encode('never read')),
      ]);
      expect(messages, [fits]);
      expect(status?.code, 1009);
      expect(sent, 1009);

      // In many frames: stopped at the frame that passes the limit.
      (messages, status, sent) = await receive([
        _frame(1, List.filled(4000, 0x61), fin: false),
        _frame(0, List.filled(4000, 0x61), fin: false),
        _frame(0, List.filled(4000, 0x61)),
      ]);
      expect(messages, isEmpty);
      expect(status?.code, 1009);

      (messages, status, sent) = await receive([_frame(2, Uint8List(8193))]);
      expect(messages, isEmpty);
      expect(status?.code, 1009);

      // Raised (or -1, no limit).
      (messages, status, sent) = await receive(
        [
          _frame(1, utf8.encode('${fits}b')),
          _frame(2, Uint8List(1 << 20)),
          _frame(8, [0x03, 0xE8]), // the server closes: 1000
        ],
        transport: IoWebSocketTransport(
          maxTextMessageSize: 16 * 1024,
          maxBinaryMessageSize: -1,
        ),
      );
      expect(messages, hasLength(2));
      expect(status?.code, 1000);
    });

    test('platformWebSocketTransport passes the message size limits', () {
      final defaults = platformWebSocketTransport() as IoWebSocketTransport;
      expect(defaults.maxTextMessageSize, 8192);
      expect(defaults.maxBinaryMessageSize, 8192);
      final raised = platformWebSocketTransport(
        maxTextMessageSize: 1 << 20,
        maxBinaryMessageSize: -1,
      ) as IoWebSocketTransport;
      expect(raised.maxTextMessageSize, 1 << 20);
      expect(raised.maxBinaryMessageSize, -1);
    });
  });

  group('IoWebSocketSession: the fourth review', () {
    test('a session made right after a handshake answer written by hand '
        'sends its first messages; flush and close complete', () async {
      // The answer still waits in the socket when the session takes it
      // over: the socket takes the session's output only once it is out.
      final flushed = Completer<String>();
      final server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((request) async {
        final key = request.headers.value('Sec-WebSocket-Key')!;
        final socket = await request.response.detachSocket(
          writeHeaders: false,
        );
        socket.add(latin1.encode(_accepted(key)));
        final session = IoWebSocketSession.fromUpgradedSocket(
          socket,
          request.requestedUri.replace(scheme: 'ws'),
          serverSide: true,
        );
        session.messages.listen((_) {});
        session
          ..sendMessage('hello')
          ..sendMessage(Uint8List.fromList([1, 2, 3]));
        flushed.complete(
          session
              .flush()
              .then((_) => 'flushed')
              .timeout(const Duration(seconds: 5), onTimeout: () => 'stuck'),
        );
        await flushed.future;
        await session.close(const CloseStatus(4000, 'done'));
      });
      try {
        final session = await IoWebSocketTransport().connect(
          Uri.parse('ws://127.0.0.1:${server.port}/'),
        );
        final messages = await session.messages.toList().timeout(
          const Duration(seconds: 10),
          onTimeout: () => const ['nothing'],
        );
        expect(await flushed.future, 'flushed');
        expect(messages, [
          'hello',
          [1, 2, 3],
        ]);
        expect(session.closeStatus, const CloseStatus(4000, 'done'));
      } finally {
        await server.close(force: true);
      }
    });

    test("a socket that never takes the session's output (what was added "
        'to it before does not leave): dropped with 4500 after '
        'sendTimeLimit, not stuck', () async {
      final listener = await io.ServerSocket.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      final accepted = listener.first;
      final peer = await io.Socket.connect('127.0.0.1', listener.port);
      try {
        final socket = await accepted;
        // More than the kernel's buffers, for a peer that reads nothing.
        socket.add(Uint8List(32 << 20));
        final session = IoWebSocketSession.fromUpgradedSocket(
          socket,
          Uri.parse('ws://127.0.0.1:${listener.port}/'),
          serverSide: true,
          sendTimeLimit: const Duration(milliseconds: 500),
        );
        final ended = session.messages.drain<void>();
        session.sendMessage('hello');
        final flushFails = expectLater(
          session.flush(),
          throwsA(isA<WebSocketException>()),
        );
        await session.done.timeout(const Duration(seconds: 10));
        expect(session.closeStatus?.code, CloseStatus.sessionNotReliable.code);
        expect(session.closeStatus?.reason, contains('Send time'));
        expect(session.isOpen, isFalse);
        await flushFails;
        await ended.timeout(const Duration(seconds: 10));
      } finally {
        peer.destroy();
        await listener.close();
      }
    });

    // The server sends [frames] (and [rest] once the client has answered
    // the first ping), echoes a close frame, and records what the client
    // sends.
    Future<(List<Object>, CloseStatus?, List<(int, List<int>)>)> receive(
      List<List<int>> frames, {
      List<List<int>> rest = const [],
      IoWebSocketTransport? transport,
    }) async {
      final sent = <(int, List<int>)>[];
      final server = await _fakeServer(
        _accepted,
        then: (socket, incoming) {
          frames.forEach(socket.add);
          incoming.listen((frame) {
            sent.add(frame);
            if (frame.$1 == 10 && sent.where((f) => f.$1 == 10).length == 1) {
              rest.forEach(socket.add);
            } else if (frame.$1 == 8) {
              socket.add(_frame(8, frame.$2));
            }
          });
        },
      );
      try {
        final session = await (transport ?? IoWebSocketTransport()).connect(
          Uri.parse('ws://127.0.0.1:${server.port}/'),
        );
        final messages = await session.messages.toList().timeout(
          const Duration(seconds: 10),
        );
        return (messages, session.closeStatus, sent);
      } finally {
        await server.close();
      }
    }

    final a = List.filled(1024, 0x61);
    final b = List.filled(1024, 0x62);
    final close1000 = _frame(8, [0x03, 0xE8]);

    test('a ping or a pong between the fragments of a message from the '
        'server: the message arrives whole, and the ping is answered at '
        'once with its own payload; with or without size limits', () async {
      for (final transport in [
        IoWebSocketTransport(),
        IoWebSocketTransport(maxTextMessageSize: -1, maxBinaryMessageSize: -1),
      ]) {
        // The rest of the message comes only after the pong.
        var (messages, status, sent) = await receive(
          [
            _frame(1, a, fin: false),
            _frame(9, [1, 2, 3]),
          ],
          rest: [_frame(0, b), close1000],
          transport: transport,
        );
        expect(messages, ['a' * 1024 + 'b' * 1024]);
        expect(status?.code, 1000);
        expect(sent.first.$1, 10);
        expect(sent.first.$2, [1, 2, 3]);

        // Three fragments, a pong (unasked) and an empty ping between.
        (messages, status, sent) = await receive([
          _frame(2, a, fin: false),
          _frame(10, [9]),
          _frame(0, b, fin: false),
          _frame(9, []),
          _frame(0, a),
          _frame(1, utf8.encode('next')),
          close1000,
        ], transport: transport);
        expect(messages, [
          [...a, ...b, ...a],
          'next',
        ]);
        expect(sent.first.$1, 10);
        expect(sent.first.$2, isEmpty);
      }

      // The size limit still counts the whole message: 8193 bytes with a
      // ping in the middle is too big.
      final (messages, status, sent) = await receive([
        _frame(1, List.filled(4096, 0x61), fin: false),
        _frame(9, [7]),
        _frame(0, List.filled(4097, 0x61)),
      ]);
      expect(messages, isEmpty);
      expect(status?.code, 1009);
      expect(sent.map((f) => f.$1), [10, 8]);
      expect(sent.first.$2, [7]);
    });

    test('a close between the fragments of a message from the server ends '
        'the session at once with its code; the unfinished message is '
        'dropped', () async {
      for (final transport in [
        IoWebSocketTransport(),
        IoWebSocketTransport(maxTextMessageSize: -1, maxBinaryMessageSize: -1),
      ]) {
        final (messages, status, sent) = await receive([
          _frame(1, a, fin: false),
          _frame(8, [0x0F, 0xA0, ...utf8.encode('bye')]), // 4000
        ], transport: transport);
        expect(messages, isEmpty);
        expect(status, const CloseStatus(4000, 'bye'));
        expect(sent.single.$1, 8); // the answer
        expect(sent.single.$2.take(2), [0x0F, 0xA0]);
      }
    });

    test("a client's masked fragments with pings and pongs between, in "
        'pieces of one byte: the server session gets each message whole, '
        'the client the right pongs; a close between fragments ends the '
        'session', () async {
      final sessions = StreamController<IoWebSocketSession>();
      final server = await _guardedServer(sessions.add);
      final next = StreamIterator(sessions.stream);
      try {
        final (socket, frames) = await _frameClient(server.port);
        expect(await next.moveNext(), isTrue);
        final session = next.current;
        final received = <Object>[];
        final ended = Completer<void>();
        session.messages.listen(received.add, onDone: ended.complete);
        final pongs = <List<int>>[];
        final closes = <List<int>>[];
        frames.listen((frame) {
          if (frame.$1 == 10) {
            pongs.add(frame.$2);
          } else if (frame.$1 == 8) {
            closes.add(frame.$2);
          }
        });
        Future<void> send(List<List<int>> frames) async {
          for (final byte in frames.expand((frame) => frame)) {
            socket.add([byte]);
            await socket.flush();
          }
        }

        await send([
          _frame(1, List.filled(200, 0x61), fin: false, mask: true),
          _frame(9, [1, 2], mask: true),
        ]);
        // Answered before the message ends.
        await until(() => pongs.isNotEmpty);
        expect(pongs, [
          [1, 2],
        ]);
        await send([
          _frame(0, List.filled(200, 0x62), fin: false, mask: true),
          _frame(10, [9], mask: true),
          _frame(0, List.filled(200, 0x63), mask: true),
          _frame(2, [4, 5, 6], mask: true),
          _frame(1, List.filled(300, 0x64), fin: false, mask: true),
          _frame(8, [0x03, 0xE8], mask: true), // 1000, mid-message
        ]);
        await ended.future.timeout(const Duration(seconds: 10));
        expect(received, [
          'a' * 200 + 'b' * 200 + 'c' * 200,
          [4, 5, 6],
        ]);
        expect(session.closeStatus?.code, 1000);
        await until(() => closes.isNotEmpty);
        expect(closes.single.take(2), [0x03, 0xE8]); // the answer
        expect(pongs, hasLength(1));
        socket.destroy();
      } finally {
        await next.cancel();
        await server.close(force: true);
      }
    });

    test('after close(), while the other side has not answered: isOpen is '
        'false and sendMessage throws a WebSocketException, on the client, '
        'the server and a plain dart:io WebSocket', () async {
      void closing(WebSocketSession session, int code) {
        unawaited(session.close(CloseStatus(code)).catchError((Object _) {}));
        expect(session.isOpen, isFalse);
        expect(session.closeStatus?.code, code);
        expect(
          () => session.sendMessage('late'),
          throwsA(isA<WebSocketException>()),
        );
        expect(
          () => session.sendMessage([1]),
          throwsA(isA<WebSocketException>()),
        );
      }

      // A server that never answers the close frame.
      final sockets = <io.Socket>[];
      final silent = await _fakeServer(
        _accepted,
        then: (socket, _) => sockets.add(socket),
      );
      final sessions = <IoWebSocketSession>[];
      final guarded = await _guardedServer(sessions.add);
      try {
        final client = await IoWebSocketTransport().connect(
          Uri.parse('ws://127.0.0.1:${silent.port}/'),
        );
        client.messages.listen((_) {});
        expect(client.isOpen, isTrue);
        closing(client, 1000);

        final plain = IoWebSocketSession(
          await io.WebSocket.connect('ws://127.0.0.1:${silent.port}/'),
          Uri.parse('ws://127.0.0.1:${silent.port}/'),
        );
        plain.messages.listen((_) {});
        expect(plain.isOpen, isTrue);
        closing(plain, 4001);

        // A client that reads nothing.
        final (socket, _) = await _rawClient(guarded.port);
        await until(() => sessions.isNotEmpty);
        final server = sessions.single;
        server.messages.listen((_) {});
        expect(server.isOpen, isTrue);
        closing(server, 1001);
        socket.destroy();
      } finally {
        for (final socket in sockets) {
          socket.destroy();
        }
        await silent.close();
        await guarded.close(force: true);
      }
    });
  });

  group('IoWebSocketSession: the fifth review', () {
    final close1000 = _frame(8, [0x03, 0xE8]);

    test('a client that sends a message in hundreds of thousands of empty '
        'fragments: the server session holds the payload and nothing per '
        'fragment, with or without a size limit; the message arrives '
        'whole', () async {
      for (final limit in [IoWebSocketSession.defaultMaxMessageSize, -1]) {
        final pair = await _Pair.open(maxMessageSize: limit);
        try {
          await pair.send(_frame(1, [0x61], fin: false, mask: true));
          await pair.send(
            _repeat(_frame(0, [], fin: false, mask: true), 300000),
          );
          await pair.sync();
          final held = heldIncomingMessage(pair.session);
          expect(held.buffers, 1);
          expect(held.bytes, inInclusiveRange(1, 1024));
          await pair.send(_frame(0, [0x62], mask: true));
          await until(() => pair.received.isNotEmpty);
          expect(pair.received, ['ab']);
          expect(heldIncomingMessage(pair.session), (bytes: 0, buffers: 0));
          expect(pair.session.isOpen, isTrue);
        } finally {
          await pair.close();
        }
      }
    });

    test('a server that sends a message in hundreds of thousands of empty '
        'fragments: the client holds the payload and nothing per '
        'fragment', () async {
      final pong = Completer<List<int>>();
      final sockets = <io.Socket>[];
      final server = await _fakeServer(
        _accepted,
        then: (socket, frames) {
          sockets.add(socket);
          socket
            ..add(_frame(1, [0x61], fin: false))
            ..add(_repeat(_frame(0, [], fin: false), 300000))
            ..add(_frame(9, [5]));
          frames.listen((frame) {
            if (frame.$1 == 10 && !pong.isCompleted) {
              pong.complete(frame.$2);
            } else if (frame.$1 == 8) {
              socket.add(_frame(8, frame.$2));
            }
          });
        },
      );
      try {
        final session = await IoWebSocketTransport().connect(
          Uri.parse('ws://127.0.0.1:${server.port}/'),
        ) as IoWebSocketSession;
        final received = <Object>[];
        session.messages.listen(received.add);
        // Answered once all the empty fragments before it are read.
        expect(await pong.future.timeout(const Duration(seconds: 20)), [5]);
        final held = heldIncomingMessage(session);
        expect(held.buffers, 1);
        expect(held.bytes, inInclusiveRange(1, 1024));
        sockets.single.add(_frame(0, [0x62]));
        await until(() => received.isNotEmpty);
        expect(received, ['ab']);
        expect(heldIncomingMessage(session), (bytes: 0, buffers: 0));
        await session.close();
      } finally {
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    });

    test('a message from the server in fragments of many sizes, a ping '
        'between: the client gets it intact, whatever the length of what '
        'was held', () async {
      final transport = IoWebSocketTransport(
        maxTextMessageSize: -1,
        maxBinaryMessageSize: -1,
      );
      for (final sizes in [
        [3, 0, 50], // 3 bytes held: a 7-bit length
        [100, 0, 1000, 1], // 16 bits
        [100, 0, 70000, 1, 30000], // 64 bits
      ]) {
        var seed = sizes.length;
        final parts = [
          for (final size in sizes)
            [for (var j = 0; j < size; j++) (seed = seed * 31 + 7) & 0xFF],
        ];
        final pongs = <List<int>>[];
        final server = await _fakeServer(
          _accepted,
          then: (socket, frames) {
            for (var i = 0; i < parts.length; i++) {
              socket.add(
                _frame(i == 0 ? 2 : 0, parts[i], fin: i == parts.length - 1),
              );
              if (i == 1) {
                socket.add(_frame(9, [3]));
              }
            }
            socket.add(close1000);
            frames.listen((frame) {
              if (frame.$1 == 10) {
                pongs.add(frame.$2);
              }
            });
          },
        );
        try {
          final session = await transport.connect(
            Uri.parse('ws://127.0.0.1:${server.port}/'),
          );
          final messages = await session.messages.toList().timeout(
            const Duration(seconds: 10),
          );
          expect(messages, [parts.expand((part) => part).toList()]);
          await until(() => pongs.isNotEmpty);
          expect(pongs.single, [3]);
        } finally {
          await server.close();
        }
      }
    });

    test('a message in one-byte fragments is held as one payload, not one '
        'buffer per fragment; exactly the limit arrives, one byte more '
        'closes the session with 1009', () async {
      final pair = await _Pair.open();
      try {
        final text = [for (var i = 0; i < 8192; i++) 0x61 + i % 26];
        final wire = BytesBuilder();
        for (var i = 0; i < 8191; i++) {
          wire.add(
            _frame(
              i == 0 ? 1 : 0,
              [text[i]],
              fin: false,
              mask: true,
              key: [i & 0xFF, 0x5A, i >> 8, 0xC3],
            ),
          );
        }
        await pair.send(wire.takeBytes());
        await pair.sync();
        final held = heldIncomingMessage(pair.session);
        expect(held.bytes, inInclusiveRange(8191, 2 * 8192));
        expect(held.buffers, lessThanOrEqualTo(8));
        await pair.send(_frame(0, [text.last], mask: true));
        await until(() => pair.received.isNotEmpty);
        expect(pair.received, [String.fromCharCodes(text)]);

        for (var i = 0; i < 8193; i++) {
          wire.add(
            _frame(i == 0 ? 2 : 0, [i & 0xFF], fin: i == 8192, mask: true),
          );
        }
        await pair.send(wire.takeBytes());
        await pair.ended;
        expect(pair.received, hasLength(1));
        expect(pair.session.closeStatus?.code, 1009);
        expect(heldIncomingMessage(pair.session), (bytes: 0, buffers: 0));
      } finally {
        await pair.close();
      }
    });

    test('without a size limit, 200000 one-byte fragments are held as '
        'their payload in a few buffers, and the message arrives '
        'intact', () async {
      final pair = await _Pair.open(maxMessageSize: -1);
      try {
        const count = 200000;
        final wire = BytesBuilder();
        for (var i = 0; i < count; i++) {
          wire.add(
            _frame(
              i == 0 ? 2 : 0,
              [i & 0xFF],
              fin: false,
              mask: true,
              key: [i & 0xFF, i >> 8 & 0xFF, 0x11, 0x99],
            ),
          );
        }
        await pair.send(wire.takeBytes());
        await pair.sync();
        final held = heldIncomingMessage(pair.session);
        expect(held.bytes, inInclusiveRange(count, count + 65536));
        expect(held.buffers, lessThanOrEqualTo(16));
        await pair.send(_frame(0, [7], mask: true));
        await until(() => pair.received.isNotEmpty);
        final message = pair.received.single as List<int>;
        expect(message, hasLength(count + 1));
        expect([
          for (var i = 0; i < count; i++)
            if (message[i] != i & 0xFF) i,
        ], isEmpty);
        expect(message.last, 7);
      } finally {
        await pair.close();
      }
    });

    test('fragments of many sizes and mask keys, split across reads at odd '
        'places, arrive intact; a character split between fragments is '
        'decoded, and invalid UTF-8 across fragments closes with '
        '1007', () async {
      final pair = await _Pair.open(maxMessageSize: -1);
      try {
        var seed = 1;
        int next() => (seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF) >> 8;
        const sizes = [1, 15, 16, 17, 31, 0, 33, 100, 1000, 3, 4096, 70000, 5];
        final payload = <int>[];
        final wire = BytesBuilder();
        for (var i = 0; i < sizes.length; i++) {
          final part = [for (var j = 0; j < sizes[i]; j++) next() & 0xFF];
          payload.addAll(part);
          wire.add(
            _frame(
              i == 0 ? 2 : 0,
              part,
              fin: i == sizes.length - 1,
              mask: true,
              key: [for (var k = 0; k < 4; k++) next() & 0xFF],
            ),
          );
        }
        // 'aé😀b': é split between two fragments, 😀 among three.
        wire
          ..add(_frame(1, [0x61, 0xC3], fin: false, mask: true))
          ..add(_frame(0, [0xA9, 0xF0, 0x9F], fin: false, mask: true))
          ..add(_frame(0, [0x98], fin: false, mask: true))
          ..add(_frame(0, [0x80, 0x62], mask: true));
        final bytes = wire.takeBytes();
        for (var i = 0; i < bytes.length; i += 4093) {
          await pair.send(bytes.sublist(i, min(i + 4093, bytes.length)));
        }
        await until(() => pair.received.length == 2);
        expect(pair.received.first, payload);
        expect(pair.received.last, 'aé😀b');

        await pair.send([
          ..._frame(1, [0x61, 0xC3], fin: false, mask: true),
          ..._frame(0, [0x28], mask: true),
        ]);
        await pair.ended;
        expect(pair.received, hasLength(2));
        expect(pair.session.closeStatus?.code, 1007);
      } finally {
        await pair.close();
      }
    });

    test('a malformed frame after held fragments still fails the '
        'connection with 1002', () async {
      final reserved = _frame(0, [0x62], mask: true);
      reserved[0] |= 0x40; // RSV1: no extension was negotiated
      for (final bad in [
        _frame(1, [0x62], mask: true), // a new message before the end
        reserved,
        _frame(0, [0x62]), // not masked, from a client
      ]) {
        final pair = await _Pair.open();
        try {
          await pair.send([
            ..._frame(1, [0x61], fin: false, mask: true),
            ..._frame(0, [], fin: false, mask: true),
            ...bad,
          ]);
          await pair.ended;
          expect(pair.received, isEmpty);
          expect(pair.session.closeStatus?.code, 1002);
        } finally {
          await pair.close();
        }
      }
    });
  });

  group('IoWebSocketSession: the sixth review', () {
    const reset = io.SocketException(
      'Connection reset by peer',
      osError: io.OSError('Connection reset by peer', 54),
    );

    // The session over a socket whose write or read fails on demand;
    // `sendMessage` starts dart:io's output first.
    Future<(IoWebSocketSession, _FailingSocket, Future<void>)> open({
      required bool serverSide,
    }) async {
      final socket = _FailingSocket();
      final session = IoWebSocketSession.fromUpgradedSocket(
        socket,
        Uri.parse('ws://h/'),
        serverSide: serverSide,
      );
      final ended = session.messages
          .drain<void>()
          .catchError((Object _) {})
          .timeout(const Duration(seconds: 5));
      session.sendMessage('x');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return (session, socket, ended);
    }

    test('a reset the write meets first keeps the error as the reason '
        '(1006), as one the read meets first', () async {
      for (final serverSide in [true, false]) {
        for (final writeFirst in [true, false]) {
          final (session, socket, ended) = await open(serverSide: serverSide);
          if (writeFirst) {
            // The session destroys the socket: the input just ends.
            socket.failWrite(reset);
          } else {
            socket.failRead(reset);
          }
          await ended;
          expect(
            session.closeStatus,
            CloseStatus.noCloseFrame.withReason('Connection reset by peer'),
            reason: 'serverSide: $serverSide, writeFirst: $writeFirst',
          );
          expect(session.isOpen, isFalse);
        }
      }
    });

    test('after a close from this side, a reset the write meets keeps '
        'the status passed to close', () async {
      final (session, socket, ended) = await open(serverSide: true);
      final closing = session.close(CloseStatus.goingAway.withReason('bye'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      socket.failWrite(reset);
      await ended;
      await closing.timeout(const Duration(seconds: 5), onTimeout: () {});
      expect(session.closeStatus, CloseStatus.goingAway.withReason('bye'));
    });
  });

  group('IoWebSocketSession: the seventh review', () {
    test('a session closed before anyone listens to its messages (dart:io '
        'drained them, and the later listen threw): they end once the close '
        'is done, what came meanwhile dropped, on the server, the client and '
        'a plain dart:io WebSocket', () async {
      // Listens to [session] after [delay]: the messages and the status at
      // their end.
      Future<(List<Object>, CloseStatus?)> later(
        WebSocketSession session, {
        Duration delay = const Duration(milliseconds: 100),
      }) async {
        await Future<void>.delayed(delay);
        final got = <Object>[];
        await session.messages
            .forEach(got.add)
            .timeout(const Duration(seconds: 5));
        return (got, session.closeStatus);
      }

      final sessions = <IoWebSocketSession>[];
      final guarded = await _guardedServer(sessions.add);
      final echo = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      echo.listen((request) async {
        final socket = await io.WebSocketTransformer.upgrade(request);
        socket.listen(socket.add);
      });
      try {
        // The server closes a session before listening; the client sent a
        // message first.
        final client = await io.WebSocket.connect(
          'ws://127.0.0.1:${guarded.port}/',
        );
        client.add('early');
        await until(() => sessions.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final server = sessions.single;
        await server
            .close(CloseStatus.policyViolation.withReason('no'))
            .timeout(const Duration(seconds: 5));
        expect(await client.drain<void>().then((_) => client.closeCode), 1008);
        final (got, status) = await later(server);
        expect(got, isEmpty);
        expect(status, CloseStatus.policyViolation.withReason('no'));

        // The client side.
        final session = await IoWebSocketTransport().connect(
          Uri.parse('ws://127.0.0.1:${echo.port}/'),
        );
        await session
            .close(const CloseStatus(4002, 'bye'))
            .timeout(const Duration(seconds: 5));
        final (gotClient, statusClient) = await later(session);
        expect(gotClient, isEmpty);
        expect(statusClient, const CloseStatus(4002, 'bye'));

        // A plain dart:io WebSocket.
        final plain = IoWebSocketSession(
          await io.WebSocket.connect('ws://127.0.0.1:${echo.port}/'),
          Uri.parse('ws://127.0.0.1:${echo.port}/'),
        );
        await plain.close().timeout(const Duration(seconds: 5));
        final (gotPlain, statusPlain) = await later(plain);
        expect(gotPlain, isEmpty);
        expect(statusPlain, CloseStatus.normal);

        // Listened to before the close: the messages arrive as usual.
        final open = await IoWebSocketTransport().connect(
          Uri.parse('ws://127.0.0.1:${echo.port}/'),
        );
        final replies = StreamIterator(open.messages);
        open.sendMessage('one');
        expect(await replies.moveNext(), isTrue);
        expect(replies.current, 'one');
        await open.close();
        expect(await replies.moveNext(), isFalse);
      } finally {
        await guarded.close(force: true);
        await echo.close(force: true);
      }
    });

    const reset = io.SocketException(
      'Connection reset by peer',
      osError: io.OSError('Connection reset by peer', 54),
    );

    // A session over a socket the test drives, its output started; the
    // status [closeStatus] gives when [messages] ends, and when.
    (IoWebSocketSession, _FailingSocket, Future<(CloseStatus?, Duration)>)
    open({required bool serverSide}) {
      final socket = _FailingSocket();
      final session = IoWebSocketSession.fromUpgradedSocket(
        socket,
        Uri.parse('ws://h/'),
        serverSide: serverSide,
      );
      final ended = Completer<(CloseStatus?, Duration)>();
      final watch = Stopwatch();
      session.messages.listen(
        (_) {},
        onError: (Object _) {},
        onDone: () => ended.complete((session.closeStatus, watch.elapsed)),
      );
      session.sendMessage('x');
      watch.start();
      return (
        session,
        socket,
        ended.future.timeout(const Duration(seconds: 5)),
      );
    }

    test(
      'the input ends cleanly before the write fails (TLS): messages ends '
      'after the write, closeStatus has the error as the reason (1006)',
      () async {
        for (final serverSide in [true, false]) {
          final (_, socket, ended) = open(serverSide: serverSide);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          socket.endInput();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          socket.failWrite(reset);
          final (status, _) = await ended;
          expect(
            status,
            CloseStatus.noCloseFrame.withReason('Connection reset by peer'),
            reason: 'serverSide: $serverSide',
          );
        }
      },
    );

    test('after close(4001), the input ends without an answer: closeStatus '
        'is 4001, whether the write then fails or not', () async {
      for (final fails in [true, false]) {
        final (session, socket, ended) = open(serverSide: true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        unawaited(
          session.close(const CloseStatus(4001, 'bye')).catchError((_) {}),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        socket.endInput();
        if (fails) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          socket.failWrite(reset);
        }
        final (status, _) = await ended;
        expect(status, const CloseStatus(4001, 'bye'), reason: 'fails: $fails');
        expect(session.closeStatus, const CloseStatus(4001, 'bye'));
      }
    });

    test('the wait for the write is bounded: a write that never ends lets '
        'messages end a second later, with 1006', () async {
      final (_, socket, ended) = open(serverSide: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      socket.endInput();
      final (status, elapsed) = await ended;
      expect(status, CloseStatus.noCloseFrame);
      expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      expect(elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  test("CloseStatus: Spring's constants, withReason, equalsCode", () {
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

Future<void> until(bool Function() condition, {int seconds = 20}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > Duration(seconds: seconds)) {
      fail('timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A server that answers each handshake by hand and wraps the connection
/// in an [IoWebSocketSession] (as the web starter does) for [onSession].
Future<io.HttpServer> _guardedServer(
  void Function(IoWebSocketSession session) onSession, {
  int sendBufferSizeLimit = IoWebSocketSession.defaultSendBufferSizeLimit,
  Duration? sendTimeLimit = IoWebSocketSession.defaultSendTimeLimit,
  int maxMessageSize = IoWebSocketSession.defaultMaxMessageSize,
}) async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final key = request.headers.value('Sec-WebSocket-Key')!;
    final response = request.response
      ..statusCode = io.HttpStatus.switchingProtocols
      ..headers.set(io.HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.set(io.HttpHeaders.upgradeHeader, 'websocket')
      ..headers.set('Sec-WebSocket-Accept', webSocketAccept(key))
      ..headers.contentLength = 0;
    final socket = await response.detachSocket();
    onSession(
      IoWebSocketSession.fromUpgradedSocket(
        socket,
        request.requestedUri.replace(scheme: 'ws'),
        serverSide: true,
        sendBufferSizeLimit: sendBufferSizeLimit,
        sendTimeLimit: sendTimeLimit,
        maxTextMessageSize: maxMessageSize,
        maxBinaryMessageSize: maxMessageSize,
      ),
    );
  });
  return server;
}

/// A server that accepts the handshake, then reads nothing; after
/// [resetAfter] it drops the connection, with unread data: a reset.
Future<io.ServerSocket> _stuckServer({required Duration resetAfter}) =>
    _fakeServer(
      (key) =>
          'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Accept: ${webSocketAccept(key)}\r\n\r\n',
      readFrames: false,
      then: (socket, _) => Timer(resetAfter, socket.destroy),
    );

/// A raw server: it answers the first handshake of each connection with
/// [answer] (given the key), then calls [then] with the socket and the
/// frames the client sends (opcode, unmasked payload), unless
/// [readFrames] is false: then it reads nothing more.
Future<io.ServerSocket> _fakeServer(
  String Function(String key) answer, {
  void Function(io.Socket socket, Stream<(int, List<int>)> frames)? then,
  bool readFrames = true,
}) async {
  final server = await io.ServerSocket.bind(
    io.InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((socket) {
    // A write after the client went away fails here; nobody waits for it.
    socket.done.ignore();
    final buffer = BytesBuilder();
    final frames = StreamController<(int, List<int>)>();
    var answered = false;
    // Paused for good, or ended by the socket.
    // ignore: cancel_subscriptions
    late final StreamSubscription<Uint8List> subscription;
    subscription = socket.listen(
      (chunk) {
        buffer.add(chunk);
        if (!answered) {
          final text = latin1.decode(buffer.toBytes());
          final end = text.indexOf('\r\n\r\n');
          if (end < 0) {
            return;
          }
          answered = true;
          final rest = buffer.toBytes().sublist(end + 4);
          buffer
            ..clear()
            ..add(rest);
          final key =
              RegExp(
                r'sec-websocket-key: *(\S+)',
                caseSensitive: false,
              ).firstMatch(text)?[1] ??
              '';
          socket.add(latin1.encode(answer(key)));
          if (!readFrames) {
            subscription.pause();
          }
          then?.call(socket, frames.stream);
        }
        _takeFrames(buffer).forEach(frames.add);
      },
      onError: (Object _) {},
      onDone: frames.close,
    );
  });
  return server;
}

/// An unmasked frame, as a server sends it, or a masked one ([mask]), as
/// a client sends it, with the mask [key].
List<int> _frame(
  int opcode,
  List<int> payload, {
  bool fin = true,
  bool mask = false,
  List<int> key = const [0x37, 0xFA, 0x21, 0x3D],
}) {
  final length = payload.length;
  return [
    (fin ? 0x80 : 0) | opcode,
    (mask ? 0x80 : 0) | (length < 126 ? length : (length < 65536 ? 126 : 127)),
    if (length >= 126 && length < 65536) ...[length >> 8, length & 0xFF],
    if (length >= 65536)
      for (var shift = 56; shift >= 0; shift -= 8) (length >> shift) & 0xFF,
    if (mask) ...[
      ...key,
      for (var i = 0; i < length; i++) payload[i] ^ key[i % 4],
    ] else
      ...payload,
  ];
}

/// The complete frames at the start of [buffer] (opcode, unmasked
/// payload), masked or not; what is left of an incomplete one stays.
List<(int, List<int>)> _takeFrames(BytesBuilder buffer) {
  final frames = <(int, List<int>)>[];
  var bytes = buffer.toBytes();
  while (bytes.length >= 2) {
    final masked = (bytes[1] & 0x80) != 0;
    var length = bytes[1] & 0x7F;
    var start = 2;
    if (length == 126) {
      if (bytes.length < 4) {
        break;
      }
      length = bytes[2] << 8 | bytes[3];
      start = 4;
    } else if (length == 127) {
      if (bytes.length < 10) {
        break;
      }
      length = 0;
      for (var i = 2; i < 10; i++) {
        length = length << 8 | bytes[i];
      }
      start = 10;
    }
    final mask = masked ? start : -1;
    if (masked) {
      start += 4;
    }
    if (bytes.length < start + length) {
      break;
    }
    frames.add((
      bytes[0] & 0x0F,
      [
        for (var i = 0; i < length; i++)
          if (masked)
            bytes[start + i] ^ bytes[mask + i % 4]
          else
            bytes[start + i],
      ],
    ));
    bytes = bytes.sublist(start + length);
  }
  buffer
    ..clear()
    ..add(bytes);
  return frames;
}

/// [frame] [times] over, in one list.
Uint8List _repeat(List<int> frame, int times) {
  final bytes = Uint8List(frame.length * times);
  for (var i = 0; i < times; i++) {
    bytes.setRange(i * frame.length, (i + 1) * frame.length, frame);
  }
  return bytes;
}

/// A server session (wrapped as the web starter does) and a raw client
/// that sends it frames: what the session receives, and the pongs the
/// client gets back. The client answers a close frame.
final class _Pair {
  _Pair._(this.server, this.session, this.socket);

  static Future<_Pair> open({
    int maxMessageSize = IoWebSocketSession.defaultMaxMessageSize,
  }) async {
    final opened = Completer<IoWebSocketSession>();
    final server = await _guardedServer(
      opened.complete,
      maxMessageSize: maxMessageSize,
    );
    final (socket, frames) = await _frameClient(server.port);
    final pair = _Pair._(
      server,
      await opened.future.timeout(const Duration(seconds: 10)),
      socket,
    );
    pair.session.messages.listen(
      pair.received.add,
      onDone: pair._ended.complete,
    );
    // A write after the server went away fails there; nobody waits for it.
    socket.done.ignore();
    frames.listen((frame) {
      if (frame.$1 == 10) {
        pair.pongs.add(frame.$2);
      } else if (frame.$1 == 8) {
        socket.add(_frame(8, frame.$2, mask: true)); // the answer
      }
    });
    return pair;
  }

  final io.HttpServer server;
  final IoWebSocketSession session;
  final io.Socket socket;
  final received = <Object>[];
  final pongs = <List<int>>[];
  final _ended = Completer<void>();

  /// Completes when the session's messages end.
  Future<void> get ended => _ended.future.timeout(const Duration(seconds: 10));

  Future<void> send(List<int> bytes) async {
    socket.add(bytes);
    await socket.flush();
  }

  /// Sends a ping and waits for its pong: the session has then read all
  /// that was sent before it.
  Future<void> sync() async {
    final count = pongs.length;
    await send(_frame(9, [count & 0x7F], mask: true));
    await until(() => pongs.length > count);
  }

  Future<void> close() async {
    socket.destroy();
    await server.close(force: true);
  }
}

/// The answer that accepts a handshake whose key is [key].
String _accepted(String key) =>
    'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
    'Connection: Upgrade\r\n'
    'Sec-WebSocket-Accept: ${webSocketAccept(key)}\r\n\r\n';

/// A raw WebSocket client of [port] that does the handshake, then gives
/// the server's frames (opcode, payload) as they come.
Future<(io.Socket, Stream<(int, List<int>)>)> _frameClient(int port) async {
  final socket = await io.Socket.connect('127.0.0.1', port);
  socket.add(
    latin1.encode(
      'GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
      'Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
      'Sec-WebSocket-Version: 13\r\n\r\n',
    ),
  );
  final head = Completer<void>();
  final frames = StreamController<(int, List<int>)>();
  final buffer = BytesBuilder();
  socket.listen(
    (chunk) {
      buffer.add(chunk);
      if (!head.isCompleted) {
        final bytes = buffer.toBytes();
        final end = latin1.decode(bytes).indexOf('\r\n\r\n');
        if (end < 0) {
          return;
        }
        buffer
          ..clear()
          ..add(bytes.sublist(end + 4));
        head.complete();
      }
      _takeFrames(buffer).forEach(frames.add);
    },
    onError: (Object _) {},
    onDone: frames.close,
  );
  await head.future.timeout(const Duration(seconds: 10));
  return (socket, frames.stream);
}

/// A raw WebSocket client of [port] that does the handshake, then reads
/// nothing (its subscription is paused).
Future<(io.Socket, StreamSubscription<Uint8List>)> _rawClient(int port) async {
  final socket = await io.Socket.connect('127.0.0.1', port);
  socket.add(
    latin1.encode(
      'GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
      'Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
      'Sec-WebSocket-Version: 13\r\n\r\n',
    ),
  );
  final head = Completer<void>();
  final buffer = BytesBuilder();
  // Returned paused; destroying the socket ends it.
  // ignore: cancel_subscriptions
  late final StreamSubscription<Uint8List> subscription;
  subscription = socket.listen((chunk) {
    buffer.add(chunk);
    if (!head.isCompleted &&
        latin1.decode(buffer.toBytes()).contains('\r\n\r\n')) {
      head.complete();
    }
  }, onError: (Object _) {});
  await head.future.timeout(const Duration(seconds: 10));
  subscription.pause();
  return (socket, subscription);
}

/// A connection whose write ([failWrite]) or read ([failRead]) fails when
/// the test says, as when the other side resets it: which of the two
/// meets the error first is up to the test, not the network.
final class _FailingSocket extends Stream<Uint8List> implements io.Socket {
  final _input = StreamController<Uint8List>();
  final _written = Completer<void>();
  final _done = Completer<void>();

  void failWrite(Object error) => _written.completeError(error);

  void failRead(Object error) => _input.addError(error);

  /// Ends the input cleanly, without a close frame: over TLS a reset often
  /// does that before the write that fails reports the error.
  void endInput() => unawaited(_input.close());

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
