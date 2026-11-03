import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/file_appender.dart';
import 'package:spring_boot_starter_logging/src/log_buffer.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';
import 'package:spring_boot_starter_logging/src/platform.dart' as platform;
import 'package:spring_boot_starter_logging/src/properties/logging_properties.dart';
import 'package:spring_boot_starter_logging/src/properties/properties_beans.dart';

const _log = SpringLog('spring_boot_starter_logging');

/// Reads a size written in a property, such as
/// `logging.file.rolling-policy.max-file-size`, and returns it in bytes.
///
/// Accepts `10MB`, `512 KB`, `1GB`, `100B` or a plain number of bytes
/// (`1024`); the unit is case-insensitive. Units are binary, as in
/// Spring's `DataSize`: 1 KB is 1024 bytes. Throws a [FormatException]
/// for anything else, such as `10 megabytes` or `-1MB`.
///
/// ```dart
/// parseDataSize('10MB'); // 10485760
/// ```
int parseDataSize(String value) {
  final match = RegExp(
    r'^\s*(\d+)\s*(B|KB|MB|GB|TB)?\s*$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) {
    throw FormatException('Not a data size (e.g. 10MB)', value);
  }
  final unit = switch (match.group(2)?.toUpperCase()) {
    'KB' => 1024,
    'MB' => 1024 * 1024,
    'GB' => 1024 * 1024 * 1024,
    'TB' => 1024 * 1024 * 1024 * 1024,
    _ => 1,
  };
  return int.parse(match.group(1)!) * unit;
}

/// Where log records go once this starter is installed: it receives every
/// record written through `SpringLog` and sends it to the [console], the
/// in-memory [buffer], the log [file] and any appender you added.
///
/// `SpringLog` alone only prints plain lines. This class gives an
/// application Spring Boot's logging: formatted, coloured console lines, a
/// log file that rolls over, a buffer for an in-app log screen, and
/// logger levels that can change while the application runs. There is one
/// per process, [instance]. With Spring Boot, the starter configures it
/// from the `logging.*` properties and installs it as the context starts,
/// so most applications only write properties. Code uses it to change a
/// level at runtime, to add an output with [addAppender], or, in Flutter,
/// to send the console to `debugPrint` and set [fileDirectory] before the
/// application starts. Without Spring Boot, call [configure] and
/// [install] yourself.
///
/// ```dart
/// // An admin action turns on debug lines for the checkout, no restart.
/// @Service()
/// class LogLevels {
///   LogLevels(this.logging); // the starter's `loggingSystem` bean
///
///   final LoggingSystem logging;
///
///   void debugCheckout() =>
///       logging.setLogLevel('neon.checkout', SpringLogLevel.debug);
/// }
/// ```
///
/// Spring Boot (Java):
/// ```java
/// LoggingSystem logging = LoggingSystem.get(classLoader);
/// logging.setLogLevel("neon.checkout", LogLevel.DEBUG);
/// ```
///
/// The properties it reads (`lib/resources/application.properties`); the
/// `logging.level.*` and `logging.group.*` ones are applied by
/// `spring_boot_dart` itself:
///
/// ```properties
/// logging.level.root=info                 # handled by spring_boot_dart
/// logging.level.neon.checkout=debug
/// logging.pattern.console=%d{HH:mm:ss} %-5p [%logger] %m%X%n%ex
/// logging.pattern.dateformat=yyyy-MM-dd HH:mm:ss.SSS
/// logging.pattern.level=%5p
/// logging.include-application-name=true   # [spring.application.name] in lines
/// logging.threshold.console=warn          # console: warnings only
/// spring.output.ansi.enabled=always       # colours: always (default)/detect/never
/// logging.console.enabled=true
/// logging.buffer.enabled=true
/// logging.buffer.capacity=2000
/// logging.threshold.buffer=debug
/// logging.file.name=logs/shop.log         # or logging.file.path=logs (spring.log)
/// logging.pattern.file=%d %5p [%logger] %m%X%n%ex
/// logging.threshold.file=info
/// logging.file.rolling-policy.max-file-size=10MB   # shop.log.1, .2, ...
/// logging.file.rolling-policy.max-history=7        # rolled-over files kept
/// logging.file.rolling-policy.total-size-cap=0B    # total (0B: no limit)
/// logging.file.rolling-policy.clean-history-on-start=false
/// logging.enabled=false                   # leave SpringLog alone
/// ```
///
/// Relative file locations are resolved against [fileDirectory] when it is
/// set (for example the app's documents directory in Flutter), else
/// against the working directory. Files are not written on the web.
final class LoggingSystem {
  LoggingSystem._();

