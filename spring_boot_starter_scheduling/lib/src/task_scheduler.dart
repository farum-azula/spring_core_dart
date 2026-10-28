import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/trigger.dart';

/// The work a [TaskScheduler] runs: a function without parameters. It may
/// return a `Future`; the run then counts as finished when the future
/// completes, and the next run is planned only after that.
typedef ScheduledFunction = FutureOr<void> Function();

/// A function that creates a timer, which [TimerTaskScheduler] uses for
/// every wait. The default is [Timer.new]; a test passes timers of a fake
/// clock so tasks can run without waiting for real time.
typedef TimerFactory = Timer Function(Duration delay, void Function() callback);

/// The service that runs functions later or repeatedly: once at a given
/// time, at a fixed rate, with a fixed delay, or by any [Trigger].
///
/// `@Scheduled` covers work that is known when the code is written.
/// Inject the scheduler when the schedule is decided at runtime: a
/// reminder at a time the user picked, a poll that starts when a screen
/// opens and stops when it closes. Every call returns a [ScheduledTask]
/// to cancel the work or see its next run. The starter registers a
/// [TimerTaskScheduler] as the `taskScheduler` bean; declaring your own
/// `TaskScheduler` bean replaces it. Tasks stop when the context closes.
///
/// ```dart
/// @Service()
/// class Reminders {
///   Reminders(this.scheduler); // the starter's `taskScheduler` bean
///   final TaskScheduler scheduler;
///
///   // At the time the user picked in the app.
///   ScheduledTask remind(String text, DateTime at) =>
///       scheduler.scheduleAt(() => notify(text), at, name: 'reminder');
///
///   // While the inbox screen is open; the caller cancels the task.
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
///     return scheduler.schedule(() -> notify(text), at);
///   }
///
///   ScheduledFuture<?> poll() {
///     return scheduler.scheduleWithFixedDelay(
///         this::checkInbox, Duration.ofSeconds(30));
///   }
/// }
/// ```
///
/// Differences: `schedule(task, Instant)` is [scheduleAt] (Dart has no
/// overloads), and tasks return a [ScheduledTask] instead of a
/// `ScheduledFuture`.
abstract interface class TaskScheduler {
  /// The current time of the scheduler's clock. Triggers plan from it, so
  /// a scheduler on a fake clock moves every schedule with it.
  DateTime now();

  /// Runs [task] at the times [trigger] returns, until it returns `null`
  /// or the task is cancelled. Use it for a schedule the other methods do
  /// not cover, such as a [CronTrigger] or your own [Trigger].
  ///
  /// [name] identifies the task in error logs and in [ScheduledTask.name].
  /// Throws a [StateError] once the scheduler has shut down.
  ScheduledTask schedule(
    ScheduledFunction task,
    Trigger trigger, {
    String? name,
  });

  /// Runs [task] once at [startTime], or right away when that time has
  /// passed.
  ScheduledTask scheduleAt(
    ScheduledFunction task,
    DateTime startTime, {
    String? name,
  });

  /// Runs [task] every [period], measured between starts, the first time
  /// after [initialDelay] (at once by default). Runs never overlap: a run
  /// longer than the period is followed by one run right after it.
  ScheduledTask scheduleAtFixedRate(
    ScheduledFunction task,
    Duration period, {
    Duration initialDelay = Duration.zero,
    String? name,
  });

  /// Runs [task] again and again, waiting [delay] after each run has
  /// finished, the first time after [initialDelay] (at once by default).
  ScheduledTask scheduleWithFixedDelay(
    ScheduledFunction task,
    Duration delay, {
    Duration initialDelay = Duration.zero,
    String? name,
  });
}

/// A [Trigger] that runs a task once, at [at], or right away when that time
/// has passed.
///
/// [TaskScheduler.scheduleAt] uses it, and most code calls that instead.
/// Create one when an API takes a [Trigger], such as
/// [TaskScheduler.schedule].
///
/// ```dart
/// // The New Year's Eve reminder; the same as scheduleAt.
/// scheduler.schedule(
///     sendReminder, OneShotTrigger(DateTime(2026, 12, 31, 18)));
/// ```
///
/// Spring (Java):
/// ```java
/// scheduler.schedule(
///     this::sendReminder, Instant.parse("2026-12-31T18:00:00Z"));
/// ```
final class OneShotTrigger implements Trigger {
  /// A trigger for a single run at [at].
  const OneShotTrigger(this.at);

