import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart' show Simulation;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show ScrollMetrics, ScrollPhysics;
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// How a mouse wheel scrolls, `motion.wheel-scroll`: at once by the
/// wheel's step (`none`, Flutter's own), or eased over [duration] and
/// scaled by [speed]; with [inertia], each kind of pointer its own, off by
/// default:
///
/// - `mouse`: quick steps of the wheel one after another go further each
///   and glide longer, as a wheel spun fast does elsewhere;
/// - `trackpad`: when the fingers stop, the page glides on (a trackpad
///   whose system does not, such as many on Windows and Linux; macOS
///   glides by itself);
/// - `touch`: a flick of the finger throws the page further.
///
/// ```yaml
/// motion:
///   wheel-scroll: { duration: 250ms, speed: 0.8, inertia: { mouse: 0.2 } }
/// ```
final class WheelScrollSpec {
  /// A wheel that moves [speed] times its step over [duration].
  const WheelScrollSpec({
    this.duration = Duration.zero,
    this.speed = 1,
    this.inertia = ScrollInertia.none,
  });

  /// Flutter's own: the step at once.
  static const none = WheelScrollSpec();

  /// Reads the spec at [base] of [p]; [none] when nothing is written.
  static WheelScrollSpec parseAt(ThemeProperties p, String base) {
    final kind = p[base];
    if (kind != null) {
      if (ThemeValues.canonical(kind) == 'none') {
        return none;
      }
      throw ThemePropertyException(
        p.propertyName(base),
        kind,
        'none, or a map of duration, speed and inertia',
      );
    }
    final children = p.children(base);
    if (children.isEmpty) {
      return none;
    }
    const keys = ['duration', 'speed', 'inertia'];
    for (final key in children) {
      if (!keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          p['$base.$key'] ?? '',
          'duration, speed or inertia${didYouMean(key, keys)}',
        );
      }
    }
    return WheelScrollSpec(
      duration:
          p.read(
            '$base.duration',
            ThemeValues.duration,
            'a duration like 250ms',
          ) ??
          const Duration(milliseconds: 250),
      speed:
          p.read(
            '$base.speed',
            (v) => switch (ThemeValues.number(v)) {
              final n? when n > 0 => n,
              _ => null,
            },
            'a number over zero (1 is the wheel step)',
          ) ??
          1,
      inertia: ScrollInertia.parseAt(p, '$base.inertia'),
    );
  }

  /// How long a step takes to arrive; zero for at once.
  final Duration duration;

  /// The step's share: below 1 slower, above faster.
  final double speed;

  /// The inertia of each kind of pointer; [ScrollInertia.none] by
  /// default.
  final ScrollInertia inertia;

  /// Whether the wheel scrolls as Flutter does by itself.
  bool get isNone =>
      duration == Duration.zero && speed == 1 && inertia.mouse == 0;

  @override
  bool operator ==(Object other) =>
      other is WheelScrollSpec &&
      other.duration == duration &&
      other.speed == speed &&
      other.inertia == inertia;

  @override
  int get hashCode => Object.hash(duration, speed, inertia);
}

/// Eases the wheel's scroll signals for every scrollable of the app: a
/// step of the wheel becomes a small step in each frame over the theme's
/// `motion.wheel-scroll`, scaled by its speed. It sits between the
/// platform and Flutter's gesture binding, so no scrollable needs a
/// controller of its own. `SpringApp` sets [spec] from the active theme.
///
/// A trackpad's scroll passes as it comes: it is smooth already, and
/// easing it again would lag behind the fingers. Only a frame it sends
/// nothing in, while the fingers move, gets the step of the frames before
/// (a browser sends a step a frame and now and then none: the page would
/// stop for that frame and jump twice as far in the next); the next step
/// that comes is that much shorter. A browser scrolls its own pages so.
final class WheelScrollSmoother {
  WheelScrollSmoother._(this._dispatcher);

  static WheelScrollSmoother? _instance;

  /// The smoother of [PlatformDispatcher.instance], installed on the first
  /// call.
  static WheelScrollSmoother get instance =>
      _instance ??= WheelScrollSmoother._(PlatformDispatcher.instance);

