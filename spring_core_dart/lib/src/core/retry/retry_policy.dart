import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/core/nested_exception.dart';
import 'package:spring_core_dart/src/core/retry/back_off.dart';

/// An exception that a new attempt cannot cure, so it is never retried,
/// whatever a retry policy includes: the caller was refused (not logged
/// in, not allowed), its input is invalid, or the outcome of the work is
/// unknown (a commit that may have happened).
///
/// The family's exceptions of that kind implement it: the security's
/// `AuthenticationException` and `AccessDeniedException`, the
/// validation's `ConstraintViolationException`, `BindException` and
/// `ValidationException`, the data starter's `UnexpectedRollbackException`
/// and `TransactionSystemException`. Implement it in an exception of your
/// own that must not be retried. Dart `Error` subclasses (`TypeError`,
/// `StateError`, a failed assertion) are never retried either: they are
/// bugs.
///
/// ```dart
/// class PaymentDeclined implements NonRetryableException {
///   const PaymentDeclined(this.reason);
///   final String reason;
/// }
/// ```
///
/// Spring (Java) has no such marker: a `@Retryable` method retries what
/// `includes` lists, every exception by default, `AccessDeniedException`
/// too. This is an extension of Spring for Dart.
abstract interface class NonRetryableException {
  /// Whether [error], or an error behind it
  /// ([NestedExceptionUtils.causeChain]), is a Dart `Error` or a
  /// [NonRetryableException]: no policy retries it.
  static bool isNonRetryable(Object error) => NestedExceptionUtils.causeChain(
    error,
  ).any((e) => e is Error || e is NonRetryableException);
}

/// Which failures of an operation are tried again, how long to wait
/// before each new attempt, and for how long in all.
///
/// A `RetryTemplate` runs an operation under one; a `@Retryable` method
/// gets one from its annotation. [RetryPolicy.builder] makes one:
///
/// ```dart
/// final policy = RetryPolicy.builder()
///     .maxRetries(5)
///     .delay(const Duration(milliseconds: 200))
///     .multiplier(2)
///     .maxDelay(const Duration(seconds: 2))
///     .include<TimeoutException>()
///     .build();
/// ```
///
/// A Dart `Error` and a [NonRetryableException] (also as the cause of
/// another) are never retried, whatever the policy says.
///
/// Spring (Java):
/// ```java
/// RetryPolicy policy = RetryPolicy.builder()
///     .maxRetries(5)
///     .delay(Duration.ofMillis(200))
///     .multiplier(2)
///     .maxDelay(Duration.ofSeconds(2))
///     .includes(TimeoutException.class)
///     .build();
/// ```
abstract interface class RetryPolicy {
  /// Three retries (four attempts) one second apart, of any failure but
  /// the ones never retried. Spring (Java): `RetryPolicy.withDefaults()`.
  factory RetryPolicy.withDefaults() => RetryPolicyBuilder().build();

  /// [maxRetries] retries one second apart. Spring (Java):
  /// `RetryPolicy.withMaxRetries(long)`.
  factory RetryPolicy.withMaxRetries(int maxRetries) =>
      RetryPolicyBuilder().maxRetries(maxRetries).build();

  /// A builder; its defaults are those of [RetryPolicy.withDefaults].
  /// Spring (Java): `RetryPolicy.builder()`.
  static RetryPolicyBuilder builder() => RetryPolicyBuilder();

  /// Whether [error] is to be tried again (when the back-off and the
  /// timeout still allow it).
  bool shouldRetry(Object error);

  /// The pauses between attempts and how many there are.
  BackOff get backOff;

  /// The longest time from the first attempt to the start of the last
  /// one: a retry whose pause would end later is not made. Zero: no
  /// limit.
  Duration get timeout;
}

/// Builds a [RetryPolicy]; each method sets one part and returns the
/// builder.
///
/// What is retried: every failure (but a Dart `Error` and a
/// [NonRetryableException]), unless [includes] or [include] name the
/// ones to retry; [excludes] and [exclude] name the ones not to retry,
/// and win. Both are matched along the causes of the failure
/// ([NestedExceptionUtils.causeChain]). Then [predicate] decides.
///
/// How: [maxRetries] new attempts (3), [delay] before the first (1 s),
/// each pause [multiplier] times the one before (1), at most [maxDelay],
/// with a random [jitter] added; or a [backOff] of your own. [timeout]
/// limits them all.
///
/// Spring (Java): `RetryPolicy.Builder`.
final class RetryPolicyBuilder {
  /// A builder with the defaults.
  RetryPolicyBuilder();

  BackOff? _backOff;
  int _maxRetries = 3;
  Duration _delay = const Duration(seconds: 1);
  Duration _jitter = Duration.zero;
  double _multiplier = 1;
  Duration? _maxDelay;
  Duration _timeout = Duration.zero;
  Introspector _introspector = Introspector.shared;
  final List<Type> _includedTypes = [];
  final List<Type> _excludedTypes = [];
  final List<bool Function(Object error)> _includeTests = [];
  final List<bool Function(Object error)> _excludeTests = [];
  bool Function(Object error)? _predicate;

  /// The pauses, instead of [delay], [multiplier], [maxDelay], [jitter]
  /// and [maxRetries].
  RetryPolicyBuilder backOff(BackOff backOff) {
    _backOff = backOff;
    return this;
  }

