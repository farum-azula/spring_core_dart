import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/trigger.dart';

/// A task: a function whose result may be a `Future` (awaited before the
/// run counts as completed).
typedef ScheduledFunction = FutureOr<void> Function();

/// Creates a timer; [TimerTaskScheduler] takes one so tests can control
/// time (the default is [Timer.new]).
typedef TimerFactory = Timer Function(Duration delay, void Function() callback);

/// Runs tasks later or repeatedly, like Spring's `TaskScheduler`.
///
/// Inject it to schedule work in code; `@Scheduled` methods use it too.
///
/// ```dart
/// @Service()
/// class Reminders {
///   Reminders(this.scheduler);
///   final TaskScheduler scheduler;
///
///   ScheduledTask remind(String text, DateTime at) =>
///       scheduler.scheduleAt(() => print(text), at);
///
///   ScheduledTask poll() => scheduler.scheduleWithFixedDelay(
///     checkInbox,
///     const Duration(seconds: 30),
///   );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Reminders {
///   Reminders(TaskScheduler scheduler) { this.scheduler = scheduler; }
///
///   ScheduledFuture<?> remind(String text, Instant at) {
///     return scheduler.schedule(() -> System.out.println(text), at);
///   }
///
///   ScheduledFuture<?> poll() =>
///       scheduler.scheduleWithFixedDelay(this::checkInbox, Duration.ofSeconds(30));
/// }
/// ```
abstract interface class TaskScheduler {
  /// The scheduler's current time.
  DateTime now();

  /// Runs [task] at the times [trigger] returns, until it returns `null`
  /// or the task is cancelled. [name] appears in error logs.
  ScheduledTask schedule(
    ScheduledFunction task,
    Trigger trigger, {
    String? name,
  });

  /// Runs [task] once at [startTime] (right away when it is past), like
  /// Spring's `schedule(Runnable, Instant)` (Dart has no overloads).
  ScheduledTask scheduleAt(
    ScheduledFunction task,
    DateTime startTime, {
    String? name,
  });

  /// Runs [task] every [period] between starts (never overlapping), first
  /// after [initialDelay].
  ScheduledTask scheduleAtFixedRate(
    ScheduledFunction task,
    Duration period, {
    Duration initialDelay = Duration.zero,
    String? name,
  });

  /// Runs [task] repeatedly, waiting [delay] after each completion, first
  /// after [initialDelay].
  ScheduledTask scheduleWithFixedDelay(
    ScheduledFunction task,
    Duration delay, {
    Duration initialDelay = Duration.zero,
    String? name,
  });
}

/// A trigger that fires once, at [at] (or right away if [at] is past).
///
/// ```dart
/// scheduler.schedule(sendReminder, OneShotTrigger(DateTime(2026, 12, 31, 18)));
/// scheduler.scheduleAt(sendReminder, DateTime(2026, 12, 31, 18)); // the same
/// ```
///
/// Spring (Java):
/// ```java
/// scheduler.schedule(this::sendReminder, Instant.parse("2026-12-31T18:00:00Z"));
/// ```
final class OneShotTrigger implements Trigger {
  /// Fires once at [at].
  const OneShotTrigger(this.at);

  /// When the task runs.
  final DateTime at;

  @override
  DateTime? nextExecution(TriggerContext context) =>
      context.lastScheduledExecution == null ? at : null;

  @override
  String toString() => 'OneShotTrigger($at)';
}

/// A scheduled task, like Spring's `ScheduledTask` / `ScheduledFuture`:
/// cancel it or look at its next run.
///
/// ```dart
/// final task = scheduler.scheduleAtFixedRate(tick, const Duration(seconds: 1));
/// print(task.nextExecution);
/// task.cancel();
/// ```
///
/// Spring (Java):
/// ```java
/// ScheduledFuture<?> task = scheduler.scheduleAtFixedRate(this::tick, Duration.ofSeconds(1));
/// task.cancel(false);
/// ```
abstract interface class ScheduledTask {
  /// The task's name (`Class.method` for `@Scheduled` methods).
  String get name;