  /// The logging system of this process. There is only one because
  /// `SpringLog` is global; the starter's `loggingSystem` bean is this
  /// object.
  static final instance = LoggingSystem._();

  /// The console output. The starter sets its pattern, colours and
  /// threshold from `logging.pattern.console`,
  /// `spring.output.ansi.enabled` and `logging.threshold.console`; its
  /// lines go to standard output on the Dart VM
  /// (`logging.console.target=stderr` for standard error) and to `print`
  /// in Flutter and on the web, unless you change `console.out`.
  final console = ConsoleAppender();

  /// The last records in memory, for an in-app log screen; also the
  /// `logBuffer` bean. It keeps `logging.buffer.capacity` records, 1000 by
  /// default.
  final buffer = LogBuffer();

  final _appenders = <LogAppender>[];
  SpringLogHandler? _previous;
  FileAppender? _file;

  /// The directory a relative `logging.file.name` or `logging.file.path`
  /// is resolved against; `null` uses the working directory.
  ///
  /// Set it before the application starts, as it is read when the
  /// properties are applied. A Flutter app needs it, since its writable
  /// directory is only known at runtime:
  ///
  /// ```dart
  /// LoggingSystem.instance.fileDirectory =
  ///     (await getApplicationDocumentsDirectory()).path; // path_provider
  /// ```
  String? fileDirectory;

  /// The log file set up from `logging.file.*`; `null` when no file is
  /// configured, on the web, when `logging.pattern.file` is empty, or when
  /// the file cannot be opened.
  FileAppender? get file => _file;

  /// Whether [console] receives records. The starter sets it from
  /// `logging.console.enabled`, and to `false` when
  /// `logging.pattern.console` is empty.
  bool consoleEnabled = true;

  /// Whether [buffer] receives records (`logging.buffer.enabled`, `true`
  /// by default).
  bool bufferEnabled = true;

  /// The outputs that receive records now, in the order they get them:
  /// [console] and [buffer] when enabled, [file] when there is one, then
  /// the ones added with [addAppender]. An unmodifiable snapshot.
  List<LogAppender> get appenders => List.unmodifiable([
    if (consoleEnabled) console,
    if (bufferEnabled) buffer,
    ?_file,
    ..._appenders,
  ]);

  /// Sends every record from now on to [appender] as well, after the
  /// built-in outputs. It stays until [removeAppender], also across
  /// [uninstall] and a new start.
  void addAppender(LogAppender appender) => _appenders.add(appender);

  /// Stops sending records to [appender], an appender added with
  /// [addAppender], and closes it. Returns `false`, and does nothing, when
  /// it was not added. An error closing it is logged, not thrown.
  bool removeAppender(LogAppender appender) {
    final removed = _appenders.remove(appender);
    if (removed) {
      try {
        appender.close();
      } on Object catch (error) {
        _log.warning('Cannot close the log appender $appender: $error');
      }
    }
    return removed;
  }

  /// Whether this system is the `SpringLog.handler` now, so records come
  /// here.
  bool get isInstalled => _previous != null;

  /// Makes this system receive every `SpringLog` record by becoming the
  /// `SpringLog.handler`; the handler it replaces is kept for
  /// [uninstall]. Does nothing when already installed.
  ///
  /// The starter calls it when the context starts. Call it yourself only
  /// without Spring Boot, after [configure].
  void install() {
    if (_uninstallPending) {
      uninstall();
    }
    if (isInstalled) {
      return;
    }
    _previous = SpringLog.handler;
    SpringLog.handler = _dispatch;
  }

  /// Gives `SpringLog` back the handler it had before [install], and closes
  /// the log file. The starter calls it when the context closes. When some
  /// other code has replaced the handler in between, that handler stays.
  void uninstall() {
    _uninstallPending = false;
    try {
      _closeFile();
    } finally {
      final previous = _previous;
      if (previous != null) {
        if (SpringLog.handler == _dispatch) {
          SpringLog.handler = previous;
        }
        _previous = null;
      }
    }
  }

