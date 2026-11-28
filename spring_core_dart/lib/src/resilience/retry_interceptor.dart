import 'dart:async';

import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/event/application_listener.dart';
import 'package:spring_core_dart/src/core/convert/duration_style.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/retry/retry_execution.dart';
import 'package:spring_core_dart/src/core/retry/retry_listener.dart';
import 'package:spring_core_dart/src/core/retry/retry_policy.dart';
import 'package:spring_core_dart/src/resilience/retry_streams.dart';
import 'package:spring_core_dart/src/resilience/retryable.dart';

const _log = SpringLog('spring.resilience');

const bool _debugBuild =
    !bool.fromEnvironment('dart.vm.product') &&
    !bool.fromEnvironment('dart.vm.profile');

/// A rule that keeps a failed call of a `@Retryable` method from being
/// retried where a new attempt would do harm: asked once, at the first
/// failure, in the caller's zone.
///
/// The data starter adds one: a call that runs inside a transaction it
/// did not open is not retried, since its failure has marked that
/// transaction rollback-only (the retry would end in an
/// `UnexpectedRollbackException`, or write twice). A debug build logs the
/// reason once per method.
///
/// ```dart
/// final class OutsideBatches implements MethodRetryVeto {
///   const OutsideBatches();
///
///   @override
///   String? vetoRetry(MethodInvocation invocation) => Batch.current == null
///       ? null
///       : 'it runs inside a batch; retry the batch instead';
/// }
/// ```
///
/// Spring (Java) has no such rule: a retry inside a joined transaction
/// fails with `UnexpectedRollbackException` at the commit.
abstract interface class MethodRetryVeto {
  /// Why the failed call [invocation] must not be retried, for the
  /// developer; `null` when it may be.
  String? vetoRetry(MethodInvocation invocation);
}

/// The pointcut of the members marked `@Retryable`: a member marked, or a
/// method of a class marked (not its getters and setters), for
/// [RetryInterceptor] in an advisor bean.
///
/// It declares [annotationTypes], so the build gives a proxy class only to
/// the beans that carry `@Retryable`; without the advisor in the build (its
/// module left out), none gets one.
final class RetryablePointcut implements AnnotationPointcut {
  /// The pointcut; it has no settings.
  const RetryablePointcut();

  /// The annotation this pointcut matches; the generator reads it.
  static const List<Type> annotationTypes = [Retryable];

  @override
  bool matches(MethodSignature signature, String beanName) =>
      RetryInterceptor.retryableOf(signature) != null;

  @override
  String toString() => 'RetryablePointcut';
}

/// The advice of `@Retryable`: runs the rest of the call again (the
/// advice inside it and the method) when it fails, as the annotation
/// says; see `Retryable` for what is retried and how.
///
/// [environment] fills the `${...}` placeholders of the `*String`
/// attributes; [introspector] tests the types of `includes` and
/// `excludes` (the context's knows those its modules wrote);
/// [eventPublisher] gets a `MethodRetryEvent` for each failure;
/// [retryListener] is told of the attempts; [streamAdapters] make the
/// retried stream of a stream type of their own; [vetoes] may forbid a
/// retry.
///
/// ```dart
/// DefaultPointcutAdvisor(
///   const RetryablePointcut(),
///   RetryInterceptor(environment: environment),
///   order: AdvisorOrder.retry,
/// );
/// ```
///
/// Spring (Java): `RetryAnnotationInterceptor`, set up by
/// `RetryAnnotationBeanPostProcessor`
/// (`org.springframework.resilience.annotation`).
final class RetryInterceptor implements MethodInterceptor {
  /// The interceptor; see the class.
  RetryInterceptor({
    this.environment,
    Introspector? introspector,
    this.eventPublisher,
    RetryListener? retryListener,
    List<RetryStreamAdapter> streamAdapters = const [],
    List<MethodRetryVeto> vetoes = const [],
  }) : introspector = introspector ?? Introspector.shared,
       retryListener = retryListener ?? CompositeRetryListener(const []),
       streamAdapters = List.unmodifiable([
         ...streamAdapters,
         const PlainStreamRetryAdapter(),
       ]),
       vetoes = List.unmodifiable(vetoes);

  /// Fills the placeholders of the `*String` attributes; without it they
  /// are read as they are.
  final PropertyResolver? environment;

  /// Tests the types of `includes` and `excludes`.
  final Introspector introspector;

