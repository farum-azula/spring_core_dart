/// A moment read on a clock and on a monotonic [Stopwatch], to measure a
/// pause or a cache's lifetime from it.
///
/// The wall clock can be set back (by hand, or a time server): a pause
/// measured on it alone, `now - at < pause`, then lasts as long again (a
/// cached error served for hours, logins blocked). The stopwatch is not
/// moved by that. The clock still counts so that tests can move theirs.
final class Since {
  /// The moment [at] of the clock, and now on a new stopwatch.
  Since(this.at) : _stopwatch = Stopwatch()..start();

  /// The clock's time of the moment.
  final DateTime at;

  final Stopwatch _stopwatch;

  /// Whether [length] has passed since the moment: on the stopwatch, or
  /// on the clock, which reads [now]. A clock that went back past [at]
  /// tells nothing: that counts as passed.
  bool passed(Duration length, DateTime now) {
    final byClock = now.difference(at);
    return _stopwatch.elapsed >= length ||
        byClock.isNegative ||
        byClock >= length;
  }
}