  bool _uninstallPending = false;

  // A failed start: like Logback after Spring Boot's cleanUp, records still
  // reach the appenders (and the file) while the failure is reported;
  // uninstalled once the current work is done, or by the next install.
  void _uninstallAfterFailure() {
    if (!isInstalled && _file == null) {
      return;
    }
    _uninstallPending = true;
    Timer.run(() {
      if (_uninstallPending) {
        uninstall();
      }
    });
  }

  void _dispatch(SpringLogRecord record) {
    for (final appender in appenders) {
      try {
        appender.append(record);
      } on Object catch (_) {
        // One broken appender must not hide the record from the others.
      }
    }
  }

  /// Sets up the outputs from the `logging.*` properties of [environment],
  /// the ones listed on this class. It does not [install] the system.
  ///
  /// The root level becomes `info`, Spring Boot's default, unless
  /// `logging.level` or `logging.level.root` (in any case) is set
  /// (`SpringLog` starts at `info` without this starter too). The console
  /// gets `logging.pattern.console` or Spring Boot's pattern
  /// ([LogPattern.defaultConsolePattern]). An open log file is closed and
  /// a new one is opened from the current `logging.file.*` values.
  ///
  /// The properties are bound like any `@ConfigurationProperties` class
  /// ([LoggingProperties]): a value that cannot be read (a level, a
  /// number, a size, an on/off value, `spring.output.ansi.enabled`) throws
  /// a [ConfigurationPropertiesBindException], and so do a pattern or a
  /// charset that is invalid (a [FormatException]). In an application that
  /// fails the start. A log file that cannot be opened (a read-only
  /// directory) does not: the error is logged and the application runs
  /// without the file, as with Logback.
  void configure(ConfigurableEnvironment environment) {
    if (_uninstallPending) {
      uninstall();
    }
    final logging = _bind(environment, LoggingProperties());
    if (!_rootLevelConfigured(environment, logging)) {
      SpringLog.level = SpringLogLevel.info;
    }
    final consolePattern =
        logging.pattern.console ?? LogPattern.defaultConsolePattern;
    // An empty pattern turns the console off, as Logback's appender does
    // not start without one.
    consoleEnabled =
        logging.console.enabled && consolePattern.trim().isNotEmpty;
    bufferEnabled = logging.buffer.enabled;
    final variables = _variables(environment, logging);
    String? lookup(String name) => environment.getProperty(name);
    _charset(logging.charset.console, 'logging.charset.console');
    console.pattern = LogPattern(
      consolePattern.trim().isEmpty ? '%m' : consolePattern,
      variables: variables,
      lookup: lookup,
      ansi: _ansi(_bind(environment, AnsiProperties()).enabled),
    );
    console.threshold = _level(
      logging.threshold.console,
      'logging.threshold.console',
    );
    _consoleTarget(logging.console.target);
    buffer
      ..threshold = _level(logging.threshold.buffer, 'logging.threshold.buffer')
      ..capacity = logging.buffer.capacity;
    _configureFile(environment, logging, variables, lookup);
  }

  // The introspections of the classes `configure` binds: this starter's
  // and `spring.application.name` of Boot's.
  static final _introspector = BeanIntrospector(
    introspections: [
      ...loggingConfigBeans.introspections,
      ...bootPropertiesBeans.introspections,
    ],
  );

  // [properties] filled from [environment]: the binding of a bean, which
  // the context cannot do yet (this runs before the beans are created).
  static T _bind<T extends Object>(
    ConfigurableEnvironment environment,
    T properties,
  ) {
    final name = '${properties.runtimeType}';
    return ConfigurationPropertiesBinder(
          environment,
          _introspector,
        ).postProcessBeforeInitialization(
          properties,
          '${name[0].toLowerCase()}${name.substring(1)}',
        )
        as T;
  }

  // `logging.level.root` (in any case) or the scalar `logging.level`.
  static bool _rootLevelConfigured(
    ConfigurableEnvironment environment,
    LoggingProperties logging,
  ) =>
      logging.level.keys.any((name) => name.toLowerCase() == 'root') ||
      environment.getProperty('logging.level') != null;

