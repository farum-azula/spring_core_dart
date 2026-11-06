import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:neon_ui/src/neon_label.dart';

/// A [child] with a label above it.
class NeonField extends StatelessWidget {
  const NeonField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      NeonLabel(label),
      SizedBox(height: context.theme.tokens.neon.labelGap),
      child,
    ],
  );
}
