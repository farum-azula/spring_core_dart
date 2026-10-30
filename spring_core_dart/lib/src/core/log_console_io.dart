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