  /// When it runs.
  Trigger get trigger;

  /// When the next run is due; `null` while a run is going on, after the
  /// last run or once cancelled.
  DateTime? get nextExecution;

  /// How many runs have started.
  int get runs;

  /// Whether [cancel] was called (or the scheduler shut down).
  bool get isCancelled;

  /// Stops the task; a run that is going on finishes.
  void cancel();
}

const _log = SpringLog('spring.scheduling');

/// The default [TaskScheduler], on `dart:async` timers (one event loop, so
/// a task never runs twice at the same time), like Spring's
/// `ThreadPoolTaskScheduler` with one thread.
///
/// Errors thrown by a task (synchronously or by its `Future`) are logged
/// at error level to `spring.scheduling` and the task keeps its schedule.
///
/// ```dart
/// final scheduler = TimerTaskScheduler();
/// scheduler.scheduleAtFixedRate(() => print('tick'), const Duration(seconds: 1));
/// ...
/// scheduler.shutdown();
///
/// // In tests: a controlled clock and timers.
/// final scheduler = TimerTaskScheduler(now: clock.now, createTimer: clock.timer);
/// ```
///
/// Spring (Java):
/// ```java
/// ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
/// scheduler.initialize();
/// scheduler.scheduleAtFixedRate(() -> System.out.println("tick"), Duration.ofSeconds(1));
/// scheduler.shutdown();
/// ```
final class TimerTaskScheduler implements TaskScheduler, DisposableBean {
  /// A scheduler using [now] as its clock and [createTimer] for delays;
  /// see [awaitTermination] and [awaitTerminationPeriod].
  TimerTaskScheduler({
    DateTime Function()? now,
    TimerFactory? createTimer,
    this.awaitTermination = false,
    this.awaitTerminationPeriod,
  }) : _now = now ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new;

  final DateTime Function() _now;
  final TimerFactory _createTimer;
  final _tasks = <_TimerTask>{};
  final _running = <_TimerTask>{};
  Completer<void>? _terminated;
  var _shutdown = false;

  /// Whether [destroy] (the context's `closeAsync()`) waits for the runs
  /// going on when the scheduler shuts down, like Spring Boot's
  /// `spring.task.scheduling.shutdown.await-termination`; `false` by
  /// default (the runs finish on their own, after the close).
  final bool awaitTermination;

  /// How long [destroy] waits at most when [awaitTermination] is on, like
  /// `spring.task.scheduling.shutdown.await-termination-period`; `null`
  /// waits until the runs are finished. When it elapses a warning is
  /// logged and the shutdown goes on.
  final Duration? awaitTerminationPeriod;

  /// Tasks that are not cancelled and not finished.
  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  /// The tasks whose run (or its `Future`) is going on right now.
  List<ScheduledTask> get runningTasks => List.unmodifiable(_running);

  /// Whether [shutdown] was called.
  bool get isShutdown => _shutdown;

  @override
  DateTime now() => _now();

  @override
  ScheduledTask schedule(
    ScheduledFunction task,
    Trigger trigger, {
    String? name,
  }) {
    if (_shutdown) {
      throw StateError('The TaskScheduler has been shut down');
    }
    final scheduled = _TimerTask(this, task, trigger, name ?? 'task');
    _tasks.add(scheduled);
    scheduled._scheduleNext();
    return scheduled;
  }

  @override
  ScheduledTask scheduleAt(
    ScheduledFunction task,
    DateTime startTime, {
    String? name,
  }) => schedule(task, OneShotTrigger(startTime), name: name);

  @override
  ScheduledTask scheduleAtFixedRate(
    ScheduledFunction task,
    Duration period, {
    Duration initialDelay = Duration.zero,
    String? name,
  }) => schedule(
    task,
    PeriodicTrigger(period, fixedRate: true, initialDelay: initialDelay),
    name: name,
  );

