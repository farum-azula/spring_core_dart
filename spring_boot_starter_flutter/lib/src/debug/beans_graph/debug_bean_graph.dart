import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_edge.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_event.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_graph_reader.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_graph_snapshot.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_lifecycle_recorder.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_module.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_role.dart';

/// The data of the "Beans" layer of the debug application graph
/// (`debugBeanGraph`): the application's beans grouped by module, what
/// each depends on, how it was made and what advises it, and the beans
/// created and destroyed while it runs.
///
/// [snapshot] reads the context on demand: by default only the beans the
/// application defined (its `@Service`, `@Component`, `@Repository`,
/// `@Configuration` and `@Bean` methods, controllers, and the Spring
/// widgets that inject beans), with [includeFramework] the framework's and
/// the auto-configurations' too. It creates no bean.
///
/// Between [start] and [stop] the graph hears of every bean created and
/// destroyed (a route's beans come and go with their screen): it keeps
/// them in [events] and tells its listeners once per burst, after the
/// container is done. Outside of that it adds nothing to the container:
/// no post-processor, no callback ([recorder] is `null`), so a running
/// app pays for it only while a view shows it; and the generator leaves
/// it out of the build when `spring.flutter.debug.graph.layers` does not
/// let `beans` in, with the views of the graph.
///
/// ```dart
/// final graph = context.getBean<DebugBeanGraph>()..start();
/// graph.addListener(() {
///   for (final event in graph.eventsAfter(seen)) { ... }
///   final beans = graph.snapshot.beans;
/// });
/// // The beans behind a widget on screen.
/// final widget = graph.snapshot.widgetOf(basketBadge.beansType)!;
/// final shown = graph.snapshot.closureOf([widget.name]);
/// graph.stop();
/// ```
///
/// Method calls are not followed: for that, the `@Observed` methods'
/// observations (an `ObservationHandler` bean, as the timeline's) or an
/// advisor bean of the application are the hooks.
final class DebugBeanGraph extends ChangeNotifier {
  /// The graph of [context]'s beans, with [roles] and up to [maxEvents]
  /// events kept.
  DebugBeanGraph(
    this.context, {
    this.roles = const DebugBeanRoles(),
    this.maxEvents = 256,
  });

  /// The application.
  final ConfigurableApplicationContext context;

  /// The roles of the beans.
  final DebugBeanRoles roles;

  /// How many of the latest [events] are kept.
  final int maxEvents;

  DebugBeanModules _modules = DebugBeanModules.none;
  bool _includeFramework = false;
  DebugBeanLifecycleRecorder? _recorder;
  DebugBeanGraphSnapshot? _snapshot;
  final _instances = <String, int>{};
  final _declaredEdges = <String, List<DebugBeanEdge>>{};
  final _events = ListQueue<DebugBeanEvent>();
  var _sequence = 0;
  var _notifyScheduled = false;
  var _disposed = false;

  /// Which beans the application defined and where each comes from:
  /// those of the `SpringApplication` that started the context (set when
  /// it has started), none known before.
  DebugBeanModules get modules => _modules;

  set modules(DebugBeanModules modules) {
    _modules = modules;
    _changed();
  }

  /// Takes the modules of [application], the one that started the
  /// context; the bean definition calls it on `ApplicationStartedEvent`.
  void useApplication(SpringApplication application) =>
      modules = DebugBeanModules.of(application);

  /// Whether [snapshot] has the framework's beans too; `false` (only the
  /// application's) by default.
  bool get includeFramework => _includeFramework;

  set includeFramework(bool include) {
    if (include != _includeFramework) {
      _includeFramework = include;
      _changed();
    }
  }

  /// The post-processor that tells the graph of the beans created and
  /// destroyed: in the bean factory between [start] and [stop], `null`
  /// (and nowhere) otherwise.
  DebugBeanLifecycleRecorder? get recorder => _recorder;

  /// Whether the graph follows the beans created and destroyed.
  bool get running => _recorder != null;

  /// The beans now, read again after each change.
  DebugBeanGraphSnapshot get snapshot => _snapshot ??= DebugBeanGraphReader(
    context,
    modules: _modules,
    roles: roles,
    instances: _instances,
    declaredEdges: _declaredEdges,
  ).read(includeFramework: _includeFramework);

  /// The latest beans created and destroyed while the graph ran, oldest
  /// first.
  List<DebugBeanEvent> get events => List.unmodifiable(_events);

  /// The [events] after the one numbered [sequence]: what a listener has
  /// not seen yet.
  List<DebugBeanEvent> eventsAfter(int sequence) => [
    for (final event in _events)
      if (event.sequence > sequence) event,
  ];

  /// Starts following the beans created and destroyed. A bean of a
  /// custom scope created before is not counted in its
  /// `DebugBean.instances`: the scope does not tell of it.
  void start() {
    final factory = context.beanFactory;
    if (running || factory is! DefaultListableBeanFactory) {
      return;
    }
    factory.addBeanPostProcessor(
      _recorder = DebugBeanLifecycleRecorder(factory, _record),
    );
    _changed();
  }

  /// Stops following them; the container does no more work for the graph.
  void stop() {
    final recorder = _recorder;
    final factory = context.beanFactory;
    if (recorder == null || factory is! DefaultListableBeanFactory) {
      return;
    }
    factory.removeBeanPostProcessor(recorder);
    _recorder = null;
    _instances.clear();
    _changed();
  }

  /// Reads the beans again at the next [snapshot], the injection points
  /// resolved anew too (a lazy bean created while the graph was stopped, a
  /// singleton registered later).
  void refresh() {
    _declaredEdges.clear();
    _changed();
  }

  // Called by the recorder while the container creates or destroys the
  // bean: only takes note; the listeners hear of it after.
  void _record(DebugBeanEventKind kind, String beanName) {
    final factory = context.beanFactory;
    if (factory.containsBeanDefinition(beanName) &&
        !factory.getBeanDefinition(beanName).isSingleton) {
      final count =
          (_instances[beanName] ?? 0) +
          (kind == DebugBeanEventKind.created ? 1 : -1);
      _instances[beanName] = count < 0 ? 0 : count;
    }
    _events.addLast(
      DebugBeanEvent(++_sequence, kind, beanName, DateTime.now()),
    );
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    _changed();
  }

  void _changed() {
    _snapshot = null;
    if (_notifyScheduled || _disposed) {
      return;
    }
    // After the container (and the frame building a route's widgets) is
    // done, once for a burst of beans.
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}
