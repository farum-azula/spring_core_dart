import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';

/// Where an entry's bar lies in the Network tab's waterfall, as fractions
/// of the window's width: from [start] to [end], the wait for the first
/// byte (a WebSocket's handshake) until [firstByte] when it is known.
@immutable
final class WaterfallBar {
  /// A bar from [start] to [end].
  const WaterfallBar({
    required this.start,
    required this.end,
    this.firstByte,
    this.inFlight = false,
    this.slow = false,
    this.failed = false,
    this.clipped = false,
  });

  /// Where it begins, `0` to `1`.
  final double start;

  /// Where the first byte arrived (a WebSocket open), between [start] and
  /// [end]; `null` when it is not known.
  final double? firstByte;

  /// Where it ends, `0` to `1`.
  final double end;

  /// Whether it is still going: its end is now.
  final bool inFlight;

  /// Whether it took [NetworkWaterfall.slowAfter] or longer.
  final bool slow;

  /// Whether it failed.
  final bool failed;

  /// Whether it goes on past the window's end (a WebSocket open longer
  /// than the requests around it).
  final bool clipped;

  @override
  bool operator ==(Object other) =>
      other is WaterfallBar &&
      other.start == start &&
      other.firstByte == firstByte &&
      other.end == end &&
      other.inFlight == inFlight &&
      other.slow == slow &&
      other.failed == failed &&
      other.clipped == clipped;

  @override
  int get hashCode =>
      Object.hash(start, firstByte, end, inFlight, slow, failed, clipped);

  @override
  String toString() =>
      'WaterfallBar($start..${firstByte ?? '-'}..$end'
      '${inFlight ? ', in flight' : ''}${slow ? ', slow' : ''}'
      '${failed ? ', failed' : ''}${clipped ? ', clipped' : ''})';
}

/// The Network tab's waterfall: one time scale for the entries shown, so
/// the bars of their rows show which requests overlapped and which were
/// slow. The window runs from the first start to the last end of the HTTP
/// requests (all entries when there is none): a WebSocket open for minutes
/// does not squeeze them, its bar goes on past the end ([WaterfallBar.clipped]).
/// An entry in flight ends at [now].
final class NetworkWaterfall {
  /// The scale of [entries] at [now].
  factory NetworkWaterfall(Iterable<NetworkEntry> entries, DateTime now) {
    final all = entries.toList(growable: false);
    final requests = all.whereType<HttpExchange>().toList(growable: false);
    final scaled = requests.isEmpty ? all : requests;
    if (scaled.isEmpty) {
      return NetworkWaterfall._(now, Duration.zero, now);
    }
    var start = scaled.first.started;
    var end = _end(scaled.first, now);
    for (final entry in scaled.skip(1)) {
      if (entry.started.isBefore(start)) {
        start = entry.started;
      }
      final ends = _end(entry, now);
      if (ends.isAfter(end)) {
        end = ends;
      }
    }
    return NetworkWaterfall._(start, end.difference(start), now);
  }

  NetworkWaterfall._(this.start, this.span, this.now);

  /// A request this long or longer is slow.
  static const slowAfter = Duration(seconds: 1);

  /// The narrowest bar, so an instant request still shows.
  static const minWidth = 0.01;

  /// The window's start.
  final DateTime start;

  /// The window's length.
  final Duration span;

  /// The time an entry in flight ends at.
  final DateTime now;

  static DateTime _end(NetworkEntry entry, DateTime now) =>
      switch (entry.duration) {
        final duration? => entry.started.add(duration),
        null => now.isBefore(entry.started) ? entry.started : now,
      };

  double _at(DateTime time) {
    if (span <= Duration.zero) {
      return 0;
    }
    final fraction =
        time.difference(start).inMicroseconds / span.inMicroseconds;
    return fraction.clamp(0.0, 1.0);
  }

  /// [entry]'s bar on this scale.
  WaterfallBar barOf(NetworkEntry entry) {
    final ends = _end(entry, now);
    final elapsed = ends.difference(entry.started);
    final Duration? firstByte = switch (entry) {
      final HttpExchange exchange => exchange.firstByte,
      final WebSocketConnection connection => connection.connectTime,
    };
    var from = _at(entry.started);
    var to = _at(ends);
    if (to - from < minWidth) {
      to = from + minWidth;
      if (to > 1) {
        to = 1;
        from = 1 - minWidth;
      }
    }
    final mark = firstByte == null
        ? null
        : _at(entry.started.add(firstByte)).clamp(from, to);
    return WaterfallBar(
      start: from,
      firstByte: mark,
      end: to,
      inFlight: !entry.isDone,
      slow: entry is HttpExchange && elapsed >= slowAfter,
      failed: entry.statusClass == NetworkStatusClass.failed,
      clipped: span > Duration.zero && ends.isAfter(start.add(span)),
    );
  }
}

/// Paints a [WaterfallBar] across its width: the wait muted, the rest in
/// the accent ([DebugStyle.warning] when slow, [DebugStyle.bad] when
/// failed), an entry in flight lighter.
class WaterfallBarPainter extends CustomPainter {
  /// Paints [bar] in [style]'s colours.
  WaterfallBarPainter(this.bar, this.style);

  /// The bar.
  final WaterfallBar bar;

  /// The colours.
  final DebugStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final color = bar.failed
        ? style.bad
        : bar.slow
        ? style.warning
        : style.accent;
    final alpha = bar.inFlight ? 0.55 : 1.0;
    final left = bar.start * size.width;
    final right = bar.end * size.width;
    final split = (bar.firstByte ?? bar.start) * size.width;
    final radius = Radius.circular(size.height / 2);
    if (split > left) {
      canvas.drawRRect(
        RRect.fromLTRBR(left, 0, split, size.height, radius),
        Paint()..color = style.muted.withValues(alpha: 0.6 * alpha),
      );
    }
    if (right > split) {
      canvas.drawRRect(
        RRect.fromLTRBR(split, 0, right, size.height, radius),
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(WaterfallBarPainter old) =>
      old.bar != bar || old.style != style;
}
