import 'dart:async';

import 'package:clock/clock.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/trigger.dart';

/// The work a [TaskScheduler] runs: a function without parameters. It may
/// return a `Future`; the run then counts as finished when the future
/// completes, and the next run is planned only after that.
typedef ScheduledFunction = FutureOr<void> Function();

/// A function that creates a timer, which [TimerTaskScheduler] uses for
/// every wait. The default is [Timer.new]; a test may pass timers of a fake
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
  /// after [initialDelay] (at once by default). Runs never overlap: after
  /// a run longer than the period (or one that started late), the runs
  /// that came due meanwhile start one after the other until the rate is
  /// caught up, as Spring's `scheduleAtFixedRate` does.
  ///
  /// That includes a pause of the whole process: stopped (`SIGSTOP`), a
  /// hidden browser tab whose timers were throttled, a mobile app the
  /// system suspended in the background (the Flutter starter pauses
  /// `@Scheduled` tasks there, not the tasks started here). When it runs
  /// again, every run missed meanwhile starts at once, back to back: a
  /// 1-second rate after a minute suspended runs about 60 times. For a
  /// poll or a UI tick, where only the latest run matters, use
  /// [scheduleWithFixedDelay], which runs once and goes on, or cancel the
  /// task when the screen goes away.
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
/// A task keeps its schedule until it is cancelled, also while a Flutter
/// app is in the background (the starter pauses only `@Scheduled`
/// tasks). A fixed-rate one catches up every run missed while the system
/// suspended the app, all at once when it comes back; a fixed-delay one
/// runs once and goes on, which is what a tick or a poll wants.
///
/// ```dart
/// // The clock ticks while the timer screen is open: with a fixed delay,
/// // back from the background it ticks once, not once a missed second.
/// final task =
///     scheduler.scheduleWithFixedDelay(tick, const Duration(seconds: 1));
/// ...
/// task.cancel(); // the screen closed
/// ```
///
/// Spring (Java):
/// ```java
/// ScheduledFuture<?> task =
///     scheduler.scheduleWithFixedDelay(this::tick, Duration.ofSeconds(1));
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

/// The longest single timer a [TimerTaskScheduler] arms; a longer wait is
/// made of several. Far below JavaScript's limit of 2^31-1 ms, and a cron
/// or one-shot wait checks the wall clock at each step (a laptop that
/// slept catches up).
const _maxWait = Duration(days: 1);

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
/// // A test that runs a 5-minute schedule without waiting 5 minutes:
/// // fake_async fakes the timers and `clock.now()`, which the scheduler
/// // reads by default (as does a Flutter widget test's `tester.pump`).
/// fakeAsync((async) {
///   final scheduler = TimerTaskScheduler();
///   scheduler.scheduleAtFixedRate(refresh, const Duration(minutes: 5));
///   async.elapse(const Duration(minutes: 10)); // three runs, now
///   scheduler.shutdown();
/// });
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
/// It behaves like a `ThreadPoolTaskScheduler` with one thread: a
/// fixed-rate task that falls behind catches up the runs it missed, one
/// after the other, never two at once.
///
/// Fixed-rate and fixed-delay tasks never read the wall clock: as Spring's
/// executor counts on a monotonic clock, each task keeps a timeline that
/// its timers move. A timer armed for a wait moves it by that wait when it
/// fires, or by the real time it took (a monotonic `Stopwatch`) when that
/// is longer: a real timer that fires late (a blocked isolate) counts
/// late. Under a clock of its own (`withClock`, or the `now` given), the
/// real time counted is at most what that clock moved, so fake timers
/// (fake_async, widget tests) move it by exactly their wait, however long
/// the test takes in real time. A fixed-rate run is due a period after the
/// previous one was due; the timer goes on during a run, and the runs that
/// came due meanwhile start one after the other when it ends (Spring's
/// `scheduleAtFixedRate` catches up the same way, also after the process
/// was suspended: see [scheduleAtFixedRate]). A fixed-delay task arms its
/// delay when a run ends. So setting the wall clock moves none of their
/// runs, and neither does a clock of its own that stands still, runs slow
/// or fast, or jumps while real timers wait.
///
/// Counting no more than that clock moved keeps a clock faster than the
/// timers from running a task twice, and tests from depending on the
/// machine's speed. It has two limits, both under a clock of its own:
///
/// - On real timers, a timer counts late only as far as that clock moved:
///   under `Clock.fixed`, or a slower clock, a blocked isolate's missed
///   runs are skipped rather than caught up, and each run comes as late
///   after the one before as its timer fired (a fraction of a
///   millisecond).
/// - On fake timers, the timeline moves by the timers' waits alone, never
///   by how far the clock went past them. A clock moved without firing
///   the timers (fake_async's `elapseBlocking`, standing for a blocked
///   isolate) makes the run that was due come when the timers next fire,
///   skips the others missed meanwhile, and shifts every later run by the
///   delay: with a 60-second rate, `elapseBlocking` of 130 seconds at 30
///   seconds gives runs at 0, 160, 220, 280 seconds..., where Spring would
///   run at 160, 160, 180, 240.... Fake timers fired by `elapse` (or
///   `tester.pump`) keep the exact pace.
///
/// Cron expressions, [scheduleAt] and other triggers plan with [now], the
/// wall clock, and the timers wait the planned delay: when the wall clock
/// is set back during a wait, the run comes early by the wall clock, once,
/// and the next time is planned from the wall clock again.
///
/// Waits of any length work on every platform, browsers and Node.js
/// included (where one timer cannot wait more than 24.8 days): a long wait
/// is made of timers of at most a day, and a timer that fires before the
/// time has come is armed again for the rest. Between those timers, a cron
/// or [scheduleAt] wait checks the wall clock, so it ends within a day of
/// the wall clock passing its time (after a computer slept, say).
final class TimerTaskScheduler implements TaskScheduler, DisposableBean {
  /// A scheduler that reads the time from `now` and waits with timers from
  /// `createTimer`; by default `clock.now()` of `package:clock` and
  /// [Timer.new]. That is the real clock, or the fake one of `fake_async`
  /// and Flutter widget tests, which move it with their fake timers. A
  /// test with timers of its own passes both from the same fake clock.
  /// Fixed-rate and fixed-delay tasks count the waits of the timers, never
  /// more real time than `now` (or `clock`) moved meanwhile.
  ///
  /// [awaitTermination] and [awaitTerminationPeriod] control how [destroy]
  /// waits for runs going on; [errorHandler] receives the errors of the
  /// tasks.
  TimerTaskScheduler({
    this._now,
    this._createTimer,
    this.awaitTermination = false,
    this.awaitTerminationPeriod,
    this.errorHandler,
  });

