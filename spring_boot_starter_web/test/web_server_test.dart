@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'app/web_config.dart';
import 'support.dart';

void main() {
  late ApplicationContextRunner runner;

  setUp(() => runner = webRunner());

  Future<void> withServer(
    Future<void> Function(Client client, ApplicationContext context) body,
  ) => runner.runAsync((context) async {
    expect(context.startupFailure, isNull);
    final client = await Client.of(context.context);
    try {
      await body(client, context.context);
    } finally {
      client.close();
    }
  });

  test(
    'a request target starting with // is a path, not a host',
    () => withServer((client, _) async {
      // Dart reads `//books/api/books/1111` as the host `books` and the
      // path `/api/books/1111`; the server puts the path back together, so
      // it is not routed to /api/books/1111.
      final socket = await io.Socket.connect('127.0.0.1', client.port);
      socket.add(
        latin1.encode(
          'GET //books/api/books/1111 HTTP/1.1\r\nHost: localhost\r\n'
          'Connection: close\r\n\r\n',
        ),
      );
      final text = latin1.decode(
        await socket.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
      );
      socket.destroy();
      expect(text.split('\r\n').first, contains('404'));
    }),
  );

  test(
    '@RequestParam reads the fields of a form body, like servlet parameters',
    () => withServer((client, _) async {
      final reply = await client.send(
        'POST',
        '/api/books/form',
        body: 'title=Dune&count=2',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      expect(reply.status, 200);
      expect(reply.body, 'Dune x2');
    }),
  );

  test(
    'a controller answers with JSON',
    () => withServer((client, _) async {
      final reply = await client.get('/api/books/1111');
      expect(reply.status, 200);
      expect(reply.headers.contentType?.mimeType, 'application/json');
      expect(reply.json, {
        'isbn': '1111',
        'title': 'Dune',
        'stock': 3,
        'genre': 'fiction',
      });
      expect(reply.headers.value('X-Trace'), 'on');
    }),
  );

  test(
    'query parameters, defaults and enums',
    () => withServer((client, _) async {
      var reply = await client.get('/api/books?q=');
      expect((reply.json! as List).length, 2);
      reply = await client.get('/api/books?q=&genre=science');
      expect(reply.json, [
        {'isbn': '2222', 'title': 'Cosmos', 'stock': 0, 'genre': 'science'},
      ]);
      reply = await client.get('/api/books');
      expect(reply.status, 400);
      expect(reply.headers.contentType?.mimeType, 'application/problem+json');
      expect(
        (reply.json! as Map)['detail'],
        "Required parameter 'q' is not present.",
      );
      reply = await client.get('/api/books?q=x&page=abc');
      expect(reply.status, 400);
    }),
  );

  test(
    'a valid body creates, an invalid one is a 400 with the errors',
    () => withServer((client, _) async {
      var reply = await client.send(
        'POST',
        '/api/books',
        json: {'isbn': '3333', 'title': 'Solaris', 'stock': 1},
      );
      expect(reply.status, 201);
      expect(reply.headers.value('location'), '/api/books/3333');
      expect((reply.json! as Map)['title'], 'Solaris');

      reply = await client.send(
        'POST',
        '/api/books',
        json: {'isbn': '', 'title': ''},
      );
      expect(reply.status, 400);
      final problem = reply.json! as Map;
      expect(problem['detail'], 'Invalid request content.');
      expect([
        for (final e in problem['errors'] as List) (e as Map)['field'],
      ], containsAll(['isbn', 'title']));

      reply = await client.send(
        'POST',
        '/api/books',
        body: '{not json',
        headers: {'Content-Type': 'application/json'},
      );
      expect(reply.status, 400);
    }),
  );

  test(
    'exception handlers: local, advice, default',
    () => withServer((client, _) async {
      var reply = await client.get('/api/books/9');
      expect(reply.status, 404);
      expect(reply.json, {
        'type': 'about:blank',
        'title': 'Not Found',
        'status': 404,
        'detail': 'No book 9',
        'instance': '/api/books/9',
        'isbn': '9',
      });
      reply = await client.send(
        'POST',
        '/api/books',
        json: {'isbn': '1111', 'title': 'Again'},
      );
      expect(reply.status, 409);
      reply = await client.get('/misc/boom');
      expect(reply.status, 500);
      expect((reply.json! as Map)['title'], 'Internal Server Error');
      expect((reply.json! as Map).containsKey('detail'), isFalse);
    }),
  );

  test(
    '404, 405 with Allow, 415, OPTIONS, HEAD',
    () => withServer((client, _) async {
      var reply = await client.get('/nothing');
      expect(reply.status, 404);
      reply = await client.send('PUT', '/api/books/1111');
      expect(reply.status, 405);
      expect(reply.headers.value('allow'), contains('GET'));
      reply = await client.send(
        'POST',
        '/misc/json-only',
        body: 'x',
        headers: {'Content-Type': 'text/plain'},
      );
      expect(reply.status, 415);
      reply = await client.send('OPTIONS', '/api/books/1111');
      expect(reply.status, 200);
      expect(reply.headers.value('allow'), contains('DELETE'));
      reply = await client.send('HEAD', '/misc/text');
      expect(reply.status, 200);
      expect(reply.body, isEmpty);
      expect(reply.headers.contentLength, 5);
    }),
  );

  test(
    '@ResponseStatus, ResponseStatusException',
    () => withServer((client, _) async {
      expect((await client.send('DELETE', '/api/books/2222')).status, 204);
      expect((await client.send('DELETE', '/api/books/2222')).status, 404);
    }),
  );

  test(
    'text, bytes, headers, cookies, lists, rest of the path',
    () => withServer((client, _) async {
      var reply = await client.get('/misc/text');
      expect(reply.body, 'hello');
      expect(reply.headers.contentType?.mimeType, 'text/plain');
      reply = await client.get('/misc/echo-header', headers: {'X-Name': 'Ann'});
      expect(reply.body, 'hi Ann');
      reply = await client.get('/misc/echo-header');
      expect(reply.status, 400);
      reply = await client.get(
        '/misc/cookie',
        headers: {'Cookie': 'session=abc; other=1'},
      );
      expect(reply.body, 'abc');
      reply = await client.get('/misc/ids?id=1&id=2');
      expect(reply.json, [1, 2]);
      reply = await client.get('/misc/ids?id=3,4');
      expect(reply.json, [3, 4]);
      reply = await client.get('/misc/files/a/b%20c.txt');
      expect(reply.body, '/a/b c.txt');
      reply = await client.get('/misc/request');
      expect(reply.body, 'GET /misc/request');
      final bytes = await client.open('/misc/bytes');
      expect(await bytes.expand((c) => c).toList(), [1, 2, 3]);
    }),
  );

  test(
    '406 when Accept excludes JSON',
    () => withServer((client, _) async {
      final reply = await client.get(
        '/api/books/1111',
        headers: {'Accept': 'text/csv'},
      );
      expect(reply.status, 406);
    }),
  );

  test(
    'CORS: pre-flight and actual requests',
    () => withServer((client, _) async {
      var reply = await client.send(
        'OPTIONS',
        '/api/books',
        headers: {
          'Origin': 'https://shop.example',
          'Access-Control-Request-Method': 'POST',
        },
      );
      expect(reply.status, 200);
      expect(
        reply.headers.value('access-control-allow-origin'),
        'https://shop.example',
      );
      reply = await client.send(
        'OPTIONS',
        '/api/books',
        headers: {
          'Origin': 'https://evil.example',
          'Access-Control-Request-Method': 'POST',
        },
      );
      expect(reply.status, 403);
      reply = await client.get(
        '/api/books/1111',
        headers: {'Origin': 'https://shop.example'},
      );
      expect(
        reply.headers.value('access-control-allow-origin'),
        'https://shop.example',
      );
      reply = await client.get(
        '/api/books/1111',
        headers: {'Origin': 'https://evil.example'},
      );
      expect(reply.status, 403);
    }),
  );

  test(
    'interceptors run for their paths',
    () => withServer((client, context) async {
      final config = context.getBeanByName('webConfig');
      await client.get('/api/books/1111');
      await client.get('/misc/text');
      expect((config as WebConfig).interceptor.count, 1);
    }),
  );

  test(
    'server-sent events from an EventStream and an SseEmitter',
    () => withServer((client, _) async {
      Future<String> until(Stream<List<int>> body, String text) async {
        final out = StringBuffer();
        await for (final chunk in body.transform(utf8.decoder)) {
          out.write(chunk);
          if (out.toString().contains(text)) {
            break;
          }
        }
        return out.toString();
      }

      final stream = await client.open('/api/books/changes');
      expect(stream.headers.contentType?.mimeType, 'text/event-stream');
      final emitter = await client.open('/api/books/notifications');
      final changes = until(stream, 'Ubik');
      final notifications = until(emitter, 'Ubik');
      await client.send(
        'POST',
        '/api/books',
        json: {'isbn': '4444', 'title': 'Ubik'},
      );
      expect(
        await changes,
        allOf(contains('id: 4444'), contains('"title":"Ubik"')),
      );
      expect(await notifications, contains('event: created'));
    }),
  );

  test(
    'NDJSON from a Stream',
    () => withServer((client, _) async {
      final reply = await client.get('/misc/ndjson');
      expect(reply.headers.contentType?.mimeType, 'application/x-ndjson');
      expect(const LineSplitter().convert(reply.body).map(jsonDecode), [
        {'isbn': '1', 'title': 'A', 'stock': 0, 'genre': 'fiction'},
        {'isbn': '2', 'title': 'B', 'stock': 0, 'genre': 'fiction'},
      ]);
    }),
  );

  test('a port in use fails the startup with the analysis', () async {
    final blocker = await io.ServerSocket.bind('127.0.0.1', 0);
    try {
      await webRunner([
        'spring.test.web-environment=defined-port',
        'server.port=${blocker.port}',
      ]).runAsync((context) async {
        final lifecycle = context.context
            .getBean<WebServerStartStopLifecycle>();
        await expectLater(
          lifecycle.started,
          throwsA(isA<PortInUseException>()),
        );
      });
    } finally {
      await blocker.close();
    }
  });

  test('a graceful shutdown lets running requests finish', () async {
    late Client client;
    late Future<Reply> slow;
    await webRunner().runAsync((context) async {
      client = await Client.of(context.context);
      slow = client.get('/misc/slow');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }); // closes the context while the request runs
    expect((await slow).body, 'done');
    await expectLater(client.get('/misc/text'), throwsA(isA<io.IOException>()));
    client.close();
  });

  test('a context closed while the socket opens leaves no server', () async {
    WebServer? server;
    webRunner().run((context) {
      server = context.context.getBean<WebServerStartStopLifecycle>().webServer;
    }); // closes right away, before the bind completes
    expect(server, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server!.port, -1);
  });

  test('spring.main.web-application-type=none starts no server', () async {
    await webRunner(['spring.main.web-application-type=none']).runAsync((
      context,
    ) async {
      expect(
        await context.context.getBean<WebServerStartStopLifecycle>().started,
        isNull,
      );
    });
  });

  test(
    'local.server.port and WebServerInitializedEvent',
    () => withServer((client, context) async {
      expect(
        context.environment.getProperty('local.server.port'),
        '${client.port}',
      );
    }),
  );
}
