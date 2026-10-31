import 'dart:io' as io;

/// Whether standard output is a terminal that shows ANSI colours, which
/// decides the default of `printLogHandlerColours`.
///
/// Never in Flutter: its `print` goes to the device log (logcat, the
/// system log), not to a terminal. Otherwise when standard output is a
/// terminal that understands the codes, not a file or a pipe.
bool get consoleSupportsAnsi {
  if (const bool.fromEnvironment('dart.library.ui')) {
    return false;
  }
  try {
    return io.stdout.hasTerminal && io.stdout.supportsAnsiEscapes;
  } on Object {
    return false;
  }
}

/// Writes one line of `printLogHandler`: to standard output on the Dart
/// VM, at once and not through `print` (which a zone may redirect); with
/// `print` in a Flutter app (its device log, also when it runs a server).
void writeConsoleLine(String line) {
  if (const bool.fromEnvironment('dart.library.ui')) {
    // The device log is the console of a Flutter app.
    // ignore: avoid_print
    print(line);
    return;
  }
  io.stdout.writeln(line);
}
