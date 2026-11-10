import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The time since some start, which only goes on: what a probe measures
/// with. A test gives its own.
typedef EngineClock = Duration Function();

/// A clock that starts now.
EngineClock engineStopwatch() {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}

/// Measures some threads of the Flutter engine: one source of the rows of
/// `FlutterEngineLoads`, which starts it at its first read and stops it
/// when nobody reads any more.
///
/// The starter has one for the frames ([FrameLoadProbe]) and one for a
/// thread that answers a question ([RoundTripProbe]); an application
/// gives `FlutterEngineLoads` its own for a thread it knows how to ask.
abstract interface class EngineLoadProbe {
  /// Starts measuring.
  void start();

  /// Called now and then while it measures (`FlutterEngineLoads.interval`):
  /// the moment to ask a thread again.
  void tick();

  /// Stops measuring and forgets what was measured.
  void stop();

  /// The rows now.
  List<IsolateLoad> loads();
}

// One frame: when its times came, how long its build and raster took.
typedef _Frame = ({Duration at, int build, int raster});

/// The frames of the last [window], from Flutter's own times
/// (`FrameTiming`, in release builds too): two rows.
///
/// - `main`, the app's isolate, gets details only: the average and the
///   worst build time (`buildMicros`, `buildMaxMicros`) and the number of
///   `frames`. How busy it is the `isolateLoadSampler` tells, in the row
///   of the same name.
/// - `raster`, the thread that draws: `busy` is the raster time over the
///   time measured; the details are the average and the worst raster time
///   (`rasterMicros`, `rasterMaxMicros`) and the last frame's caches
///   (`layerCacheBytes`, `pictureCacheBytes`).
///
/// In a browser the raster is the renderer's: a worker with skwasm, the
/// page's own thread with CanvasKit.
///
/// The engine reports the times of several frames at once (every second
/// in a release build), so a frame counts from when it was reported.
final class FrameLoadProbe implements EngineLoadProbe {
  /// A probe of the frames of the last [window], timed by [clock].
  FrameLoadProbe({
    this.window = const Duration(seconds: 5),
    EngineClock? clock,
  }) : _clock = clock ?? engineStopwatch();

  /// How far back the rows look.
  final Duration window;

  final EngineClock _clock;
  final _frames = ListQueue<_Frame>();
  Duration? _since;
  ui.FrameTiming? _last;

  @override
  void start() {
    _since = _clock();
    SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  @override
  void tick() {}

  @override
  void stop() {
    if (_since != null) {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
    }
    _since = null;
    _last = null;
    _frames.clear();
  }

  void _timings(List<ui.FrameTiming> timings) {
    final at = _clock();
    for (final timing in timings) {
      _frames.addLast((
        at: at,
        build: timing.buildDuration.inMicroseconds,
        raster: timing.rasterDuration.inMicroseconds,
      ));
      _last = timing;
    }
  }

  @override
  List<IsolateLoad> loads() {
    final now = _clock();
    final since = _since ?? now;
    while (_frames.isNotEmpty && now - _frames.first.at > window) {
      _frames.removeFirst();
    }
    final measured = now - since < window ? now - since : window;
    final count = _frames.length;
    var build = 0;
    var buildMax = 0;
    var raster = 0;
    var rasterMax = 0;
    for (final frame in _frames) {
      build += frame.build;
      raster += frame.raster;
      buildMax = frame.build > buildMax ? frame.build : buildMax;
      rasterMax = frame.raster > rasterMax ? frame.raster : rasterMax;
    }
    return [
      IsolateLoad(
        name: IsolateInfo.current.name,
        kind: 'main',
        details: {
          'frames': count,
          if (count > 0) ...{
            'buildMicros': build ~/ count,
            'buildMaxMicros': buildMax,
          },
        },
      ),
      IsolateLoad(
        name: 'raster',
        kind: 'engine',
        busy: measured > Duration.zero
            ? (raster / measured.inMicroseconds).clamp(0, 1).toDouble()
            : null,
        details: {
          if (count > 0) ...{
            'rasterMicros': raster ~/ count,
            'rasterMaxMicros': rasterMax,
          },
          if (_last case final last?) ...{
            'layerCacheBytes': last.layerCacheBytes,
            'pictureCacheBytes': last.pictureCacheBytes,
          },
        },
      ),
    ];
  }
}

/// A question a thread of the engine answers: it completes when the
/// answer is back in the app's isolate, and fails when nothing answers.
typedef EngineRoundTrip = Future<void> Function();

/// How long a thread of the engine takes to answer: a row named [name]
/// whose `lag` is the average of the last [samples] round trips and whose
/// `maxLag` is the longest, or how long the one under way has waited when
/// that is longer. A free thread answers in well under a millisecond; a
/// busy one after what keeps it.
///
/// The answer comes back to the app's isolate, so a busy `main` adds its
/// own wait to every row.
///
/// The [trips] are tried in order: one that fails (no implementation on
/// this platform, an error) is not asked again and the next one is. When
/// none is left the row has no lag; the probe never throws.
final class RoundTripProbe implements EngineLoadProbe {
  /// A probe of the thread [name], asked by the first of [trips] that
  /// answers.
  RoundTripProbe(
    this.name,
    this.trips, {
    this.samples = 5,
    EngineClock? clock,
  }) : _clock = clock ?? engineStopwatch();