  /// Gets a `MethodRetryEvent` for each failure; none when `null`.
  final ApplicationEventPublisher? eventPublisher;

  /// Told of the attempts.
  final RetryListener retryListener;

  /// Make the retried streams, the first that supports a stream; a plain
  /// stream's last.
  final List<RetryStreamAdapter> streamAdapters;

  /// Rules that may forbid a retry.
  final List<MethodRetryVeto> vetoes;

  final _plans = Map<MethodSignature, _RetryPlan?>.identity();
  final _warned = Set<MethodSignature>.identity();

  /// The `@Retryable` of [signature]: the member's own, else its class's
  /// for a method; `null` when there is none.
  static Retryable? retryableOf(MethodSignature signature) =>
      signature.mergedAnnotations.whereType<Retryable>().firstOrNull ??
      (signature.kind == MemberKind.method
          ? (signature.implementingTypeAnnotations ??
                        signature.targetAnnotations)
                    .whereType<Retryable>()
                    .firstOrNull ??
                signature.targetAnnotations.whereType<Retryable>().firstOrNull
          : null);

  /// The policy of [signature]'s `@Retryable`, its placeholders filled;
  /// `null` when it has none. Computed once per member; a placeholder that
  /// cannot be filled or a value that cannot be read throws.
  RetryPolicy? policyOf(MethodSignature signature) =>
      _planOf(signature)?.policy;

  _RetryPlan? _planOf(MethodSignature signature) =>
      _plans.putIfAbsent(signature, () => _plan(signature));

  _RetryPlan? _plan(MethodSignature signature) {
    final retryable = retryableOf(signature);
    if (retryable == null) {
      return null;
    }
    final member = '${signature.targetType}.${signature.name}';
    String? text(String? value) => switch (value) {
      null => null,
      final value => environment?.resolveRequiredPlaceholders(value) ?? value,
    };
    Duration duration(String? value, Duration fallback) => switch (text(
      value,
    )) {
      null => fallback,
      final value => DurationStyle.parse(value),
    };
    final maxDelay = switch (text(retryable.maxDelayString)) {
      null => retryable.maxDelay,
      final value => DurationStyle.parse(value),
    };
    final predicate = retryable.predicate;
    final builder = RetryPolicy.builder()
        .typeTests(introspector)
        .maxRetries(
          switch (text(retryable.maxRetriesString)) {
            null => retryable.maxRetries,
            final value => int.parse(value.trim()),
          },
        )
        .delay(duration(retryable.delayString, retryable.delay))
        .jitter(duration(retryable.jitterString, retryable.jitter))
        .multiplier(
          switch (text(retryable.multiplierString)) {
            null => retryable.multiplier,
            final value => double.parse(value.trim()),
          },
        )
        .timeout(duration(retryable.timeoutString, retryable.timeout))
        .includes(retryable.includes)
        .excludes(retryable.excludes);
    if (maxDelay != null) {
      builder.maxDelay(maxDelay);
    }
    if (predicate != null) {
      builder.predicate((error) => predicate.shouldRetry(signature, error));
    }
    final returnType = signature.returnType.split('<').first;
    return _RetryPlan(
      builder.build(),
      member,
      async: returnType == 'Future' || returnType == 'FutureOr',
    );
  }

  @override
  Object? invoke(MethodInvocation invocation) {
    final plan = _planOf(invocation.signature);
    if (plan == null) {
      return invocation.proceed();
    }
    return _Attempts(this, plan, invocation).run();
  }

  // The reason a veto gives, logged once per member in a debug build.
  String? _vetoOf(MethodInvocation invocation, _RetryPlan plan) {
    for (final veto in vetoes) {
      if (veto.vetoRetry(invocation) case final reason?) {
        if (_debugBuild && _warned.add(invocation.signature)) {
          _log.warning('@Retryable ${plan.member} was not retried: $reason.');
        }
        return reason;
      }
    }
    return null;
  }

  RetryStreamAdapter _adapterOf(Stream<Object?> stream) =>
      streamAdapters.firstWhere((adapter) => adapter.supports(stream));
}

final class _RetryPlan {
  _RetryPlan(this.policy, this.member, {required this.async});

  final RetryPolicy policy;
  final String member;
  final bool async;
}

// The attempts of one call: each one gets a copy of the caller's
// arguments, the policy decides after each failure.
final class _Attempts {
  _Attempts(this.interceptor, this.plan, this.invocation)
    : _arguments = invocation.args;

