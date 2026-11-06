import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';
import 'package:spring_boot_starter_flutter/src/theme/loader_tracks.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_loader.dart';

/// Where the phases of a loader are, moved on by time and by progress.
///
/// Phases play in order: an animated phase plays once and the next one
/// starts; a looping phase goes on until the loader is `ready`; a phase
/// that follows progress ends when the progress reaches 1; the last phase
/// of a loader with several waits for `ready`. A phase not yet started is
/// 0, one that is done 1. Internal to the starter; public for tests.
final class LoaderTimeline {
  /// A timeline over [phases], all at 0.
  LoaderTimeline(this.phases)
    : _entries = phases.entries.toList(),
      values = {for (final name in phases.keys) name: 0.0};

  /// The phases in order.
  final Map<String, ThemeLoaderPhase> phases;

  /// The position of each phase by name.
  final Map<String, double> values;

  final List<MapEntry<String, ThemeLoaderPhase>> _entries;
  int _index = 0;
  Duration _inPhase = Duration.zero;
  double _shown = 0;

  /// Whether every phase has ended.
  bool get finished => _index >= _entries.length;

  /// Whether nothing moves any more (every phase ended, progress shown).
  bool settled(double target) => finished && (_shown - target).abs() < 0.001;

  /// Every phase at its end (reduced motion); a phase that follows
  /// progress is at [progress].
  void still(double progress) {
    _shown = progress;
    for (final MapEntry(:key, :value) in _entries) {
      values[key] = value.followsProgress ? progress : 1.0;
    }
    _index = _entries.length;
  }

  /// Starts as if the work was already at [progress]: the animated
  /// phases before the first one that waits (follows progress or loops)
  /// are at their end. For a splash that takes over from the web page's
  /// loader, which has played them.
  ///
  /// With [elapsed] (how long the page loader has run) a phase the page
  /// has not finished is not skipped: it goes on from where the page was,
  /// and a progress phase with a `min-duration` goes on with its clock.
  void resume(double progress, {Duration? elapsed}) {
    _shown = progress.clamp(0.0, 1.0);
    var spent = elapsed;
    while (_index < _entries.length) {
      final MapEntry(:key, :value) = _entries[_index];
      final spec = value.animation;
      final last = _index == _entries.length - 1 && _entries.length > 1;
      if (spec == null || spec.repeat != AnimationRepeat.none || last) {
        // The clock of the fill phase starts when the earlier ones end.
        if (spec == null && spent != null) {
          _inPhase = spent;
        }
        break;
      }
      if (spent != null && spent < spec.duration) {
        _inPhase = spent;
        values[key] = spec.curve.transform(
          _inPhase.inMicroseconds / spec.duration.inMicroseconds,
        );
        return;
      }
      if (spent != null) {
        spent -= spec.duration;
      }
      values[key] = 1;
      _index++;
    }
  }

  /// Whether the last phase of a loader with several is playing: the
  /// loader is on its way out.
  bool get inLastPhase => _entries.length > 1 && _index >= _entries.length - 1;

  // The most a progress phase with a `min-duration` lets show: nothing
  // before it starts, then its clock (eased) over the minimum; `null` when
  // the loader has no such phase ahead or it is over.
  double? _fillCap() {
    for (var i = _index; i < _entries.length; i++) {
      final phase = _entries[i].value;
      if (!phase.followsProgress) {
        continue;
      }
      final min = phase.minDuration;
      if (min <= Duration.zero) {
        return null;
      }
      if (i > _index) {
        return 0;
      }
      return fillEase(
        (_inPhase.inMicroseconds / min.inMicroseconds).clamp(0.0, 1.0),
      );
    }
    return null;
  }

