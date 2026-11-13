import 'package:signals_core/signals_core.dart' as signals;

/// Keeps what a run followed (the body of a computed value, of an effect,
/// of a widget's build), so that a run that fails does not lose it.
///
/// A run follows what it reads, and each run starts from nothing. One that
/// throws before it read anything (it was refused, something was not
/// ready) would follow nothing from then on, and never run again: an
/// effect that died without a word, a value that kept its failure for
/// ever. After a run that fails, the keeper follows again what the last
/// run that succeeded followed, so the next change of any of it runs the
/// body again.
final class FollowKeeper {
  static List<void Function()>? _recording;

  List<void Function()> _kept = const [];

  /// Notes that the run of the moment follows what [follow] reads;
  /// [follow] is called again after a later run of it fails. Called by
  /// every followed read.
  static void note(void Function() follow) => _recording?.add(follow);

  /// Runs [body] with nothing noted: for a read that is not followed.
  static T unnoted<T>(T Function() body) {
    final outer = _recording;
    _recording = null;
    try {
      return body();
    } finally {
      _recording = outer;
    }
  }

  /// Runs [body], noting what it follows. When it throws, what the last
  /// run that did not throw followed is followed again, and the error
  /// goes on.
  T run<T>(T Function() body) {
    final outer = _recording;
    final mine = _recording = <void Function()>[];
    try {
      final result = body();
      _kept = mine;
      return result;
    } on Object {
      _recording = null;
      for (final follow in _kept) {
        try {
          follow();
        } on Object {
          // A member that is gone, or a value that fails itself: there
          // is nothing of it to follow.
        }
      }
      rethrow;
    } finally {
      _recording = outer;
    }
  }
}

/// Runs [body] without the reader being told of what it reads: an effect
/// or a computed value that reads a field inside it does not run again
/// when that field changes.
///
/// ```dart
/// @Effect()
/// void save() {
///   final user = untracked(() => session.user);   // read, not followed
///   storage.write(user, items);
/// }
/// ```
T untracked<T>(T Function() body) =>
    FollowKeeper.unnoted(() => signals.untracked(body));
