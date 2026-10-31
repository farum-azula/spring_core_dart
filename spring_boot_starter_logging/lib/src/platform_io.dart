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

/// Where the console's lines go by default ([stderr]: standard error):
/// standard output, written at once (a line written before `exit` is
/// not lost), not `print`, which any zone may redirect. In a Flutter app
/// `print`: its device log (logcat, the system log, `flutter run`), also
/// when the app runs a server.
void Function(String line) consoleOut({bool stderr = false}) {
  if (const bool.fromEnvironment('dart.library.ui')) {
    return print;
  }
  final sink = stderr ? io.stderr : io.stdout;
  return sink.writeln;
}

const bool _isFlutterDebug =
    bool.fromEnvironment('dart.library.ui') &&
    !bool.fromEnvironment('dart.vm.product');
