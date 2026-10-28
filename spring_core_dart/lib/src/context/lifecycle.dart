import 'dart:async';
import 'dart:collection';

import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/core/log.dart';

/// The error a context throws when one of its own steps fails, as opposed
/// to an error in creating a bean.
///
/// Today it is thrown when a [Lifecycle] bean fails to start: the message
/// is "Failed to start bean 'x'" and the bean's own error is the [cause].
/// Applications receive it from `refresh()` or `start()`; they do not
/// throw it.
///
/// ```dart
/// // Report which bean failed to start, and why.
/// try {
///   context.refresh();
/// } on ApplicationContextException catch (e) {
///   log.error(e.message, error: e.cause);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (ApplicationContextException ex) { ... }
/// ```
class ApplicationContextException extends BeansException {
  /// Creates the error with [message] and the underlying [cause].
  const ApplicationContextException(super.message, {super.cause});
}

/// A bean that runs something in the background between a start and a
/// stop, such as a timer, a server or a connection.
///
/// Implement it so that the context can stop the background work: on
/// `context.stop()`, on `close()` (before the beans are destroyed) and on
/// `pause()`. A plain [Lifecycle] bean is not started at refresh, only by
/// an explicit `context.start()`, or at refresh when an auto-startup bean
/// depends on it. For a bean that should start by itself with the
/// application, which is the usual case, use [SmartLifecycle]. Only
/// singletons take part, and a lazy plain [Lifecycle] bean only once it
/// was created.
///
/// ```dart
/// // Polls every 5 seconds while the context runs.
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
  /// Starts the background work. The context does not call it when
  /// [isRunning] is already `true`; an error thrown here fails the start
  /// as an [ApplicationContextException].
  void start();

  /// Stops the background work. The context calls it only when
  /// [isRunning] is `true`; an error thrown here is logged and the other
  /// beans are still stopped.
  void stop();

  /// Whether the background work is running; the context asks before
  /// starting or stopping the bean.
  bool get isRunning;
}

/// A [Lifecycle] bean that the context starts by itself at the end of the
/// refresh and stops in order at shutdown.
///
/// This is the usual way to run background work with the application: a
/// client that connects at startup, a scheduler, a server. [phase] orders
/// the beans: lower phases start first and stop last, so a bean that
/// others need gets a lower phase. [stopWithCallback] lets a bean stop
/// asynchronously (closing a socket), and `closeAsync()` waits for it.
/// [isPauseable] keeps a bean running during `pause()`.
///
/// Mix it in (`with SmartLifecycle`) or extend it to get Spring's
/// defaults: [isAutoStartup] `true`, [phase] [defaultPhase] and
/// [stopWithCallback] calling [stop], then the callback. `implements`
/// works too; then every member is yours to write.
///
/// ```dart
/// // Connects when the application starts, disconnects at shutdown,
/// // before the beans in lower phases stop.
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
  /// The default [phase]: the highest value, so the bean starts after all
  /// others and stops before them. Spring's `SmartLifecycle.DEFAULT_PHASE`
  /// (`Integer.MAX_VALUE`).
  static const defaultPhase = 0x7FFFFFFF;

  /// Whether the context starts the bean at the end of the refresh;
  /// `true` by default. With `false` it starts only on an explicit
  /// `context.start()`.
  bool get isAutoStartup => true;

  /// The start and stop order: lower phases start earlier and stop later;
  /// [defaultPhase] by default. Plain [Lifecycle] beans count as phase 0.
  /// A bean's dependencies start before it whatever their phase.
  int get phase => defaultPhase;

  /// Whether `context.pause()` stops the bean (and `context.restart()`
  /// starts it again); `true` by default, as Spring 7's `isPauseable()`.
  /// Return `false` for work that must go on while the application is in
  /// the background; the bean still stops on `stop()` and `close()`.
  bool get isPauseable => true;

  /// Stops the bean and calls [callback] once it has really stopped;
  /// override it when stopping is asynchronous. By default it calls
  /// [stop], then [callback].
  ///
  /// The lifecycle processor always stops smart lifecycle beans through
  /// this method. `closeAsync()` waits for the callbacks of a phase (at
  /// most the processor's timeout for that phase) before it stops the next
  /// phase; the synchronous `stop()` and `close()` do not wait. Call
  /// [callback] exactly once, also when stopping fails. Spring's
  /// `stop(Runnable callback)`.
  ///
  /// ```dart
  /// // The bean counts as stopped once the socket is closed.
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

