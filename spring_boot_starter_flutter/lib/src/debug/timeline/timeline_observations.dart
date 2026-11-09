import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The observations of one name: how many stopped, how long they took.
final class ObservationStats {
  /// The stats of [name], none stopped yet, keeping the last [history]
  /// durations.
  ObservationStats(this.name, {this.history = 30});

  /// The observation's name (`http.client.requests`).
  final String name;

  /// How many durations [recent] keeps.
  final int history;

  int _count = 0;
  Duration _total = Duration.zero;
  Duration _max = Duration.zero;
  Duration _last = Duration.zero;
  final _recent = ListQueue<Duration>();

  /// How many stopped.
  int get count => _count;

  /// All their durations added up.
  Duration get total => _total;

  /// Their average duration.
  Duration get average => _count == 0 ? Duration.zero : _total ~/ _count;

  /// The longest.
  Duration get max => _max;

  /// The latest.
  Duration get last => _last;

  /// The last durations, the oldest first.
  List<Duration> get recent => List.unmodifiable(_recent);

  void _add(Duration duration) {
    _count++;
    _total += duration;
    if (duration > _max) {
      _max = duration;
    }
    _last = duration;
    _recent.addLast(duration);
    while (_recent.length > history) {
      _recent.removeFirst();
    }
  }

  /// The stats as JSON, times in milliseconds.
  Map<String, Object?> toJson() => {
    'count': count,
    'averageMs': average.inMicroseconds / 1000,
    'maxMs': max.inMicroseconds / 1000,
    'lastMs': last.inMicroseconds / 1000,
    'recentMs': [for (final d in _recent) d.inMicroseconds / 1000],
  };
}

/// An observation that stopped.
@immutable
final class TimelineObservation {
  /// The observation [name], stopped after [duration].
  const TimelineObservation({
    required this.name,
    required this.startedAt,
    required this.duration,
    this.contextualName,
    this.error,
  });

  /// Its name.
  final String name;

  /// Its name in this call (`GET /todos`), if it has one.
  final String? contextualName;

  /// When it started, by the registry's clock.
  final Duration startedAt;

  /// How long it took.
  final Duration duration;

  /// What it failed with, if it did.
  final Object? error;

  /// The observation as JSON, times in milliseconds.
  Map<String, Object?> toJson() => {
    'name': name,
    'contextualName': ?contextualName,
    'startedAtMs': startedAt.inMicroseconds / 1000,
    'durationMs': duration.inMicroseconds / 1000,
    if (error != null) 'error': '$error',
  };
}

/// The observations of the app for the debug timeline: an
/// [ObservationHandler] of the `observationRegistry` that keeps, per name,
/// the count, the average, the longest and the last durations
/// ([ObservationStats]), and the latest observations ([recent]).
///
/// It notifies at most once per [interval], however many observations
/// stop.
class TimelineObservations extends ObservationHandler with ChangeNotifier {
  /// Stats keeping the last [history] durations of a name and the last
  /// [capacity] observations, notifying at most once per [interval].
  TimelineObservations({
    this.history = 30,
    this.capacity = 200,
    this.interval = const Duration(milliseconds: 300),
  });

  /// How many durations of a name are kept.
  final int history;

  /// How many observations [recent] keeps.
  final int capacity;

  /// The least time between two notifications.
  final Duration interval;

  final _stats = <String, ObservationStats>{};
  final _recent = ListQueue<TimelineObservation>();
  Timer? _pending;
  bool _disposed = false;

  /// The stats of each name.
  Map<String, ObservationStats> get stats => UnmodifiableMapView(_stats);

  /// The latest observations, the oldest first.
  List<TimelineObservation> get recent => List.unmodifiable(_recent);

  /// The observation that stopped last, `null` before any.
  TimelineObservation? get last => _recent.isEmpty ? null : _recent.last;

  @override
  void onStop(ObservationContext context) {
    final duration = context.duration;
    if (duration == null) {
      return;
    }
    (_stats[context.name] ??= ObservationStats(
      context.name,
      history: history,
    ))._add(duration);
    _recent.addLast(
      TimelineObservation(
        name: context.name,
        contextualName: context.contextualName,
        startedAt: context.startedAt ?? Duration.zero,
        duration: duration,
        error: context.error,
      ),
    );
    while (_recent.length > capacity) {
      _recent.removeFirst();
    }
    _changed();
  }

  /// Forgets every observation.
  void clear() {
    _stats.clear();
    _recent.clear();
    _changed();
  }

  void _changed() {
    if (_disposed) {
      return;
    }
    _pending ??= Timer(interval, () {
      _pending = null;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    super.dispose();
  }

  /// The stats and the latest observations as JSON.
  Map<String, Object?> toJson() => {
    'stats': {
      for (final MapEntry(:key, :value) in _stats.entries) key: value.toJson(),
    },
    'recent': [for (final o in _recent) o.toJson()],
  };
}
