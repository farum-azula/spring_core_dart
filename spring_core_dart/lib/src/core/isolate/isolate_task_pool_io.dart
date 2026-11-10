import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:spring_core_dart/src/core/isolate/isolate_info.dart';
import 'package:spring_core_dart/src/core/isolate/isolate_load.dart';
import 'package:spring_core_dart/src/core/isolate/isolate_task_executor.dart';
import 'package:spring_core_dart/src/core/log.dart';

/// The executor where isolates exist: a pool of them.
IsolateTaskExecutor createIsolateTaskExecutor(
  IsolateTaskExecutorSettings settings,
) => IsolatePoolTaskExecutor(settings);

/// An [IsolateTaskExecutor] over a pool of isolates, each running one task
/// at a time.
final class IsolatePoolTaskExecutor implements IsolateTaskExecutor {
  /// A pool as [settings] say; no isolate is started before the first
  /// task.
  IsolatePoolTaskExecutor(this.settings);

  /// The pool's sizes.
  final IsolateTaskExecutorSettings settings;

  final _workers = <_Worker>[];
  final _queue = Queue<_Task<Object?>>();
  var _number = 0;
  var _closed = false;

  int get _core {
    final core = settings.coreSize ?? Platform.numberOfProcessors - 1;
    return core < 1 ? 1 : core;
  }

  int get _max {
    final max = settings.maxSize ?? _core;
    return max < _core ? _core : max;
  }

  @override
  int get poolSize => _workers.length;

  @override
  int get activeCount => _workers.where((w) => w.task != null).length;

  @override
  int get queueSize => _queue.length;

  @override
  Future<R> submit<R>(FutureOr<R> Function() task) => _submit<R>(task, null);

  @override
  Future<R> submitWith<M, R>(
    FutureOr<R> Function(M message) task,
    M message,
  ) => _submit<R>(_Call<M, R>(task, message).run, null);

  Future<R> _submit<R>(FutureOr<R> Function() run, Object? _) {
    if (_closed) {
      throw const IsolateTaskRejectedException('the executor was shut down');
    }
    final task = _Task<R>(run);
    final free = _workers.where((w) => w.task == null).firstOrNull;
    if (free != null) {
      free.run(task);
    } else if (_workers.length < _core) {
      _spawn(task, 'a task found no free isolate');
    } else if (settings.queueCapacity == null ||
        _queue.length < settings.queueCapacity!) {
      _queue.add(task);
    } else if (_workers.length < _max) {
      _spawn(task, 'the queue is full (${_queue.length})');
    } else {
      throw IsolateTaskRejectedException(
        'the pool has its $_max isolates busy and its queue is full '
        '(${_queue.length}); raise spring.task.execution.isolates.max-size '
        'or queue-capacity',
      );
    }
    return task.completer.future;
  }

  void _spawn(_Task<Object?> first, String why) {
    final worker = _Worker(this, '${settings.namePrefix}${++_number}');
    _workers.add(worker);
    _log.debug(
      () =>
          'Starting isolate ${worker.name}: $why '
          '(${_workers.length} of $_max)',
    );
    worker.start(first);
  }

  // A worker finished its task: the next of the queue, or idle until
  // keep-alive.
  void _free(_Worker worker) {
    if (_closed) {
      return;
    }
    if (_queue.isNotEmpty) {
      worker.run(_queue.removeFirst());
      return;
    }
    worker.idleTimer = Timer(settings.keepAlive, () {
      if (worker.task != null) {
        return;
      }
      final core = _workers.indexOf(worker) < _core;
      if (core && !settings.allowCoreTimeout) {
        return;
      }
      _workers.remove(worker);
      _log.debug(
        () =>
            'Isolate ${worker.name} idle for ${settings.keepAlive}: '
            'stopped (${_workers.length} left)',
      );
      worker.stop();
    });
  }

  // A worker's isolate ended by itself (an error outside a task, or
  // killed): its task fails, the queue goes on with another.
  void _lost(_Worker worker, Object error) {
    if (!_workers.remove(worker)) {
      return;
    }
    _log.warning('Isolate ${worker.name} failed', error: error);
    worker.task?.completer.completeError(
      IsolateTaskException('the isolate ${worker.name} ended: $error', ''),
    );
    worker
      ..task = null
      ..stop();
    if (!_closed && _queue.isNotEmpty) {
      _spawn(_queue.removeFirst(), 'replacing ${worker.name}');
    }
  }

  @override
  List<IsolateLoad> loads() => [
    for (final worker in _workers)
      IsolateLoad(
        name: worker.name,
        kind: 'task',
        busy: worker.busyShare(),
        active: worker.task == null ? 0 : 1,
        details: {
          'tasks': worker.done,
          if (worker == _workers.first && _queue.isNotEmpty)
            'queued': _queue.length,
        },
      ),
  ];

  @override
  Future<void> shutdown() async {
    if (_closed) {
      return;
    }
    _closed = true;
    const closed = IsolateTaskRejectedException('the executor was shut down');
    for (final task in _queue) {
      task.completer.completeError(closed);
    }
    _queue.clear();
    for (final worker in _workers.toList()) {
      worker.task?.completer.completeError(closed);
      worker
        ..task = null
        ..stop();
    }
    _workers.clear();
  }
}

