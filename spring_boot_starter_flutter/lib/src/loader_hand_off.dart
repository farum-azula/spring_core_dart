import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/loader_hand_off_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter/src/loader_hand_off_web.dart';

/// Tells the web page loader (the block the generator writes into
/// `web/index.html`) that the Flutter splash is on screen, so it can
/// remove itself: calls `window.springLoaderHandOff(progress)` when the
/// page defines it. Nothing happens off the web, or when the page has no
/// such function.
abstract final class LoaderHandOff {
  /// Replaces the call; for tests.
  @visibleForTesting
  static void Function(double progress)? override;

  /// Replaces [pageProgress]; for tests.
  @visibleForTesting
  static double? Function()? pageProgressOverride;

  /// How far the web page loader has come (0 to 1) while it is still on
  /// screen, so the splash can start from there; `null` off the web or
  /// when the page has no loader.
  static double? pageProgress() => pageProgressOverride != null
      ? pageProgressOverride!()
      : springPageLoaderProgress();

  /// Replaces [pageElapsed]; for tests.
  @visibleForTesting
  static Duration? Function()? pageElapsedOverride;

  /// How long the web page loader has been running while it is still on
  /// screen, so the splash's movement (a flicker, a turning border) goes on
  /// from where the page left it; `null` off the web or without a loader.
  static Duration? pageElapsed() => pageElapsedOverride != null
      ? pageElapsedOverride!()
      : springPageLoaderElapsed();

  /// Hands over with the start's [progress], 0 to 1.
  static void call(double progress) =>
      (override ?? springLoaderHandOff)(progress);
}
