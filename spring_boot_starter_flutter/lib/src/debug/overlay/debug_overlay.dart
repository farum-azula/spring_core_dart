import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';

/// The corner a debug overlay shows in (`top-right`, `bottom-left`, …).
typedef DebugOverlayCorner = FrameMeterPosition;

/// A debug feature that can show a small widget over the app: the frame
/// meter, the timeline. The `debugDock` puts the overlays shown of one
/// corner together, in a stack or as pages to swipe ([DebugOverlayLayout]),
/// so they never cover each other; a feature only says where and what.
///
/// A bean; it notifies when it is shown or hidden, or moves.
///
/// Spring has no counterpart.
abstract interface class DebugOverlay implements Listenable {
  /// Its name, unique among the overlays (`frame-meter`): where a moved
  /// one is remembered.
  String get id;

  /// What the dock's page dots and the debug panel call it.
  String get title;

  /// The corner it shows in, until it is moved.
  DebugOverlayCorner get corner;

  /// Its place among the overlays of a corner: lower nearer the edge.
  int get order;

  /// Whether it is on screen.
  bool get shown;
  set shown(bool value);

  /// About how much room it takes: what `auto` adds up to choose between a
  /// stack and pages.
  Size get size;

  /// The widget, built only while [shown].
  Widget build(BuildContext context);
}

/// How the `debugDock` puts the overlays of one corner together
/// (`spring.flutter.debug.overlays.layout`).
enum DebugOverlayLayout {
  /// A stack when it fits in the corner's room (`max-height`, half the
  /// width), pages otherwise: a stack on a laptop, pages on a phone.
  auto,

  /// Always one under the other.
  stack,

  /// One at a time, the others a swipe (or a wheel turn, a dot) away.
  pages,
}

/// Where a debug overlay is placed when it can be moved: the debug feature
/// `drag` provides it; without it, an overlay stays in its corner.
abstract interface class DebugOverlayPlacement implements Listenable {
  /// The corner [overlay] was moved to, or its own.
  DebugOverlayCorner cornerOf(DebugOverlay overlay);

  /// Where [overlay] was left when it was moved freely (from the top left,
  /// a fraction of the screen each way); `null` when it is in a corner.
  Offset? freeOf(DebugOverlay overlay);

  /// [child], the widget of [overlay], made to be moved.
  Widget movable(DebugOverlay overlay, Widget child);

  /// Forgets every move: the overlays back in their own corners.
  void reset();
}
