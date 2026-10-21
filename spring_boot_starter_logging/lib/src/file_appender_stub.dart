import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

/// Writes records to a file; not available on this platform (no file
/// system), see [isSupported].
class FileAppender extends LogAppender {
  /// Throws [UnsupportedError]: there is no file system here.
  FileAppender(
    this.path, {
    LogPattern? pattern,
    this.maxSize = 10 * 1024 * 1024,
    this.maxHistory = 7,
    bool cleanHistoryOnStart = false,
    super.threshold,
  }) : pattern = pattern ?? LogPattern(LogPattern.defaultPattern) {
    throw UnsupportedError('Log files need dart:io');
  }

  /// Whether files can be written on this platform.
  static const bool isSupported = false;

  /// The log file.
  final String path;

  /// The line format.
  LogPattern pattern;

  /// Size that triggers a rollover, in bytes; `0` never rolls over.
  final int maxSize;

  /// Number of rolled-over files kept.
  final int maxHistory;

  @override
  void write(SpringLogRecord record) {}

  /// Writes buffered lines now.
  void flush() {}
}
