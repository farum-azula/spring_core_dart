import 'package:flutter/widgets.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// A color with its name under it.
class Swatch extends StatelessWidget {
  const Swatch(this.name, this.color, {super.key});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: theme.colors.outline,
                width: theme.tokens.neon.borderWidth,
              ),
              borderRadius: BorderRadius.circular(theme.tokens.neon.radius),
            ),
          ),
          SizedBox(height: theme.spacing.xs),
          Text(
            name,
            style: theme.typography.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
