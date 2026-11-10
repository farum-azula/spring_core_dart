import 'dart:async';

import 'package:spring_core_dart/src/core/isolate/isolate_load.dart';
import 'package:spring_core_dart/src/core/isolate/isolate_task_pool_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/isolate/isolate_task_pool_io.dart';

/// Runs work in other isolates, taken from a pool: for what would block
/// the isolate it is called from (parsing megabytes of JSON, hashing,
/// resizing an image), so a server goes on answering and an app goes on
/// drawing.
///
/// ```dart
/// @Service()
/// class Reports {
///   Reports(this.isolates);
///   final IsolateTaskExecutor isolates;
///
///   Future<Summary> summarize(String csv) =>
///       isolates.submitWith(_summarize, csv);
///
///   static Summary _summarize(String csv) => Summary.parse(csv);
/// }
/// ```
///
/// **What crosses.** An isolate shares no memory with another: the
/// function, its argument and its result are copied. So:
///
/// - give it a top-level or static function and its data as the argument
///   ([submitWith]). A closure works too ([submit]), but everything it
///   uses is copied with it: one that reads a field copies the whole
///   object, and a bean with a socket or a timer in reach cannot be
///   copied at all (the call fails with an [ArgumentError]);
/// - the beans of the application do not exist there; nor does its
///   logging configuration (a task's logs use the default format, under
///   the isolate's name, `task-1`);
/// - an error the task throws comes back as the future's error.
///
/// **The pool.** An isolate is started when a task finds none free, up to
/// [IsolateTaskExecutorSettings.coreSize]; then tasks wait in the queue;
/// when the queue is full, more isolates are started, up to
/// [IsolateTaskExecutorSettings.maxSize]; when that is reached too, the
/// task is refused ([IsolateTaskRejectedException]). An isolate idle for
/// [IsolateTaskExecutorSettings.keepAlive] leaves. The properties are
/// `spring.task.execution.isolates.*`.
///
/// **In a browser** there are no isolates to start: the task runs in the
/// calling isolate, in a later turn of its event loop, with the same API.
///
/// Spring (Java): `ThreadPoolTaskExecutor.submit(callable)`, with the pool
/// of `spring.task.execution.pool.*`; a thread shares the heap, an isolate
/// does not.
abstract interface class IsolateTaskExecutor implements IsolateLoadSource {
  /// The executor of this platform: a pool of isolates where there are
  /// isolates, the calling isolate in a browser.
  factory IsolateTaskExecutor({
    IsolateTaskExecutorSettings settings = const IsolateTaskExecutorSettings(),
  }) => createIsolateTaskExecutor(settings);

  /// Runs [task] in an isolate of the pool and completes with its result.
  /// What [task] uses from around it is copied to that isolate.
  Future<R> submit<R>(FutureOr<R> Function() task);

  /// Runs [task] with [message] in an isolate of the pool: for a top-level
  /// or static function, so only [message] is copied.
  Future<R> submitWith<M, R>(FutureOr<R> Function(M message) task, M message);

  /// The isolates running now.
  int get poolSize;

  /// The tasks running now.
  int get activeCount;

  /// The tasks waiting for an isolate.
  int get queueSize;

  /// Ends the pool: waiting tasks fail, running ones are given up, the
  /// isolates stop. The context calls it when it closes.
  Future<void> shutdown();
}

/// The pool of an [IsolateTaskExecutor]
/// (`spring.task.execution.isolates.*`).
final class IsolateTaskExecutorSettings {
  /// The pool's sizes; without [coreSize], one isolate less than the
  /// machine has processors (at least one).
  const IsolateTaskExecutorSettings({
    this.coreSize,
    this.maxSize,
    this.keepAlive = const Duration(seconds: 60),
    this.queueCapacity,
    this.allowCoreTimeout = true,
    this.namePrefix = 'task-',
  });

  /// The isolates started before tasks wait in the queue; `null`: the
  /// machine's processors less one.
  final int? coreSize;

  /// The most isolates, reached only when the queue is full; `null`: as
  /// many as [coreSize].
  final int? maxSize;

  /// How long an idle isolate stays.
  final Duration keepAlive;

  /// How many tasks may wait; `null`: any number, so the pool never grows
  /// past [coreSize].
  final int? queueCapacity;

  /// Whether the first [coreSize] isolates leave when idle too. They are
  /// started again by the next task, in a few milliseconds.
  final bool allowCoreTimeout;

  /// The isolates' names in the logs: `task-1`.
  final String namePrefix;
}

/// A task the [IsolateTaskExecutor] could not take: its queue is full and
/// so is its pool, or it was shut down.
///
/// Spring (Java): `TaskRejectedException`.
final class IsolateTaskRejectedException implements Exception {
  /// The refusal, with why in [message].
  const IsolateTaskRejectedException(this.message);

  /// Why the task was refused.
  final String message;

  @override
  String toString() => 'IsolateTaskRejectedException: $message';
}

/// An error a task threw in its isolate, when the error itself could not
/// be copied back: its text and its stack trace.
final class IsolateTaskException implements Exception {
  /// The error as text.
  const IsolateTaskException(this.message, this.remoteStackTrace);

  /// The error's `toString()`.
  final String message;

  /// The stack trace in the task's isolate.
  final String remoteStackTrace;

  @override
  String toString() => 'IsolateTaskException: $message\n$remoteStackTrace';
}
