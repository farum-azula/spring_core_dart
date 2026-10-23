import 'package:spring_boot_dart/src/shutdown_hook_stub.dart'
    if (dart.library.io) 'package:spring_boot_dart/src/shutdown_hook_io.dart'
    as platform;
import 'package:spring_core_dart/spring_core_dart.dart';

/// Closes [context] when the process gets SIGINT or SIGTERM and ends the
/// process with `128 + signal`, like the JVM runs Spring Boot's shutdown
/// hook. The watch stops when the context closes (a Dart program that listens
/// for signals does not end by itself). Nothing without `dart:io`.
///
/// [watch] and [exit] are replaced in tests.
void addShutdownHook(
  ConfigurableApplicationContext context, {
  void Function() Function(void Function(int exitCode) onSignal) watch =
      platform.watchShutdownSignals,
  void Function(int exitCode) exit = platform.exitProcess,
}) {
  late final void Function() stopWatching;
  var watching = true;
  void stop() {
    if (watching) {
      watching = false;
      stopWatching();
    }
  }

  stopWatching = watch((code) {
    stop();
    context.close();
    exit(code);
  });
  context.addApplicationListener(
    ApplicationListenerAdapter.of<ContextClosedEvent>((_) => stop()),
  );
}
