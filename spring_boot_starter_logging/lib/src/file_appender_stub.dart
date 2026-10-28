import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

/// A log file, which the web cannot have: this version keeps the API of
/// the real one so code compiles everywhere, but its constructor throws.
///
/// Check [isSupported] before creating one. The starter does: on the web
/// it ignores `logging.file.*` with a warning.
class FileAppender extends LogAppender {
  /// Always throws an [UnsupportedError]: there is no file system here.
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

  /// Whether log files can be written on this platform: always `false`
  /// here.
  static const bool isSupported = false;

  /// The location of the log file, as given to the constructor.
  final String path;

  /// How a record becomes a line.
  LogPattern pattern;

  /// The size in bytes that starts a new file; `0` never rolls over.
  final int maxFileSize;

  /// How many rolled-over files are kept; `0` keeps all of them.
  final int maxHistory;

  /// The charset the lines are written in (`logging.charset.file`, UTF-8
  /// by default).
  final Encoding encoding;

  /// The most bytes the rolled-over files may take together; `0` sets no
  /// limit.
  final int totalSizeCap;

  @override
  void write(SpringLogRecord record) {}

  /// Does nothing: nothing is ever buffered here.
  void flush() {}
}
