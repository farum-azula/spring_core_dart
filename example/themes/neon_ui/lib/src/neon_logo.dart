import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';

/// The logo: the accent glowing, a pink and a cyan copy shifted behind it.
class NeonLogo extends StatelessWidget {
  const NeonLogo({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final neon = context.theme.tokens.neon;
    final style = context.theme.typography.displaySmall.copyWith(
      fontSize: neon.logoSize,
      height: 1,
    );
    Widget layer(Color color, double offset) => Transform.translate(
      offset: Offset(offset, 0),
      child: Text(text, style: style.copyWith(color: color)),
    );
    return Stack(
      children: [
        layer(neon.logoLayer, -neon.logoShift),
        layer(neon.logoLayerB, neon.logoShift),
        Text(
          text,
          style: style.copyWith(
            color: neon.accent,
            shadows: [Shadow(color: neon.glow, blurRadius: neon.glowBlur)],
          ),
        ),
      ],
    );
  }
}
