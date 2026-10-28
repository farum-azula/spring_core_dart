import 'package:spring_core_dart/src/context/shutdown_hook_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/context/shutdown_hook_io.dart'
    as platform;

/// The two platform operations behind `registerShutdownHook()`: watching
/// SIGINT and SIGTERM, and ending the process.
///
/// `watch` calls its callback with the exit code (`130`, `143`) when a
/// signal arrives and returns a function that stops watching; `exit` ends
/// the process. Without `dart:io` nothing is watched. Tests replace it so
/// that no real signal or exit is needed.
({
  void Function() Function(void Function(int exitCode) onSignal) watch,
  void Function(int exitCode) exit,
})
shutdownHookPlatform = (
  watch: platform.watchShutdownSignals,
  exit: platform.exitProcess,
);
