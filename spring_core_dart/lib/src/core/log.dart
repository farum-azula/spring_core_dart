import 'dart:async';

/// How important a log message is, from [trace] (most detail) to [error];
/// [off] silences a logger.
///
/// Every message is logged at a level, and every logger shows messages
/// from a minimum level up, so the same code can be quiet in production
/// and chatty while debugging. Applications usually set levels in
/// configuration (`logging.level.neon.checkout=debug`) and use the level
/// methods of [SpringLog] (`log.debug(...)`); they name a level directly
/// to set one in code or in a log handler.
///
/// ```dart
/// // While chasing a bug: show debug output of the checkout code.
/// SpringLog.setLevel('neon.checkout', SpringLogLevel.debug);
/// ```
///
/// Spring (Java): `org.apache.commons.logging.Log` levels
/// (`trace`, `debug`, `info`, `warn`, `error`).
enum SpringLogLevel {
  /// Very detailed diagnostics, such as every step of a loop.
  trace,

  /// Diagnostics useful while developing, such as which auto-configuration
  /// conditions matched.
  debug,

  /// Normal operation worth seeing: started, listening on a port.
  info,

  /// Something went wrong but the program carried on, such as a destroy
  /// callback that threw during shutdown. Shown by default.
  warning,

  /// A failure that could not be handled, such as a failed start or a
  /// request that ended in an error. Shown by default.
  error,

  /// Not a message level: as a logger's level it turns that logger's
  /// output off.
  off,
}

/// One logged message with everything known about it, as a log handler
/// receives it.
///
/// Applications receive records when they write a [SpringLogHandler] (to
/// send logs elsewhere) or [SpringLog.listen] (to capture logs in a test
/// or show them on a screen). A record cannot change and carries what a
/// console line or a log viewer needs: [time], a unique increasing
/// [sequence] (a stable list key), [level], [loggerName], [message],
/// structured [fields] and the [error] with its [stackTrace].
///
/// ```dart
/// // Hand every record to a logging package the application already uses.
/// SpringLog.handler = (record) =>
///     myLogger.log(record.level.name, record.message, record.error);
/// ```
final class SpringLogRecord {
  /// Creates a record of [level] from the logger [loggerName]. [time]
  /// defaults to now and [sequence] to the next number; loggers create
  /// records, tests sometimes do.
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

  /// How important the message is.
  final SpringLogLevel level;

  /// The name of the logger that logged it, such as
  /// `spring_core_dart.beans`.
  final String loggerName;

  /// The text of the message, already built.
  final String message;

  /// The error that caused the message, or `null`.
  final Object? error;

  /// The stack trace of [error], or `null`.
  final StackTrace? stackTrace;

  /// Structured data for search and filtering, such as an order id: the
  /// [SpringLog.withFields] context of the caller merged with the fields
  /// passed to the log call (like SLF4J's MDC and key-value pairs). Empty
  /// when there are none, never `null`.
  final Map<String, Object?> fields;

  /// When the message was logged.
  final DateTime time;

  /// A number that grows with every record, unique within the process.
  final int sequence;

  @override
  String toString() =>
      '[$loggerName] ${level.name.toUpperCase()}: $message'
      '${error == null ? '' : ': $error'}';
}

/// A function that receives log records: the type of [SpringLog.handler]
/// (where records go) and of [SpringLog.listen] listeners.
typedef SpringLogHandler = void Function(SpringLogRecord record);

/// An annotation that gives a class a ready-made `log` getter, so its
/// methods can log without declaring a logger.
///
/// The generator writes an extension with a constant [SpringLog] named
/// after the class (`<package>.<Class>`, like
/// `spring_boot_dart.SpringApplication`), so levels can be set per class
/// or per package in configuration. It is the usual way an application
/// logs.
///
/// ```dart
/// import 'package:my_app/main.spring.dart'; // the generated file
///
/// @Component()
/// @Log()
/// class Checkout {
///   void pay(Order order) => log.info('paid ${order.id}'); // my_app.Checkout
/// }
///
/// @Log(topic: 'neon.payments', fieldName: 'logger')
/// class Payments {
///   void refund() => logger.warning('refund');
/// }
/// ```
///
/// The getter lives in the `.spring.dart` file of the `@ComponentScan` or
/// `@SpringBootApplication` that scans the class: import that file in the
/// class's library. A `log` declared in the library's scope wins over the
/// getter, and `dart:math` and `dart:developer` both declare a function
/// `log`, so with one of them imported pick another [fieldName]. Any
/// class of the scan may carry it, bean or not.
///
/// Spring (Java), with Lombok:
/// ```java
/// @Slf4j(topic = "neon.payments")
/// class Payments { void refund() { log.warn("refund"); } }
/// ```
class Log {
  /// Asks for a getter named [fieldName] (`log` unless given) that returns
  /// the logger [topic] (`<package>.<Class>` unless given).
  const Log({this.topic, this.fieldName = 'log'});

