import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A tiny chart of [values]: a line, or bars with [bars]; the largest
/// reaches the top.
class TimelineSparkline extends StatelessWidget {
  /// A chart of [values] in [color].
  const TimelineSparkline(
    this.values, {
    required this.color,
    this.bars = false,
    super.key,
  });

  /// The values, the oldest first.
  final List<double> values;

  /// The line's or the bars' color.
  final Color color;

  /// Whether it draws bars rather than a line.
  final bool bars;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SparklinePainter(values, color, bars: bars),
    size: Size.infinite,
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color, {required this.bars});

  final List<double> values;
  final Color color;
  final bool bars;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }
    final top = values.reduce(math.max);
    double y(double value) =>
        size.height - (top <= 0 ? 0 : value / top * size.height);
    final paint = Paint()..color = color;
    if (bars) {
      final width = size.width / values.length;
      for (final (i, value) in values.indexed) {
        canvas.drawRect(
          Rect.fromLTRB(
            i * width + width * 0.15,
            math.min(y(value), size.height - 1),
            (i + 1) * width - width * 0.15,
            size.height,
          ),
          paint,
        );
      }
      return;
    }
    if (values.length == 1) {
      canvas.drawCircle(Offset(size.width, y(values.single)), 1.5, paint);
      return;
    }
    final step = size.width / (values.length - 1);
    final path = Path()..moveTo(0, y(values.first));
    for (final (i, value) in values.indexed.skip(1)) {
      path.lineTo(i * step, y(value));
    }
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || old.bars != bars || !_same(old.values, values);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// [duration] for a person: `840ms`, `3.2s`.
String formatTimelineDuration(Duration? duration) {
  if (duration == null) {
    return '…';
  }
  final ms = duration.inMicroseconds / 1000;
  if (ms >= 1000) {
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }
  if (ms >= 10) {
    return '${ms.round()}ms';
  }
  return '${ms.toStringAsFixed(1)}ms';
}
