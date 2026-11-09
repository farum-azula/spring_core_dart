import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';

/// The frames: the frame meter turned on or off over the running app, and
/// its corner, without a new build. Without the meter in the build
/// (`spring.flutter.debug.frame-meter.enabled`) it says so.
final class DebugFramesSection implements DebugPanelSection, Ordered {
  /// The section of [meter]'s switch, `null` when the build left it out.
  const DebugFramesSection(this.meter);

  /// The switch.
  final DebugFrameMeter? meter;

  @override
  String get title => 'Frames';

  @override
  int get order => 10;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final meter = this.meter;
    if (meter == null) {
      return Text(
        'The frame meter is not in this build '
        '(spring.flutter.debug.frame-meter.enabled).',
        style: style.text.copyWith(color: style.muted),
      );
    }
    return ListenableBuilder(
      listenable: meter,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Frame meter', style: style.title),
          const SizedBox(height: 8),
          // Live here: the overlays hide while the panel is open.
          const FrameMeterGauge(),
          const SizedBox(height: 12),
          Text(
            'On screen',
            style: style.text.copyWith(color: style.muted),
          ),
          const SizedBox(height: 6),
          Wrap(
            children: [
              DebugChip(
                meter.on ? 'On' : 'Off',
                selected: meter.on,
                onTap: () => meter.on = !meter.on,
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
                  selected: meter.position == position,
                  onTap: () => meter.position = position,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
