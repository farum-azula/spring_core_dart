import 'package:spring_boot_starter_scheduling/src/cron_expression.dart';

/// The facts a [Trigger] gets to decide the next run of its task: the
/// current time, and when the previous run was due, started and finished.
///
/// The scheduler creates one before each run and passes it to
/// [Trigger.nextExecution]; all the previous-run times are `null` before
/// the first run. Code creates one only to ask a trigger by hand, such as
/// in a test or to show when a schedule would first run.
///
/// ```dart
/// // When would this cron trigger run first, if scheduled now?
/// final first = CronTrigger(CronExpression.parse('0 0 9 * * MON-FRI'))
///     .nextExecution(TriggerContext(now: DateTime.now()));
/// ```
///
/// Spring (Java):
/// ```java
/// TriggerContext context = new SimpleTriggerContext();
/// trigger.nextExecution(context);
/// ```
final class TriggerContext {
  /// The facts at [now]; leave the other times out before the first run.
  TriggerContext({
    required this.now,
    this.lastScheduledExecution,
    this.lastActualExecution,
    this.lastCompletion,
  });

  /// The current time of the scheduler's clock (`TaskScheduler.now`),
  /// which a test may control.
  final DateTime now;

  /// When the previous run was due, as the trigger returned it; `null`
  /// before the first run.
  final DateTime? lastScheduledExecution;

  /// When the previous run actually started, which can be later than it
  /// was due; `null` before the first run.
  final DateTime? lastActualExecution;

  /// When the previous run finished, after its `Future` completed;
  /// `null` before the first run.
  final DateTime? lastCompletion;
}

/// The rule that decides when a scheduled task runs next.
///
/// A `TaskScheduler` asks its trigger for the first run, and again after
/// each run, and stops the task when the trigger returns `null`. The
/// provided triggers cover the usual schedules: [PeriodicTrigger] (fixed
/// rate or delay), [CronTrigger] and `OneShotTrigger`. Implement this
/// interface for a schedule they cannot express, such as a delay that
/// grows after each run or a task that stops after a date. `@Scheduled`
/// builds its trigger itself.
///
/// ```dart
/// // Polls quickly at first, then backs off up to every 10 minutes.
/// final class BackOff implements Trigger {
///   var _delay = const Duration(seconds: 5);
///
///   @override
///   DateTime? nextExecution(TriggerContext context) {
///     final next = (context.lastCompletion ?? context.now).add(_delay);
///     if (_delay < const Duration(minutes: 10)) {
///       _delay *= 2;
///     }
///     return next;
///   }
/// }
///
/// scheduler.schedule(checkInbox, BackOff());
/// ```
///
/// Spring (Java):
/// ```java
/// class BackOff implements Trigger {
///   private Duration delay = Duration.ofSeconds(5);
///
///   @Override
///   public Instant nextExecution(TriggerContext context) {
///     Instant last = context.lastCompletion();
///     Instant next = (last != null ? last : context.getClock().instant())
///         .plus(delay);
///     if (delay.compareTo(Duration.ofMinutes(10)) < 0) {
///       delay = delay.multipliedBy(2);
///     }
///     return next;
///   }
/// }
/// ```
abstract interface class Trigger {
  /// When the task should run next, given the runs described by
  /// [context]. A time in the past runs it at once; `null` ends the task.
  DateTime? nextExecution(TriggerContext context);
}

/// A [Trigger] that runs a task at the times of a [CronExpression], such
/// as 9:00 on working days.
///
/// `@Scheduled(cron: ...)` uses it. Create one yourself to start a cron
/// schedule from code, for example when the expression is chosen by a
/// user at runtime.
///
/// The next time is computed from the end of the previous run (or from
/// when it was due, if that is later), so a run that takes longer than
/// the interval skips the times it missed.
///
/// ```dart
/// // The cleanup time is a user setting, so it is scheduled in code.
/// final trigger = CronTrigger(CronExpression.parse(settings.cleanupCron));
/// scheduler.schedule(cleanUp, trigger, name: 'cleanup');
/// ```
///
/// Spring (Java):
/// ```java
/// scheduler.schedule(this::cleanUp, new CronTrigger("0 */10 * * * *"));
/// ```
final class CronTrigger implements Trigger {
  /// A trigger at the times of [expression], read in local time, or in
  /// UTC when [utc] is `true`.
  CronTrigger(this.expression, {this.utc = false});

