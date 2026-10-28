@TestOn('vm')
library;

import 'dart:io' show pid;
import 'dart:isolate';

import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:test/test.dart';

// The offset as `%d{XXX}` writes it for a local time.
String offsetOf(DateTime time) {
  final offset = time.timeZoneOffset;
  if (offset == Duration.zero) {
    return 'Z';
  }
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  return '$sign${'${minutes ~/ 60}'.padLeft(2, '0')}:'
      '${'${minutes % 60}'.padLeft(2, '0')}';
}

void main() {
  final time = DateTime(2026, 3, 7, 9, 5, 2, 42);
  final failed = SpringLogRecord(
    SpringLogLevel.warning,
    'neon.checkout',
    'slow payment',
    time: time,
    sequence: 12,
    error: StateError('timeout'),
    stackTrace: StackTrace.fromString('#0 pay (checkout.dart:1)\n'),
  );
  final plain = SpringLogRecord(
    SpringLogLevel.info,
    'neon.checkout',
    'paid',
    time: time,
    sequence: 3,
    fields: const {'order': 42, 'user': 'ada'},
  );
  SpringLogRecord at(SpringLogLevel level) =>
      SpringLogRecord(level, 'a', 'm', time: time);
  final isolate = Isolate.current.debugName ?? 'main';

  test('conversion words', () {
    const cases = {
      '%d{yyyy-MM-dd HH:mm:ss.SSS} %p %c: %m [%seq] 100%%':
          '2026-03-07 09:05:02.042 INFO neon.checkout: paid [3] 100%',
      '%date{HH:mm} %level %logger %msg%n': '09:05 INFO neon.checkout paid\n',
      '%le|%lo|%message': 'INFO|neon.checkout|paid',
      '%X{order}/%X{none}/%X{none:-n/a}': '42//n/a',
      '%mdc{user}': 'ada',
      '%m%X': 'paid {order=42, user=ada}',
      r'\%m \(%m\) (%m) \\': r'%m (paid) (paid) \',
      '%t|%thread': '',
      '%r': '',
    };
    for (final MapEntry(key: pattern, value: expected) in cases.entries) {
      final text = LogPattern(pattern).format(plain);
      switch (pattern) {
        case '%t|%thread':
          expect(text, '$isolate|$isolate', reason: pattern);
        case '%r':
          expect(int.tryParse(text), isNotNull, reason: pattern);
        default:
          expect(text, expected, reason: pattern);
      }
    }
  });

  test('%r is never negative, also for records older than the pattern', () {
    final pattern = LogPattern('%r');
    final early = SpringLogRecord(
      SpringLogLevel.info,
      'a',
      'buffered before the logging system started',
      time: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    expect(int.parse(pattern.format(early)), greaterThanOrEqualTo(0));
    final later = SpringLogRecord(SpringLogLevel.info, 'a', 'now');
    expect(int.parse(pattern.format(later)), greaterThanOrEqualTo(0));
    expect(int.parse(pattern.format(later)), greaterThanOrEqualTo(299000));
  });

  test('format modifiers, like Logback', () {
    const cases = {
      '[%5p]': '[ INFO]',
      '[%-5p]': '[INFO ]',
      '[%3p]': '[INFO]',
      '[%.3p]': '[NFO]', // truncated from the beginning
      '[%.-3p]': '[INF]', // from the end
      '[%-10.10logger]': '[n.checkout]',
      '[%20.30logger]': '[       neon.checkout]',
      '[%-6(%p)]': '[INFO  ]',
      '[%10(%p %m)]': '[ INFO paid]',
      '[%-8.8(%p %m %m)]': '[aid paid]',
    };
    for (final MapEntry(key: pattern, value: expected) in cases.entries) {
      expect(LogPattern(pattern).format(plain), expected, reason: pattern);
    }
  });

  test('%logger{n} abbreviates like Logback', () {
    // Logback's documentation table.
    const name = 'mainPackage.sub.sample.Bar';
    const cases = {
      0: 'Bar',
      5: 'm.s.s.Bar',
      10: 'm.s.s.Bar',
      15: 'm.s.sample.Bar',
      16: 'm.sub.sample.Bar',
      26: 'mainPackage.sub.sample.Bar',
    };
    for (final MapEntry(key: length, value: expected) in cases.entries) {
      expect(LogPattern.abbreviate(name, length), expected, reason: '$length');
      final record = SpringLogRecord(SpringLogLevel.info, name, 'm');
      expect(
        LogPattern('%logger{$length}').format(record),
        expected,
        reason: '%logger{$length}',
      );
    }
    expect(
      LogPattern.abbreviate('org.springframework.boot.SpringApplication', 39),
      'o.s.boot.SpringApplication',
    );
    expect(LogPattern.abbreviate('Bar', 1), 'Bar');
    expect(LogPattern.abbreviate('a.b.Bar', 0), 'Bar');
  });

  test('%d: Java date patterns, ISO8601 by default', () {
    final micros = DateTime(2026, 3, 7, 21, 5, 2, 42, 7);
    final utc = DateTime.utc(2026, 3, 7, 9, 5);
    final cases = <(String, DateTime), String>{
      ('%d', time): '2026-03-07 09:05:02,042',
      ('%d{ISO8601}', time): '2026-03-07 09:05:02,042',
      ('%d{STRICT}', time): '2026-03-07T09:05:02,042',
      ("%d{yyyy-MM-dd'T'HH:mm:ss.SSSXXX}", time):
          '2026-03-07T09:05:02.042${offsetOf(time)}',
      ('%d{yy/M/d H:m:s}', time): '26/3/7 9:5:2',
      ('%d{"EEE, MMM d"}', time): 'Sat, Mar 7',
      ("%d{EEEE MMMM ''yy hh a D}", micros): "Saturday March '26 09 PM 66",
      ('%d{HH:mm:ss.SSSSSS}', micros): '21:05:02.042007',
      ('%d{HH:mm:ss.S}', micros): '21:05:02.0',
      ('%d{HH:mm X|XX|XXX|x|Z|ZZZZZ}', utc): '09:05 Z|Z|Z|+00|+0000|Z',
      ('%d{HH:mm XXX, UTC}', utc): '09:05 Z',
    };
    for (final MapEntry(key: (pattern, at), value: expected) in cases.entries) {
      final record = SpringLogRecord(SpringLogLevel.info, 'a', 'm', time: at);
      expect(LogPattern(pattern).format(record), expected, reason: pattern);
    }
    // A local time keeps its offset; UTC converts.
    final local = SpringLogRecord(SpringLogLevel.info, 'a', 'm', time: time);
    expect(
      LogPattern('%d{HH:mm, UTC}').format(local),
      LogPattern('%d{HH:mm}').format(
        SpringLogRecord(SpringLogLevel.info, 'a', 'm', time: time.toUtc()),
      ),
    );
  });

  test('%clr colours with ANSI output on, and is plain text off', () {
    expect(
      LogPattern('%clr(%p){cyan}', ansi: true).format(plain),
      '\x1B[36mINFO\x1B[0;39m',
    );
    expect(
      LogPattern('%clr(%5p) %clr(:){faint}', ansi: true).format(plain),
      '\x1B[32m INFO\x1B[0;39m \x1B[2m:\x1B[0;39m',
    );
    expect(
      LogPattern('%clr(x){bright_red}', ansi: true).format(plain),
      '\x1B[91mx\x1B[0;39m',
    );
    // Without a colour: by level, like Spring Boot's ColorConverter.
    final byLevel = LogPattern('%clr(%p)', ansi: true);
    expect(byLevel.format(at(SpringLogLevel.error)), '\x1B[31mERROR\x1B[0;39m');
    expect(
      byLevel.format(at(SpringLogLevel.warning)),
      '\x1B[33mWARN\x1B[0;39m',
    );
    expect(byLevel.format(at(SpringLogLevel.debug)), '\x1B[32mDEBUG\x1B[0;39m');
    expect(LogPattern('%clr(%p){cyan} %clr(x)').format(plain), 'INFO x');
  });

  test('%esb: [value] of its content or a variable, nothing when empty', () {
    final named = {'APPLICATION_NAME': 'shop'};
    expect(
      LogPattern('%esb(){APPLICATION_NAME}x', variables: named).format(plain),
      '[shop] x',
    );
    expect(
      LogPattern('%esb{APPLICATION_NAME}x', variables: named).format(plain),
      '[shop] x',
    );
    expect(LogPattern('%esb(){APPLICATION_NAME}x').format(plain), 'x');
    expect(LogPattern('%esb(%p)x').format(plain), '[INFO] x');
  });

  test('errors: %ex, %wEx, %nopex, and appended when not converted', () {
    final deep = SpringLogRecord(
      SpringLogLevel.error,
      'a',
      'm',
      error: 'boom',
      stackTrace: StackTrace.fromString('#0 a\n#1 b\n#2 c\n'),
    );
    final cases = <(String, SpringLogRecord), String>{
      ('%m%n%ex', failed):
          'slow payment\nBad state: timeout\n#0 pay (checkout.dart:1)\n',
      ('%m%n%exception', failed):
          'slow payment\nBad state: timeout\n#0 pay (checkout.dart:1)\n',
      // Spring Boot's %wEx: the error between line breaks.
      ('%m%n%wEx', failed):
          'slow payment\n\nBad state: timeout\n#0 pay (checkout.dart:1)\n\n',
      ('%m%n%wEx', plain): 'paid\n',
      ('%m%ex', plain): 'paid',
      ('%m%n%ex{2}', deep): 'm\nboom\n#0 a\n#1 b\n',
      ('%m%n%throwable{short}', deep): 'm\nboom\n#0 a\n',
      ('%m%n%xEx{full}', deep): 'm\nboom\n#0 a\n#1 b\n#2 c\n',
      ('%m%nopex', failed): 'slow payment',
      // Like Logback's EnsureExceptionHandling: still printed.
      ('%m', failed):
          'slow payment\nBad state: timeout\n#0 pay (checkout.dart:1)\n',
      ('%m%n', failed):
          'slow payment\nBad state: timeout\n#0 pay (checkout.dart:1)\n',
    };
    for (final MapEntry(key: (pattern, record), value: expected)
        in cases.entries) {
      expect(LogPattern(pattern).format(record), expected, reason: pattern);
    }
    // Appenders write lines: formatLine drops the final line break.
    expect(
      LogPattern('%m%n%wEx').formatLine(failed),
      'slow payment\n\nBad state: timeout\n#0 pay (checkout.dart:1)\n',
    );
    expect(LogPattern('%m%n%wEx').formatLine(plain), 'paid');
  });

  test(r'${variables}: given, PID, looked up, defaults', () {
    final cases = <String, String>{
      r'${PID} %m': '$pid paid',
      r'${LOG_LEVEL_PATTERN:-%5p}|%m': ' INFO|paid',
      r'${MISSING:fallback}|${MISSING:-}|': 'fallback||',
      r'${A:-${B:-nested}}': 'nested',
      r'${NAME}': 'shop',
      r'[${app.tag}]': '[blue]',
      r'\${PID}': r'${PID}',
    };
    for (final MapEntry(key: pattern, value: expected) in cases.entries) {
      final text = LogPattern(
        pattern,
        variables: const {'NAME': 'shop'},
        lookup: (name) => name == 'app.tag' ? 'blue' : null,
      ).format(plain);
      expect(text, expected, reason: pattern);
    }
    expect(
      LogPattern(
        r'${LOG_LEVEL_PATTERN:-%5p}|%m',
        variables: const {'LOG_LEVEL_PATTERN': '%-5p'},
      ).format(plain),
      'INFO |paid',
    );
  });

  test('anything it cannot parse is rejected', () {
    const patterns = [
      '%foo',
      '%m %bogus',
      '%clr(%p',
      '%clr(%p){pink}',
      '%clr{red}',
      '%d{yyyy-MM-dd qq}',
      "%d{'T}",
      '%d{HH:mm, Europe/Berlin}',
      '%d{HH:mm:ss,SSS}', // a comma separates the time zone, as in Logback
      r'${NOPE}',
      r'${PID',
      '%',
      'text %',
      '%-p',
      '%5.p',
      '%.p',
      '%logger{x}',
      '%p(x)',
      '%ex{lots}',
      '%d{HH',
    ];
    for (final pattern in patterns) {
      expect(() => LogPattern(pattern), throwsFormatException, reason: pattern);
    }
  });

  test("the default patterns are Spring Boot's", () {
    final thread = isolate.length > 15
        ? isolate.substring(isolate.length - 15)
        : isolate.padLeft(15);
    final record = SpringLogRecord(
      SpringLogLevel.info,
      'neon.checkout.Payments',
      'paid',
      time: time,
      fields: const {'order': 1},
    );
    final console = LogPattern(
      LogPattern.defaultConsolePattern,
      variables: const {'APPLICATION_NAME': 'shop'},
    );
    expect(
      console.formatLine(record),
      '2026-03-07T09:05:02.042${offsetOf(time)}  INFO $pid --- [shop] '
      '[$thread] ${'neon.checkout.Payments'.padRight(40)} : paid {order=1}',
    );
    // Without an application name; the logger abbreviated to 39.
    expect(
      LogPattern(LogPattern.defaultConsolePattern).formatLine(
        SpringLogRecord(
          SpringLogLevel.warning,
          'org.springframework.boot.SpringApplication',
          'm',
          time: time,
        ),
      ),
      endsWith(
        ' WARN $pid --- [$thread] '
        '${'o.s.boot.SpringApplication'.padRight(40)} : m',
      ),
    );
    // Errors follow between blank lines (%wEx).
    expect(
      console.formatLine(failed),
      endsWith(
        ': slow payment\n\nBad state: timeout\n#0 pay (checkout.dart:1)\n',
      ),
    );
    expect(
      LogPattern(LogPattern.defaultConsolePattern, ansi: true).format(record),
      startsWith('\x1B[2m2026-03-07T09:05:02.042'),
    );
    expect(
      LogPattern(
        LogPattern.defaultFilePattern,
        variables: const {'APPLICATION_NAME': 'shop'},
      ).formatLine(record),
      '2026-03-07T09:05:02.042${offsetOf(time)}  INFO $pid --- [shop] '
      '[$isolate] ${'neon.checkout.Payments'.padRight(40)} : paid {order=1}',
    );
  });
}
