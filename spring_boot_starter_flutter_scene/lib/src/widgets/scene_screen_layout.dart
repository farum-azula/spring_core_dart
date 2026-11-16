import 'package:flutter/rendering.dart';

/// Where a scene's frame goes on the engine's canvas, in the canvas's
/// pixels from its top left: the scene's rectangle and the part of it
/// that shows; [target] is what holds the frame.
typedef ScenePiece<T> = ({
  T target,
  double left,
  double top,
  double right,
  double bottom,
  int clipLeft,
  int clipTop,
  int clipRight,
  int clipBottom,
});

/// The arithmetic of the engine's canvas (`spring.flutter.scene.canvas:
/// engine`), apart from the browser: where the canvas stands, where each
/// scene goes on it, what shows of it, in which order.
abstract final class SceneScreenLayout {
  /// [box]'s rectangle on the screen, in logical pixels.
  static Rect areaOf(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );

  /// Whether [box] covers a screen of [screen] logical pixels (a pixel
  /// short on an edge still covers it): the canvas can stand behind the
  /// whole page then.
  static bool fills(RenderBox box, Size screen) {
    if (screen.isEmpty) {
      return false;
    }
    final area = areaOf(box).inflate(1);
    return area.contains(Offset.zero) &&
        area.contains(screen.bottomRight(Offset.zero));
  }

  /// The part of [rect], [box]'s on the screen, that the boxes around it
  /// let show: a scrolled list clips what it scrolls, a `ClipRect` its
  /// child.
  static Rect shown(RenderObject box, Rect rect) {
    var shown = rect;
    var child = box;
    var parent = child.parent;
    while (parent != null) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        shown = shown.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
      parent = child.parent;
    }
    return shown;
  }

  /// Where [target]'s scene, filling [box], goes on a canvas over [area]
  /// (the canvas's rectangle on the screen) at [ratio] device pixels a
  /// logical one; `null` when none of it shows. The scene's edges fall on
  /// whole pixels, so a frame drawn at the device's ratio lands pixel for
  /// pixel.
  static ScenePiece<T>? piece<T>(
    T target,
    RenderBox box, {
    required Rect area,
    required double ratio,
  }) {
    final rect = areaOf(box);
    final visible = shown(box, rect).intersect(area);
    if (visible.width <= 0 || visible.height <= 0) {
      return null;
    }
    double x(double value) => (value - area.left) * ratio;
    double y(double value) => (value - area.top) * ratio;
    final left = x(rect.left).roundToDouble();
    final top = y(rect.top).roundToDouble();
    return (
      target: target,
      left: left,
      top: top,
      right: left + (rect.width * ratio).roundToDouble(),
      bottom: top + (rect.height * ratio).roundToDouble(),
      clipLeft: x(visible.left).floor(),
      clipTop: y(visible.top).floor(),
      clipRight: x(visible.right).ceil(),
      clipBottom: y(visible.bottom).ceil(),
    );
  }

  /// [places] in the order they are painted, by [depth] (an element's in
  /// the tree): a view around another first, those of one depth as they
  /// came.
  static List<T> painted<T>(List<T> places, int Function(T place) depth) {
    final indexed = [
      for (var i = 0; i < places.length; i++)
        (place: places[i], index: i, depth: depth(places[i])),
    ];
    indexed.sort(
      (a, b) => a.depth != b.depth
          ? a.depth.compareTo(b.depth)
          : a.index.compareTo(b.index),
    );
    return [for (final entry in indexed) entry.place];
  }
}