  /// When the task runs, in the clock of the scheduler.
  final DateTime at;

  @override
  DateTime? nextExecution(TriggerContext context) =>
      context.lastScheduledExecution == null ? at : null;

  @override
  String toString() => 'OneShotTrigger($at)';
}

/// A handle on work given to a [TaskScheduler]: it tells when the next run
/// is due and how many runs there were, and cancels the work.
///
/// Every scheduling method returns one; keep it when the work must stop
/// before the context closes, such as a poll tied to an open screen.
/// `ScheduledAnnotationBeanPostProcessor.scheduledTasks` lists the ones of
/// `@Scheduled` methods.
///
/// ```dart
/// // The clock ticks while the timer screen is open.
/// final task =
///     scheduler.scheduleAtFixedRate(tick, const Duration(seconds: 1));
/// ...
/// task.cancel(); // the screen closed
/// ```
///
/// Spring (Java):
/// ```java
/// ScheduledFuture<?> task =
///     scheduler.scheduleAtFixedRate(this::tick, Duration.ofSeconds(1));
/// task.cancel(false);
/// ```
abstract interface class ScheduledTask {
  /// The name given when scheduling (`task` without one), as used in
  /// error logs; `Class.method` for `@Scheduled` methods.
  String get name;

  /// The rule that decides when the task runs.
  Trigger get trigger;

  /// When the next run is due; `null` while a run is going on, after the
  /// last run or once cancelled.
  DateTime? get nextExecution;

  /// How many runs have started so far.
  int get runs;

  /// Whether the task was cancelled, by [cancel] or by the scheduler
  /// shutting down. A task that ended because its trigger had no next
  /// time is not cancelled.
  bool get isCancelled;

  /// Stops the task: no further run starts. A run that is going on is not
  /// interrupted and finishes. Calling it again does nothing.
  void cancel();
}

const _log = SpringLog('spring.scheduling');

/// Receives the errors thrown by scheduled tasks, instead of the log.
///
/// By default an error of a task, thrown or from its `Future`, is logged
/// at error level to `spring.scheduling` and the task keeps its schedule.
/// Declare an `ErrorHandler` bean to do something else, such as reporting
/// the error to a crash service. The starter's scheduler uses the only
/// `ErrorHandler` bean, or the primary one; with several and none
/// primary, it uses none. A handler that throws stops the task: the error
/// is logged and the task does not run again (Spring's
/// `LOG_AND_PROPAGATE`).
///
/// ```dart
/// // Every failed run is reported, and the task keeps running.
/// @Component()
/// class ReportErrors implements ErrorHandler {
///   @override
///   void handleError(Object error, StackTrace stackTrace) =>
///       crashReporter.record(error, stackTrace);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// scheduler.setErrorHandler(t -> crashReporter.record(t));
/// ```
abstract interface class ErrorHandler {
  /// Called with each [error] a run throws, synchronously or through its
  /// `Future`, and its [stackTrace]. Throw to stop the task.
  void handleError(Object error, StackTrace stackTrace);
}

