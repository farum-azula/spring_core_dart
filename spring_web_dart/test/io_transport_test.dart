@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  late io.HttpServer server;
  late Uri base;
  final transport = IoHttpTransport();

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/json':
          response.headers.contentType = io.ContentType.json;
          response.write('{"isbn":"1"}');
        case '/echo':
          final body = await utf8.decodeStream(request);
          response.headers.set('X-Method', request.method);
          response.headers.set(
            'X-Got',
            request.headers.value('X-Request-Id') ?? '',
          );
          response.statusCode = 201;
          response.write(body);
        case '/missing':
          response.statusCode = 404;
          response.write('nope');
        case '/old':
          await response.redirect(base.resolve('/json'));
          return;
        case '/slow':
          await Future<void>.delayed(const Duration(milliseconds: 500));
          response.write('late');
      }
      await response.close();
    });
  });

  tearDownAll(() async {
    transport.close();
    await server.close(force: true);
  });

  test('GET with JSON', () async {
    final response = await transport.send(
      HttpRequest(method: HttpMethod.get, url: base.resolve('/json')),
    );
    expect(response.statusCode, 200);
    expect(jsonDecode(response.bodyText), {'isbn': '1'});
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(response.request!.url.path, '/json');
  });

  test('POST with headers and body', () async {
    final response = await transport.send(
      HttpRequest(
        method: HttpMethod.post,
        url: base.resolve('/echo'),
        headers: HttpHeaders({
          'X-Request-Id': 'r-1',
          'Content-Type': 'text/plain',
        }),
        body: utf8.encode('hello'),
      ),
    );
    expect(response.statusCode, 201);
    expect(response.bodyText, 'hello');
    expect(response.headers['x-method'], 'POST');
    expect(response.headers['x-got'], 'r-1');
  });

  test('error statuses are responses, redirects are followed', () async {
    final missing = await transport.send(
      HttpRequest(method: HttpMethod.get, url: base.resolve('/missing')),
    );
    expect(missing.statusCode, 404);
    expect(missing.bodyText, 'nope');
    final moved = await transport.send(
      HttpRequest(method: HttpMethod.get, url: base.resolve('/old')),
    );
    expect(moved.statusCode, 200);
    expect(moved.bodyText, '{"isbn":"1"}');
  });

  test('timeouts and refused connections', () async {
    await expectLater(
      transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: base.resolve('/slow'),
          timeout: const Duration(milliseconds: 50),
        ),
      ),
      throwsA(
        isA<HttpTransportException>().having(
          (e) => e.isTimeout,
          'isTimeout',
          isTrue,
        ),
      ),
    );
    final free = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
    final port = free.port;
    await free.close();
    await expectLater(
      transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('http://127.0.0.1:$port/'),
        ),
      ),
      throwsA(
        isA<HttpTransportException>().having(
          (e) => e.isTimeout,
          'isTimeout',
          isFalse,
        ),
      ),
    );
  });

  test('platformHttpTransport is the dart:io one here', () {
    final platform = platformHttpTransport(
      connectTimeout: const Duration(seconds: 1),
    );
    expect(platform, isA<IoHttpTransport>());
    platform.close();
  });
}
