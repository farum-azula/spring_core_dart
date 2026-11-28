import 'dart:async';
import 'dart:collection';

import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';

/// What a call of a `@ConcurrencyLimit` method does when the limit is
/// reached.
///
/// Spring (Java): `ConcurrencyLimit.ThrottlePolicy`.
enum ThrottlePolicy {
  /// Waits for a permit, in turn, without blocking: the method must
  /// return a `Future` (a synchronous one fails the build).
  block,

  /// Fails at once with an [InvocationRejectedException].
  reject,
}

/// Lets at most [limit] calls of a method run at the same time, on each
/// bean; on a class, of all its methods together. A call over the limit
/// waits for one to end ([ThrottlePolicy.block], the default) or fails
/// with an [InvocationRejectedException] ([ThrottlePolicy.reject]).
///
/// ```dart
/// @Service()
/// class Reports {
///   // At most two reports are made at a time; the others wait.
///   @ConcurrencyLimit(2)
///   Future<Report> make(Query query) => engine.run(query);
/// }
/// ```
///
/// A call of a method returning a `Future` holds its permit until the
/// future completes; any other call until it returns (a `Stream` method
/// gives the permit back when it returns its stream). Around a
/// `@Retryable` method the permit is held across the retries. The limit
/// counts in the memory of one isolate: with a pool of isolates, or a
/// function on the edge (whose start lists it among its warnings), each
/// has its own.
///
/// It needs `spring.resilience.enabled: true` in `application.yml`.
///
/// Spring (Java):
/// `org.springframework.resilience.annotation.ConcurrencyLimit`, with
/// `@EnableResilientMethods`.
class ConcurrencyLimit {
  /// At most [limit] concurrent calls.
  const ConcurrencyLimit(
    this.limit, {
    this.limitString,
    this.policy = ThrottlePolicy.block,
  });

  /// How many calls may run at the same time; at least 1.
  final int limit;

  /// [limit] as text, with `${...}` placeholders; wins when set.
  final String? limitString;

  /// What a call over the limit does.
  final ThrottlePolicy policy;
}

/// Thrown by a call of a `@ConcurrencyLimit` method over its limit, with
/// [ThrottlePolicy.reject] (or a synchronous method, which cannot wait).
///
/// Spring (Java): `org.springframework.resilience.InvocationRejectedException`.
class InvocationRejectedException implements Exception {
  /// The rejection, described by [message], of a call of [target].
  InvocationRejectedException(this.message, this.target);

  /// What was rejected.
  final String message;

  /// The bean whose method was called.
  final Object target;

  @override
  String toString() => 'InvocationRejectedException: $message';
}

/// The pointcut of the members marked `@ConcurrencyLimit`: a member
/// marked, or a method of a class marked, for
/// [ConcurrencyLimitInterceptor] in an advisor bean. It declares
/// [annotationTypes], so the build gives a proxy class only to the beans
/// that carry the annotation.
final class ConcurrencyLimitPointcut implements AnnotationPointcut {
  /// The pointcut; it has no settings.
  const ConcurrencyLimitPointcut();

  /// The annotation this pointcut matches; the generator reads it.
  static const List<Type> annotationTypes = [ConcurrencyLimit];

  @override
  bool matches(MethodSignature signature, String beanName) =>
      ConcurrencyLimitInterceptor.limitOf(signature) != null;

  @override
  String toString() => 'ConcurrencyLimitPointcut';
}

/// The advice of `@ConcurrencyLimit`: counts the running calls of each
/// bean (each proxy) and lets a call over the limit wait or fails it.
/// [environment] fills the placeholders of `limitString`.
///
/// Spring (Java):
/// `ConcurrencyLimitBeanPostProcessor` with a
/// `ConcurrencyThrottleInterceptor` per bean
/// (`org.springframework.resilience.annotation`).
final class ConcurrencyLimitInterceptor implements MethodInterceptor {
  /// The interceptor.
  ConcurrencyLimitInterceptor({this.environment});

  /// Fills the placeholders of `limitString`.
  final PropertyResolver? environment;

