import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage_event.dart';

/// The stages of the start (the `splashStages` bean): the current one as a
/// [ValueListenable], and when each was reached. `SpringApplicationWidget`
/// moves it on; a loader reads it in `LoaderFrame.stage`; listeners get a
/// [SplashStageEvent] for each stage.
///
/// A stage is reached once; the current one is the latest of the stages
/// reached, so a stage reached late (the splash's first frame drawn while
/// the beans are made) is recorded without going back.
class SplashStages extends ChangeNotifier
    implements ValueListenable<SplashStage> {
  /// The stages from [at]'s zero; [reached] are stages already reached
  /// before (the web page's, with their times).
  SplashStages({
    Duration Function()? clock,
    Map<SplashStage, Duration> reached = const {},
  }) : _clock = clock ?? _stopwatch(reached) {
    for (final MapEntry(:key, :value) in reached.entries) {
      _reached[key] = value;
    }
  }

  // A clock that goes on from the page's last stage.
  static Duration Function() _stopwatch(Map<SplashStage, Duration> reached) {
    final offset = reached.values.fold(
      Duration.zero,
      (latest, at) => at > latest ? at : latest,
    );
    final watch = Stopwatch()..start();
    return () => offset + watch.elapsed;
  }

  final Duration Function() _clock;
  final _reached = <SplashStage, Duration>{};
  ApplicationEventPublisher? _publisher;

  @override
  SplashStage get value => _reached.isEmpty
      ? SplashStage.splash
      : _reached.keys.reduce((a, b) => a.index >= b.index ? a : b);

  /// When each stage reached was reached, in the stages' order.
  Map<SplashStage, Duration> get reached => {
    for (final stage in SplashStage.values) stage: ?_reached[stage],
  };

  /// When [stage] was reached; `null` before.
  Duration? at(SplashStage stage) => _reached[stage];

  /// The time from the start now.
  Duration get now => _clock();

  /// Records [stage] as reached now. The stages only go forward: a stage
  /// reached before, or one behind a later stage reached (`splash` after
  /// `app` when no splash showed), is not recorded.
  void enter(SplashStage stage) {
    if (_reached.keys.any((reached) => reached.index >= stage.index)) {
      return;
    }
    final at = _clock();
    _reached[stage] = at;
    _publisher?.publishEvent(SplashStageEvent(this, stage: stage, at: at));
    notifyListeners();
  }

  /// From now on, every stage is published through [publisher]; the stages
  /// reached before are published first, in order.
  void publishTo(ApplicationEventPublisher publisher) {
    if (_publisher != null) {
      return;
    }
    _publisher = publisher;
    for (final MapEntry(:key, :value) in reached.entries) {
      publisher.publishEvent(SplashStageEvent(this, stage: key, at: value));
    }
  }
}