  /// The easing of the `min-duration` clock of a progress phase: cubic ease
  /// in and out (`t < .5 ? 4t³ : 1 - (2 - 2t)³ / 2`), the same as the web
  /// page loader's script, so the hand-off does not jump.
  static double fillEase(double t) {
    if (t < 0.5) {
      return 4 * t * t * t;
    }
    final u = 2 - 2 * t;
    return 1 - u * u * u / 2;
  }

  /// Moves on by [dt]. [progress] is what the loader is given, `null` for
  /// indeterminate; [ready] says the loader may end.
  void advance(Duration dt, {double? progress, required bool ready}) {
    var target = ready ? 1.0 : (progress ?? 0.0).clamp(0.0, 1.0);
    // A progress phase with a minimum time shows no more than its clock
    // allows; the clock runs while the phase is the current one.
    var left = dt;
    if (_index < _entries.length) {
      final phase = _entries[_index].value;
      if (phase.followsProgress && phase.minDuration > Duration.zero) {
        _inPhase += dt;
        left = Duration.zero;
      }
    }
    final cap = _fillCap();
    if (cap != null) {
      target = math.min(target, cap);
    }
    // The shown progress catches up at most a whole run in 300 ms.
    final step = dt.inMicroseconds / 300000;
    _shown = target > _shown
        ? math.min(target, _shown + step)
        : math.max(target, _shown - step);
    while (_index < _entries.length) {
      final MapEntry(:key, :value) = _entries[_index];
      if (_index == _entries.length - 1 && _entries.length > 1 && !ready) {
        return;
      }
      final spec = value.animation;
      if (spec == null) {
        if (value.minDuration > Duration.zero && left > Duration.zero) {
          _inPhase += left;
          left = Duration.zero;
        }
        values[key] = _shown;
        if (_shown < 1) {
          return;
        }
        _inPhase = Duration.zero;
        _index++;
        continue;
      }
      _inPhase += left;
      left = Duration.zero;
      final run = spec.duration;
      if (spec.repeat == AnimationRepeat.none) {
        if (run == Duration.zero || _inPhase >= run) {
          values[key] = 1;
          left = run == Duration.zero ? Duration.zero : _inPhase - run;
          _inPhase = Duration.zero;
          _index++;
          continue;
        }
        values[key] = spec.curve.transform(
          _inPhase.inMicroseconds / run.inMicroseconds,
        );
        return;
      }
      final cycle = run == Duration.zero
          ? 0.0
          : (_inPhase.inMicroseconds % (run.inMicroseconds * 2)) /
                run.inMicroseconds;
      final position = spec.repeat == AnimationRepeat.loop
          ? cycle % 1
          : (cycle <= 1 ? cycle : 2 - cycle);
      values[key] = spec.curve.transform(position);
      if (ready && _index < _entries.length - 1) {
        values[key] = 1;
        _inPhase = Duration.zero;
        _index++;
        continue;
      }
      return;
    }
  }
}

Color _primary(BuildContext context) =>
    SpringTheme.maybeOf(context)?.colorScheme.primary ??
    const Color(0xFF2196F3);

/// Shows a loader of the theme: a built-in kind or one of the app's own.
///
/// Without [progress] the loader is indeterminate (a spinner turns, the
/// phases of a kind of the app's own run until the one that follows
/// progress, and wait there); with it (0 to 1) a bar fills and the phase
/// `{progress: true}` follows it. When the loader is [ready] (by default
/// when [progress] reached 1) its looping phases end and the last phase
/// plays. With the system asking for less motion each phase is at its
/// end, and nothing flickers or shimmers.
///
/// ```dart
/// ThemeLoader(context.theme.loaders.dots)
/// ThemeLoader(context.theme.loaders.upload, progress: sent / total)
/// ```
class ThemeLoader extends StatefulWidget {
  /// Shows [spec]; [size] is the room of a kind of the app's own (it
  /// fills the parent, or 48 by 48 when the parent has no bounds).
  const ThemeLoader(
    this.spec, {
    this.progress,
    this.ready,
    this.size,
    this.onFinished,
    this.onExiting,
    this.resumeFrom,
    this.resumeElapsed,
    this.stages,
    super.key,
  });

