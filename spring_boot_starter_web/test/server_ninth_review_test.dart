// Regression tests of the ninth review before 0.5.0 over real sockets:
// `Vary: Accept-Encoding` on every answer that would be compressed for a
// client that takes gzip, also when this client does not take it, as
// Tomcat adds it (a cache must not hand the plain answer to a client that
// takes gzip, nor the reverse). The expected values are Tomcat 11's
// (Spring Boot 4, server.compression.enabled, October 2026).
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'server_review_test.dart' show serve;

void main() {
  late IoWebServer server;
  final big = 'x' * 5000;

  setUpAll(() async {
    server = await serve((request, response) async {
      final headers = response.headers;
      switch (request.path) {
        case '/vary-star':
          headers
            ..add('Vary', 'Origin')
            ..add('Vary', '*');
        case '/vary-own':
          headers.add('Vary', 'accept-encoding');
        case '/strong':
          headers.eTag = '"v1"';
        case '/weak':
          headers.eTag = 'W/"v1"';
        case '/not-modified':
          response.statusCode = 304;
          return await response.close();
        case '/small':
          return await response.send(200, 'x', contentType: 'text/plain');
        case '/png':
          return await response.send(200, big, contentType: 'image/png');
      }
      await response.send(200, big, contentType: 'text/plain');
    }, const ServerProperties(compression: true));
  });

  tearDownAll(() => server.stop(timeout: Duration.zero));

  Future<io.HttpClientResponse> send(
    String path, {
    String method = 'GET',
    String? acceptEncoding,
  }) async {
    final client = io.HttpClient()..autoUncompress = false;
    addTearDown(() => client.close(force: true));
    final request = await client.open(method, '127.0.0.1', server.port, path);
    request.headers.removeAll('accept-encoding');
    if (acceptEncoding != null) {
      request.headers.set('Accept-Encoding', acceptEncoding);
    }
    return await request.close();
  }

  test('a compressible answer to a client without gzip: '
      'Vary: Accept-Encoding, not compressed', () async {
    for (final acceptEncoding in [null, 'identity', 'br', 'gzip;q=0']) {
      for (final method in ['GET', 'HEAD']) {
        final response = await send(
          '/big',
          method: method,
          acceptEncoding: acceptEncoding,
        );
        final reason = '$method $acceptEncoding';
        expect(response.statusCode, 200, reason: reason);
        expect(response.headers.value('content-encoding'), isNull);
        expect(response.headers['vary'], ['Accept-Encoding'], reason: reason);
      }
    }
    final plain = await send('/big');
    expect(utf8.decode(await plain.expand((c) => c).toList()), big);
  });

  test('with gzip: compressed, the same Vary', () async {
    final response = await send('/big', acceptEncoding: 'gzip');
    expect(response.headers.value('content-encoding'), 'gzip');
    expect(response.headers['vary'], ['Accept-Encoding']);
    expect(
      utf8.decode(io.gzip.decode(await response.expand((c) => c).toList())),
      big,
    );
  });

  test('Vary merged as Tomcat merges it: once, and a * among the names '
      'becomes the whole Vary', () async {
    for (final acceptEncoding in [null, 'gzip']) {
      expect(
        (await send(
          '/vary-own',
          acceptEncoding: acceptEncoding,
        )).headers['vary'],
        ['accept-encoding'],
      );
      expect(
        (await send(
          '/vary-star',
          acceptEncoding: acceptEncoding,
        )).headers['vary'],
        ['*'],
        reason: '$acceptEncoding',
      );
    }
  });

  test('a strong ETag: never compressed, no Vary (it promises these very '
      'bytes); a weak one is', () async {
    for (final acceptEncoding in [null, 'gzip']) {
      final strong = await send('/strong', acceptEncoding: acceptEncoding);
      expect(strong.headers.value('content-encoding'), isNull);
      expect(strong.headers['vary'], isNull, reason: '$acceptEncoding');
      final weak = await send('/weak', acceptEncoding: acceptEncoding);
      expect(weak.headers['vary'], ['Accept-Encoding']);
    }
    final weak = await send('/weak', acceptEncoding: 'gzip');
    expect(weak.headers.value('content-encoding'), 'gzip');
  });

  test('not compressible (too small, another type, a 304): no Vary', () async {
    for (final path in ['/small', '/png', '/not-modified']) {
      for (final acceptEncoding in [null, 'gzip']) {
        final response = await send(path, acceptEncoding: acceptEncoding);
        expect(response.headers.value('content-encoding'), isNull);
        expect(response.headers['vary'], isNull, reason: path);
      }
    }
  });
}