  @override
  ScheduledTask scheduleWithFixedDelay(
    ScheduledFunction task,
    Duration delay, {
    Duration initialDelay = Duration.zero,
    String? name,
  }) => schedule(
    task,
    PeriodicTrigger(delay, initialDelay: initialDelay),
    name: name,
  );

  /// Cancels every task; [schedule] throws afterwards.
  void shutdown() {
    _shutdown = true;
    for (final task in [..._tasks]) {
      task.cancel();
    }
  }

  /// Shuts down when the context closes; with [awaitTermination] the
  /// returned `Future` (awaited by `closeAsync()`) completes when the runs
  /// going on are finished, or after [awaitTerminationPeriod].
  @override
  FutureOr<void> destroy() {
    shutdown();
    if (!awaitTermination || _running.isEmpty) {
      return null;
    }
    final terminated = (_terminated ??= Completer<void>()).future;
    final period = awaitTerminationPeriod;
    if (period == null) {
      return terminated;
    }
    return terminated.timeout(
      period,
      onTimeout: () => _log.warning(
        'Timed out while waiting for the TaskScheduler to terminate: '
        '${_running.length} task(s) still running after '
        '${period.inMilliseconds}ms: ${_running.toList()}',
      ),
    );
  }

  void _started(_TimerTask task) => _running.add(task);

  void _finished(_TimerTask task) {
    _running.remove(task);
    final terminated = _terminated;
    if (_running.isEmpty && terminated != null) {
      _terminated = null;
      terminated.complete();
    }
  }
}

final class _TimerTask implements ScheduledTask {
  _TimerTask(this._scheduler, this._task, this.trigger, this.name);

  final TimerTaskScheduler _scheduler;
  final ScheduledFunction _task;

  @override
  final Trigger trigger;

  @override
  final String name;

  Timer? _timer;
  DateTime? _next;
  DateTime? _lastScheduled;
  DateTime? _lastActual;
  DateTime? _lastCompletion;
  var _runs = 0;
  var _cancelled = false;

  @override
  DateTime? get nextExecution => _next;

  @override
  int get runs => _runs;

  @override
  bool get isCancelled => _cancelled;

  void _scheduleNext() {
    if (_cancelled) {
      return;
    }
    final now = _scheduler.now();
    final next = trigger.nextExecution(
      TriggerContext(
        now: now,
        lastScheduledExecution: _lastScheduled,
        lastActualExecution: _lastActual,
        lastCompletion: _lastCompletion,
      ),
    );
    _next = next;
    if (next == null) {
      _scheduler._tasks.remove(this);
      return;
    }
    final delay = next.difference(now);
    _timer = _scheduler._createTimer(
      delay.isNegative ? Duration.zero : delay,
      () => _run(next),
    );
  }

  void _run(DateTime scheduled) {
    if (_cancelled) {
      return;
    }
    _timer = null;
    _next = null;
    _lastScheduled = scheduled;
    _lastActual = _scheduler.now();
    _runs++;
    _scheduler._started(this);
    Object? result;
    try {
      result = _task();
    } catch (error, stackTrace) {
      _failed(error, stackTrace);
      _completed();
      return;
    }
    if (result is Future) {
      result.then(
        (_) => _completed(),
        onError: (Object error, StackTrace stackTrace) {
          _failed(error, stackTrace);
          _completed();
        },
      );
    } else {
      _completed();
    }
  }

  void _failed(Object error, StackTrace stackTrace) => _log.error(
    'Scheduled task $name failed',
    error: error,
    stackTrace: stackTrace,
    fields: {'task': name},
  );

  void _completed() {
    _lastCompletion = _scheduler.now();
    _scheduler._finished(this);
    _scheduleNext();
  }

  @override
  void cancel() {
    _cancelled = true;
    _next = null;
    _timer?.cancel();
    _timer = null;
    _scheduler._tasks.remove(this);
  }

  @override
  String toString() => 'ScheduledTask($name, $trigger)';
}
