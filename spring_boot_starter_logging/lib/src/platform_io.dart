import 'dart:io' as io;
import 'dart:isolate';

/// The id of this process, for `${PID}` in log patterns.
int? get processId => io.pid;

/// The name of the current isolate, for `%thread`; `main` when the
/// isolate has no debug name, as the main one.
String get isolateName => Isolate.current.debugName ?? 'main';

/// Whether the console can show ANSI colours; this decides
/// `spring.output.ansi.enabled=detect`.
///
/// True for standard output attached to a terminal that understands the
/// codes, and for a Flutter app in a debug or profile build: its output
/// goes through the device log to `flutter run` and the IDEs, which show
/// colours. A release build has no console to colour.
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

const bool _isFlutterDebug =
    bool.fromEnvironment('dart.library.ui') &&
    !bool.fromEnvironment('dart.vm.product');
