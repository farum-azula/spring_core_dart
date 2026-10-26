// End to end without the internet: the application starts like
// `dart run bin/main.dart` (generated springApplication, config file,
// auto-configuration, runners) with the real dart:io transports, against
// local stand-ins for JSONPlaceholder, Wikimedia EventStreams and the echo
// server (test/support/local_servers.dart). Runs in CI.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart';
import 'support/local_servers.dart';

void main() {
  late LocalServers servers;
  // The runners run (and log) while the application starts, before any
  // test: the records are collected from the start. springBootTest waits
  // for the runners, as @SpringBootTest does.
  final records = <SpringLogRecord>[];
  void Function()? stopListening;

  setUpAll(() async {
    servers = await LocalServers.start();
    stopListening = SpringLog.listen(records.add);
  });

  tearDownAll(() async {
    stopListening?.call();
    await servers.close();
  });

  springBootTest(
    springApplication,
    // The servers' addresses are known only once they run: set before the
    // context is refreshed, above every other property source.
    initializers: [
      ApplicationContextInitializer.of(
        (context) => context.environment.propertySources.addFirst(
          MapPropertySource('local servers', {
            'jsonplaceholder.url': servers.httpUrl,
            'wikimedia.url': servers.httpUrl,
            'echo.url': servers.echoUrl,
          }),
        ),
      ),
    ],
  );

  List<String> linesOf(String logger) => [
    for (final record in records)
      if (record.loggerName == logger) record.message,
  ];

  test('REST: the blog runner went through JSONPlaceholder', () async {
    expect(linesOf('blog'), [
      'user 1: Leanne Graham <Sincere@april.biz>, Gwenborough, works at '
          'Romaguera-Crona',
      '2 posts by Bret, first: "first post"',
      '3 comments on post 1, by ann@example.com, bob@example.com, ...',
      'created: 201, id 101, "Spring in Dart"',
      'post 9999: 404 Not Found (FeignNotFound)',
    ]);
    expect(
      [
        for (final r in servers.requests)
          if (r.contains('/posts') || r.contains('/users')) r,
      ],
      [
        'GET /users/1',
        'GET /posts?userId=1',
        'GET /posts/1/comments',
        'POST /posts',
        'GET /posts/9999',
      ],
    );
    expect(servers.clientHeaders, everyElement('spring-boot-feign-example'));
  });

  test(
    'server-sent events: 5 changes across a reconnect, then closed',
    () async {
      expect(linesOf('wikipedia'), [
        'enwiki new: "Page 1" by Editor1',
        'enwiki edit: "Page 2" by Editor2',
        'enwiki new: "Page 3" by TidyBot (bot)',
        'enwiki edit: "Page 4" by Editor4',
        'enwiki new: "Page 5" by Editor5',
      ]);
      const userAgent =
          'spring-boot-feign-example/0.1 '
          '(https://github.com/farum-azula/spring_core_dart)';
      // The first connection ended after event 3; the client came back with
      // Last-Event-ID and got the rest.
      expect(servers.streamConnections, [
        (userAgent: userAgent, lastEventId: null),
        (userAgent: userAgent, lastEventId: '3'),
      ]);
      // `break` after 5 events closed the connection the server kept open.
      await servers.streamLeft.future.timeout(const Duration(seconds: 5));
    },
  );

  test('the runners ran one after another, in @Order order', () {
    // Each runner's lines form one block: no interleaving.
    final blocks = <String>[];
    for (final record in records) {
      final name = record.loggerName;
      if (const {'blog', 'wikipedia', 'echo'}.contains(name) &&
          (blocks.isEmpty || blocks.last != name)) {
        blocks.add(name);
      }
    }
    expect(blocks, ['blog', 'wikipedia', 'echo']);
  });

  test('WebSocket: two messages echoed back as ChatMessage', () async {
    expect(linesOf('echo'), [
      'echo: dart says "hello"',
      'echo: dart says "spring"',
    ]);
    expect(
      [for (final m in servers.echoed) jsonDecode(m)],
      [
        {'from': 'dart', 'text': 'hello'},
        {'from': 'dart', 'text': 'spring'},
      ],
    );
  });
}
