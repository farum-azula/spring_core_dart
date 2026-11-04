import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';

/// The accent of a badge. The colors are `tokens.neon.tone.*` and their soft
/// fills `tokens.neon.tone-soft.*` (a color object: `alpha: 12%`).
enum NeonTone {
  /// The theme's primary color.
  accent,
  cyan,
  pink,
  lavender,
  green;

  /// The strong color: the border and the text.
  Color color(BuildContext context) {
    final tone = context.theme.tokens.neon.tone;
    return switch (this) {
      accent => tone.accent,
      cyan => tone.cyan,
      pink => tone.pink,
      lavender => tone.lavender,
      green => tone.green,
    };
  }

  /// The soft color: the fill.
  Color soft(BuildContext context) {
    final tone = context.theme.tokens.neon.toneSoft;
    return switch (this) {
      accent => tone.accent,
      cyan => tone.cyan,
      pink => tone.pink,
      lavender => tone.lavender,
      green => tone.green,
    };
  }
}
