// A client that does not read its response, and a request with both
// Content-Length and Transfer-Encoding, over real sockets: the first must
// not hold a request for ever (server.connection-timeout bounds how long
// written bytes may wait for the client), while a slow download that
// keeps moving and a stream that is quiet between events stay; the second
// is a 400 on a connection that closes.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

const _timeout = Duration(seconds: 1);
const int _big = 32 * 1024 * 1024;

/// [length] bytes whose value depends on their position, so a missing or
/// repeated piece shows.
Uint8List pattern(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31 + (i >> 16)) & 0xFF;
  }
  return bytes;
}

Future<IoWebServer> serve(
  FutureOr<void> Function(ServerHttpRequest, ServerHttpResponse) handle, [
  ServerProperties settings = const ServerProperties(),
]) async {
  final server = IoWebServer(
    FunctionHttpHandler(
      (request, response) async => await handle(request, response),
    ),
    settings.copyWith(port: 0, address: '127.0.0.1'),
  );
  await server.start();
  addTearDown(() => server.stop(timeout: const Duration(seconds: 2)));
  return server;
}

/// A connection that sent `GET [path]` and reads nothing.
Future<io.Socket> deaf(int port, String path) async {
  final socket = await io.Socket.connect('127.0.0.1', port);
  socket.add(latin1.encode('GET $path HTTP/1.1\r\nHost: localhost\r\n\r\n'));
  await socket.flush();
  addTearDown(socket.destroy);
  return socket;
}

