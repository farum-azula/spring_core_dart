## Unreleased

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
