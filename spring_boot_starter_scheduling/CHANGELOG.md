## 0.5.0

### Breaking

- Cron and daylight saving time, as in Spring: a time inside the hour skipped when clocks go forward does not exist and is skipped (a daily `0 30 2 * * *` does not run that day; it was moved to 03:30), and a time inside the hour repeated when clocks go back runs twice.
- A fixed-rate task catches up, as Spring's `ThreadPoolTaskScheduler`: the runs that came due during a long run, or while the process was paused, start one after the other until the rate is caught up (it ran once right after). `PeriodicTrigger(fixedRate: true).nextExecution` can then be before the completion. Use `fixedDelay` for polls and UI ticks.
- `fixedRate` and `fixedDelay` run on a timeline their timers move, as Spring's executor counts on a monotonic clock, never on the wall clock: setting the clock moves none of their runs.

### Changes

- In browsers and on JavaScript, a wait longer than 24.8 days no longer fires at once and repeats: no single timer waits more than a day, and a cron or `scheduleAt` wait checks the wall clock at each step.
- `TimerTaskScheduler` reads the current time from `package:clock` by default, so `fake_async` and Flutter widget tests (`tester.pump`) run schedules as real time would: a cron at each of its times, one fixed-rate run per period, also under `withClock(Clock.fixed(...))`.
- Fixed rate no longer runs twice after the wall clock jumps forward, and no longer slows down or drifts under a clock of its own that stands still or runs fast.

## 0.4.3

- Flutter security (#15)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- feat: spring_security_core, spring_boot_starter_security and a CI quality gate

## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds
- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- **Brings logging, like every Spring Boot starter:** depends on and re-exports `spring_boot_starter_logging` (and through it `spring_boot_dart` and `spring_core_dart`), so the starter is the only dependency an application lists, and one import gives everything. An application using it now gets the logging system (Boot's console format, `logging.*` properties) without adding the logging starter; `logging.enabled=false` turns it off.
- The example is a Spring Boot application (`@Scheduled` bean, a one-off task from the `TaskScheduler` bean), written by the generator.
- `spring_auto_configuration.dart` re-exports the logging starter's (and through it `spring_boot_dart`'s) auto-configuration, so a test naming `springBootAutoConfiguration` (`ApplicationContextRunner`) needs no other dependency.

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- ci: run only the tests of the packages a change affects

## 0.2.1

- feat: spring_boot_starter_flutter, @Log, --dart-define properties, Flutter counter example

## 0.2.0

- the auto-configured `applicationTaskExecutor` and `taskScheduler` back off for beans registered by an `@Import`ed `BeanRegistrar` / `ImportBeanDefinitionRegistrar` of the application; their conditions are decided when the auto-configuration is read, like Boot's `OnBeanCondition`
- `fixedRateString`, `fixedDelayString` and `initialDelayString` that are or resolve to blank (`r'${jobs.rate:}'`) count as not set, like Spring (they failed as not a duration).
- Two `ErrorHandler` beans no longer fail the start: the scheduler takes the unique or primary one, else none (`getIfUnique`).
- `ErrorHandler` for the errors of scheduled tasks (`TimerTaskScheduler(errorHandler:)`; the auto-configured scheduler uses the `ErrorHandler` bean); a handler that throws stops the task, like Spring's `LOG_AND_PROPAGATE`.
- `@Scheduled(initialDelay: ...)` (or `initialDelayString`) alone runs the method once after the delay, like Spring 6.1.
- `TaskScheduler.scheduleAt(task, DateTime)` runs a task once at that time, like Spring's `schedule(Runnable, Instant)`.
- cron on the web: fields with values of 32 and above (`0 45 * * * *`, `50 * * * * *`) fire under dart2js (the field sets were 64-bit int bit masks, shifted modulo 32 there)
- an `applicationTaskExecutor` bean (alias `taskExecutor`, a `SimpleAsyncTaskExecutor`) unless the application has a `TaskExecutor`, like Spring Boot's `TaskExecutionAutoConfiguration`; it switches `@Async` event listeners on

## 0.1.7

- `spring.task.scheduling.shutdown.await-termination` / `await-termination-period`: the context's `closeAsync()` waits for the runs going on (`TimerTaskScheduler(awaitTermination:, awaitTerminationPeriod:)`, `runningTasks`; `destroy()` returns the `Future`)
- cron day of week like Spring's: MON-SUN are 1-7 and Sunday at the start of a range is 0, so `SAT-SUN`, `MON-SUN`, `FRI-SUN` parse
- breaking: `*` and `?` in the cron day of week are 1-7, so `*/2` is MON, WED, FRI, SUN (was SUN, TUE, THU, SAT); `L-0` is rejected
- cron lists of Quartz specials and values: `MON#1,MON#3`, `1,L`, `MON-FRI,SATL`
- `@Scheduled(scheduler:)` picks a `TaskScheduler` bean by qualifier or name; with several schedulers the default is the primary one or `taskScheduler`

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- add feign runner + web socket runner
- add web core + faign starter for http calling

## 0.1.4

- feat: ObjectMapper in core — JSON on generated metadata (@Introspected, @JsonProperty/@JsonIgnore/@JsonInclude/@JsonCreator/@JsonValue), spring.jackson.* in Boot

## 0.1.3

- Initial version: @Scheduled methods (fixed rate, fixed delay, cron), TaskScheduler.