  /// A smoother of [dispatcher]; for tests.
  @visibleForTesting
  factory WheelScrollSmoother.of(PlatformDispatcher dispatcher) =>
      WheelScrollSmoother._(dispatcher);

  final PlatformDispatcher _dispatcher;
  PointerDataPacketCallback? _forward;
  WheelScrollSpec _spec = WheelScrollSpec.none;
  PointerData? _last;
  double _restX = 0;
  double _restY = 0;
  // The wheel's quick steps in a row (inertia) and when the last came.
  int _run = 0;
  Duration? _stepAt;

  /// The quick steps in a row [ScrollInertia.mouse] counts at most.
  static const maxRun = 6;

  // Two steps closer than this are one run.
  static const _quick = Duration(milliseconds: 140);
  bool _scheduled = false;
  Duration? _lastFrame;
  // The trackpad: its last step, how long before the one before it came,
  // whether one came since the last frame, the frames filled in a row and
  // what they moved ahead of it.
  PointerData? _pad;
  Duration? _padAt;
  Duration _padEvery = _frame;
  bool _padCame = false;
  bool _padWatched = false;
  int _filled = 0;
  double _aheadX = 0;
  double _aheadY = 0;
  Duration? _padFrame;

  // The frames in a row a missing trackpad step is made up for.
  static const _fill = 2;
  // The frames the trackpad's page has glided since the fingers stopped.
  int _gliding = 0;

  // The time of a frame when there is no frame before.
  static const _frame = Duration(microseconds: 16667);

  /// How the wheel scrolls now.
  WheelScrollSpec get spec => _spec;

  set spec(WheelScrollSpec value) {
    _spec = value;
    if (_forward == null) {
      _forward = _dispatcher.onPointerDataPacket;
      _dispatcher.onPointerDataPacket = _receive;
    }
  }

  bool _eases(PointerData data) =>
      data.signalKind == PointerSignalKind.scroll &&
      data.kind != PointerDeviceKind.trackpad &&
      !_spec.isNone;

  void _receive(PointerDataPacket packet) {
    final forward = _forward;
    if (forward == null) {
      return;
    }
    final pass = <PointerData>[];
    for (final data in packet.data) {
      if (data.signalKind == PointerSignalKind.scroll &&
          data.kind == PointerDeviceKind.trackpad) {
        pass.add(_padStep(data));
      } else if (_eases(data)) {
        final boost = _boost(data.timeStamp);
        // A step against the run stops it: the page turns at once.
        if (data.scrollDeltaY.sign * _restY.sign < 0) {
          _restY = 0;
        }
        if (data.scrollDeltaX.sign * _restX.sign < 0) {
          _restX = 0;
        }
        _restX += data.scrollDeltaX * _spec.speed * boost;
        _restY += data.scrollDeltaY * _spec.speed * boost;
        _last = data;
      } else {
        pass.add(data);
      }
    }
    if (pass.isNotEmpty) {
      forward(PointerDataPacket(data: pass));
    }
    if (_last != null && !_scheduled) {
      _scheduled = true;
      _lastFrame = null;
      SchedulerBinding.instance.scheduleFrameCallback(_step);
    }
  }

  // One step in each frame, by the frame's time: as smooth as the screen.
  void _step(Duration frame) {
    _scheduled = false;
    final last = _last;
    final forward = _forward;
    if (last == null || forward == null) {
      return;
    }
    final before = _lastFrame;
    _lastFrame = frame;
    final dt = (before == null || frame <= before ? _frame : frame - before)
        .inMicroseconds;
    // A fast run glides longer: up to twice the duration.
    final glide = 1 + _spec.inertia.mouse * 5 * _run / maxRun;
    final tau = _spec.duration.inMicroseconds / 3 * glide.clamp(1.0, 2.0);
    final share = tau <= 0 ? 1.0 : 1 - math.exp(-dt / tau);
    var dx = _restX * share;
    var dy = _restY * share;
    if ((_restX - dx).abs() < 0.5 && (_restY - dy).abs() < 0.5) {
      dx = _restX;
      dy = _restY;
    }
    _restX -= dx;
    _restY -= dy;
    if (dx != 0 || dy != 0) {
      forward(
        PointerDataPacket(
          data: [
            PointerData(
              viewId: last.viewId,
              timeStamp: last.timeStamp,
              change: last.change,
              kind: last.kind,
              signalKind: PointerSignalKind.scroll,
              device: last.device,
              physicalX: last.physicalX,
              physicalY: last.physicalY,
              scrollDeltaX: dx,
              scrollDeltaY: dy,
            ),
          ],
        ),
      );
    }
    if (_restX == 0 && _restY == 0) {
      _last = null;
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_step);
  }

