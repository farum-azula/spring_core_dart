import 'dart:async';

import 'package:spring_core_dart/src/core/isolate/isolate_info.dart';
import 'package:spring_core_dart/src/core/isolate/process_memory_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/isolate/process_memory_io.dart'
    if (dart.library.js_interop) 'package:spring_core_dart/src/core/isolate/process_memory_web.dart';

/// How busy an isolate (or a thread of a Flutter engine) is, as measured
/// over the last few seconds: one row of the task manager.
///
/// Every value but [name] and [kind] is `null` when its source cannot
/// measure it. It is plain data: [toJson] is what an isolate sends to the
/// primary, and what the actuator's `isolates` endpoint answers.
final class IsolateLoad {
  /// The load of [name].
  const IsolateLoad({
    required this.name,
    required this.kind,
    this.busy,
    this.lag,
    this.maxLag,
    this.active,
    this.memory,
    this.details = const {},
  });

  /// The load [json] ([toJson]) describes.
  factory IsolateLoad.fromJson(Map<Object?, Object?> json) => IsolateLoad(
    name: '${json['name']}',
    kind: '${json['kind']}',
    busy: (json['busy'] as num?)?.toDouble(),
    lag: _micros(json['lagMicros']),
    maxLag: _micros(json['maxLagMicros']),
    active: (json['active'] as num?)?.toInt(),
    memory: (json['memory'] as num?)?.toInt(),
    details: {
      for (final MapEntry(:key, :value)
          in (json['details'] as Map<Object?, Object?>? ?? const {}).entries)
        '$key': value,
    },
  );

  /// The name the logs show: `main`, `isolate-2`, `task-1`, `raster`.
  final String name;

  /// What it is: `main` (the application's first isolate), `server` (an
  /// isolate of the web server's pool), `task` (one of the task
  /// executor's), `engine` (a thread of the Flutter engine), or a source's
  /// own word.
  final String kind;

  /// The share of the time it was working, `0` to `1`. For an isolate
  /// with an event loop it is estimated from [lag]: how late its timers
  /// were, over the time measured.
  final double? busy;

  /// How late the event loop ran a timer, on average: near zero when the
  /// isolate is free, the length of what blocks it when it is not.
  final Duration? lag;

  /// The longest [lag] measured.
  final Duration? maxLag;

  /// What it is working on now: requests in flight, tasks running.
  final int? active;

  /// Memory in bytes. Isolates share their process's memory, so only the
  /// `main` row has it: the resident size of the process.
  final int? memory;

  /// What only this source measures, by name: `queued` tasks, `raster
  /// cache` bytes. Values are numbers, text, or a [Duration] in
  /// microseconds under a name ending in `Micros`.
  final Map<String, Object?> details;

  /// This load as JSON, which crosses isolates and is what the actuator
  /// answers.
  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind,
    'busy': ?busy,
    'lagMicros': ?lag?.inMicroseconds,
    'maxLagMicros': ?maxLag?.inMicroseconds,
    'active': ?active,
    'memory': ?memory,
    if (details.isNotEmpty) 'details': details,
  };

  /// This load with what [other] knows and this one does not; the
  /// [details] of both, [other]'s over this one's.
  IsolateLoad merge(IsolateLoad other) => IsolateLoad(
    name: name,
    kind: kind,
    busy: busy ?? other.busy,
    lag: lag ?? other.lag,
    maxLag: maxLag ?? other.maxLag,
    active: active ?? other.active,
    memory: memory ?? other.memory,
    details: {...details, ...other.details},
  );

  static Duration? _micros(Object? value) =>
      value is num ? Duration(microseconds: value.toInt()) : null;

  @override
  String toString() => 'IsolateLoad(${toJson()})';
}

/// Tells the load of some isolates or threads: one source of the task
/// manager's rows.
///
/// The framework has one for the isolate it runs in
/// ([IsolateLoadSampler]), one for the web server's pool, one for the task
/// executor's isolates, and in a Flutter app one for the engine's threads.
/// Declare a bean of your own for isolates the application starts itself:
/// [IsolateLoads] asks every source.
///
/// A source may also add to a row another source gives, by giving a load
/// of the same name: the web server adds the requests in flight to its
/// isolate's row, a Flutter app the frame times to `main`.
abstract interface class IsolateLoadSource {
  /// The loads now.
  List<IsolateLoad> loads();
}

/// Every isolate the application knows about, with its load: the bean
/// `isolateLoads`, which a debug widget and the actuator's `isolates`
/// endpoint read.
///
/// It asks each [IsolateLoadSource] bean, in order; loads of one name
/// are one row ([IsolateLoad.merge]). An isolate the
/// application starts by itself (`Isolate.run`, `compute`) is not seen by
/// any source (a compiled program cannot list its isolates); [track] shows
/// it while it runs:
///
/// ```dart
/// final report = await loads.track('report', Isolate.run(buildReport));
/// ```
final class IsolateLoads {
  /// The loads of [sources].
  IsolateLoads(this.sources);

