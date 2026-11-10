// The server's isolates, for the scaling scenarios of the load tool: how
// many serve, how loaded each is, and a way to change their number while
// the load runs.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/bench/isolates')
class IsolatesController {
  IsolatesController(this._isolate, this._primary, this._scaler);

  final IsolateInfo _isolate;

  /// Asks the first isolate, which knows the load of all of them.
  final PrimaryIsolate _primary;

  /// Only where the server has a pool (`server.isolates.count` or `max`
  /// above 1, or automatic scaling).
  final IsolateScaler? _scaler;

  /// `GET /bench/isolates`: the isolate that answers, the pool's size and
  /// the load of every isolate. Any isolate answers for all: the loads
  /// come from the first one.
  @GetMapping()
  Future<IsolatesState> state() => _state();

  /// `POST /bench/isolates?to=3`: brings the pool to that many isolates
  /// and answers once the new ones serve and the removed ones have ended.
  /// 409 without a pool; 421 from an isolate that is not the first: ask
  /// again on a new connection.
  ///
  /// The scaler works in every isolate, but an isolate cannot answer for
  /// its own removal: its request would wait for the step, and the step
  /// for its requests to end. The first isolate is never removed.
  @PostMapping()
  Future<IsolatesState> scale(@RequestParam('to') int to) async {
    final scaler = _scaler;
    if (scaler == null) {
      throw ResponseStatusException(
        HttpStatus.conflict,
        'The server has no pool of isolates: set server.isolates.max (or '
        'server.isolates.count) above 1.',
      );
    }
    if (!_isolate.primary) {
      throw ResponseStatusException(
        HttpStatus.misdirectedRequest,
        '${_isolate.name} does not scale the pool here: ask the first '
        'isolate, on a new connection.',
      );
    }
    await scaler.scaleTo(to, reason: 'load bench');
    return await _state();
  }

  Future<IsolatesState> _state() async {
    final loads = await _primary.ask(IsolateLoadsHandler.handlerId);
    return IsolatesState(
      isolate: _isolate.name,
      primary: _isolate.primary,
      pool: _scaler != null,
      count: _scaler?.count ?? 1,
      min: _scaler?.min,
      max: _scaler?.max,
      loads: [
        for (final load in (loads as List?) ?? const <Object?>[])
          (load! as Map).cast<String, Object?>(),
      ],
    );
  }
}

/// The answer of `/bench/isolates`.
class IsolatesState {
  const IsolatesState({
    required this.isolate,
    required this.primary,
    required this.pool,
    required this.count,
    required this.min,
    required this.max,
    required this.loads,
  });

  /// The isolate that answered: `main`, `isolate-1`.
  final String isolate;

  /// Whether it is the application's first isolate.
  final bool primary;

  /// Whether the server has a pool that can be scaled.
  final bool pool;

  /// The isolates serving; `1` without a pool.
  final int count;

  /// The bounds of the pool; `null` without one.
  final int? min;
  final int? max;

  /// The load of each isolate (`IsolateLoad.toJson`): its event loop's
  /// lag, its requests in flight and, under `details`, the requests it
  /// has taken.
  final List<Map<String, Object?>> loads;
}
