/// The corner of the screen a debug tool shows in: the frame meter
/// (`spring.flutter.frame-meter.position`), the console
/// (`spring.flutter.debug.console.position`) and every other debug
/// overlay.
enum DebugCorner {
  /// Top left.
  topLeft,

  /// Top right.
  topRight,

  /// Bottom left.
  bottomLeft,

  /// Bottom right.
  bottomRight,
}

/// The layout the debug tools share.
abstract final class DebugLayout {
  /// A screen narrower than this is a phone's: the console takes all of
  /// its width, the debug panel lays its tabs out for a phone.
  static const double phoneWidth = 600;
}
