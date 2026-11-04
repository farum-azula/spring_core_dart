import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';

/// A block of code (or any monospaced text).
class NeonCode extends StatelessWidget {
  const NeonCode(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: EdgeInsets.all(theme.spacing.m),
      decoration: BoxDecoration(
        color: theme.tokens.neon.code,
        border: Border.all(
          color: theme.colors.outlineVariant,
          width: theme.tokens.neon.borderWidth,
        ),
        borderRadius: BorderRadius.circular(theme.tokens.neon.radius),
      ),
      child: Text(
        text,
        style: theme.typography.code.copyWith(
          color: color ?? theme.colors.onSurface,
        ),
      ),
    );
  }
}
