import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// How a mouse wheel scrolls, `motion.wheel-scroll`: at once by the
/// wheel's step (`none`, Flutter's own), or eased over [duration] and
/// scaled by [speed].
///
/// ```yaml
/// motion:
///   wheel-scroll: { duration: 250ms, speed: 0.8 }
/// ```
final class WheelScrollSpec {
  /// A wheel that moves [speed] times its step over [duration].
  const WheelScrollSpec({this.duration = Duration.zero, this.speed = 1});

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
        'none, or a map of duration and speed',
      );
    }
    final children = p.children(base);
    if (children.isEmpty) {
      return none;
    }
    const keys = ['duration', 'speed'];
    for (final key in children) {
      if (!keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          p['$base.$key'] ?? '',
          'duration or speed${didYouMean(key, keys)}',
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
    );
  }

  /// How long a step takes to arrive; zero for at once.
  final Duration duration;

  /// The step's share: below 1 slower, above faster.
  final double speed;

  /// Whether the wheel scrolls as Flutter does by itself.
  bool get isNone => duration == Duration.zero && speed == 1;

  @override
  bool operator ==(Object other) =>
      other is WheelScrollSpec &&
      other.duration == duration &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(duration, speed);
}

/// Eases the wheel's scroll signals for every scrollable of the app: a
/// step of the wheel becomes a small step in each frame over the theme's
/// `motion.wheel-scroll`, scaled by its speed. It sits between the
/// platform and Flutter's gesture binding, so no scrollable needs a
/// controller of its own. `SpringApp` sets [spec] from the active theme.
///
/// A trackpad's scroll passes as it comes: it is smooth already, and
/// easing it again would lag behind the fingers.
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
  bool _scheduled = false;
  Duration? _lastFrame;

  // The time of a frame when there is no frame before.
  static const _frame = Duration(microseconds: 16667);

  /// How the wheel scrolls now.
  WheelScrollSpec get spec => _spec;

  set spec(WheelScrollSpec value) {
    _spec = value;
    if (!value.isNone && _forward == null) {
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
      if (_eases(data)) {
        _restX += data.scrollDeltaX * _spec.speed;
        _restY += data.scrollDeltaY * _spec.speed;
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
    final tau = _spec.duration.inMicroseconds / 3;
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
}
