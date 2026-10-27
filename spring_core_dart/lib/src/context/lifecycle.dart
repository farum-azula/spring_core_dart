import 'dart:async';
import 'dart:collection';

import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/core/log.dart';

/// A context-level failure, like Spring's `ApplicationContextException`:
/// thrown, for example, when a [Lifecycle] bean fails to start
/// ("Failed to start bean 'x'", the bean's error as [cause]).
///
/// ```dart
/// try {
///   context.refresh();
/// } on ApplicationContextException catch (e) {
///   print('${e.message}: ${e.cause}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (ApplicationContextException ex) { ... }
/// ```
class ApplicationContextException extends BeansException {
  /// A failure described by [message], caused by [cause].
  const ApplicationContextException(super.message, {super.cause});
}

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

  /// Whether `context.pause()` stops it (and `context.restart()` starts it
  /// again); `true` by default, like Spring 7's `isPauseable()`. Return
  /// `false` for a component that must keep running while the context is
  /// paused (it still stops on `stop()` and `close()`).
  bool get isPauseable => true;

  /// Stops the component and calls [callback] once it has stopped, like
  /// Spring's `stop(Runnable callback)`; by default [stop], then
  /// [callback]. The lifecycle processor stops smart lifecycles through
  /// this method: `closeAsync()` waits for the callbacks of a phase (at
  /// most the processor's timeout for that phase) before stopping the
  /// next phase; the synchronous `stop()` / `close()` do not wait.
  ///
  /// ```dart
  /// @override
  /// void stopWithCallback(void Function() callback) {
  ///   _socket.close().whenComplete(callback);
  /// }
  /// ```
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
///   ) => DefaultLifecycleProcessor(
///     factory,
///     timeoutPerShutdownPhase: const Duration(seconds: 30),
///   );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// LifecycleProcessor lifecycleProcessor() {
///   var processor = new DefaultLifecycleProcessor();
///   processor.setTimeoutPerShutdownPhase(30000);
///   return processor;
/// }
/// ```
abstract interface class LifecycleProcessor implements Lifecycle {
  /// Starts auto-startup [SmartLifecycle] beans (context refresh).
  void onRefresh();

  /// Stops the pauseable beans if running, then starts the auto-startup
  /// beans again (context `restart()`), like Spring 7's `onRestart()`.
  void onRestart();

  /// Stops running beans except the [SmartLifecycle] beans that are not
  /// [SmartLifecycle.isPauseable] (context `pause()`), like Spring 7's
  /// `onPause()`; does not wait for [SmartLifecycle.stopWithCallback]
  /// callbacks that come later.
  void onPause();

  /// Like [onPause] (context `pauseAsync()`), waiting for the callbacks of
  /// [SmartLifecycle.stopWithCallback] phase by phase.
  Future<void> onPauseAsync();

  /// Stops running beans (context close); does not wait for
  /// [SmartLifecycle.stopWithCallback] callbacks that come later.
  void onClose();

  /// Stops running beans (context `closeAsync()`), waiting for the
  /// callbacks of [SmartLifecycle.stopWithCallback] phase by phase.
  Future<void> onCloseAsync();
}

/// Default [LifecycleProcessor], like Spring's `DefaultLifecycleProcessor`:
/// phases ascending on start, descending on stop; plain [Lifecycle] beans
/// have phase 0.
///
/// Beans in the same phase start in registration order and stop in the
/// reverse order; a bean's dependencies (injected or `dependsOn`) start
/// before it and its dependents stop before it, whatever their phase. Like
/// Spring's `getLifecycleBeans`, only singletons are considered, and of
/// the plain [Lifecycle] beans only those already created: a lazy plain
/// [Lifecycle] bean is not created to be started or stopped
/// ([SmartLifecycle] beans are). At refresh a plain [Lifecycle] bean is
/// started only as the dependency of an auto-startup bean.
///
/// On `closeAsync()` the processor waits, per phase, for the callbacks
/// of [SmartLifecycle.stopWithCallback] at most [timeoutPerShutdownPhase]
/// (or the phase's entry in [timeoutsForShutdownPhases]), logs the beans
/// still running and goes on with the next phase, like Spring. The
/// synchronous `stop()` / `close()` do not wait (Spring's block); a bean
/// asked to start while its stop callback is still pending (`restart()`,
/// or `start()` right after `stop()`) is started when the callback fires
/// instead of being skipped as running.
///
/// Like Spring 7, `pause()` stops the running beans except the
/// [SmartLifecycle] beans that are not [SmartLifecycle.isPauseable] (plain
/// [Lifecycle] beans are stopped too) and `restart()` stops the pauseable
/// beans if still running, then starts the auto-startup beans again, which
/// restores the state after refresh.
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
class DefaultLifecycleProcessor implements LifecycleProcessor {
  /// Creates a processor managing the lifecycle singletons of
  /// [beanFactory]; see [timeoutPerShutdownPhase] and
  /// [timeoutsForShutdownPhases].
  DefaultLifecycleProcessor(
    this.beanFactory, {
    this.timeoutPerShutdownPhase = const Duration(seconds: 10),
    Map<int, Duration> timeoutsForShutdownPhases = const {},
  }) : timeoutsForShutdownPhases = {...timeoutsForShutdownPhases};