  /// The sources, asked in this order.
  final List<IsolateLoadSource> sources;

  final _tracked = <String, int>{};

  /// The loads now, the sources' first and then what is [track]ed; one
  /// row per name.
  List<IsolateLoad> all() {
    final rows = <String, IsolateLoad>{};
    for (final load in [
      for (final source in sources) ...source.loads(),
      for (final MapEntry(key: name, value: count) in _tracked.entries)
        IsolateLoad(name: name, kind: 'tracked', busy: 1, active: count),
    ]) {
      rows[load.name] = rows[load.name]?.merge(load) ?? load;
    }
    return rows.values.toList();
  }

  /// Shows an isolate named [name] as working until [work] completes, and
  /// returns [work]. For isolates the application starts itself.
  Future<T> track<T>(String name, Future<T> work) {
    _tracked[name] = (_tracked[name] ?? 0) + 1;
    return work.whenComplete(() {
      final left = (_tracked[name] ?? 1) - 1;
      if (left <= 0) {
        _tracked.remove(name);
      } else {
        _tracked[name] = left;
      }
    });
  }
}

/// Measures the isolate it runs in: how late its event loop is, and from
/// that how busy.
///
/// A timer is due every [interval]; how late it fires is the lag. A free
/// isolate fires it on time; one that computes for 80 ms fires it 80 ms
/// late. [load] is the last [window] of it. How late a platform's timers
/// are by themselves (the least lateness seen since the start, a few
/// milliseconds on some systems) is taken off, so a free isolate reads
/// zero everywhere.
///
/// An isolate that answers many short requests is late by about the
/// requests waiting at that moment: with fifty connections of 0.2 ms
/// each, some 10 ms. So the lag shows a queue, not how much of a
/// processor is used.
///
/// It measures only while someone reads: the first [load] starts the
/// timer (and has no lag yet), and it stops by itself after [idleAfter]
/// without a read. So an application nobody watches pays nothing.
final class IsolateLoadSampler implements IsolateLoadSource {
  /// A sampler of the current isolate.
  IsolateLoadSampler({
    this.interval = const Duration(milliseconds: 100),
    this.window = const Duration(seconds: 5),
    this.idleAfter = const Duration(seconds: 30),
    this.kind,
  });

  /// How often the timer is due.
  final Duration interval;

  /// How far back [load] looks.
  final Duration window;

  /// Without a read for this long, the timer stops.
  final Duration idleAfter;

  /// The row's [IsolateLoad.kind]; `null`: `main` for the primary isolate
  /// and `server` for another.
  final String? kind;

  Timer? _timer;
  final _clock = Stopwatch();
  int _due = 0;
  int _read = 0;
  int? _floor;
  // The lags of the window, in microseconds, with when each was measured.
  final _lags = <(int, int)>[];

  /// Whether the timer runs.
  bool get isRunning => _timer != null;

  /// The load of the isolate over the last [window].
  IsolateLoad load() {
    _start();
    _read = _clock.elapsedMicroseconds;
    final since = _read - window.inMicroseconds;
    _lags.removeWhere((entry) => entry.$1 < since);
    final info = IsolateInfo.current;
    var sum = 0;
    var most = 0;
    for (final (_, lag) in _lags) {
      sum += lag;
      if (lag > most) {
        most = lag;
      }
    }
    final measured = _lags.isEmpty
        ? 0
        : _lags.length * interval.inMicroseconds + sum;
    return IsolateLoad(
      name: info.name,
      kind: kind ?? (info.primary ? 'main' : 'server'),
      busy: _lags.isEmpty ? null : (sum / measured).clamp(0, 1).toDouble(),
      lag: _lags.isEmpty ? null : Duration(microseconds: sum ~/ _lags.length),
      maxLag: _lags.isEmpty ? null : Duration(microseconds: most),
      memory: info.primary ? processMemory() : null,
    );
  }

  @override
  List<IsolateLoad> loads() => [load()];

  /// Stops the timer and forgets what was measured.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock
      ..stop()
      ..reset();
    _lags.clear();
  }

  void _start() {
    if (_timer != null) {
      return;
    }
    _clock.start();
    _schedule();
  }

  void _schedule() {
    _due = _clock.elapsedMicroseconds + interval.inMicroseconds;
    _timer = Timer(interval, _fired);
  }

  void _fired() {
    final now = _clock.elapsedMicroseconds;
    if (now - _read > idleAfter.inMicroseconds) {
      stop();
      return;
    }
    final late = now - _due < 0 ? 0 : now - _due;
    // A timer of a free isolate is late too, by what the platform's timers
    // are (a few milliseconds on some): the least ever seen is that, and
    // the lag is what comes on top.
    if (_floor == null || late < _floor!) {
      _floor = late;
    }
    _lags.add((now, late - _floor!));
    _schedule();
  }
}
