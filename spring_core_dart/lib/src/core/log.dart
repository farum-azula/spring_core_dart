import 'dart:async';

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

/// One message emitted through [SpringLog].
///
/// Records are immutable and carry everything a console line or a log
/// viewer screen needs: [time], a unique increasing [sequence] (a stable
/// list key), [level], [loggerName], [message], structured [fields] and the
/// [error] with its [stackTrace].
///
/// ```dart
/// SpringLog.handler = (record) =>
///     myLogger.log(record.level.name, record.message, record.error);
/// ```
final class SpringLogRecord {
  /// Creates a record of [level] from the logger [loggerName].
  SpringLogRecord(
    this.level,
    this.loggerName,
    this.message, {
    this.error,
    this.stackTrace,
    this.fields = const {},
    DateTime? time,
    int? sequence,
  }) : time = time ?? DateTime.now(),
       sequence = sequence ?? _nextSequence++;

  static int _nextSequence = 0;

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

  /// Structured data: the [SpringLog.withFields] context of the caller
  /// merged with the fields passed to the log call (like SLF4J's MDC and
  /// key-value pairs). Never `null`.
  final Map<String, Object?> fields;

  /// When the record was created.
  final DateTime time;

  /// Increasing number, unique within the process.
  final int sequence;

  @override
  String toString() =>
      '[$loggerName] ${level.name.toUpperCase()}: $message'
      '${error == null ? '' : ': $error'}';
}

/// Receives the records that pass the logger's level.
typedef SpringLogHandler = void Function(SpringLogRecord record);

/// A named logger, like the `Log` instances Spring obtains from
/// `LogFactory` (or SLF4J's `Logger`).
///
/// This is the logging facade of the whole family: the framework, starters
/// and applications log through it, and a logging backend (for example
/// `spring_boot_starter_logging`) decides where records go via [handler].
/// Without a backend, records of [SpringLogLevel.warning] and above are
/// printed.
///
/// ```dart
/// const log = SpringLog('neon.checkout');
///
/// log.info('order placed');
/// log.debug(() => 'basket: ${basket.dump()}'); // built only if enabled
/// log.error('payment failed', error: e, stackTrace: s, fields: {'order': 42});
///
/// SpringLog.level = SpringLogLevel.info;                   // root level
/// SpringLog.setLevel('neon.checkout', SpringLogLevel.debug); // and below
/// ```
///
/// Levels are hierarchical by dots: `neon.checkout.payment` uses the level
/// of `neon.checkout.payment`, else `neon.checkout`, else `neon`, else the
/// root [level].
///
/// Spring (Java):
/// ```java
/// private static final Log log = LogFactory.getLog(Checkout.class);
/// log.info("order placed");
/// ```
final class SpringLog {
  /// Creates a logger named [name].
  const SpringLog(this.name);

  /// Logger name, e.g. `spring_core_dart.context`.
  final String name;

  static SpringLogLevel _level = SpringLogLevel.warning;
  static final _levels = <String, SpringLogLevel>{};
  static final _effective = <String, SpringLogLevel>{};
  static final _listeners = <SpringLogHandler>[];
  static final _holds = <SpringLogHold>[];
  static final _fieldsKey = Object();

  /// Holds back every record from now on, of any level, until
  /// [SpringLogHold.release] emits those that pass the levels of that
  /// time, like Spring Boot's `DeferredLog` before the logging system is
  /// initialized. `SpringApplication` holds the records logged before the
  /// `logging.level.*` properties are applied.
  ///
  /// While a hold is active every level is enabled ([isEnabled] is `true`)
  /// and records reach neither [handler] nor the [listen]ers. Holds nest:
  /// releasing an inner one passes its records to the outer one.
  ///
  /// ```dart
  /// final hold = SpringLog.hold();
  /// log.debug('early'); // held
  /// SpringLog.setLevel('neon', SpringLogLevel.debug);
  /// hold.release(); // emits 'early' now
  /// ```
  static SpringLogHold hold() {
    final hold = SpringLogHold._();
    _holds.add(hold);
    return hold;
  }

  // Emits [record] to the handler and listeners, or to the innermost hold.
  static void _dispatch(SpringLogRecord record) {
    if (_holds.lastOrNull case final hold?) {
      hold._records.add(record);
      return;
    }
    handler(record);
    for (final listener in List.of(_listeners)) {
      try {
        listener(record);
      } catch (_) {
        // A broken listener must not break the caller.
      }
    }
  }

  /// The root level: the minimum level of loggers without a level of
  /// their own ([setLevel]); [SpringLogLevel.warning] by default.
  static SpringLogLevel get level => _level;

  static set level(SpringLogLevel value) {
    _level = value;
    _effective.clear();
  }

  /// Sets the level of the logger [name] and its descendants
  /// (`a.b` also applies to `a.b.c`); `null` inherits again.
  static void setLevel(String name, SpringLogLevel? level) {
    if (level == null) {
      _levels.remove(name);
    } else {
      _levels[name] = level;
    }
    _effective.clear();
  }

  /// Levels set with [setLevel], by logger name.
  static Map<String, SpringLogLevel> get configuredLevels =>
      Map.unmodifiable(_levels);

  /// Removes every [setLevel] level (the root [level] stays).
  static void resetLevels() {
    _levels.clear();
    _effective.clear();
  }

