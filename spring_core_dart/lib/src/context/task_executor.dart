import 'dart:async';

import 'package:spring_core_dart/src/core/log.dart';

/// Something that runs a task now or later, so that the code handing it
/// over does not have to wait.
///
/// The framework uses it to run event listeners away from the publishing
/// call: `@Async` listeners run on a `TaskExecutor` bean, and
/// `SimpleApplicationEventMulticaster(taskExecutor: ...)` runs every
/// listener on one. Declaring a `TaskExecutor` bean is also what switches
/// `@Async` on; the scheduling starter declares one. Dart has no threads
/// here: an asynchronous executor runs the task in a later event-loop turn
/// of the same isolate ([SimpleAsyncTaskExecutor]). Implement it to run
/// tasks elsewhere, for example in another isolate.
///
/// ```dart
/// final TaskExecutor executor = SimpleAsyncTaskExecutor();
/// executor.execute(() => print('later'));
/// print('now'); // printed first
/// ```
///
/// Spring (Java):
/// ```java
/// TaskExecutor executor = new SimpleAsyncTaskExecutor();
/// executor.execute(() -> System.out.println("later"));
/// ```
abstract interface class TaskExecutor {
  /// Runs [task], now or later depending on the implementation; a
  /// returned `Future` counts as the rest of the task. Returns at once
  /// for an asynchronous executor.
  void execute(FutureOr<void> Function() task);
}

/// A [TaskExecutor] that runs each task right away, in the calling code.
///
/// Use it where an executor is required but the work should stay
/// synchronous, for example in tests that check what a listener did right
/// after publishing. Errors thrown by the task reach the caller; a
/// `Future` the task returns is not awaited, and its error is not caught.
///
/// ```dart
/// const SyncTaskExecutor().execute(() => print('now'));
/// ```
///
/// Spring (Java):
/// ```java
/// new SyncTaskExecutor().execute(() -> System.out.println("now"));
/// ```
final class SyncTaskExecutor implements TaskExecutor {
  /// Creates the executor; it has no state.
  const SyncTaskExecutor();

  @override
  void execute(FutureOr<void> Function() task) {
    // The task's result is dropped, as Spring's synchronous executor does:
    // a FutureOr cannot be passed to unawaited.
    // ignore: discarded_futures
    task();
  }
}

/// A [TaskExecutor] that runs each task in a later event-loop turn
/// (`Timer.run`), so the caller goes on first.
///
/// Use it for event listeners that should not hold up the publisher, as
/// the executor of a `SimpleApplicationEventMulticaster` or as the
/// `TaskExecutor` bean of `@Async` listeners. It is Spring's
/// `SimpleAsyncTaskExecutor`, which starts a thread per task; here the
/// tasks share the isolate, so a long synchronous task still blocks
/// everything else.
///
/// An error of a task (thrown or from its `Future`) goes to
/// [errorHandler]; without one it is logged and suppressed, so a failing
/// task never becomes an uncaught error of the isolate (Spring logs the
/// uncaught exception of the thread). [activeCount] and [whenIdle] tell
/// whether tasks are still running, which helps in tests and for a
/// graceful shutdown.
///
/// ```dart
/// // Send the mail in the background; wait for it before exiting.
/// final executor = SimpleAsyncTaskExecutor(
///   errorHandler: (error, stack) => log.error('task failed', error: error),
/// );
/// executor.execute(() async => await sendMail());
/// await executor.whenIdle;
/// ```
///
/// Spring (Java):
/// ```java
/// var executor = new SimpleAsyncTaskExecutor();
/// executor.execute(this::sendMail);
/// ```
final class SimpleAsyncTaskExecutor implements TaskExecutor {
  /// Creates the executor; without an [errorHandler], task errors are
  /// logged.
  SimpleAsyncTaskExecutor({this.errorHandler});

  /// Receives the error of a failing task (thrown or from its `Future`);
  /// `null` logs it at ERROR.
  final void Function(Object error, StackTrace stackTrace)? errorHandler;

  int _active = 0;
  Completer<void>? _idle;

  /// The number of tasks submitted and not finished yet.
  int get activeCount => _active;

  /// Completes once no task is pending or running (at once when none
  /// is). Await it in a test before checking what the tasks did, or before
  /// the program ends.
  Future<void> get whenIdle =>
      _active == 0 ? Future.value() : (_idle ??= Completer<void>()).future;

  @override
  void execute(FutureOr<void> Function() task) {
    _active++;
    Timer.run(() async {
      try {
        await task();
      } on Object catch (error, stackTrace) {
        _failed(error, stackTrace);
      } finally {
        if (--_active == 0) {
          _idle?.complete();
          _idle = null;
        }
      }
    });
  }

  void _failed(Object error, StackTrace stackTrace) {
    final handler = errorHandler;
    if (handler != null) {
      handler(error, stackTrace);
      return;
    }
    _log.error(
      'Unexpected error occurred in asynchronous task',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

const _log = SpringLog('spring_core_dart.context.task');
