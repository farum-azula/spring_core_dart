// Chapter 8, "Cache & scheduling": catalog reads are @Cacheable; a
// @Scheduled task refreshes the catalog while the app is in the
// foreground and stops while it is in the background.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/catalog/catalog_service.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show HttpMethod;
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart'
    show CronExpression, CronTrigger, TimerTaskScheduler;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

int catalogRequests(FakeServer server) =>
    server.http.requests.where((r) => r.url.path == '/api/books').length;

void main() {
  group('@Cacheable', () {
    final server = FakeServer();
    final app = springBootTest(springApplication, overrides: server.overrides);

    setUp(() {
      app.markDirty(); // empty caches
      server.http.reset();
      server.answerCatalog();
    });

    test('a page is asked for once per query and page', () async {
      final catalog = app.getBean<CatalogService>();

      await catalog.page('', 0);
      await catalog.page('', 0);
      await catalog.page('dune', 0);

      expect(catalogRequests(server), 2);
    });

    test('a missing book is not cached (unless: #result == null)', () async {
      server.http
        ..when(HttpMethod.get, '/api/books/42').respond(404)
        ..when(
          HttpMethod.get,
          '/api/books/42',
        ).respond(200, json: {'isbn': '42', 'title': 'The Hitchhiker'});
      final catalog = app.getBean<CatalogService>();

      expect(await catalog.find('42'), isNull);
      expect((await catalog.find('42'))?.title, 'The Hitchhiker');
      expect((await catalog.find('42'))?.title, 'The Hitchhiker');
      expect(
        server.http.requests.where((r) => r.url.path == '/api/books/42'),
        hasLength(2),
      );
    });

    test('refresh() empties the catalog caches (@CacheEvict)', () async {
      final catalog = app.getBean<CatalogService>();
      await catalog.page('', 0);
      await catalog.find('9780441013593');

      catalog.refresh();
      await catalog.page('', 0);
      await catalog.find('9780441013593');

      expect(catalogRequests(server), 2);
      expect(
        server.http.requests.where(
          (r) => r.url.path == '/api/books/9780441013593',
        ),
        hasLength(2),
      );
    });
  });

  testWidgets(
    '@Scheduled: refreshed in the foreground, not in the background',
    (tester) async {
      final server = FakeServer();
      await startApp(tester, server, args: ['--catalog.refresh-interval=1m']);
      expect(catalogRequests(server), 1); // the catalog on screen

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(catalogRequests(server), 2); // refreshed: caches emptied, reloaded

      // In the background the context is paused: no refresh.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 5));
      expect(catalogRequests(server), 2);

      // Back in the foreground: refreshed again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(catalogRequests(server), 3);
      await stopApp(tester);
    },
  );

  // The scheduler reads the current time of package:clock, which a widget
  // test fakes along with its timers: each pumped minute is a minute of
  // the schedule, also for runs that take time.
  testWidgets('tester.pump keeps the pace of fixed rate, fixed delay and '
      'cron', (tester) async {
    final scheduler = TimerTaskScheduler();
    addTearDown(scheduler.shutdown);
    final start = scheduler.now();
    final runs = <String, List<Duration>>{};
    void Function() instant(String name) =>
        () => (runs[name] ??= []).add(scheduler.now().difference(start));
    Future<void> Function() slow(String name) => () {
      instant(name)();
      return Future<void>.delayed(const Duration(seconds: 30));
    };
    const minute = Duration(minutes: 1);
    final cron = CronTrigger(CronExpression.parse('0 * * * * *'));
    scheduler
      ..scheduleAtFixedRate(instant('rate'), minute)
      ..scheduleAtFixedRate(slow('rate, 30 s runs'), minute)
      ..scheduleWithFixedDelay(instant('delay'), minute)
      ..scheduleWithFixedDelay(slow('delay, 30 s runs'), minute)
      ..schedule(instant('cron'), cron)
      ..schedule(slow('cron, 30 s runs'), cron);
    for (var i = 0; i < 10; i++) {
      await tester.pump(minute);
    }
    List<Duration> every(Duration step) => [
      for (var t = Duration.zero; t <= minute * 10; t += step) t,
    ];
    expect(runs['rate'], every(minute));
    expect(runs['rate, 30 s runs'], every(minute));
    expect(runs['delay'], every(minute));
    expect(runs['delay, 30 s runs'], every(const Duration(seconds: 90)));
    // At each whole minute, ten of them (waits are whole milliseconds,
    // rounded up: under a millisecond late, without adding up).
    final firstCron = start
        .add(minute)
        .copyWith(second: 0, millisecond: 0, microsecond: 0);
    for (final name in ['cron', 'cron, 30 s runs']) {
      expect(runs[name], hasLength(10), reason: name);
      for (final (i, run) in runs[name]!.indexed) {
        final late = start.add(run).difference(firstCron.add(minute * i));
        expect(late.inMicroseconds, inInclusiveRange(0, 999), reason: name);
      }
    }
    scheduler.shutdown();
    await tester.pump(minute); // the runs going on end
  });
}
