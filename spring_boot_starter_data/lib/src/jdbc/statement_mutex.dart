import 'dart:async';

/// Runs one action at a time, in the order they were asked: how a driver's
/// connection keeps two statements started at once from interleaving on the
/// wire (or in its cursor).
final class StatementMutex {
  Future<void> _tail = Future.value();

  /// The action's turn: completes once the earlier ones are done; the
  /// returned function gives the turn up.
  Future<void Function()> acquire() {
    final done = Completer<void>();
    final turn = _tail.then(
      (_) =>
          () => done.complete(),
    );
    _tail = done.future;
    return turn;
  }

  /// Runs [action] in its turn.
  Future<T> run<T>(FutureOr<T> Function() action) async {
    final release = await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}
