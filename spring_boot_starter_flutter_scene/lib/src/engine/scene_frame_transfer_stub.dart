/// How the browser passes a frame of the engine's WebGL to the page:
/// `null` off the web, where frames are not passed through the browser.
String? get sceneFrameTransfer => null;

/// Runs [start]: off the web there is nothing to adjust.
Future<void> startWithFrameTransfer(
  Future<void> Function() start, {
  bool onScreen = false,
}) => start();
