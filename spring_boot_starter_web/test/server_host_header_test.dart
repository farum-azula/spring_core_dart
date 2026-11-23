// Two Host headers over real sockets: dart:io keeps only the last, so the
// server counts them in the bytes on their way to it. The framing the
// scanner follows must be dart:io's, or a body would be read as a head.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_web/src/io_request_heads.dart';
import 'package:test/test.dart';

const _forged =
    'GET /forged HTTP/1.1\r\nHost: a.example\r\nHost: b.example\r\n\r\n';

/// A server that answers each request with its path and the length of its
/// body, and records the paths it was given.
Future<(IoWebServer, List<String>)> _serve([
  ServerProperties settings = const ServerProperties(),
]) async {
  final seen = <String>[];
  final server = IoWebServer(
    FunctionHttpHandler((request, response) async {
      seen.add(request.path);
      var length = 0;
      await for (final chunk in request.body) {
        length += chunk.length;
      }
      final text = '${request.path}:$length';
      response.headers
        ..set('Content-Type', 'text/plain')
        ..contentLength = text.length;
      response.write(text);
    }),
    settings.copyWith(
      port: 0,
      address: '127.0.0.1',
      maxRequestBodySize: -1,
    ),
  );
  await server.start();
  return (server, seen);
}

/// Everything the server sends on one connection until it closes it, after
/// [chunks] were written one at a time.
Future<String> _exchange(
  io.Socket socket,
  Iterable<List<int>> chunks,
) async {
  final received = <int>[];
  final done = socket.listen(received.addAll).asFuture<void>();
  for (final chunk in chunks) {
    socket.add(chunk);
    await socket.flush();
    await Future<void>.delayed(Duration.zero);
  }
  await done.timeout(const Duration(seconds: 20));
  socket.destroy();
  return latin1.decode(received);
}

Future<String> _send(int port, String text) async => await _exchange(
  await io.Socket.connect('127.0.0.1', port),
  [latin1.encode(text)],
);

int _count(String text, String part) => part.allMatches(text).length;

/// The scanner's verdicts on the heads in [text], split at every [step]
/// bytes.
List<RequestHeadVerdict> _verdicts(String text, {int? step, int heads = 1}) {
  final scanner = RequestHeadScanner();
  final bytes = latin1.encode(text);
  final size = step ?? bytes.length;
  for (var i = 0; i < bytes.length; i += size) {
    scanner.scan(
      Uint8List.sublistView(bytes, i, min(i + size, bytes.length)),
    );
  }
  return [for (var i = 0; i < heads; i++) scanner.next()];
}

