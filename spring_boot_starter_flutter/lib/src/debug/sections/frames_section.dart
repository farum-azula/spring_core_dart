import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';

/// The frames: the frame meter turned on or off over the running app, and
/// its corner, without a new build.
final class DebugFramesSection implements DebugPanelSection, Ordered {
  /// The section of [panel]'s switches.
  const DebugFramesSection(this.panel);

  /// The switches.
  final DebugPanel panel;

  @override
  String get title => 'Frames';

  @override
  int get order => 10;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: panel,
    builder: (context, _) {
      final style = DebugStyle.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Frame meter', style: style.title),
          const SizedBox(height: 8),
          Wrap(
            children: [
              DebugChip(
                panel.frameMeter ? 'On' : 'Off',
                selected: panel.frameMeter,
                onTap: () => panel.frameMeter = !panel.frameMeter,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Corner', style: style.text.copyWith(color: style.muted)),
          const SizedBox(height: 6),
          Wrap(
            children: [
              for (final position in FrameMeterPosition.values)
                DebugChip(
                  position.name,
                  selected: panel.frameMeterPosition == position,
                  onTap: () => panel.frameMeterPosition = position,
                ),
            ],
          ),
        ],
      );
    },
  );
}
