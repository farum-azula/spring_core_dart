import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';

/// Upper-case small text.
class NeonLabel extends StatelessWidget {
  const NeonLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.theme.typography.labelSmall.copyWith(
      color: color ?? context.theme.colors.onSurfaceVariant,
    ),
  );
}
