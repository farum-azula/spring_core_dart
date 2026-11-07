import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// The corner of the screen the frame meter shows in
/// (`spring.flutter.frame-meter.position`).
enum FrameMeterPosition {
  /// Top left.
  topLeft,

  /// Top right.
  topRight,

  /// Bottom left.
  bottomLeft,

  /// Bottom right.
  bottomRight,
}

/// A small panel over [child] with the frames a second the app really
/// draws, the time of their build and raster, and a bar per frame: green
/// within the budget of [targetRate], yellow up to twice it, red over.
/// `SpringApp` puts one over the app with
/// `spring.flutter.frame-meter.enabled`; its look is the theme's
/// `frame-meter`.
///
/// The times are Flutter's own (`FrameTiming`), on every platform the web
/// included. The panel is drawn again at most four times a second, and
/// its own frames are not counted, so an idle app shows `idle`, not the
/// meter.
class FrameMeter extends StatefulWidget {
  /// A meter over [child] in the corner [position].
  const FrameMeter({
    required this.child,
    this.position = FrameMeterPosition.topRight,
    this.targetRate = 60,
    this.stages,
    super.key,
  });

  /// What the meter is over.
  final Widget child;

  /// The corner it shows in.
  final FrameMeterPosition position;

  /// The frames a second the screen is meant to show.
  final int targetRate;

  /// The stages of the start: until the app shows, the meter neither shows
  /// nor counts, so it takes nothing from the splash. `null`: always on.
  final ValueListenable<SplashStage>? stages;

  @override
  State<FrameMeter> createState() => _FrameMeterState();
}

// One frame of the app: when it started, how long its build and raster
// took.
typedef _Frame = ({int start, int interval, int build, int raster});

class _FrameMeterState extends State<FrameMeter> {
  static const _shown = 48;
  static const _window = Duration(seconds: 1);
  static const _pause = 250000;

  final _frames = ListQueue<_Frame>();
  int? _lastStart;
  // Frames of the meter itself still to come in a report.
  int _own = 0;
  bool _fresh = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    widget.stages?.addListener(_stageChanged);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_fresh && mounted) {
        _fresh = false;
        _own++;
        setState(() {});
      }
    });
  }

  void _stageChanged() {
    if (_started && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.stages?.removeListener(_stageChanged);
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }

  bool get _started =>
      widget.stages == null || widget.stages!.value == SplashStage.app;

  void _timings(List<FrameTiming> timings) {
    if (!_started) {
      return;
    }
    for (final timing in timings) {
      final start = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final last = _lastStart;
      _lastStart = start;
      // The meter's own repaint: not the app's.
      if (_own > 0) {
        _own--;
        continue;
      }
      _frames.addLast((
        start: start,
        // The first frame after a pause starts anew: the pause is no frame.
        interval: last == null || start - last > _pause ? 0 : start - last,
        build: timing.buildDuration.inMicroseconds,
        raster: timing.rasterDuration.inMicroseconds,
      ));
      _fresh = true;
    }
    while (_frames.length > _shown) {
      _frames.removeFirst();
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    final top =
        position == FrameMeterPosition.topLeft ||
        position == FrameMeterPosition.topRight;
    final left =
        position == FrameMeterPosition.topLeft ||
        position == FrameMeterPosition.bottomLeft;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_started)
          Positioned(
            top: top ? 0 : null,
            bottom: top ? null : 0,
            left: left ? 0 : null,
            right: left ? null : 0,
            child: IgnorePointer(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _Panel(
                    frames: _frames.toList(),
                    budget: 1000000 ~/ widget.targetRate,
                    window: _window.inMicroseconds,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.frames,
    required this.budget,
    required this.window,
  });

  final List<_Frame> frames;
  final int budget;
  final int window;

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.maybeOf(context);
    final look = theme?.frameMeter;
    final colors = theme?.colorScheme;
    final good = look?.good ?? colors?.primary ?? const Color(0xFF4CAF50);
    final warning =
        look?.warning ?? colors?.tertiary ?? const Color(0xFFFFC107);
    final bad = look?.bad ?? colors?.error ?? const Color(0xFFF44336);
    final foreground =
        look?.foreground ?? colors?.onSurface ?? const Color(0xFFFFFFFF);
    final background =
        look?.background ??
        (colors?.surface ?? const Color(0xFF000000)).withValues(alpha: 0.85);
    final style =
        (theme?.textStyle(look?.textStyle ?? 'labelsmall') ??
                const TextStyle(fontSize: 11))
            .copyWith(color: foreground, height: 1.3);

    Color colorOf(int interval) => interval <= budget * 1.2
        ? good
        : interval <= budget * 2
        ? warning
        : bad;

    final last = frames.isEmpty ? null : frames.last.start;
    final recent = [
      for (final frame in frames)
        if (last != null && last - frame.start < window) frame,
    ];
    final idle = recent.length < 2;
    final rate = idle
        ? 0
        : ((recent.length - 1) * 1e6 / (recent.last.start - recent.first.start))
              .round();
    double average(int Function(_Frame) of) => recent.isEmpty
        ? 0
        : recent.map(of).reduce((a, b) => a + b) / recent.length / 1000;
    final worst = recent.isEmpty
        ? 0
        : recent.map((f) => f.interval).reduce((a, b) => a > b ? a : b);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              idle ? 'idle' : '$rate fps',
              style: style.copyWith(
                color: idle
                    ? foreground
                    : colorOf(1000000 ~/ rate.clamp(1, 1000)),
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'build ${average((f) => f.build).toStringAsFixed(1)} ms\n'
              'raster ${average((f) => f.raster).toStringAsFixed(1)} ms\n'
              'worst ${(worst / 1000).toStringAsFixed(0)} ms',
              style: style,
            ),
            const SizedBox(height: 4),
            CustomPaint(
              size: const Size(96, 24),
              painter: _Bars(
                [for (final frame in frames) frame.interval],
                budget: budget,
                colorOf: colorOf,
                line: foreground.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A bar per frame, its height the time since the frame before; the line
// is the budget.
class _Bars extends CustomPainter {
  _Bars(
    this.intervals, {
    required this.budget,
    required this.colorOf,
    required this.line,
  });

  final List<int> intervals;
  final int budget;
  final Color Function(int interval) colorOf;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final top = budget * 3;
    final width = size.width / _FrameMeterState._shown;
    for (final (i, interval) in intervals.indexed) {
      if (interval == 0) {
        continue;
      }
      final height = size.height * (interval.clamp(0, top) / top);
      canvas.drawRect(
        Rect.fromLTWH(
          i * width,
          size.height - height,
          (width - 1).clamp(1, width),
          height,
        ),
        Paint()..color = colorOf(interval),
      );
    }
    final y = size.height * (1 - budget / top);
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = line
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_Bars old) => true;
}