  // A trackpad step as it came, less what the frames before it made up.
  PointerData _padStep(PointerData data) {
    final at = data.timeStamp;
    final before = _padAt;
    if (before != null && at > before) {
      final every = at - before;
      // A pause of the fingers is not a step's time.
      if (every < const Duration(milliseconds: 50)) {
        _padEvery = every;
      }
    }
    _padAt = at;
    var dx = data.scrollDeltaX;
    var dy = data.scrollDeltaY;
    // What was made up comes off this step, never past it.
    dx = _less(dx, _aheadX);
    dy = _less(dy, _aheadY);
    _aheadX = 0;
    _aheadY = 0;
    _filled = 0;
    _pad = data;
    _padCame = true;
    if (!_padWatched) {
      _padWatched = true;
      _padFrame = null;
      SchedulerBinding.instance.scheduleFrameCallback(_padCheck);
    }
    return dx == data.scrollDeltaX && dy == data.scrollDeltaY
        ? data
        : _scroll(data, dx, dy);
  }

  static double _less(double step, double ahead) {
    if (ahead == 0 || step == 0 || step.sign != ahead.sign) {
      return step;
    }
    return step.abs() > ahead.abs() ? step - ahead : 0;
  }

  static PointerData _scroll(PointerData from, double dx, double dy) =>
      PointerData(
        viewId: from.viewId,
        timeStamp: from.timeStamp,
        change: from.change,
        kind: from.kind,
        signalKind: PointerSignalKind.scroll,
        device: from.device,
        physicalX: from.physicalX,
        physicalY: from.physicalY,
        scrollDeltaX: dx,
        scrollDeltaY: dy,
      );

  // Each frame while the trackpad scrolls: one without its step gets the
  // last step again, for the frame's time; a few such frames in a row and
  // the fingers have stopped.
  void _padCheck(Duration frame) {
    final pad = _pad;
    final forward = _forward;
    final before = _padFrame;
    _padFrame = frame;
    if (pad == null || forward == null) {
      _padWatched = false;
      return;
    }
    if (_padCame) {
      _padCame = false;
      _gliding = 0;
    } else if (before != null && _filled < _fill) {
      _filled++;
      final dt = (frame - before).inMicroseconds;
      final share =
          dt / math.max(_padEvery.inMicroseconds, _frame.inMicroseconds ~/ 2);
      // Less each frame: by half, or as the trackpad's glide keeps it, so
      // the glide goes on from there.
      final keep = _spec.inertia.trackpad.clamp(0.0, 0.97);
      final scale =
          share.clamp(0.0, 2.0) *
          (keep > 0 ? math.pow(keep, _filled - 1).toDouble() : 1 / _filled);
      final dx = pad.scrollDeltaX * scale;
      final dy = pad.scrollDeltaY * scale;
      _aheadX += dx;
      _aheadY += dy;
      forward(PointerDataPacket(data: [_scroll(pad, dx, dy)]));
    } else if (before != null && _glide(pad, forward)) {
      // The fingers stopped and the page glides on (trackpad inertia).
    } else if (before != null) {
      // The fingers stopped: the next scroll is a new one, nothing comes
      // off it.
      _pad = null;
      _padWatched = false;
      _aheadX = 0;
      _aheadY = 0;
      _gliding = 0;
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback(_padCheck);
  }

  // How much more this step moves for the quick ones before it.
  double _boost(Duration at) {
    final before = _stepAt;
    _stepAt = at;
    final inertia = _spec.inertia.mouse;
    if (inertia == 0) {
      _run = 0;
      return 1;
    }
    final quick = before != null && at > before && at - before < _quick;
    _run = quick ? math.min(_run + 1, maxRun) : 0;
    return 1 + inertia * _run;
  }

  // One frame of the trackpad's glide: the last step, smaller each frame
  // by the inertia (0.9 keeps nine tenths); `false` once it is too small.
  bool _glide(PointerData pad, PointerDataPacketCallback forward) {
    final keep = _spec.inertia.trackpad.clamp(0.0, 0.97);
    if (keep == 0) {
      return false;
    }
    _gliding++;
    final scale = math.pow(keep, _gliding + _fill - 1).toDouble();
    final dx = pad.scrollDeltaX * scale;
    final dy = pad.scrollDeltaY * scale;
    if (dx.abs() < 0.5 && dy.abs() < 0.5) {
      return false;
    }
    forward(PointerDataPacket(data: [_scroll(pad, dx, dy)]));
    return true;
  }
}

/// The inertia of scrolling, each kind of pointer its own (0, none, by
/// default): `motion.wheel-scroll.inertia`.
///
/// ```yaml
/// motion:
///   wheel-scroll: { duration: 260ms, inertia: { mouse: 0.2 } }
/// ```
final class ScrollInertia {
  /// The inertia of a [mouse], a [trackpad] and [touch].
  const ScrollInertia({this.mouse = 0, this.trackpad = 0, this.touch = 0});

