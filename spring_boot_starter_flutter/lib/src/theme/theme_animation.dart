import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// What an animation does when it reaches its end.
enum AnimationRepeat {
  /// Plays once and stays at the end.
  none,

  /// Starts again from the beginning, forever.
  loop,

  /// Plays back and forth, forever.
  reverse,
}

/// One `animations.<name>` of the theme: how long it takes, with which
/// curve, and whether it repeats.
///
/// ```yaml
/// animations:
///   border-spin: { duration: 4s, curve: linear, repeat: loop }
/// ```
///
/// Play it with [ThemeAnimation].
@immutable
final class AnimationSpec {
  /// An animation of [duration] along [curve], repeating as [repeat].
  const AnimationSpec({
    required this.duration,
    this.curve = Curves.linear,
    this.repeat = AnimationRepeat.none,
  });

  /// Reads `animations.<name>` of [p]; throws a [ThemePropertyException]
  /// for a missing duration, a wrong value or an unknown key.
  factory AnimationSpec.parse(ThemeProperties p, String name) =>
      AnimationSpec.parseAt(p, 'animations.$name');

  /// Reads the animation written at [base] of [p] (a loader's phase has
  /// the same keys); errors are those of [AnimationSpec.parse].
  factory AnimationSpec.parseAt(ThemeProperties p, String base) {
    const keys = ['duration', 'curve', 'repeat'];
    for (final key in p.children(base)) {
      if (!keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          p['$base.$key'] ?? '',
          'duration, curve or repeat${didYouMean(key, keys)}',
        );
      }
    }
    final duration = p.read(
      '$base.duration',
      ThemeValues.duration,
      'a duration like 4s or 250ms',
    );
    if (duration == null) {
      throw ThemePropertyException(
        p.propertyName('$base.duration'),
        '',
        'a duration like 4s or 250ms (every animation has one)',
      );
    }
    return AnimationSpec(
      duration: duration,
      curve:
          p.read(
            '$base.curve',
            ThemeValues.anyCurve,
            'a curve: ${ThemeValues.curveNames.join(', ')}, or four numbers',
          ) ??
          Curves.linear,
      repeat:
          p.read(
            '$base.repeat',
            (v) => ThemeValues.enumValue(AnimationRepeat.values, v),
            'none, loop or reverse',
          ) ??
          AnimationRepeat.none,
    );
  }

  /// The time of one run.
  final Duration duration;

  /// The curve of the run.
  final Curve curve;

  /// What happens at the end of a run.
  final AnimationRepeat repeat;

  @override
  bool operator ==(Object other) =>
      other is AnimationSpec &&
      other.duration == duration &&
      other.curve == curve &&
      other.repeat == repeat;

  @override
  int get hashCode => Object.hash(duration, curve, repeat);
}

/// Plays an [AnimationSpec] of the theme and gives its progress, from 0 to
/// 1 along the spec's curve, to [builder].
///
/// It owns the controller: plays once, loops or goes back and forth as
/// the spec says, takes a new duration, curve or repeat when the spec
/// changes (a theme switch), and disposes. When the system asks for less
/// motion (`MediaQuery.disableAnimations`) a one-shot animation jumps to its end (1), a loop or back
/// and forth stands still at 0.
///
/// ```dart
/// ThemeAnimation(
///   context.theme.animations.borderSpin,
///   builder: (context, t) => Transform.rotate(angle: t.value * 2 * pi, child: ring),
/// )
/// ```
class ThemeAnimation extends StatefulWidget {
  /// Plays [spec] and builds with its progress.
  const ThemeAnimation(this.spec, {required this.builder, super.key});

  /// What to play.
  final AnimationSpec spec;

  /// Builds the child from the animation, whose value follows the curve.
  final Widget Function(BuildContext context, Animation<double> animation)
  builder;

  @override
  State<ThemeAnimation> createState() => _ThemeAnimationState();
}

