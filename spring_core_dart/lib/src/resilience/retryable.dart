import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/context/event/application_event.dart';

/// Calls a method again when it fails, or every method of a class: a
/// failed call is tried again up to [maxRetries] times, after [delay]
/// (growing by [multiplier] up to [maxDelay], with a random [jitter]),
/// and the caller gets the result of the first attempt that succeeds, or
/// the last failure itself when the retries give up.
///
/// ```dart
/// @Service()
/// class Payments {
///   @Retryable(
///     includes: [TimeoutException, SocketException],
///     maxRetries: 4,
///     delay: Duration(milliseconds: 200),
///     multiplier: 2,
///     maxDelay: Duration(seconds: 2),
///   )
///   Future<Receipt> charge(Order order) => gateway.charge(order);
/// }
/// ```
///
/// How it runs: the bean's proxy calls the rest of the advice and the
/// method again for each attempt, so each attempt of a `@Transactional`
/// method is a new transaction, and each gets a copy of the arguments (a
/// parameter declared as a `List`, a `Set` or a `Map` gets a copy of the
/// caller's, so a failed attempt that changed it does not change what the
/// next one gets). A `Future` is
/// retried when it fails and when the method throws; a `Stream` (an
/// `EventStream` too) when it emits an error: the method is called again
/// and its events go on in the stream the caller listens to, the
/// [maxRetries] counted over the stream's life (a source that starts from
/// the beginning repeats its events). A synchronous method is retried at
/// once: Dart cannot wait without returning, so a [delay], a [jitter] or
/// a [timeout] on one fails the build (write `delay: Duration.zero`).
///
/// What is retried: every failure, or only those of [includes] (or of a
/// subtype), not those of [excludes], both matched along the causes of
/// the failure (`NestedException`); then [predicate] decides. Never
/// retried, whatever is listed: a Dart `Error` (a bug), a
/// `NonRetryableException` (security's `AuthenticationException` and
/// `AccessDeniedException`, validation errors, an
/// `UnexpectedRollbackException`, a `TransactionSystemException`), and a
/// call that runs inside a transaction it did not open (its failure has
/// marked that transaction rollback-only; put `@Retryable` on the method
/// that opens the transaction, or use `Propagation.requiresNew`).
///
/// A retry whose pause would end after the `RequestDeadline` of the call
/// is not made. A call the bean makes on itself skips the proxy, so it is
/// not retried (as in Spring). Every failure is published as a
/// [MethodRetryEvent], and the `RetryListener` beans are told.
///
/// It needs `spring.resilience.enabled: true` in `application.yml`:
/// without it the build writes no proxy for it, and nothing is retried.
///
/// Spring (Java): `org.springframework.resilience.annotation.Retryable`
/// with `@EnableResilientMethods`. Its `value` is [includes] here; its
/// `timeUnit` is in the `Duration` values. Unlike Spring, method security runs
/// before the retries (a denial is never retried), Dart `Error` subclasses are
/// not retried, nor is a joined transaction.
class Retryable {
  /// Retries the method, or every method of the class.
  const Retryable({
    this.includes = const [],
    this.excludes = const [],
    this.predicate,
    this.maxRetries = 3,
    this.maxRetriesString,
    this.delay = const Duration(seconds: 1),
    this.delayString,
    this.jitter = Duration.zero,
    this.jitterString,
    this.multiplier = 1,
    this.multiplierString,
    this.maxDelay,
    this.maxDelayString,
    this.timeout = Duration.zero,
    this.timeoutString,
  });

  /// The failures retried (and their subtypes), here or behind the
  /// failure; empty: every failure but those never retried.
  final List<Type> includes;

  /// The failures not retried (and their subtypes), here or behind the
  /// failure; they win over [includes].
  final List<Type> excludes;

  /// A last word on a failure [includes] and [excludes] let through.
  final MethodRetryPredicate? predicate;

  /// How many new attempts at most: 3, so 4 attempts in all.
  final int maxRetries;

  /// [maxRetries] as text, with `${...}` placeholders; wins when set.
  final String? maxRetriesString;

  /// The pause before the first new attempt: 1 second.
  final Duration delay;

  /// [delay] as text (`500ms`, `2s`, `PT1S`, a number of milliseconds),
  /// with `${...}` placeholders; wins when set.
  final String? delayString;

  /// The most added at random to the first pause (and in proportion to
  /// the later ones): none.
  final Duration jitter;

  /// [jitter] as text, with `${...}` placeholders; wins when set.
  final String? jitterString;

  /// What each pause is multiplied by for the next one: 1, the same pause.
  final double multiplier;

  /// [multiplier] as text, with `${...}` placeholders; wins when set.
  final String? multiplierString;

  /// The longest pause; `null`: no limit.
  final Duration? maxDelay;

  /// [maxDelay] as text, with `${...}` placeholders; wins when set.
  final String? maxDelayString;

  /// The longest time from the first attempt to the start of the last
  /// one; zero: no limit.
  final Duration timeout;

  /// [timeout] as text, with `${...}` placeholders; wins when set.
  final String? timeoutString;
}

/// Decides whether a failure of a `@Retryable` method is retried, after
/// its `includes` and `excludes`: a class with a const constructor, given
/// to `predicate`.
///
/// ```dart
/// final class OnlyServerErrors implements MethodRetryPredicate {
///   const OnlyServerErrors();
///
///   @override
///   bool shouldRetry(MethodSignature method, Object error) =>
///       error is HttpServerErrorException;
/// }
///
/// @Retryable(predicate: OnlyServerErrors())
/// Future<Book> find(String isbn) => client.find(isbn);
/// ```
///
/// Spring (Java): `org.springframework.resilience.retry.MethodRetryPredicate`.
abstract interface class MethodRetryPredicate {
  /// Whether [error], thrown by [method], is retried.
  bool shouldRetry(MethodSignature method, Object error);
}

/// Published for each failure of a `@Retryable` method: before it is
/// retried ([retryAborted] `false`), or when it is the last one
/// ([retryAborted] `true`, the caller gets [failure]).
///
/// ```dart
/// @EventListener()
/// void onRetry(MethodRetryEvent event) => log.info(
///   '${event.method.name}: ${event.failure}'
///   '${event.retryAborted ? ' (gave up)' : ''}',
/// );
/// ```
///
/// Spring (Java): `org.springframework.resilience.retry.MethodRetryEvent`.
final class MethodRetryEvent extends ApplicationEvent {
  /// The failure [failure] of [method] of the bean [source].
  MethodRetryEvent(
    super.source,
    this.method,
    this.failure, {
    required this.retryAborted,
  });

  /// The method that failed.
  final MethodSignature method;

  /// What it threw.
  final Object failure;

  /// Whether this failure ends the retries: no new attempt follows, and
  /// the caller gets it.
  final bool retryAborted;

  @override
  String get eventName => 'MethodRetryEvent';

  @override
  String toString() =>
      'MethodRetryEvent[${method.targetType}.${method.name}: $failure'
      '${retryAborted ? ', aborted' : ''}]';
}
