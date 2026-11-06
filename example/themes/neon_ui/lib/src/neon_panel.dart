import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:neon_ui/src/neon_label.dart';

/// A translucent panel with a title and an accent mark. Its [child] fills
/// the rest, so give the panel a height.
class NeonPanel extends StatelessWidget {
  const NeonPanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.titleTrailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final neon = theme.tokens.neon;
    return Container(
      decoration: BoxDecoration(
        color: neon.panel,
        border: Border.all(color: neon.panelBorder, width: neon.borderWidth),
        borderRadius: BorderRadius.circular(neon.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(theme.spacing.m),
            child: Row(
              children: [
                Container(
                  width: neon.accentWidth,
                  height: neon.accentHeight,
                  color: neon.accent,
                ),
                SizedBox(width: theme.spacing.s),
                Expanded(
                  child: Row(
                    children: [
                      NeonLabel(title, color: theme.colors.onSurface),
                      if (titleTrailing case final actions?) ...[
                        SizedBox(width: theme.spacing.m),
                        actions,
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Container(
            height: neon.borderWidth,
            color: theme.colors.outlineVariant,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