void main() {
  group('the scanner', () {
    const sound = RequestHeadVerdict.sound;
    const repeated = RequestHeadVerdict.repeatedHost;
    const unchecked = RequestHeadVerdict.unchecked;

    test('one Host is sound, two are not, in any case and any split', () {
      const one = 'GET / HTTP/1.1\r\nHost: a\r\n\r\n';
      const two = 'GET / HTTP/1.1\r\nHost: a\r\nhOsT: b\r\n\r\n';
      for (final step in [1, 2, 3, 7, 1000]) {
        expect(_verdicts(one, step: step), [sound]);
        expect(_verdicts(two, step: step), [repeated]);
      }
    });

    test('a bare LF ends lines as it does for dart:io', () {
      expect(_verdicts('GET / HTTP/1.1\nHost: a\nHost: b\n\n'), [repeated]);
    });

    test('a folded value is one header; a Host after it counts', () {
      expect(
        _verdicts('GET / HTTP/1.1\r\nHost: a\r\n b\r\nX: c\r\n\r\n'),
        [sound],
      );
      expect(
        _verdicts('GET / HTTP/1.1\r\nX: y\r\n Host: b\r\nHost: a\r\n\r\n'),
        [sound],
        reason: 'the indented line continues X',
      );
      expect(
        _verdicts('GET / HTTP/1.1\r\nHost: a\r\n\tb\r\nHost: c\r\n\r\n'),
        [repeated],
      );
    });

    test('names that only look like Host do not count', () {
      expect(
        _verdicts('GET / HTTP/1.1\r\nHost: a\r\nX-Host: b\r\nHosts: c\r\n\r\n'),
        [sound],
      );
    });

    test('a body is skipped by its length, also when it looks like a '
        'request', () {
      const text =
          'POST / HTTP/1.1\r\nHost: a\r\nContent-Length: ${_forged.length}'
          '\r\n\r\n$_forged'
          'GET /next HTTP/1.1\r\nHost: a\r\n\r\n';
      for (final step in [1, 5, 1000]) {
        expect(_verdicts(text, step: step, heads: 3), [
          sound,
          sound,
          unchecked,
        ]);
      }
    });

    test('a chunked body is skipped, with extensions and either line '
        'end', () {
      final size = _forged.length.toRadixString(16);
      final text =
          'POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n'
          '$size;ext=1\r\n$_forged\r\n'
          '$size\n$_forged\n'
          '0\r\n\r\n'
          'GET /next HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n';
      for (final step in [1, 4, 1000]) {
        expect(_verdicts(text, step: step, heads: 2), [sound, repeated]);
      }
    });

    test('Transfer-Encoding wins over a Content-Length before it', () {
      const text =
          'POST / HTTP/1.1\r\nHost: a\r\nContent-Length: 3\r\n'
          'Transfer-Encoding: chunked\r\n\r\n'
          '1\r\nx\r\n0\r\n\r\n'
          'GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n';
      expect(_verdicts(text, heads: 2), [sound, repeated]);
    });

    test('after an upgrade the bytes are not HTTP', () {
      const text =
          'GET / HTTP/1.1\r\nHost: a\r\nConnection: keep-alive, UPGRADE\r\n'
          '\r\n$_forged';
      expect(_verdicts(text, heads: 2), [sound, unchecked]);
    });

    test('what dart:io refuses ends the scan', () {
      for (final head in [
        'Content-Length: 1\r\nContent-Length: 1\r\n',
        'Content-Length: x\r\n',
        'Transfer-Encoding: gzip\r\n',
      ]) {
        expect(
          _verdicts(
            'POST / HTTP/1.1\r\nHost: a\r\n$head\r\n$_forged',
            heads: 2,
          ).last,
          unchecked,
          reason: head,
        );
      }
    });
  });

  group('the server', () {
    late IoWebServer server;
    late List<String> seen;

    setUp(() async {
      (server, seen) = await _serve();
    });

    tearDown(() => server.stop(timeout: Duration.zero));

    test('answers two Host headers with 400 and closes the connection, '
        'without calling the handler', () async {
      final answer = await _send(
        server.port,
        'GET /reset HTTP/1.1\r\nHost: shop.example\r\n'
        'Host: evil.example\r\n\r\n',
      );
      expect(answer, startsWith('HTTP/1.1 400'));
      expect(answer.toLowerCase(), contains('connection: close'));
      expect(seen, isEmpty);
    });

    test('sees them one byte per packet, and in another case', () async {
      final bytes = latin1.encode(
        'GET /reset HTTP/1.1\r\nHost: a.example\r\nhOsT: b.example\r\n\r\n',
      );
      final answer = await _exchange(
        await io.Socket.connect('127.0.0.1', server.port),
        [
          for (final byte in bytes) [byte],
        ],
      );
      expect(answer, startsWith('HTTP/1.1 400'));
      expect(seen, isEmpty);
    });

    test('serves what was pipelined before them, and nothing after', () async {
      final answer = await _send(
        server.port,
        'GET /one HTTP/1.1\r\nHost: a\r\n\r\n'
        'POST /two HTTP/1.1\r\nHost: a\r\nContent-Length: ${_forged.length}'
        '\r\n\r\n$_forged'
        'GET /bad HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n'
        'GET /after HTTP/1.1\r\nHost: a\r\n\r\n',
      );
      expect(seen, ['/one', '/two']);
      expect(_count(answer, 'HTTP/1.1 200'), 2);
      expect(_count(answer, 'HTTP/1.1 400'), 1);
      expect(answer, contains('/two:${_forged.length}'));
    });

    test(
      'on a keep-alive connection, the second request is checked too',
      () async {
        final socket = await io.Socket.connect('127.0.0.1', server.port);
        final answers = StreamIterator<List<int>>(socket);
        socket.add(latin1.encode('GET /one HTTP/1.1\r\nHost: a\r\n\r\n'));
        expect(await answers.moveNext(), isTrue);
        expect(latin1.decode(answers.current), startsWith('HTTP/1.1 200'));
        socket.add(
          latin1.encode('GET /two HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n'),
        );
        expect(await answers.moveNext(), isTrue);
        expect(latin1.decode(answers.current), startsWith('HTTP/1.1 400'));
        await answers.cancel();
        socket.destroy();
        expect(seen, ['/one']);
      },
    );

    test('a large body passes untouched', () async {
      const size = 5 * 1024 * 1024;
      final body = Uint8List(size);
      final filler = latin1.encode(_forged);
      for (var i = 0; i < size; i++) {
        body[i] = filler[i % filler.length];
      }
      final client = io.HttpClient();
      addTearDown(client.close);
      final request = await client.post('127.0.0.1', server.port, '/big');
      request
        ..contentLength = size
        ..add(body);
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(await utf8.decodeStream(response), '/big:$size');
    });

    test('a chunked body passes untouched', () async {
      final client = io.HttpClient();
      addTearDown(client.close);
      final request = await client.post('127.0.0.1', server.port, '/chunks');
      request.headers.chunkedTransferEncoding = true;
      for (var i = 0; i < 200; i++) {
        request.add(latin1.encode(_forged));
        await request.flush();
      }
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(
        await utf8.decodeStream(response),
        '/chunks:${200 * _forged.length}',
      );
    });

    test('random framing and packet sizes stay in step with dart:io', () async {
      final random = Random(20261122);
      for (var round = 0; round < 300; round++) {
        final (text, expected) = _randomRequests(random);
        seen.clear();
        final bytes = latin1.encode(text);
        final chunks = <List<int>>[];
        for (var i = 0; i < bytes.length;) {
          final end = min(i + 1 + random.nextInt(40), bytes.length);
          chunks.add(bytes.sublist(i, end));
          i = end;
        }
        final answer = await _exchange(
          await io.Socket.connect('127.0.0.1', server.port),
          chunks,
        );
        expect(seen, expected, reason: 'round $round');
        expect(_count(answer, 'HTTP/1.1 200'), expected.length);
        expect(_count(answer, 'HTTP/1.1 400'), 1, reason: 'round $round');
        expect(answer, contains('more than one Host'), reason: 'round $round');
      }
    });
  });

  test('a WebSocket keeps working, its frames not read as requests', () async {
    final server = IoWebServer(
      FunctionHttpHandler((request, response) async {
        final session = await request.upgradeToWebSocket();
        session.messages.listen(session.sendMessage, onError: (Object _) {});
      }),
      const ServerProperties(port: 0, address: '127.0.0.1'),
    );
    await server.start();
    addTearDown(() => server.stop(timeout: Duration.zero));
    final socket = await io.WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws',
    );
    final answers = StreamIterator<Object?>(socket);
    for (var i = 0; i < 3; i++) {
      socket.add(_forged);
      expect(await answers.moveNext(), isTrue);
      expect(answers.current, _forged);
    }
    await socket.close();
    await answers.cancel();
  });

  test('a graceful stop still answers a request on an open connection, and '
      'refuses two Hosts', () async {
    final (server, seen) = await _serve();
    final socket = await io.Socket.connect('127.0.0.1', server.port);
    final answers = StreamIterator<List<int>>(socket);
    socket.add(latin1.encode('GET /one HTTP/1.1\r\nHost: a\r\n\r\n'));
    expect(await answers.moveNext(), isTrue);
    final stopping = server.stop(timeout: const Duration(seconds: 5));
    socket.add(
      latin1.encode('GET /two HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n'),
    );
    expect(await answers.moveNext(), isTrue);
    expect(latin1.decode(answers.current), startsWith('HTTP/1.1 400'));
    await answers.cancel();
    socket.destroy();
    await stopping;
    expect(seen, ['/one']);
  });

  test('a full server still refuses two Hosts with 400', () async {
    final (server, seen) = await _serve(
      const ServerProperties(maxConnections: 1),
    );
    addTearDown(() => server.stop(timeout: Duration.zero));
    final answer = await _send(
      server.port,
      'GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n',
    );
    expect(answer, startsWith('HTTP/1.1 400'));
    expect(seen, isEmpty);
  });

  group('over TLS', () {
    io.Directory? certificates;

    setUpAll(() async {
      final directory = await io.Directory.systemTemp.createTemp('host_tls');
      try {
        final made = await io.Process.run('openssl', [
          'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
          '-keyout', '${directory.path}/key.pem',
          '-out', '${directory.path}/cert.pem',
          '-days', '1', '-subj', '/CN=localhost',
        ]);
        if (made.exitCode == 0) {
          certificates = directory;
        }
      } on io.ProcessException {
        // No openssl: the tests say so.
      }
    });

    tearDownAll(() => certificates?.delete(recursive: true));

    test('two Hosts are refused, one split over records, and bodies and '
        'keep-alive work', () async {
      final directory = certificates;
      if (directory == null) {
        markTestSkipped('openssl is needed to make a test certificate');
        return;
      }
      final (server, seen) = await _serve(
        ServerProperties(
          ssl: SslSettings(
            certificate: '${directory.path}/cert.pem',
            privateKey: '${directory.path}/key.pem',
          ),
        ),
      );
      addTearDown(() => server.stop(timeout: Duration.zero));
      final socket = await io.SecureSocket.connect(
        '127.0.0.1',
        server.port,
        onBadCertificate: (_) => true,
      );
      const text =
          'POST /one HTTP/1.1\r\nHost: a\r\nContent-Length: ${_forged.length}'
          '\r\n\r\n$_forged'
          'GET /two HTTP/1.1\r\nHost: a\r\n\r\n'
          'GET /bad HTTP/1.1\r\nHost: a\r\nHOST: b\r\n\r\n';
      final bytes = latin1.encode(text);
      final answer = await _exchange(socket, [
        for (var i = 0; i < bytes.length; i += 9)
          bytes.sublist(i, min(i + 9, bytes.length)),
      ]);
      expect(seen, ['/one', '/two']);
      expect(_count(answer, 'HTTP/1.1 200'), 2);
      expect(_count(answer, 'HTTP/1.1 400'), 1);
    });
  });
}