  /// The start's stages, for `LoaderFrame.stage` and the tracks that
  /// follow a stage; `null` for a loader that is not the splash's.
  final SplashStages? stages;

  /// The loader to show.
  final ThemeLoaderSpec spec;

  /// How far the work is, from 0 to 1; `null`: indeterminate.
  final double? progress;

  /// Whether the loader may end; `null`: when [progress] is 1.
  final bool? ready;

  /// The size to paint at; `null`: the built-in kind's own size, or the
  /// parent's room.
  final Size? size;

  /// Called once, when every phase has ended.
  final VoidCallback? onFinished;

  /// Called once, when the last phase of a loader with several starts: the
  /// loader is on its way out. The splash uses it to show what is below.
  final VoidCallback? onExiting;

  /// Start as if the work was already this far (0 to 1): the phases that
  /// only play once before the one that follows progress are skipped. The
  /// splash sets it when the web page loader was on screen before it.
  final double? resumeFrom;

  /// How long the loader had already run (the web page loader), so
  /// `LoaderFrame.elapsed` goes on from there: a flicker or a turning edge
  /// does not start over.
  final Duration? resumeElapsed;

  @override
  State<ThemeLoader> createState() => _ThemeLoaderState();
}

class _ThemeLoaderState extends State<ThemeLoader>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late LoaderTimeline _timeline = _newTimeline();
  final _repaint = _Repaint();
  Duration _last = Duration.zero;
  Duration _elapsed = Duration.zero;
  bool _reduce = false;
  bool _notified = false;
  late Object? _props = _makeProps();
  late Map<String, LoaderTrackRun> _runs = _newRuns();
  // The first frame is built before the ticker's first tick.
  late Map<String, double> _tracks = _trackValues(Duration.zero);

  Map<String, LoaderTrackRun> _newRuns() => {
    for (final MapEntry(:key, :value) in widget.spec.tracks.entries)
      key: value.run(),
  };

  void _advanceTracks(Duration dt) {
    if (_runs.isNotEmpty) {
      _tracks = _trackValues(dt);
    }
  }

  Map<String, double> _trackValues(Duration dt) {
    final stages = widget.stages;
    final clock = LoaderClock(
      elapsed: _elapsed,
      dt: dt,
      progress: widget.progress,
      stage: stages?.value,
      since: stages == null
          ? null
          : (stage) => switch (stages.at(stage)) {
              final at? => stages.now - at,
              null => null,
            },
    );
    return {
      for (final MapEntry(:key, :value) in _runs.entries)
        key: value.advance(clock),
    };
  }

  Map<String, double> _stillTracks() => {
    for (final MapEntry(:key, :value) in widget.spec.tracks.entries)
      key: value.still(widget.progress),
  };

  LoaderTimeline _newTimeline() {
    final timeline = LoaderTimeline(widget.spec.phases);
    final from = widget.resumeFrom;
    if (from != null) {
      timeline.resume(from, elapsed: widget.resumeElapsed);
    }
    return timeline;
  }

  bool get _ready =>
      widget.ready ?? (widget.progress != null && widget.progress! >= 1);

  Object? _makeProps() =>
      ThemeLoaderKinds.lookup(widget.spec.kind)?.makeProps(
        widget.spec.values!,
      ) ??
      widget.spec.values;

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    _elapsed += dt;
    _timeline.advance(dt, progress: widget.progress, ready: _ready);
    _advanceTracks(dt);
    _repaint.touch();
    _checkExiting();
    _checkFinished();
    if (_runs.isEmpty && (_timeline.settled(_target) || _barWithProgress)) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  // A bar that is given progress only shows it: nothing moves by itself, so
  // the ticker need not run (a test can settle).
  bool get _barWithProgress =>
      widget.spec.kind == 'bar' &&
      widget.spec.isBuiltIn &&
      widget.progress != null;

  double get _target => _ready ? 1.0 : (widget.progress ?? 0.0).clamp(0.0, 1.0);

  void _checkExiting() {
    if (_timeline.inLastPhase && !_exitingNotified) {
      _exitingNotified = true;
      scheduleMicrotask(() {
        if (mounted) {
          widget.onExiting?.call();
        }
      });
    }
  }

  bool _exitingNotified = false;

  void _checkFinished() {
    if (_timeline.finished && !_notified) {
      _notified = true;
      // Not from a build: the callback may change the state above.
      scheduleMicrotask(() {
        if (mounted) {
          widget.onFinished?.call();
        }
      });
    }
  }

  void _restart() {
    if (_reduce) {
      _ticker.stop();
      _timeline.still(widget.progress ?? 1.0);
      _tracks = _stillTracks();
      _repaint.touch();
      _checkExiting();
      _checkFinished();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce != _reduce || !_started) {
      _reduce = reduce;
      _started = true;
      _restart();
    }
  }

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _elapsed = widget.resumeElapsed ?? Duration.zero;
  }

  @override
  void didUpdateWidget(ThemeLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.spec, oldWidget.spec)) {
      _timeline = _newTimeline();
      _props = _makeProps();
      _runs = _newRuns();
      _tracks = _trackValues(Duration.zero);
      _notified = false;
      _exitingNotified = false;
      _last = Duration.zero;
      if (_ticker.isActive) {
        _ticker.stop();
      }
    }
    _restart();
    if (_reduce) {
      _repaint.touch();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  LoaderFrame<Object?> _frame() => LoaderFrame<Object?>(
    phases: Map.unmodifiable(_timeline.values),
    props: _props,
    values: widget.spec.values!,
    progress: widget.progress,
    reduceMotion: _reduce,
    elapsed: _reduce ? Duration.zero : _elapsed,
    stage: widget.stages?.value,
    tracks: Map.unmodifiable(_tracks),
  );

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final Widget loader;
    if (spec.isBuiltIn) {
      final look = spec.look!;
      final color = look.color ?? _primary(context);
      final painter = _BuiltInPainter(
        spec: spec,
        color: color,
        timeline: _timeline,
        progress: () => widget.progress,
        reduce: () => _reduce,
        repaint: _repaint,
      );
      loader = SizedBox.fromSize(
        size: widget.size ?? _intrinsic(spec.kind, look),
        child: CustomPaint(painter: painter),
      );
    } else {
      final registration = ThemeLoaderKinds.lookup(spec.kind);
      if (registration == null) {
        throw FlutterError(
          "No loader kind '${spec.kind}' is registered "
          '(@ThemeLoaderKind / ThemeLoaderKinds.register).',
        );
      }
      if (registration.paints) {
        loader = LayoutBuilder(
          builder: (context, box) {
            final size =
                widget.size ??
                Size(
                  box.hasBoundedWidth ? box.maxWidth : 48,
                  box.hasBoundedHeight ? box.maxHeight : 48,
                );
            return SizedBox.fromSize(
              size: size,
              child: CustomPaint(
                painter: _KindPainter(registration, _frame, _repaint),
              ),
            );
          },
        );
      } else {
        loader = AnimatedBuilder(
          animation: _repaint,
          builder: (context, _) => registration.build(context, _frame()),
        );
      }
    }
    return Semantics(
      label: 'Loading',
      value: widget.progress == null
          ? null
          : '${(widget.progress! * 100).round()}%',
      child: ExcludeSemantics(child: RepaintBoundary(child: loader)),
    );
  }

  static Size _intrinsic(String kind, BuiltInLoaderLook look) => switch (kind) {
    'spinner' || 'pulse' => Size.square(look.size ?? 24),
    'dots' => () {
      final size = look.size ?? 8;
      final count = look.count ?? 3;
      final gap = look.gap ?? size / 2;
      return Size(count * size + (count - 1) * gap, size);
    }(),
    'bar' => Size(look.width ?? 120, look.height ?? 4),
    _ => Size(160, 16),
  };
}

