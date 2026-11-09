import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_motion.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The motion: every animation of the running app on, or off as the
/// device's "reduce motion" turns it off, without a new build. Without
/// the switch in the build (`spring.flutter.debug.motion.enabled`) it
/// says so.
final class DebugMotionSection implements DebugPanelSection, Ordered {
  /// The section of [motion]'s switch, `null` when the build left it out.
  const DebugMotionSection(this.motion);

  /// The switch.
  final DebugMotion? motion;

  @override
  String get title => 'Motion';

  @override
  int get order => 15;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final motion = this.motion;
    if (motion == null) {
      return Text(
        'The motion switch is not in this build '
        '(spring.flutter.debug.motion.enabled).',
        style: style.text.copyWith(color: style.muted),
      );
    }
    return ListenableBuilder(
      listenable: motion,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Animations', style: style.title),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final on in [true, false])
                DebugChip(
                  on ? 'On' : 'Off',
                  selected: motion.animations == on,
                  onTap: () => motion.animations = on,
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
      ),
    );
  }
}
