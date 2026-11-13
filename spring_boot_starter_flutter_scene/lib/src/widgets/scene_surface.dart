import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

/// A widget's rectangle as a plane of the scene behind it: [size] in
/// logical pixels, the scene's origin in its middle, `+Y` up, a unit of
/// the scene [pixelsPerUnit] pixels. What a `SceneBackdrop` gives its
/// scene, so a mesh is laid out by the widget's own pixels.
@immutable
final class SceneSurface {
  /// The plane of a widget of [size].
  const SceneSurface(this.size, {this.pixelsPerUnit = 100});

  /// The widget's size, in logical pixels.
  final Size size;

  /// How many pixels a unit of the scene is.
  final double pixelsPerUnit;

  /// The width in the scene's units.
  double get width => size.width / pixelsPerUnit;

  /// The height in the scene's units.
  double get height => size.height / pixelsPerUnit;

  /// A point of the widget (pixels from its top-left corner) in the
  /// scene, [depth] units behind the widget's plane.
  Vector3 toScene(Offset point, {double depth = 0}) => Vector3(
    (point.dx - size.width / 2) / pixelsPerUnit,
    (size.height / 2 - point.dy) / pixelsPerUnit,
    depth,
  );

  /// A length in pixels as a length of the scene.
  double length(double pixels) => pixels / pixelsPerUnit;

  @override
  bool operator ==(Object other) =>
      other is SceneSurface &&
      other.size == size &&
      other.pixelsPerUnit == pixelsPerUnit;

  @override
  int get hashCode => Object.hash(size, pixelsPerUnit);
}
