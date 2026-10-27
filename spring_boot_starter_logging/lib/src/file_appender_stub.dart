import 'dart:convert';

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
    this.maxFileSize = 10 * 1024 * 1024,
    this.maxHistory = 7,
    this.totalSizeCap = 0,
    // Same signature as the dart:io FileAppender; this one only throws.
    // ignore: avoid_unused_constructor_parameters
    bool cleanHistoryOnStart = false,
    this.encoding = utf8,
    super.threshold,
  }) : pattern = pattern ?? LogPattern(LogPattern.defaultFilePattern) {
    throw UnsupportedError('Log files need dart:io');
  }

  /// Whether files can be written on this platform.
  static const bool isSupported = false;

  /// The log file.
  final String path;

  /// The line format.
  LogPattern pattern;

  /// Size that triggers a rollover, in bytes; `0` never rolls over.
  final int maxFileSize;

  /// Number of rolled-over files kept; `0` keeps all.
  final int maxHistory;

  /// The charset of the file (`logging.charset.file`, UTF-8 by default);
  /// characters it cannot encode are written as `?`, like Java.
  final Encoding encoding;

  /// Total size of the rolled-over files, in bytes; `0` sets no limit.
  final int totalSizeCap;

  @override
  void write(SpringLogRecord record) {}

  /// Writes buffered lines now.
  void flush() {}
}