/// The status of `GET [path]` on a connection of its own.
Future<int> status(int port, String path) async {
  final client = io.HttpClient();
  try {
    final request = await client.get('127.0.0.1', port, path);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// Waits until [server] has no request in progress; the time it took.
Future<Duration> idle(IoWebServer server, {required Duration within}) async {
  final watch = Stopwatch()..start();
  while (server.activeRequests > 0) {
    if (watch.elapsed > within) {
      fail(
        '${server.activeRequests} request(s) still in progress after '
        '${watch.elapsed}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return watch.elapsed;
}

/// Sends `GET [path]` on a raw socket and reads the answer [pause] apart, a
/// piece at a time: the response of a slow client. The body, once the
/// connection closes.
Future<({String head, Uint8List body, Duration took})> slowly(
  int port,
  String path, {
  required Duration pause,
  String headers = '',
}) async {
  // A raw socket: nothing leaves the system's buffer but what is asked
  // for, so the pace is the client's.
  final socket = await io.RawSocket.connect('127.0.0.1', port);
  var closed = false;
  // Read events are on only while there is nothing to read: dart:io
  // repeats them without a pause for as long as data is left unread.
  final events = socket.listen((event) {
    if (event == io.RawSocketEvent.read) {
      socket.readEventsEnabled = false;
    } else if (event == io.RawSocketEvent.readClosed ||
        event == io.RawSocketEvent.closed) {
      closed = true;
    }
  }, onError: (Object _) => closed = true);
  socket.write(
    latin1.encode(
      'GET $path HTTP/1.1\r\nHost: localhost\r\n'
      'Connection: close\r\n$headers\r\n',
    ),
  );
  final watch = Stopwatch()..start();
  final out = BytesBuilder(copy: false);
  while (true) {
    final piece = socket.read(16 * 1024);
    if (piece != null && piece.isNotEmpty) {
      out.add(piece);
    } else if (closed) {
      break;
    } else {
      socket.readEventsEnabled = true;
    }
    await Future<void>.delayed(pause);
  }
  await events.cancel();
  await socket.close();
  final all = out.takeBytes();
  final split = latin1
      .decode(all.sublist(0, all.length < 2048 ? all.length : 2048))
      .indexOf('\r\n\r\n');
  return (
    head: latin1.decode(all.sublist(0, split)),
    body: Uint8List.sublistView(all, split + 4),
    took: watch.elapsed,
  );
}

/// Sends [request] on a raw socket; what comes back until the server
/// closes the connection, and whether it did within [timeout].
Future<({String text, bool closed})> raw(
  int port,
  String request, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final socket = await io.Socket.connect('127.0.0.1', port);
  socket.add(latin1.encode(request));
  unawaited(socket.flush().catchError((Object _) {}));
  final out = BytesBuilder();
  final done = Completer<bool>();
  socket.listen(
    out.add,
    onError: (Object _) => done.isCompleted ? null : done.complete(true),
    onDone: () => done.isCompleted ? null : done.complete(true),
  );
  final closed = await done.future.timeout(timeout, onTimeout: () => false);
  socket.destroy();
  return (text: latin1.decode(out.takeBytes()), closed: closed);
}

int answers(String text) => 'HTTP/1.1 '.allMatches(text).length;

void main() {
  group('a client that does not read', () {
    final body = pattern(_big);

    // How the 32 MB are written: all at once, as a stream of pieces, in
    // pieces with a flush after each, and compressed.
    final ways = <String, Future<void> Function(ServerHttpResponse response)>{
      'add': (response) async {
        response
          ..headers.contentType = 'application/octet-stream'
          ..headers.contentLength = body.length
          ..add(body);
      },
      'addStream': (response) async {
        response.headers.contentType = 'application/octet-stream';
        await response.addStream(
          Stream.fromIterable([
            for (var at = 0; at < body.length; at += 1024 * 1024)
              Uint8List.sublistView(body, at, at + 1024 * 1024),
          ]),
        );
      },
      'flush': (response) async {
        response.headers.contentType = 'application/octet-stream';
        for (var at = 0; at < body.length; at += 1024 * 1024) {
          response.add(Uint8List.sublistView(body, at, at + 1024 * 1024));
          await response.flush();
        }
      },
      'many small writes': (response) async {
        response.headers.contentType = 'application/octet-stream';
        for (var at = 0; at < body.length; at += 4096) {
          response.add(Uint8List.sublistView(body, at, at + 4096));
        }
      },
    };

    for (final MapEntry(key: way, value: write) in ways.entries) {
      test('its request ends after the connection timeout ($way)', () async {
        final server = await serve(
          (request, response) async {
            if (request.path == '/big') {
              await write(response);
            } else {
              await response.send(200, 'ok');
            }
          },
          const ServerProperties(
            maxConcurrentRequests: 2,
            connectionTimeout: _timeout,
          ),
        );
        final first = await deaf(server.port, '/big');
        final second = await deaf(server.port, '/big');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(server.activeRequests, 2);
        expect(await status(server.port, '/small'), 503);

        // Both places are free again: within about twice the timeout.
        final took = await idle(server, within: _timeout * 2.5);
        expect(server.activeRequests, 0);
        expect(await status(server.port, '/small'), 200);
        printOnFailure('released after $took');

        // The connections were dropped, the responses cut short.
        for (final socket in [first, second]) {
          var received = 0;
          final closed = Completer<void>();
          socket.listen(
            (chunk) => received += chunk.length,
            onError: (Object _) =>
                closed.isCompleted ? null : closed.complete(),
            onDone: () => closed.isCompleted ? null : closed.complete(),
          );
          await closed.future.timeout(const Duration(seconds: 5));
          expect(received, lessThan(_big));
        }
      });
    }

    test('a compressed response too', () async {
      // Bytes that stay as large compressed.
      final random = Random(7);
      final noise = Uint8List.fromList([
        for (var i = 0; i < 8 * 1024 * 1024; i++) random.nextInt(256),
      ]);
      final server = await serve(
        (request, response) async {
          response
            ..headers.contentType = 'text/plain'
            ..add(noise);
        },
        const ServerProperties(
          maxConcurrentRequests: 1,
          connectionTimeout: _timeout,
          compression: true,
        ),
      );
      final socket = await io.Socket.connect('127.0.0.1', server.port);
      addTearDown(socket.destroy);
      socket.add(
        latin1.encode(
          'GET /big HTTP/1.1\r\nHost: localhost\r\n'
          'Accept-Encoding: gzip\r\n\r\n',
        ),
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.activeRequests, 1);
      await idle(server, within: _timeout * 2.5);
      expect(await status(server.port, '/small'), 200);
    });

    test('a graceful stop does not wait for it', () async {
      final server = await serve(
        (request, response) async {
          response
            ..headers.contentLength = body.length
            ..add(body);
        },
        const ServerProperties(connectionTimeout: _timeout),
      );
      await deaf(server.port, '/big');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.activeRequests, 1);
      final watch = Stopwatch()..start();
      await server.stop(timeout: const Duration(seconds: 20));
      expect(watch.elapsed, lessThan(_timeout * 3));
    });

    test('without a connection timeout nothing is cut', () async {
      final server = await serve(
        (request, response) async {
          response
            ..headers.contentLength = body.length
            ..add(body);
        },
        ServerProperties.from(
          ServerSettings()..connectionTimeout = Duration.zero,
        ),
      );
      expect(server.settings.effectiveConnectionTimeout, isNull);
      final socket = await deaf(server.port, '/big');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(server.activeRequests, 1);
      // It reads at last, and gets everything.
      var received = 0;
      final all = Completer<void>();
      socket.listen((chunk) {
        received += chunk.length;
        if (received >= _big && !all.isCompleted) {
          all.complete();
        }
      });
      await all.future.timeout(const Duration(seconds: 20));
      await idle(server, within: const Duration(seconds: 2));
    });
  });

  group('a client that reads slowly but steadily', () {
    // 6 MB read 16 KB every 8 ms or so: several times the timeout in all,
    // each piece well within it.
    const size = 6 * 1024 * 1024;
    final body = pattern(size);

    Future<void> check(
      Future<void> Function(ServerHttpResponse response) write, {
      ServerProperties settings = const ServerProperties(
        connectionTimeout: _timeout,
      ),
      String headers = '',
      bool gzip = false,
    }) async {
      final server = await serve(
        (request, response) => write(response),
        settings,
      );
      final reply = await slowly(
        server.port,
        '/big',
        pause: const Duration(milliseconds: 8),
        headers: headers,
      );
      expect(reply.head, startsWith('HTTP/1.1 200'));
      expect(
        reply.took,
        greaterThan(_timeout * 2),
        reason: 'the download must outlast the timeout to show anything',
      );
      var received = reply.body;
      if (reply.head.toLowerCase().contains('transfer-encoding: chunked')) {
        received = dechunk(received);
      }
      if (gzip) {
        expect(reply.head.toLowerCase(), contains('content-encoding: gzip'));
        received = Uint8List.fromList(io.gzip.decode(received));
      }
      expect(received.length, size);
      expect(received, body);
      await idle(server, within: const Duration(seconds: 2));
    }

    test('gets all of a body written at once', () async {
      await check((response) async {
        response
          ..headers.contentType = 'application/octet-stream'
          ..headers.contentLength = size
          ..add(body);
      });
    });

    test('gets all of a stream', () async {
      await check((response) async {
        response.headers.contentType = 'application/octet-stream';
        await response.addStream(
          Stream.fromIterable([
            for (var at = 0; at < size; at += 256 * 1024)
              Uint8List.sublistView(body, at, at + 256 * 1024),
          ]),
        );
      });
    });

    test('gets all of a body written in pieces, flushed or not', () async {
      await check((response) async {
        response.headers.contentType = 'application/octet-stream';
        var pieces = 0;
        for (var at = 0; at < size; at += 100 * 1024) {
          final end = at + 100 * 1024 < size ? at + 100 * 1024 : size;
          // A list that is not typed data, now and then.
          response.add(
            pieces.isEven
                ? Uint8List.sublistView(body, at, end)
                : body.sublist(at, end).toList(),
          );
          if (++pieces % 7 == 0) {
            await response.flush();
          }
        }
      });
    });
  });

  group('a stream that is quiet between events', () {
    // The gaps are longer than the timeout; the client reads all along.
    const gap = Duration(milliseconds: 1600);

    test('server-sent events are not cut', () async {
      final server = await serve((request, response) async {
        response.headers.contentType = 'text/event-stream';
        for (var i = 0; i < 3; i++) {
          response.write('data: event $i\n\n');
          await response.flush();
          await Future<void>.delayed(gap);
        }
        response.write('data: last\n\n');
      }, const ServerProperties(connectionTimeout: _timeout));
      final reply = await slowly(
        server.port,
        '/events',
        pause: const Duration(milliseconds: 5),
      );
      expect(reply.head, startsWith('HTTP/1.1 200'));
      final text = utf8.decode(dechunk(reply.body));
      expect(
        text,
        'data: event 0\n\ndata: event 1\n\ndata: event 2\n\n'
        'data: last\n\n',
      );
      expect(reply.took, greaterThan(gap * 3));
    });

    test('a stream added from a slow producer is not cut', () async {
      final server = await serve((request, response) async {
        response.headers.contentType = 'application/octet-stream';
        Stream<List<int>> produce() async* {
          for (var i = 0; i < 3; i++) {
            yield utf8.encode('piece $i\n');
            await Future<void>.delayed(gap);
          }
          yield utf8.encode('end\n');
        }

        await response.addStream(produce());
      }, const ServerProperties(connectionTimeout: _timeout));
      final reply = await slowly(
        server.port,
        '/pieces',
        pause: const Duration(milliseconds: 5),
      );
      expect(reply.head, startsWith('HTTP/1.1 200'));
      expect(
        utf8.decode(dechunk(reply.body)),
        'piece 0\npiece 1\npiece 2\nend\n',
      );
      expect(reply.took, greaterThan(gap * 3));
    });
  });

  group('responses as before', () {
    Future<io.HttpClientResponse> get(
      int port,
      String method, {
      bool gzip = false,
    }) async {
      final client = io.HttpClient()..autoUncompress = true;
      addTearDown(() => client.close(force: true));
      final request = await client.open(method, '127.0.0.1', port, '/');
      if (!gzip) {
        request.headers.removeAll(io.HttpHeaders.acceptEncodingHeader);
      }
      return await request.close();
    }

    final body = pattern(3 * 1024 * 1024);

    test('a large compressed body arrives whole', () async {
      final server = await serve(
        (request, response) async {
          response
            ..headers.contentType = 'text/plain'
            ..headers.contentLength = body.length
            ..add(body);
        },
        const ServerProperties(compression: true),
      );
      final response = await get(server.port, 'GET', gzip: true);
      expect(response.headers.value('content-encoding'), 'gzip');
      final received = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (all, chunk) => all..add(chunk),
      );
      expect(received.takeBytes(), body);
    });

    test('a large body to HEAD, and a 204, have no body', () async {
      final server = await serve((request, response) async {
        if (request.method == HttpMethod.head) {
          response
            ..headers.contentLength = body.length
            ..add(body);
        } else {
          response
            ..statusCode = 204
            ..add(body);
        }
      });
      final head = await get(server.port, 'HEAD');
      expect(head.statusCode, 200);
      expect(head.contentLength, body.length);
      expect(await head.drain<int>(0), 0);
      final empty = await get(server.port, 'GET');
      expect(empty.statusCode, 204);
      expect(await empty.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      await idle(server, within: const Duration(seconds: 2));
    });

    test('writes while a flush is under way keep their order', () async {
      final server = await serve((request, response) async {
        response.headers.contentType = 'text/plain';
        for (var i = 0; i < 50; i++) {
          response.write('line $i\n');
          unawaited(response.flush());
        }
        response.write('end\n');
      });
      final response = await get(server.port, 'GET');
      expect(
        await utf8.decodeStream(response),
        '${[for (var i = 0; i < 50; i++) 'line $i\n'].join()}end\n',
      );
    });
  });

  group('Content-Length with Transfer-Encoding', () {
    late IoWebServer server;
    final seen = <String>[];

    setUp(() async {
      seen.clear();
      server = await serve((request, response) async {
        final body = await utf8.decodeStream(request.body);
        seen.add('${request.method.value} ${request.path} $body');
        await response.send(200, 'ok');
      });
    });

    // After the request, the request a proxy that went by Content-Length
    // would take the rest for.
    String both(String headers) =>
        'POST /first HTTP/1.1\r\nHost: localhost\r\n$headers\r\n'
        '3\r\nabc\r\n0\r\n\r\n'
        'GET /smuggled HTTP/1.1\r\nHost: localhost\r\n\r\n';

    for (final headers in [
      'Content-Length: 5\r\nTransfer-Encoding: Chunked\r\n',
      'Content-Length: 5\r\nTransfer-Encoding: CHUNKED\r\n',
      'content-length: 5\r\ntransfer-encoding: gzip, chunked\r\n',
      'Content-Length: 5\r\nTransfer-Encoding:  chunkeD \r\n',
    ]) {
      test('400 and the connection closes: ${jsonEncode(headers)}', () async {
        final reply = await raw(server.port, both(headers));
        expect(reply.text, startsWith('HTTP/1.1 400'));
        expect(reply.text.toLowerCase(), contains('\r\nconnection: close'));
        expect(reply.text, contains('application/problem+json'));
        expect(
          reply.text,
          contains('both Content-Length and Transfer-Encoding'),
        );
        expect(reply.closed, isTrue);
        expect(answers(reply.text), 1, reason: reply.text);
        expect(seen, isEmpty);
      });
    }

    // What dart:io hides: for these it drops the Content-Length before
    // the server sees the request, so the request is a chunked one here
    // (RFC 9112 §6.3 allows to serve it so). The body is the chunked
    // one, and what follows is the next request, as dart:io reads it.
    for (final headers in [
      'Content-Length: 5\r\nTransfer-Encoding: chunked\r\n',
      'Transfer-Encoding: chunked\r\nContent-Length: 5\r\n',
      'Transfer-Encoding: Chunked\r\nContent-Length: 5\r\n',
    ]) {
      test('known limit, served as chunked: ${jsonEncode(headers)}', () async {
        final reply = await raw(
          server.port,
          both(headers),
          timeout: const Duration(seconds: 1),
        );
        expect(reply.text, startsWith('HTTP/1.1 200'));
        expect(seen, ['POST /first abc', 'GET /smuggled ']);
      });
    }

    test('a chunked request and one with a length still work', () async {
      final chunked = await raw(
        server.port,
        'POST /chunked HTTP/1.1\r\nHost: localhost\r\n'
        'Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n'
        '3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n',
      );
      expect(chunked.text, startsWith('HTTP/1.1 200'));
      final sized = await raw(
        server.port,
        'POST /sized HTTP/1.1\r\nHost: localhost\r\n'
        'Content-Length: 5\r\nConnection: close\r\n\r\nabcde',
      );
      expect(sized.text, startsWith('HTTP/1.1 200'));
      expect(seen, ['POST /chunked abcde', 'POST /sized abcde']);
      // And the connection of such a request is kept.
      final kept = await raw(
        server.port,
        'POST /one HTTP/1.1\r\nHost: localhost\r\n'
        'Content-Length: 1\r\n\r\n'
        'a' // the body, and the next request right after it
        'GET /two HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
      );
      expect(answers(kept.text), 2);
    });
  });
}

/// The body of a chunked response.
Uint8List dechunk(Uint8List chunked) {
  final out = BytesBuilder(copy: false);
  var at = 0;
  while (at < chunked.length) {
    var end = at;
    while (chunked[end] != 13) {
      end++;
    }
    final size = int.parse(
      latin1.decode(chunked.sublist(at, end)).split(';').first.trim(),
      radix: 16,
    );
    if (size == 0) {
      break;
    }
    out.add(Uint8List.sublistView(chunked, end + 2, end + 2 + size));
    at = end + 2 + size + 2;
  }
  return out.takeBytes();
}