  // The values of Spring Boot's logging system properties, as pattern
  // variables (`${LOG_LEVEL_PATTERN:-%5p}` in the default patterns).
  static Map<String, String> _variables(
    ConfigurableEnvironment environment,
    LoggingProperties logging,
  ) {
    final application = _bind(environment, ApplicationProperties());
    final group = _bind(environment, ApplicationGroupProperties());
    return {
      'LOG_LEVEL_PATTERN': ?_blankToNull(logging.pattern.level),
      'LOG_DATEFORMAT_PATTERN': ?_blankToNull(logging.pattern.dateformat),
      'LOG_EXCEPTION_CONVERSION_WORD': ?_blankToNull(
        logging.exceptionConversionWord,
      ),
      'LOG_CORRELATION_PATTERN': ?_blankToNull(logging.pattern.correlation),
      if (logging.includeApplicationName)
        'APPLICATION_NAME': ?_blankToNull(application.name),
      if (logging.includeApplicationGroup)
        'APPLICATION_GROUP': ?_blankToNull(group.group),
      'LOG_FILE': ?_blankToNull(logging.file.name),
      'LOG_PATH': ?_blankToNull(logging.file.path),
    };
  }

  // The out set by logging.console.target, to tell it from one the
  // application set (debugPrint in Flutter): only ours is replaced.
  void Function(String)? _targetOut;

  // `logging.console.target`: `stdout` (the default, Logback's
  // `System.out`) or `stderr` (`System.err`). Logback's ConsoleAppender
  // has the setting; Spring Boot has no property for it. In Flutter and
  // on the web both are `print`.
  void _consoleTarget(ConsoleTarget? target) {
    final stderr = switch (target) {
      null => null,
      ConsoleTarget.stdout || ConsoleTarget.systemOut => false,
      ConsoleTarget.stderr || ConsoleTarget.systemErr => true,
    };
    if (stderr == null) {
      if (_targetOut != null && identical(console.out, _targetOut)) {
        console.out = platform.consoleOut();
      }
      _targetOut = null;
      return;
    }
    console.out = _targetOut = platform.consoleOut(stderr: stderr);
  }

  // `spring.output.ansi.enabled`: the console's colours. On by default
  // (Spring Boot detects a terminal: `detect`); `never` for plain text.
  static bool _ansi(AnsiOutput? value) => switch (value) {
    AnsiOutput.detect => platform.stdoutSupportsAnsi,
    // On by default, but not where the console escapes the codes
    // (a Flutter app on iOS: its system log shows `\^[[32m`).
    null => !platform.consoleEscapesAnsi,
    AnsiOutput.always => true,
    AnsiOutput.never => false,
  };

  // The names from before Spring Boot 2.4, which this project never read.
  static const _removedProperties = {
    'logging.file.max-size': 'logging.file.rolling-policy.max-file-size',
    'logging.file.max-history': 'logging.file.rolling-policy.max-history',
    'logging.file.total-size-cap': 'logging.file.rolling-policy.total-size-cap',
    'logging.file.clean-history-on-start':
        'logging.file.rolling-policy.clean-history-on-start',
  };

  void _configureFile(
    ConfigurableEnvironment environment,
    LoggingProperties logging,
    Map<String, String> variables,
    String? Function(String name) lookup,
  ) {
    for (final MapEntry(key: removed, value: current)
        in _removedProperties.entries) {
      if (environment.containsProperty(removed)) {
        _log.warning('$removed is not supported (ignored): use $current');
      }
    }
    _closeFile();
    final name = _blankToNull(logging.file.name);
    final directory = _blankToNull(logging.file.path);
    if (name == null && directory == null) {
      return;
    }
    if (!FileAppender.isSupported) {
      _log.warning(
        'logging.file.* is ignored: no file system on this platform',
      );
      return;
    }
    final path = _resolve(name ?? '${_trimSlash(directory!)}/spring.log');
    const policy = 'logging.file.rolling-policy';
    if (environment.containsProperty('$policy.file-name-pattern')) {
      _log.warning(
        '$policy.file-name-pattern is not supported (ignored): files roll '
        'over by size only, to <file>.1, <file>.2, ...',
      );
    }
    final filePattern = logging.pattern.file ?? LogPattern.defaultFilePattern;
    // An empty pattern: no file, as Logback's appender does not start.
    if (filePattern.trim().isEmpty) {
      return;
    }
    final pattern = LogPattern(
      filePattern,
      variables: variables,
      lookup: lookup,
    );
    final encoding = _charset(logging.charset.file, 'logging.charset.file');
    final rolling = logging.file.rollingPolicy;
    final maxFileSize = rolling.maxFileSize.toBytes();
    final maxHistory = rolling.maxHistory;
    final totalSizeCap = rolling.totalSizeCap?.toBytes() ?? 0;
    final cleanHistoryOnStart = rolling.cleanHistoryOnStart;
    final threshold = _level(logging.threshold.file, 'logging.threshold.file');
    try {
      _file = FileAppender(
        path,
        pattern: pattern,
        encoding: encoding ?? utf8,
        maxFileSize: maxFileSize,
        maxHistory: maxHistory,
        totalSizeCap: totalSizeCap,
        cleanHistoryOnStart: cleanHistoryOnStart,
        threshold: threshold,
      );
    } on Exception catch (error) {
      // The file system's error (the values were read above). Logback
      // reports that its file appender did not start, and the
      // application starts without the file.
      _log.error(
        'Cannot open the log file $path (logging goes on without it): '
        '$error',
      );
    }
  }