/// The part of the context that starts and stops its [Lifecycle] beans,
/// at refresh, pause, restart and close.
///
/// Applications rarely touch it. The context uses a bean named
/// `lifecycleProcessor` if one exists, otherwise a
/// [DefaultLifecycleProcessor]. Declare one to change the shutdown
/// timeouts; implement the interface only for a different start and stop
/// strategy.
///
/// ```dart
/// // Give the beans 30 seconds per phase to stop.
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
  /// Starts the auto-startup [SmartLifecycle] beans; called at the end of
  /// the context's refresh.
  void onRefresh();

  /// Stops the pauseable beans if they are still running, then starts the
  /// auto-startup beans again; called by the context's `restart()`
  /// (Spring 7's `onRestart()`).
  void onRestart();

  /// Stops the running beans except the [SmartLifecycle] beans that are
  /// not [SmartLifecycle.isPauseable]; called by the context's `pause()`
  /// (Spring 7's `onPause()`). Does not wait for
  /// [SmartLifecycle.stopWithCallback] callbacks that come later.
  void onPause();

  /// Like [onPause], but waits for the callbacks of
  /// [SmartLifecycle.stopWithCallback] phase by phase; called by the
  /// context's `pauseAsync()`.
  Future<void> onPauseAsync();

  /// Stops the running beans; called by the context's `close()` and by a
  /// failed refresh. Does not wait for [SmartLifecycle.stopWithCallback]
  /// callbacks that come later.
  void onClose();

  /// Stops the running beans, waiting for the callbacks of
  /// [SmartLifecycle.stopWithCallback] phase by phase; called by the
  /// context's `closeAsync()`.
  Future<void> onCloseAsync();
}

/// The [LifecycleProcessor] every context uses unless it declares its own:
/// it starts the lifecycle beans phase by phase, lowest first, and stops
/// them in the reverse order.
///
/// Applications meet it only to change the shutdown timeouts, by declaring
/// a `lifecycleProcessor` bean. Plain [Lifecycle] beans have phase 0.
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
/// // Outside a context: drive the lifecycle beans of a bean factory.
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
  /// Creates a processor for the lifecycle singletons of [beanFactory].
  /// [timeoutPerShutdownPhase] defaults to 10 seconds;
  /// [timeoutsForShutdownPhases] overrides it for single phases.
  DefaultLifecycleProcessor(
    this.beanFactory, {
    this.timeoutPerShutdownPhase = const Duration(seconds: 10),
    Map<int, Duration> timeoutsForShutdownPhases = const {},
  }) : timeoutsForShutdownPhases = {...timeoutsForShutdownPhases};

  /// The factory whose lifecycle beans are started and stopped.
  final ConfigurableListableBeanFactory beanFactory;

  /// How long `closeAsync()` and `pauseAsync()` wait for the stop
  /// callbacks of one phase before they log the beans still running and
  /// go on; 10 seconds by default (Spring's `timeoutPerShutdownPhase`).
  Duration timeoutPerShutdownPhase;

  /// Timeouts for single phases, by phase, overriding
  /// [timeoutPerShutdownPhase]; for example a longer one for the phase of
  /// a server that drains its requests (Spring's
  /// `timeoutsForShutdownPhases`).
  final Map<int, Duration> timeoutsForShutdownPhases;

  bool _running = false;

  // SmartLifecycle beans whose stopWithCallback callback has not fired yet
  // (Spring's stop() blocks on a latch per phase; Dart cannot block), and
  // those of them to start once it fires: a start (restart(), or start()
  // after stop()) asked for while they were still stopping.
  final _stopping = <String, Completer<void>>{};
  final _startWhenStopped = <String>{};

  /// The timeout for the shutdown of [phase]: its entry in
  /// [timeoutsForShutdownPhases], else [timeoutPerShutdownPhase] (Spring's
  /// `determineTimeout`).
  Duration timeoutForShutdownPhase(int phase) =>
      timeoutsForShutdownPhases[phase] ?? timeoutPerShutdownPhase;

  @override
  bool get isRunning => _running;

  /// Starts every [Lifecycle] bean that is not running, auto-startup or
  /// not; called by an explicit `context.start()`.
  @override
  void start() {
    _startBeans(autoStartupOnly: false);
    _running = true;
  }

  /// Stops every running [Lifecycle] bean, highest phase first, without
  /// waiting for stop callbacks; called by `context.stop()`.
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