  /// The level that applies to the logger [name].
  static SpringLogLevel levelOf(String name) =>
      _effective[name] ??= _resolveLevel(name);

  static SpringLogLevel _resolveLevel(String name) {
    for (var current = name; ;) {
      final own = _levels[current];
      if (own != null) {
        return own;
      }
      final dot = current.lastIndexOf('.');
      if (dot < 0) {
        return _level;
      }
      current = current.substring(0, dot);
    }
  }

  /// The backend: receives every record that passes its logger's level;
  /// [printLogHandler] by default.
  static SpringLogHandler handler = printLogHandler;

  /// Also sends every emitted record to [listener] (after [handler]), for
  /// example to capture logs in a test. Call the returned function to
  /// stop. Errors thrown by listeners are ignored.
  static void Function() listen(SpringLogHandler listener) {
    // A wrapper, so the same function can be registered twice.
    void wrapper(SpringLogRecord record) => listener(record);
    _listeners.add(wrapper);
    return () => _listeners.remove(wrapper);
  }

  /// Runs [body] with [fields] added to every record logged inside it,
  /// also asynchronously (like SLF4J's MDC, but scoped by zones).
  ///
  /// ```dart
  /// SpringLog.withFields({'request': id}, () => handle(request));
  /// ```
  static R withFields<R>(Map<String, Object?> fields, R Function() body) =>
      runZoned(
        body,
        zoneValues: {
          _fieldsKey: {...currentFields, ...fields},
        },
      );

  /// The [withFields] context of the current zone.
  static Map<String, Object?> get currentFields =>
      (Zone.current[_fieldsKey] as Map<String, Object?>?) ?? const {};

  /// Whether records of [level] are currently emitted by this logger.
  /// Check it before building expensive messages (or pass a closure as
  /// the message).
  bool isEnabled(SpringLogLevel level) =>
      level != SpringLogLevel.off &&
      (_holds.isNotEmpty || level.index >= levelOf(name).index);

  /// Emits [message] at [level] if enabled. [message] may be a
  /// `String Function()`, called only when the record is emitted.
  void log(
    SpringLogLevel level,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    if (!isEnabled(level)) {
      return;
    }
    final context = currentFields;
    final record = SpringLogRecord(
      level,
      name,
      '${message is Object? Function() ? message() : message}',
      error: error,
      stackTrace: stackTrace,
      fields: context.isEmpty
          ? Map.unmodifiable(fields)
          : Map.unmodifiable({...context, ...fields}),
    );
    _dispatch(record);
  }

  /// Emits a [SpringLogLevel.trace] message.
  void trace(Object? message, {Map<String, Object?> fields = const {}}) =>
      log(SpringLogLevel.trace, message, fields: fields);

  /// Emits a [SpringLogLevel.debug] message.
  void debug(Object? message, {Map<String, Object?> fields = const {}}) =>
      log(SpringLogLevel.debug, message, fields: fields);

  /// Emits a [SpringLogLevel.info] message.
  void info(Object? message, {Map<String, Object?> fields = const {}}) =>
      log(SpringLogLevel.info, message, fields: fields);

  /// Emits a [SpringLogLevel.warning] message.
  void warning(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => log(
    SpringLogLevel.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Emits a [SpringLogLevel.error] message.
  void error(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => log(
    SpringLogLevel.error,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  @override
  String toString() => 'SpringLog($name)';
}

/// Records held back by [SpringLog.hold] until [release].
///
/// ```dart
/// final hold = SpringLog.hold();
/// try {
///   configureLevels();
/// } finally {
///   hold.release();
/// }
/// ```
///
/// Spring Boot (Java): `DeferredLog.replayTo(destination)`.
final class SpringLogHold {
  SpringLogHold._();

  final _records = <SpringLogRecord>[];

  /// Whether records are still held (until [release]).
  bool get isHolding => SpringLog._holds.contains(this);

  /// Stops holding and emits, in order, the held records that pass the
  /// current level of their logger (to an outer hold, if one is still
  /// active); returns those. A second call does nothing.
  List<SpringLogRecord> release() {
    if (!SpringLog._holds.remove(this)) {
      return const [];
    }
    final passed = [
      for (final record in _records)
        if (record.level != SpringLogLevel.off &&
            (SpringLog._holds.isNotEmpty ||
                record.level.index >=
                    SpringLog.levelOf(record.loggerName).index))
          record,
    ];
    _records.clear();
    passed.forEach(SpringLog._dispatch);
    return passed;
  }
}

/// The default [SpringLog.handler]: prints the record (one line).
void printLogHandler(SpringLogRecord record) {
  // ignore: avoid_print
  print(record);
}

/// Parses a level name as used in properties (`logging.level.*`):
/// `trace`, `debug`, `info`, `warn`/`warning`, `error`, `off`
/// (case-insensitive); `null` for anything else.
SpringLogLevel? parseSpringLogLevel(String? value) =>
    switch (value?.trim().toLowerCase()) {
      'trace' => SpringLogLevel.trace,
      'debug' => SpringLogLevel.debug,
      'info' => SpringLogLevel.info,
      'warn' || 'warning' => SpringLogLevel.warning,
      'error' || 'fatal' => SpringLogLevel.error,
      'off' => SpringLogLevel.off,
      _ => null,
    };
