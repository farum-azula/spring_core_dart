@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  late io.HttpServer server;
  late Uri base;
  final endless = Completer<void>();
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
          response.headers.set(
            'X-User-Agent',
            request.headers['user-agent']?.join(' | ') ?? '',
          );
          response.headers.set(
            'X-Tags',
            request.headers['x-tag']?.join(' | ') ?? '',
          );
          response
            ..statusCode = 201
            ..write(body);
        case '/missing':
          response
            ..statusCode = 404
            ..write('nope');
        case '/old':
          await response.redirect(base.resolve('/json'));
          return;
        case '/events':
          response.headers.contentType = io.ContentType('text', 'event-stream');
          response.bufferOutput = false;
          for (var i = 1; i <= 3; i++) {
            response.write('id: $i\ndata: tick $i\n\n');
            await response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        case '/endless':
          response.bufferOutput = false;
          // Write errors after the client left go to `done`.
          unawaited(
            response.done.then(
              (_) => endless.complete(),
              onError: (Object _) => endless.complete(),
            ),
          );
          while (!endless.isCompleted) {
            response.write('data: first\n\n');
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          return;
        case '/slow':
          await Future<void>.delayed(const Duration(milliseconds: 500));
          response.write('late');
        case '/trickle':
          // Steady data, slower in total than a short deadline.
          response.bufferOutput = false;
          for (var i = 0; i < 6; i++) {
            response.write('$i');
            await response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        case '/stall':
          // Headers and a first chunk, then silence.
          response
            ..bufferOutput = false
            ..write('first');
          await response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 600));
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

  test(
    'request headers replace the defaults; repeated names are kept',
    () async {
      final response = await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: base.resolve('/echo'),
          headers: HttpHeaders()
            ..set('User-Agent', 'neon-books/1.0')
            ..add('X-Tag', 'a')
            ..add('X-Tag', 'b'),
        ),
      );
      // Not "Dart/3.x (dart:io), neon-books/1.0".
      expect(response.headers['x-user-agent'], 'neon-books/1.0');
      // Both values sent (dart:io joins them into one line, as HTTP allows).
      expect(response.headers['x-tags'], 'a, b');
    },
  );

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

  test('readTimeout is the longest wait for data, not a deadline', () async {
    // 6 chunks 40 ms apart: never 400 ms without data, even on a loaded
    // machine (several test processes at once)...
    final steady = await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: base.resolve('/trickle'),
        readTimeout: const Duration(milliseconds: 400),
      ),
    );
    expect(steady.bodyText, '012345');
    // ... but longer than a 150 ms deadline for the whole exchange.
    await expectLater(
      transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: base.resolve('/trickle'),
          timeout: const Duration(milliseconds: 150),
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
    // Silence in the middle of the body.
    await expectLater(
      transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: base.resolve('/stall'),
          readTimeout: const Duration(milliseconds: 100),
        ),
      ),
      throwsA(
        isA<HttpTransportException>()
            .having((e) => e.isTimeout, 'isTimeout', isTrue)
            .having((e) => e.message, 'message', contains('read timeout')),
      ),
    );
    // No response at all.
    await expectLater(
      transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: base.resolve('/slow'),
          readTimeout: const Duration(milliseconds: 50),
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
  });

  test('followRedirects: false returns the redirect', () async {
    final moved = await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: base.resolve('/old'),
        followRedirects: false,
      ),
    );
    expect(moved.statusCode, HttpStatus.found);
    expect(moved.statusCode.is3xxRedirection, isTrue);
    expect(moved.headers.location, base.resolve('/json'));
  });

  test('stream reads the body as it arrives', () async {
    final response = await transport.stream(
      HttpRequest(
        method: HttpMethod.get,
        url: base.resolve('/events'),
        timeout: const Duration(milliseconds: 30),
      ),
    );
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], startsWith('text/event-stream'));
    // The timeout covered the headers only: the body takes longer.
    final events = await response.body.transform(const SseDecoder()).toList();
    expect([for (final e in events) e.data], ['tick 1', 'tick 2', 'tick 3']);
    expect(events.last.id, '3');
  });

  test('cancelling a streamed body closes the connection', () async {
    final response = await transport.stream(
      HttpRequest(method: HttpMethod.get, url: base.resolve('/endless')),
    );
    final first = await response.body.transform(const SseDecoder()).first;
    expect(first.data, 'first');
    // The server sees the connection go away.
    await endless.future.timeout(const Duration(seconds: 5));
  });

  test('platformHttpTransport is the dart:io one here', () {
    final platform = platformHttpTransport(
      connectTimeout: const Duration(seconds: 1),
    );
    expect(platform, isA<IoHttpTransport>());
    platform.close();
  });
}
