import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:test/test.dart';

DateTime? next(String cron, DateTime after) =>
    CronExpression.parse(cron).next(after);

List<DateTime> times(String cron, DateTime after, int count) {
  final expression = CronExpression.parse(cron);
  final result = <DateTime>[];
  var current = after;
  for (var i = 0; i < count; i++) {
    current = expression.next(current)!;
    result.add(current);
  }
  return result;
}

DateTime utc(int y, [int m = 1, int d = 1, int h = 0, int mi = 0, int s = 0]) =>
    DateTime.utc(y, m, d, h, mi, s);

void main() {
  // Every value 0..59 of the second and minute fields, also those at or
  // above 32 that a 64-bit int bit set loses under dart2js (run with
  // `dart test -p node`).
  group('every field value (web-safe bit set)', () {
    test('a single second 0..59 fires at that second', () {
      for (var s = 0; s < 60; s++) {
        expect(
          next('$s * * * * *', utc(2026, 1, 1, 10)),
          s == 0 ? utc(2026, 1, 1, 10, 1) : utc(2026, 1, 1, 10, 0, s),
          reason: 'second $s',
        );
      }
    });

    test('a single minute 0..59 fires at that minute', () {
      for (var m = 0; m < 60; m++) {
        expect(
          next('0 $m * * * *', utc(2026, 1, 1, 10)),
          m == 0 ? utc(2026, 1, 1, 11) : utc(2026, 1, 1, 10, m),
          reason: 'minute $m',
        );
      }
    });

    test('lists and steps above 31 and day lists with specials', () {
      expect(times('45,50 33-34 * * * *', utc(2026, 1, 1, 10), 3), [
        utc(2026, 1, 1, 10, 33, 45),
        utc(2026, 1, 1, 10, 33, 50),
        utc(2026, 1, 1, 10, 34, 45),
      ]);
      expect(next('0 0 0 15,L * *', utc(2026, 1, 16)), utc(2026, 1, 31));
      expect(next('0 0 0 31,L * *', utc(2026)), utc(2026, 1, 31));
    });
  });

  group('fields', () {
    test('every second and strictly after', () {
      expect(
        next('* * * * * *', utc(2026, 1, 1, 10)),
        utc(2026, 1, 1, 10, 0, 1),
      );
      expect(
        next('* * * * * *', DateTime.utc(2026, 1, 1, 10, 0, 0, 500)),
        utc(2026, 1, 1, 10, 0, 1),
      );
    });

    test('values, lists, ranges and steps', () {
      expect(
        next('0 */15 * * * *', utc(2026, 1, 1, 10, 7)),
        utc(2026, 1, 1, 10, 15),
      );
      expect(
        next('0 */15 * * * *', utc(2026, 1, 1, 10, 45)),
        utc(2026, 1, 1, 11),
      );
      expect(
        next('30 5 * * * *', utc(2026, 1, 1, 10, 5, 30)),
        utc(2026, 1, 1, 11, 5, 30),
      );
      expect(times('0 0 9-17/4 * * *', utc(2026), 4), [
        utc(2026, 1, 1, 9),
        utc(2026, 1, 1, 13),
        utc(2026, 1, 1, 17),
        utc(2026, 1, 2, 9),
      ]);
      expect(times('0 0 0 1,15 * *', utc(2026), 3), [
        utc(2026, 1, 15),
        utc(2026, 2),
        utc(2026, 2, 15),
      ]);
      // `5/20`: from 5 to the end of the field, every 20.
      expect(times('5/20 * * * * *', utc(2026), 4), [
        utc(2026, 1, 1, 0, 0, 5),
        utc(2026, 1, 1, 0, 0, 25),
        utc(2026, 1, 1, 0, 0, 45),
        utc(2026, 1, 1, 0, 1, 5),
      ]);
    });

    test('month and day names, case-insensitive; 0 and 7 are Sunday', () {
      // 2026-01-01 is a Thursday.
      expect(
        next('0 0 9 * * MON-FRI', utc(2026, 1, 2, 10)),
        utc(2026, 1, 5, 9),
      );
      expect(
        next('0 0 9 * * mon-fri', utc(2026, 1, 2, 10)),
        utc(2026, 1, 5, 9),
      );
      expect(next('0 0 0 * * 0', utc(2026)), utc(2026, 1, 4));
      expect(next('0 0 0 * * 7', utc(2026)), utc(2026, 1, 4));
      expect(next('0 0 0 * * SUN', utc(2026)), utc(2026, 1, 4));
      expect(next('0 0 0 1 JUN *', utc(2026)), utc(2026, 6));
      expect(next('0 0 0 1 jun-aug/2 *', utc(2026, 6, 2)), utc(2026, 8));
    });

    test('day of month and day of week are both required (and)', () {
      // The 13th that is a Friday: 2026-02-13.
      expect(next('0 0 0 13 * FRI', utc(2026)), utc(2026, 2, 13));
      expect(next('0 0 0 ? * FRI', utc(2026)), utc(2026, 1, 2));
      expect(next('0 0 0 13 * ?', utc(2026)), utc(2026, 1, 13));
    });

    test('month ends and leap years', () {
      expect(next('0 0 0 31 * *', utc(2026, 1, 31, 1)), utc(2026, 3, 31));
      expect(next('0 0 0 29 2 *', utc(2026)), utc(2028, 2, 29));
      // A leap day on a Monday: 2044-02-29.
      expect(next('0 0 0 29 2 MON', utc(2026)), utc(2044, 2, 29));
      expect(next('0 0 0 30 2 *', utc(2026)), isNull);
      expect(
        next('59 59 23 31 12 *', utc(2026, 12, 31, 23, 59, 59)),
        utc(2027, 12, 31, 23, 59, 59),
      );
    });
  });

  group('specials', () {
    test('L, L-n and LW', () {
      expect(times('0 0 0 L * *', utc(2026), 3), [
        utc(2026, 1, 31),
        utc(2026, 2, 28),
        utc(2026, 3, 31),
      ]);
      expect(next('0 0 0 L 2 *', utc(2028)), utc(2028, 2, 29));
      expect(next('0 0 0 L-2 * *', utc(2026)), utc(2026, 1, 29));
      // 2026-01-31 is a Saturday, so the last weekday is Friday the 30th;
      // 2026-05-31 is a Sunday → Friday the 29th.
      expect(next('0 0 0 LW * *', utc(2026)), utc(2026, 1, 30));
      expect(next('0 0 0 LW 5 *', utc(2026)), utc(2026, 5, 29));
    });

    test('nW: the nearest weekday in the same month', () {
      // 2026-02-15 is a Sunday → Monday the 16th.
      expect(next('0 0 0 15W 2 *', utc(2026)), utc(2026, 2, 16));
      // 2026-08-01 is a Saturday → Monday the 3rd (not July 31st).
      expect(next('0 0 0 1W 8 *', utc(2026)), utc(2026, 8, 3));
      // 2026-05-31 is a Sunday → Friday the 29th (not June 1st).
      expect(next('0 0 0 31W 5 *', utc(2026)), utc(2026, 5, 29));
      // 2026-03-14 is a Saturday → Friday the 13th.
      expect(next('0 0 0 14W 3 *', utc(2026)), utc(2026, 3, 13));
      // A weekday stays.
      expect(next('0 0 0 10W 3 *', utc(2026)), utc(2026, 3, 10));
    });

    test('last weekday of the month: 5L, FRIL', () {
      expect(next('0 0 0 ? * 5L', utc(2026)), utc(2026, 1, 30));
      expect(next('0 0 0 ? * FRIL', utc(2026, 2)), utc(2026, 2, 27));
      expect(next('0 0 0 ? * SUNL', utc(2026)), utc(2026, 1, 25));
    });

    test('nth weekday of the month: MON#2, 1#3', () {
      expect(next('0 0 0 ? * MON#2', utc(2026)), utc(2026, 1, 12));
      expect(next('0 0 0 ? * 1#3', utc(2026)), utc(2026, 1, 19));
      expect(next('0 0 0 ? * MON#5', utc(2026)), utc(2026, 3, 30));
    });

    test('specials in lists, mixed with values', () {
      expect(times('0 0 0 ? * MON#1,MON#3', utc(2026), 4), [
        utc(2026, 1, 5),
        utc(2026, 1, 19),
        utc(2026, 2, 2),
        utc(2026, 2, 16),
      ]);
      expect(times('0 0 0 1,L * *', utc(2026), 4), [
        utc(2026, 1, 31),
        utc(2026, 2),
        utc(2026, 2, 28),
        utc(2026, 3),
      ]);
      expect(times('0 0 0 L,15 * *', utc(2026), 3), [
        utc(2026, 1, 15),
        utc(2026, 1, 31),
        utc(2026, 2, 15),
      ]);
      // 2026-02-01 and 2026-02-15 are Sundays.
      expect(times('0 0 0 1W,15W * *', utc(2025, 12, 31), 4), [
        utc(2026),
        utc(2026, 1, 15),
        utc(2026, 2, 2),
        utc(2026, 2, 16),
      ]);
      // Saturdays and the last Friday of the month.
      expect(times('0 0 0 ? * sat,FriL', utc(2026, 1, 24), 3), [
        utc(2026, 1, 30),
        utc(2026, 1, 31),
        utc(2026, 2, 7),
      ]);
    });

    test('macros', () {
      expect(next('@yearly', utc(2026, 3)), utc(2027));
      expect(next('@annually', utc(2026, 3)), utc(2027));
      expect(next('@monthly', utc(2026, 3, 5)), utc(2026, 4));
      expect(next('@weekly', utc(2026)), utc(2026, 1, 4));
      expect(next('@daily', utc(2026, 1, 1, 5)), utc(2026, 1, 2));
      expect(next('@midnight', utc(2026, 1, 1, 5)), utc(2026, 1, 2));
      expect(next('@hourly', utc(2026, 1, 1, 5, 1)), utc(2026, 1, 1, 6));
      expect(next('@DAILY', utc(2026, 1, 1, 5)), utc(2026, 1, 2));
    });
  });

  // Spring's CronField numbers the days like java.time: MON = 1 ... SUN = 7
  // (0 is Sunday too, and 7 at the start of a range means 0).
  group("Spring's day-of-week numbering", () {
    // 2026-01-01 is a Thursday.
    final cases = {
      'SAT-SUN': [utc(2026, 1, 3), utc(2026, 1, 4), utc(2026, 1, 10)],
      'sat-sun': [utc(2026, 1, 3), utc(2026, 1, 4), utc(2026, 1, 10)],
      'MON-SUN': [utc(2026, 1, 2), utc(2026, 1, 3), utc(2026, 1, 4)],
      'FRI-SUN': [utc(2026, 1, 2), utc(2026, 1, 3), utc(2026, 1, 4)],
      'Fri-Sun': [utc(2026, 1, 2), utc(2026, 1, 3), utc(2026, 1, 4)],
      'SUN-TUE': [utc(2026, 1, 4), utc(2026, 1, 5), utc(2026, 1, 6)],
      '7-1': [utc(2026, 1, 4), utc(2026, 1, 5), utc(2026, 1, 11)],
      'SUN-SAT': [utc(2026, 1, 2), utc(2026, 1, 3), utc(2026, 1, 4)],
      '6-7': [utc(2026, 1, 3), utc(2026, 1, 4), utc(2026, 1, 10)],
      '0-7': [utc(2026, 1, 2), utc(2026, 1, 3), utc(2026, 1, 4)],
      '1-5': [utc(2026, 1, 2), utc(2026, 1, 5), utc(2026, 1, 6)],
      'MON,SUN': [utc(2026, 1, 4), utc(2026, 1, 5), utc(2026, 1, 11)],
      // `*` is 1-7: MON, WED, FRI, SUN.
      '*/2': [utc(2026, 1, 2), utc(2026, 1, 4), utc(2026, 1, 5)],
      '1/2': [utc(2026, 1, 2), utc(2026, 1, 4), utc(2026, 1, 5)],
      // From 0 (Sunday): SUN, TUE, THU, SAT.
      '0/2': [utc(2026, 1, 3), utc(2026, 1, 4), utc(2026, 1, 6)],
      '?': [utc(2026, 1, 2), utc(2026, 1, 3), utc(2026, 1, 4)],
    };
    for (final MapEntry(key: days, value: expected) in cases.entries) {
      test(days, () {
        expect(times('0 0 0 * * $days', utc(2026), 3), expected);
      });
    }
  });

  // The examples of Spring's CronExpression javadoc and reference docs.
  group("Spring's documented examples", () {
    // 2026-01-01 is a Thursday; February 1st and March 1st are Sundays.
    final cases = <(String, String, DateTime, List<DateTime>)>[
      (
        '0 0 * * * *',
        'the top of every hour of every day',
        utc(2026, 1, 1, 10, 30),
        [utc(2026, 1, 1, 11), utc(2026, 1, 1, 12)],
      ),
      (
        '*/10 * * * * *',
        'every ten seconds',
        utc(2026, 1, 1, 10, 0, 5),
        [utc(2026, 1, 1, 10, 0, 10), utc(2026, 1, 1, 10, 0, 20)],
      ),
      (
        '0 0 8-10 * * *',
        "8, 9 and 10 o'clock of every day",
        utc(2026),
        [
          utc(2026, 1, 1, 8),
          utc(2026, 1, 1, 9),
          utc(2026, 1, 1, 10),
          utc(2026, 1, 2, 8),
        ],
      ),
      (
        '0 0 6,19 * * *',
        '6:00 AM and 7:00 PM every day',
        utc(2026),
        [utc(2026, 1, 1, 6), utc(2026, 1, 1, 19), utc(2026, 1, 2, 6)],
      ),
      (
        '0 0/30 8-10 * * *',
        '8:00, 8:30, 9:00, 9:30, 10:00 and 10:30 every day',
        utc(2026),
        [
          utc(2026, 1, 1, 8),
          utc(2026, 1, 1, 8, 30),
          utc(2026, 1, 1, 9),
          utc(2026, 1, 1, 9, 30),
          utc(2026, 1, 1, 10),
          utc(2026, 1, 1, 10, 30),
          utc(2026, 1, 2, 8),
        ],
      ),
      (
        '0 0 9-17 * * MON-FRI',
        'on the hour nine-to-five weekdays',
        utc(2026, 1, 2, 17),
        [utc(2026, 1, 5, 9), utc(2026, 1, 5, 10)],
      ),
      (
        '0 0 0 25 12 ?',
        'every Christmas Day at midnight',
        utc(2026),
        [utc(2026, 12, 25), utc(2027, 12, 25)],
      ),
      (
        '0 0 0 25 DEC ?',
        'every Christmas Day at midnight (month name)',
        utc(2026),
        [utc(2026, 12, 25), utc(2027, 12, 25)],
      ),
      (
        '0 0 0 L * *',
        'last day of the month at midnight',
        utc(2026),
        [utc(2026, 1, 31), utc(2026, 2, 28), utc(2026, 3, 31)],
      ),
      (
        '0 0 0 L-3 * *',
        'third-to-last day of the month at midnight',
        utc(2026),
        [utc(2026, 1, 28), utc(2026, 2, 25), utc(2026, 3, 28)],
      ),
      (
        '0 0 0 1W * *',
        'first weekday of the month at midnight',
        utc(2025, 12, 31),
        [utc(2026), utc(2026, 2, 2), utc(2026, 3, 2)],
      ),
      (
        '0 0 0 LW * *',
        'last weekday of the month at midnight',
        utc(2026),
        [utc(2026, 1, 30), utc(2026, 2, 27), utc(2026, 3, 31)],
      ),
      (
        '0 0 0 * * 5L',
        'last Friday of the month at midnight',
        utc(2026),
        [utc(2026, 1, 30), utc(2026, 2, 27), utc(2026, 3, 27)],
      ),
      (
        '0 0 0 * * THUL',
        'last Thursday of the month at midnight',
        utc(2026),
        [utc(2026, 1, 29), utc(2026, 2, 26), utc(2026, 3, 26)],
      ),
      (
        '0 0 0 ? * 5#2',
        'the second Friday in the month at midnight',
        utc(2026),
        [utc(2026, 1, 9), utc(2026, 2, 13), utc(2026, 3, 13)],
      ),
      (
        '0 0 0 ? * MON#1',
        'the first Monday in the month at midnight',
        utc(2026),
        [utc(2026, 1, 5), utc(2026, 2, 2), utc(2026, 3, 2)],
      ),
    ];
    for (final (cron, meaning, after, expected) in cases) {
      test('$cron: $meaning', () {
        expect(times(cron, after, expected.length), expected);
      });
    }
  });

  test('local time stays local', () {
    final result = next('0 30 2 * * *', DateTime(2026, 7, 1, 3))!;
    expect(result.isUtc, isFalse);
    expect(
      (result.month, result.day, result.hour, result.minute),
      (7, 2, 2, 30),
    );
  });

  group('errors name the field', () {
    final cases = {
      '0 0 * *': '6 fields',
      '0 0 * * * * *': '6 fields',
      '60 * * * * *': 'second field "60": 60 is out of range 0-59',
      '* 61 * * * *': 'minute field',
      '* * 24 * * *': 'hour field "24"',
      '* * * 0 * *': 'day-of-month field "0"',
      '* * * 32 * *': 'day-of-month field',
      '* * * * 13 *': 'month field "13"',
      '* * * * FOO *': "'FOO' is not a number or a name",
      '* * * * * 8': 'day-of-week field "8"',
      '* * * * * FRI-MON': 'goes backwards',
      '* * * * * SAT-FRI': 'goes backwards',
      '*/0 * * * * *': 'step',
      '* * * L-0 * *': 'the offset after L- must be 1-30',
      '* * * L3 * *': 'day-of-month field "L3"',
      '* * * W * *': 'day-of-month specials',
      '* * * 1,L,X * *': "'X' is not a number",
      '* * * * * MON#6': 'ordinal',
      '* * * * * L': 'day-of-week',
      '* * * * * 5L3': 'day-of-week specials',
      '* * * * * MON#1,XYZ': "'XYZ' is not a number or a name",
      '1,,2 * * * * *': 'empty list element',
      '1-2-3 * * * * *': 'not a range',
    };
    for (final MapEntry(key: cron, value: message) in cases.entries) {
      test(cron, () {
        expect(
          () => CronExpression.parse(cron),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
        expect(CronExpression.isValid(cron), isFalse);
      });
    }
  });

  test('equality and toString', () {
    expect(
      CronExpression.parse('0 0 * * * *'),
      CronExpression.parse('0 0 * * * *'),
    );
    expect('${CronExpression.parse('@daily')}', '@daily');
  });
}