  final _plans = Map<MethodSignature, _LimitPlan?>.identity();
  final _throttles = Expando<Map<Object, _Throttle>>('ConcurrencyLimit');
  static final Object _classKey = Object();

  /// The `@ConcurrencyLimit` of [signature] and whether it is its class's
  /// (one limit for all the methods); `null` when it has none.
  static ({ConcurrencyLimit limit, bool ofClass})? limitOf(
    MethodSignature signature,
  ) {
    if (signature.mergedAnnotations.whereType<ConcurrencyLimit>().firstOrNull
        case final limit?) {
      return (limit: limit, ofClass: false);
    }
    if (signature.kind != MemberKind.method) {
      return null;
    }
    final limit =
        (signature.implementingTypeAnnotations ?? signature.targetAnnotations)
            .whereType<ConcurrencyLimit>()
            .firstOrNull ??
        signature.targetAnnotations.whereType<ConcurrencyLimit>().firstOrNull;
    return limit == null ? null : (limit: limit, ofClass: true);
  }

  _LimitPlan? _planOf(MethodSignature signature) =>
      _plans.putIfAbsent(signature, () {
        final found = limitOf(signature);
        if (found == null) {
          return null;
        }
        final text = found.limit.limitString;
        final limit = text == null
            ? found.limit.limit
            : int.parse(
                (environment?.resolveRequiredPlaceholders(text) ?? text).trim(),
              );
        if (limit < 1) {
          throw ArgumentError.value(
            limit,
            'limit',
            '@ConcurrencyLimit of ${signature.targetType}.${signature.name} '
                'must be at least 1',
          );
        }
        final returnType = signature.returnType.split('<').first;
        return _LimitPlan(
          limit,
          found.limit.policy,
          found.ofClass ? _classKey : signature,
          '${signature.targetType}.${signature.name}',
          async: returnType == 'Future' || returnType == 'FutureOr',
        );
      });

  /// How many calls of [signature] run now on [proxy] (with a class's
  /// limit, of all its methods); for tests and diagnostics.
  int running(Object proxy, MethodSignature signature) {
    final plan = _planOf(signature);
    return plan == null ? 0 : _throttles[proxy]?[plan.key]?.active ?? 0;
  }

  @override
  Object? invoke(MethodInvocation invocation) {
    final plan = _planOf(invocation.signature);
    if (plan == null) {
      return invocation.proceed();
    }
    final throttles = _throttles[invocation.proxy] ??= {};
    final throttle = throttles[plan.key] ??= _Throttle(plan.limit);
    if (throttle.tryAcquire()) {
      return _holding(throttle, invocation);
    }
    if (plan.policy == ThrottlePolicy.reject || !plan.async) {
      throw InvocationRejectedException(
        'Concurrency limit of ${plan.limit} reached for ${plan.member}',
        invocation.target,
      );
    }
    return throttle.acquire().then((_) => _holding(throttle, invocation));
  }

  static Object? _holding(_Throttle throttle, MethodInvocation invocation) {
    final Object? result;
    try {
      result = invocation.proceed();
    } on Object {
      throttle.release();
      rethrow;
    }
    if (result is Future<Object?>) {
      return result.whenComplete(throttle.release);
    }
    throttle.release();
    return result;
  }
}

final class _LimitPlan {
  _LimitPlan(
    this.limit,
    this.policy,
    this.key,
    this.member, {
    required this.async,
  });

  final int limit;
  final ThrottlePolicy policy;
  final Object key;
  final String member;
  final bool async;
}

// The permits of one limit: a waiting call gets the permit of the call
// that ends, in the order they came.
final class _Throttle {
  _Throttle(this.limit);

  final int limit;
  int active = 0;
  final Queue<Completer<void>> _waiting = Queue();

  bool tryAcquire() {
    if (active < limit) {
      active++;
      return true;
    }
    return false;
  }

  Future<void> acquire() {
    final waiting = Completer<void>();
    _waiting.add(waiting);
    return waiting.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      active--;
    }
  }
}
