import 'package:spring_core_dart/src/core/order.dart';

/// Where each advisor of the framework sits around a bean's method, the
/// one place that says it: a lower order runs outside a higher one.
///
/// From the outside in:
///
/// 1. [methodSecurity]: `@PreAuthorize`, `@PostAuthorize`, `@Secured`.
///    A call is checked once; a denied call runs nothing else, and is
///    never retried.
/// 2. [observation], [notifyListeners], [beanReads]: `@Observed` and the
///    Flutter starter's `@NotifyListeners` and bean reads. They see the
///    whole call: one observation, one notification, however many
///    attempts a retry makes.
/// 3. [concurrencyLimit]: `@ConcurrencyLimit`. The permit is held across
///    the retries.
/// 4. [retry]: `@Retryable`. Each attempt runs what is inside it again.
/// 5. [transaction]: `@Transactional`. Each attempt is a new transaction.
/// 6. [cache]: `@Cacheable`, `@CachePut`, `@CacheEvict`, inside the
///    retries: a failed attempt caches nothing.
/// 7. [methodValidation]: `@Validated`. The arguments are checked right
///    before the method.
///
/// An application's own aspect or advisor without an order
/// ([Ordered.lowestPrecedence]) runs inside all of these, next to the
/// method; give it a lower order to put it outside one. Every value
/// leaves room between its neighbours.
///
/// ```dart
/// // Timed around each attempt of a retried call, inside the transaction.
/// @Bean()
/// PointcutAdvisor timing() => DefaultPointcutAdvisor(
///   const AnnotationMatchingPointcut<Timed>(),
///   TimingInterceptor(),
///   order: AdvisorOrder.transaction + 10,
/// );
/// ```
///
/// Spring (Java) gives most of its advisors `Ordered.LOWEST_PRECEDENCE`,
/// so their nesting follows the order the advisors are registered in,
/// with `AuthorizationInterceptorsOrder` for method security and
/// `@EnableResilientMethods(order)` for the retries. Unlike Spring,
/// method security comes before the retries: a denial is checked once.
abstract final class AdvisorOrder {
  /// Method security: before every other advice, so nothing runs for a
  /// call that is denied and a cached result never reaches someone who may
  /// not call the method. Spring (Java):
  /// `AuthorizationInterceptorsOrder.FIRST` + 100.
  static const int methodSecurity = Ordered.highestPrecedence + 100;

  /// `@Observed`: one observation for the whole call.
  static const int observation = Ordered.lowestPrecedence - 1000;

  /// The Flutter starter's `@NotifyListeners`: one notification for the
  /// whole call.
  static const int notifyListeners = Ordered.lowestPrecedence - 950;

  /// The Flutter starter's bean reads: the reads of the whole call.
  static const int beanReads = Ordered.lowestPrecedence - 900;

  /// `@ConcurrencyLimit`: outside the retries, so the permit is held
  /// across them.
  static const int concurrencyLimit = Ordered.lowestPrecedence - 800;

  /// `@Retryable`: each attempt runs the advice inside it again.
  static const int retry = Ordered.lowestPrecedence - 700;

  /// `@Transactional`: a new transaction for each attempt.
  static const int transaction = Ordered.lowestPrecedence - 600;

  /// `@Cacheable`, `@CachePut`, `@CacheEvict`.
  static const int cache = Ordered.lowestPrecedence - 500;

  /// `@Validated`: the arguments right before the method.
  static const int methodValidation = Ordered.lowestPrecedence - 400;
}
