import 'dart:async';

import 'package:spring_core_dart/src/core/log.dart';

/// Runs tasks, like Spring's `TaskExecutor` (`java.util.concurrent.Executor`).
///
/// Dart has no threads: an asynchronous executor runs the task in a later
/// event-loop turn of the same isolate ([SimpleAsyncTaskExecutor]). Used
/// by `SimpleApplicationEventMulticaster(taskExecutor: ...)` and by
/// `@Async` event listeners.
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
  /// returned `Future` counts as the rest of the task.
  void execute(FutureOr<void> Function() task);
}

/// Runs each task immediately on the calling code, like Spring's
/// `SyncTaskExecutor`; errors propagate to the caller.
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
  /// Creates the executor.
  const SyncTaskExecutor();

  @override
  void execute(FutureOr<void> Function() task) {
    task();
  }
}

/// Runs each task in a later event-loop turn (`Timer.run`), like Spring's
/// `SimpleAsyncTaskExecutor` starting a thread per task.
///
/// An error of a task (thrown or from its `Future`) goes to
/// [errorHandler]; without one it is logged and suppressed, so a failing
/// task never becomes an uncaught error of the isolate (Spring logs the
/// uncaught exception of the thread). [activeCount] and [whenIdle] tell
/// whether tasks are still running (handy in tests and for a graceful
/// shutdown).
///
/// ```dart
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
  /// Creates the executor; see [errorHandler].
  SimpleAsyncTaskExecutor({this.errorHandler});

  /// Receives the errors of the tasks; `null` logs them.
  final void Function(Object error, StackTrace stackTrace)? errorHandler;

  int _active = 0;
  Completer<void>? _idle;

  /// Tasks submitted and not finished yet.
  int get activeCount => _active;

  /// Completes once no task is pending or running.
  Future<void> get whenIdle =>
      _active == 0 ? Future.value() : (_idle ??= Completer<void>()).future;

  @override
  void execute(FutureOr<void> Function() task) {
    _active++;
    Timer.run(() async {
      try {
        await task();
      } catch (error, stackTrace) {
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
