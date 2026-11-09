import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_chart.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_observations.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_view.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_trace.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// The debug timeline (the `debugTimeline` bean): a pill over the app with
/// how long the start took and the last observation, and, a tap on it
/// away, the whole start as a waterfall, the observations and the events
/// ([TimelineView], shown by [DebugTimelineHost]).
///
/// The action `debug.timeline` shows or hides the pill: by default ⌘⇧L
/// (Ctrl+Shift+L) or five quick taps and a sixth held two seconds;
/// `spring.flutter.shortcuts.debug.timeline` names other keys or taps. The
/// debug panel's Timeline tab switches it too.
class DebugTimeline extends ChangeNotifier
    implements KeyedShortcutHandler, DebugOverlay {
  /// The timeline of [trace] and [observations], hidden, in the corner
  /// [position].
  DebugTimeline({
    required this.trace,
    required this.observations,
    this._position = DebugOverlayCorner.bottomLeft,
  });

  /// The start's steps.
  final SplashTrace trace;

  /// The observations' stats.
  final TimelineObservations observations;

  DebugOverlayCorner _position;
  bool _shown = false;
  bool _expanded = false;

  @override
  String get action => 'debug.timeline';

  @override
  List<String> get keys => const ['primary+shift+l', 'taps:6+hold:2s'];

  @override
  bool handle(ShortcutInvocation invocation) {
    shown = !shown;
    return true;
  }

  @override
  String get id => 'timeline';

  @override
  String get title => 'Timeline';

  @override
  DebugOverlayCorner get corner => _position;

  /// Moves the pill to [value].
  set corner(DebugOverlayCorner value) {
    if (value != _position) {
      _position = value;
      notifyListeners();
    }
  }

  @override
  int get order => 10;

  @override
  bool get shown => _shown;

  /// Shows or hides the pill; hiding it closes the full view too.
  @override
  set shown(bool value) {
    if (value != _shown || (!value && _expanded)) {
      _shown = value;
      if (!value) {
        _expanded = false;
      }
      notifyListeners();
    }
  }

  /// Whether the full view shows over the app.
  bool get expanded => _expanded;

  set expanded(bool value) {
    if (value != _expanded) {
      _expanded = value;
      notifyListeners();
    }
  }

  @override
  Size get size => const Size(220, 48);

  @override
  Widget build(BuildContext context) => DebugTimelinePill(timeline: this);

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

/// The timeline's pill: when the context was ready and when the app
/// showed, from the page's start, and the last observation with its
/// recent durations; a tap opens the full view.
class DebugTimelinePill extends StatelessWidget {
  /// The pill of [timeline].
  const DebugTimelinePill({required this.timeline, super.key});

  /// The timeline.
  final DebugTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.maybeOf(context);
    final colors = theme?.colorScheme;
    final foreground = colors?.onSurface ?? const Color(0xFFFFFFFF);
    final accent = colors?.primary ?? const Color(0xFF4FC3F7);
    final background = (colors?.surface ?? const Color(0xFF000000)).withValues(
      alpha: 0.85,
    );
    final text =
        (theme?.textStyle('labelsmall') ?? const TextStyle(fontSize: 11))
            .copyWith(color: foreground, height: 1.3);
    final stages = timeline.trace.stages;
    return GestureDetector(
      onTap: () => timeline.expanded = !timeline.expanded,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: timeline.size.width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([stages, timeline.observations]),
          builder: (context, _) {
            final last = timeline.observations.last;
            final recent = last == null
                ? const <Duration>[]
                : timeline.observations.stats[last.name]?.recent ?? const [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⏱ start ${formatTimelineDuration(stages.at(SplashStage.ready))}'
                  ' · app ${formatTimelineDuration(stages.at(SplashStage.app))}',
                  style: text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        last == null
                            ? 'no observations'
                            : '${last.contextualName ?? last.name} '
                                  '${formatTimelineDuration(last.duration)}',
                        style: text.copyWith(
                          color: last?.error == null
                              ? foreground.withValues(alpha: 0.75)
                              : colors?.error ?? const Color(0xFFF44336),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (recent.length > 1)
                      SizedBox(
                        width: 48,
                        height: 12,
                        child: TimelineSparkline(
                          [for (final d in recent) d.inMicroseconds / 1000],
                          color: accent,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Puts the timeline's full view over the app ([DebugTimelineHost]).
final class DebugTimelineCustomizer implements FlutterAppCustomizer, Ordered {
  /// The host of [timeline].
  const DebugTimelineCustomizer(this.timeline);

  /// The timeline.
  final DebugTimeline timeline;

  /// After the dock (`100`), so the full view is over the overlays.
  @override
  int get order => 200;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => DebugTimelineHost(
      timeline: timeline,
      child: inner == null ? child! : inner(context, child),
    );
  }
}

/// [child] with the timeline's full view over it while it is
/// [DebugTimeline.expanded]: a sheet over the whole screen on a narrow
/// one (under 700 wide), a panel on the right (420 wide) on a wide one.
class DebugTimelineHost extends StatelessWidget {
  /// [child] under the full view of [timeline].
  const DebugTimelineHost({
    required this.timeline,
    required this.child,
    super.key,
  });

  /// Below this width the view is a sheet over the whole screen.
  static const double narrow = 700;

  /// The width of the side panel on a wide screen.
  static const double panelWidth = 420;

  /// The timeline.
  final DebugTimeline timeline;

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: timeline,
    child: child,
    builder: (context, app) => Stack(
      fit: StackFit.expand,
      children: [
        app!,
        if (timeline.expanded)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, room) => room.maxWidth < narrow
                  ? Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.maybePaddingOf(context)?.top ?? 0,
                      ),
                      child: _FullView(
                        timeline: timeline,
                        radius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: panelWidth,
                        height: room.maxHeight,
                        child: _FullView(timeline: timeline),
                      ),
                    ),
            ),
          ),
      ],
    ),
  );
}

class _FullView extends StatelessWidget {
  const _FullView({required this.timeline, this.radius});

  final DebugTimeline timeline;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Container(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: radius,
        border: radius == null
            ? Border(left: BorderSide(color: style.line))
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Timeline', style: style.title)),
                  DebugChip(
                    'Close',
                    onTap: () => timeline.expanded = false,
                  ),
                ],
              ),
              Expanded(child: TimelineView(timeline: timeline)),
            ],
          ),
        ),
      ),
    );
  }
}
