/// Severity of a [SpringLogRecord], like the levels of Spring's
/// (commons-)logging.
///
/// ```dart
/// SpringLog.level = SpringLogLevel.debug; // also show debug output
/// ```
///
/// Spring (Java): `org.apache.commons.logging.Log` levels
/// (`trace`, `debug`, `info`, `warn`, `error`).
enum SpringLogLevel {
  /// Very detailed diagnostics.
  trace,

  /// Diagnostics useful while developing (e.g. condition evaluation).
  debug,

  /// Normal operation.
  info,

  /// Something went wrong but the framework carried on (e.g. a destroy
  /// callback threw during shutdown).
  warning,

  /// An error the framework could not handle.
  error,

  /// Disables all output when used as [SpringLog.level].
  off,
}

/// One message emitted by the framework through [SpringLog].
///
/// ```dart
/// SpringLog.handler = (record) =>
///     myLogger.log(record.level.name, record.message, record.error);
/// ```
final class SpringLogRecord {
  /// Creates a record of [level] from the logger [loggerName].
  const SpringLogRecord(
    this.level,
    this.loggerName,
    this.message, {
    this.error,
    this.stackTrace,
  });

  /// Severity.
  final SpringLogLevel level;

  /// Name of the emitting logger, e.g. `spring_core_dart.beans`.
  final String loggerName;

  /// The message.
  final String message;

  /// The error that caused the message, if any.
  final Object? error;

  /// Stack trace of [error], if any.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      '[$loggerName] ${level.name.toUpperCase()}: $message'
      '${error == null ? '' : ': $error'}';
}

/// Receives the records that pass [SpringLog.level].
typedef SpringLogHandler = void Function(SpringLogRecord record);

/// A named framework logger, like the `Log` instances Spring obtains from
/// `LogFactory`.
///
/// The framework logs problems it recovers from (for example a destroy
/// callback that throws while the context closes) instead of hiding them.
/// By default records of [SpringLogLevel.warning] and above are printed;
/// route them elsewhere with [handler] (for example to `package:logging`)
/// and change the threshold with [level].
///
/// ```dart
/// SpringLog.level = SpringLogLevel.debug;
/// SpringLog.handler = (record) => stderr.writeln(record);
///
/// const log = SpringLog('my_app.startup');
/// log.info('ready');
/// ```
///
/// Spring (Java):
/// ```java
/// private static final Log log = LogFactory.getLog(MyBean.class);
/// log.info("ready");
/// ```
final class SpringLog {
  /// Creates a logger named [name].
  const SpringLog(this.name);

  /// Logger name, e.g. `spring_core_dart.context`.
  final String name;

  /// Minimum level that reaches [handler]; [SpringLogLevel.warning] by
  /// default.
  static SpringLogLevel level = SpringLogLevel.warning;

  /// Receives every record that passes [level]; [printLogHandler] by
  /// default.
  static SpringLogHandler handler = printLogHandler;

  /// Whether records of [level] are currently emitted. Check it before
  /// building expensive messages.
  bool isEnabled(SpringLogLevel level) =>
      level != SpringLogLevel.off && level.index >= SpringLog.level.index;

  /// Emits [message] at [level] if enabled.
  void log(
    SpringLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (isEnabled(level)) {
      handler(
        SpringLogRecord(
          level,
          name,
          message,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Emits a [SpringLogLevel.trace] message.
  void trace(String message) => log(SpringLogLevel.trace, message);

  /// Emits a [SpringLogLevel.debug] message.
  void debug(String message) => log(SpringLogLevel.debug, message);

  /// Emits a [SpringLogLevel.info] message.
  void info(String message) => log(SpringLogLevel.info, message);

  /// Emits a [SpringLogLevel.warning] message.
  void warning(String message, {Object? error, StackTrace? stackTrace}) => log(
    SpringLogLevel.warning,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  /// Emits a [SpringLogLevel.error] message.
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(SpringLogLevel.error, message, error: error, stackTrace: stackTrace);

  @override
  String toString() => 'SpringLog($name)';
}

/// The default [SpringLog.handler]: prints the record (one line).
void printLogHandler(SpringLogRecord record) {
  // ignore: avoid_print
  print(record);
}
