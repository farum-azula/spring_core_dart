import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

/// A log file: each record is formatted with a [LogPattern] and appended
/// to the file [path], which is rolled over when it grows too large.
///
/// Most applications do not create one: setting `logging.file.name` (a
/// file) or `logging.file.path` (a directory, with `spring.log` in it)
/// makes the starter create it, with its limits from
/// `logging.logback.rollingpolicy.*`; it is then `LoggingSystem.file`.
/// Create one yourself for a second file, such as one that keeps only
/// errors.
///
/// Lines logged in one synchronous burst are written together at the end
/// of the current microtask, one write instead of one per record; [flush]
/// writes at once and [close] writes the rest. When the file would grow
/// past [maxFileSize], it is renamed to `<path>.1` and a new file is
/// started; older files shift to `.2`, `.3`, and so on. Only [maxHistory]
/// such files are kept (all of them with `0`, as in Logback), and the
/// oldest are deleted while together they exceed [totalSizeCap].
///
/// ```dart
/// // A second file with the errors only, kept apart from the main log.
/// LoggingSystem.instance.addAppender(
///   FileAppender(
///     'logs/errors.log',
///     maxFileSize: 5 * 1024 * 1024,
///     threshold: SpringLogLevel.error,
///   ),
/// );
/// ```
///
/// Spring (Java): Logback's `RollingFileAppender` with a size-based policy,
/// which Spring Boot sets up from the same properties. Here files roll over
/// by size only, into numbered files that are not compressed.
class FileAppender extends LogAppender {
  /// Opens [path] for appending, creating missing directories.
  ///
  /// [pattern] defaults to Spring Boot's file pattern
  /// ([LogPattern.defaultFilePattern], without colours). The limits
  /// default to 10 MB per file, 7 rolled-over files and no total limit.
  /// [cleanHistoryOnStart] deletes the rolled-over files (`<path>.1`,
  /// `<path>.2`, ...) first. Throws an [ArgumentError] for a negative
  /// limit, and a [FileSystemException] when the file cannot be opened.
  FileAppender(
    this.path, {
    LogPattern? pattern,
    this.maxFileSize = 10 * 1024 * 1024,
    this.maxHistory = 7,
    this.totalSizeCap = 0,
    bool cleanHistoryOnStart = false,
    this.encoding = utf8,
    super.threshold,
  }) : pattern = pattern ?? LogPattern(LogPattern.defaultFilePattern) {
    if (maxFileSize < 0 || maxHistory < 0 || totalSizeCap < 0) {
      throw ArgumentError(
        'maxFileSize, maxHistory and totalSizeCap must not be negative',
      );
    }
    final file = File(path);
    file.parent.createSync(recursive: true);
    if (cleanHistoryOnStart) {
      for (var i = 1; ; i++) {
        final archive = File('$path.$i');
        if (!archive.existsSync()) {
          break;
        }
        archive.deleteSync();
      }
    }
    _open();
  }

  /// Whether log files can be written on this platform: `true` here, and
  /// `false` on the web, where creating a [FileAppender] throws.
  static const bool isSupported = true;

  /// The location of the log file, as given to the constructor.
  final String path;

  /// How a record becomes a line; it can be replaced at runtime.
  LogPattern pattern;

  /// The size in bytes the file may not grow past: the line that would
  /// cross it goes into a new file. `0` never rolls over. A single line
  /// larger than the limit is still written whole.
  final int maxFileSize;

  /// How many rolled-over files are kept (`<path>.1` is the newest);
  /// `0` keeps all of them. Unlike Logback's `maxHistory`, it counts
  /// files, not days.
  final int maxHistory;

  /// The charset the lines are written in (`logging.charset.file`, UTF-8
  /// by default). Characters it cannot encode are written as `?`, as in
  /// Java.
  final Encoding encoding;

  /// The most bytes the rolled-over files may take together: after each
  /// rollover the oldest are deleted until they fit. `0` sets no limit.
  /// The current file is not counted.
  final int totalSizeCap;

  RandomAccessFile? _file;
  int _size = 0;
  final _pending = <List<int>>[];
  bool _flushScheduled = false;

  void _open() {
    final file = File(path);
    _file = file.openSync(mode: FileMode.append);
    _size = file.lengthSync();
  }

  @override
  void write(SpringLogRecord record) {
    if (_file == null) {
      return;
    }
    _pending.add(_encode('${pattern.formatLine(record)}\n'));
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(flush);
    }
  }

  List<int> _encode(String text) {
    final limit = switch (encoding) {
      AsciiCodec() => 0x7f,
      Latin1Codec() => 0xff,
      _ => null,
    };
    if (limit == null) {
      return encoding.encode(text);
    }
    return [
      for (final rune in text.runes)
        if (rune > limit) 0x3f else rune,
    ];
  }

  /// Writes the lines waiting for the end of the microtask now, rolling
  /// the file over when needed. Useful before reading the file, such as
  /// in a test or before sharing it.
  void flush() {
    _flushScheduled = false;
    final file = _file;
    if (file == null || _pending.isEmpty) {
      return;
    }
    final lines = [..._pending];
    _pending.clear();
    var current = file;
    final chunk = BytesBuilder(copy: false);
    for (final line in lines) {
      if (maxFileSize > 0 && _size > 0 && _size + line.length > maxFileSize) {
        current.writeFromSync(chunk.takeBytes());
        current = _rollOver();
      }
      chunk.add(line);
      _size += line.length;
    }
    current.writeFromSync(chunk.takeBytes());
  }

  RandomAccessFile _rollOver() {
    _file!.closeSync();
    if (maxHistory > 0) {
      final oldest = File('$path.$maxHistory');
      if (oldest.existsSync()) {
        oldest.deleteSync();
      }
    }
    for (var i = _lastArchive(); i >= 1; i--) {
      final archive = File('$path.$i');
      if (archive.existsSync()) {
        archive.renameSync('$path.${i + 1}');
      }
    }
    File(path).renameSync('$path.1');
    _capTotalSize();
    _open();
    return _file!;
  }

  // The index of the oldest archive kept: maxHistory - 1 before a rollover
  // with a limit, the last one in a row (`.1`, `.2`, ...) without (0).
  int _lastArchive() {
    if (maxHistory > 0) {
      return maxHistory - 1;
    }
    var last = 0;
    while (File('$path.${last + 1}').existsSync()) {
      last++;
    }
    return last;
  }

  // Deletes the oldest archives while all of them exceed totalSizeCap.
  void _capTotalSize() {
    if (totalSizeCap <= 0) {
      return;
    }
    final last = maxHistory > 0 ? maxHistory : _lastArchive();
    final archives = [
      for (var i = 1; i <= last; i++)
        if (File('$path.$i') case final file when file.existsSync()) file,
    ];
    var total = archives.fold(0, (sum, file) => sum + file.lengthSync());
    for (final file in archives.reversed) {
      if (total <= totalSizeCap) {
        break;
      }
      total -= file.lengthSync();
      file.deleteSync();
    }
  }

  /// Writes the waiting lines and closes the file; records that arrive
  /// later are dropped. The logging system calls it when the application
  /// context closes or the file settings change.
  @override
  void close() {
    flush();
    _file?.closeSync();
    _file = null;
  }

  @override
  String toString() => 'FileAppender($path)';
}
