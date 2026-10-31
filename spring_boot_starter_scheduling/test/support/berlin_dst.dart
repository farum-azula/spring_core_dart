// Cron expressions across daylight saving changes, in Europe/Berlin local
// time. Not a `_test.dart` file: `test/cron_dst_test.dart` runs it with
// TZ=Europe/Berlin; to run it alone:
//   TZ=Europe/Berlin dart run test/support/berlin_dst.dart
//   TZ=Europe/Berlin dart test -p node test/support/berlin_dst.dart
//
// The expected times are Spring 7's `CronExpression.next` with a
// `ZonedDateTime` in Europe/Berlin (CEST = UTC+2, CET = UTC+1; clocks go
// forward on 2026-03-29 at 02:00, back on 2026-10-25 at 03:00).
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:test/test.dart';

import '../fake_clock.dart';

void main() {
  setUpAll(() {
    final berlin =
        DateTime(2026, 7, 2).timeZoneOffset == const Duration(hours: 2) &&
        DateTime(2026, 1, 2).timeZoneOffset == const Duration(hours: 1);
    if (!berlin) {
      fail('Run with TZ=Europe/Berlin');
    }
  });

  /// The next [count] times after [from] (UTC), in UTC.
  List<DateTime> next(String cron, DateTime from, int count) {
    final expression = CronExpression.parse(cron);
    var time = from.toLocal();
    return [
      for (var i = 0; i < count; i++) (time = expression.next(time)!).toUtc(),
    ];
  }

  DateTime utc(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) => DateTime.utc(year, month, day, hour, minute, second);

  group('clocks going back: the repeated hour matches twice', () {
    test('a daily time inside it', () {
      // From 2026-10-24T12:00+02:00.
      expect(next('0 30 2 * * *', utc(2026, 10, 24, 10), 3), [
        utc(2026, 10, 25, 0, 30), // 02:30+02:00
        utc(2026, 10, 25, 1, 30), // 02:30+01:00
        utc(2026, 10, 26, 1, 30),
      ]);
    });

    test('every hour', () {
      expect(next('0 0 * * * *', utc(2026, 10, 24, 22, 30), 5), [
        utc(2026, 10, 24, 23), // 01:00+02:00
        utc(2026, 10, 25), // 02:00+02:00
        utc(2026, 10, 25, 1), // 02:00+01:00
        utc(2026, 10, 25, 2), // 03:00+01:00
        utc(2026, 10, 25, 3),
      ]);
    });

    test('every half hour inside it', () {
      expect(next('0 */30 2 * * *', utc(2026, 10, 24, 23), 5), [
        utc(2026, 10, 25),
        utc(2026, 10, 25, 0, 30),
        utc(2026, 10, 25, 1),
        utc(2026, 10, 25, 1, 30),
        utc(2026, 10, 26, 1),
      ]);
    });

    test('from inside the first pass', () {
      final firstPass = utc(2026, 10, 25, 0, 30); // 02:30+02:00
      expect(next('0 15 2 * * *', firstPass, 2), [
        utc(2026, 10, 25, 1, 15), // 02:15+01:00, before 02:30 on the wall
        utc(2026, 10, 26, 1, 15),
      ]);
      expect(next('0 45 2 * * *', firstPass, 3), [
        utc(2026, 10, 25, 0, 45),
        utc(2026, 10, 25, 1, 45),
        utc(2026, 10, 26, 1, 45),
      ]);
      expect(next('0 0 3 * * *', firstPass, 1), [utc(2026, 10, 25, 2)]);
      expect(next('0 0 0 1 4 *', firstPass, 1), [utc(2027, 3, 31, 22)]);
      expect(next('59 59 2 * * *', utc(2026, 10, 25, 0, 59, 59), 2), [
        utc(2026, 10, 25, 1, 59, 59),
        utc(2026, 10, 26, 1, 59, 59),
      ]);
      expect(next('* * * * * *', utc(2026, 10, 25, 0, 59, 58), 3), [
        utc(2026, 10, 25, 0, 59, 59),
        utc(2026, 10, 25, 1),
        utc(2026, 10, 25, 1, 0, 1),
      ]);
    });

    test('from inside the second pass', () {
      expect(next('0 15 2 * * *', utc(2026, 10, 25, 1, 30), 1), [
        utc(2026, 10, 26, 1, 15),
      ]);
    });
  });

  group('clocks going forward: the skipped hour does not exist', () {
    test('a daily time inside it does not run that day', () {
      expect(next('0 30 2 * * *', utc(2026, 3, 28, 11), 2), [
        utc(2026, 3, 30, 0, 30), // 02:30+02:00
        utc(2026, 3, 31, 0, 30),
      ]);
      expect(next('0 0 2 * * *', utc(2026, 3, 28, 11), 1), [
        utc(2026, 3, 30),
      ]);
    });

    test('every second and every half hour', () {
      expect(next('* * * * * *', utc(2026, 3, 29, 0, 59, 58), 3), [
        utc(2026, 3, 29, 0, 59, 59), // 01:59:59+01:00
        utc(2026, 3, 29, 1), // 03:00+02:00
        utc(2026, 3, 29, 1, 0, 1),
      ]);
      expect(next('0 */30 * * * *', utc(2026, 3, 29), 3), [
        utc(2026, 3, 29, 0, 30),
        utc(2026, 3, 29, 1),
        utc(2026, 3, 29, 1, 30),
      ]);
    });
  });

  test('a daily cron task runs twice on the day clocks go back', () {
    final clock = FakeClock(utc(2026, 10, 24, 10));
    final scheduler = TimerTaskScheduler(
      now: clock.now,
      createTimer: clock.timer,
    );
    addTearDown(scheduler.shutdown);
    final runs = <DateTime>[];
    scheduler.schedule(
      () => runs.add(clock.now()),
      CronTrigger(CronExpression.parse('0 30 2 * * *')),
    );
    clock.elapse(const Duration(days: 2));
    expect(runs, [
      utc(2026, 10, 25, 0, 30),
      utc(2026, 10, 25, 1, 30),
      utc(2026, 10, 26, 1, 30),
    ]);
  });
}
