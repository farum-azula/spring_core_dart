import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_loader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// What a loader's tracks read on each frame: the time, the start's
/// progress and stage.
final class LoaderClock {
  /// A clock at [elapsed], [dt] after the last frame.
  const LoaderClock({
    required this.elapsed,
    required this.dt,
    this.progress,
    this.stage,
    this.since,
  });

  /// How long the loader has run (on the web, from the page's loader).
  final Duration elapsed;

  /// The time since the last frame.
  final Duration dt;

  /// The start's progress, 0 to 1; `null` when it is indeterminate.
  final double? progress;

  /// The start's stage; `null` for a loader outside the splash.
  final SplashStage? stage;

  /// How long ago a stage was reached; `null` when it was not (yet).
  final Duration? Function(SplashStage stage)? since;
}

/// A track of a loader as the theme declares it
/// (`loaders.<name>.tracks.<track>`): a value from 0 to 1 that a loader reads each frame
/// (`LoaderFrame.track`) for one of its movements, led by what its
/// [LoaderTrackDriver] follows.
abstract interface class LoaderTrack {
  /// A run of the track for one loader on screen (it may keep state, the
  /// smoothed progress).
  LoaderTrackRun run();

  /// The value with less motion (`reduceMotion`): where the track rests.
  double still(double? progress);
}

/// One loader's run of a [LoaderTrack].
abstract interface class LoaderTrackRun {
  /// The value at [clock], 0 to 1.
  double advance(LoaderClock clock);
}

/// Reads the tracks that follow one thing (`follows: time`): its keys and
/// the [LoaderTrack] they make. The built-in drivers are `time`, `stage`
/// and `progress`; an application adds its own with
/// [LoaderTrackDrivers.register], and `follows:` may name it.
abstract interface class LoaderTrackDriver {
  /// What `follows:` names, in canonical form (`time`).
  String get name;

  /// The keys a track of this driver takes besides `follows`.
  List<String> get keys;

  /// Reads the track from its [values] (`duration`, ...). Throws a
  /// `ThemePropertyException` for a missing or wrong value
  /// ([LoaderValues.fail] names the property).
  LoaderTrack parse(LoaderValues values);
}

/// The drivers of the loaders' tracks, by what `follows:` names: the
/// built-in [TimeTrackDriver], [StageTrackDriver] and [ProgressTrackDriver],
/// and the application's own. Registered before the context starts (the
/// themes are read at the start), as the loader kinds are.
///
/// ```dart
/// LoaderTrackDrivers.register(const BeatTrackDriver());
/// ```
abstract final class LoaderTrackDrivers {
  static final _drivers = <String, LoaderTrackDriver>{
    for (final driver in builtIn) driver.name: driver,
  };

  /// The built-in drivers.
  static const builtIn = <LoaderTrackDriver>[
    TimeTrackDriver(),
    StageTrackDriver(),
    ProgressTrackDriver(),
  ];

  /// Registers [driver]; one of the same name replaces the earlier one.
  static void register(LoaderTrackDriver driver) =>
      _drivers[ThemeValues.canonical(driver.name)] = driver;

  /// The driver [name] names; `null` when there is none.
  static LoaderTrackDriver? lookup(String name) =>
      _drivers[ThemeValues.canonical(name)];

  /// The names `follows:` may take.
  static List<String> get names => List.unmodifiable(_drivers.keys);

  /// Reads every track of the loader's `tracks`, by name.
  static Map<String, LoaderTrack> parseAll(LoaderValues loader) => {
    for (final name in loader.keys('tracks'))
      name: parse(loader.at('tracks.$name')),
  };

  /// Reads one track: its `follows` (`time` when not written) picks the
  /// driver, which reads the rest.
  static LoaderTrack parse(LoaderValues track) {
    final follows = track.textOrNull('follows') ?? 'time';
    final driver = lookup(follows);
    if (driver == null) {
      track.fail(
        'follows',
        'what a track follows: ${names.join(', ')}'
            '${didYouMean(follows, names)}',
      );
    }
    final keys = ['follows', ...driver.keys];
    for (final key in track.keys()) {
      if (!keys.contains(key)) {
        track.fail(
          key,
          'a key of a ${driver.name} track: ${keys.join(', ')}'
          '${didYouMean(key, keys)}',
        );
      }
    }
    return driver.parse(track);
  }

  /// Forgets the application's drivers; for tests.
  static void reset() => _drivers
    ..clear()
    ..addAll({for (final driver in builtIn) driver.name: driver});
}

// The position in [spec] after [t]: once, looping or back and forth.
double _play(AnimationSpec spec, Duration t) {
  final run = spec.duration.inMicroseconds;
  if (run <= 0) {
    return 1;
  }
  final x = t.inMicroseconds / run;
  final position = switch (spec.repeat) {
    AnimationRepeat.none => x.clamp(0.0, 1.0),
    AnimationRepeat.loop => x - x.floorToDouble(),
    AnimationRepeat.reverse => () {
      final cycle = x % 2;
      return cycle <= 1 ? cycle : 2 - cycle;
    }(),
  };
  return spec.curve.transform(position.clamp(0.0, 1.0));
}

