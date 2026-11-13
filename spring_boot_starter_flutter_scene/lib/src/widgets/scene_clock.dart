import 'package:clock/clock.dart';

/// The time a scene runs by: the wall's, without the stretches the scene
/// stood paused. A view that comes back to the screen after a minute
/// then moves on by one frame, not by a minute: the engine steps its
/// components, animations and physics by the time between two ticks.
final class SceneClock {
  Duration _held = Duration.zero;
  DateTime? _pausedAt;

  /// The clock the engine's view reads.
  late final Clock clock = Clock(_now);

  /// Whether the time stands.
  bool get paused => _pausedAt != null;

  set paused(bool value) {
    if (value == paused) {
      return;
    }
    if (value) {
      _pausedAt = DateTime.now();
    } else {
      _held += DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
    }
  }

  DateTime _now() => (_pausedAt ?? DateTime.now()).subtract(_held);
}
