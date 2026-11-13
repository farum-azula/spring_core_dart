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
///
/// A frame is late only when the app was waiting for it. While something
/// moves at every frame (a scroll, a ticker) each frame is asked for as
/// the one before ends, and the time between them is what is measured:
/// 20 a second there is red. An animation that asks for a frame now and
/// then (a slow drift drawn 15 times a second, a clock) draws few frames
/// because it wants few: the meter says how many, in its plain color, and
/// measures each by what it cost to build and raster.
/// `SpringApp` puts one over the app with
/// `spring.flutter.frame-meter.enabled`; its look is the theme's
/// `frame-meter`.
///
/// The times are Flutter's own (`FrameTiming`), on every platform the web
/// included. The panel is drawn again at most four times a second, and
/// its own frames are not counted, so an idle app shows `idle`, not the
/// meter.
class FrameMeter extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final top =
        position == FrameMeterPosition.topLeft ||
        position == FrameMeterPosition.topRight;
    final left =
        position == FrameMeterPosition.topLeft ||
        position == FrameMeterPosition.bottomLeft;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        Positioned(
          top: top ? 0 : null,
          bottom: top ? null : 0,
          left: left ? 0 : null,
          right: left ? null : 0,
          child: IgnorePointer(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: FrameMeterGauge(targetRate: targetRate, stages: stages),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The meter's panel alone, measuring the frames while it is shown: what
/// [FrameMeter] puts in a corner, and what the debug overlays stack with
/// the others. Nothing until the app shows ([stages]).
class FrameMeterGauge extends StatefulWidget {
  /// The panel, with the budget of [targetRate].
  const FrameMeterGauge({this.targetRate = 60, this.stages, super.key});

  /// The frames a second the screen is meant to show.
  final int targetRate;

  /// The stages of the start: until the app shows, the gauge neither shows
  /// nor counts. `null`: always on.
  final ValueListenable<SplashStage>? stages;

  @override
  State<FrameMeterGauge> createState() => _FrameMeterState();
}

// One frame of the app: when it started, how long after the one before,
// how long its build and raster took, and whether the app was waiting
// for it (the frame before ended with this one already asked for).
typedef _Frame = ({
  int start,
  int interval,
  int build,
  int raster,
  bool awaited,
});

extension on _Frame {
  // How long the frame took to come once it was wanted: the time since
  // the frame before when the app was waiting for it, else its own work.
  int get took => awaited && interval > 0 ? interval : build + raster;
}

class _FrameMeterState extends State<FrameMeterGauge> {
  static const _shown = 48;
  static const _window = Duration(seconds: 1);
  static const _pause = 250000;

  final _frames = ListQueue<_Frame>();
  // For each frame that ended, in order: whether it was drawn for the
  // meter alone, and whether the next one was asked for already. Reports
  // of frames come later, in batches.
  final _ends = ListQueue<({bool own, bool next})>();
  bool _awaited = false;
  int? _lastStart;
  // The frame to come is the meter's own: nothing else had asked for one
  // when the meter asked to be drawn again.
  bool _mine = false;
  bool _fresh = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _watch();
    widget.stages?.addListener(_stageChanged);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_fresh && mounted) {
        _fresh = false;
        // A frame that is coming anyway carries the meter with it, and
        // stays the app's.
        _mine = !SchedulerBinding.instance.hasScheduledFrame;
        setState(() {});
      }
    });
  }

  // Notes, as each frame ends, whether the app has asked for the next:
  // a callback after the frame that puts itself back, and asks for no
  // frame itself.
  void _watch() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _ends.addLast((
        own: _mine,
        next: SchedulerBinding.instance.hasScheduledFrame,
      ));
      _mine = false;
      // Frames nobody reported (the reports stopped): not kept for ever.
      while (_ends.length > 600) {
        _ends.removeFirst();
      }
      _watch();
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
      final end = _ends.isEmpty ? null : _ends.removeFirst();
      // What the frame before left: this one asked for, or not.
      final awaited = _awaited;
      _awaited = end?.next ?? false;
      // The meter's own repaint: not the app's, and not a frame between
      // two of the app's either (the time between those runs across it).
      if (end?.own ?? false) {
        continue;
      }
      final last = _lastStart;
      _lastStart = start;
      _frames.addLast((
        start: start,
        // The first frame after a pause starts anew: the pause is no
        // frame. A frame the app was waiting for is late however long.
        interval: last == null || (!awaited && start - last > _pause)
            ? 0
            : start - last,
        build: timing.buildDuration.inMicroseconds,
        raster: timing.rasterDuration.inMicroseconds,
        awaited: awaited,
      ));
      _fresh = true;
    }
    while (_frames.length > _shown) {
      _frames.removeFirst();
    }
  }

  @override
  Widget build(BuildContext context) => !_started
      ? const SizedBox.shrink()
      : _Panel(
          frames: _frames.toList(),
          budget: 1000000 ~/ widget.targetRate,
          window: _window.inMicroseconds,
        );
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

    Color colorOf(int took) => took <= budget * 1.2
        ? good
        : took <= budget * 2
        ? warning
        : bad;

    final last = frames.isEmpty ? null : frames.last.start;
    final recent = [
      for (final frame in frames)
        if (last != null && last - frame.start < window) frame,
    ];
    // The time between the frames the app was waiting for: it moves at
    // every frame there, and a longer time is a late frame.
    final moving = <int>[
      for (final frame in recent)
        if (frame.awaited && frame.interval > 0) frame.interval,
    ];
    // Without any, the frames it drew because something asked for one now
    // and then: few by choice, not late.
    final paced = <int>[
      if (moving.isEmpty)
        for (final (i, frame) in recent.indexed)
          if (i > 0 && frame.interval > 0) frame.interval,
    ];
    final between = moving.isEmpty ? paced : moving;
    final idle = between.isEmpty;
    final rate = idle
        ? 0
        : (between.length * 1e6 / between.reduce((a, b) => a + b)).round();
    double average(int Function(_Frame) of) => recent.isEmpty
        ? 0
        : recent.map(of).reduce((a, b) => a + b) / recent.length / 1000;
    final worst = recent.isEmpty
        ? 0
        : recent.map((frame) => frame.took).reduce((a, b) => a > b ? a : b);

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
                // Few frames by choice are no fault: the plain color.
                color: moving.isEmpty
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
                [for (final frame in frames) frame.took],
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

// A bar per frame, its height the time the frame took to come once it
// was wanted; the line is the budget.
class _Bars extends CustomPainter {
  _Bars(
    this.took, {
    required this.budget,
    required this.colorOf,
    required this.line,
  });

  final List<int> took;
  final int budget;
  final Color Function(int took) colorOf;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final top = budget * 3;
    final width = size.width / _FrameMeterState._shown;
    for (final (i, time) in took.indexed) {
      if (time == 0) {
        continue;
      }
      final height = size.height * (time.clamp(0, top) / top);
      canvas.drawRect(
        Rect.fromLTWH(
          i * width,
          size.height - height,
          (width - 1).clamp(1, width),
          height,
        ),
        Paint()..color = colorOf(time),
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
