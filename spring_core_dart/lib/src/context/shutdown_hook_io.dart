import 'dart:async';
import 'dart:io';

/// Calls [onSignal] with the conventional exit code (`130`, `143`) when the
/// process gets SIGINT or SIGTERM; the returned function stops listening.
/// A signal the platform cannot watch (SIGTERM on Windows) is skipped.
void Function() watchShutdownSignals(void Function(int exitCode) onSignal) {
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final (signal, code) in [
    (ProcessSignal.sigint, 130),
    (ProcessSignal.sigterm, 143),
  ]) {
    try {
      subscriptions.add(signal.watch().listen((_) => onSignal(code)));
    } on SignalException {
      continue;
    }
  }
  return () {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  };
}

/// Ends the process with [code].
void exitProcess(int code) => exit(code);
