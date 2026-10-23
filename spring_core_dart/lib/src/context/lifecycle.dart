import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/log.dart';

/// A component that can be started and stopped, like Spring's `Lifecycle`.
///
/// Plain [Lifecycle] singletons are started only by an explicit
/// `context.start()` and stopped by `context.stop()` / `close()`.
///
/// ```dart
/// @Component()
/// class Poller implements Lifecycle {
///   Timer? _timer;
///
///   @override
///   void start() => _timer = Timer.periodic(
///     const Duration(seconds: 5),
///     (_) => poll(),
///   );
///
///   @override
///   void stop() => _timer?.cancel();
///
///   @override
///   bool get isRunning => _timer?.isActive ?? false;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Poller implements Lifecycle {
///   public void start() { ... }
///   public void stop() { ... }
///   public boolean isRunning() { ... }
/// }
/// ```
abstract interface class Lifecycle {
  /// Starts the component; not called when [isRunning] is already `true`.
  void start();

  /// Stops the component; only called when [isRunning] is `true`.
  void stop();

  /// Whether the component is currently running.
  bool get isRunning;
}

/// A [Lifecycle] started automatically at refresh and ordered by [phase],
/// like Spring's `SmartLifecycle`. Lower phases start first and stop last.
///
/// Mix it in (`with SmartLifecycle`) or extend it to get Spring's
/// defaults: [isAutoStartup] `true`, [phase] [defaultPhase] and
/// [stopWithCallback] calling [stop], then the callback; `implements`
/// works too (then every member is yours to write).
///
/// ```dart
/// @Component()
/// class WebSocketClient with SmartLifecycle {
///   bool _running = false;
///
///   @override
///   void start() => _running = true; // connect
///
///   @override
///   void stop() => _running = false; // disconnect
///
///   @override
///   bool get isRunning => _running;
///
///   @override
///   int get phase => 10;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class WebSocketClient implements SmartLifecycle {
///   public void start() { ... }
///   public void stop() { ... }
///   public boolean isRunning() { ... }
///   public int getPhase() { return 10; }
/// }
/// ```
abstract mixin class SmartLifecycle implements Lifecycle {
  /// Spring's default phase for smart lifecycles (starts last, stops
  /// first): `Integer.MAX_VALUE`, like `SmartLifecycle.DEFAULT_PHASE`.
  static const defaultPhase = 0x7FFFFFFF;

  /// Whether the context starts it at refresh; `true` by default.
  bool get isAutoStartup => true;

  /// Start/stop order: lower phases start earlier and stop later;
  /// [defaultPhase] by default.
  int get phase => defaultPhase;

  /// Stops the component and calls [callback] once it has stopped, like
  /// Spring's `stop(Runnable callback)`; by default [stop], then
  /// [callback]. The lifecycle processor stops smart lifecycles through
  /// this method. Unlike Spring, it does not wait for a [callback] that
  /// is called later (there are no per-phase stop timeouts).
  void stopWithCallback(void Function() callback) {
    stop();
    callback();
  }
}

/// Starts and stops lifecycle beans, like Spring's `LifecycleProcessor`.
///
/// The context uses a bean named `lifecycleProcessor` if one exists,
/// otherwise a [DefaultLifecycleProcessor].
///
/// ```dart
/// @Configuration()
/// class LifecycleConfig {
///   @Bean()
///   LifecycleProcessor lifecycleProcessor(
///     ConfigurableListableBeanFactory factory,
///   ) => DefaultLifecycleProcessor(factory);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// LifecycleProcessor lifecycleProcessor() {
///   return new DefaultLifecycleProcessor();
/// }
/// ```
abstract interface class LifecycleProcessor implements Lifecycle {
  /// Starts auto-startup [SmartLifecycle] beans (context refresh).
  void onRefresh();

  /// Stops running beans (context close).
  void onClose();
}

