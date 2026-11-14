import 'package:flutter/foundation.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/annotations.dart';
import 'package:spring_boot_starter_flutter_signals/src/follow_keeper.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/signals_advice.dart';

const _log = SpringLog('spring.flutter.signals');

/// Finds, before any bean is made, the beans that have a `@Signal`,
/// `@Computed` or `@Effect` member: the advice then covers each of their
/// methods, not only the annotated members. It stops the start for one
/// whose proxy cannot follow the bean's own calls (an application built
/// by a generator older than this starter).
final class SignalBeanNames implements BeanFactoryPostProcessor {
  /// The finder that fills [beans].
  const SignalBeanNames(this.beans);

  /// Where the names are kept.
  final SignalBeans beans;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    for (final name in beanFactory.beanDefinitionNames) {
      final proxy = beanFactory.aopProxyOf(
        beanFactory.getBeanDefinition(name),
      );
      if (proxy == null || !proxy.signatures.any(SignalsPointcut.isAnnotated)) {
        continue;
      }
      // The proxy of such a bean extends it and follows its own calls. One
      // that wraps the bean was written by a generator that knows nothing
      // of followed state: the bean's own code would read and assign its
      // fields past it, and nothing would be told.
      if (!proxy.adviseSelfCalls) {
        throw StateError(
          "The bean '$name' has @Signal, @Computed or @Effect members, but "
          'its generated proxy does not follow them: the application was '
          'built by a spring_core_dart_generator older than 0.8.1, or with '
          'aop_proxies other than `all`. Update the generator '
          '(dev_dependencies: spring_core_dart_generator: ^0.8.1), leave '
          'aop_proxies at its default, and build again.',
        );
      }
      beans.names.add(name);
    }
  }
}

/// Starts the `@Effect` methods of a bean once it is made (and advised),
/// and ends its followed state when it is destroyed.
///
/// An effect runs at once, and again each time something it read changes.
/// A run that throws as the bean is made stops it from being made; a
/// later one is reported (`FlutterError.reportError`) and the effect
/// lives on.
/// The state ends before the bean's own `@PreDestroy` methods run; from
/// then on its members read and write the bean's own fields, so those
/// methods still see their values.
final class SignalEffects extends DestructionAwareBeanPostProcessor
    implements BeanFactoryAware, Ordered {
  /// The processor over the state kept in [beans].
  SignalEffects(this.beans);

  /// The beans with followed state.
  final SignalBeans beans;

  BeanFactory? _beanFactory;

  // After the auto proxy creator: an effect must run on the advised bean,
  // or its reads would not be followed.
  @override
  int get order => Ordered.lowestPrecedence;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (!beans.names.contains(beanName) ||
        factory is! BeanDefinitionRegistry ||
        !(factory as BeanDefinitionRegistry).containsBeanDefinition(
          beanName,
        )) {
      return bean;
    }
    final definition = (factory as BeanDefinitionRegistry).getBeanDefinition(
      beanName,
    );
    final owner = switch (definition.source?.split('#')) {
      [_, final name] when name.isNotEmpty && !name.contains('.') => name,
      _ => beanName,
    };
    if (bean is! Advised ||
        !bean.aopAdvisors.any((a) => a.advice is SignalsInterceptor)) {
      throw StateError(
        "The bean '$beanName' ($owner) has @Signal, @Computed or @Effect "
        'members, but is not advised: nothing would follow its state. '
        'The application must be built by the generator with proxies '
        '(aop_proxies: all, the default), and the bean made by the '
        'container, not by a @Bean method that calls its constructor.',
      );
    }
    // The state exists from now on, so the bean's destruction ends it.
    final state = beans.of(bean, owner);
    for (final method in definition.annotatedMethods) {
      if (method.annotations.whereType<Effect>().isEmpty) {
        continue;
      }
      final name = '$owner.${method.name}';
      if (method.parameterTypes.isNotEmpty || method.parameters.isNotEmpty) {
        throw StateError(
          'Invalid @Effect method $name: it must not take parameters '
          '(nothing calls it with any: it runs when what it read changes).',
        );
      }
      state.effectRuns[method.name] = 0;
      // A first run that fails: the bean is not made, for the reason its
      // own code gave.
      // The first run, as the bean is made: a failure is the bean's, and
      // stops it from being made. A later run is nobody's call: its
      // failure is reported, not thrown at the code whose assignment ran
      // it, and the effect goes on following what it followed.
      final keeper = FollowKeeper();
      var made = false;
      state.addEffect(
        unwrapped(
          () => signals.effect(() {
            state.effectRuns[method.name] = state.effectRuns[method.name]! + 1;
            _log.debug(() => 'effect $name runs');
            if (!made) {
              keeper.run(() => method.invoke(bean, const []));
              return;
            }
            try {
              keeper.run(() => method.invoke(bean, const []));
            } on Object catch (error, stackTrace) {
              _report(name, error, stackTrace);
            }
          }, options: signals.EffectOptions(name: name)),
        ),
      );
      made = true;
    }
    return bean;
  }

  // As a ChangeNotifier does for a listener that throws: the error is
  // the application's to see (the console, a crash reporter), and whoever
  // changed the state goes on.
  static void _report(String name, Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'spring_boot_starter_flutter_signals',
        context: ErrorDescription('while running the effect $name'),
      ),
    );
  }

  @override
  bool requiresDestruction(Object bean) => beans.find(bean) != null;

  @override
  void postProcessBeforeDestruction(Object bean, String beanName) =>
      beans.close(bean);
}
