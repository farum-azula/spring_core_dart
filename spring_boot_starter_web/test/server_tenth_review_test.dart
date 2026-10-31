// Regression tests of the tenth review before 0.5.0 over real sockets:
// answers without a body or a media type. `dart:io` labels every answer
// whose type the application did not set `text/plain; charset=utf-8`, and
// gives a 204 or 304 without a body `Content-Length: 0` (a HEAD one
// `Transfer-Encoding: chunked`). RFC 9110 §8.6 forbids that length on a
// 1xx or 204; a cache updating its stored answer with a 304's headers
// (RFC 9111 §4.3.4) would store the wrong type, which `nosniff` browsers
// then refuse for a script or style sheet. The expected values are
// Tomcat 11's (Spring Boot 4, Spring MVC 7.0.10, October 2026): no
// `Content-Type` unless set (none on a 304 at all), no `Content-Length`
// and no `Transfer-Encoding` on a 1xx, 204 or 304.
@Tags(['integration'])
library;

import 'dart:io' as io;

import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'server_review_test.dart' show raw, serve, statusOf;

// The header names of [response] (lower case) with their values.
Map<String, List<String>> _headersOf(String response) {
  final head = response.substring(0, response.indexOf('\r\n\r\n'));
  final headers = <String, List<String>>{};
  for (final line in head.split('\r\n').skip(1)) {
    final colon = line.indexOf(':');
    headers
        .putIfAbsent(line.substring(0, colon).trim().toLowerCase(), () => [])
        .add(line.substring(colon + 1).trim());
  }
  return headers;
}

String _bodyOf(String response) =>
    response.substring(response.indexOf('\r\n\r\n') + 4);

void main() {
  late IoWebServer server;
  late io.File css;
  final writer = ResponseWriter(mapper: ObjectMapper());

  setUpAll(() async {
    css = io.File(
      '${io.Directory.systemTemp.createTempSync('tenth_').path}/site.css',
    )..writeAsStringSync('body { color: red }\n');
    server = await serve((request, response) async {
      switch (request.path) {
        case '/json':
          return await writer.writeResult(
            ResponseEntity.status(200).eTag('"v1"').body({'a': 1}),
            request,
            response,
          );
        case '/typed-json':
          return await writer.writeResult(
            ResponseEntity.status(
              200,
            ).contentType('application/json').eTag('"v1"').body({'a': 1}),
            request,
            response,
          );
        case '/site.css':
          return await writer.writeResource(
            FileSystemResource(css.path),
            request,
            response,
          );
        case '/no-content':
          response.statusCode = 204;
          return await response.close();
        case '/no-content-typed':
          response
            ..statusCode = 204
            ..headers.contentType = 'application/json';
          return await response.close();
        case '/no-content-body':
          return await response.send(204, 'x');
        case '/empty':
          return await response.close();
        case '/empty-typed':
          response.headers.contentType = 'application/json';
          return await response.close();
        case '/ws':
          await request.upgradeToWebSocket();
          return;
      }
      await response.send(200, 'hello', contentType: 'text/plain');
    }, const ServerProperties(compression: true));
  });

  tearDownAll(() async {
    await server.stop(timeout: Duration.zero);
    css.parent.deleteSync(recursive: true);
  });

  Future<String> send(
    String method,
    String path, [
    Map<String, String> headers = const {},
  ]) => raw(
    server.port,
    '$method $path HTTP/1.1\r\nHost: 127.0.0.1\r\n'
    '${headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join()}'
    'Connection: close\r\n\r\n',
  );

  void expectBodiless(String response, int status, {String? reason}) {
    expect(statusOf(response), status, reason: reason);
    final headers = _headersOf(response);
    expect(headers['content-length'], isNull, reason: reason);
    expect(headers['transfer-encoding'], isNull, reason: reason);
    expect(_bodyOf(response), isEmpty, reason: reason);
  }

  test('a 304 for an ETag: no Content-Type, no Content-Length, GET and HEAD '
      '(Spring MVC: the same)', () async {
    for (final method in ['GET', 'HEAD']) {
      for (final path in ['/json', '/typed-json']) {
        final response = await send(method, path, {'If-None-Match': '"v1"'});
        final reason = '$method $path';
        expectBodiless(response, 304, reason: reason);
        final headers = _headersOf(response);
        expect(headers['content-type'], isNull, reason: reason);
        expect(headers['etag'], ['"v1"'], reason: reason);
      }
    }
  });

  test(
    'a 304 for a file: no Content-Type, so a cache keeps text/css',
    () async {
      final full = await send('GET', '/site.css');
      expect(statusOf(full), 200);
      expect(_headersOf(full)['content-type'], ['text/css']);
      for (final method in ['GET', 'HEAD']) {
        final response = await send(method, '/site.css', {
          'If-Modified-Since': 'Thu, 01 Jan 2099 00:00:00 GMT',
        });
        expectBodiless(response, 304, reason: method);
        expect(_headersOf(response)['content-type'], isNull, reason: method);
      }
    },
  );

  test('a 204: no Content-Length, no Transfer-Encoding; a Content-Type only '
      'when set (Tomcat keeps it on a 204)', () async {
    for (final method in ['GET', 'HEAD']) {
      final plain = await send(method, '/no-content');
      expectBodiless(plain, 204, reason: method);
      expect(_headersOf(plain)['content-type'], isNull, reason: method);
      final typed = await send(method, '/no-content-typed');
      expectBodiless(typed, 204, reason: method);
      expect(_headersOf(typed)['content-type'], [
        'application/json',
      ], reason: method);
    }
  });

  test('a body written to a 204 is dropped, so the connection serves the '
      'next request (Tomcat drops it too)', () async {
    final response = await raw(
      server.port,
      'GET /no-content-body HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n'
      'GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n',
    );
    expect(statusOf(response), 204);
    final rest = _bodyOf(response);
    expect(rest, startsWith('HTTP/1.1 200 '));
    expect(_headersOf(response)['content-length'], isNull);
    expect(_bodyOf(rest), 'hello');
  });

  test('an empty 200: Content-Length: 0, the Content-Type only when set; '
      'no text/plain of dart:io', () async {
    final plain = await send('GET', '/empty');
    expect(statusOf(plain), 200);
    expect(_headersOf(plain)['content-type'], isNull);
    expect(_headersOf(plain)['content-length'], ['0']);
    final typed = await send('GET', '/empty-typed');
    expect(statusOf(typed), 200);
    expect(_headersOf(typed)['content-type'], ['application/json']);
    expect(_headersOf(typed)['content-length'], ['0']);
  });

  test("a HEAD keeps the GET's Content-Type and Content-Length", () async {
    final get = await send('GET', '/hello');
    final head = await send('HEAD', '/hello');
    for (final response in [get, head]) {
      expect(statusOf(response), 200);
      expect(_headersOf(response)['content-type'], ['text/plain']);
      expect(_headersOf(response)['content-length'], ['5']);
    }
    expect(_bodyOf(get), 'hello');
    expect(_bodyOf(head), isEmpty);
  });

  test('the 101 of a WebSocket handshake: no Content-Length, no '
      'Content-Type, no Transfer-Encoding', () async {
    final response = await raw(
      server.port,
      'GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n'
      'Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n'
      'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n',
      timeout: const Duration(seconds: 2),
    );
    expect(statusOf(response), 101);
    final headers = _headersOf(response);
    expect(headers['sec-websocket-accept'], ['s3pPLMBiTxaQ9kYGzzhZRbK+xOo=']);
    expect(headers['content-length'], isNull);
    expect(headers['content-type'], isNull);
    expect(headers['transfer-encoding'], isNull);
  });
}
