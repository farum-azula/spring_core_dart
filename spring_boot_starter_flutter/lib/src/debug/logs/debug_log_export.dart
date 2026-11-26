import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart' show SpringLogRecord;
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_file_export.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_format.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_logs_action.dart';

/// The log export (`debugLogExport`): records as a file of a
/// [DebugLogFormat], named `<app>-logs-<yyyyMMdd-HHmmss>.<extension>`,
/// handed to the first available [DebugFileExport] ([files]). The debug
/// panel's Logs tab has an `Export .<extension>` button per format (the
/// marked records, or all its filter shows); a console command calls
/// [exportRecords].
///
/// The file is made on the UI isolate in slices of at most [slice] of
/// work, each followed by a turn of the event loop, so a frame is never
/// held for the whole buffer: on every platform alike, the web included.
/// Not in an isolate: a record holds its error and stack trace, any
/// object, which would have to become text before it could be sent, and
/// that is most of the work.
///
/// In the build only with `spring.flutter.debug.logs.export.enabled` (not
/// set: debug builds), and only with the debug panel or the
/// console.
final class DebugLogExport implements DebugLogsActions {
  /// The export of [formats] to [files], the files named after [appName].
  DebugLogExport({
    required this.formats,
    required this.files,
    required String appName,
    this.slice = const Duration(milliseconds: 4),
    this._clock = DateTime.now,
  }) : appName = _fileSafe(appName);

  /// The formats, in order.
  final List<DebugLogFormat> formats;

  /// Where a file goes.
  final DebugFileExports files;

  /// The start of a file's name: `spring.application.name`, else
  /// `spring.flutter.app.title`, else `app`, with what a file name cannot
  /// hold made `-`.
  final String appName;

  /// The most work done between two turns of the event loop.
  final Duration slice;

  final DateTime Function() _clock;

  @override
  List<DebugLogsAction> get actions => [
    for (final format in formats)
      DebugLogsAction(
        'Export .${format.extension}',
        (records) => exportRecords(records, format),
        short: '.${format.extension}',
      ),
  ];

  /// The format of [extension] (`log`, `jsonl`); an [ArgumentError] naming
  /// the others when there is none.
  DebugLogFormat format(String extension) {
    final name = extension.startsWith('.') ? extension.substring(1) : extension;
    for (final format in formats) {
      if (format.extension == name) {
        return format;
      }
    }
    throw ArgumentError.value(
      extension,
      'extension',
      'not one of ${formats.map((f) => f.extension).join(', ')}',
    );
  }

  /// The name of a file of [format] made [at] (now by default):
  /// `<app>-logs-<yyyyMMdd-HHmmss>.<extension>`.
  String fileName(DebugLogFormat format, [DateTime? at]) {
    final t = at ?? _clock();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return '$appName-logs-$stamp.${format.extension}';
  }

  /// [records] as the bytes of a [format] file, UTF-8: made in slices of
  /// at most [slice], with a turn of the event loop after each.
  Future<Uint8List> encode(
    List<SpringLogRecord> records,
    DebugLogFormat format,
  ) async {
    final bytes = BytesBuilder(copy: false);
    final text = StringBuffer();
    final watch = Stopwatch()..start();
    for (final record in records) {
      text.write(format.format(record));
      if (watch.elapsed >= slice) {
        bytes.add(utf8.encode(text.toString()));
        text.clear();
        await Future<void>.delayed(Duration.zero);
        watch.reset();
      }
    }
    bytes.add(utf8.encode(text.toString()));
    return bytes.takeBytes();
  }

  /// Exports [records] as a [format] file; what to tell the user.
  Future<String> exportRecords(
    List<SpringLogRecord> records,
    DebugLogFormat format,
  ) async {
    final name = fileName(format);
    final bytes = await encode(records, format);
    return files.export(name, bytes, format.mimeType);
  }

  static String _fileSafe(String name) {
    final safe = name
        .trim()
        .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('^[-.]+|-+\$'), '');
    return safe.isEmpty ? 'app' : safe;
  }
}
