import 'dart:convert';

import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_text.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

/// A file format of the log export (`debugLogExport`): its file
/// [extension], its [mimeType], and the text of each record. Every
/// `DebugLogFormat` bean is one; the built-in ones are `.log`
/// ([PlainDebugLogFormat]) and `.jsonl` ([JsonLinesDebugLogFormat]). An
/// application adds its own (a CSV, say) as a bean; the debug panel's
/// Logs tab has a button for each.
abstract interface class DebugLogFormat {
  /// The file extension, without the dot, which also names the format
  /// (`log`, `jsonl`).
  String get extension;

  /// The type of the file (`text/plain`).
  String get mimeType;

  /// [record] as its text in the file, ending with a line break.
  String format(SpringLogRecord record);
}

/// `.log`: each record as the console prints it, in the console's pattern
/// (`logging.pattern.console`) at the time of the export, without colours.
final class PlainDebugLogFormat implements DebugLogFormat, Ordered {
  /// The format by the console's [pattern].
  const PlainDebugLogFormat(this.pattern);

  /// The console's pattern now.
  final LogPattern Function() pattern;

  @override
  String get extension => 'log';

  @override
  String get mimeType => 'text/plain';

  @override
  int get order => Ordered.lowestPrecedence - 1;

  @override
  String format(SpringLogRecord record) =>
      '${debugLogPlainText(record, pattern())}\n';
}

/// `.jsonl`: one JSON object per line and record, with `time` (ISO-8601,
/// UTC), `level` (`INFO`, `WARN`, as the console names it), `logger`,
/// `message`, `error` and `stack` (`null` without an error or a stack
/// trace).
final class JsonLinesDebugLogFormat implements DebugLogFormat, Ordered {
  /// The format.
  const JsonLinesDebugLogFormat();

  @override
  String get extension => 'jsonl';

  @override
  String get mimeType => 'application/jsonl';

  @override
  int get order => Ordered.lowestPrecedence;

  @override
  String format(SpringLogRecord record) {
    final error = record.error;
    final stack = record.stackTrace;
    return '${jsonEncode({
      'time': record.time.toUtc().toIso8601String(),
      'level': LogPattern.levelName(record.level),
      'logger': record.loggerName,
      'message': record.message,
      'error': error == null ? null : '$error',
      'stack': stack == null ? null : '$stack',
    })}\n';
  }
}
