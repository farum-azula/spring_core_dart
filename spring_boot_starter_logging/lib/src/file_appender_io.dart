import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

/// Writes formatted records to the file [path], rolling it over by size,
/// like Logback's rolling file appender (`logging.file.*`,
/// `logging.logback.rollingpolicy.*`).
///
/// Lines logged in one synchronous burst are written together at the end
/// of the current microtask (one write instead of one per record); [flush]
/// writes immediately and [close] writes the rest. When the file would grow
/// past [maxFileSize], it is renamed to `<path>.1` (older files shift to
/// `.2`, `.3`, ...); only [maxHistory] such archives are kept (all with
/// `0`, like Logback), and the oldest are deleted while together they
/// exceed [totalSizeCap].
///
/// ```dart
/// LoggingSystem.instance.addAppender(
///   FileAppender('/var/log/neon/shop.log', maxFileSize: 5 * 1024 * 1024),
/// );
/// ```
class FileAppender extends LogAppender {
  /// An appender writing to [path] (directories are created).
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

  /// Whether files can be written on this platform.
  static const bool isSupported = true;

  /// The log file.
  final String path;

  /// The line format.
  LogPattern pattern;

  /// Size that triggers a rollover, in bytes; `0` never rolls over.
  final int maxFileSize;

  /// Number of rolled-over files kept (`<path>.1` is the newest); `0`
  /// keeps all, like Logback's `maxHistory`.
  final int maxHistory;

  /// The charset of the file (`logging.charset.file`, UTF-8 by default);
  /// characters it cannot encode are written as `?`, like Java.
  final Encoding encoding;

  /// Total size of the rolled-over files, in bytes: the oldest are deleted
  /// while they exceed it; `0` sets no limit.
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

  /// Writes buffered lines now.
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

  /// Writes the rest and closes the file; later records are ignored.
  @override
  void close() {
    flush();
    _file?.closeSync();
    _file = null;
  }

  @override
  String toString() => 'FileAppender($path)';
}
