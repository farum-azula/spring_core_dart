import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:neon_ui/src/neon_label.dart';
import 'package:neon_ui/src/neon_tone.dart';

/// A status badge: a soft fill and a border in the color of its [tone].
class NeonBadge extends StatelessWidget {
  const NeonBadge(this.text, {super.key, this.tone = NeonTone.accent});

  final String text;
  final NeonTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final color = tone.color(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.s,
        vertical: theme.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.soft(context),
        border: Border.all(color: color, width: theme.tokens.neon.borderWidth),
        borderRadius: BorderRadius.circular(theme.tokens.neon.radius),
      ),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: NeonLabel(text, color: color),
      ),
    );
  }
}
