# spring_boot_starter_scheduling

Done: `@Scheduled` (cron, fixed rate and delay, placeholders), the task
scheduler and `spring.task.scheduling.enabled`. Differences from Spring to
fix: [fix_plan.md](fix_plan.md) (the scheduling items).

## `TaskExecutor`: a pool of worker isolates

Spring's `@Async` exists because a Java call blocks its thread. In Dart
I/O does not block — `async` / `await` and `Future` are in the language —
so that use needs nothing. What `async` / `await` does not give is
parallel computation: everything runs on one isolate (in Flutter, the UI
one), and a heavy computation in an `async` method still freezes it. That
needs isolates, and this is what the executor is for.

```dart
@Service()
class Thumbnails {
  Thumbnails(this.executor);
  final TaskExecutor executor;

  Future<Uint8List> make(Uint8List jpeg) =>
      executor.run(() => resize(jpeg, 256));   // runs on a worker isolate
}
```

Compared with a bare `Isolate.run`:

- isolates are kept in a pool and reused (starting one costs milliseconds);
- the pool size and limits come from `spring.task.execution.*`, like
  Spring Boot's `ThreadPoolTaskExecutor`;
- tests swap in an executor that runs in the same isolate, so they stay
  simple and deterministic;
- errors and timings are logged in one place;
- on the web, which has no isolates, the work runs in the same thread
  instead of failing.

Limits of isolates, which the docs must say plainly: no shared memory (a
bean with its HTTP client, sockets or database connection cannot be sent
to another isolate — only computations over data), and arguments and
results are copied. For native-speed work there is
[flutter_spring_rust](flutter_spring_rust.md).

## `@Async` on the pool

Kept for Spring's familiar annotation: an `@Async` method runs on the
`TaskExecutor` pool through the generated proxy; `@Async('images')` picks a
named executor bean.

```dart
@Service()
class Reports {
  @Async()
  Future<Report> build(List<Order> orders) async => ...;   // on a worker isolate
}
```

**Needs more thought before it is built.** The annotation hides that the
method leaves the isolate, and most methods cannot: one that reads the
bean's fields or calls its dependencies would fail, or copy them, at run
time. Open questions:

- what the generator can check at build time (only parameters and locals
  used? no instance members?), so a wrong `@Async` is a build error, not a
  runtime surprise;
- what is sent: the bean is not, so is the method a static-like function of
  its arguments, or does a copy of the bean go along?
- `void` methods (fire and forget): where errors go (Spring's
  `AsyncUncaughtExceptionHandler`);
- whether a plain `executor.run(...)` is simply clearer in most code — in
  which case `@Async` stays a convenience for the few methods that fit.
