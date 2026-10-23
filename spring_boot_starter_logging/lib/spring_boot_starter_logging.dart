/// Logging for `spring_boot_dart` applications, like
/// `spring-boot-starter-logging`: add the dependency and the
/// auto-configuration installs a [LoggingSystem] behind `SpringLog`.
///
/// - console output in Spring Boot's format, or your own Logback pattern
///   ([LogPattern]);
/// - `logging.*` properties (levels per logger, patterns, thresholds,
///   capacity);
/// - [LogBuffer]: the last records in memory with [LogQuery] filtering,
///   live streams, counters and export, made for an in-app log screen;
/// - log files with size-based rollover ([FileAppender], `logging.file.*`,
///   `logging.logback.rollingpolicy.*`; not on the web);
/// - custom [LogAppender]s (crash reporting, network).
///
/// Re-exports `spring_boot_dart`.
library;

export 'package:spring_boot_dart/spring_boot_dart.dart';
export 'package:spring_boot_starter_logging/src/appenders.dart';
export 'package:spring_boot_starter_logging/src/file_appender.dart';
export 'package:spring_boot_starter_logging/src/log_buffer.dart';
export 'package:spring_boot_starter_logging/src/log_pattern.dart';
export 'package:spring_boot_starter_logging/src/logging_auto_configuration.dart';
export 'package:spring_boot_starter_logging/src/logging_system.dart';