// Tells the painters to repaint.
class _Repaint extends ChangeNotifier {
  void touch() => notifyListeners();
}

class _KindPainter extends CustomPainter {
  _KindPainter(this.kind, this.frame, Listenable repaint)
    : super(repaint: repaint);

  final LoaderKindRegistration kind;
  final LoaderFrame<Object?> Function() frame;

  @override
  void paint(Canvas canvas, Size size) => kind.paint(canvas, size, frame());

  @override
  bool shouldRepaint(_KindPainter oldDelegate) => true;
}

class _BuiltInPainter extends CustomPainter {
  _BuiltInPainter({
    required this.spec,
    required this.color,
    required this.timeline,
    required this.progress,
    required this.reduce,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ThemeLoaderSpec spec;
  final Color color;
  final LoaderTimeline timeline;
  final double? Function() progress;
  final bool Function() reduce;

  @override
  void paint(Canvas canvas, Size size) {
    final t = timeline.values['main'] ?? 0;
    final look = spec.look!;
    final still = reduce();
    switch (spec.kind) {
      case 'spinner':
        _spinner(canvas, size, look, t, still);
      case 'dots':
        _dots(canvas, size, look, t, still);
      case 'pulse':
        _pulse(canvas, size, t, still);
      case 'bar':
        _bar(canvas, size, look, t, still);
      default:
        _skeleton(canvas, size, look, t, still);
    }
  }

  void _spinner(
    Canvas canvas,
    Size size,
    BuiltInLoaderLook look,
    double t,
    bool still,
  ) {
    final stroke = look.stroke ?? 3;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    if (look.track != null) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = look.track!,
      );
    }
    // The arc grows and shrinks while the whole turns.
    final sweep = still ? math.pi * 1.5 : math.pi * (0.3 + 1.2 * _wave(t));
    final start = still ? -math.pi / 2 : -math.pi / 2 + t * math.pi * 2;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color,
    );
  }

  // 0 to 1 and back over one run.
  static double _wave(double t) => 0.5 - 0.5 * math.cos(t * math.pi * 2);

  void _dots(
    Canvas canvas,
    Size size,
    BuiltInLoaderLook look,
    double t,
    bool still,
  ) {
    final dot = look.size ?? 8;
    final count = look.count ?? 3;
    final gap = look.gap ?? dot / 2;
    for (var i = 0; i < count; i++) {
      final lift = still ? 1.0 : _wave((t - i / (count * 2)) % 1);
      final scale = still ? 1.0 : 0.6 + 0.4 * lift;
      final alpha = still ? 1.0 : 0.35 + 0.65 * lift;
      canvas.drawCircle(
        Offset(i * (dot + gap) + dot / 2, size.height / 2),
        dot / 2 * scale,
        Paint()..color = color.withValues(alpha: color.a * alpha),
      );
    }
  }

  void _pulse(Canvas canvas, Size size, double t, bool still) {
    final radius = size.shortestSide / 2;
    final scale = still ? 1.0 : 0.5 + 0.5 * t;
    final alpha = still ? 1.0 : 1 - 0.7 * t;
    canvas.drawCircle(
      size.center(Offset.zero),
      radius * scale,
      Paint()..color = color.withValues(alpha: color.a * alpha),
    );
  }

  void _bar(
    Canvas canvas,
    Size size,
    BuiltInLoaderLook look,
    double t,
    bool still,
  ) {
    final radius = Radius.circular(look.radius ?? size.height / 2);
    final track = look.track ?? color.withValues(alpha: color.a * 0.2);
    final all = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(all, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(all);
    final value = progress();
    final Rect fill;
    if (value != null) {
      fill = Rect.fromLTWH(0, 0, size.width * value.clamp(0, 1), size.height);
    } else if (still) {
      fill = Rect.fromLTWH(0, 0, size.width * 0.4, size.height);
    } else {
      final length = size.width * 0.4;
      final x = -length + (size.width + length) * t;
      fill = Rect.fromLTWH(x, 0, length, size.height);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, radius),
      Paint()..color = color,
    );
    canvas.restore();
  }

  void _skeleton(
    Canvas canvas,
    Size size,
    BuiltInLoaderLook look,
    double t,
    bool still,
  ) {
    final base = look.base ?? const Color(0xFFE0E0E0);
    final highlight = look.highlight ?? const Color(0xFFF5F5F5);
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(look.radius ?? 8),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = still
            ? null
            : skeletonGradient(
                base,
                highlight,
                look.angle ?? 20,
                t,
              ).createShader(Offset.zero & size)
        ..color = base,
    );
  }

  @override
  bool shouldRepaint(_BuiltInPainter oldDelegate) => true;
}

