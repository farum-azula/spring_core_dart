import 'dart:async';

import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/annotations.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_errors.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';

const _log = SpringLog('spring.flutter.signals');

/// The advice on a `@Computed` member of a bean that has other advice: a
/// read that advice answered without computing (a cache hit) goes on
/// following what the value last read, so its reader hears of a change.
final class ComputedFollowInterceptor implements MethodInterceptor {
  /// The advice.
  const ComputedFollowInterceptor();

  @override
  Object? invoke(MethodInvocation invocation) {
    final target = invocation.target;
    if (target is! SignalBeanHolder) {
      return invocation.proceed();
    }
    final name = invocation.signature.name;
    final state = target.signalBean;
    final member = state.members[name] ?? target.signalMembers[name]?.call();
    if (member is! ComputedMember) {
      return invocation.proceed();
    }
    if (member is AsyncMember) {
      member.advisedCall = invocation.proceed;
    }
    final before = member.computations;
    final Object? result;
    try {
      result = DerivedFutures.recording(invocation.proceed);
    } on Object {
      // Refused before it read anything: its reader still hears of a
      // change of what the value is made of.
      member.followLast();
      rethrow;
    }
    if (member.computations == before) {
      member.followLast();
    }
    if (member is AsyncMember && result is Future<Object?>) {
      DerivedFutures.track(result);
      member.bind(DerivedFutures.of(result)!.origin);
    }
    return result;
  }
}

final class _ComputedPointcut implements AnnotationPointcut {
  const _ComputedPointcut();

  @override
  bool matches(MethodSignature signature, String beanName) =>
      signature.mergedAnnotations.any((annotation) => annotation is Computed);
}

