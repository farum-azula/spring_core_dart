# spring_boot_starter_scheduling

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Scheduled tasks for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications: annotate a bean method with `@Scheduled` and the
application runs it by itself, every few minutes, with a pause after each
run, or at cron times such as "9:00 on working days".

Some work nobody calls: refreshing a cache, syncing with a server,
sending a daily digest, deleting old files. Without this starter you
would start `Timer`s yourself, keep them, handle their errors and cancel
them on shutdown. With it you annotate the method; the tasks start once
the application is ready and stop when it closes. The `TaskScheduler`
bean also lets code schedule work decided at runtime, such as a reminder
at a time the user picked.

It is the Dart counterpart of Spring's `@Scheduled` and `TaskScheduler`,
for servers and Flutter apps alike.

*In the guides:* [server, 8. Cache and scheduling](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#8-cache-and-scheduling), [app, 8. Cache & scheduling](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#8-cache--scheduling).

## Installation

```yaml
dependencies:
  spring_boot_starter_scheduling: ^0.5.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.5.0   # required: makes @Scheduled methods callable
```

```bash
dart run build_runner build
```

That is all: the starter is found automatically, there is no
`@EnableScheduling`. The generator is required because Dart has no
reflection: it writes the code that finds and calls the `@Scheduled`
methods. The starter is the only dependency an application needs: it
brings `spring_boot_dart` and `spring_boot_starter_logging` and re-exports
them, as every Spring Boot starter does.

## Quick example

```dart
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';

@Component()
class Reports {
  Reports(this.repository);
  final ReportRepository repository;

  // Keeps the report cache fresh: a run starts every 5 minutes.
  @Scheduled(fixedRate: Duration(minutes: 5))
  void refreshCache() => repository.refresh();

  // Talks to a slow server: the 30 s pause starts when a sync is done.
  @Scheduled(fixedDelay: Duration(seconds: 30))
  Future<void> syncWithServer() async => await repository.sync();

  @Scheduled(cron: '0 0 9 * * MON-FRI') // 9:00 on working days
  void morningDigest() => repository.sendDigest();
}
```

Start the application as usual (`runApplication(args)`); the tasks start
once the context is ready, and closing the context cancels them.

The same in Spring (Java):

```java
@Component
class Reports {
  @Scheduled(fixedRate = 5, timeUnit = TimeUnit.MINUTES)
  void refreshCache() { repository.refresh(); }

  @Scheduled(fixedDelay = 30, timeUnit = TimeUnit.SECONDS)
  void syncWithServer() { repository.sync(); }

  @Scheduled(cron = "0 0 9 * * MON-FRI")
  void morningDigest() { repository.sendDigest(); }
}
```

## `@Scheduled`

Give exactly one of `cron`, `fixedRate` or `fixedDelay` (or their
`*String` forms). `initialDelay` alone, without any of them, runs the
method once.

| Attribute | Meaning | Example |
|---|---|---|
| `fixedRate` | start a run every period, measured between starts; runs missed during a long run or a pause of the process start back to back ([below](#fixed-rate-after-a-pause-of-the-process)) | `fixedRate: Duration(minutes: 5)` |
| `fixedDelay` | wait this long after each run completes; the one for polls and UI ticks | `fixedDelay: Duration(seconds: 30)` |
| `initialDelay` | wait before the first run (not with `cron`); alone, one run after it (Spring 6.1) | `initialDelay: Duration(seconds: 10)` |
| `cron` | run at cron times (see below); `-` switches the task off | `cron: '0 */15 * * * *'` |
| `zone` | the time zone of `cron`: leave it out for local time, or `'UTC'` (also `'Z'`, `'GMT'`) | `zone: 'UTC'` |
| `scheduler` | the `TaskScheduler` bean to run on, by qualifier or bean name (`${...}` allowed), when there are several; default: the only one, the primary one or `taskScheduler` (Spring 6.1) | `scheduler: 'reportsScheduler'` |
| `fixedRateString`, `fixedDelayString`, `initialDelayString` | the same as text, with `${...}` placeholders and Spring Boot durations; a blank value, also once resolved, counts as not set | `fixedRateString: r'${reports.rate:5m}'` |

Rules:

- The method must be public and take no parameters. It may return a
  `Future`: the run counts as finished when the future completes.
- Several `@Scheduled` on one method give several schedules.
- Only singleton beans are scheduled; `@Scheduled` on a bean of another
  scope, such as `@Scope('prototype')`, is ignored with a warning.
- A wrong attribute stops the start with a message naming
  `Class.method`: two kinds at once, none, a bad or blank cron, an unknown
  zone or `scheduler`, a missing property, a negative duration, a zero
  `fixedRate` or `fixedDelay`.
- The method is called on the bean as other beans see it, so AOP advice
  (`@Around`, `@Cacheable`, ...) applies.

## Cron expressions

A cron expression describes calendar times. It has six fields, as in
Spring, starting with the seconds (Unix cron has five):

```text
second minute hour day-of-month month day-of-week
```

| Expression | Runs |
|---|---|
| `0 * * * * *` | every minute, at second 0 |
| `*/10 * * * * *` | every 10 seconds |
| `0 */15 * * * *` | every 15 minutes |
| `0 0 * * * *` | every hour |
| `0 0 9-17 * * MON-FRI` | every hour from 9 to 17 on working days |
| `0 30 8 * * *` | 8:30 every day |
| `0 0 0 1 * *` | midnight on the 1st of each month |
| `0 0 18 L * *` | 18:00 on the last day of the month |
| `0 0 12 LW * *` | noon on the last working day of the month |
| `0 0 10 15W * *` | 10:00 on the working day nearest to the 15th |
| `0 0 20 ? * FRIL` | 20:00 on the last Friday of the month |
| `0 0 9 ? * MON#1` | 9:00 on the first Monday of the month |
| `0 0 9 ? * MON#1,MON#3` | 9:00 on the first and the third Monday |
| `0 0 0 1,L * *` | midnight on the first and the last day of the month |
| `0 0 10 * * SAT-SUN` | 10:00 at the weekend |
| `0 0 0 25 DEC *` | midnight on December 25th |
| `@hourly`, `@daily` (`@midnight`), `@weekly`, `@monthly`, `@yearly` (`@annually`) | the usual macros |

- Every field takes `*`, a value (`5`), a list (`1,15,30`), a range
  (`9-17`) and a step (`*/5`, `0-30/10`, `5/15` = from 5, every 15).
  Months are `JAN`-`DEC`; names are case-insensitive. `?` means "any" in
  the day fields.
- Days of the week are numbered as in Spring: `MON`-`SUN` are 1-7, and 0
  is Sunday too. Sunday at the start of a range counts as 0, so `SAT-SUN`,
  `MON-SUN` and `SUN-TUE` all work. `*/2` is MON, WED, FRI, SUN.
- The specials `L`, `L-n`, `nW`, `LW`, `nL` and `n#k` may be combined in
  lists with each other and with values (`1,L`, `MON-FRI,SATL`).
- As in Spring, a day must match both day fields (Unix cron matches
  either), and ranges cannot wrap around: `FRI-MON` is an error, write
  `FRI-SUN,MON`.
- Local time follows the wall clock, as in Spring. A time inside the hour
  skipped when clocks go forward does not exist and is skipped (a daily
  `0 30 2 * * *` does not run that day); a time inside the hour repeated
  when clocks go back runs twice, before and after the change.

To check an expression in code, for example one a user typed:

```dart
final cron = CronExpression.parse('0 0 9 * * MON-FRI');
final next = cron.next(DateTime.now()); // when it runs next
CronExpression.isValid('0 0 25 * * *'); // false: there is no hour 25
```

`CronExpression.parse` throws a `FormatException` naming the wrong
field.

## Configuration from properties

The text attributes resolve `${...}` placeholders, so schedules can live
in `application.properties` and change per profile:

```dart
// Every 5 minutes unless reports.rate says otherwise.
@Scheduled(fixedRateString: r'${reports.rate:5m}')
void refresh() { ... }

// Off unless a profile sets reports.cleanup-cron.
@Scheduled(cron: r'${reports.cleanup-cron:-}')
void cleanup() { ... }
```

```properties
# lib/resources/application.properties
reports.rate=10m
reports.cleanup-cron=0 0 3 * * *
```

Durations: `500` (milliseconds), `10s`, `5m`, `2h`, `1d`, `PT1H30M`.

| Property | Default | Meaning |
|---|---|---|
| `spring.task.scheduling.enabled` | `true` | `false` switches scheduling off: no `TaskScheduler` bean, no tasks (the `TaskExecutor` stays) |
| `spring.task.scheduling.shutdown.await-termination` | `false` | `true`: the context's `closeAsync()` waits for the runs going on when it closes. A run, or its `Future`, is never interrupted |
| `spring.task.scheduling.shutdown.await-termination-period` | — | the longest wait (`30s`); then a warning naming the running tasks is logged and the shutdown goes on. Without it the wait has no limit |

The synchronous `close()` cannot wait: a run going on finishes after the
close (no further runs start), and `TimerTaskScheduler.runningTasks`
lists it. A `TaskScheduler` bean of your own can wait the same way through
a `destroy()` that returns a `Future` (`DisposableBean`).

`spring.task.scheduling.pool.size` and
`spring.task.scheduling.thread-name-prefix` are not read: everything runs
on Dart's event loop, without a thread pool.

## Scheduling in code: `TaskScheduler`

`@Scheduled` covers work that is known when the code is written. When the
schedule is decided at runtime, such as a reminder at a time the user
picked, or a poll that runs while a screen is open, inject the
`TaskScheduler` bean:

```dart
@Service()
class Reminders {
  Reminders(this.scheduler);
  final TaskScheduler scheduler;

  // At the time the user picked in the app.
  ScheduledTask remindAt(DateTime at, String text) =>
      scheduler.scheduleAt(() => notify(text), at);

  // While the inbox screen is open; the caller cancels the task.
  ScheduledTask poll() => scheduler.scheduleWithFixedDelay(
    checkInbox,
    const Duration(seconds: 30),
  );
}

final task = reminders.poll();
final due = task.nextExecution; // when the next run is due
task.cancel();                  // the screen closed
```

| Method | Runs the task |
|---|---|
| `scheduleAt(task, time)` | once at `time`, or right away when it has passed |
| `scheduleAtFixedRate(task, period, initialDelay:)` | every `period`, measured between starts; after a pause of the process, every missed run at once ([below](#fixed-rate-after-a-pause-of-the-process)) |
| `scheduleWithFixedDelay(task, delay, initialDelay:)` | again and again, `delay` after each run has finished |
| `schedule(task, trigger)` | at the times a `Trigger` gives: `PeriodicTrigger`, `CronTrigger`, `OneShotTrigger` or your own |

Each returns a `ScheduledTask` with its `name`, `nextExecution`, the
number of runs so far, and `cancel()`. A cancelled task finishes a run
that is going on; no further run starts.

The starter's scheduler is a `TimerTaskScheduler`; declare your own
`TaskScheduler` bean to replace it. With several `TaskScheduler` beans,
`@Scheduled` methods run on the primary one or the one named
`taskScheduler`, unless they name another with `scheduler:`. When neither
exists, the start fails; Spring would fall back to a local
single-threaded scheduler.

In Spring, `schedule(task, Instant)` is `scheduleAt(task, DateTime)` here
(Dart has no overloads), and a `ScheduledTask` replaces
`ScheduledFuture`.

## Long runs and overlapping

Everything runs on Dart's event loop, so a task never runs twice at the
same time:

- `fixedDelay`: the pause starts when the run, its `Future` included,
  completes.
- `fixedRate`: each run is due a period after the one before was due.
  When a run takes longer than the period (or starts late: an isolate
  busy with other work), the runs that came due meanwhile start one
  after the other right after it, until the rate is caught up, as with
  Spring's scheduler (a 300 ms rate whose first run takes a second
  starts at 0, then 1000, 1000 and 1000 ms, then 1200, 1500, ...).
- `cron`: the next time is computed after the run, so times missed
  during a long run are skipped.

### Fixed rate after a pause of the process

A fixed-rate task catches up after any pause, not only a long run. When
a process that was stopped (`SIGSTOP`), an app the system suspended in
the background (iOS, Android), or a browser tab whose timers were
throttled while hidden runs again, every run that came due meanwhile
starts at once, one after the other: a 100 ms rate after 5 seconds
stopped runs about 50 times in the same millisecond. Spring's
`ThreadPoolTaskScheduler` does the same (it is `ScheduledThreadPoolExecutor`
underneath), and so does this scheduler, on purpose. The pause counts as
far as the system's monotonic clock counts it: time a device slept
usually does not. A `fixedDelay` task runs once after the pause and
keeps its delay; cron runs once too (missed times are skipped).

That suits work that must happen once per period. For a poll or a UI
tick, where only the latest run matters, use `fixedDelay` /
`scheduleWithFixedDelay`:

```dart
// A countdown on screen: back from the background it ticks once.
final tick = scheduler.scheduleWithFixedDelay(
  refreshCountdown,
  const Duration(seconds: 1),
);
```

In a Flutter app the starter stops `@Scheduled` tasks while the app is in
the background and schedules them afresh when it comes back, so they do
not catch up (unless `spring.flutter.lifecycle.pause-in-background=false`).
Tasks started with a `TaskScheduler` keep their schedule in the
background: cancel them when their screen goes away, or give them a fixed
delay.

## `TaskExecutor` and `@Async` listeners

The starter also registers Spring Boot's `applicationTaskExecutor` bean
(alias `taskExecutor`), a `SimpleAsyncTaskExecutor` of the core: it runs
each task in a later event-loop turn and logs its errors. Declaring your
own `TaskExecutor` bean replaces it.

Having an executor switches `@Async` on for `@EventListener` methods, as
Spring's `@EnableAsync` does: such a listener runs on the executor
instead of inside the call that published the event, so the publisher
does not wait for it.

```dart
@Component()
class Mailer {
  // The order is confirmed without the publisher waiting for the mail.
  @EventListener()
  @Async() // or @Async('mailExecutor') for another TaskExecutor bean
  Future<void> onPlaced(OrderPlaced order) => sendConfirmation(order);
}
```

## Errors

An exception of a run, thrown or from the returned `Future`, is logged at
error level to the `spring.scheduling` logger with the task's name, and
the task keeps its schedule. Handle errors in the method if you need
retries or alerts, or declare an `ErrorHandler` bean, which then receives
every error instead of the log:

```dart
// Every failed run is reported, and the task keeps running.
@Component()
class ReportErrors implements ErrorHandler {
  @override
  void handleError(Object error, StackTrace stackTrace) =>
      crashReporter.record(error, stackTrace);
}
```

The scheduler uses the only `ErrorHandler` bean, or the primary one; with
several and none primary, it uses none. A handler that throws stops the
task: the error is logged and the task does not run again, as with
Spring's `LOG_AND_PROPAGATE`. Spring sets such a handler on its
`ThreadPoolTaskScheduler`.

## Testing

Scheduled methods run in `springBootTest` too. To keep tests
deterministic, switch scheduling off and call the methods directly:

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.task.scheduling.enabled': false},
);

test('refresh', () => app.getBean<Reports>().refreshCache());
```

Or let the test move time. Flutter widget tests (`tester.pump`) and
`fake_async` fake the timers and the current time of `package:clock`,
which the scheduler reads by default: a 5-minute schedule runs without
waiting 5 minutes, exactly as real time would run it: a cron runs at
each of its times, and each pumped minute runs a 1-minute `fixedRate`
task once, also when its runs await something for 30 seconds or when the
test fixes the date with `withClock(Clock.fixed(...))` (cron times follow
the clock, which a fixed one holds). With timers of its
own, a test passes the current time and the timers of its fake clock:
`TimerTaskScheduler(now: ..., createTimer: ...)`, registered through
`BeanOverride`. `ScheduledAnnotationBeanPostProcessor.scheduledTasks`
lists what is scheduled.

## The wall clock

`fixedRate` and `fixedDelay` never read the wall clock: as Spring's
executor counts on a monotonic clock, each task keeps a timeline of its
own that its timers move. A timer armed for a wait moves it by that wait
when it fires, or by the real time it took (a monotonic `Stopwatch`) when
that is longer: a real timer that fires late, behind an isolate busy
with other work, counts late. Under a clock of its own (`withClock` of
`package:clock`, as `fake_async` and widget tests set, or the `now` given
to `TimerTaskScheduler`), the real time counted is at most what that
clock moved, so fake timers move the timeline by exactly their wait,
however long the test takes in real time. A `fixedRate` run is due a
period after the one before was due, and the runs that came due during a
long run start one after the other when it ends; a `fixedDelay` waits
its delay from the end of each run. So setting the wall clock (by hand,
or a time server) moves none of their runs, and neither does a clock of
its own that stands still (`Clock.fixed`), runs slow or fast, or jumps
while real timers wait.

Counting no more than that clock moved keeps a clock faster than the
timers from running a task twice, and tests from depending on the
machine's speed. It has two limits, both under a clock of its own:

- On real timers, a timer counts late only as far as that clock moved.
  Under `Clock.fixed` (or a slower clock) the runs an isolate missed
  while blocked are skipped, not caught up, and each run comes as late
  after the one before as its timer fired (a fraction of a millisecond).
- On fake timers (`fake_async`, widget tests), the timeline moves by the
  timers' waits alone, never by how far the clock went past them. A clock
  moved without firing the timers, such as `fake_async`'s
  `elapseBlocking` standing for a blocked isolate, makes the run that was
  due come when the timers next fire, skips the others missed meanwhile,
  and shifts every later run by the delay. With a 60-second rate,
  `elapseBlocking(Duration(seconds: 130))` 30 seconds in gives runs at
  0, 160, 220, 280 s...; Spring would run at 160, 160, 180, 240 s....
  Timers fired by `elapse` or `tester.pump` keep the exact pace.

A cron or `scheduleAt` time is a wall clock time: the scheduler computes
the wait from the wall clock, and the timers wait it. When the wall
clock is set back during the wait, the run comes early by the wall
clock, once; the next time is planned from the wall clock again.

## Hot reload

Tasks belong to the context: a hot-reload restart closes it, which
cancels every task, and the new context schedules the methods of the new
code.

## Differences from Spring

- No `@EnableScheduling`: the dependency switches scheduling on;
  `spring.task.scheduling.enabled=false` switches it off.
- Time zones: local time or UTC only (Dart has no time zone database).
- Durations are `Duration`s instead of numbers plus `timeUnit`.
- `TaskScheduler.schedule(task, Instant)` is `scheduleAt(task, DateTime)`
  (Dart has no overloads).
- A `PeriodicTrigger` given to `schedule(task, trigger)` runs as
  `scheduleAtFixedRate` or `scheduleWithFixedDelay` do, on the task's
  timeline; Spring plans it with the wall clock.
- A cron or `scheduleAt` wait longer than a day ends within a day of the
  wall clock passing its time (set forward, or a computer that slept),
  as the wait is made of timers of at most a day (JavaScript's timers
  cannot wait 25 days); Spring waits the whole delay computed at the start.
- A method returning a `Future` is awaited before its run counts as
  finished, with `fixedRate` and `cron` too, so a slow run delays the next
  one instead of overlapping it. Spring does not wait for a returned
  `CompletableFuture`, and waits for a reactive result only with
  `fixedDelay`.
- `#k` in the day of week takes 1-5; Spring accepts larger ordinals that
  never match.
- Several `TaskScheduler` beans without a primary one or one named
  `taskScheduler` fail the start; Spring falls back to a local scheduler.
- `spring.task.scheduling.shutdown.await-termination[-period]` works with
  the context's `closeAsync()` only (`close()` cannot wait). A run that is
  going on is never interrupted and, without `await-termination`, finishes
  after the close (no further runs start).
- `@Async` works on `@EventListener` methods only and needs no
  `@EnableAsync` (the `TaskExecutor` bean switches it on). There is no
  thread pool configuration (`spring.task.scheduling.pool.*`,
  `spring.task.execution.*`): Dart has no threads.
- Not yet: `SchedulingConfigurer` / `ScheduledTaskRegistrar`, scheduling
  of prototype beans.