  /// The platform thread, where the platform's own code and the plugins
  /// run: a call of a channel the engine itself answers, with no effect
  /// and no permission asked ([keyboardState], and [liveTextAvailable]
  /// on iOS, which has no keyboard state).
  ///
  /// Where the engine runs the app's isolate on the platform thread (its
  /// default on phones and macOS today) they are one thread, and this
  /// row waits as `main` does.
  factory RoundTripProbe.platform({EngineClock? clock}) => RoundTripProbe(
    'platform',
    const [keyboardState, liveTextAvailable],
    clock: clock,
  );

  /// The engine's IO and worker threads, which decode the app's pictures:
  /// a picture of one pixel decoded ([decodeImage]).
  factory RoundTripProbe.io({EngineClock? clock}) =>
      RoundTripProbe('io', const [decodeImage], clock: clock);

  /// The row's name.
  final String name;

  /// The questions, the first that answers being the one asked.
  final List<EngineRoundTrip> trips;

  /// How many round trips the row tells of.
  final int samples;

  final EngineClock _clock;
  final _lags = ListQueue<Duration>();
  // The trip asked: those before it failed.
  int _trip = 0;
  // When the trip under way was asked.
  Duration? _asked;
  // Changes at every stop, so an answer that comes after it is dropped.
  int _run = 0;

  /// Asks the keys held down over the `flutter/keyboard` channel, as
  /// `HardwareKeyboard.syncKeyboardState` does: answered on Android,
  /// Linux, macOS and Windows.
  static Future<void> keyboardState() =>
      _answered(SystemChannels.keyboard, 'getKeyboardState');

  /// Asks whether the camera can read text, as a text field's menu does
  /// (`LiveText.isLiveTextInputAvailable`): answered on iOS only.
  static Future<void> liveTextAvailable() =>
      _answered(SystemChannels.platform, 'LiveText.isLiveTextInputAvailable');

  // The engine's own channels answer nothing, without an error, where a
  // method has no implementation: that is no round trip to the thread.
  static Future<void> _answered(MethodChannel channel, String method) async {
    if (await channel.invokeMethod<Object?>(method) == null) {
      throw MissingPluginException('$method on ${channel.name}');
    }
  }

  /// Decodes a transparent picture of one pixel from memory.
  static Future<void> decodeImage() async {
    final codec = await ui.instantiateImageCodec(_pixel);
    try {
      (await codec.getNextFrame()).image.dispose();
    } finally {
      codec.dispose();
    }
  }

  @override
  void start() => tick();

  @override
  void tick() {
    if (_asked != null || _trip >= trips.length) {
      return;
    }
    final run = _run;
    final asked = _asked = _clock();
    unawaited(
      Future.sync(trips[_trip]).then(
        (_) {
          if (run == _run) {
            _asked = null;
            _lags.addLast(_clock() - asked);
            while (_lags.length > samples) {
              _lags.removeFirst();
            }
          }
        },
        onError: (Object _) {
          if (run == _run) {
            _asked = null;
            _trip++;
            tick();
          }
        },
      ),
    );
  }

  @override
  void stop() {
    _run++;
    _asked = null;
    _lags.clear();
  }

  @override
  List<IsolateLoad> loads() {
    var sum = Duration.zero;
    Duration? most;
    for (final lag in _lags) {
      sum += lag;
      most = most == null || lag > most ? lag : most;
    }
    // The trip under way counts once it waits longer than every one
    // measured.
    if (_asked case final asked?) {
      final waited = _clock() - asked;
      most = waited > (most ?? Duration.zero) ? waited : most;
    }
    return [
      IsolateLoad(
        name: name,
        kind: 'engine',
        lag: _lags.isEmpty ? null : sum ~/ _lags.length,
        maxLag: most,
      ),
    ];
  }
}

// A transparent PNG of one pixel.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAA'
  'AAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=',
);
