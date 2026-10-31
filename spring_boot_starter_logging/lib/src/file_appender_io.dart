import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

const _log = SpringLog('spring_boot_starter_logging');

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
/// A file that cannot be written breaks nothing else, as in Logback: the
/// error is reported once as an error of the `spring_boot_starter_logging`
/// logger (on the console), the lines are dropped meanwhile, and the file
/// is opened and written again after a pause that grows from 20 ms to
/// about 5 minutes with each failed try (on a full disk the file opens,
/// but the write fails). When a write works again, one line reports how
/// many lines were lost; a later failure is reported again. A roll-over
/// that fails (a read-only directory) is reported once too; the lines go
/// on into the current file, past [maxFileSize], and the roll-over is tried
/// again a minute later.
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
  /// `<path>.2`, ...) first; one that cannot be deleted is reported and
  /// kept. Throws an [ArgumentError] for a negative limit, and a
  /// [FileSystemException] when the file cannot be opened (the logging
  /// system then reports it and goes on without the file).
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
        try {
          archive.deleteSync();
        } on FileSystemException catch (error) {
          _log.warning(
            'Cannot delete the old log file ${archive.path}: '
            '${_describe(error)}',
          );
          break;
        }
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
  bool _closed = false;

  // While the file cannot be written: when to try to open it again, the
  // pause after that, and the lines dropped meanwhile (Logback's
  // ResilientFileOutputStream: 20 ms, times 4, up to 327.68 s). Set from
  // the first failed write until a write works again: on a full disk the
  // file opens but the next write fails, so opening it again is no
  // recovery (Logback's postSuccessfulWrite).
  DateTime? _retryAt;
  Duration _retryPause = _firstRetryPause;
  int _lost = 0;
  static const _firstRetryPause = Duration(milliseconds: 20);
  static const _maxRetryPause = Duration(milliseconds: 327680);

  // After a failed roll-over: not before this time again (Logback checks
  // the size once a minute at most).
  DateTime? _rollOverAfter;
  bool _rollOverReported = false;
  static const _rollOverPause = Duration(minutes: 1);

  /// Whether the file cannot be written now: from a failed write until a
  /// write works again (tried on the next lines after a pause), the lines
  /// are dropped.
  bool get isFailing => _retryAt != null;

  void _open() {
    final file = File(path);
    _file = file.openSync(mode: FileMode.append);
    _size = file.lengthSync();
  }

  @override
  void write(SpringLogRecord record) {
    if (_closed) {
      return;
    }
    final retryAt = _retryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      _lost++;
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
  /// in a test or before sharing it. Never throws: a file that cannot be
  /// written is reported (see the class).
  void flush() {
    _flushScheduled = false;
    if (_pending.isEmpty) {
      return;
    }
    final lines = [..._pending];
    _pending.clear();
    if (_file == null && !_reopen()) {
      _lost += lines.length;
      return;
    }
    var written = 0;
    var inChunk = 0;
    try {
      final chunk = BytesBuilder(copy: false);
      for (final line in lines) {
        if (_rollOverDue(line.length)) {
          _file!.writeFromSync(chunk.takeBytes());
          written += inChunk;
          inChunk = 0;
          _rollOver();
        }
        chunk.add(line);
        _size += line.length;
        inChunk++;
      }
      _file!.writeFromSync(chunk.takeBytes());
    } on Object catch (error) {
      _failed(error, lost: lines.length - written);
      return;
    }
    _recovered();
  }

  bool _rollOverDue(int length) {
    if (maxFileSize <= 0 || _size == 0 || _size + length <= maxFileSize) {
      return false;
    }
    final after = _rollOverAfter;
    return after == null || !DateTime.now().isBefore(after);
  }

  // Throws only when the log file itself cannot be opened again.
  void _rollOver() {
    _file!.closeSync();
    _file = null;
    try {
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
      _rollOverAfter = null;
      _rollOverReported = false; // a later failure is reported again
      _capTotalSize();
    } on FileSystemException catch (error) {
      // Logback: "RolloverFailure occurred. Deferring roll-over."
      _rollOverAfter = DateTime.now().add(_rollOverPause);
      if (!_rollOverReported) {
        _rollOverReported = true;
        _log.error(
          'Cannot roll over the log file $path (it grows past its maximum '
          'size until a roll-over works): ${_describe(error)}',
        );
      }
    }
    _open();
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

  // The file failed: drop it, retry later, after a longer pause each time.
  // Only the first failure since the last write that worked is reported.
  void _failed(Object error, {required int lost}) {
    _lost += lost;
    try {
      _file?.closeSync();
    } on Object catch (_) {
      // Already broken.
    }
    _file = null;
    final first = _retryAt == null;
    _retryAt = DateTime.now().add(_retryPause);
    final doubled = _retryPause * 4;
    _retryPause = doubled > _maxRetryPause ? _maxRetryPause : doubled;
    if (first) {
      _log.error(
        'Cannot write the log file $path (its lines are dropped until it '
        'can be written again): ${_describe(error)}',
      );
    }
  }

  // Opens the file again after a failure, when the pause is over. The
  // failure lasts until a write works ([_recovered]).
  bool _reopen() {
    final retryAt = _retryAt;
    if (_closed || retryAt == null || DateTime.now().isBefore(retryAt)) {
      return false;
    }
    try {
      File(path).parent.createSync(recursive: true);
      _open();
    } on Object catch (error) {
      _failed(error, lost: 0);
      return false;
    }
    return true;
  }

  // A write worked: after a failure, the pause starts again from 20 ms
  // and one line says how many lines were lost.
  void _recovered() {
    if (_retryAt == null) {
      return;
    }
    final lost = _lost;
    _retryAt = null;
    _retryPause = _firstRetryPause;
    _lost = 0;
    _log.info(
      'The log file $path is written again; lines lost meanwhile: $lost',
    );
  }

  static String _describe(Object error) => switch (error) {
    FileSystemException(:final message, :final osError?) =>
      '$message (${osError.message})',
    FileSystemException(:final message) => message,
    _ => '$error',
  };

  /// Writes the waiting lines and closes the file; records that arrive
  /// later are dropped. The logging system calls it when the application
  /// context closes or the file settings change. Never throws, also when
  /// the file cannot be written.
  @override
  void close() {
    flush();
    _closed = true;
    _pending.clear();
    final file = _file;
    _file = null;
    try {
      file?.closeSync();
    } on Object catch (_) {
      // Nothing more can be written to it anyway.
    }
  }

  @override
  String toString() => 'FileAppender($path)';
}
