import 'dart:async';

import 'package:clock/clock.dart' show Clock, withClock;
import 'package:fake_async/fake_async.dart';

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

    test('fixed rate counts between starts and catches up, as in '
        'Spring', () {
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
      // A 25 s run: the next one was due at 10 s already, so it starts
      // when this one completes (Spring's PeriodicTrigger answers the same).
      expect(
        trigger.nextExecution(
          context(
            scheduled: start,
            completion: start.add(const Duration(seconds: 25)),
          ),
        ),
        start.add(const Duration(seconds: 10)),
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

    test('scheduleAt runs once at the start time, like schedule(task, '
        'Instant)', () {
      final runs = <DateTime>[];
      final task = scheduler.scheduleAt(
        () => runs.add(clock.now()),
        start.add(const Duration(minutes: 2)),
        name: 'once',
      );
      expect(task.nextExecution, start.add(const Duration(minutes: 2)));
      clock.elapse(const Duration(hours: 1));
      expect(runs, [start.add(const Duration(minutes: 2))]);
      expect(task.runs, 1);
      expect(scheduler.tasks, isEmpty);
      // A past start time runs right away.
      scheduler.scheduleAt(
        () => runs.add(clock.now()),
        start.subtract(const Duration(days: 1)),
      );
      clock.elapse(Duration.zero);
      expect(runs, hasLength(2));
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

    // The runs missed during a long run were skipped: Spring's
    // scheduleAtFixedRate runs them back to back after it.
    test('fixed rate never overlaps a long asynchronous run; the runs '
        'missed follow it back to back, as in Spring', () async {
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
      // The run due at 10 s, right after the long run.
      expect(starts, [start, start.add(const Duration(seconds: 25))]);
      done.last.complete();
      await clock.elapseAsync(Duration.zero);
      // The one due at 20 s, right after it.
      expect(starts, [
        start,
        for (var i = 0; i < 2; i++) start.add(const Duration(seconds: 25)),
      ]);
      done.last.complete();
      await clock.elapseAsync(const Duration(seconds: 10));
      // Caught up: the one due at 30 s at 30 s.
      expect(starts.last, start.add(const Duration(seconds: 30)));
      expect(starts, hasLength(4));
      expect(maxRunning, 1);
    });

    test('errors are logged and the task keeps running', () async {
      var calls = 0;
      scheduler
        ..scheduleAtFixedRate(
          () {
            calls++;
            throw StateError('boom $calls');
          },
          const Duration(seconds: 1),
          name: 'Jobs.flaky',
        )
        ..scheduleAtFixedRate(
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

      scheduler
        ..scheduleAtFixedRate(() => runs++, const Duration(seconds: 1))
        ..shutdown();
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

    // JavaScript's setTimeout fires at once beyond 2^31-1 ms (24.8 days):
    // without splitting the wait, a yearly cron ran in a loop. Run with
    // `dart test -p node` too.
    test('long waits on real timers do not fire early', () async {
      final real = TimerTaskScheduler();
      addTearDown(real.shutdown);
      var delayed = 0;
      var delayedOnce = 0;
      var yearly = 0;
      var later = 0;
      real
        ..scheduleWithFixedDelay(
          () => delayed++,
          const Duration(days: 30),
          initialDelay: const Duration(days: 30),
        )
        // Runs once at once, then waits 30 days.
        ..scheduleWithFixedDelay(
          () => delayedOnce++,
          const Duration(days: 30),
        )
        ..schedule(
          () => yearly++,
          CronTrigger(CronExpression.parse('0 0 0 1 1 *'), utc: true),
        )
        ..scheduleAt(
          () => later++,
          DateTime.now().add(const Duration(days: 400)),
        );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delayed, 0);
      expect(delayedOnce, 1);
      // 0 unless the test runs at midnight, New Year's Day (UTC).
      expect(yearly, lessThanOrEqualTo(1));
      expect(later, 0);
      expect(real.tasks, hasLength(4));
    });

    test('a long wait is made of timers of at most a day', () {
      final delays = <Duration>[];
      final split = TimerTaskScheduler(
        now: clock.now,
        createTimer: (delay, callback) {
          delays.add(delay);
          return clock.timer(delay, callback);
        },
      );
      addTearDown(split.shutdown);
      var runs = 0;
      split.scheduleAt(
        () => runs++,
        start.add(const Duration(days: 30, hours: 6)),
      );
      expect(delays, [const Duration(days: 1)]);
      clock.elapse(const Duration(days: 30));
      expect(runs, 0);
      clock.elapse(const Duration(hours: 6));
      expect(runs, 1);
      expect(delays, [
        for (var i = 0; i < 30; i++) const Duration(days: 1),
        const Duration(hours: 6),
      ]);
    });

    test('a yearly cron runs once a year', () {
      var runs = 0;
      scheduler.schedule(
        () => runs++,
        CronTrigger(CronExpression.parse('0 0 0 1 1 *'), utc: true),
      );
      clock.elapse(const Duration(days: 364));
      expect(runs, 0);
      clock.elapse(const Duration(days: 2));
      expect(runs, 1);
    });

    test('a timer that fires before the time has come is armed again', () {
      // A timer that fires at once, whatever its delay (what setTimeout
      // does beyond 2^31-1 ms); the clock moves only by elapse.
      final early = <void Function()>[];
      final eager = TimerTaskScheduler(
        now: clock.now,
        createTimer: (delay, callback) {
          final timer = clock.timer(Duration.zero, () {});
          early.add(callback);
          return timer;
        },
      );
      addTearDown(eager.shutdown);
      var runs = 0;
      eager.scheduleAt(() => runs++, start.add(const Duration(days: 30)));
      // Ten one-day timers fire at once: the clock and the timers' own
      // count both say the 30 days are not over.
      for (var i = 0; i < 10; i++) {
        early.removeAt(0)();
      }
      expect(runs, 0);
      expect(eager.tasks, hasLength(1));
      expect(early, hasLength(1), reason: 'armed again for the rest');
    });

    test('a clock that stands still does not hold the runs', () {
      // The runs come when the timers have waited the delay, as with
      // Spring's executor (a wall clock set back does not hold them).
      final frozen = FakeClock(start);
      final timers = FakeClock(start);
      final pumped = TimerTaskScheduler(
        now: frozen.now,
        createTimer: timers.timer,
      );
      addTearDown(pumped.shutdown);
      var minutely = 0;
      var monthly = 0;
      pumped
        ..scheduleAtFixedRate(
          () => minutely++,
          const Duration(minutes: 1),
          initialDelay: const Duration(minutes: 1),
        )
        ..scheduleAt(() => monthly++, start.add(const Duration(days: 30)));
      timers.elapse(const Duration(minutes: 1));
      expect(minutely, 1);
      timers.elapse(const Duration(days: 30));
      expect(monthly, 1);
    });

    test('on real timers, a fixed rate with asynchronous runs keeps its '
        'pace', () async {
      final real = TimerTaskScheduler();
      addTearDown(real.shutdown);
      final stopwatch = Stopwatch()..start();
      final starts = <int>[];
      real.scheduleAtFixedRate(() async {
        starts.add(stopwatch.elapsedMilliseconds);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }, const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 520));
      real.shutdown();
      // Due at 0, 50, ..., 500 ms; never before its time. Counted from
      // the end of each run instead, it would be 0, 80, 160, ... ms.
      expect(starts.length, greaterThanOrEqualTo(9), reason: '$starts');
      for (final (i, start) in starts.indexed) {
        expect(start, greaterThanOrEqualTo(i * 50 - 2), reason: '$starts');
      }
    });
  });

  // A `clock` of its own (withClock) was taken to mean fake timers: on
  // real timers under Clock.fixed, each wait of a 50 ms fixed rate was
  // 50 ms longer than the one before (11 runs in 3.2 s instead of 65).
  // Run with `dart test -p node` too.
  test('on real timers, fixed rate and fixed delay keep their pace under a '
      'clock that stands still or goes back', () async {
    final stopwatch = Stopwatch()..start();
    for (final (name, wall) in [
      ('fixed', Clock.fixed(start)),
      ('backwards', Clock(() => start.subtract(stopwatch.elapsed * 3))),
    ]) {
      await withClock(wall, () async {
        final real = TimerTaskScheduler();
        addTearDown(real.shutdown);
        final began = stopwatch.elapsedMilliseconds;
        final rate = <int>[];
        final delay = <int>[];
        real
          ..scheduleAtFixedRate(
            () => rate.add(stopwatch.elapsedMilliseconds - began),
            const Duration(milliseconds: 50),
          )
          ..scheduleWithFixedDelay(
            () => delay.add(stopwatch.elapsedMilliseconds - began),
            const Duration(milliseconds: 50),
          );
        await Future<void>.delayed(const Duration(milliseconds: 1020));
        real.shutdown();
        // Due at 0, 50, ..., 1000 ms: 21 runs, never before their time.
        expect(rate.length, greaterThanOrEqualTo(16), reason: '$name $rate');
        for (final (i, at) in rate.indexed) {
          expect(at, greaterThanOrEqualTo(i * 50 - 2), reason: '$name $rate');
        }
        expect(delay.length, greaterThanOrEqualTo(12), reason: '$name $delay');
      });
    }
  });

  // Spring's ThreadPoolTaskScheduler (ScheduledThreadPoolExecutor's
  // `time += period`) catches up the runs missed back to back, then the
  // rate goes on; the scheduler skipped them (the reviewer's isolate
  // blocked 350..1350 ms: runs at [3, 303, 1354, 1354, 1656, 1957] ms).
  // Run with `dart test -p node` too.
  group('a fixed rate that falls behind catches up, as in Spring', () {
    void busy(int milliseconds) {
      final busy = Stopwatch()..start();
      while (busy.elapsedMilliseconds < milliseconds) {}
    }

    // The runs after the one that fell behind: three started right when
    // it ended ([end]), one after the other, then the next at [next] ms.
    void expectCaughtUp(List<int> starts, int end, int next) {
      final reason = '$starts';
      final behind = starts.where((at) => at >= end - 5 && at < end + 60);
      expect(behind, hasLength(3), reason: reason);
      final after = starts.where((at) => at >= end + 60).toList();
      expect(after, isNotEmpty, reason: reason);
      expect(
        after.first,
        inInclusiveRange(next - 2, next + 90),
        reason: reason,
      );
    }

    test('a first run that takes a second', () async {
      final real = TimerTaskScheduler();
      addTearDown(real.shutdown);
      final stopwatch = Stopwatch()..start();
      final starts = <int>[];
      real.scheduleAtFixedRate(() {
        starts.add(stopwatch.elapsedMilliseconds);
        if (starts.length == 1) busy(1000);
      }, const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 1650));
      real.shutdown();
      // Spring: [4, 1004, 1004, 1004, 1203, 1504, 1803].
      expect(starts.first, lessThan(50), reason: '$starts');
      expectCaughtUp(starts.skip(1).toList(), starts.first + 1000, 1200);
    });

    test('an isolate blocked by other work', () async {
      final real = TimerTaskScheduler();
      addTearDown(real.shutdown);
      final stopwatch = Stopwatch()..start();
      final starts = <int>[];
      real.scheduleAtFixedRate(
        () => starts.add(stopwatch.elapsedMilliseconds),
        const Duration(milliseconds: 300),
      );
      var end = 0;
      Timer(const Duration(milliseconds: 350), () {
        busy(1000);
        end = stopwatch.elapsedMilliseconds;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1650));
      real.shutdown();
      // Spring: [1, 306, 1353, 1353, 1353, 1506, 1805].
      expect(starts.take(2), [lessThan(50), inInclusiveRange(298, 349)]);
      expectCaughtUp(starts.skip(2).toList(), end, 1500);
    });

    test('a run that awaits longer than the period, on fake timers', () {
      fakeAsync((async) {
        final scheduler = TimerTaskScheduler();
        final starts = <Duration>[];
        scheduler.scheduleAtFixedRate(() {
          starts.add(async.elapsed);
          return starts.length == 1
              ? Future<void>.delayed(const Duration(seconds: 210))
              : null;
        }, const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 6));
        scheduler.shutdown();
        const behind = Duration(seconds: 210);
        expect(starts, [
          Duration.zero,
          behind, behind, behind, // due at 1, 2 and 3 minutes
          for (var m = 4; m <= 6; m++) Duration(minutes: m),
        ]);
      }, initialTime: start);
    });
  });

  // The scheduler took a `clock` that moved less than the timers for real
  // timers, and one that moved more for fake ones: on fake timers under a
  // clock that stands still, a fixed rate drifted (runs at 0, 1, 3, 6, 10
  // minutes); under a clock faster than the timers (fake or real), it ran
  // twice in a row each period.
  group('fixed rate and fixed delay keep their period whatever the clock', () {
    const period = Duration(milliseconds: 100);

    List<Duration> gaps(List<Duration> runs) => [
      for (var i = 1; i < runs.length; i++) runs[i] - runs[i - 1],
    ];

    for (final (name, wall) in [
      ('stands still', (FakeAsync _) => Clock.fixed(start)),
      (
        'runs slow (0.999x)',
        (FakeAsync async) => Clock(() => start.add(async.elapsed * 0.999)),
      ),
      (
        'runs fast (2x)',
        (FakeAsync async) => Clock(() => start.add(async.elapsed * 2)),
      ),
      (
        'jumps back and forth',
        (FakeAsync async) => Clock(
          () => start.add(
            async.elapsed +
                Duration(hours: async.elapsed.inMilliseconds ~/ 250 % 3 - 1),
          ),
        ),
      ),
    ]) {
      test('fake timers, a clock that $name', () {
        fakeAsync((async) {
          withClock(wall(async), () {
            final scheduler = TimerTaskScheduler();
            final rate = <Duration>[];
            final awaiting = <Duration>[];
            final delay = <Duration>[];
            scheduler
              ..scheduleAtFixedRate(() => rate.add(async.elapsed), period)
              // Runs that await 30 ms of the fake timers.
              ..scheduleAtFixedRate(() {
                awaiting.add(async.elapsed);
                return Future<void>.delayed(const Duration(milliseconds: 30));
              }, period)
              ..scheduleWithFixedDelay(() => delay.add(async.elapsed), period);
            async.elapse(const Duration(seconds: 3));
            scheduler.shutdown();
            final every = [for (var i = 0; i <= 30; i++) period * i];
            expect(rate, every, reason: 'gaps ${gaps(rate)}');
            expect(awaiting, every, reason: 'gaps ${gaps(awaiting)}');
            expect(delay, every, reason: 'gaps ${gaps(delay)}');
          });
        });
      });
    }

    // The real time a test spends between pumps is no lateness of fake
    // timers: it would catch up runs the fake time never missed.
    test('fake timers: the real time the test takes counts for nothing', () {
      fakeAsync((async) {
        final scheduler = TimerTaskScheduler();
        final rate = <Duration>[];
        scheduler.scheduleAtFixedRate(
          () => rate.add(async.elapsed),
          const Duration(milliseconds: 10),
        );
        async.flushMicrotasks();
        final busy = Stopwatch()..start();
        while (busy.elapsedMilliseconds < 100) {}
        async.elapse(const Duration(milliseconds: 50));
        scheduler.shutdown();
        expect(rate, [
          for (var i = 0; i <= 5; i++) Duration(milliseconds: 10 * i),
        ]);
      });
    });

    // The limit the README ("The wall clock") states: fake timers move the
    // timeline by their waits alone, so a clock moved without firing them
    // delays the run that was due, skips the others and shifts the rest
    // (Spring, catching up: 160, 160, 180, 240, 300, 360). The price of
    // never counting more than the timers waited, which keeps a faster
    // clock from running a task twice.
    test('fake timers: a clock moved without firing them (elapseBlocking) '
        'delays the runs, as documented', () {
      fakeAsync((async) {
        final scheduler = TimerTaskScheduler();
        final runs = <int>[];
        scheduler.scheduleAtFixedRate(
          () => runs.add(async.elapsed.inSeconds),
          const Duration(seconds: 60),
        );
        async
          ..elapse(const Duration(seconds: 30))
          ..elapseBlocking(const Duration(seconds: 130))
          ..elapse(const Duration(seconds: 200));
        scheduler.shutdown();
        expect(runs, [0, 160, 220, 280, 340]);
      });
    });

    // Run with `dart test -p node` too.
    test('real timers, a clock ten times faster, or set forward', () async {
      final stopwatch = Stopwatch()..start();
      final origin = DateTime.now();
      var offset = Duration.zero;
      for (final (name, wall) in [
        ('10x', Clock(() => origin.add(stopwatch.elapsed * 10))),
        ('set forward', Clock(() => DateTime.now().add(offset))),
      ]) {
        await withClock(wall, () async {
          final real = TimerTaskScheduler();
          addTearDown(real.shutdown);
          final began = stopwatch.elapsedMilliseconds;
          final rate = <int>[];
          real.scheduleAtFixedRate(
            () => rate.add(stopwatch.elapsedMilliseconds - began),
            const Duration(milliseconds: 50),
          );
          final jump = Timer(
            const Duration(milliseconds: 120),
            () => offset += const Duration(seconds: 1),
          );
          await Future<void>.delayed(const Duration(milliseconds: 520));
          jump.cancel();
          real.shutdown();
          // Due at 0, 50, ..., 500 ms: one run each, never two in a row.
          expect(rate.length, inInclusiveRange(9, 11), reason: '$name $rate');
          for (final (i, at) in rate.indexed) {
            expect(at, greaterThanOrEqualTo(i * 50 - 2), reason: '$name $rate');
          }
        });
      }
    });
  });

  // fake_async fakes the timers and package:clock's `clock`, which the
  // scheduler reads by default; so does a Flutter widget test
  // (`tester.pump`).
  group('fake_async', () {
    const minute = Duration(minutes: 1);

    List<Duration> every(Duration step, {Duration from = Duration.zero}) => [
      for (var t = from; t <= const Duration(minutes: 10); t += step) t,
    ];

    // The scheduler read DateTime.now(), which stands still under
    // fake_async: a 1-minute fixed rate whose runs await 30 s ran at 0,
    // 1:29, 2:59 and so on.
    test('fixed rate, fixed delay and cron keep their pace, with synchronous '
        'and asynchronous runs', () {
      fakeAsync((async) {
        final scheduler = TimerTaskScheduler();
        final runs = <String, List<Duration>>{};
        void Function() sync(String name) =>
            () => (runs[name] ??= []).add(async.elapsed);
        Future<void> Function() taking(String name, int seconds) => () {
          (runs[name] ??= []).add(async.elapsed);
          return Future<void>.delayed(Duration(seconds: seconds));
        };
        final cron = CronExpression.parse('0 * * * * *');
        scheduler
          ..scheduleAtFixedRate(sync('rate'), minute)
          ..scheduleAtFixedRate(taking('rate 30 s', 30), minute)
          ..scheduleAtFixedRate(taking('rate 90 s', 90), minute)
          ..scheduleWithFixedDelay(sync('delay'), minute)
          ..scheduleWithFixedDelay(taking('delay 30 s', 30), minute)
          ..schedule(sync('cron'), CronTrigger(cron, utc: true))
          ..schedule(taking('cron 30 s', 30), CronTrigger(cron, utc: true));
        async.elapse(const Duration(minutes: 10));
        expect(runs, {
          'rate': every(minute),
          'rate 30 s': every(minute),
          // Longer than the period: the next starts when it completes.
          'rate 90 s': every(const Duration(seconds: 90)),
          'delay': every(minute),
          'delay 30 s': every(const Duration(seconds: 90)),
          'cron': every(minute, from: minute),
          'cron 30 s': every(minute, from: minute),
        });
        scheduler.shutdown();
        async.elapse(const Duration(minutes: 2)); // the runs going on end
        expect(async.pendingTimers, isEmpty);
        expect(runs['rate'], hasLength(11), reason: 'no run after shutdown');
      }, initialTime: start);
    });

    test('long waits', () {
      fakeAsync((async) {
        final scheduler = TimerTaskScheduler();
        final monthly = <DateTime>[];
        var once = 0;
        scheduler
          ..schedule(
            () => monthly.add(start.add(async.elapsed)),
            CronTrigger(CronExpression.parse('0 0 0 1 * *'), utc: true),
          )
          ..scheduleAt(() => once++, start.add(const Duration(days: 40)));
        async.elapse(const Duration(days: 92)); // to April 3rd
        expect(monthly, [
          DateTime.utc(2026, 2),
          DateTime.utc(2026, 3),
          DateTime.utc(2026, 4),
        ]);
        expect(once, 1);
        scheduler.shutdown();
      }, initialTime: start);
    });

    // The wall clock is `now`; the timers, as real ones, run on their own
    // monotonic clock.
    test('a wall clock set back moves no fixed-rate or fixed-delay run; a '
        'cron runs early once, then on time, as in Spring', () {
      fakeAsync((async) {
        var shift = Duration.zero;
        DateTime wall() => start.add(async.elapsed + shift);
        final scheduler = TimerTaskScheduler(now: wall);
        final rate = <Duration>[];
        final delay = <Duration>[];
        final cron = <DateTime>[];
        scheduler
          ..scheduleAtFixedRate(() => rate.add(async.elapsed), minute)
          ..scheduleWithFixedDelay(() => delay.add(async.elapsed), minute)
          ..schedule(
            () => cron.add(wall()),
            CronTrigger(CronExpression.parse('0 * * * * *'), utc: true),
          );
        async.elapse(const Duration(seconds: 20));
        // Back by more than half the wait.
        shift = const Duration(seconds: -40);
        async.elapse(const Duration(minutes: 4, seconds: 20)); // to 4:40
        final times = [for (var m = 0; m <= 4; m++) Duration(minutes: m)];
        expect(rate, times);
        expect(delay, times);
        // The timers waited the minute planned: 12:00:20 by the wall
        // clock. Then on time again (a time kept ahead of the wall clock
        // made every later run 40 s early).
        expect(cron, [
          DateTime.utc(2026, 1, 1, 12, 0, 20),
          DateTime.utc(2026, 1, 1, 12, 2),
          DateTime.utc(2026, 1, 1, 12, 3),
          DateTime.utc(2026, 1, 1, 12, 4),
        ]);
        scheduler.shutdown();
      }, initialTime: start);
    });

    // A fixed rate planned on the wall clock ran twice in a row after it
    // jumped forward by more than the period (a computer waking up), and
    // waited as much longer after it was set back.
    test('a wall clock set forward moves no fixed-rate or fixed-delay run; '
        'a cron runs at its next time', () {
      fakeAsync((async) {
        var shift = Duration.zero;
        DateTime wall() => start.add(async.elapsed + shift);
        final scheduler = TimerTaskScheduler(now: wall);
        final rate = <Duration>[];
        final delay = <Duration>[];
        final cron = <DateTime>[];
        scheduler
          ..scheduleAtFixedRate(() => rate.add(async.elapsed), minute)
          ..scheduleWithFixedDelay(() => delay.add(async.elapsed), minute)
          ..schedule(
            () => cron.add(wall()),
            CronTrigger(CronExpression.parse('0 * * * * *'), utc: true),
          );
        async.elapse(const Duration(seconds: 20));
        shift = const Duration(minutes: 10);
        async.elapse(const Duration(minutes: 2, seconds: 40)); // to 3:00
        final times = [for (var m = 0; m <= 3; m++) Duration(minutes: m)];
        expect(rate, times);
        expect(delay, times);
        // The first run when the timers have waited the minute planned
        // (12:11 by the wall clock), as in Spring; then each minute.
        expect(cron, [
          DateTime.utc(2026, 1, 1, 12, 11),
          DateTime.utc(2026, 1, 1, 12, 12),
          DateTime.utc(2026, 1, 1, 12, 13),
        ]);
        scheduler.shutdown();
      }, initialTime: start);
    });

    test('a wall clock a little behind the timers: a fixed rate follows the '
        'timers, a cron the wall clock, neither drifts', () {
      fakeAsync((async) {
        // The wall clock runs 1 ms a minute slower than the timers (the
        // timers use a monotonic clock that NTP does not adjust).
        DateTime slow() => start.add(async.elapsed - async.elapsed ~/ 60000);
        final scheduler = TimerTaskScheduler(now: slow);
        final rate = <Duration>[];
        final cron = <DateTime>[];
        scheduler
          ..scheduleAtFixedRate(() => rate.add(async.elapsed), minute)
          ..schedule(
            () => cron.add(slow()),
            CronTrigger(CronExpression.parse('0 * * * * *'), utc: true),
          );
        async.elapse(const Duration(days: 1));
        expect(rate, [for (var m = 0; m <= 24 * 60; m++) minute * m]);
        // Each cron run starts when the wall clock says so, give or take
        // a millisecond: no day's worth (1.44 s) of drift.
        expect(cron, hasLength(greaterThan(1400)));
        for (final (i, run) in cron.indexed) {
          final due = start.add(minute * (i + 1));
          expect(
            run.difference(due).abs(),
            lessThanOrEqualTo(const Duration(milliseconds: 2)),
            reason: 'run $i at $run',
          );
        }
        scheduler.shutdown();
      }, initialTime: start);
    });
  });
}