  /// The factory the lifecycle beans are looked up in.
  final ConfigurableListableBeanFactory beanFactory;

  /// How long `closeAsync()` waits for the stop callbacks of one phase
  /// (Spring's `timeoutPerShutdownPhase`, 10 seconds by default).
  Duration timeoutPerShutdownPhase;

  /// Timeouts of specific phases, overriding [timeoutPerShutdownPhase]
  /// (Spring's `timeoutsForShutdownPhases`).
  final Map<int, Duration> timeoutsForShutdownPhases;

  bool _running = false;

  // SmartLifecycle beans whose stopWithCallback callback has not fired yet
  // (Spring's stop() blocks on a latch per phase; Dart cannot block), and
  // those of them to start once it fires: a start (restart(), or start()
  // after stop()) asked for while they were still stopping.
  final _stopping = <String, Completer<void>>{};
  final _startWhenStopped = <String>{};

  /// The timeout for the shutdown of [phase] (Spring's
  /// `determineTimeout`).
  Duration timeoutForShutdownPhase(int phase) =>
      timeoutsForShutdownPhases[phase] ?? timeoutPerShutdownPhase;

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
  void onRestart() {
    if (_running) {
      _stopBeans(pauseableOnly: true);
    }
    _startBeans(autoStartupOnly: true);
    _running = true;
  }

  @override
  void onPause() {
    if (_running) {
      _stopBeans(pauseableOnly: true);
      _running = false;
    }
  }

  @override
  Future<void> onPauseAsync() async {
    if (_running) {
      await _stopBeansAsync(pauseableOnly: true);
      _running = false;
    }
  }

  @override
  void onClose() {
    _stopBeans();
    _running = false;
  }

  @override
  Future<void> onCloseAsync() async {
    await _stopBeansAsync();
    _running = false;
  }

  // Spring's getLifecycleBeans: created singletons and SmartLifecycle
  // beans (created if needed) by name; a plain Lifecycle bean not created
  // yet is left alone. A created singleton counts by its instance too (a
  // `@Bean Object server()` returning a Lifecycle, like Spring matching
  // the singleton's actual type).
  Map<String, Lifecycle> _lifecycleBeans() {
    final smart = beanFactory
        .getBeanNamesForType(SmartLifecycle, includeNonSingletons: false)
        .toSet();
    final beans = <String, Lifecycle>{};
    for (final name in beanFactory.getBeanNamesForType(
      Lifecycle,
      includeNonSingletons: false,
    )) {
      final canonical = name.startsWith(BeanFactory.factoryBeanPrefix)
          ? name.substring(BeanFactory.factoryBeanPrefix.length)
          : name;
      if (!smart.contains(name) && !beanFactory.containsSingleton(canonical)) {
        continue;
      }
      if (beanFactory.getBeanByName(name) case final Lifecycle bean
          when !identical(bean, this)) {
        beans[canonical] = bean;
      }
    }
    for (final name in beanFactory.singletonNames) {
      if (beans.containsKey(name)) {
        continue;
      }
      if (beanFactory.getSingleton(name) case final Lifecycle bean
          when !identical(bean, this) &&
              !beans.values.any((known) => identical(known, bean))) {
        beans[name] = bean;
      }
    }
    return beans;
  }

  static int _phase(Lifecycle bean) => bean is SmartLifecycle ? bean.phase : 0;

  // Like Spring's startBeans: the candidates grouped by phase, ascending;
  // every bean when started explicitly, the auto-startup SmartLifecycle
  // beans at refresh.
  void _startBeans({required bool autoStartupOnly}) {
    final beans = _lifecycleBeans();
    final phases = SplayTreeMap<int, List<String>>();
    beans.forEach((name, bean) {
      if (!autoStartupOnly || (bean is SmartLifecycle && bean.isAutoStartup)) {
        phases.putIfAbsent(_phase(bean), () => []).add(name);
      }
    });
    for (final names in phases.values) {
      for (final name in names) {
        _doStart(beans, name, autoStartupOnly: autoStartupOnly);
      }
    }
  }

  // Like Spring's doStart: the bean's dependencies first (removed from
  // [beans], so each bean starts once); a SmartLifecycle dependency that
  // is not auto-startup is skipped at refresh, a plain one is started.
  void _doStart(
    Map<String, Lifecycle> beans,
    String name, {
    required bool autoStartupOnly,
  }) {
    final bean = beans.remove(name);
    if (bean == null) {
      return;
    }
    for (final dependency in beanFactory.getDependenciesForBean(name)) {
      _doStart(beans, dependency, autoStartupOnly: autoStartupOnly);
    }
    if (autoStartupOnly && bean is SmartLifecycle && !bean.isAutoStartup) {
      return;
    }
    if (_stopping.containsKey(name)) {
      // Still stopping: started when its stop callback fires, instead of
      // being skipped as running and ending up stopped.
      _startWhenStopped.add(name);
      return;
    }
    if (!bean.isRunning) {
      try {
        bean.start();
      } on Object catch (error, stackTrace) {
        // Spring's doStart wraps the failure, naming the bean.
        Error.throwWithStackTrace(
          ApplicationContextException(
            "Failed to start bean '$name'",
            cause: error,
          ),
          stackTrace,
        );
      }
    }
  }