  /// The times the task runs at.
  final CronExpression expression;

  /// Whether [expression] is read in UTC rather than local time.
  final bool utc;

  @override
  DateTime? nextExecution(TriggerContext context) {
    var base = context.lastCompletion ?? context.now;
    final scheduled = context.lastScheduledExecution;
    if (context.lastCompletion != null &&
        scheduled != null &&
        base.isBefore(scheduled)) {
      base = scheduled;
    }
    final next = expression.next(utc ? base.toUtc() : base.toLocal());
    return next;
  }

  @override
  String toString() =>
      'CronTrigger(${expression.expression}'
      '${utc ? ', UTC' : ''})';
}

/// A [Trigger] that runs a task again and again with a fixed interval:
/// [period] after each run ends (fixed delay, the default), or every
/// [period] between starts ([fixedRate]).
///
/// `@Scheduled(fixedRate:)`, `@Scheduled(fixedDelay:)` and the
/// `TaskScheduler.scheduleAtFixedRate` and `scheduleWithFixedDelay`
/// methods use it; create one yourself only to pass it to
/// `TaskScheduler.schedule`.
///
/// A fixed-rate run never overlaps the previous one. Each run is due
/// [period] after the one before was due, as in Spring: when a run takes
/// longer than [period], the runs that came due meanwhile start one after
/// the other as soon as it completes, until the rate is caught up.
///
/// A `TimerTaskScheduler` applies these rules on a timeline its timers
/// move, as Spring's `scheduleAtFixedRate` and `scheduleWithFixedDelay`
/// count on a monotonic clock: setting the wall clock moves no run.
///
/// ```dart
/// // A poll that keeps 30 s between the end of one and the next start.
/// scheduler.schedule(poll, PeriodicTrigger(Duration(seconds: 30)));
/// // A refresh every 5 minutes, the first one 10 s after the start.
/// scheduler.schedule(
///   refresh,
///   PeriodicTrigger(Duration(minutes: 5), fixedRate: true,
///       initialDelay: Duration(seconds: 10)),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// PeriodicTrigger trigger = new PeriodicTrigger(Duration.ofMinutes(5));
/// trigger.setFixedRate(true);
/// trigger.setInitialDelay(Duration.ofSeconds(10));
/// ```
final class PeriodicTrigger implements Trigger {
  /// A trigger every [period], measured between starts when [fixedRate]
  /// is `true`, else from the end of a run. The first run comes
  /// [initialDelay] after the task is scheduled, at once by default.
  /// Throws an [ArgumentError] when [period] is not positive or
  /// [initialDelay] is negative.
  PeriodicTrigger(
    this.period, {
    this.fixedRate = false,
    this.initialDelay = Duration.zero,
  }) {
    if (period <= Duration.zero) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    if (initialDelay.isNegative) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'must not be negative',
      );
    }
  }

  /// The time between runs: between two starts with [fixedRate], else
  /// from the end of one run to the start of the next.
  final Duration period;

  /// Whether [period] is measured between starts (`true`) or from the end
  /// of a run to the next start (`false`, the default).
  final bool fixedRate;

  /// How long after scheduling the first run comes; zero by default.
  final Duration initialDelay;

  @override
  DateTime? nextExecution(TriggerContext context) {
    final scheduled = context.lastScheduledExecution;
    final completion = context.lastCompletion;
    if (scheduled == null) {
      return context.now.add(initialDelay);
    }
    if (!fixedRate) {
      return (completion ?? context.now).add(period);
    }
    // Before the completion when the run took longer than the period: the
    // scheduler starts it right away (Spring's PeriodicTrigger as well).
    return scheduled.add(period);
  }

  @override
  String toString() {
    final delay = initialDelay == Duration.zero
        ? ''
        : ', initialDelay: $initialDelay';
    return 'PeriodicTrigger(${fixedRate ? 'fixedRate' : 'fixedDelay'}: $period'
        '$delay)';
  }
}
