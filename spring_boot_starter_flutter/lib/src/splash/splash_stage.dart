/// Where the start of a Flutter application is, as its splash sees it.
/// The stages come in this order; a platform skips those it does not have
/// (only the web has [page] and [engine]).
///
/// See the stages of every platform in `docs/flutter/theme/loaders.md`.
enum SplashStage {
  /// The web page is open and the browser downloads the app's code
  /// (`main.dart.js`): the page loader of `web/index.html` shows. Web
  /// only.
  page,

  /// The Flutter engine starts (CanvasKit or skwasm): the page loader
  /// still shows. Web only; on Android and iOS the system's launch screen
  /// covers this, on a desktop the window is not shown yet.
  engine,

  /// Flutter draws its first frame: the theme's splash is on screen (the
  /// web page's loader is removed). The first stage on Android, iOS and
  /// desktops.
  splash,

  /// The application starts: the configuration is read, the beans are
  /// created. The splash shows the start's progress.
  starting,

  /// The beans are created; the `SplashTask` beans run (a font downloaded,
  /// a cache filled) and the splash's loader follows them. Skipped when
  /// the app has none.
  tasks,

  /// The context is ready; the splash ends its loader, waits for its
  /// `min-duration`.
  ready,

  /// The splash plays its exit (`splash.exit`: a fade, or `reveal`).
  exit,

  /// The splash is gone; the application is shown.
  app,
}
