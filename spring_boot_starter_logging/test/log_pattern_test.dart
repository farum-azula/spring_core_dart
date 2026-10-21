import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:test/test.dart';

void main() {
  final record = SpringLogRecord(
    SpringLogLevel.warning,
    'neon.checkout',
    'slow payment',
    time: DateTime(2026, 3, 7, 9, 5, 2, 42),
    sequence: 12,
    fields: const {'order': 42, 'user': 'ada'},
    error: StateError('timeout'),
    stackTrace: StackTrace.fromString('#0 pay (checkout.dart:1)\n'),
  );

  test('tokens', () {
    expect(
      LogPattern('%d %p %c: %m [%seq] 100%%').format(record),
      '2026-03-07 09:05:02.042 WARN neon.checkout: slow payment [12] 100%',
    );
    expect(
      LogPattern('%date{HH:mm} %level %logger %msg%n').format(record),
      '09:05 WARN neon.checkout slow payment\n',
    );
    expect(LogPattern('%X{order}/%X{none}').format(record), '42/');
    expect(
      LogPattern('%m%X').format(record),
      'slow payment {order=42, user=ada}',
    );
    expect(
      LogPattern('%m%ex').format(record),
      'slow payment\nBad state: timeout\n#0 pay (checkout.dart:1)',
    );
  });

  test('widths pad left or right', () {
    expect(LogPattern('[%5p][%-7c]').format(record), '[ WARN][neon.checkout]');
    expect(LogPattern('[%-6p]').format(record), '[WARN  ]');
  });

  test('empty fields and errors render nothing', () {
    final plain = SpringLogRecord(SpringLogLevel.info, 'a', 'm');
    expect(LogPattern('%m%X%ex').format(plain), 'm');
    expect(
      LogPattern(LogPattern.defaultPattern).format(plain),
      matches(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}  INFO --- \[a\] m$'),
    );
  });

  test('unknown tokens are rejected', () {
    expect(() => LogPattern('%m %thread'), throwsFormatException);
  });
}
