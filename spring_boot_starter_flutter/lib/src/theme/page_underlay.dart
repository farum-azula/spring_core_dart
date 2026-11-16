import 'package:flutter/foundation.dart';

/// What the browser shows under the app's page, behind Flutter's canvas,
/// covering the whole view: the canvas of the 3D scenes when they are
/// drawn on the engine's canvas (`spring.flutter.scene.canvas: engine`)
/// and the first of them fills the screen.
///
/// While one shows, the theme's background ([ThemeBackground] around the
/// navigator) draws nothing: it is under the page already, and drawn by
/// Flutter over it would hide it. A screen's own background
/// (`ThemeBackground.screen`) and an opaque one (`ThemeBackground.none`)
/// still draw, over it.
abstract final class PageUnderlay {
  static final ValueNotifier<bool> _shows = ValueNotifier(false);

  /// Whether one shows now.
  static ValueListenable<bool> get shows => _shows;

  /// One shows now, or no longer.
  static set showing(bool value) => _shows.value = value;
}