  String _resolve(String location) {
    final base = fileDirectory;
    final absolute =
        location.startsWith('/') ||
        location.startsWith(r'\\') || // Windows UNC path
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(location); // C:\ or C:/
    return absolute || base == null
        ? location
        : '${_trimSlash(base)}/$location';
  }

  static String _trimSlash(String path) =>
      path.length > 1 && (path.endsWith('/') || path.endsWith(r'\'))
      ? path.substring(0, path.length - 1)
      : path;

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  void _closeFile() {
    final file = _file;
    _file = null;
    try {
      file?.close();
    } on Object catch (error) {
      _log.warning('Cannot close the log file ${file?.path}: $error');
    }
  }

  // A threshold: a level name (`warn` and `fatal` too), or `false`, which
  // is YAML's `off`, like Boot's lenient enum conversion.
  static SpringLogLevel _level(String value, String key) {
    if (value.trim().isEmpty) {
      return SpringLogLevel.trace;
    }
    if (value.trim().toLowerCase() == 'false') {
      return SpringLogLevel.off;
    }
    return parseSpringLogLevel(value) ??
        (throw FormatException('$key: unknown level', value));
  }

  // `logging.charset.*`: an encoding Dart knows (UTF-8, ISO-8859-1,
  // US-ASCII and their IANA or Java aliases, `Charset.forName`), or a
  // failed start.
  static Encoding? _charset(String? raw, String key) {
    final value = _blankToNull(raw);
    if (value == null) {
      return null;
    }
    final name = value.trim().toLowerCase();
    return Encoding.getByName(name) ??
        _javaCharsetAliases[name] ??
        (throw FormatException(
          '$key: unsupported charset (use UTF-8, ISO-8859-1 or US-ASCII)',
          value,
        ));
  }

  // Java's aliases of the charsets Dart knows, missing from the IANA names
  // `Encoding.getByName` takes.
  static const Map<String, Encoding> _javaCharsetAliases = {
    'utf8': utf8,
    'unicode-1-1-utf-8': utf8,
    'iso8859_1': latin1,
    'iso8859-1': latin1,
    'iso_8859_1': latin1,
    '8859_1': latin1,
    '819': latin1,
    'ibm-819': latin1,
    'ascii7': ascii,
    '646': ascii,
    'default': ascii,
  };

  // Records logged before this system took over (Spring Boot's
  // DeferredLogs): to every appender but the console, as the handler of
  // the time has shown them already.
  void _replay(List<SpringLogRecord> records) {
    for (final record in records) {
      for (final appender in appenders) {
        if (identical(appender, console)) {
          continue;
        }
        try {
          appender.append(record);
        } on Object catch (_) {
          // As in _dispatch.
        }
      }
    }
  }

  /// The name that means the root logger in [setLogLevel] and [levelOf],
  /// matched in any case, as Spring Boot's
  /// `LoggingSystem.ROOT_LOGGER_NAME`.
  static const rootLoggerName = 'ROOT';

  static bool _isRoot(String? logger) =>
      logger == null ||
      logger.isEmpty ||
      logger.toUpperCase() == rootLoggerName;

  /// The level of every logger that has none of its own nor an ancestor
  /// with one (`logging.level.root`); setting it takes effect at once.
  SpringLogLevel get rootLevel => SpringLog.level;

  set rootLevel(SpringLogLevel level) => SpringLog.level = level;

  /// Changes the level of [loggerName] and its descendants while the
  /// application runs, as `logging.level.<name>` does at startup.
  ///
  /// `neon` also applies to `neon.checkout`, unless that logger has a level
  /// of its own. A `null` [level] removes the logger's own level, so it
  /// inherits again. `ROOT` (in any case), an empty name or `null` is the
  /// root logger; it needs a level, otherwise an [ArgumentError] is
  /// thrown.
  ///
  /// ```dart
  /// // Look into one part of the application, keep the rest quiet.
  /// logging.setLogLevel('neon.checkout', SpringLogLevel.debug);
  /// logging.setLogLevel('ROOT', SpringLogLevel.warning);
  /// ```
  void setLogLevel(String? loggerName, SpringLogLevel? level) {
    if (_isRoot(loggerName)) {
      if (level == null) {
        throw ArgumentError.value(
          level,
          'level',
          'The root logger needs a level',
        );
      }
      SpringLog.level = level;
      return;
    }
    SpringLog.setLevel(loggerName!, level);
  }

  /// The level that applies to [logger]: its own, else that of its
  /// nearest ancestor with one, else the root level. `ROOT` (in any case)
  /// gives the root level.
  SpringLogLevel levelOf(String logger) =>
      _isRoot(logger) ? SpringLog.level : SpringLog.levelOf(logger);

  /// The levels set for single loggers, by logger name, from
  /// `logging.level.*` and [setLogLevel]; the root level is not in it.
  Map<String, SpringLogLevel> get loggerLevels => SpringLog.configuredLevels;

  @override
  String toString() => 'LoggingSystem(installed: $isInstalled)';
}

/// The bean that ties the [LoggingSystem] to the life of an application
/// context. Applications never use it; the starter registers it.
///
/// It configures and installs the logging system as soon as the context
/// starts processing its beans (it is a `BeanFactoryPostProcessor`, so this
/// happens before any application bean exists), and uninstalls it when the
/// context closes. Lines logged earlier in the start, which Spring Boot
/// holds as `DeferredLogs`, are then written to the file, the buffer and
/// the added appenders; the console has shown them already. When the
/// start fails, the system stays installed until the failure has been
/// logged, so the report reaches the log file too.
final class LoggingSystemInitializer
    implements
        BeanFactoryPostProcessor,
        PriorityOrdered,
        DisposableBean,
        ApplicationContextAware {
  /// An initializer that configures [system] ([LoggingSystem.instance] by
  /// default) from [environment].
  LoggingSystemInitializer(this.environment, [LoggingSystem? system])
    : system = system ?? LoggingSystem.instance;

  /// Where the `logging.*` properties are read.
  final ConfigurableEnvironment environment;

  /// The logging system it configures and installs.
  final LoggingSystem system;

  @override
  int get order => Ordered.highestPrecedence;

  ApplicationContext? _context;
  bool _closing = false;

  @override
  void setApplicationContext(ApplicationContext applicationContext) =>
      _context = applicationContext;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    system
      ..configure(environment)
      ..install();
    if (beanFactory.containsBean(DeferredLogs.beanName)) {
      final deferred = beanFactory.getBeanByName(DeferredLogs.beanName);
      if (deferred is DeferredLogs) {
        system._replay(deferred.switchOver());
      }
    }
    if (_context case final ConfigurableApplicationContext context) {
      context.addApplicationListener(_ClosedListener(this));
    }
  }

  @override
  void destroy() {
    // Destroyed without ContextClosedEvent: the refresh failed, and Spring
    // Boot is about to report it.
    if (_context != null && !_closing) {
      system._uninstallAfterFailure();
    } else {
      system.uninstall();
    }
  }
}

final class _ClosedListener implements GenericApplicationListener {
  _ClosedListener(this.initializer);

  final LoggingSystemInitializer initializer;

  @override
  bool supportsEvent(Object event) => event is ContextClosedEvent;

  @override
  void onApplicationEvent(Object event) => initializer._closing = true;
}
