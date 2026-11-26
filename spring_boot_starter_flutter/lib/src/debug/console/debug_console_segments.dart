import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/debug_isolates.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_filter.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/debug_timeline.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_chart.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_stats.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';

// The framework's segments of the debug console's header.

/// `fps`: the frames a second Flutter draws (`fps 60`, `fps idle`), from
/// [frames], measured while the console shows.
final class FpsSegment extends DebugConsoleSegment {
  /// The segment of [frames].
  const FpsSegment(this.frames);

  /// The frames, shared with `frames-lost`.
  final FrameStats frames;

  @override
  void Function() start(void Function() changed) {
    frames.addListener(changed);
    return () => frames.removeListener(changed);
  }

  @override
  DebugConsoleValue? read() => switch (frames.reading) {
    null => null,
    FrameReading(idle: true) => const DebugConsoleValue(
      'idle',
      label: 'fps',
      tone: DebugConsoleTone.text,
    ),
    final reading => DebugConsoleValue('${reading.rate}', label: 'fps'),
  };
}

/// `frames-lost`: how many frames of the last second were over the
/// budget (`lost 0`), green without one, red with one over twice the
/// budget, else amber.
final class FramesLostSegment extends DebugConsoleSegment {
  /// The segment of [frames].
  const FramesLostSegment(this.frames);

  /// The frames, shared with `fps`.
  final FrameStats frames;

  @override
  void Function() start(void Function() changed) {
    frames.addListener(changed);
    return () => frames.removeListener(changed);
  }

  @override
  DebugConsoleValue? read() => switch (frames.reading) {
    null => null,
    final reading => DebugConsoleValue(
      '${reading.lost}',
      label: 'lost',
      tone: switch (reading.status) {
        FrameStatus.good => DebugConsoleTone.good,
        FrameStatus.warning => DebugConsoleTone.warning,
        FrameStatus.bad => DebugConsoleTone.bad,
      },
    ),
  };
}

/// `filter`: the filter the records show by (`logs info "cart"`), the
/// debug panel's Logs tab's.
final class FilterSegment extends DebugConsoleSegment {
  /// The segment of [filter].
  const FilterSegment(this.filter);

  /// The filter.
  final DebugLogFilter filter;

  @override
  void Function() start(void Function() changed) {
    filter.addListener(changed);
    return () => filter.removeListener(changed);
  }

  @override
  DebugConsoleValue read() {
    final level = debugLogLevels
        .where((entry) => entry.$2 == filter.level)
        .map((entry) => entry.$1.toLowerCase())
        .firstOrNull;
    return DebugConsoleValue(
      [?level, if (filter.text.isNotEmpty) '"${filter.text}"'].join(' '),
      label: 'logs',
      tone: DebugConsoleTone.text,
    );
  }
}

/// `isolates`: how many isolates and engine threads there are and how
/// busy the busiest is (`isolates 4 · 12%`), read only while the console
/// shows; in the build only with the task manager
/// (`spring.flutter.debug.isolates.enabled`).
final class IsolatesSegment extends DebugConsoleSegment {
  /// The segment of [isolates].
  const IsolatesSegment(this.isolates);

  /// The task manager.
  final DebugIsolates isolates;

  @override
  void Function() start(void Function() changed) {
    final rows = isolates.rows..addListener(changed);
    return () => rows.removeListener(changed);
  }

  @override
  DebugConsoleValue? read() {
    final rows = isolates.rows.value;
    if (rows.isEmpty) {
      return null;
    }
    double? busiest;
    for (final row in rows) {
      if (row.busy case final busy? when busiest == null || busy > busiest) {
        busiest = busy;
      }
    }
    return DebugConsoleValue(
      '${rows.length} · ${formatIsolateBusy(busiest)}',
      label: 'isolates',
    );
  }
}

/// `timeline`: how long the start took until the app showed
/// (`start 840ms`); in the build only with the timeline
/// (`spring.flutter.debug.timeline.enabled`).
final class TimelineSegment extends DebugConsoleSegment {
  /// The segment of [timeline].
  const TimelineSegment(this.timeline);

  /// The timeline.
  final DebugTimeline timeline;

  @override
  void Function() start(void Function() changed) {
    final stages = timeline.trace.stages..addListener(changed);
    return () => stages.removeListener(changed);
  }

  @override
  DebugConsoleValue? read() {
    final at = timeline.trace.stages.at(SplashStage.app);
    return at == null
        ? null
        : DebugConsoleValue(formatTimelineDuration(at), label: 'start');
  }
}
