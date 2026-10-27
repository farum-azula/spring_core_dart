import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/file_appender.dart';
import 'package:spring_boot_starter_logging/src/log_buffer.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';
import 'package:spring_boot_starter_logging/src/platform.dart' as platform;

const _log = SpringLog('spring_boot_starter_logging');

/// Parses a data size as used in properties: `10MB`, `512 KB`, `1GB`,
/// `100B` or plain bytes (`1024`); units are binary (1 KB = 1024 bytes),
/// like Spring's `DataSize`.
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

/// The logging backend behind `SpringLog`, like Spring Boot's
/// `LoggingSystem` (with Logback): sends records to the [console], the
/// in-memory [buffer], a log [file] and any added [LogAppender]s, and
/// changes logger
/// levels at runtime (like the `/actuator/loggers` endpoint).
///
/// With Spring Boot it is installed and configured from properties by the
/// starter's auto-configuration; without Boot call [configure] / [install]
/// yourself.
///
/// ```dart
/// final logging = LoggingSystem.instance; // or inject LoggingSystem
/// logging.console.out = debugPrint;       // Flutter
/// logging.setLogLevel('neon.checkout', SpringLogLevel.debug);
/// logging.buffer.watch();                 // the log screen
/// ```
///
/// Spring Boot (Java):
/// ```java
/// LoggingSystem logging = LoggingSystem.get(classLoader);
/// logging.setLogLevel("neon.checkout", LogLevel.DEBUG);
/// ```
///
/// Properties (`lib/resources/application.properties`):
///
/// ```properties
/// logging.level.root=info                 # handled by spring_boot_dart
/// logging.level.neon.checkout=debug
/// logging.pattern.console=%d{HH:mm:ss} %-5p [%logger] %m%X%n%ex
/// logging.pattern.dateformat=yyyy-MM-dd HH:mm:ss.SSS
/// logging.pattern.level=%5p
/// logging.include-application-name=true   # [spring.application.name] in lines
/// logging.threshold.console=warn          # console: warnings only
/// spring.output.ansi.enabled=detect       # %clr colours: detect/always/never
/// logging.console.enabled=true
/// logging.buffer.enabled=true
/// logging.buffer.capacity=2000
/// logging.threshold.buffer=debug
/// logging.file.name=logs/shop.log         # or logging.file.path=logs (spring.log)
/// logging.pattern.file=%d %5p [%logger] %m%X%n%ex
/// logging.threshold.file=info
/// logging.logback.rollingpolicy.max-file-size=10MB   # shop.log.1, .2, ...
/// logging.logback.rollingpolicy.max-history=7        # rolled-over files kept
/// logging.logback.rollingpolicy.total-size-cap=0B    # total (0B: no limit)
/// logging.logback.rollingpolicy.clean-history-on-start=false
/// logging.enabled=false                   # leave SpringLog alone
/// ```
///
/// Relative file locations are resolved against [fileDirectory] when set
/// (for example the app's documents directory in Flutter), else against
/// the working directory. Files are not written on the web.
final class LoggingSystem {
  LoggingSystem._();

  /// The process-wide logging system (`SpringLog` itself is global).
  static final instance = LoggingSystem._();

  /// Formatted output, `print` by default.
  final console = ConsoleAppender();

  /// The last records in memory, for a log viewer.
  final buffer = LogBuffer();

  final _appenders = <LogAppender>[];
  SpringLogHandler? _previous;
  FileAppender? _file;

  /// Base directory of relative `logging.file.name` / `logging.file.path`
  /// values; set it before the application starts.
  String? fileDirectory;

  /// The file appender configured by `logging.file.*`, if any.
  FileAppender? get file => _file;

  /// Whether [console] receives records.
  bool consoleEnabled = true;

  /// Whether [buffer] receives records.
  bool bufferEnabled = true;

  /// Every active appender: [console], [buffer], [file], then the added
  /// ones.
  List<LogAppender> get appenders => List.unmodifiable([
    if (consoleEnabled) console,
    if (bufferEnabled) buffer,
    ?_file,
    ..._appenders,
  ]);

  /// Also sends records to [appender].
  void addAppender(LogAppender appender) => _appenders.add(appender);

  /// Stops sending records to [appender] and closes it.
  bool removeAppender(LogAppender appender) {
    final removed = _appenders.remove(appender);
    if (removed) {
      appender.close();
    }
    return removed;
  }

  /// Whether `SpringLog` records currently come here.
  bool get isInstalled => _previous != null;

  /// Makes this the `SpringLog.handler` (the previous one is restored by
  /// [uninstall]).
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