  /// None for any pointer.
  static const none = ScrollInertia();

  /// Reads the inertia at [base] of [p]; [none] when nothing is written.
  static ScrollInertia parseAt(ThemeProperties p, String base) {
    final kind = p[base];
    if (kind != null) {
      if (ThemeValues.canonical(kind) == 'none') {
        return none;
      }
      throw ThemePropertyException(
        p.propertyName(base),
        kind,
        'none, or a map of mouse, trackpad and touch',
      );
    }
    const keys = ['mouse', 'trackpad', 'touch'];
    for (final key in p.children(base)) {
      if (!keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          p['$base.$key'] ?? '',
          'mouse, trackpad or touch${didYouMean(key, keys)}',
        );
      }
    }
    double read(String key, String expected) =>
        p.read(
          '$base.$key',
          (v) => switch (ThemeValues.number(v)) {
            final n? when n >= 0 => n,
            _ => null,
          },
          expected,
        ) ??
        0;
    return ScrollInertia(
      mouse: read(
        'mouse',
        'a number from 0; 0.2 adds a fifth to each quick step',
      ),
      trackpad: read(
        'trackpad',
        'a number from 0 to 1; 0.9 keeps nine tenths of the step each frame',
      ),
      touch: read(
        'touch',
        'a number from 0; 0.5 throws a flick half again as far',
      ),
    );
  }

  /// What each quick step of the wheel in a row adds to the next (0.2: a
  /// fifth more, up to [WheelScrollSmoother.maxRun] steps), and the longer
  /// glide of a fast run.
  final double mouse;

  /// How much of its last step the page keeps each frame once the fingers
  /// stop on the trackpad: 0.9 glides on, nine tenths each frame.
  final double trackpad;

  /// How much further a flick throws the page: 0.5 half again as far.
  final double touch;

  @override
  bool operator ==(Object other) =>
      other is ScrollInertia &&
      other.mouse == mouse &&
      other.trackpad == trackpad &&
      other.touch == touch;

  @override
  int get hashCode => Object.hash(mouse, trackpad, touch);
}

/// Throws a flick further by [ScrollInertia.touch]: the velocity the
/// finger leaves the page with, times one and that much.
class InertiaScrollPhysics extends ScrollPhysics {
  /// A flick [extra] times faster, on [parent]'s physics.
  const InertiaScrollPhysics(this.extra, {super.parent});

  /// What the flick's velocity gets on top (0.5: half again).
  final double extra;

  @override
  InertiaScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      InertiaScrollPhysics(extra, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(position, velocity * (1 + extra));
}
