# Method retries and concurrency limits (0.10.1, in core)

No starter of its own (the owner, 27 November 2026): as Spring Framework
7, which archived Spring Retry and moved retries into the framework,
`@Retryable`, `@ConcurrencyLimit` and `RetryTemplate` go into
`spring_core_dart`.

## What Spring 7 does

- `@Retryable` / `@ConcurrencyLimit` on a method or a class (interface
  methods too), enabled by `@EnableResilientMethods`; Boot adds nothing.
- `maxRetries = 3` (retries, so 4 attempts), `delay = 1s`,
  `multiplier = 1`, `jitter = 0`, `maxDelay` unlimited, `timeout = 0`;
  each with a `*String` variant taking `${...}`.
- Matching: an exclude anywhere in the cause chain stops; then includes
  along the chain; then the predicate. Empty includes retry any
  `Throwable`. The caller gets the last original exception; the history
  goes to `RetryListener` and `MethodRetryEvent`.
- Sync methods re-run the rest of the chain, sleeping between attempts;
  `Mono` / `Flux` are called once and resubscribed; a `CompletableFuture`
  is retried only on a synchronous throw.
- Order: `@Async` → `ConcurrencyLimit` → `Retry` → transaction, cache,
  method security → target. Each attempt is a new transaction; an
  `AccessDeniedException` is retried (no test or issue covers it).
- `@ConcurrencyLimit`: per proxy instance, `BLOCK` or `REJECT`; the
  permit is held across the retries.
- `RetryTemplate` / `RetryPolicy` in spring-core: the same, in code.

## The family's design

- **API** as Spring 7: `@Retryable`, `@ConcurrencyLimit`,
  `RetryTemplate`, `RetryPolicy`, `RetryListener`, `MethodRetryEvent`.
  User code takes the annotation; the framework's own retries (the
  Supabase starter's edge functions) take
  `RetryTemplate`, which works without the switch. One `RetryPolicy`
  under both.
- **Switch**: `spring.resilience.enabled`, an `AutoConfigurationBuild`
  left out by default (as `@Observed`); the pointcut known to the build
  (`static const annotationTypes`) so pruning keeps working.
- **Order, explicit constants** (today every advisor but method security
  is `lowestPrecedence`, so their nesting is chance): method security →
  `@Observed` / `@NotifyListeners` → `ConcurrencyLimit` → `Retry` →
  `@Transactional` → `@Cacheable` → target. Security comes first (the
  owner): a denial is checked once and never retried, unlike Spring.
  Observations and notifications count the whole call, not each
  attempt.
- **Never retried**, even with empty includes: Dart `Error`s (bugs:
  `TypeError`, `StateError`, assertions), `AuthenticationException`,
  `AccessDeniedException`, validation errors,
  `UnexpectedRollbackException`, `TransactionSystemException` (the
  commit may have happened).
- **`Future`**: retried on a failed future too (in Dart nearly every
  failure is asynchronous).
- **`Stream`**, `SseEmitter`, `EventStream<T>`: as Spring's `Flux`. On an
  error the method is called again and its events go on into the same
  stream the subscriber holds; `maxRetries` counts over the stream's
  life. A source that starts from the beginning repeats its events (the
  docs say so; `Last-Event-ID` to go on). `EventStream` keeps its type,
  and its own reconnects come first.
- **Sync methods**: a build error with a delay (Dart cannot wait
  synchronously); `@ConcurrencyLimit(BLOCK)` on a sync method likewise.
- **A joined transaction**: an attempt running inside a transaction it
  did not open is not retried (the failure has marked that transaction
  rollback-only, so a retry would end in `UnexpectedRollbackException`);
  the exception goes straight on, and a debug build warns once to put
  `@Retryable` on the method that opens the transaction (or to use
  `requiresNew`).
- **Deadline**: the request deadline (`RequestDeadline`, today in
  `spring_web_dart`) moves into core as a zone deadline the web starters
  set; a retry stops when its next pause would pass it. On the edge this
  keeps retries inside the request's wall time.
- **Each attempt gets a copy of the arguments.**
- **Signals**: build errors for `@Retryable` on `@Effect` / `@Computed`
  and on a signals bean's method without a buffer (`@SignalBuffer`), so a
  failed attempt never publishes partial state or fires effects.
- **Edge**: `@ConcurrencyLimit` counts per isolate (an edge warning, as
  `IsolateLocalState`); retry timers live within the request.
- **Build errors** as for every advice: a non-bean, a private or static
  member.
- **Tests**: one for each risky case — order against transactions,
  security (`@PreAuthorize` and `@PostAuthorize`), cache (`sync`),
  `@Observed`, `@NotifyListeners`, `@Scheduled`, signals, joined
  transactions, streams, the deadline, the arguments, self-calls,
  pruning.
