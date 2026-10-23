import 'package:spring_core_dart/src/context/shutdown_hook_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/context/shutdown_hook_io.dart'
    as platform;

/// How `registerShutdownHook()` watches SIGINT / SIGTERM and ends the
/// process: `watch` calls its callback with the exit code (`130`, `143`)
/// on a signal and returns a function that stops watching; `exit` ends the
/// process. Nothing is watched without `dart:io`. Replaced in tests.
({
  void Function() Function(void Function(int exitCode) onSignal) watch,
  void Function(int exitCode) exit,
})
shutdownHookPlatform = (
  watch: platform.watchShutdownSignals,
  exit: platform.exitProcess,
);
