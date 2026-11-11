// A graceful stop over real sockets: the server stops accepting first, and
// a keep-alive connection that has just sent its next request still gets
// its answer (closing at once would end it as idle, and the request with
// it).
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

Future<IoWebServer> _serve([
  ServerProperties settings = const ServerProperties(),
]) async {
  final server = IoWebServer(
    FunctionHttpHandler((request, response) async {
      response.headers.set('Content-Type', 'text/plain');
      response.write('ok');
    }),
    settings.copyWith(port: 0, address: '127.0.0.1'),
  );
  await server.start();
  return server;
}

const _get = 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n';

/// One answer of a connection: its head and its body `ok`, with a length
/// or in chunks.
Future<String> _read(StreamIterator<List<int>> bytes) async {
  final text = StringBuffer();
  bool whole() {
    final answer = '$text';
    final head = answer.indexOf('\r\n\r\n');
    if (head < 0) {
      return false;
    }
    final body = answer.substring(head + 4);
    return body == 'ok' || body.endsWith('0\r\n\r\n');
  }

  while (!whole()) {
    if (!await bytes.moveNext().timeout(const Duration(seconds: 5))) {
      break;
    }
    text.write(latin1.decode(bytes.current));
  }
  return '$text';
}

void main() {
  test('a request sent as the server stops is answered, and its connection '
      'closes', () async {
    final server = await _serve();
    final port = server.port;
    final socket = await io.Socket.connect('127.0.0.1', port);
    addTearDown(socket.destroy);
    final bytes = StreamIterator<List<int>>(socket);
    socket.add(latin1.encode(_get));
    final first = await _read(bytes);
    expect(first, startsWith('HTTP/1.1 200'));
    expect(first.toLowerCase(), isNot(contains('connection: close')));

    // The connection is idle now; its next request leaves with the stop.
    final stopped = server.stop(timeout: const Duration(seconds: 5));
    socket.add(latin1.encode(_get));
    final second = await _read(bytes);
    expect(second, startsWith('HTTP/1.1 200'));
    expect(second.toLowerCase(), contains('connection: close'));
    expect(second, contains('ok'));
    // And the server closes it.
    expect(await bytes.moveNext().timeout(const Duration(seconds: 5)), isFalse);
    await stopped;
  });

  test('no connection is accepted once the stop began', () async {
    final server = await _serve();
    final port = server.port;
    final idle = await io.Socket.connect('127.0.0.1', port);
    addTearDown(idle.destroy);
    await server.stop(timeout: const Duration(seconds: 5));
    await expectLater(
      io.Socket.connect('127.0.0.1', port),
      throwsA(isA<io.SocketException>()),
    );
  });

  test('connections that send nothing do not hold the stop', () async {
    final server = await _serve();
    final idle = [
      for (var i = 0; i < 3; i++)
        await io.Socket.connect('127.0.0.1', server.port),
    ];
    addTearDown(() {
      for (final socket in idle) {
        socket.destroy();
      }
    });
    final watch = Stopwatch()..start();
    await server.stop(timeout: const Duration(seconds: 5));
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('an immediate stop closes at once, as before', () async {
    final server = await _serve(
      const ServerProperties(shutdown: Shutdown.immediate),
    );
    final socket = await io.Socket.connect('127.0.0.1', server.port);
    addTearDown(socket.destroy);
    final bytes = StreamIterator<List<int>>(socket);
    socket.add(latin1.encode(_get));
    expect(await _read(bytes), startsWith('HTTP/1.1 200'));
    await server.stop();
    expect(await bytes.moveNext().timeout(const Duration(seconds: 5)), isFalse);
  });
}