/// The [TaskScheduler] the starter provides: it waits with `dart:async`
/// timers and runs every task on the event loop, so a task never runs
/// twice at the same time.
///
/// An application gets it injected as `TaskScheduler`; the starter sets
/// it up from the `spring.task.scheduling.shutdown.*` properties and the
/// `ErrorHandler` bean. Create one yourself without Spring Boot, or in a
/// test with a fake clock ([TimerTaskScheduler.new]'s `now` and
/// `createTimer`), registered in place of the starter's.
///
/// Errors thrown by a task, synchronously or by its `Future`, go to the
/// [errorHandler]; without one they are logged at error level to
/// `spring.scheduling` (Spring's `LOG_AND_SUPPRESS_ERROR_HANDLER`). Either
/// way the task keeps its schedule, unless the handler throws.
///
/// ```dart
/// // A test that runs a 5-minute schedule without waiting 5 minutes;
/// // `clock` is the test's fake clock (`now`, `timer`, `elapse`).
/// final scheduler =
///     TimerTaskScheduler(now: clock.now, createTimer: clock.timer);
/// scheduler.scheduleAtFixedRate(refresh, const Duration(minutes: 5));
/// clock.elapse(const Duration(minutes: 10)); // ten minutes of runs, now
/// scheduler.shutdown();
/// ```
///
/// Spring (Java):
/// ```java
/// ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
/// scheduler.initialize();
/// scheduler.scheduleAtFixedRate(this::refresh, Duration.ofMinutes(5));
/// scheduler.shutdown();
/// ```
///
/// It behaves like a `ThreadPoolTaskScheduler` with one thread, except
/// that a fixed-rate task does not catch up missed runs.
final class TimerTaskScheduler implements TaskScheduler, DisposableBean {
  /// A scheduler that reads the time from [now] and waits with timers from
  /// [createTimer]; by default the real clock ([DateTime.now]) and
  /// [Timer.new]. Pass both from a fake clock in tests.
  ///
  /// [awaitTermination] and [awaitTerminationPeriod] control how [destroy]
  /// waits for runs going on; [errorHandler] receives the errors of the
  /// tasks.
  TimerTaskScheduler({
    DateTime Function()? now,
    TimerFactory? createTimer,
    this.awaitTermination = false,
    this.awaitTerminationPeriod,
    this.errorHandler,
  }) : _now = now ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new;

  final DateTime Function() _now;
  final TimerFactory _createTimer;
  final _tasks = <_TimerTask>{};
  final _running = <_TimerTask>{};
  Completer<void>? _terminated;
  var _shutdown = false;

  /// Whether [destroy], called by the context's `closeAsync()`, waits for
  /// the runs going on to finish
  /// (`spring.task.scheduling.shutdown.await-termination`). `false` by
  /// default: those runs finish on their own after the close. A run is
  /// never interrupted either way. The synchronous `close()` cannot wait.
  final bool awaitTermination;

  /// How long [destroy] waits at most when [awaitTermination] is on
  /// (`spring.task.scheduling.shutdown.await-termination-period`); `null`
  /// waits until the runs are finished. When it elapses, a warning naming
  /// the tasks still running is logged and the shutdown goes on.
  final Duration? awaitTerminationPeriod;

  /// Receives the errors of the tasks; `null` logs them instead. The
  /// starter passes the only or primary `ErrorHandler` bean.
  final ErrorHandler? errorHandler;

  /// The tasks that will still run: neither cancelled nor ended because
  /// their trigger had no next time.
  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  /// The tasks with a run going on right now, its `Future` included. After
  /// a synchronous `close()` it shows the runs that outlive the context.
  List<ScheduledTask> get runningTasks => List.unmodifiable(_running);

  /// Whether [shutdown] was called; scheduling then throws.
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

  /// Cancels every task; runs going on finish. Scheduling throws a
  /// [StateError] afterwards. Called by [destroy] when the context closes.
  void shutdown() {
    _shutdown = true;
    for (final task in [..._tasks]) {
      task.cancel();
    }
  }

  /// Called when the context closes: [shutdown], then, with
  /// [awaitTermination] and runs going on, a `Future` that `closeAsync()`
  /// awaits. It completes when those runs are finished, or after
  /// [awaitTerminationPeriod]. Otherwise it returns `null` at once.
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
    } on Object catch (error, stackTrace) {
      _failed(error, stackTrace);
      _completed();
      return;
    }
    if (result is Future) {
      unawaited(
        result.then(
          (_) => _completed(),
          onError: (Object error, StackTrace stackTrace) {
            _failed(error, stackTrace);
            _completed();
          },
        ),
      );
    } else {
      _completed();
    }
  }

  void _failed(Object error, StackTrace stackTrace) {
    final handler = _scheduler.errorHandler;
    if (handler == null) {
      _log.error(
        'Scheduled task $name failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'task': name},
      );
      return;
    }
    try {
      handler.handleError(error, stackTrace);
    } on Object catch (propagated, propagatedTrace) {
      // Spring: an error escaping the handler suppresses later runs.
      _log.error(
        'Scheduled task $name failed and will not run again',
        error: propagated,
        stackTrace: propagatedTrace,
        fields: {'task': name},
      );
      cancel();
    }
  }

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
