import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:vector_math/vector_math.dart';

/// A colour of the app (sRGB, as the theme and `Color` have it) as the
/// light a scene works in. The engine's materials take linear light: an
/// sRGB value given as it is comes out pale and too bright.
///
/// ```dart
/// material.parameters.setVector3('tint', context.theme.colors.primary.linear);
/// ```
extension SceneColor on Color {
  /// The colour in linear light: red, green, blue.
  Vector3 get linear => Vector3(_linear(r), _linear(g), _linear(b));

  /// The colour in linear light with its opacity.
  Vector4 get linearWithAlpha => Vector4(_linear(r), _linear(g), _linear(b), a);

  static double _linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}