class _ThemeAnimationState extends State<ThemeAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.spec.duration,
  );
  late Animation<double> _animation = _curved(widget.spec.curve);
  bool? _still;

  Animation<double> _curved(Curve curve) =>
      CurveTween(curve: curve).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still != _still) {
      _still = still;
      _play();
    }
  }

  @override
  void didUpdateWidget(ThemeAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final spec = widget.spec;
    if (spec.curve != oldWidget.spec.curve) {
      _animation = _curved(spec.curve);
    }
    if (spec.duration != oldWidget.spec.duration ||
        spec.repeat != oldWidget.spec.repeat) {
      _controller.duration = spec.duration;
      _play();
    }
  }

  bool get _repeats => widget.spec.repeat != AnimationRepeat.none;

  void _play() {
    final spec = widget.spec;
    if (_still ?? false) {
      _controller
        ..stop()
        // A one-shot goes to its end; a loop stands still at the start.
        ..value = _repeats ? 0 : 1;
    } else if (spec.duration == Duration.zero) {
      _controller
        ..stop()
        ..value = _repeats ? 0 : 1;
    } else {
      switch (spec.repeat) {
        case AnimationRepeat.none:
          _controller.forward(from: 0);
        case AnimationRepeat.loop:
          _controller.repeat();
        case AnimationRepeat.reverse:
          _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _animation);
}

/// The kinds of `motion.page-transition`: how a router's screens come in
/// and go out.
enum PageTransitionType {
  /// The app type's own: Material's per platform in a `MaterialApp`, the
  /// iOS slide in a `CupertinoApp`, none in a `WidgetsApp`.
  platform,

  /// Material's fade with an upward slide.
  fadeUpwards,

  /// Material's zoom.
  zoom,

  /// The iOS slide, in any app type.
  cupertino,

  /// A fade.
  fade,

  /// None: the screen shows at once.
  none,
}

/// The theme's page transition, `motion.page-transition`: a kind alone,
/// or a kind with its duration and curve. None when not set: screens show
/// at once unless the theme (or the screen) asks for a transition.
///
/// ```yaml
/// motion:
///   page-transition: platform             # the app type's own
/// # or
/// motion:
///   page-transition: { type: fade, duration: $motion.durations.fast, curve: ease-out }
/// ```
///
/// The navigation starter's router follows it for every app type; a
/// screen may choose its own (`@ScreenRoute(transition: ...)`). Reduced
/// motion on the device makes every transition instant.
@immutable
final class PageTransitionSpec {
  /// A transition of [type], [duration] and [curve] (`null`: the kind's
  /// own). None by default.
  const PageTransitionSpec({
    this.type = PageTransitionType.none,
    this.duration,
    this.curve,
  });

  /// Reads the transition written at [base] of [p] (a kind, or a map of
  /// `type`, `duration` and `curve`); `null` when nothing is written.
  /// Throws a [ThemePropertyException] for a wrong value or key.
  static PageTransitionSpec? parseAt(ThemeProperties p, String base) {
    const kinds = 'platform, fadeUpwards, zoom, cupertino, fade or none';
    PageTransitionType? kind(String value) =>
        ThemeValues.enumValue(PageTransitionType.values, value);
    final children = p.children(base);
    if (children.isEmpty) {
      final type = p.read(base, kind, kinds);
      return type == null ? null : PageTransitionSpec(type: type);
    }
    const keys = ['type', 'duration', 'curve'];
    for (final key in children) {
      if (!keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          p['$base.$key'] ?? '',
          'type, duration or curve${didYouMean(key, keys)}',
        );
      }
    }
    return PageTransitionSpec(
      type: p.read('$base.type', kind, kinds) ?? PageTransitionType.none,
      duration: p.read(
        '$base.duration',
        ThemeValues.duration,
        'a duration like 250ms',
      ),
      curve: p.read(
        '$base.curve',
        ThemeValues.anyCurve,
        'a curve: ${ThemeValues.curveNames.join(', ')}, or four numbers',
      ),
    );
  }

  /// The kind of transition.
  final PageTransitionType type;

  /// How long it takes, or `null` for the kind's own.
  final Duration? duration;

  /// The curve of the animation, or `null` for the kind's own.
  final Curve? curve;

  @override
  bool operator ==(Object other) =>
      other is PageTransitionSpec &&
      other.type == type &&
      other.duration == duration &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(type, duration, curve);
}