  // All lifecycle beans grouped by phase, highest first; within a phase
  // the reverse of the start order.
  static List<(int, List<String>)> _shutdownPhases(
    Map<String, Lifecycle> beans,
  ) {
    final phases = SplayTreeMap<int, List<String>>((a, b) => b.compareTo(a));
    beans.forEach(
      (name, bean) => phases.putIfAbsent(_phase(bean), () => []).add(name),
    );
    return [
      for (final MapEntry(:key, :value) in phases.entries)
        (key, value.reversed.toList()),
    ];
  }

  void _stopBeans({bool pauseableOnly = false}) {
    final beans = _lifecycleBeans();
    for (final (_, names) in _shutdownPhases(beans)) {
      for (final name in names) {
        _doStop(beans, name, pending: null, pauseableOnly: pauseableOnly);
      }
    }
  }

  Future<void> _stopBeansAsync({bool pauseableOnly = false}) async {
    final beans = _lifecycleBeans();
    for (final (phase, names) in _shutdownPhases(beans)) {
      final pending = <String, Future<void>>{};
      for (final name in names) {
        _doStop(beans, name, pending: pending, pauseableOnly: pauseableOnly);
      }
      await _awaitPhase(phase, pending);
    }
  }

  // Like Spring's doStop: the beans depending on this one first. A
  // SmartLifecycle is stopped through stopWithCallback; when [pending] is
  // given, its callback is waited for by phase. When pausing, a
  // SmartLifecycle that is not pauseable keeps running. A bean that fails
  // to stop is logged and the remaining beans are still stopped.
  void _doStop(
    Map<String, Lifecycle> beans,
    String name, {
    required Map<String, Future<void>>? pending,
    bool pauseableOnly = false,
  }) {
    final bean = beans.remove(name);
    if (bean == null) {
      return;
    }
    for (final dependent in beanFactory.getDependentBeans(name)) {
      _doStop(beans, dependent, pending: pending, pauseableOnly: pauseableOnly);
    }
    try {
      if (bean is SmartLifecycle && pauseableOnly && !bean.isPauseable) {
        return;
      }
      _startWhenStopped.remove(name);
      if (_stopping[name] case final stopping?) {
        // A stop still in progress: wait for its callback.
        pending?[name] = stopping.future;
        return;
      }
      if (!bean.isRunning) {
        return;
      }
      if (bean is SmartLifecycle) {
        final stopped = Completer<void>();
        _stopping[name] = stopped;
        pending?[name] = stopped.future;
        bean.stopWithCallback(() => _stopped(name, bean, stopped));
      } else {
        bean.stop();
      }
    } on Object catch (error, stackTrace) {
      // Removes the entry from the map; no future is started here.
      // ignore: discarded_futures
      pending?.remove(name);
      if (_stopping.remove(name) case final stopped?
          when !stopped.isCompleted) {
        stopped.complete();
      }
      _log.warning(
        "Failed to stop bean '$name'",
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // The stop callback of [bean]: once only; starts the bean again when a
  // start was asked for meanwhile.
  void _stopped(String name, SmartLifecycle bean, Completer<void> stopped) {
    if (stopped.isCompleted) {
      return;
    }
    stopped.complete();
    if (identical(_stopping[name], stopped)) {
      _stopping.remove(name);
    }
    if (!_startWhenStopped.remove(name) || bean.isRunning) {
      return;
    }
    try {
      bean.start();
    } on Object catch (error, stackTrace) {
      _log.warning(
        "Failed to start bean '$name' after its stop callback",
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // Like Spring's LifecycleGroup.stop: waits for the phase's callbacks at
  // most the phase's timeout, then logs the beans still running.
  Future<void> _awaitPhase(int phase, Map<String, Future<void>> pending) {
    if (pending.isEmpty) {
      return Future<void>.value();
    }
    final running = {...pending.keys};
    final timeout = timeoutForShutdownPhase(phase);
    return Future.wait([
      for (final MapEntry(:key, :value) in pending.entries)
        value.whenComplete(() => running.remove(key)),
    ]).timeout(
      timeout,
      onTimeout: () {
        final count = running.length;
        _log.warning(
          'Failed to shut down $count bean${count == 1 ? '' : 's'} with phase '
          'value $phase within timeout of ${timeout.inMilliseconds}ms: '
          '${running.toList()}',
        );
        return const [];
      },
    );
  }
}

const _log = SpringLog('spring_core_dart.context');
