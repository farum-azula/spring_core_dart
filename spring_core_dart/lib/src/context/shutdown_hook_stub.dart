/// Without `dart:io` (on the web) there are no signals: nothing is
/// watched, and the returned function does nothing.
void Function() watchShutdownSignals(void Function(int exitCode) onSignal) =>
    () {};

/// Without `dart:io` (on the web) the process cannot be ended: does
/// nothing.
void exitProcess(int code) {}
