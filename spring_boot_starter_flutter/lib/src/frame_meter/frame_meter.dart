import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_layout.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_stats.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/outside_frames.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/theme/frame_meter_theme.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// The corner of the screen the frame meter shows in
/// (`spring.flutter.frame-meter.position`).
@Deprecated('Use DebugCorner')
typedef FrameMeterPosition = DebugCorner;

/// A small panel over [child] with the frames a second the app really
/// draws (with [detailed], the time of their build and raster too), and a
/// bar per frame: green
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
/// included. Frames drawn without Flutter (a 3D scene on a canvas of its
/// own, [OutsideFrames]) show beside them (`60 (120 3D)`). The panel is
/// drawn again at most four times a second ([FrameStats]), and its own
/// frames are not counted, so an idle app shows `idle`, not the
/// meter.
class FrameMeter extends StatelessWidget {
  /// A meter over [child] in the corner [position].
  const FrameMeter({
    required this.child,
    this.position = DebugCorner.topRight,
    this.targetRate = 60,
    this.stages,
    this.detailed = false,
    super.key,
  });

  /// What the meter is over.
  final Widget child;

  /// The corner it shows in.
  final DebugCorner position;

  /// The frames a second the screen is meant to show.
  final int targetRate;

  /// The stages of the start: until the app shows, the meter neither shows
  /// nor counts, so it takes nothing from the splash. `null`: always on.
  final ValueListenable<SplashStage>? stages;

  /// Whether it shows the times of build and raster as well.
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final top =
        position == DebugCorner.topLeft || position == DebugCorner.topRight;
    final left =
        position == DebugCorner.topLeft || position == DebugCorner.bottomLeft;
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
                child: FrameMeterGauge(
                  targetRate: targetRate,
                  stages: stages,
                  detailed: detailed,
                ),
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
///
/// Compact by default: one short line, the frames a second in the
/// theme's primary colour and those drawn without Flutter beside them
/// (`60 (120 3D)`), over a strip with a bar per frame. [detailed] adds the
/// times of build and raster and the worst frame (the debug panel's
/// Frames tab).
class FrameMeterGauge extends StatefulWidget {
  /// The panel, with the budget of [targetRate].
  const FrameMeterGauge({
    this.targetRate = 60,
    this.stages,
    this.detailed = false,
    this.look,
    this.number,
    this.textStyle,
    super.key,
  });

  /// Colours over the theme's `frame-meter` look, each that is set (the
  /// debug theme's, over the debug overlays); `null`: the theme's.
  final FrameMeterTheme? look;

  /// The colour of the rate; `null`: the theme's primary colour.
  final Color? number;

  /// The text's style; `null`: the theme's `frame-meter` text style.
  final TextStyle? textStyle;

  /// The frames a second the screen is meant to show.
  final int targetRate;

  /// The stages of the start: until the app shows, the gauge neither shows
  /// nor counts. `null`: always on.
  final ValueListenable<SplashStage>? stages;

  /// Whether it shows the times as well.
  final bool detailed;

  @override
  State<FrameMeterGauge> createState() => _FrameMeterState();
}

class _FrameMeterState extends State<FrameMeterGauge> {
  late final FrameStats _stats = FrameStats(
    targetRate: widget.targetRate,
    stages: widget.stages,
  )..addListener(_changed);

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _stats
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_stats.reading) {
    null => const SizedBox.shrink(),
    final reading => _Panel(
      reading: reading,
      detailed: widget.detailed,
      over: widget.look,
      number: widget.number,
      textStyle: widget.textStyle,
    ),
  };
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.reading,
    required this.detailed,
    this.over,
    this.number,
    this.textStyle,
  });

  final FrameReading reading;
  final bool detailed;
  final FrameMeterTheme? over;
  final Color? number;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.maybeOf(context);
    final look = theme?.frameMeter;
    final colors = theme?.colorScheme;
    final good =
        over?.good ?? look?.good ?? colors?.primary ?? const Color(0xFF4CAF50);
    final warning =
        over?.warning ??
        look?.warning ??
        colors?.tertiary ??
        const Color(0xFFFFC107);
    final bad =
        over?.bad ?? look?.bad ?? colors?.error ?? const Color(0xFFF44336);
    final foreground =
        over?.foreground ??
        look?.foreground ??
        colors?.onSurface ??
        const Color(0xFFFFFFFF);
    final accent = number ?? colors?.primary ?? const Color(0xFF4FC3F7);
    final background =
        over?.background ??
        look?.background ??
        (colors?.surface ?? const Color(0xFF000000)).withValues(alpha: 0.85);
    final style =
        (textStyle ??
                theme?.textStyle(look?.textStyle ?? 'labelsmall') ??
                const TextStyle(fontSize: 11))
            .copyWith(color: foreground, height: 1.3);
    final budget = reading.budget;

    Color colorOf(int took) => switch (FrameReading.statusOf(took, budget)) {
      FrameStatus.good => good,
      FrameStatus.warning => warning,
      FrameStatus.bad => bad,
    };

    final rate = reading.rate;
    final bars = CustomPaint(
      size: Size(detailed ? 96 : 72, detailed ? 24 : 10),
      painter: _Bars(
        reading.took,
        budget: budget,
        colorOf: colorOf,
        line: foreground.withValues(alpha: 0.4),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: detailed
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: detailed
              ? [
                  Text(
                    reading.idle ? 'idle' : '$rate fps',
                    style: style.copyWith(
                      // Few frames by choice are no fault: the plain color.
                      color: reading.moving
                          ? colorOf(1000000 ~/ rate.clamp(1, 1000))
                          : foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  for (final source in OutsideFrames.all)
                    if (source.recent case final recent?)
                      Text(
                        '${source.name} ${recent.rate} fps · '
                        '${recent.cost.toStringAsFixed(1)} ms',
                        style: style.copyWith(
                          color: colorOf(1000000 ~/ recent.rate.clamp(1, 1000)),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  Text(
                    'build ${reading.build.toStringAsFixed(1)} ms\n'
                    'raster ${reading.raster.toStringAsFixed(1)} ms\n'
                    'worst ${(reading.worst / 1000).toStringAsFixed(0)} ms',
                    style: style,
                  ),
                  const SizedBox(height: 4),
                  bars,
                ]
              : [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: reading.idle ? 'idle' : '$rate',
                          style: TextStyle(
                            color: reading.idle ? foreground : accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        for (final source in OutsideFrames.all)
                          if (source.recent case final recent?)
                            TextSpan(
                              text: ' (${recent.rate} ${source.name})',
                            ),
                      ],
                    ),
                    style: style,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  bars,
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
    final width = size.width / FrameStats.kept;
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
