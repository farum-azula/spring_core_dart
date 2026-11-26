import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A point of a [MemoryChart]: when, the bytes used and what they are
/// measured against (the heap's capacity; `null`: nothing).
typedef MemoryChartPoint = ({DateTime at, int used, int? of});

/// The last [window] of one figure as an area: the bytes used filled in
/// [color], what they are measured against as a faint line above, scaled
/// from a little under the lowest of either to the highest, so a change
/// of a few megabytes shows; the newest at the right edge, what was read
/// so far stretched across the width until it spans the window. A time
/// nothing was read (the tab closed) is a gap.
class MemoryChart extends StatelessWidget {
  /// The chart of [points], oldest first.
  const MemoryChart({
    required this.points,
    required this.window,
    required this.gap,
    required this.color,
    required this.line,
    super.key,
  });

  /// The points, oldest first.
  final List<MemoryChartPoint> points;

  /// How far back the left edge is.
  final Duration window;

  /// The longest time between two points that are joined; a longer one
  /// is a gap.
  final Duration gap;

  /// The area's colour.
  final Color color;

  /// The baseline's colour.
  final Color line;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MemoryChartPainter(points, window, gap, color, line),
    size: Size.infinite,
  );
}

// The span the chart is at least as wide as: what was read so far fills
// it, up to the window.
const _shortest = Duration(seconds: 30);

final class _MemoryChartPainter extends CustomPainter {
  _MemoryChartPainter(
    this.points,
    this.window,
    this.gap,
    this.color,
    this.line,
  );

  final List<MemoryChartPoint> points;
  final Duration window;
  final Duration gap;
  final Color color;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = line,
    );
    if (points.isEmpty) {
      return;
    }
    final end = points.last.at;
    final read = end.difference(points.first.at).inMicroseconds;
    final span = read
        .clamp(_shortest.inMicroseconds, window.inMicroseconds)
        .toDouble();
    var low = points.first.used;
    var high = low;
    for (final point in points) {
      for (final bytes in [point.used, ?point.of]) {
        low = math.min(low, bytes);
        high = math.max(high, bytes);
      }
    }
    final pad = math.max((high - low) * 0.25, high * 0.02);
    final bottom = math.max(0.0, low - pad);
    final range = math.max(1.0, high + pad * 0.3 - bottom);
    double x(DateTime at) =>
        size.width * (1 - end.difference(at).inMicroseconds / span);
    double y(int bytes) => size.height * (1 - (bytes - bottom) / range);

    final area = Path();
    final edge = Path();
    final of = Path();
    MemoryChartPoint? last;
    for (final point in points) {
      final px = x(point.at);
      if (px < 0) {
        continue;
      }
      final broken = last == null || point.at.difference(last.at) > gap;
      if (broken) {
        if (last != null) {
          area.lineTo(x(last.at), size.height);
        }
        area
          ..moveTo(px, size.height)
          ..lineTo(px, y(point.used));
        edge.moveTo(px, y(point.used));
      } else {
        area.lineTo(px, y(point.used));
        edge.lineTo(px, y(point.used));
      }
      if (point.of case final bytes?) {
        broken || last.of == null
            ? of.moveTo(px, y(bytes))
            : of.lineTo(px, y(bytes));
      }
      last = point;
    }
    if (last != null) {
      area.lineTo(x(last.at), size.height);
    }
    canvas
      ..drawPath(area, Paint()..color = color.withValues(alpha: 0.25))
      ..drawPath(
        edge,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      )
      ..drawPath(
        of,
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_MemoryChartPainter old) =>
      old.points != points || old.color != color || old.line != line;
}
