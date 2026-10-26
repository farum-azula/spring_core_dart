import 'dart:io' as io;
import 'dart:isolate';

/// The process id (`${PID}`).
int? get processId => io.pid;

/// The name of the current isolate (`%thread`); `main` for the main one.
String get isolateName => Isolate.current.debugName ?? 'main';

/// Whether the console shows ANSI colours
/// (`spring.output.ansi.enabled=detect`): a terminal that understands them,
/// or a Flutter app in a debug or profile build, whose output goes through
/// the device log to `flutter run` and the IDEs, which show colours (a
/// release build has no console to colour).
bool get stdoutSupportsAnsi {
  if (_isFlutterDebug) {
    return true;
  }
  try {
    return io.stdout.hasTerminal && io.stdout.supportsAnsiEscapes;
  } on Object {
    return false;
  }
}

const _isFlutterDebug =
    bool.fromEnvironment('dart.library.ui') &&
    !bool.fromEnvironment('dart.vm.product');