  final RetryInterceptor interceptor;
  final _RetryPlan plan;
  final MethodInvocation invocation;
  final List<Object?> _arguments;

  late final RetryExecution _execution = _newExecution();

  RetryExecution _newExecution() =>
      RetryExecution(plan.policy, interceptor.retryListener, plan.member);

  Object? _attempt() => invocation.proceed(_copies());

  List<Object?> _copies() {
    final signature = invocation.signature;
    final types = signature.parameterTypes;
    final mapTypes = signature.parameterMapTypes;
    return [
      for (final (index, argument) in _arguments.indexed)
        switch ((types.elementAtOrNull(index), argument)) {
          ('List', final List<Object?> list) => list.toList(),
          ('Set', final Set<Object?> set) => set.toSet(),
          ('Map', final Map<Object?, Object?> map) =>
            mapTypes.elementAtOrNull(index)?.copyWhere(map, (_) => true) ?? map,
          _ => argument,
        },
    ];
  }

  Object? run() {
    final Object? result;
    try {
      result = _attempt();
    } on Object catch (error, stackTrace) {
      if (plan.async) {
        return _awaiting(Future<Object?>.error(error, stackTrace));
      }
      return _synchronously(error, stackTrace);
    }
    return _after(result);
  }

  Object? _after(Object? result) {
    if (result is Future<Object?>) {
      return _awaiting(result);
    }
    if (result is Stream<Object?>) {
      return _stream(result);
    }
    _execution.succeeded(result);
    return result;
  }

  // A synchronous method: no pause (Dart cannot wait without returning).
  Object? _synchronously(Object error, StackTrace stackTrace) {
    var failure = error;
    var trace = stackTrace;
    while (true) {
      if (_failed(_execution, failure, trace) == null) {
        Error.throwWithStackTrace(failure, trace);
      }
      _execution.retrying();
      try {
        return _after(_attempt());
      } on Object catch (error, stackTrace) {
        failure = error;
        trace = stackTrace;
      }
    }
  }

  Future<Object?> _awaiting(Future<Object?> first) async {
    var current = first;
    while (true) {
      try {
        final value = await current;
        _execution.succeeded(value);
        return value;
      } on Object catch (error, stackTrace) {
        final pause = _failed(_execution, error, stackTrace);
        if (pause == null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (pause > Duration.zero) {
          await Future<void>.delayed(pause);
        }
        _execution.retrying();
        try {
          final next = _attempt();
          current = next is Future<Object?> ? next : Future.value(next);
        } on Object catch (error, stackTrace) {
          current = Future<Object?>.error(error, stackTrace);
        }
      }
    }
  }

  // A stream keeps its type only when the build wrote the element type
  // (`returnTypeArguments`); without it, its errors are not retried.
  Stream<Object?> _stream(Stream<Object?> first) {
    final element = invocation.signature.returnTypeArguments.firstOrNull;
    if (element == null) {
      _execution.succeeded(first);
      return first;
    }
    return element.run(<T>() => _typedStream<T>(first as Stream<T>));
  }

  Stream<T> _typedStream<T>(Stream<T> first) => interceptor
      ._adapterOf(first)
      .adapt<T>(
        RetriedStreamAttempts<T>(
          first,
          next: () => _attempt()! as Stream<T>,
          start: () => _StreamRun(this, _newExecution()),
        ),
      );

  // Records [error] in [execution] and publishes it; the pause before the
  // next attempt, or null when there is none (the listeners told).
  Duration? _failed(
    RetryExecution execution,
    Object error,
    StackTrace stackTrace,
  ) {
    final vetoed =
        execution.errors.isEmpty &&
        interceptor.vetoes.isNotEmpty &&
        plan.policy.shouldRetry(error) &&
        interceptor._vetoOf(invocation, plan) != null;
    final pause = execution.failed(error, stackTrace, vetoed: vetoed);
    interceptor.eventPublisher?.publishEvent(
      MethodRetryEvent(
        invocation.target,
        invocation.signature,
        error,
        retryAborted: pause == null,
      ),
    );
    if (pause == null) {
      execution.end();
    }
    return pause;
  }
}

final class _StreamRun implements StreamRetryRun {
  _StreamRun(this.attempts, this.execution);

  final _Attempts attempts;
  final RetryExecution execution;

  @override
  Duration? failed(Object error, StackTrace stackTrace) =>
      attempts._failed(execution, error, stackTrace);

  @override
  void retrying() => execution.retrying();

  @override
  void done() => execution.succeeded(null);
}