/// Default [LifecycleProcessor], like Spring's `DefaultLifecycleProcessor`:
/// phases ascending on start, descending on stop; plain [Lifecycle] beans
/// have phase 0.
///
/// Beans in the same phase start in registration order and stop in the
/// reverse order. Like Spring's `getLifecycleBeans`, only singletons are
/// considered, and of the plain [Lifecycle] beans only those already
/// created: a lazy plain [Lifecycle] bean is not created to be started or
/// stopped ([SmartLifecycle] beans are).
///
/// ```dart
/// final processor = DefaultLifecycleProcessor(context.beanFactory)
///   ..start(); // starts every Lifecycle bean, auto-startup or not
/// processor.stop();
/// ```
///
/// Spring (Java):
/// ```java
/// var processor = new DefaultLifecycleProcessor();
/// processor.setBeanFactory(beanFactory);
/// processor.start();
/// ```
///
/// Unlike Spring there are no per-phase stop timeouts.
class DefaultLifecycleProcessor implements LifecycleProcessor {
  /// Creates a processor managing the lifecycle singletons of
  /// [beanFactory].
  DefaultLifecycleProcessor(this.beanFactory);

  /// The factory the lifecycle beans are looked up in.
  final ConfigurableListableBeanFactory beanFactory;
  bool _running = false;

  @override
  bool get isRunning => _running;

  /// Starts every [Lifecycle] bean that is not running, auto-startup or
  /// not (explicit `context.start()`).
  @override
  void start() {
    _startBeans(autoStartupOnly: false);
    _running = true;
  }

  /// Stops every running [Lifecycle] bean, highest phase first.
  @override
  void stop() {
    _stopBeans();
    _running = false;
  }

  @override
  void onRefresh() {
    _startBeans(autoStartupOnly: true);
    _running = true;
  }

  @override
  void onClose() {
    _stopBeans();
    _running = false;
  }

  // Spring's getLifecycleBeans: created singletons and SmartLifecycle
  // beans (created if needed); a plain Lifecycle bean not created yet is
  // left alone.
  List<Lifecycle> _lifecycleBeans() {
    final smart = beanFactory
        .getBeanNamesForType(SmartLifecycle, includeNonSingletons: false)
        .toSet();
    return [
      for (final name in beanFactory.getBeanNamesForType(
        Lifecycle,
        includeNonSingletons: false,
      ))
        if (smart.contains(name) ||
            beanFactory.containsSingleton(
              name.startsWith(BeanFactory.factoryBeanPrefix)
                  ? name.substring(BeanFactory.factoryBeanPrefix.length)
                  : name,
            ))
          if (beanFactory.getBeanByName(name) case final Lifecycle bean
              when !identical(bean, this))
            bean,
    ];
  }

  List<Lifecycle> _byPhase({required bool descending}) {
    final beans = _lifecycleBeans();
    // Sort by phase, ties by registration index; reversing the whole
    // comparison makes stop order the exact mirror of start order.
    final indexed = beans.indexed.toList()
      ..sort((a, b) {
        final byPhase = _phase(a.$2).compareTo(_phase(b.$2));
        final ordered = byPhase != 0 ? byPhase : a.$1.compareTo(b.$1);
        return descending ? -ordered : ordered;
      });
    return [for (final (_, bean) in indexed) bean];
  }

  static int _phase(Lifecycle bean) => bean is SmartLifecycle ? bean.phase : 0;

  void _startBeans({required bool autoStartupOnly}) {
    for (final bean in _byPhase(descending: false)) {
      final eligible =
          !autoStartupOnly || (bean is SmartLifecycle && bean.isAutoStartup);
      if (eligible && !bean.isRunning) {
        bean.start();
      }
    }
  }

  // Like Spring's DefaultLifecycleProcessor: a bean that fails to stop is
  // logged and the remaining beans are still stopped.
  void _stopBeans() {
    for (final bean in _byPhase(descending: true)) {
      try {
        if (!bean.isRunning) {
          continue;
        }
        if (bean is SmartLifecycle) {
          bean.stopWithCallback(() {});
        } else {
          bean.stop();
        }
      } catch (error, stackTrace) {
        _log.warning(
          'Failed to stop lifecycle bean ${bean.runtimeType}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}

const _log = SpringLog('spring_core_dart.context');
