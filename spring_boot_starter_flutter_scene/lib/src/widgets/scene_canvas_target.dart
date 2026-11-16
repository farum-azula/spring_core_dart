import 'package:flutter/widgets.dart';

/// Where a view's frames go when Flutter does not draw them: a layer of
/// the scene's own (`canvas: layer`) or its place on the engine's canvas
/// (`canvas: engine`).
abstract interface class SceneCanvasTarget {
  /// What stands in the view for it.
  Widget build();

  /// Has the engine draw a frame by [draw] and puts it there; `false` when
  /// nothing was drawn.
  bool present(void Function() draw);

  /// The view is gone, or draws elsewhere.
  void dispose();
}
