import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// A pill that can be selected: `styles.neon-chip`.
class NeonChip extends StatelessWidget {
  const NeonChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;

  /// Null: the chip is disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ThemeStates(
    style: context.theme.styles.neonChip,
    selected: selected,
    onPressed: onPressed,
    builder: (context, s) => Container(
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.fill,
        border: Border.all(color: s.border, width: s.borderWidth),
        borderRadius: BorderRadius.circular(s.radius),
      ),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: context.theme.typography.labelMedium.copyWith(color: s.text),
        ),
      ),
    ),
  );
}
