import 'dart:ui' show Color;

import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';

/// How the network views write and colour an entry's values, shared by the
/// Network tab and a compact view.
abstract final class NetworkFormat {
  /// The methods that only read.
  static const readMethods = {'GET', 'HEAD', 'OPTIONS', 'TRACE'};

  /// [bytes] as `512 B`, `1.2 KB`, `3.4 MB`.
  static String bytes(int bytes) => switch (bytes) {
    < 1024 => '$bytes B',
    < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
    _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
  };

  /// [duration] as `85 ms` or `1.25 s`; `…` when `null`.
  static String duration(Duration? duration) => switch (duration) {
    null => '…',
    final d when d.inMilliseconds < 1000 => '${d.inMilliseconds} ms',
    final d => '${(d.inMilliseconds / 1000).toStringAsFixed(2)} s',
  };

  /// [duration] as an uptime: `45 s`, `3 m 12 s`, `2 h 05 m`; `…` when
  /// `null`.
  static String uptime(Duration? duration) {
    if (duration == null) {
      return '…';
    }
    final seconds = duration.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return switch (seconds) {
      < 60 => '$seconds s',
      < 3600 => '${seconds ~/ 60} m ${two(seconds % 60)} s',
      _ => '${seconds ~/ 3600} h ${two(seconds % 3600 ~/ 60)} m',
    };
  }

  /// [time] as a clock: `14:03:27.415`.
  static String clock(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  /// The colour of [method]:[DebugStyle.methodRead] for the methods that
  /// read, [DebugStyle.methodWrite] for the others, the accent for a
  /// WebSocket.
  static Color method(String method, DebugStyle style) => method == 'WS'
      ? style.accent
      : readMethods.contains(method)
      ? style.methodRead
      : style.methodWrite;

  /// The colour of [status]: good, warning or bad; muted while pending.
  static Color status(NetworkStatusClass status, DebugStyle style) =>
      switch (status) {
        NetworkStatusClass.pending => style.muted,
        NetworkStatusClass.informational ||
        NetworkStatusClass.success ||
        NetworkStatusClass.redirect => style.good,
        NetworkStatusClass.clientError => style.warning,
        NetworkStatusClass.serverError ||
        NetworkStatusClass.failed => style.bad,
      };

  /// [entry]'s address as a row shows it: the path and the query, or the
  /// whole address when it has no path.
  static String path(NetworkEntry entry) {
    final url = entry.url;
    final path = url.path.isEmpty ? '/' : url.path;
    return url.hasQuery ? '$path?${url.query}' : path;
  }
}
