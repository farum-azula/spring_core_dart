import 'dart:async';

/// A controlled clock and timers for TimerTaskScheduler tests.
final class FakeClock {
  FakeClock(this._now);

  DateTime _now;
  final _timers = <_FakeTimer>[];

  DateTime now() => _now;

  Timer timer(Duration delay, void Function() callback) {
    final timer = _FakeTimer(_now.add(delay), callback, this);
    _timers.add(timer);
    return timer;
  }

  int get pendingTimers => _timers.length;

  /// Moves time forward by [duration], firing due timers in time order
  /// (synchronous tasks only).
  void elapse(Duration duration) {
    final end = _now.add(duration);
    while (true) {
      final due = _nextDue(end);
      if (due == null) {
        break;
      }
      _fire(due);
    }
    _now = end;
  }

  /// Like [elapse], letting futures of asynchronous tasks complete between
  /// timers.
  Future<void> elapseAsync(Duration duration) async {
    final end = _now.add(duration);
    await _flush();
    while (true) {
      final due = _nextDue(end);
      if (due == null) {
        break;
      }
      _fire(due);
      await _flush();
    }
    _now = end;
    await _flush();
  }

  _FakeTimer? _nextDue(DateTime end) {
    _FakeTimer? first;
    for (final timer in _timers) {
      if (!timer.at.isAfter(end) &&
          (first == null || timer.at.isBefore(first.at))) {
        first = timer;
      }
    }
    return first;
  }

  void _fire(_FakeTimer timer) {
    _timers.remove(timer);
    if (timer.at.isAfter(_now)) {
      _now = timer.at;
    }
    timer.callback();
  }

  static Future<void> _flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.at, this.callback, this._clock);

  final DateTime at;
  final void Function() callback;
  final FakeClock _clock;

  @override
  void cancel() => _clock._timers.remove(this);

  @override
  bool get isActive => _clock._timers.contains(this);

  @override
  int get tick => 0;
}
