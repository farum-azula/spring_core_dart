import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/debug_timeline.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_view.dart';

/// The timeline in the debug panel: its pill shown on screen or not, and
/// the full view ([TimelineView]).
final class DebugTimelineSection implements DebugPanelSection, Ordered {
  /// The section of [timeline].
  const DebugTimelineSection(this.timeline);

  /// The timeline.
  final DebugTimeline timeline;

  @override
  String get title => 'Timeline';

  @override
  int get order => 55;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: timeline,
          builder: (context, _) => Row(
            children: [
              Text(
                'Show on screen ',
                style: style.text.copyWith(color: style.muted),
              ),
              const SizedBox(width: 6),
              DebugChip(
                timeline.shown ? 'On' : 'Off',
                selected: timeline.shown,
                onTap: () => timeline.shown = !timeline.shown,
              ),
            ],
          ),
        ),
        Expanded(child: TimelineView(timeline: timeline)),
      ],
    );
  }
}