/// A few requests in the framings dart:io reads, its tolerances included,
/// the last with two Hosts, and the paths the handler must get.
(String, List<String>) _randomRequests(Random random) {
  final text = StringBuffer();
  final paths = <String>[];
  final count = 1 + random.nextInt(5);
  T pick<T>(List<T> from) => from[random.nextInt(from.length)];
  for (var i = 0; i < count; i++) {
    final path = '/r$i';
    paths.add(path);
    final eol = pick(['\r\n', '\n']);
    final version = pick(['HTTP/1.1', 'HTTP/1.1xyz']);
    final host = pick(['Host', 'host', 'HOST', 'hOsT']);
    final extra = pick([
      '',
      'X-F: a$eol\tb$eol',
      'X-Host: b$eol',
      'Connection: ,upgrade$eol',
      'Connection: keep-alive$eol',
      'X-Empty:$eol',
      'X-Fold:$eol  c$eol',
    ]);
    final start = '$version$eol$host: a$eol$extra';
    final body = _forged * random.nextInt(3);
    final size = body.length.toRadixString(16);
    final chunks = StringBuffer();
    if (body.isNotEmpty) {
      chunks
        ..write(pick([size, size.toUpperCase(), '00$size']))
        ..write('${pick(['', ';x=1', ';'])}$eol$body$eol');
    }
    chunks.write('${pick(['0', '000', ''])}$eol${pick(['', '\r'])}$eol');
    final length = body.length;
    final framing = pick<String Function()>([
      () => 'GET $path $start$eol',
      () => 'POST $path ${start}Content-Length: $length$eol$eol$body',
      () => 'POST $path ${start}Content-Length: 00$length$eol$eol$body',
      () => 'POST $path ${start}Transfer-Encoding: chunked$eol$eol$chunks',
      () => 'POST $path ${start}Transfer-Encoding: Chunked$eol$eol$chunks',
      () =>
          'POST $path ${start}Transfer-Encoding: gzip$eol'
          'Transfer-Encoding: chunked$eol$eol$chunks',
      () =>
          'POST $path ${start}Transfer-Encoding: chunked$eol'
          'Content-Length: 3$eol$eol$chunks',
    ]);
    text.write(framing());
  }
  text.write('GET /bad HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n');
  return ('$text', paths);
}
