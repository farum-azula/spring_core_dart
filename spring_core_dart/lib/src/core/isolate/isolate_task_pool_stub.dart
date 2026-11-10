import 'dart:async';

import 'package:spring_core_dart/src/core/isolate/isolate_load.dart';
import 'package:spring_core_dart/src/core/isolate/isolate_task_executor.dart';

/// The executor where no isolate can be started (a browser): tasks run in
/// the calling isolate, each in a later turn of its event loop.
IsolateTaskExecutor createIsolateTaskExecutor(
  IsolateTaskExecutorSettings settings,
) => _InlineIsolateTaskExecutor();

final class _InlineIsolateTaskExecutor implements IsolateTaskExecutor {
  int _active = 0;
  bool _closed = false;

  @override
  Future<R> submit<R>(FutureOr<R> Function() task) {
    if (_closed) {
      throw const IsolateTaskRejectedException('the executor was shut down');
    }
    _active++;
    return Future<R>(task).whenComplete(() => _active--);
  }

  @override
  Future<R> submitWith<M, R>(
    FutureOr<R> Function(M message) task,
    M message,
  ) => submit(() => task(message));

  @override
  int get poolSize => 0;

  @override
  int get activeCount => _active;

  @override
  int get queueSize => 0;

  @override
  List<IsolateLoad> loads() => const [];

  @override
  Future<void> shutdown() async => _closed = true;
}