  final DateTime Function()? _now;
  final TimerFactory? _createTimer;
  // Real time, monotonic: setting the wall clock does not move it.
  final _stopwatch = Stopwatch()..start();
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
  DateTime now() => _now?.call() ?? clock.now();

  // The time of a clock of its own: the `now` given, or a `clock` of its
  // own (`withClock`, as fake_async and widget tests set); `null` with
  // the default clock, the wall clock, which fixed-rate and fixed-delay
  // tasks never read.
  Duration? _ownClock() => _now == null && identical(clock, const Clock())
      ? null
      : Duration(microseconds: now().microsecondsSinceEpoch);

  // How long since a timer was armed at [watch] (of the stopwatch) and
  // [ownClock] (_ownClock): the stopwatch, but under a clock of its own
  // no more than that clock moved. Fake timers fire when their clock has
  // moved by the wait, however long the test took in real time, so a
  // fake timer is never counted late.
  Duration _since(Duration watch, Duration? ownClock) {
    final real = _stopwatch.elapsed - watch;
    final clockNow = ownClock == null ? null : _ownClock();
    if (clockNow == null) {
      return real;
    }
    final moved = clockNow - ownClock!;
    return moved >= real
        ? real
        : moved > Duration.zero
        ? moved
        : Duration.zero;
  }

  Timer _timer(Duration delay, void Function() callback) =>
      (_createTimer ?? Timer.new)(delay, callback);

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
    scheduled._start();
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
  var _running = false;

  // A fixed-rate or fixed-delay task keeps a timeline of its own: [_pos]
  // its time when last moved, [_due] when the next run is due on it. A
  // timer armed for a wait moves it by that wait when it fires, or by the
  // time it really took when longer (real timers firing late; see
  // TimerTaskScheduler._since): the wall clock plays no part. [_armedAt],
  // [_armedWatch] and [_armedClock] are the timeline, the stopwatch and
  // the clock of its own when the timer was armed.
  Duration _pos = Duration.zero;
  Duration _due = Duration.zero;
  Duration _armedAt = Duration.zero;
  Duration _armedWatch = Duration.zero;
  Duration? _armedClock;

  // The runs of a fixed-rate task that are due and not started yet: its
  // timer goes on during a run, and the runs it finds due start one after
  // the other when the run ends, as Spring's scheduleAtFixedRate catches
  // up (never two at once).
  var _owed = 0;
  Timer? _catchUp;

  @override
  DateTime? get nextExecution => _next;

  @override
  int get runs => _runs;

  @override
  bool get isCancelled => _cancelled;

  void _start() {
    if (trigger case final PeriodicTrigger periodic) {
      _due = periodic.initialDelay;
      _next = _scheduler.now().add(_due);
      _tick(_due);
      return;
    }
    _plan();
  }

