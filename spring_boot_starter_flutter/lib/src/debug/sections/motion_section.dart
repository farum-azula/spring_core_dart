import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The motion: every animation of the running app on, or off as the
/// device's "reduce motion" turns it off, without a new build.
final class DebugMotionSection implements DebugPanelSection, Ordered {
  /// The section of [panel]'s switch.
  const DebugMotionSection(this.panel);

  /// The switch.
  final DebugPanel panel;

  @override
  String get title => 'Motion';

  @override
  int get order => 15;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: panel,
    builder: (context, _) {
      final style = DebugStyle.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Animations', style: style.title),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final on in [true, false])
                DebugChip(
                  on ? 'On' : 'Off',
                  selected: panel.animations == on,
                  onTap: () => panel.animations = on,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Off: every transition and change is instant, as with the '
            "device's reduce motion. The theme sets it for every build with "
            'motion.enabled.',
            style: style.text.copyWith(color: style.muted),
          ),
        ],
      );
    },
  );
}
