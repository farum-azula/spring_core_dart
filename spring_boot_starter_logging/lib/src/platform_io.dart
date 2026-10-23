import 'dart:io' as io;
import 'dart:isolate';

/// The process id (`${PID}`).
int? get processId => io.pid;

/// The name of the current isolate (`%thread`); `main` for the main one.
String get isolateName => Isolate.current.debugName ?? 'main';

/// Whether standard output is a terminal that understands ANSI colours
/// (`spring.output.ansi.enabled=detect`).
bool get stdoutSupportsAnsi {
  try {
    return io.stdout.hasTerminal && io.stdout.supportsAnsiEscapes;
  } on Object {
    return false;
  }
}
