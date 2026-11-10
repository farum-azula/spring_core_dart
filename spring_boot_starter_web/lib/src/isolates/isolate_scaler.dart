import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Changes how many isolates serve the port while the server runs: the
/// bean `isolateScaler`, there when the server has a pool
/// (`server.isolates.count` above one, `server.isolates.scaling: auto`, or
/// `server.isolates.max` above one), in every isolate of it: the pool
/// itself in the first, and in the others a bean that hands the step to
/// it.
///
/// ```dart
/// @RestController()
/// class Operations {
///   Operations(this.isolates);
///   final IsolateScaler isolates;
///
///   // Before the sale starts.
///   @PostMapping('/internal/scale')
///   Future<int> scale(@RequestParam() int to) => isolates.scaleTo(to);
/// }
/// ```
///
/// **Adding** starts new isolates; each runs the whole application and
/// joins the port when its own beans are up, so requests are never sent
/// to one that is not ready. **Removing** takes the newest isolates: each
/// stops taking connections, finishes its requests (for at most
/// `server.isolates.drain-timeout`), runs its `@PreDestroy` methods and
/// ends. Its event streams and WebSocket sessions are closed; clients
/// connect again and reach another isolate. The application's first
/// isolate is never removed.
///
/// Every step is logged (`Scaling 2 → 4 isolates (manual)`).
///
/// Spring has no counterpart; nearest is changing a pool's size over JMX.
abstract interface class IsolateScaler {
  /// The isolates serving now, the first one included.
  int get count;

  /// The fewest [scaleTo] goes down to (`server.isolates.min`).
  int get min;

  /// The most [scaleTo] goes up to (`server.isolates.max`).
  int get max;

  /// Brings the pool to [count] isolates, kept between [min] and [max],
  /// and completes with how many serve once the new ones are ready and
  /// the removed ones have ended (their requests finished, or
  /// `server.isolates.drain-timeout` passed). [reason] is for the log.
  ///
  /// It works in every isolate: asked in another one than the first, the
  /// step is done by the pool there, in the first.
  Future<int> scaleTo(int count, {String reason = 'manual'});

  /// Adds [delta] isolates, or removes them when it is negative.
  Future<int> scaleBy(int delta, {String reason = 'manual'});
}

/// What a scaling policy sees every few seconds: the pool and how its
/// isolates are doing.
final class IsolateScalingState {
  /// The pool's state.
  const IsolateScalingState({
    required this.count,
    required this.min,
    required this.max,
    required this.lag,
    required this.maxLag,
    required this.activeRequests,
    required this.requestsPerSecond,
  });

  /// The isolates serving.
  final int count;

  /// The fewest allowed.
  final int min;

  /// The most allowed.
  final int max;

  /// How late the isolates' event loops run, on average over them.
  final Duration lag;

  /// The longest lag any isolate measured.
  final Duration maxLag;

  /// The requests in flight, all isolates together.
  final int activeRequests;

  /// The requests taken per second, all isolates together.
  final double requestsPerSecond;
}

/// Decides how many isolates the pool should have, with
/// `server.isolates.scaling: auto`. Declare a bean of your own to replace
/// [LagScalingPolicy].
abstract interface class IsolateScalingPolicy {
  /// The number of isolates wanted for [state] seen at [now], or `null`
  /// to leave the pool as it is. The pool keeps the answer between its
  /// `min` and `max` and waits `server.isolates.cooldown` between steps.
  int? decide(IsolateScalingState state, Duration now);
}

/// The default policy: by how late the isolates are.
///
/// An isolate does one thing at a time. While it keeps up, its timers
/// fire on time; when requests arrive faster than it answers, they queue
/// and its event loop runs late ([IsolateLoad.lag]). So:
///
/// - **up**: the average lag stays at [scaleUpLag] or more for
///   [scaleUpAfter]: half as many isolates again are added (1 → 2 → 3 →
///   5 → 8). The requests per second each isolate took at that moment
///   are remembered as what one isolate can take;
/// - **down**: the lag stays under a quarter of [scaleUpLag] for
///   [scaleDownAfter], and the requests now would fit in one isolate
///   less at 60 % of what one can take (or, while that is not known,
///   fewer requests are in flight than isolates): one isolate is
///   removed.
///
/// The lag of an isolate answering short requests is about the requests
/// waiting at that moment, so it grows with the connections that send
/// them: a server saturated through a handful of connections stays under
/// the threshold and is not scaled. Lower [scaleUpLag] for such traffic,
/// or give the pool a policy of your own.
///
/// Lag shows overload late, when requests already wait, and not how close
/// an isolate is to it: a compiled program cannot ask how much processor
/// time its isolates use. So it scales up only once it is needed, and the
/// first seconds of a sudden peak are slow; keep `server.isolates.min`
/// high enough for the load expected.
final class LagScalingPolicy implements IsolateScalingPolicy {
  /// The policy with its thresholds.
  LagScalingPolicy({
    this.scaleUpLag = const Duration(milliseconds: 5),
    this.scaleUpAfter = const Duration(seconds: 5),
    this.scaleDownAfter = const Duration(minutes: 2),
  });

  /// The average lag that means overload.
  final Duration scaleUpLag;

  /// How long it must last.
  final Duration scaleUpAfter;

  /// How long the pool must be free before it shrinks.
  final Duration scaleDownAfter;

  Duration? _lateSince;
  Duration? _freeSince;

  /// The requests per second one isolate took when the pool was last
  /// overloaded; `null` before that.
  double? capacity;

  @override
  int? decide(IsolateScalingState state, Duration now) {
    if (state.lag >= scaleUpLag) {
      _freeSince = null;
      final since = _lateSince ??= now;
      if (now - since < scaleUpAfter) {
        return null;
      }
      _lateSince = null;
      if (state.count > 0 && state.requestsPerSecond > 0) {
        final each = state.requestsPerSecond / state.count;
        capacity = capacity == null ? each : (capacity! + each) / 2;
      }
      return state.count + (state.count + 1) ~/ 2;
    }
    _lateSince = null;
    if (state.lag * 4 >= scaleUpLag || state.count <= state.min) {
      _freeSince = null;
      return null;
    }
    final each = capacity;
    final fits = each == null
        ? state.activeRequests < state.count
        : state.requestsPerSecond < 0.6 * each * (state.count - 1);
    if (!fits) {
      _freeSince = null;
      return null;
    }
    final since = _freeSince ??= now;
    if (now - since < scaleDownAfter) {
      return null;
    }
    _freeSince = null;
    return state.count - 1;
  }
}
