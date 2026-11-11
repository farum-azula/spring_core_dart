// The rate limiter on a server with a pool of isolates: real isolates,
// one set of buckets in the first.
import 'dart:io' as io;
import 'dart:isolate';

import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'app/app.dart';

// What a pool starts in each isolate: nothing from around it.
SpringApplication _application() => SpringApplication(
  [webTestBeans],
  autoConfigurations: [
    springBootAutoConfiguration,
    springBootStarterLoggingAutoConfiguration,
    springBootStarterWebAutoConfiguration,
    springBootStarterWebRateLimitAutoConfiguration,
  ],
);

Future<ConfigurableApplicationContext> _start(List<String> properties) async {
  final context = _application().run([
    '--server.port=0',
    '--server.address=127.0.0.1',
    '--spring.main.banner-mode=off',
    '--logging.level.root=warn',
    for (final property in properties) '--$property',
  ], hotReload: _application);
  addTearDown(() async {
    if (context.isActive) {
      await context.closeAsync();
    }
  });
  await context.getBean<WebServerStartStopLifecycle>().started;
  if (context.containsBean('serverIsolatePool')) {
    await context.getBean<ServerIsolatePool>().awaitStartup();
  }
  return context;
}

// One request on a connection of its own, so that any isolate may take
// it: the status and the isolate that answered.
Future<(int, String)> _fetch(int port, String path) async {
  final client = io.HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.persistentConnection = false;
    final response = await request.close();
    final body = await response
        .transform(const io.SystemEncoding().decoder)
        .join();
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

// [count] requests, [atOnce] at a time, sent from an isolate of their own
// (sent from this one, it would be busy sending while the others are
// free, and they would take every connection).
Future<List<(int, String)>> _flood(
  int port,
  String path, {
  int count = 100,
  int atOnce = 100,
}) => Isolate.run(() async {
  final answers = <(int, String)>[];
  for (var sent = 0; sent < count; sent += atOnce) {
    answers.addAll(
      await Future.wait([
        for (var i = sent; i < sent + atOnce && i < count; i++)
          _fetch(port, path),
      ]),
    );
  }
  return answers;
});

void main() {
  test('three isolates share one limit: 100 requests at once, 10 '
      'pass', () async {
    final context = await _start([
      'server.isolates.count=3',
      'spring.web.rate-limit.rules[0].path=/isolate/name',
      'spring.web.rate-limit.rules[0].key=ip',
      'spring.web.rate-limit.rules[0].limit=10/1h',
    ]);
    expect(context.getBean<ServerIsolatePool>().count, 3);
    expect(
      context.getBean<RateLimitStore>(),
      isA<PrimaryIsolateRateLimitStore>(),
    );
    final port = context.getBean<WebServerStartStopLifecycle>().webServer!.port;

    final answers = await _flood(port, '/isolate/name');
    expect(answers.where((a) => a.$1 == 200), hasLength(10));
    expect(answers.where((a) => a.$1 == 429), hasLength(90));

    // Every isolate refuses from then on: asked until each of the three
    // has answered a request that is not counted, all of the counted
    // ones are refused.
    final later = await _flood(port, '/isolate/name', count: 60, atOnce: 6);
    expect(later.map((a) => a.$1).toSet(), {429});
    final seen = <String>{};
    for (var round = 0; round < 40 && seen.length < 3; round++) {
      seen.addAll(
        (await _flood(
          port,
          '/isolate/slow?ms=1',
          count: 12,
          atOnce: 6,
        )).map((a) => a.$2),
      );
    }
    expect(seen, {'main', 'isolate-1', 'isolate-2'});
    // One bucket for the whole server, kept in the first isolate.
    expect(
      context.getBean<PrimaryIsolateRateLimitHandler>().buckets.length,
      1,
    );
  });

  test('with the store in memory each isolate counts for itself, and the '
      'pool says so', () async {
    final warnings = <String>[];
    final stop = SpringLog.listen((record) {
      if (record.level.index >= SpringLogLevel.warning.index) {
        warnings.add(record.message);
      }
    });
    addTearDown(stop);
    final context = await _start([
      'server.isolates.count=2',
      'spring.web.rate-limit.store=memory',
      'spring.web.rate-limit.rules[0].path=/isolate/name',
      'spring.web.rate-limit.rules[0].key=ip',
      'spring.web.rate-limit.rules[0].limit=5/1h',
    ]);
    expect(context.getBean<RateLimitStore>(), isA<InMemoryRateLimitStore>());
    expect(warnings.join('\n'), contains("the rate limiter's buckets"));
  });
}