// A function with its argument, as one closure that copies only them.
final class _Call<M, R> {
  _Call(this.function, this.message);

  final FutureOr<R> Function(M message) function;
  final M message;

  FutureOr<R> run() => function(message);
}

final class _Task<R> {
  _Task(this.run);

  final FutureOr<R> Function() run;
  final completer = Completer<R>();

  // The result came back untyped: R is this task's own.
  void complete(Object? result) => completer.complete(result as R);
}

// One isolate of the pool and the task it runs.
final class _Worker {
  _Worker(this.pool, this.name);

  final IsolatePoolTaskExecutor pool;
  final String name;

  final _results = ReceivePort();
  final _exits = ReceivePort();
  final _errors = ReceivePort();
  Isolate? _isolate;
  late SendPort _tasks;
  _Task<Object?>? task;
  Timer? idleTimer;
  int done = 0;
  var _stopped = false;

  // For the busy share: the time spent in tasks since the last read.
  final _clock = Stopwatch()..start();
  int _busyMicros = 0;
  int _taskStarted = 0;
  int _readAt = 0;
  double _share = 0;

  void start(_Task<Object?> first) {
    task = first;
    _taskStarted = _clock.elapsedMicroseconds;
    _results.listen(_received);
    _exits.listen((_) => pool._lost(this, 'it exited'));
    _errors.listen((Object? error) {
      final text = error is List && error.isNotEmpty ? error.first : error;
      pool._lost(this, '$text');
    });
    unawaited(
      Isolate.spawn(
        _main,
        (_results.sendPort, name),
        debugName: name,
        onExit: _exits.sendPort,
        onError: _errors.sendPort,
        errorsAreFatal: false,
      ).then(
        (isolate) {
          _isolate = isolate;
          if (_stopped) {
            isolate.kill(priority: Isolate.immediate);
          }
        },
        onError: (Object error) => pool._lost(this, error),
      ),
    );
  }

  void run(_Task<Object?> next) {
    idleTimer?.cancel();
    idleTimer = null;
    task = next;
    _taskStarted = _clock.elapsedMicroseconds;
    _send(next);
  }

  void _send(_Task<Object?> next) {
    try {
      _tasks.send(next.run);
    } on Object catch (error, stackTrace) {
      // What the task uses cannot be copied to another isolate.
      _finished();
      next.completer.completeError(error, stackTrace);
      pool._free(this);
    }
  }

  void _received(Object? message) {
    if (message is SendPort) {
      // The isolate is up: its first task.
      _tasks = message;
      final first = task;
      if (first != null) {
        _send(first);
      }
      return;
    }
    final running = task;
    if (running == null) {
      return;
    }
    _finished();
    switch (message) {
      case (final Object? result,):
        try {
          running.complete(result);
        } on Object catch (error, stackTrace) {
          running.completer.completeError(error, stackTrace);
        }
      case (final Object error, final StackTrace stackTrace):
        running.completer.completeError(error, stackTrace);
      default:
        running.completer.completeError(
          StateError('unexpected answer of $name: $message'),
        );
    }
    pool._free(this);
  }

  void _finished() {
    _busyMicros += _clock.elapsedMicroseconds - _taskStarted;
    task = null;
    done++;
  }

  // The share of the time spent in tasks, over the last second or more:
  // worked out at most once a second, so several readers see the same.
  double busyShare() {
    final now = _clock.elapsedMicroseconds;
    if (now - _readAt < Duration.microsecondsPerSecond && _readAt > 0) {
      return _share;
    }
    var busy = _busyMicros;
    if (task != null) {
      busy += now - _taskStarted;
      _taskStarted = now;
    }
    final elapsed = now - _readAt;
    _busyMicros = 0;
    _readAt = now;
    return _share = elapsed <= 0 ? 0 : (busy / elapsed).clamp(0, 1).toDouble();
  }

  void stop() {
    _stopped = true;
    idleTimer?.cancel();
    _results.close();
    _exits.close();
    _errors.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  // The isolate: takes one task after another and answers each.
  static void _main((SendPort, String) start) {
    final (results, name) = start;
    IsolateInfo.current = IsolateInfo(name: name, primary: false);
    final tasks = ReceivePort();
    results.send(tasks.sendPort);
    tasks.listen((Object? message) async {
      final run = message! as FutureOr<Object?> Function();
      try {
        final result = await run();
        try {
          results.send((result,));
        } on Object catch (error, stackTrace) {
          // The result cannot be copied back.
          results.send((
            IsolateTaskException('$error', '$stackTrace'),
            StackTrace.empty,
          ));
        }
      } on Object catch (error, stackTrace) {
        try {
          results.send((error, stackTrace));
        } on Object {
          results.send((
            IsolateTaskException('$error', '$stackTrace'),
            StackTrace.empty,
          ));
        }
      }
    });
  }
}

const _log = SpringLog('spring_core_dart.isolate.task');
