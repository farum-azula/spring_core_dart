// Regression tests of the fourth review before 0.5.0 over real sockets:
// the server's WebSocket sessions, with control frames between the
// fragments of a client's message, and after close().
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'server_review_test.dart' show serve, until;

void main() {
  group('WebSocket sessions of the server', () {
    late IoWebServer server;
    late StreamIterator<WebSocketSession> sessions;

    setUp(() async {
      final accepted = StreamController<WebSocketSession>();
      sessions = StreamIterator(accepted.stream);
      server = await serve(
        (request, response) async =>
            accepted.add(await request.upgradeToWebSocket()),
      );
    });

    tearDown(() async {
      await sessions.cancel();
      await server.stop(timeout: Duration.zero);
    });

    test('a ping or a pong between the fragments of a message from the '
        'client: the session gets the message whole, the client a pong with '
        "the ping's payload at once; a close between fragments ends the "
        'session with its code', () async {
      final client = await _RawClient.connect(server.port);
      expect(await sessions.moveNext(), isTrue);
      final session = sessions.current;
      final received = <Object>[];
      final ended = session.messages.forEach(received.add);

      client.send([
        _frame(1, List.filled(1000, 0x61), fin: false),
        _frame(9, [1, 2, 3]),
      ]);
      await until(() => client.pongs.isNotEmpty); // before the message ends
      expect(client.pongs, [
        [1, 2, 3],
      ]);
      client.send([
        _frame(10, [7]),
        _frame(0, List.filled(1000, 0x62)),
        _frame(1, List.filled(300, 0x63), fin: false),
        _frame(8, [0x0F, 0xA1, ...utf8.encode('gone')]), // 4001
      ]);
      await ended.timeout(const Duration(seconds: 10));
      expect(received, ['a' * 1000 + 'b' * 1000]);
      expect(session.closeStatus, const CloseStatus(4001, 'gone'));
      await until(() => client.closes.isNotEmpty); // the answer
      expect(client.closes.single.take(2), [0x0F, 0xA1]);
      client.destroy();
    });

    test('after close(), while the client has not answered: isOpen is false '
        'and sendMessage throws a WebSocketException', () async {
      final client = await _RawClient.connect(server.port);
      expect(await sessions.moveNext(), isTrue);
      final session = sessions.current;
      session.messages.listen((_) {});
      expect(session.isOpen, isTrue);
      unawaited(session.close(CloseStatus.goingAway));
      expect(session.isOpen, isFalse);
      expect(session.closeStatus?.code, CloseStatus.goingAway.code);
      expect(
        () => session.sendMessage('late'),
        throwsA(isA<WebSocketException>()),
      );
      await until(() => client.closes.isNotEmpty); // sent, not answered
      client.destroy();
    });
  });
}

/// A WebSocket client written by hand: it sends masked frames as they
/// are, and records the server's pongs and close frames.
final class _RawClient {
  _RawClient._(this._socket);

  static Future<_RawClient> connect(int port) async {
    final socket = await io.Socket.connect('127.0.0.1', port);
    final client = _RawClient._(socket);
    socket.add(
      latin1.encode(
        'GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n',
      ),
    );
    final head = Completer<void>();
    final buffer = BytesBuilder();
    socket.listen(
      (chunk) {
        buffer.add(chunk);
        var bytes = buffer.toBytes();
        if (!head.isCompleted) {
          final end = latin1.decode(bytes).indexOf('\r\n\r\n');
          if (end < 0) {
            return;
          }
          expect(latin1.decode(bytes), startsWith('HTTP/1.1 101'));
          bytes = bytes.sublist(end + 4);
          head.complete();
        }
        // The server's frames: unmasked, under 64 KB.
        while (bytes.length >= 4 || (bytes.length >= 2 && bytes[1] < 126)) {
          final (length, start) = bytes[1] < 126
              ? (bytes[1], 2)
              : (bytes[2] << 8 | bytes[3], 4);
          if (bytes.length < start + length) {
            break;
          }
          final payload = bytes.sublist(start, start + length);
          switch (bytes[0] & 0x0F) {
            case 10:
              client.pongs.add(payload);
            case 8:
              client.closes.add(payload);
          }
          bytes = bytes.sublist(start + length);
        }
        buffer
          ..clear()
          ..add(bytes);
      },
      onError: (Object _) {},
    );
    await head.future.timeout(const Duration(seconds: 10));
    return client;
  }

  final io.Socket _socket;
  final pongs = <List<int>>[];
  final closes = <List<int>>[];

  void send(List<List<int>> frames) => frames.forEach(_socket.add);

  void destroy() => _socket.destroy();
}

/// A masked frame, as a client sends it.
List<int> _frame(int opcode, List<int> payload, {bool fin = true}) {
  const key = [0x37, 0xFA, 0x21, 0x3D];
  final length = payload.length;
  return [
    (fin ? 0x80 : 0) | opcode,
    0x80 | (length < 126 ? length : 126),
    if (length >= 126) ...[length >> 8, length & 0xFF],
    ...key,
    for (var i = 0; i < length; i++) payload[i] ^ key[i % 4],
  ];
}
