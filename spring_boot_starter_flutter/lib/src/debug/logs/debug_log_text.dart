import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

/// [record] as plain text in the console's [pattern]: the line, with its
/// error and stack trace on the lines after when the pattern prints
/// them, without colours (no ANSI escapes, whatever the pattern colours)
/// and without a final line break. What the debug panel's Logs tab copies
/// and the `.log` export writes.
String debugLogPlainText(SpringLogRecord record, LogPattern pattern) =>
    withoutAnsi(pattern.formatLine(record));

/// Whether none of [held], records a view keeps on screen while scrolled
/// up, is in the buffer any more: it was cleared, or all of them were
/// evicted. [records] are the buffer's, oldest first.
bool debugLogsHeldGone(
  Iterable<SpringLogRecord> held,
  List<SpringLogRecord> records,
) {
  if (held.isEmpty) {
    return false;
  }
  if (records.isEmpty) {
    return true;
  }
  var newest = held.first.sequence;
  for (final record in held) {
    if (record.sequence > newest) {
      newest = record.sequence;
    }
  }
  return newest < records.first.sequence;
}

/// [records] as [debugLogPlainText] gives each, one after the other.
String debugLogPlainLines(
  Iterable<SpringLogRecord> records,
  LogPattern pattern,
) => [for (final record in records) debugLogPlainText(record, pattern)].join(
  '\n',
);

/// [text] without its ANSI escapes (colours, bold, faint).
String withoutAnsi(String text) =>
    text.contains('\x1B') ? text.replaceAll(_ansi, '') : text;

final _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

/// The pattern of the console when the app has no logging system: the
/// time, the level, the logger and the message, then the error.
final LogPattern debugLogFallbackPattern = LogPattern(
  '%d{HH:mm:ss.SSS} %5p [%logger] %m%X%n%ex',
);
