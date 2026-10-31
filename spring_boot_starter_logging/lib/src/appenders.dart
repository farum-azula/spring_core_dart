import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';
import 'package:spring_boot_starter_logging/src/platform.dart' as platform;

/// One output of the logging system: it receives every log record that
/// passes the logger levels and writes it somewhere.
///
/// The starter's outputs are appenders too: the console
/// ([ConsoleAppender]), the in-memory buffer (`LogBuffer`) and the log
/// file (`FileAppender`). Extend this class when records must also go
/// somewhere else, such as a crash reporter, a remote log service or a
/// database; implement [write], and set [threshold] to keep only the
/// important records. Add it with `LoggingSystem.addAppender`. An
/// appender that throws does not stop the others.
///
/// ```dart
/// // Errors also go to the crash reporter, with their stack trace.
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
///
/// Spring (Java): a Logback `Appender`, usually an `AppenderBase`
/// subclass declared in `logback-spring.xml`. Here it is added in code.
abstract class LogAppender {
  /// An appender that writes records of [threshold] and above (every
  /// level by default).
  LogAppender({this.threshold = SpringLogLevel.trace});

  /// The lowest level this appender writes, checked after the logger
  /// levels; [SpringLogLevel.off] writes nothing.
  ///
  /// The logger levels decide which records exist at all; the threshold
  /// lets one output keep fewer of them, such as a console that shows
  /// only warnings while the file gets everything. The starter sets it on
  /// its outputs from `logging.threshold.console`, `.file` and `.buffer`.
  /// It can be changed at any time.
  SpringLogLevel threshold;

  /// Called by the logging system for each record: passes it to [write]
  /// when it is at or above [threshold], and drops it otherwise.
  void append(SpringLogRecord record) {
    if (threshold != SpringLogLevel.off &&
        record.level.index >= threshold.index) {
      write(record);
    }
  }

  /// Writes [record] to this output. Implement it in a subclass; the
  /// record has already passed [threshold]. It runs synchronously on the
  /// logging call, so slow work (a network call) should be queued.
  void write(SpringLogRecord record);

  /// Releases what the appender holds, such as an open file. Called by
  /// `LoggingSystem.removeAppender`; does nothing by default.
  void close() {}
}

/// The console output: formats each record with a [LogPattern] and
/// passes the text to [out], `print` by default.
///
/// The logging system has one, `LoggingSystem.console`, set up from
/// `logging.pattern.console`, `logging.threshold.console` and
/// `spring.output.ansi.enabled`; applications rarely create another. What
/// they may change is where the lines go: in Flutter, `debugPrint` keeps
/// long lines from being cut by the device log. [out] is called once per
/// record with [LogPattern.formatLine], the text without its final line
/// break, because `print` adds one.
///
/// ```dart
/// // Flutter: before the application starts.
/// LoggingSystem.instance.console.out = debugPrint;
/// ```
///
/// Spring (Java): Logback's `ConsoleAppender`, which Spring Boot's default
/// configuration declares.
class ConsoleAppender extends LogAppender {
  /// A console appender writing with [pattern] to [out]. By default the
  /// pattern is Spring Boot's console pattern
  /// ([LogPattern.defaultConsolePattern]) with colours, and [out] is
  /// standard output on the Dart VM (written at once, not through
  /// `print`) and `print` in a Flutter app (its device log, also when it
  /// runs a server) and on the web (the browser's console).
  ConsoleAppender({
    LogPattern? pattern,
    void Function(String line)? out,
    super.threshold,
  }) : pattern =
           pattern ?? LogPattern(LogPattern.defaultConsolePattern, ansi: true),
       out = out ?? platform.consoleOut();

  /// How a record becomes a line; replace it to change the format at
  /// runtime.
  LogPattern pattern;

  /// Receives each formatted record, without the final line break.
  void Function(String line) out;

  @override
  void write(SpringLogRecord record) => out(pattern.formatLine(record));
}
