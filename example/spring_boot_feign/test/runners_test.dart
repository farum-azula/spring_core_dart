// The runners against the mocks: what the application prints, and how it
// behaves when a server fails. The runners are called directly (a context
// runner does not start them), so each test waits for its runner.
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_feign_example/src/blog_runner.dart';
import 'package:spring_boot_feign_example/src/live_runners.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/app.dart';
import 'support/fixtures.dart' as fixtures;

final _args = ApplicationArguments(const []);

void main() {
  // logging.level.* is applied by SpringApplication, not by a context runner.
  final logs = captureLogs(level: SpringLogLevel.info);
  late MockHttpTransport server;
  late MockWebSocketTransport sockets;

  setUp(() {
    server = MockHttpTransport();
    sockets = MockWebSocketTransport();
  });

  ApplicationContextRunner app([List<String> properties = const []]) =>
      appContext()
          .withBean<HttpTransport>(() => server)
          .withBean<WebSocketTransport>(() => sockets)
          .withPropertyValues(properties);

  List<String> linesOf(String logger) => [
    for (final record in logs.records)
      if (record.loggerName == logger) record.message,
  ];

  group('BlogRunner', () {
    test('prints the user, posts, comments, the new post and a 404', () async {
      server
        ..when(HttpMethod.get, '/users/1').respond(200, json: fixtures.user)
        ..when(
          HttpMethod.get,
          '/posts?userId=1',
        ).respond(200, json: fixtures.posts)
        ..when(
          HttpMethod.get,
          '/posts/1/comments',
        ).respond(200, json: fixtures.comments)
        ..when(HttpMethod.post, '/posts').respondWith(
          (request) => HttpResponse(
            201,
            headers: HttpHeaders({
              HttpHeaders.contentTypeHeader: MediaType.applicationJson,
            }),
            body: utf8.encode(
              jsonEncode(
                fixtures.created(
                  jsonDecode(utf8.decode(request.body!))
                      as Map<String, Object?>,
                ),
              ),
            ),
          ),
        )
        ..when(HttpMethod.get, '/posts/9999').respond(404, json: {});
      await app().runAsync(
        (context) => context.getBean<BlogRunner>().run(_args),
      );
      expect(linesOf('blog'), [
        'user 1: Leanne Graham <Sincere@april.biz>, Gwenborough, works at '
            'Romaguera-Crona',
        '2 posts by Bret, first: "first post"',
        '3 comments on post 1, by ann@example.com, bob@example.com, ...',
        'created: 201, id 101, "Spring in Dart"',
        'post 9999: 404 Not Found (FeignNotFound)',
      ]);
    });

    test('offline: logs that the API is not reachable', () async {
      server
          .when(HttpMethod.get, '/users/1')
          .fail(HttpTransportException('connection refused'));
      await app().runAsync(
        (context) => context.getBean<BlogRunner>().run(_args),
      );
      expect(linesOf('blog'), [
        startsWith('JSONPlaceholder is not reachable: connection refused'),
      ]);
    });

    test('a server error is logged, not thrown', () async {
      server.when(HttpMethod.get, '/users/1').respond(500, body: 'oops');
      await app().runAsync(
        (context) => context.getBean<BlogRunner>().run(_args),
      );
      expect(linesOf('blog'), [
        startsWith('JSONPlaceholder answered with an error:'),
      ]);
    });
  });

  group('WikipediaRunner', () {
    test('prints 5 changes, then closes the stream', () async {
      var closed = false;
      server.when(HttpMethod.get, '/v2/stream/recentchange').respondStream(
        200,
        () {
          late final StreamController<List<int>> body;
          body = StreamController<List<int>>(
            onListen: () {
              for (var n = 1; n <= 6; n++) {
                body.add(
                  utf8.encode(
                    ServerSentEvent(
                      fixtures.recentChange(n),
                      id: '$n',
                    ).encode(jsonEncode),
                  ),
                );
              }
            },
            onCancel: () => closed = true,
          );
          return body.stream;
        },
        headers: {HttpHeaders.contentTypeHeader: MediaType.textEventStream},
      );
      await app().runAsync(
        (context) => context.getBean<WikipediaRunner>().run(_args),
      );
      expect(linesOf('wikipedia'), [
        'enwiki new: "Page 1" by Editor1',
        'enwiki edit: "Page 2" by Editor2',
        'enwiki new: "Page 3" by TidyBot (bot)',
        'enwiki edit: "Page 4" by Editor4',
        'enwiki new: "Page 5" by Editor5',
      ]);
      expect(closed, isTrue, reason: 'break in await for cancels the stream');
      expect(server.requests, hasLength(1));
    });

    test('an error status is logged, not thrown', () async {
      server
          .when(HttpMethod.get, '/v2/stream/recentchange')
          .respond(403, body: 'say who you are');
      await app().runAsync(
        (context) => context.getBean<WikipediaRunner>().run(_args),
      );
      expect(linesOf('wikipedia'), [
        startsWith('Wikimedia answered with an error:'),
      ]);
    });
  });

  group('EchoRunner', () {
    test('sends two messages and prints the echo', () async {
      // The mock server echoes what it gets.
      unawaited(
        sockets.nextConnection.then(
          (server) => server.onSent.listen(server.push),
        ),
      );
      await app().runAsync(
        (context) => context.getBean<EchoRunner>().run(_args),
      );
      expect(linesOf('echo'), [
        'echo: dart says "hello"',
        'echo: dart says "spring"',
      ]);
      expect(sockets.connections, hasLength(1));
    });

    test('an unreachable server is logged, not thrown', () async {
      sockets.failNextConnect();
      await app(['spring.websocket.client.config.echo.reconnect.enabled=false'])
          .runAsync((context) => context.getBean<EchoRunner>().run(_args));
      expect(linesOf('echo'), [
        startsWith('the echo server is not reachable:'),
      ]);
    });
  });
}