AnimationSpec _animation(LoaderValues track) => AnimationSpec(
  duration:
      track.durationOrNull('duration') ??
      track.fail(
        'duration',
        'a duration like 2s or 400ms (a time or stage track has one)',
      ),
  curve: track.curveOrNull('curve') ?? Curves.linear,
  repeat:
      track.choiceOrNull('repeat', AnimationRepeat.values) ??
      AnimationRepeat.none,
);

Duration _delay(LoaderValues track) =>
    track.durationOrNull('delay') ?? Duration.zero;

/// `follows: time`: a movement by the clock alone (a turn, a pulse), from
/// the loader's start (on the web, the page's), after `delay`: `duration`,
/// `curve`, `repeat` (`none`, `loop`, `reverse`).
final class TimeTrackDriver implements LoaderTrackDriver {
  /// The driver of time tracks.
  const TimeTrackDriver();

  @override
  String get name => 'time';

  @override
  List<String> get keys => const ['duration', 'curve', 'repeat', 'delay'];

  @override
  LoaderTrack parse(LoaderValues values) =>
      _TimeTrack(_animation(values), _delay(values));
}

final class _TimeTrack implements LoaderTrack, LoaderTrackRun {
  const _TimeTrack(this.spec, this.delay);

  final AnimationSpec spec;
  final Duration delay;

  @override
  LoaderTrackRun run() => this;

  @override
  double still(double? progress) => spec.repeat == AnimationRepeat.none ? 1 : 0;

  @override
  double advance(LoaderClock clock) {
    final t = clock.elapsed - delay;
    return t <= Duration.zero ? 0 : _play(spec, t);
  }
}

/// `follows: stage`: a movement that starts when the start reaches the
/// stage `from` (`page`, `splash`, `ready`, `exit`...), after `delay`:
/// `duration`, `curve`, `repeat`. It stays at 0 before.
final class StageTrackDriver implements LoaderTrackDriver {
  /// The driver of stage tracks.
  const StageTrackDriver();

  @override
  String get name => 'stage';

  @override
  List<String> get keys => const [
    'from',
    'duration',
    'curve',
    'repeat',
    'delay',
  ];

  @override
  LoaderTrack parse(LoaderValues values) => _StageTrack(
    values.choiceOrNull('from', SplashStage.values) ??
        values.fail(
          'from',
          'the stage the track starts at: '
              '${[for (final stage in SplashStage.values) stage.name].join(', ')}',
        ),
    _animation(values),
    _delay(values),
  );
}

final class _StageTrack implements LoaderTrack {
  const _StageTrack(this.from, this.spec, this.delay);

  final SplashStage from;
  final AnimationSpec spec;
  final Duration delay;

  @override
  LoaderTrackRun run() => _StageRun(this);

  @override
  double still(double? progress) => spec.repeat == AnimationRepeat.none ? 1 : 0;
}

final class _StageRun implements LoaderTrackRun {
  _StageRun(this.track);

  final _StageTrack track;
  Duration? _startedAt;

  @override
  double advance(LoaderClock clock) {
    final stage = clock.stage;
    if (_startedAt == null) {
      if (stage == null || stage.index < track.from.index) {
        return 0;
      }
      // Reached before this loader saw it: go on from then.
      final ago = clock.since?.call(track.from) ?? Duration.zero;
      _startedAt = clock.elapsed - ago;
    }
    final t = clock.elapsed - _startedAt! - track.delay;
    return t <= Duration.zero ? 0 : _play(track.spec, t);
  }
}

/// `follows: progress`: the start's progress, smoothed: it moves towards
/// the real progress with a time constant `smoothing` (300ms when not
/// written), so it never jumps, then through `curve`.
final class ProgressTrackDriver implements LoaderTrackDriver {
  /// The driver of progress tracks.
  const ProgressTrackDriver();

  @override
  String get name => 'progress';

  @override
  List<String> get keys => const ['smoothing', 'curve'];

  @override
  LoaderTrack parse(LoaderValues values) => _ProgressTrack(
    values.durationOrNull('smoothing') ?? const Duration(milliseconds: 300),
    values.curveOrNull('curve') ?? Curves.linear,
  );
}

final class _ProgressTrack implements LoaderTrack {
  const _ProgressTrack(this.smoothing, this.curve);

  final Duration smoothing;
  final Curve curve;

  @override
  LoaderTrackRun run() => _ProgressRun(this);

  @override
  double still(double? progress) => curve.transform(progress ?? 0);
}

final class _ProgressRun implements LoaderTrackRun {
  _ProgressRun(this.track);

  final _ProgressTrack track;
  double _shown = 0;

  @override
  double advance(LoaderClock clock) {
    final target = (clock.progress ?? 0).clamp(0.0, 1.0);
    final tau = track.smoothing.inMicroseconds;
    if (tau <= 0) {
      _shown = target;
    } else {
      final k = 1 - math.exp(-clock.dt.inMicroseconds / tau);
      _shown += (target - _shown) * k;
      if ((target - _shown).abs() < 0.0005) {
        _shown = target;
      }
    }
    return track.curve.transform(_shown.clamp(0.0, 1.0));
  }
}