/// Starts the `@Effect` and watch methods of a bean once it is made (and
/// advised), and ends its followed state when it is destroyed.
///
/// An effect runs at once, and again each time something it read changes.
/// Every later run, and every watch callback, runs as the user the bean
/// was made for (`CallerContexts`), never as the user whose change ran it.
/// A first run that throws stops the bean from being made and ends its
/// state (its effects and watches stop with it); a later one
/// goes to the `TypedErrorHandler<SignalExecutionException>` bean, else
/// to `FlutterError.reportError`, and the effect lives on. The state ends
/// before the bean's own `@PreDestroy` methods run; from then on its
/// members read and write the bean's own fields.
final class SignalEffects extends DestructionAwareBeanPostProcessor
    implements BeanFactoryAware, Ordered {
  /// The processor over the state kept in the bean [beans] gives, with the
  /// runtime [runtime] gives: both looked up on first use, as a
  /// post-processor that takes beans when it is made makes them before the
  /// other post-processors, which then skip them (Spring's "not eligible
  /// for getting processed by all BeanPostProcessors").
  SignalEffects(SignalBeans Function() beans, SignalRuntime Function() runtime)
    : _beans = beans,
      _runtime = runtime;

  /// The processor over [beans] and [runtime], made already.
  SignalEffects.of(SignalBeans beans, SignalRuntime runtime)
    : _beans = (() => beans),
      _runtime = (() => runtime);

  final SignalBeans Function() _beans;
  final SignalRuntime Function() _runtime;

  /// The beans with followed state.
  late final SignalBeans beans = _beans();

  /// What the context gives them.
  late final SignalRuntime runtime = _runtime();

  BeanFactory? _beanFactory;

  static final _followAdvisor = DefaultPointcutAdvisor(
    const _ComputedPointcut(),
    const ComputedFollowInterceptor(),
  );

  // After the auto proxy creator: an effect runs on the advised bean.
  @override
  int get order => Ordered.lowestPrecedence;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    final definition = _definitionOf(beanName);
    final target = AopUtils.getTarget(bean);
    if (target is! SignalBeanHolder) {
      _refuseUngenerated(definition, beanName);
      return bean;
    }
    final state = target.signalBean;
    final owner = state.label;
    if (!identical(bean, target)) {
      if (!runtime.allowAdvice) {
        throw StateError(
          "Advice matches the bean '$beanName' ($owner), which has @Signal, "
          '@Computed or @Effect members. Move the advised method into a '
          'bean of its own that calls this one, or allow it with '
          'spring.flutter.signals.allow-advice: true.',
        );
      }
      if (bean case final AdvisedWrapper wrapper) {
        wrapper.aopInvoker.prependAdvisor(_followAdvisor);
      }
    }
    target.signalQueues.forEach(runtime.queues.of);
    beans.adopt(bean, state, runtime);
    state
      ..beanName = beanName
      ..scope = definition?.scope;
    final makers = target.signalMembers;
    for (final name in runtime.eager ? makers.keys : target.eagerSignals) {
      makers[name]?.call();
    }
    if (definition == null) {
      return bean;
    }
    try {
      for (final method in definition.annotatedMethods) {
        for (final annotation in method.annotations) {
          switch (annotation) {
            case Effect():
              _startEffect(bean, state, method);
            case OnWatched(:final signals, :final each, :final delay):
              _watch(bean, state, makers, method, signals, each, delay, true);
            case OnUnwatched(:final signals, :final each, :final delay):
              _watch(bean, state, makers, method, signals, each, delay, false);
          }
        }
      }
    } on Object {
      // The bean is not made, so nothing destroys it: what was started
      // stops now, or it would go on running on the half-made bean.
      beans.close(bean);
      rethrow;
    }
    return bean;
  }

  BeanDefinition<Object>? _definitionOf(String beanName) {
    final factory = _beanFactory;
    return factory is BeanDefinitionRegistry &&
            (factory as BeanDefinitionRegistry).containsBeanDefinition(beanName)
        ? (factory as BeanDefinitionRegistry).getBeanDefinition(beanName)
        : null;
  }

  // An effect on a bean the generator did not make its subclass for would
  // never run: the application was built by an older generator, or the
  // bean is made by a @Bean method.
  void _refuseUngenerated(
    BeanDefinition<Object>? definition,
    String beanName,
  ) {
    if (definition == null ||
        !definition.annotatedMethods.any(
          (method) => method.annotations.any((a) => a is Effect),
        )) {
      return;
    }
    throw StateError(
      "The bean '$beanName' has @Effect methods, but it is not on signals: "
      'the application must be built by the generator of this version, and '
      'the bean made by the container, not by a @Bean method that calls its '
      'constructor.',
    );
  }

  void _watch(
    Object bean,
    SignalBean state,
    Map<String, SignalMember Function()> makers,
    IntrospectedMethod<Object> method,
    List<String> names,
    bool each,
    Duration delay,
    bool onWatched,
  ) {
    final name = method.name;
    // Run as the user the bean was made for, never as the one whose read
    // or write made the members watched.
    final caller = CallerContexts.capture();
    final watch = SignalWatch(
      members: [
        for (final signal in names)
          makers[signal]?.call() ??
              (throw StateError(
                "${state.label}.$name watches '$signal', which is no "
                '@Signal field or @Computed value of the bean.',
              )),
      ],
      onWatched: onWatched,
      each: each,
      delay: delay,
      call: () => CallerContexts.runAs(caller, () {
        try {
          final result = signals.untracked(() => method.invoke(bean, const []));
          if (result is Future<Object?>) {
            result.catchError((Object error, StackTrace stackTrace) {
              _reportWatch(onWatched, state, name, error, stackTrace);
              return null;
            });
          }
        } on Object catch (error, stackTrace) {
          _reportWatch(onWatched, state, name, error, stackTrace);
        }
      }),
    );
    state.addEffect(watch.stop);
  }

  void _reportWatch(
    bool onWatched,
    SignalBean state,
    String name,
    Object error,
    StackTrace stackTrace,
  ) => runtime.errors.report(
    onWatched ? SignalExecutionKind.watched : SignalExecutionKind.unwatched,
    state.label,
    name,
    error,
    stackTrace,
  );

  void _startEffect(
    Object bean,
    SignalBean state,
    IntrospectedMethod<Object> method,
  ) {
    final owner = state.label;
    final methodName = method.name;
    final name = '$owner.$methodName';
    if (method.parameterTypes.isNotEmpty || method.parameters.isNotEmpty) {
      throw StateError(
        'Invalid @Effect method $name: it must not take parameters '
        '(nothing calls it with any: it runs when what it read changes).',
      );
    }
    state.effectRuns[methodName] = 0;
    void report(Object error, StackTrace stackTrace) => runtime.errors.report(
      SignalExecutionKind.effect,
      owner,
      methodName,
      error,
      stackTrace,
    );
    late final EffectFollower follower;
    // Through the bean as it is handed out, with all of its advice; the
    // generated body follows what it reads.
    void run() {
      state.effectRuns[methodName] = state.effectRuns[methodName]! + 1;
      _log.debug(() => 'effect $name runs');
      final result = runZoned(
        () => method.invoke(bean, const []),
        zoneValues: {EffectFollower.zoneKey: (state, methodName, follower)},
      );
      if (result is Future<Object?>) {
        result.then<void>((_) {}, onError: report);
      }
    }

    // A later run is nobody's call: it runs as the user the bean was made
    // for (never as the one whose change ran it), its failure goes to the
    // handler, and the effect goes on following what it followed.
    final caller = CallerContexts.capture();
    follower = EffectFollower(
      name: name,
      () => CallerContexts.runAs(caller, () {
        try {
          run();
        } on Object catch (error, stackTrace) {
          report(error, stackTrace);
        }
      }),
    );
    state
      ..effectFollowers[methodName] = follower
      ..addEffect(follower.stop);
    // The first run, as the bean is made: a failure is the bean's, and
    // stops it from being made.
    run();
  }

  @override
  bool requiresDestruction(Object bean) =>
      AopUtils.getTarget(bean) is SignalBeanHolder && beans.find(bean) != null;

  @override
  void postProcessBeforeDestruction(Object bean, String beanName) =>
      beans.close(bean);
}