  /// The logger name, to group classes under one name such as
  /// `neon.payments`; `<package>.<Class>` when `null`.
  final String? topic;

  /// The name of the generated getter; `log` unless given.
  final String fieldName;
}

/// A named logger: the object code logs through, and the static switches
/// (levels, handler, holds) of logging as a whole.
///
/// It is the one logging API of the whole family: the framework, the
/// starters and applications log through it, and a logging backend (such
/// as `spring_boot_starter_logging`) decides where records go by setting
/// [handler]. Without a backend, records of [SpringLogLevel.warning] and
/// above are printed. An application gets a logger from `@Log()` or
/// declares one as a constant; it sets levels in configuration
/// (`logging.level.<name>`) or with [setLevel].
///
/// ```dart
/// // A logger shared by the checkout code.
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
/// Levels follow the dots in names: `neon.checkout.payment` uses the
/// level set for `neon.checkout.payment`, else `neon.checkout`, else
/// `neon`, else the root [level].
///
/// Spring (Java):
/// ```java
/// private static final Log log = LogFactory.getLog(Checkout.class);
/// log.info("order placed");
/// ```
final class SpringLog {
  /// Creates a logger named [name]; a `const` logger costs nothing until
  /// it logs.
  const SpringLog(this.name);

  /// The logger name, such as `spring_core_dart.context`, used to look up
  /// its level.
  final String name;

  static SpringLogLevel _level = SpringLogLevel.warning;
  static final _levels = <String, SpringLogLevel>{};
  static final _effective = <String, SpringLogLevel>{};
  static final _listeners = <SpringLogHandler>[];
  static final _holds = <SpringLogHold>[];
  static final _fieldsKey = Object();

