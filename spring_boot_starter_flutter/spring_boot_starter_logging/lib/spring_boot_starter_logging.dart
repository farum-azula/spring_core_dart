/// Console and file logging for `spring_boot_dart` applications: add the
/// dependency and the lines written through `SpringLog` (and the `log`
/// getter of `@Log()`) come out in Spring Boot's format, configured from
/// the `logging.*` properties. No code is needed.
///
/// Import it for the types an application may touch on top of that:
///
/// - `LoggingSystem`, to change logger levels at runtime or add an
///   output;
/// - `LogPattern`, the Logback pattern syntax of
///   `logging.pattern.console` and `logging.pattern.file`;
/// - `LogBuffer` and `LogQuery`, the last records in memory, made for an
///   in-app log screen;
/// - `FileAppender`, log files that roll over by size (`logging.file.*`,
///   `logging.logback.rollingpolicy.*`; not on the web);
/// - `LogAppender`, your own output, such as crash reporting.
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
