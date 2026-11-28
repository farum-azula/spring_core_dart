/// Method retries and concurrency limits: `@Retryable` calls a method
/// again when it fails, `@ConcurrencyLimit` lets only so many calls of it
/// run at once. Both are advice the bean's proxy runs, put into effect by
/// `spring.resilience.enabled: true` (Spring Boot's auto-configuration
/// writes the advisors; without the switch the build writes no proxy for
/// them). The retries in code, without an annotation, are `RetryTemplate`
/// and `RetryPolicy` of `core.dart`.
///
/// ```dart
/// @Service()
/// class Payments {
///   @ConcurrencyLimit(4)
///   @Retryable(includes: [TimeoutException], maxRetries: 2)
///   Future<Receipt> charge(Order order) => gateway.charge(order);
/// }
/// ```
///
/// Spring (Java): `org.springframework.resilience`, with
/// `@EnableResilientMethods`.
library;

export 'package:spring_core_dart/src/resilience/concurrency_limit.dart';
export 'package:spring_core_dart/src/resilience/retry_interceptor.dart';
export 'package:spring_core_dart/src/resilience/retry_streams.dart'
    hide RetriedStreamAttempts, StreamRetryRun;
export 'package:spring_core_dart/src/resilience/retryable.dart';
