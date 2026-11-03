import 'package:flutter/material.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

/// A color with its name and hex value, over a checkerboard so that a
/// see-through color (alpha) can be told from a solid one.
class Swatch extends StatelessWidget {
  const Swatch(this.color, this.label, {super.key, this.width = 132});

  final Color color;
  final String label;
  final double width;

  /// `#RRGGBB`, or `#RRGGBB @ 12%` for a color with alpha.
  static String hex(Color color) {
    final rgb = (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    return color.a >= 0.995 ? '#$rgb' : '#$rgb @ ${(color.a * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(context.theme.corner),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(context.theme.corner),
              ),
              child: CustomPaint(
                painter: _Checkerboard(colors.outlineVariant),
                child: ColoredBox(
                  color: color,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          SizedBox(height: context.theme.spacing.xs),
          Text(label, style: text.labelMedium, overflow: TextOverflow.ellipsis),
          Text(
            hex(color),
            style: context.theme.typography.code.copyWith(
              fontSize: 11,
              color: colors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _Checkerboard extends CustomPainter {
  const _Checkerboard(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.45);
    const cell = 8.0;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard old) => old.color != color;
}

extension on AppTheme {
  /// The corner of a swatch.
  double get corner => tokens.corner.tiny + 4;
}
