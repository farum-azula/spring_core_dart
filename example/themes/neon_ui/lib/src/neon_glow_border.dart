import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _fullTurn = 2 * math.pi;

/// A glowing border that turns around [child]. The look is
/// `tokens.neon.modal.border.*`; the turning is the animation
/// `animations.border-spin`, which ThemeAnimation plays (and holds still
/// when the system asks for less motion). Only the painter is code.
class NeonGlowBorder extends StatelessWidget {
  const NeonGlowBorder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final neon = context.theme.tokens.neon;
    final border = neon.modal.border;
    return ThemeAnimation(
      context.theme.animations.borderSpin,
      builder: (context, turn) => CustomPaint(
        foregroundPainter: _GlowBorderPainter(
          turn: turn,
          colors: border.colors,
          width: border.width,
          glow: border.glow,
          glowAlpha: border.glowAlpha.clamp(0, 1),
          radius: neon.radius,
        ),
        child: child,
      ),
    );
  }
}

class _GlowBorderPainter extends CustomPainter {
  _GlowBorderPainter({
    required this.turn,
    required this.colors,
    required this.width,
    required this.glow,
    required this.glowAlpha,
    required this.radius,
  }) : super(repaint: turn);

  final Animation<double> turn;
  final List<Color> colors;
  final double width;
  final double glow;
  final double glowAlpha;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0 || colors.isEmpty) {
      return;
    }
    final bounds = Offset.zero & size;
    final border = RRect.fromRectAndRadius(
      bounds.deflate(width / 2),
      Radius.circular(radius),
    );
    final shader = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(turn.value * _fullTurn),
    ).createShader(bounds);
    if (glow > 0 && glowAlpha > 0) {
      canvas.saveLayer(
        bounds.inflate(glow * 2),
        Paint()..color = Color.fromRGBO(0, 0, 0, glowAlpha),
      );
      canvas.drawRRect(
        border,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 2
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
      );
      canvas.restore();
    }
    canvas.drawRRect(
      border,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_GlowBorderPainter old) =>
      !listEquals(old.colors, colors) ||
      old.width != width ||
      old.glow != glow ||
      old.glowAlpha != glowAlpha ||
      old.radius != radius;
}
