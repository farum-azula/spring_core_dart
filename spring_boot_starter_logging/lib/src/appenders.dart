import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

/// A destination for log records, like a Logback appender.
///
/// ```dart
/// class CrashReportAppender extends LogAppender {
///   CrashReportAppender() : super(threshold: SpringLogLevel.error);
///
///   @override
///   void write(SpringLogRecord record) =>
///       crashReporter.log(record.message, record.error, record.stackTrace);
/// }
///
/// LoggingSystem.instance.addAppender(CrashReportAppender());
/// ```
abstract class LogAppender {
  /// An appender that ignores records below [threshold].
  LogAppender({this.threshold = SpringLogLevel.trace});

  /// Minimum level written by this appender (Spring Boot's
  /// `logging.threshold.*`), on top of the logger levels.
  SpringLogLevel threshold;

  /// Writes [record] if it passes [threshold].
  void append(SpringLogRecord record) {
    if (threshold != SpringLogLevel.off &&
        record.level.index >= threshold.index) {
      write(record);
    }
  }

  /// Writes a record that passed [threshold].
  void write(SpringLogRecord record);

  /// Releases resources when removed from the logging system.
  void close() {}
}

/// Writes formatted records to [out] (`print` by default; pass
/// `debugPrint` in Flutter).
///
/// ```dart
/// ConsoleAppender(pattern: LogPattern('%-5p %logger: %m'), out: debugPrint)
/// ```
class ConsoleAppender extends LogAppender {
  /// A console appender with [pattern] ([LogPattern.defaultPattern]).
  ConsoleAppender({
    LogPattern? pattern,
    void Function(String line)? out,
    super.threshold,
  }) : pattern = pattern ?? LogPattern(LogPattern.defaultPattern),
       out = out ?? print;

  /// The line format.
  LogPattern pattern;

  /// Receives each formatted record.
  void Function(String line) out;

  @override
  void write(SpringLogRecord record) => out(pattern.format(record));
}
