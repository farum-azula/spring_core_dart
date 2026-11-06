// Static resources over a real socket (dart:io): the attack catalog sent
// as raw request targets (the server parses them, not a test double), the
// answers with server compression, Range and HEAD on the wire.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:test/test.dart';

import 'static_resources_attack_test.dart' show attackCatalog;
import 'support.dart';

/// One raw HTTP/1.1 exchange: [target] is written as it is, in UTF-8.
Future<(int, String, String)> rawRequest(
  int port,
  String method,
  String target, {
  Map<String, String> headers = const {},
}) async {
  final socket = await io.Socket.connect('127.0.0.1', port);
  final head = StringBuffer('$method $target HTTP/1.1\r\n')
    ..write('Host: 127.0.0.1:$port\r\n')
    ..write('Connection: close\r\n');
  headers.forEach((name, value) => head.write('$name: $value\r\n'));
  head.write('\r\n');
  socket.add(utf8.encode('$head'));
  await socket.flush();
  final bytes = await socket.fold<List<int>>(
    [],
    (all, chunk) => all..addAll(chunk),
  );
  socket.destroy();
  final text = latin1.decode(bytes);
  final end = text.indexOf('\r\n\r\n');
  final head0 = end < 0 ? text : text.substring(0, end);
  final body = end < 0 ? '' : text.substring(end + 4);
  final status = int.parse(head0.split(' ')[1]);
  return (status, head0, body);
}

void main() {
  late io.Directory root;
  late io.Directory site;
  const secret = 'TOP-SECRET-CONTENT';
  final big = 'body { color: red; }\n' * 400;

  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('static_server_');
    site = io.Directory('${root.path}/site')..createSync();
    final files = <String, String>{
      'site/index.html': '<h1>home</h1>',
      'site/app.js': 'console.log(1);',
      'site/app.js.br': 'BROTLI',
      'site/big.css': big,
      'site/.env': secret,
      'site/.git/config': secret,
      'site/%2e%2e/secret.txt': secret,
      'secret.txt': secret,
      'site-other/secret.txt': secret,
    };
    for (final MapEntry(:key, :value) in files.entries) {
      io.File('${root.path}/$key')
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  Future<void> withServer(
    Future<void> Function(Client client) body, [
    List<String> properties = const [],
  ]) =>
      webRunner([
        'spring.web.resources.static-locations=file:${site.path}/',
        ...properties,
      ]).runAsync((context) async {
        expect(context.startupFailure, isNull);
        final client = await Client.of(context.context);
        try {
          await body(client);
        } finally {
          client.close();
        }
      });

  test(
    'the attack catalog over the wire: 400 or 404, never the secret',
    () async {
      await withServer((client) async {
        for (final MapEntry(key: category, value: payloads)
            in attackCatalog.entries) {
          for (final payload in payloads) {
            // A request line cannot carry whitespace or control characters.
            if (payload.runes.any((r) => r <= 0x20 || r == 0x7F)) {
              continue;
            }
            final (status, _, body) = await rawRequest(
              client.port,
              'GET',
              '/$payload',
              headers: {'Accept': 'text/html'},
            );
            expect(
              body,
              isNot(contains(secret)),
              reason: '$category: $payload',
            );
            // dart:io resolves raw dot segments before the server sees
            // the target (`/..` arrives as `/`): the welcome page, never
            // more.
            if (status == 200) {
              expect(body, '<h1>home</h1>', reason: '$category: $payload');
            } else {
              expect(
                status,
                anyOf(400, 404),
                reason: '$category: ${Uri.encodeFull(payload)}',
              );
            }
          }
        }
        // An absolute target, and one that starts with //.
        for (final target in [
          'http://127.0.0.1:${client.port}/../secret.txt',
          'http://127.0.0.1:${client.port}/%2e%2e/secret.txt',
          '//../secret.txt',
          '/..//..//secret.txt',
        ]) {
          final (status, _, body) = await rawRequest(
            client.port,
            'GET',
            target,
          );
          expect(body, isNot(contains(secret)), reason: target);
          expect(status, anyOf(400, 404), reason: target);
        }
      }, ['spring.web.resources.spa-fallback=true']);
    },
  );

  test('a file over the wire: type, nosniff, Range, HEAD', () async {
    await withServer((client) async {
      final reply = await client.get('/app.js');
      expect(reply.status, 200);
      expect(reply.body, 'console.log(1);');
      expect(reply.headers.contentType?.mimeType, 'text/javascript');
      expect(reply.headers.value('x-content-type-options'), 'nosniff');
      final range = await client.get(
        '/app.js',
        headers: {'Range': 'bytes=0-6'},
      );
      expect(range.status, 206);
      expect(range.body, 'console');
      final (status, head, body) = await rawRequest(
        client.port,
        'HEAD',
        '/app.js',
      );
      expect(status, 200);
      expect(head.toLowerCase(), contains('content-length: 15'));
      expect(body, isEmpty);
      final home = await client.get('/', headers: {'Accept': 'text/html'});
      expect(home.body, '<h1>home</h1>');
    });
  });

  test('server compression gzips a file (its ETag is weak)', () async {
    await withServer(
      (client) async {
        final response = await client.open(
          '/big.css',
          headers: {'Accept-Encoding': 'gzip'},
        );
        expect(response.headers.value('content-encoding'), 'gzip');
        expect(response.headers.value('etag'), startsWith('W/'));
        final bytes = await response.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        // HttpClient decompresses gzip itself.
        expect(utf8.decode(bytes), big);
      },
      [
        'server.compression.enabled=true',
        'server.compression.mime-types=text/css',
      ],
    );
  });

  test('a precompressed variant is not compressed again', () async {
    await withServer(
      (client) async {
        final (status, head, body) = await rawRequest(
          client.port,
          'GET',
          '/app.js',
          headers: {'Accept-Encoding': 'br, gzip'},
        );
        expect(status, 200);
        expect(head.toLowerCase(), contains('content-encoding: br'));
        expect(head.toLowerCase(), contains('vary: accept-encoding'));
        expect(body, 'BROTLI');
      },
      [
        'server.compression.enabled=true',
        'server.compression.min-response-size=0',
        'server.compression.mime-types=text/javascript',
        'spring.web.resources.chain.compressed=true',
      ],
    );
  });
}
