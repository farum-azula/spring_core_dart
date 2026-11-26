import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_observations.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_view.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_trace.dart';

/// The debug timeline (the `debugTimeline` bean): the whole start as a
/// waterfall, the observations and the events ([TimelineView]), in the
/// debug panel's Timeline tab; how long the start took is the debug
/// console's `timeline` segment.
final class DebugTimeline {
  /// The timeline of [trace] and [observations].
  DebugTimeline({required this.trace, required this.observations});

  /// The start's steps.
  final SplashTrace trace;

  /// The observations' stats.
  final TimelineObservations observations;

  /// The tab of the full view shown (Start, Observations, Events, by
  /// index), kept while the debug panel is closed.
  int viewTab = 0;

  /// The steps of the start, the stages and the observations' stats as
  /// JSON, times in milliseconds.
  Map<String, Object?> toJson() => {
    'stages': {
      for (final MapEntry(:key, :value) in trace.stages.reached.entries)
        key.name: value.inMicroseconds / 1000,
    },
    'steps': [
      for (final step in trace.steps)
        {
          'id': step.id,
          'parentId': ?step.parentId,
          'name': step.name,
          'startedAtMs': step.startedAt.inMicroseconds / 1000,
          if (step.duration case final duration?)
            'durationMs': duration.inMicroseconds / 1000,
          if (step.tags.isNotEmpty)
            'tags': {for (final (key, value) in step.tags) key: '$value'},
        },
    ],
    'observations': observations.toJson(),
  };
}
