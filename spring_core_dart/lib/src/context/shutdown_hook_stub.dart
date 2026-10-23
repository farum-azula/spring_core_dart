/// Without `dart:io` there are no signals: nothing is watched.
void Function() watchShutdownSignals(void Function(int exitCode) onSignal) =>
    () {};

/// Without `dart:io` the process cannot be ended.
void exitProcess(int code) {}
