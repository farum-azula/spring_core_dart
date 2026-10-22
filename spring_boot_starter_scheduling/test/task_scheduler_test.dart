import 'dart:async';

import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:test/test.dart';

import 'fake_clock.dart';

final start = DateTime.utc(2026, 1, 1, 12);

void main() {
  late FakeClock clock;
  late TimerTaskScheduler scheduler;
  late List<SpringLogRecord> logs;
  late SpringLogHandler previousHandler;

  setUp(() {
    clock = FakeClock(start);
    scheduler = TimerTaskScheduler(now: clock.now, createTimer: clock.timer);
    logs = [];
    previousHandler = SpringLog.handler;
    SpringLog.handler = logs.add;
  });
  tearDown(() {
    scheduler.shutdown();
    SpringLog.handler = previousHandler;
  });

  group('triggers', () {
    TriggerContext context({DateTime? scheduled, DateTime? completion}) =>
        TriggerContext(
          now: start,
          lastScheduledExecution: scheduled,
          lastActualExecution: scheduled,
          lastCompletion: completion,
        );

    test('fixed delay counts from completion', () {
      final trigger = PeriodicTrigger(const Duration(seconds: 10));
      expect(trigger.nextExecution(context()), start);
      expect(
        trigger.nextExecution(
          context(
            scheduled: start,
            completion: start.add(const Duration(seconds: 3)),
          ),
        ),
        start.add(const Duration(seconds: 13)),
      );
    });

    test('fixed rate counts between starts, without catching up', () {
      final trigger = PeriodicTrigger(
        const Duration(seconds: 10),
        fixedRate: true,
        initialDelay: const Duration(seconds: 5),
      );
      expect(
        trigger.nextExecution(context()),
        start.add(const Duration(seconds: 5)),
      );
      expect(
        trigger.nextExecution(
          context(
            scheduled: start,
            completion: start.add(const Duration(seconds: 2)),
          ),
        ),
        start.add(const Duration(seconds: 10)),
      );
      // A 25 s run: the next one starts when it completes, once.
      expect(
        trigger.nextExecution(
          context(
            scheduled: start,
            completion: start.add(const Duration(seconds: 25)),
          ),
        ),
        start.add(const Duration(seconds: 25)),
      );
    });

    test('periodic triggers reject non-positive periods', () {
      expect(() => PeriodicTrigger(Duration.zero), throwsArgumentError);
      expect(
        () => PeriodicTrigger(
          const Duration(seconds: 1),
          initialDelay: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('cron trigger starts from the completion or the due time', () {
      final trigger = CronTrigger(
        CronExpression.parse('0 */10 * * * *'),
        utc: true,
      );
      expect(
        trigger.nextExecution(context()),
        start.add(const Duration(minutes: 10)),
      );
      // Completed early (clock drift): still after the due time.
      expect(
        trigger.nextExecution(
          context(
            scheduled: start.add(const Duration(minutes: 10)),
            completion: start.add(const Duration(minutes: 9, seconds: 59)),
          ),
        ),
        start.add(const Duration(minutes: 20)),
      );
      // A run that took 25 minutes skips the missed times.
      expect(
        trigger.nextExecution(
          context(
            scheduled: start.add(const Duration(minutes: 10)),
            completion: start.add(const Duration(minutes: 35)),
          ),
        ),
        start.add(const Duration(minutes: 40)),
      );
    });

    test('one-shot trigger', () {
      final trigger = OneShotTrigger(start.add(const Duration(hours: 1)));
      expect(
        trigger.nextExecution(context()),
        start.add(const Duration(hours: 1)),
      );
      expect(trigger.nextExecution(context(scheduled: start)), isNull);
    });
  });

  group('TimerTaskScheduler', () {
    test('fixed rate', () {
      final runs = <DateTime>[];
      final task = scheduler.scheduleAtFixedRate(
        () => runs.add(clock.now()),
        const Duration(seconds: 10),
        initialDelay: const Duration(seconds: 1),
        name: 'tick',
      );
      expect(task.nextExecution, start.add(const Duration(seconds: 1)));
      clock.elapse(const Duration(seconds: 31));
      expect(runs, [
        for (final s in [1, 11, 21, 31]) start.add(Duration(seconds: s)),
      ]);
      expect(task.runs, 4);
      expect(task.name, 'tick');
      expect(scheduler.tasks, [task]);
    });

    test('fixed delay waits for asynchronous runs', () async {
      final starts = <DateTime>[];
      scheduler.scheduleWithFixedDelay(() async {
        starts.add(clock.now());
        // The run "takes" 4 seconds of the fake clock.
        await Future<void>.delayed(Duration.zero);
        clock.elapse(const Duration(seconds: 4));
      }, const Duration(seconds: 10));
      await clock.elapseAsync(const Duration(seconds: 30));
      expect(starts, [
        start,
        start.add(const Duration(seconds: 14)),
        start.add(const Duration(seconds: 28)),
      ]);
    });

    test('fixed rate never overlaps a long asynchronous run', () async {
      final starts = <DateTime>[];
      var running = 0;
      var maxRunning = 0;
      final done = <Completer<void>>[];
      scheduler.scheduleAtFixedRate(() {
        starts.add(clock.now());
        running++;
        maxRunning = running > maxRunning ? running : maxRunning;
        final completer = Completer<void>();
        done.add(completer);
        return completer.future.whenComplete(() => running--);
      }, const Duration(seconds: 10));
      await clock.elapseAsync(Duration.zero);
      expect(starts, [start]);
      await clock.elapseAsync(const Duration(seconds: 25));
      expect(starts, [start], reason: 'still running');
      done.last.complete();
      await clock.elapseAsync(Duration.zero);
      // Started right after the long run, once; then every 10 s again.
      expect(starts, [start, start.add(const Duration(seconds: 25))]);
      done.last.complete();
      await clock.elapseAsync(const Duration(seconds: 10));
      expect(starts.last, start.add(const Duration(seconds: 35)));
      expect(maxRunning, 1);
    });

    test('errors are logged and the task keeps running', () async {
      var calls = 0;
      scheduler.scheduleAtFixedRate(
        () {
          calls++;
          throw StateError('boom $calls');
        },
        const Duration(seconds: 1),
        name: 'Jobs.flaky',
      );
      scheduler.scheduleAtFixedRate(
        () => Future<void>.error(ArgumentError('async boom')),
        const Duration(seconds: 1),
        name: 'Jobs.asyncFlaky',
      );
      await clock.elapseAsync(const Duration(seconds: 2));
      expect(calls, 3);
      final errors = logs
          .where((r) => r.level == SpringLogLevel.error)
          .toList();
      expect(
        errors.map((r) => r.message),
        containsAll([
          'Scheduled task Jobs.flaky failed',
          'Scheduled task Jobs.asyncFlaky failed',
        ]),
      );
      expect(errors.first.loggerName, 'spring.scheduling');
      expect(errors.first.error, isA<StateError>());
    });

    test('cancel and shutdown', () {
      var runs = 0;
      final task = scheduler.scheduleAtFixedRate(
        () => runs++,
        const Duration(seconds: 1),
      );
      clock.elapse(const Duration(seconds: 2));
      expect(runs, 3);
      task.cancel();
      expect(task.isCancelled, isTrue);
      expect(task.nextExecution, isNull);
      clock.elapse(const Duration(seconds: 5));
      expect(runs, 3);
      expect(clock.pendingTimers, 0);

      scheduler.scheduleAtFixedRate(() => runs++, const Duration(seconds: 1));
      scheduler.shutdown();
      expect(scheduler.isShutdown, isTrue);
      expect(scheduler.tasks, isEmpty);
      expect(clock.pendingTimers, 0);
      expect(
        () => scheduler.schedule(() {}, OneShotTrigger(start)),
        throwsStateError,
      );
    });

    test('a trigger returning null ends the task', () {
      var runs = 0;
      final task = scheduler.schedule(
        () => runs++,
        OneShotTrigger(start.add(const Duration(minutes: 1))),
      );
      clock.elapse(const Duration(hours: 1));
      expect(runs, 1);
      expect(task.nextExecution, isNull);
      expect(scheduler.tasks, isEmpty);
    });

    test('runs on real timers by default', () async {
      final real = TimerTaskScheduler();
      final ran = Completer<void>();
      real.schedule(ran.complete, OneShotTrigger(DateTime.now()));
      await ran.future.timeout(const Duration(seconds: 5));
      real.destroy();
      expect(real.isShutdown, isTrue);
    });
  });
}
