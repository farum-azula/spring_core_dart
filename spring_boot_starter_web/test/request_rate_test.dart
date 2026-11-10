// The debug feature `qps`: the counts of an isolate, the rate between two
// looks, and a real server whose isolates are added up.
import 'dart:io' as io;
import 'dart:isolate';

import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'app/app.dart';

SpringApplication _application() => SpringApplication(
  [webTestBeans],
  autoConfigurations: [
    springBootAutoConfiguration,
    springBootStarterLoggingAutoConfiguration,
    springBootStarterWebAutoConfiguration,
    springBootStarterWebDebugQpsAutoConfiguration,
  ],
);

Future<int> _status(int port, String path) async {
  final client = io.HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.persistentConnection = false;
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

RequestCounts _counts(int requests, {int errors = 0, Map<int, int>? at}) {
  final buckets = List<int>.filled(requestLatencyBounds.length + 1, 0);
  (at ?? {0: requests}).forEach((bucket, count) => buckets[bucket] = count);
  return RequestCounts(requests: requests, errors: errors, buckets: buckets);
}

void main() {
  test('the latency buckets grow by half, from 100 µs to a minute', () {
    expect(requestLatencyBounds.first, 100);
    expect(requestLatencyBounds[1], 150);
    expect(requestLatencyBounds.last, greaterThan(40e6));
    expect(requestLatencyBounds.last, lessThan(60e6));
  });

  group('RequestRate', () {
    test('between two looks: the difference, per second', () {
      final rate = RequestRate.between(
        _counts(100, errors: 1),
        _counts(350, errors: 3),
        5,
      );
      expect(rate.requests, 250);
      expect(rate.errors, 2);
      expect(rate.qps, 50);
    });

    test('an isolate that started again counts from zero', () {
      final rate = RequestRate.between(_counts(900), _counts(40), 2);
      expect(rate.requests, 40);
      expect(rate.qps, 20);
    });

    test('percentiles are the bound of the bucket the request fell in', () {
      // 90 requests under 100 µs, 9 under ~1.1 ms, 1 under ~58 ms.
      final slow = requestLatencyBounds.indexWhere((b) => b > 50000);
      final rate = RequestRate.between(
        null,
        _counts(100, at: {0: 90, 6: 9, slow: 1}),
        1,
      );
      expect(rate.percentile(0.5), const Duration(microseconds: 100));
      expect(
        rate.percentile(0.95),
        Duration(microseconds: requestLatencyBounds[6]),
      );
      expect(
        rate.percentile(1),
        Duration(microseconds: requestLatencyBounds[slow]),
      );
      expect(RequestRate.between(null, _counts(0), 1).percentile(0.5), isNull);
    });

    test('the isolates added up', () {
      final a = RequestRate.between(null, _counts(100, at: {0: 100}), 2);
      final b = RequestRate.between(null, _counts(300, at: {3: 300}), 2);
      final total = RequestRate.sum([a, b], 2);
      expect(total.requests, 400);
      expect(total.qps, 200);
      expect(
        total.percentile(0.5),
        Duration(microseconds: requestLatencyBounds[3]),
      );
      expect(
        RequestRates.describe(RequestRateWindow(total, {'main': a, 'x': b})),
        '200.0 requests/s (p50 0.3 ms, p99 0.3 ms), 0 in flight, 0 errors; '
        'main 50.0, x 150.0',
      );
      expect(
        RequestRates.describe(RequestRateWindow(a, {'main': a})),
        '50.0 requests/s (p50 0.1 ms, p99 0.1 ms), 0 in flight, 0 errors',
      );
    });

    test('counts cross isolates as JSON', () {
      final counts = _counts(7, errors: 2, at: {1: 7});
      final back = RequestCounts.fromJson(counts.toJson());
      expect(back.toJson(), counts.toJson());
      expect(RequestCounts.fromJson('nonsense').requests, 0);
    });
  });

  test('a server counts its requests, 5xx as errors', () async {
    final context = _application().run([
      '--server.port=0',
      '--server.address=127.0.0.1',
      '--spring.main.banner-mode=off',
      '--logging.level.root=off',
      '--spring.web.debug.qps.log-interval=1h',
    ]);
    addTearDown(context.closeAsync);
    final server = await context.getBean<WebServerStartStopLifecycle>().started;
    final port = server!.port;
    final rates = context.getBean<RequestRates>();
    expect(rates.last, isNull);
    for (var i = 0; i < 5; i++) {
      expect(await _status(port, '/isolate/name'), 200);
    }
    expect(await _status(port, '/no-such-page'), 404);
    expect(await _status(port, '/isolate/slow?ms=nonsense'), 400);
    final window = await rates.look();
    expect(window.total.requests, 7);
    expect(window.total.errors, 0, reason: '4xx are answers, not errors');
    expect(window.isolates.keys, ['main']);
    expect(window.total.percentile(0.99), isNotNull);
    expect(rates.last, same(window));
    expect(window.toJson()['isolates'], isA<Map<String, Object?>>());
    // The next window starts empty.
    expect((await rates.look()).total.requests, 0);
  });

  test('the isolates of a pool are added up', () async {
    final context = _application().run([
      '--server.port=0',
      '--server.address=127.0.0.1',
      '--spring.main.banner-mode=off',
      '--logging.level.root=off',
      '--server.isolates.count=3',
      '--spring.web.debug.qps.log-interval=1h',
    ], hotReload: _application);
    addTearDown(context.closeAsync);
    final server = await context.getBean<WebServerStartStopLifecycle>().started;
    await context.getBean<ServerIsolatePool>().awaitStartup();
    final port = server!.port;
    await Isolate.run(() async {
      for (var i = 0; i < 60; i++) {
        await _status(port, '/isolate/name');
      }
    });
    final window = await context.getBean<RequestRates>().look();
    expect(window.total.requests, 60);
    expect(window.isolates.keys, ['main', 'isolate-1', 'isolate-2']);
    // Whichever isolates took them: a connection goes to the first that
    // takes it.
    expect(
      window.isolates.values.fold(0, (sum, rate) => sum + rate.requests),
      60,
    );
    // Only the first isolate works the rates out.
    expect(context.getBeansOfType<RequestRates>(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
