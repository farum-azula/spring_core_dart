import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The engine's own messages in the application's log.
///
/// `flutter_scene` writes what it has to say with Flutter's `debugPrint`:
/// bare lines beside the app's log ("flutter_scene: pipeline build took
/// 66ms mid-frame..."). While this is installed they are records of the
/// logger `flutter_scene`, like any other of the app:
///
/// ```
/// 2026-11-13T19:32:14.701+02:00  WARN 43815 --- [main] flutter_scene : pipeline build took 66ms mid-frame. ...
/// ```
///
/// so they have a time and a level, go where the app's log goes (the
/// debug panel's Logs tab too), and are set like any logger:
/// `logging.level.flutter_scene=warn` keeps only the engine's warnings.
/// A message that says something went wrong (failed, skipped, missing, a
/// program built in the middle of a frame) is a warning; the rest is
/// `info`.
///
/// `debugPrint` is one function for all of Flutter, so the messages are
/// told apart: by how the engine begins them (`flutter_scene:`, `fscene:`,
/// `glTF import:`...), and, outside a release build, by where the call
/// came from. Everything else goes on to the `debugPrint` there was.
/// `spring.flutter.scene.engine-log: false` leaves `debugPrint` alone.
///
/// Not caught: the few lines the engine writes with `print`, and those of
/// its build tools.
final class SceneEngineLog {
  static const _log = SpringLog('flutter_scene');

  /// How the engine begins its messages.
  static const _prefixes = [
    'flutter_scene:',
    'flutter_scene (web):',
    'fscene:',
    'glTF import:',
    'SceneModel:',
    'Unpacking glTF',
    'Flutter Scene is not ready',
    'FLUTTER_SCENE_PROFILE',
  ];

  /// What a message that tells of trouble has in it.
  static final _trouble = RegExp(
    'fail|skipp|missing|unknown|not supported|not found|unsupported|'
    'mid-frame|exceeded|malformed|not ready|cannot|could not',
    caseSensitive: false,
  );

  static final _engineFrame = RegExp(r'package:(flutter_scene|scene)/');

  DebugPrintCallback? _previous;
  bool _writing = false;
  late final DebugPrintCallback _own = _print;

  /// Whether the engine's messages are being taken.
  bool get installed => _previous != null;

  /// Takes the engine's messages from now on.
  void install() {
    if (installed) {
      return;
    }
    _previous = debugPrint;
    debugPrint = _own;
  }

  /// Gives `debugPrint` back, unless something else replaced it since.
  void uninstall() {
    final previous = _previous;
    if (previous == null) {
      return;
    }
    if (debugPrint == _own) {
      debugPrint = previous;
    }
    _previous = null;
  }

  /// Whether [message] is the engine's: by its beginning, or by a frame
  /// of the engine in [stack] (the call's own, read only outside a
  /// release build, where it has no package names anyway).
  @visibleForTesting
  static bool isEngine(String message, {StackTrace? stack}) {
    if (_prefixes.any(message.startsWith)) {
      return true;
    }
    if (stack != null) {
      return _engineFrame.hasMatch('$stack');
    }
    return !kReleaseMode && _engineFrame.hasMatch('${StackTrace.current}');
  }

  /// The level of [message]: a warning when it tells of trouble.
  @visibleForTesting
  static SpringLogLevel levelOf(String message) =>
      _trouble.hasMatch(message) ? SpringLogLevel.warning : SpringLogLevel.info;

  /// [message] without the engine's own name in front: the logger's name
  /// says it.
  @visibleForTesting
  static String textOf(String message) => message.startsWith('flutter_scene:')
      ? message.substring('flutter_scene:'.length).trimLeft()
      : message;

  void _print(String? message, {int? wrapWidth}) {
    // A log handler that itself writes with debugPrint is let through.
    if (message == null || _writing || !isEngine(message)) {
      (_previous ?? debugPrintThrottled)(message, wrapWidth: wrapWidth);
      return;
    }
    _writing = true;
    try {
      _log.log(levelOf(message), textOf(message));
    } finally {
      _writing = false;
    }
  }
}