  /// Arms the timer of a fixed-rate or fixed-delay task for [remaining] on
  /// its timeline; when it fires, the timeline moves by the wait.
  void _tick(Duration remaining) {
    final wait = _timerWait(remaining);
    final at = _armedAt = _pos;
    final watch = _armedWatch = _scheduler._stopwatch.elapsed;
    final ownClock = _armedClock = _scheduler._ownClock();
    _timer = _scheduler._timer(wait, () {
      _timer = null;
      if (_cancelled) {
        return;
      }
      final waited = _scheduler._since(watch, ownClock);
      _pos = at + (waited > wait ? waited : wait);
      _ticked();
    });
  }

  // The timer of a fixed-rate or fixed-delay task fired.
  void _ticked() {
    final periodic = trigger as PeriodicTrigger;
    if (_pos < _due) {
      // A part of a wait longer than a timer waits.
      _tick(_due - _pos);
      return;
    }
    if (!periodic.fixedRate) {
      _run(_next ?? _scheduler.now());
      return;
    }
    // Each due time passed is a run owed; the timer goes on to the next
    // one, a run going on or not.
    while (_due <= _pos) {
      _owed++;
      _due += periodic.period;
    }
    _tick(_due - _pos);
    _runOwed();
  }

  void _runOwed() {
    if (_cancelled || _running || _owed == 0) {
      return;
    }
    _owed--;
    _run(_next ?? _scheduler.now());
  }

  // Where the timeline of a fixed-rate task is now, between two timers.
  Duration _position() =>
      _armedAt + _scheduler._since(_armedWatch, _armedClock);

  /// Plans the next run of a cron, one-shot or other trigger, from the
  /// wall clock ([TimerTaskScheduler.now]).
  void _plan() {
    if (_cancelled) {
      return;
    }
    final now = _scheduler.now();
    final next = _next = trigger.nextExecution(
      TriggerContext(
        now: now,
        lastScheduledExecution: _lastScheduled,
        lastActualExecution: _lastActual,
        lastCompletion: _lastCompletion,
      ),
    );
    if (next == null) {
      _scheduler._tasks.remove(this);
      return;
    }
    _wait(next, next.difference(now));
  }

  /// The timer's wait for [remaining]: at most [_maxWait], as JavaScript's
  /// `setTimeout` (browsers, Node.js, edge runtimes) fires at once for
  /// more than 2^31-1 ms (24.8 days), which ran a yearly cron in a loop;
  /// rounded up to whole milliseconds, as timers truncate it.
  static Duration _timerWait(Duration remaining) {
    if (remaining > _maxWait) {
      return _maxWait;
    }
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return Duration(milliseconds: (remaining.inMicroseconds + 999) ~/ 1000);
  }

  /// Arms the timer for the run of a cron, one-shot or other trigger due
  /// at [scheduled], [remaining] from now; a longer wait than a timer
  /// waits is split.
  void _wait(DateTime scheduled, Duration remaining) {
    final wait = _timerWait(remaining);
    _timer = _scheduler._timer(wait, () => _fired(scheduled, remaining - wait));
  }

  /// A timer fired, [remaining] before [scheduled] by the timers' own
  /// count. The task runs only when the time has come; otherwise the timer
  /// is armed again for the rest.
  ///
  /// The time has come when the timers have waited the whole delay
  /// ([remaining] is zero), as with Spring's executor: a wall clock set
  /// back does not hold a task. Or when the wall clock says so (a
  /// computer that slept through a long wait).
  void _fired(DateTime scheduled, Duration remaining) {
    _timer = null;
    if (_cancelled) {
      return;
    }
    final byClock = scheduled.difference(_scheduler.now());
    final left = byClock < remaining ? byClock : remaining;
    if (left > Duration.zero) {
      _wait(scheduled, left);
      return;
    }
    _run(scheduled);
  }

  void _run(DateTime scheduled) {
    _next = null;
    _lastScheduled = scheduled;
    _lastActual = _scheduler.now();
    _runs++;
    _running = true;
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
    _running = false;
    final now = _lastCompletion = _scheduler.now();
    _scheduler._finished(this);
    if (_cancelled) {
      return;
    }
    switch (trigger) {
      case PeriodicTrigger(fixedRate: false, :final period):
        // Fixed delay: the wait starts now.
        _pos = Duration.zero;
        _due = period;
        _next = now.add(period);
        _tick(period);
      case PeriodicTrigger():
        if (_owed > 0) {
          // The next run is due already: right after this one, through a
          // timer (a long series of synchronous runs never nests).
          _next = now;
          _catchUp ??= _scheduler._timer(Duration.zero, () {
            _catchUp = null;
            _runOwed();
          });
        } else {
          _next = now.add(_due - _position());
        }
      default:
        _plan();
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    _next = null;
    _timer?.cancel();
    _timer = null;
    _catchUp?.cancel();
    _catchUp = null;
    _scheduler._tasks.remove(this);
  }

  @override
  String toString() => 'ScheduledTask($name, $trigger)';
}