  /// Holds back every record from now on, of any level, until
  /// [SpringLogHold.release] emits those that pass the levels of that
  /// time.
  ///
  /// It is for startup code that logs before the levels are known:
  /// `SpringApplication` holds the records logged before the
  /// `logging.level.*` properties are applied, like Spring Boot's
  /// `DeferredLog`. Applications rarely call it.
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
      } on Object catch (_) {
        // A broken listener must not break the caller.
      }
    }
  }

  /// The root level: the minimum level of loggers without a level of
  /// their own ([setLevel]); [SpringLogLevel.warning] unless set. The
  /// property `logging.level.root` sets it in an application.
  static SpringLogLevel get level => _level;

  static set level(SpringLogLevel value) {
    _level = value;
    _effective.clear();
  }

  /// Sets the minimum level of the logger [name] and of the loggers below
  /// it (`a.b` also applies to `a.b.c`); `null` makes it inherit again.
  /// Configuration does the same with `logging.level.<name>`.
  static void setLevel(String name, SpringLogLevel? level) {
    if (level == null) {
      _levels.remove(name);
    } else {
      _levels[name] = level;
    }
    _effective.clear();
  }

  /// The levels set with [setLevel], by logger name, as a read-only copy.
  static Map<String, SpringLogLevel> get configuredLevels =>
      Map.unmodifiable(_levels);

  /// Removes every level set with [setLevel]; the root [level] stays.
  /// Useful between tests.
  static void resetLevels() {
    _levels.clear();
    _effective.clear();
  }

  /// The level that applies to the logger [name]: its own, or the nearest
  /// one set above it, or the root [level].
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

  /// Where records go: the function that receives every record that
  /// passes its logger's level. [printLogHandler] unless replaced; a
  /// logging backend replaces it.
  static SpringLogHandler handler = printLogHandler;

  /// Also sends every emitted record to [listener], after [handler], for
  /// example to capture logs in a test or show them in an app. Call the
  /// returned function to stop. Errors thrown by listeners are ignored.
  static void Function() listen(SpringLogHandler listener) {
    // A wrapper, so the same function can be registered twice.
    void wrapper(SpringLogRecord record) => listener(record);
    _listeners.add(wrapper);
    return () => _listeners.remove(wrapper);
  }

  /// Runs [body] with [fields] added to every record logged inside it,
  /// including asynchronous work it starts, and returns its result.
  ///
  /// Use it to tag all logs of one request or job, such as with a request
  /// id. Nested calls add to the outer fields. Like SLF4J's MDC, but
  /// scoped by zones instead of threads.
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

  /// The fields [withFields] has set for the code running now; empty
  /// outside any [withFields].
  static Map<String, Object?> get currentFields =>
      (Zone.current[_fieldsKey] as Map<String, Object?>?) ?? const {};

  /// Whether this logger currently emits records of [level]. Check it
  /// before building an expensive message, or pass a closure as the
  /// message instead. Always `true` while a [hold] is active (except for
  /// [SpringLogLevel.off]).
  bool isEnabled(SpringLogLevel level) =>
      level != SpringLogLevel.off &&
      (_holds.isNotEmpty || level.index >= levelOf(name).index);

  /// Logs [message] at [level] when the level is enabled, with an optional
  /// [error], its [stackTrace] and structured [fields].
  ///
  /// [message] may be a function returning the text, called only when the
  /// record is emitted, so a disabled debug message costs nothing. Any
  /// other object is turned into text with `toString`.
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

  /// Logs [message] at [SpringLogLevel.trace]; see [log].
  void trace(Object? message, {Map<String, Object?> fields = const {}}) =>
      log(SpringLogLevel.trace, message, fields: fields);

  /// Logs [message] at [SpringLogLevel.debug]; see [log].
  void debug(Object? message, {Map<String, Object?> fields = const {}}) =>
      log(SpringLogLevel.debug, message, fields: fields);

  /// Logs [message] at [SpringLogLevel.info]; see [log].
  void info(Object? message, {Map<String, Object?> fields = const {}}) =>
      log(SpringLogLevel.info, message, fields: fields);

  /// Logs [message] at [SpringLogLevel.warning], with the [error] that
  /// caused it when there is one; see [log].
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

  /// Logs [message] at [SpringLogLevel.error], with the [error] that
  /// caused it when there is one; see [log].
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

/// The records held back by one [SpringLog.hold], until [release].
///
/// Startup code receives it from [SpringLog.hold] and must release it,
/// even when startup fails, or the held records never appear.
///
/// ```dart
/// // Levels are configured first, then the early records are judged.
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

  /// Whether this hold is still holding records, until [release].
  bool get isHolding => SpringLog._holds.contains(this);

  /// Stops holding and emits, in order, the held records that pass the
  /// current level of their logger, or hands them to an outer hold if one
  /// is still active. Returns the records it passed on. A second call does
  /// nothing and returns an empty list.
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

/// The [SpringLog.handler] used until a logging backend replaces it:
/// prints each record as one line, in colour like Spring Boot's console.
///
/// The logger name is cyan and the level coloured by level (error red,
/// warning yellow, the others green); the error follows the message, the
/// stack trace is not printed. For plain text, set
/// `SpringLog.handler = print;` (a record prints as its `toString`).
void printLogHandler(SpringLogRecord record) {
  final level = switch (record.level) {
    SpringLogLevel.error => '31',
    SpringLogLevel.warning => '33',
    _ => '32',
  };
  final error = record.error;
  // Printing is the point of this handler.
  // ignore: avoid_print
  print(
    '[\x1B[36m${record.loggerName}\x1B[0;39m] '
    '\x1B[${level}m${record.level.name.toUpperCase()}\x1B[0;39m: '
    '${record.message}${error == null ? '' : ': $error'}',
  );
}

/// Reads a level name as written in configuration (`logging.level.*`):
/// `trace`, `debug`, `info`, `warn` or `warning`, `error` (also `fatal`)
/// and `off`, in any case and with spaces around. `null` for anything
/// else, so the caller can report the bad value.
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
