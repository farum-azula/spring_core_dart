import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// A tile that can be selected, in the style of this app's own YAML:
/// `styles.showcase-tile`. It is made with the same ThemeStates as the
/// widgets of neon_ui, and the style refers to the library's colors.
class StateTile extends StatelessWidget {
  const StateTile({
    required this.child,
    super.key,
    this.selected = false,
    this.onPressed,
  });

  final Widget child;
  final bool selected;

  /// Null: the tile is disabled (no hover, no press).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ThemeStates(
    style: context.theme.styles.showcaseTile,
    selected: selected,
    onPressed: onPressed,
    builder: (context, s) => Container(
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.fill,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(s.radius),
        boxShadow: [
          if (s.glow > 0)
            BoxShadow(
              color: s.border.withValues(alpha: 0.5),
              blurRadius: s.glow,
            ),
        ],
      ),
      child: child,
    ),
  );
}