/// The skeleton's gradient: [base] with a band of [highlight] that is at
/// [t] (0 to 1) of its way across, slanted by [angle] degrees.
LinearGradient skeletonGradient(
  Color base,
  Color highlight,
  double angle,
  double t,
) {
  final center = -0.25 + 1.5 * t;
  double stop(double v) => v.clamp(0.0, 1.0);
  return LinearGradient(
    colors: [base, highlight, base],
    stops: [stop(center - 0.2), stop(center), stop(center + 0.2)],
    transform: GradientRotation(angle * math.pi / 180),
  );
}

/// The content, or while [loading] a skeleton of it: [placeholder] (or
/// [child]) painted in the loader's base color with its highlight moving
/// across, so the shape of the content shows before it is there.
///
/// ```dart
/// ThemeSkeleton(
///   context.theme.loaders.card,
///   loading: !book.hasLoaded,
///   placeholder: const BookTilePlaceholder(),
///   child: BookTile(book),
/// )
/// ```
///
/// While loading the content is hidden from taps and screen readers (the
/// skeleton says "Loading"). With the system asking for less motion the
/// skeleton stands still in the base color, with no shimmer.
class ThemeSkeleton extends StatelessWidget {
  /// Shows [child] when not [loading]; else [placeholder], or [child] if
  /// there is none, or a block of the loader's size when neither is
  /// given.
  const ThemeSkeleton(
    this.spec, {
    this.loading = true,
    this.child,
    this.placeholder,
    super.key,
  });

