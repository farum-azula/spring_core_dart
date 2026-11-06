import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// A button, filled (`styles.neon-button`) or outlined
/// (`styles.neon-button-outline`). Hover, focus, press and disabled
/// (`onPressed == null`) come from the style; there is no state in Dart.
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = theme.typography.labelLarge;
    Widget face(
      double height,
      double radius,
      Color fill,
      Color border,
      double borderWidth,
      Color color,
    ) => Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border, width: borderWidth),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(label.toUpperCase(), style: text.copyWith(color: color)),
    );
    return filled
        ? ThemeStates(
            style: theme.styles.neonButton,
            onPressed: onPressed,
            builder: (context, s) => face(
              s.height,
              s.radius,
              s.fill,
              s.border,
              s.borderWidth,
              s.text,
            ),
          )
        : ThemeStates(
            style: theme.styles.neonButtonOutline,
            onPressed: onPressed,
            builder: (context, s) => face(
              s.height,
              s.radius,
              s.fill,
              s.border,
              s.borderWidth,
              s.text,
            ),
          );
  }
}
