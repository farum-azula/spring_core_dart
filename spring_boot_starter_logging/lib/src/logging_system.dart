import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/file_appender.dart';
import 'package:spring_boot_starter_logging/src/log_buffer.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

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
/// logging.setLevel('neon.checkout', SpringLogLevel.debug);
/// logging.buffer.watch();                 // the log screen
/// ```
///
/// Properties (`lib/resources/application.properties`):
///
/// ```properties
/// logging.level.root=info                 # handled by spring_boot_dart
/// logging.level.neon.checkout=debug
/// logging.pattern.console=%d{HH:mm:ss} %-5p [%logger] %m%X%ex
/// logging.threshold.console=warn          # console: warnings only
/// logging.console.enabled=true
/// logging.buffer.enabled=true
/// logging.buffer.capacity=2000
/// logging.threshold.buffer=debug
/// logging.file.name=logs/shop.log         # or logging.file.path=logs (spring.log)
/// logging.pattern.file=%d %5p [%logger] %m%X%ex
/// logging.threshold.file=info
/// logging.file.max-size=10MB              # roll over: shop.log.1, .2, ...
/// logging.file.max-history=7              # rolled-over files kept
/// logging.file.clean-history-on-start=false
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
    if (isInstalled) {
      return;
    }
    _previous = SpringLog.handler;
    SpringLog.handler = _dispatch;
  }

  /// Restores the `SpringLog.handler` that was active before [install] and
  /// closes the log file.
  void uninstall() {
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

  void _dispatch(SpringLogRecord record) {
    for (final appender in appenders) {
      try {
        appender.append(record);
      } catch (_) {
        // One broken appender must not hide the record from the others.
      }
    }
  }

  /// Applies the `logging.*` properties of [environment] (see the class
  /// documentation). The root level becomes `info`, Spring Boot's default,
  /// unless `logging.level.root` is set.
  void configure(PropertyResolver environment) {
    if (environment.getProperty('logging.level.root') == null &&
        environment.getProperty('logging.level') == null) {
      SpringLog.level = SpringLogLevel.info;
    }
    consoleEnabled =
        environment.getProperty('logging.console.enabled') != 'false';
    bufferEnabled =
        environment.getProperty('logging.buffer.enabled') != 'false';
    if (environment.getProperty('logging.pattern.console')
        case final pattern?) {
      console.pattern = LogPattern(pattern);
    }
    console.threshold = _threshold(environment, 'logging.threshold.console');
    buffer.threshold = _threshold(environment, 'logging.threshold.buffer');
    if (_int(environment, 'logging.buffer.capacity') case final capacity?) {
      buffer.capacity = capacity;
    }
    _configureFile(environment);
  }

  void _configureFile(PropertyResolver environment) {
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
    final pattern = environment.getProperty('logging.pattern.file');
    _file = FileAppender(
      path,
      pattern: pattern == null ? null : LogPattern(pattern),
      maxSize: parseDataSize(
        environment.getProperty('logging.file.max-size') ?? '10MB',
      ),
      maxHistory: _int(environment, 'logging.file.max-history') ?? 7,
      cleanHistoryOnStart:
          environment.getProperty('logging.file.clean-history-on-start') ==
          'true',
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
    return parseSpringLogLevel(value) ??
        (throw FormatException('$key: unknown level', value));
  }

  /// The root level (`logging.level.root`).
  SpringLogLevel get rootLevel => SpringLog.level;

  set rootLevel(SpringLogLevel level) => SpringLog.level = level;

  /// Sets the level of [logger] and its descendants; `null` inherits.
  void setLevel(String logger, SpringLogLevel? level) =>
      SpringLog.setLevel(logger, level);

  /// The level that applies to [logger].
  SpringLogLevel levelOf(String logger) => SpringLog.levelOf(logger);

  /// Levels set per logger.
  Map<String, SpringLogLevel> get loggerLevels => SpringLog.configuredLevels;

  @override
  String toString() => 'LoggingSystem(installed: $isInstalled)';
}

/// Configures and installs the [LoggingSystem] as soon as the context
/// starts processing (a `BeanFactoryPostProcessor`, so before application
/// beans exist) and uninstalls it when the context closes.
final class LoggingSystemInitializer
    implements BeanFactoryPostProcessor, PriorityOrdered, DisposableBean {
  /// An initializer reading [environment].
  LoggingSystemInitializer(this.environment, [LoggingSystem? system])
    : system = system ?? LoggingSystem.instance;

  /// Source of the `logging.*` properties.
  final Environment environment;

  /// The configured system.
  final LoggingSystem system;

  @override
  int get order => Ordered.highestPrecedence;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    system
      ..configure(environment)
      ..install();
  }

  @override
  void destroy() => system.uninstall();
}
