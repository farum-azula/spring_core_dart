import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/isolates/engine_load_probe.dart';

/// The threads of the Flutter engine as rows of the task manager (the
/// `flutterEngineLoads` bean): an [IsolateLoadSource], so `isolateLoads`
/// has them beside the app's isolates. It needs no VM service and works
/// in a release build.
///
/// - `main`: the build times of the frames, added to the row the
///   `isolateLoadSampler` gives ([FrameLoadProbe]);
/// - `raster`: how busy the thread that draws is ([FrameLoadProbe]);
/// - `platform`: how long the platform thread takes to answer a call of
///   a channel ([RoundTripProbe.platform]);
/// - `io`: how long the engine's IO and worker threads take to decode a
///   picture of one pixel ([RoundTripProbe.io]).
///
/// A browser has no platform and no IO thread: there it gives `main` and
/// `raster` only ([probesOf]).
///
/// It measures only while someone reads: the first [loads] starts the
/// [probes] (and has little to tell yet), every [interval] they ask their
/// threads again, and after [idleAfter] without a read they stop. So an
/// app nobody watches pays nothing.
final class FlutterEngineLoads implements IsolateLoadSource {
  /// The loads [probes] measure; those of the platform ([probesOf]) when
  /// none are given.
  FlutterEngineLoads({
    List<EngineLoadProbe>? probes,
    this.interval = const Duration(seconds: 2),
    this.idleAfter = const Duration(seconds: 30),
  }) : probes = probes ?? probesOf();

  /// The probes of a platform: the frames everywhere, and the platform
  /// and IO threads except in a browser ([web]), which has neither.
  static List<EngineLoadProbe> probesOf({bool web = kIsWeb}) => [
    FrameLoadProbe(),
    if (!web) ...[RoundTripProbe.platform(), RoundTripProbe.io()],
  ];

  /// What measures, asked for its rows in this order.
  final List<EngineLoadProbe> probes;

  /// How often the probes ask their threads again.
  final Duration interval;

  /// Without a read for this long, the probes stop.
  final Duration idleAfter;

  Timer? _timer;
  // The ticks since the last read.
  int _idle = 0;

  /// Whether the probes measure.
  bool get isRunning => _timer != null;

  @override
  List<IsolateLoad> loads() {
    _idle = 0;
    if (_timer == null) {
      _timer = Timer.periodic(interval, _tick);
      for (final probe in probes) {
        probe.start();
      }
    }
    return [for (final probe in probes) ...probe.loads()];
  }

  /// Stops the probes, which forget what they measured.
  void stop() {
    if (_timer == null) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    for (final probe in probes) {
      probe.stop();
    }
  }

  void _tick(Timer timer) {
    if (interval * ++_idle > idleAfter) {
      stop();
      return;
    }
    for (final probe in probes) {
      probe.tick();
    }
  }
}