  /// The loader of kind `skeleton` that gives the look.
  final ThemeLoaderSpec spec;

  /// Whether to show the skeleton.
  final bool loading;

  /// The content.
  final Widget? child;

  /// What takes the content's place while loading; its shape is shown.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    if (!loading) {
      return child ?? const SizedBox.shrink();
    }
    final look = spec.look ?? const BuiltInLoaderLook();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final base = look.base ?? const Color(0xFFE0E0E0);
    final highlight = look.highlight ?? const Color(0xFFF5F5F5);
    final shape =
        placeholder ??
        child ??
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(look.radius ?? 8),
          ),
          child: const SizedBox(width: double.infinity, height: 16),
        );
    Widget masked(Animation<double>? t) => AnimatedBuilder(
      animation: t ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, _) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => still
            ? LinearGradient(colors: [base, base]).createShader(bounds)
            : skeletonGradient(
                base,
                highlight,
                look.angle ?? 20,
                t!.value,
              ).createShader(bounds),
        child: IgnorePointer(child: shape),
      ),
    );
    final animation =
        spec.animation ?? ThemeLoaderSpec.builtIn('skeleton').animation!;
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: still
            ? masked(null)
            : ThemeAnimation(animation, builder: (context, t) => masked(t)),
      ),
    );
  }
}