  /// How many new attempts at most; 3 by default, so 4 attempts in all.
  RetryPolicyBuilder maxRetries(int maxRetries) {
    _require(maxRetries >= 0, 'maxRetries', maxRetries, 'must not be negative');
    _maxRetries = maxRetries;
    return this;
  }

  /// The pause before the first new attempt; 1 second by default.
  RetryPolicyBuilder delay(Duration delay) {
    _require(!delay.isNegative, 'delay', delay, 'must not be negative');
    _delay = delay;
    return this;
  }

  /// The most added at random to the pause of the first attempt (and in
  /// proportion to the later ones); none by default.
  RetryPolicyBuilder jitter(Duration jitter) {
    _require(!jitter.isNegative, 'jitter', jitter, 'must not be negative');
    _jitter = jitter;
    return this;
  }

  /// What each pause is multiplied by for the next; 1 by default.
  RetryPolicyBuilder multiplier(double multiplier) {
    _require(multiplier >= 1, 'multiplier', multiplier, 'must be 1 or more');
    _multiplier = multiplier;
    return this;
  }

  /// The longest pause; no limit by default.
  RetryPolicyBuilder maxDelay(Duration maxDelay) {
    _require(
      !maxDelay.isNegative,
      'maxDelay',
      maxDelay,
      'must not be negative',
    );
    _maxDelay = maxDelay;
    return this;
  }

  /// The longest time from the first attempt to the start of the last
  /// one; zero (the default) for no limit.
  RetryPolicyBuilder timeout(Duration timeout) {
    _require(!timeout.isNegative, 'timeout', timeout, 'must not be negative');
    _timeout = timeout;
    return this;
  }

  /// Retries only the failures of [types] (or of a subtype), here or
  /// behind the failure. A `Type` is matched with [typeTests]: the
  /// generated modules register the types written in annotations, and a
  /// type without a test matches its exact runtime type only; in code,
  /// [include] matches any subtype.
  RetryPolicyBuilder includes(List<Type> types) {
    _includedTypes.addAll(types);
    return this;
  }

  /// Does not retry the failures of [types] (or of a subtype), here or
  /// behind the failure; they win over [includes].
  RetryPolicyBuilder excludes(List<Type> types) {
    _excludedTypes.addAll(types);
    return this;
  }

  /// Retries the failures of type [E] (or of a subtype), here or behind
  /// the failure; with [includes], only those listed by either.
  RetryPolicyBuilder include<E extends Object>() {
    _includeTests.add((error) => error is E);
    return this;
  }

  /// Does not retry the failures of type [E] (or of a subtype), here or
  /// behind the failure.
  RetryPolicyBuilder exclude<E extends Object>() {
    _excludeTests.add((error) => error is E);
    return this;
  }

  /// A last word on a failure the includes and excludes let through:
  /// `false` is not retried.
  RetryPolicyBuilder predicate(bool Function(Object error) predicate) {
    _predicate = predicate;
    return this;
  }

  /// Where the `Type` values of [includes] and [excludes] are tested; the
  /// context's introspector knows the types its modules wrote.
  /// `Introspector.shared` by default.
  RetryPolicyBuilder typeTests(Introspector introspector) {
    _introspector = introspector;
    return this;
  }

  /// The policy.
  RetryPolicy build() {
    final introspector = _introspector;
    bool Function(Object) typeTest(Type type) =>
        (error) => introspector.isInstanceOf(type, error);
    return _DefaultRetryPolicy(
      backOff:
          _backOff ??
          ExponentialBackOff(
            initialInterval: _delay,
            multiplier: _multiplier,
            maxInterval: _maxDelay,
            jitter: _jitter,
            maxAttempts: _maxRetries,
          ),
      timeout: _timeout,
      includes: [..._includedTypes.map(typeTest), ..._includeTests],
      excludes: [..._excludedTypes.map(typeTest), ..._excludeTests],
      predicate: _predicate,
      description: [
        if (_includedTypes.isNotEmpty) 'includes $_includedTypes',
        if (_excludedTypes.isNotEmpty) 'excludes $_excludedTypes',
      ].join(', '),
    );
  }

  static void _require(bool ok, String name, Object value, String message) {
    if (!ok) {
      throw ArgumentError.value(value, name, message);
    }
  }
}

final class _DefaultRetryPolicy implements RetryPolicy {
  _DefaultRetryPolicy({
    required this.backOff,
    required this.timeout,
    required this.includes,
    required this.excludes,
    required this.predicate,
    required this.description,
  });

  @override
  final BackOff backOff;

  @override
  final Duration timeout;

  final List<bool Function(Object)> includes;
  final List<bool Function(Object)> excludes;
  final bool Function(Object)? predicate;
  final String description;

  @override
  bool shouldRetry(Object error) {
    if (NonRetryableException.isNonRetryable(error)) {
      return false;
    }
    final chain = NestedExceptionUtils.causeChain(error).toList();
    if (excludes.isNotEmpty && chain.any((e) => excludes.any((t) => t(e)))) {
      return false;
    }
    if (includes.isNotEmpty && !chain.any((e) => includes.any((t) => t(e)))) {
      return false;
    }
    return predicate?.call(error) ?? true;
  }

  @override
  String toString() =>
      'RetryPolicy($backOff'
      '${timeout == Duration.zero ? '' : ', timeout ${timeout.inMilliseconds}'}'
      '${timeout == Duration.zero ? '' : ' ms'}'
      '${description.isEmpty ? '' : ', $description'})';
}
