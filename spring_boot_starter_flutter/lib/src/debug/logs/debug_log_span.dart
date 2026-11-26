import 'package:flutter/painting.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show SpringLogRecord;
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// [record] as one line of [text], coloured segment by segment as the
/// framework's console colours it, in the colours of the debug theme
/// ([style]): the time and the `:` in its time colour, the level by
/// level, the logger in its logger colour, the message (and its error,
/// on the next line) in [text]'s colour. The text is `debugLogLine`'s.
/// The debug panel's Logs tab and the debug console draw their records
/// with it.
TextSpan debugLogSpan(
  SpringLogRecord record,
  TextStyle text,
  DebugStyle style,
) {
  final faint = TextStyle(color: style.time);
  final error = record.error;
  return TextSpan(
    style: text,
    children: [
      TextSpan(text: debugLogTime(record), style: faint),
      const TextSpan(text: ' '),
      TextSpan(
        text: debugLogLevel(record),
        style: TextStyle(color: style.level(record.level)),
      ),
      const TextSpan(text: ' '),
      TextSpan(
        text: record.loggerName,
        style: TextStyle(color: style.logger),
      ),
      TextSpan(text: ':', style: faint),
      TextSpan(text: ' ${record.message}${error == null ? '' : '\n$error'}'),
    ],
  );
}

/// The time of [record] as a line shows it: `HH:mm:ss.SSS`.
String debugLogTime(SpringLogRecord record) =>
    record.time.toIso8601String().substring(11, 23);

/// The level of [record] as a line shows it: `INFO`, `WARNING`.
String debugLogLevel(SpringLogRecord record) => record.level.name.toUpperCase();
