import 'package:flutter/widgets.dart';

/// Marks a subtree that is built but drawn somewhere else than where it
/// stands: a 3D scene's widgets, built under an `Offstage` and drawn on the
/// engine's canvas. The application graph's "On screen" scope counts a
/// widget under it by the place of the marked widget itself, not as
/// offstage.
///
/// A key, so marking costs nothing at run time: the scene starter puts it
/// on the `Offstage` it builds anyway, `Offstage(key: const
/// PaintedElsewhere(), child: view)`; only the debug tools read it, while
/// they show.
final class PaintedElsewhere extends LocalKey {
  /// The marker.
  const PaintedElsewhere();
}

/// Marks the subtree of a debug tool over the app (the debug panel, the
/// overlays of the dock): the application graph's widgets layer leaves it
/// out, as it is not the application's. A key on a widget the tool builds
/// anyway, so it costs nothing.
final class DebugToolSubtree extends LocalKey {
  /// The marker.
  const DebugToolSubtree();
}
