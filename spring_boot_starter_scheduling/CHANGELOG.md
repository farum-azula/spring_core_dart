## Unreleased

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
