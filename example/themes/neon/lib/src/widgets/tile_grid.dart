import 'package:flutter/widgets.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// Tiles in as many columns as the width holds (each at least [minWidth]
/// wide), the theme's `spacing.m` between them. A row is as tall as its
/// tallest tile, so the text decides the height and is never cut off.
class TileGrid extends StatelessWidget {
  const TileGrid({required this.children, this.minWidth = 260, super.key});

  final List<Widget> children;

  /// The narrowest a tile gets before the grid drops a column.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final gap = context.theme.spacing.m;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
            .floor()
            .clamp(1, children.isEmpty ? 1 : children.length);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: gap,
          children: [
            for (var start = 0; start < children.length; start += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    for (final tile in children.skip(start).take(columns))
                      SizedBox(width: width, child: tile),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