  /// Restores the `SpringLog.handler` that was active before [install] and
  /// closes the log file.
  void uninstall() {
    _uninstallPending = false;
    _closeFile();
    final previous = _previous;
    if (previous == null) {
      return;
    }
    if (SpringLog.handler == _dispatch) {
      SpringLog.handler = previous;
    }
    _previous = null;
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

  /// Applies the `logging.*` properties of [environment] (see the class
  /// documentation). The root level becomes `info`, Spring Boot's default,
  /// unless `logging.level.root` (in any case) is set. The console gets
  /// `logging.pattern.console` or Spring Boot's pattern
  /// ([LogPattern.defaultConsolePattern]).
  void configure(PropertyResolver environment) {
    if (_uninstallPending) {
      uninstall();
    }
    // Validated like Boot's binding, though only its condition reads it.
    _flag(environment, 'logging.enabled');
    if (!_rootLevelConfigured(environment)) {
      SpringLog.level = SpringLogLevel.info;
    }
    final consolePattern =
        _rawProperty(environment, 'logging.pattern.console') ??
        LogPattern.defaultConsolePattern;
    // An empty pattern turns the console off, as Logback's appender does
    // not start without one.
    consoleEnabled =
        _flag(environment, 'logging.console.enabled') &&
        consolePattern.trim().isNotEmpty;
    bufferEnabled = _flag(environment, 'logging.buffer.enabled');
    final variables = _variables(environment);
    String? lookup(String name) => environment.getProperty(name);
    _charset(environment, 'logging.charset.console');
    console.pattern = LogPattern(
      consolePattern.trim().isEmpty ? '%m' : consolePattern,
      variables: variables,
      lookup: lookup,
      ansi: _ansi(environment),
    );
    console.threshold = _threshold(environment, 'logging.threshold.console');
    buffer.threshold = _threshold(environment, 'logging.threshold.buffer');
    if (_int(environment, 'logging.buffer.capacity') case final capacity?) {
      buffer.capacity = capacity;
    }
    _configureFile(environment, variables, lookup);
  }

  // `logging.level.root`, `logging.level.ROOT`, ... or `logging.level`.
  static bool _rootLevelConfigured(PropertyResolver environment) {
    if (environment.getProperty('logging.level.root') != null ||
        environment.getProperty('logging.level') != null) {
      return true;
    }
    if (environment is! ConfigurableEnvironment) {
      return false;
    }
    return environment.propertySources.any(
      (source) =>
          source is EnumerablePropertySource<Object> &&
          source.propertyNames.any(
            (name) => name.toLowerCase() == 'logging.level.root',
          ),
    );
  }

  // The values of Spring Boot's logging system properties, as pattern
  // variables (`${LOG_LEVEL_PATTERN:-%5p}` in the default patterns).
  static Map<String, String> _variables(PropertyResolver environment) {
    String? raw(String key) => _blankToNull(_rawProperty(environment, key));
    String? value(String key) => _blankToNull(environment.getProperty(key));
    bool include(String key) => _flag(environment, key);
    return {
      'LOG_LEVEL_PATTERN': ?raw('logging.pattern.level'),
      'LOG_DATEFORMAT_PATTERN': ?raw('logging.pattern.dateformat'),
      'LOG_EXCEPTION_CONVERSION_WORD': ?raw(
        'logging.exception-conversion-word',
      ),
      'LOG_CORRELATION_PATTERN': ?raw('logging.pattern.correlation'),
      if (include('logging.include-application-name'))
        'APPLICATION_NAME': ?value('spring.application.name'),
      if (include('logging.include-application-group'))
        'APPLICATION_GROUP': ?value('spring.application.group'),
      'LOG_FILE': ?value('logging.file.name'),
      'LOG_PATH': ?value('logging.file.path'),
    };
  }

  // A pattern property as written: Spring's placeholder resolution would
  // reject `${PID}` and read `${LOG_LEVEL_PATTERN:-%5p}` as a default of
  // `-%5p`; LogPattern resolves the variables itself, as Logback does.
  static String? _rawProperty(PropertyResolver environment, String key) {
    if (environment is ConfigurableEnvironment) {
      for (final source in environment.propertySources) {
        if (source.getProperty(key) case final value?) {
          return '$value';
        }
      }
      return null;
    }
    return environment.getProperty(key);
  }

  // `spring.output.ansi.enabled`: the colours of `%clr` on the console.
  static bool _ansi(PropertyResolver environment) {
    final value = environment.getProperty('spring.output.ansi.enabled');
    return switch (value?.trim().toLowerCase()) {
      null || '' || 'detect' => platform.stdoutSupportsAnsi,
      'always' => true,
      'never' => false,
      _ => throw FormatException(
        'spring.output.ansi.enabled must be detect, always or never',
        value,
      ),
    };
  }

  // The names before Spring Boot's logging.logback.rollingpolicy.*.
  static const _removedProperties = {
    'logging.file.max-size': 'logging.logback.rollingpolicy.max-file-size',
    'logging.file.max-history': 'logging.logback.rollingpolicy.max-history',
    'logging.file.total-size-cap':
        'logging.logback.rollingpolicy.total-size-cap',
    'logging.file.clean-history-on-start':
        'logging.logback.rollingpolicy.clean-history-on-start',
  };

  void _configureFile(
    PropertyResolver environment,
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
    final name = _blankToNull(environment.getProperty('logging.file.name'));
    final directory = _blankToNull(
      environment.getProperty('logging.file.path'),
    );
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
    const policy = 'logging.logback.rollingpolicy';
    if (environment.containsProperty('$policy.file-name-pattern')) {
      _log.warning(
        '$policy.file-name-pattern is not supported (ignored): files roll '
        'over by size only, to <file>.1, <file>.2, ...',
      );
    }
    final filePattern =
        _rawProperty(environment, 'logging.pattern.file') ??
        LogPattern.defaultFilePattern;
    // An empty pattern: no file, as Logback's appender does not start.
    if (filePattern.trim().isEmpty) {
      return;
    }
    _file = FileAppender(
      path,
      pattern: LogPattern(filePattern, variables: variables, lookup: lookup),
      encoding: _charset(environment, 'logging.charset.file') ?? utf8,
      maxFileSize: parseDataSize(
        environment.getProperty('$policy.max-file-size') ?? '10MB',
      ),
      maxHistory: _int(environment, '$policy.max-history') ?? 7,
      totalSizeCap: parseDataSize(
        environment.getProperty('$policy.total-size-cap') ?? '0B',
      ),
      cleanHistoryOnStart: _flag(
        environment,
        '$policy.clean-history-on-start',
        defaultValue: false,
      ),
      threshold: _threshold(environment, 'logging.threshold.file'),
    );
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

  static int? _int(PropertyResolver environment, String key) {
    final value = environment.getProperty(key);
    if (value == null) {
      return null;
    }
    return int.tryParse(value.trim()) ??
        (throw FormatException('$key must be a number', value));
  }

  void _closeFile() {
    final file = _file;
    _file = null;
    file?.close();
  }

  static SpringLogLevel _threshold(PropertyResolver environment, String key) {
    final value = environment.getProperty(key);
    if (value == null || value.trim().isEmpty) {
      return SpringLogLevel.trace;
    }
    // `false` is YAML's `off`, like Boot's lenient enum conversion.
    if (value.trim().toLowerCase() == 'false') {
      return SpringLogLevel.off;
    }
    return parseSpringLogLevel(value) ??
        (throw FormatException('$key: unknown level', value));
  }

  // A boolean property like Boot's binding: true / false (also on / off,
  // yes / no, 1 / 0) in any case; anything else fails the start.
  static bool _flag(
    PropertyResolver environment,
    String key, {
    bool defaultValue = true,
  }) {
    final value = environment.getProperty(key);
    return switch (value?.trim().toLowerCase()) {
      null || '' => defaultValue,
      'true' || 'on' || 'yes' || '1' => true,
      'false' || 'off' || 'no' || '0' => false,
      _ => throw FormatException(
        '$key: failed to convert to boolean (was "$value")',
        value,
      ),
    };
  }

  // `logging.charset.*`: an encoding Dart knows (UTF-8, ISO-8859-1,
  // US-ASCII and their IANA or Java aliases, `Charset.forName`), or a
  // failed start.
  static Encoding? _charset(PropertyResolver environment, String key) {
    final value = _blankToNull(environment.getProperty(key));
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

  /// The name of the root logger, like Spring Boot's
  /// `LoggingSystem.ROOT_LOGGER_NAME`; matched in any case.
  static const rootLoggerName = 'ROOT';

  static bool _isRoot(String? logger) =>
      logger == null ||
      logger.isEmpty ||
      logger.toUpperCase() == rootLoggerName;

  /// The root level (`logging.level.root`).
  SpringLogLevel get rootLevel => SpringLog.level;

  set rootLevel(SpringLogLevel level) => SpringLog.level = level;

  /// Sets the level of [loggerName] and its descendants, like Spring
  /// Boot's `LoggingSystem.setLogLevel`; a `null` [level] inherits again.
  /// `ROOT` (in any case) or `null` is the root logger, which needs a
  /// level.
  ///
  /// ```dart
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

  /// The level that applies to [logger] (`ROOT` in any case: the root
  /// level).
  SpringLogLevel levelOf(String logger) =>
      _isRoot(logger) ? SpringLog.level : SpringLog.levelOf(logger);

  /// Levels set per logger.
  Map<String, SpringLogLevel> get loggerLevels => SpringLog.configuredLevels;

  @override
  String toString() => 'LoggingSystem(installed: $isInstalled)';
}

/// Configures and installs the [LoggingSystem] as soon as the context
/// starts processing (a `BeanFactoryPostProcessor`, so before application
/// beans exist) and uninstalls it when the context closes. When the start
/// fails it stays installed until the failure has been logged (Spring
/// Boot's report reaches the log file too).
final class LoggingSystemInitializer
    implements
        BeanFactoryPostProcessor,
        PriorityOrdered,
        DisposableBean,
        ApplicationContextAware {
  /// An initializer reading [environment].
  LoggingSystemInitializer(this.environment, [LoggingSystem? system])
    : system = system ?? LoggingSystem.instance;

  /// Source of the `logging.*` properties.
  final Environment environment;

  /// The configured system.
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
