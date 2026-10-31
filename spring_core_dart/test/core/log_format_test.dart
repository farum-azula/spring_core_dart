// LogFormatUtils: values from outside cannot add a log line or move the
// terminal; long values are cut.
import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  test('strings in quotes, null empty, others by toString', () {
    expect(LogFormatUtils.formatValue('ada'), '"ada"');
    expect(LogFormatUtils.formatValue(null), '');
    expect(LogFormatUtils.formatValue(42), '42');
  });

  test('line breaks and control characters cannot forge a line', () {
    expect(
      LogFormatUtils.formatValue('ada\nINFO neon.security : root logged in'),
      '"ada<EOL>INFO neon.security : root logged in"',
    );
    expect(LogFormatUtils.formatValue('a\r\nb'), '"a<EOL><EOL>b"');
    expect(LogFormatUtils.formatValue('\x1B[31mred\x1B[0m'), '"?[31mred?[0m"');
    expect(
      LogFormatUtils.formatValue('tab\there\x00\x7F\x85'),
      '"tab?here???"',
    );
    expect(LogFormatUtils.formatValue('ünïcödé ✓'), '"ünïcödé ✓"');
  });

  test('long values are cut; -1 keeps them; the switch keeps them raw', () {
    final long = 'x' * 300;
    expect(
      LogFormatUtils.formatValue(long),
      '"${'x' * 99} (truncated)...',
    );
    expect(LogFormatUtils.formatValue(long, maxLength: -1), '"$long"');
    expect(
      LogFormatUtils.formatValue(
        'a\nb',
        replaceNewlinesAndControlCharacters: false,
      ),
      '"a\nb"',
    );
  });
}
