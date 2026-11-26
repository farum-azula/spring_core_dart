import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_edge.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_graph.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_graph_snapshot.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_role.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_skipped_bean.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_routes.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_screen.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_widgets.dart';

/// The beans as a layer of the application graph (`beansGraphLayer`), from
/// the [DebugBeanGraph]: by default the beans the application defined,
/// each module a lane (`shop/basket`, an auto-configuration), each role in
/// a shape of its own; an edge from a bean to each bean that injects it,
/// dashed for a `@Lazy` point, an `ObjectProvider` and a `@DependsOn`; a
/// bean flashes when an instance of it is created or destroyed (a route's
/// beans with their screen).
///
/// Its options (the graph's `Options` menu): `framework` adds the
/// framework's and the auto-configurations' beans, `skipped` the beans a
/// condition left out (grey, in "All"). Its nodes are in the debug
/// theme's `graph-beans`. "On screen" keeps the beans the Spring widgets on the
/// screen inject and everything those depend on.
///
/// Node ids: `beans:<bean name>`, `beans:skipped:<source>` for a bean left
/// out. A bean a Spring widget injects has an edge to the widget's node,
/// `DebugGraphWidgets.idOf(element)`, drawn when the widgets layer shows;
/// the layer makes no node of a widget. In "On screen" such a bean carries
/// the widget ([DebugGraphNode.widget]), so the graph keeps it and what it
/// depends on with or without the widgets layer.
///
/// With the route grouping of [routes] (the default of the app's graph)
/// the lanes are the navigator stack instead of the modules: a bean of a
/// route scope is in the lane of the route it lives in (the topmost, when
/// it lives in several), a singleton in `App`; a bean of a route scope
/// that lives in no route has no lane. When a route closes, its beans
/// flash in its lane as they are destroyed, then leave it.
///
/// It follows the beans only while a view shows it ([start]); in the
/// build by `spring.flutter.debug.graph.layers` naming `beans` (or `*`,
/// or not set), with a view of the graph.
final class BeansGraphLayer extends DebugGraphLayer {
  /// The layer of [graph]; [springWidgets] and [shows] find the Spring
  /// widgets and tell whether one is on the screen.
  BeansGraphLayer(
    this.graph, {
    this.springWidgets = DebugGraphWidgets.springWidgets,
    this.shows = DebugGraphScreen.shows,
    this.routes,
  });

  /// The beans.
  final DebugBeanGraph graph;

  /// How the graph groups its nodes, and the routes for the route
  /// grouping; `null`: by module.
  final DebugGraphRoutes? routes;

  /// The Spring widgets in the tree.
  final List<DebugGraphSpringWidget> Function() springWidgets;

  /// Whether a widget is on the screen.
  final bool Function(BuildContext widget) shows;

  /// How long a bean glows after an instance was created or destroyed.
  static const flash = Duration(seconds: 1);

  /// The prefix of its node ids.
  static const prefix = 'beans:';

  /// The id of the node of the bean [name].
  static String idOf(String name) => '$prefix$name';

  /// The id of the node of a bean left out, by its condition [source].
  static String skippedIdOf(String source) => '${prefix}skipped:$source';

  static const _kinds = {
    DebugBeanRole.service: DebugGraphKind(
      'service',
      '@Service',
      DebugGraphShape.rounded,
      description: 'A @Service bean: the business logic',
    ),
    DebugBeanRole.repository: DebugGraphKind(
      'repository',
      '@Repository',
      DebugGraphShape.rectangle,
      description: 'A @Repository bean: reads and writes the data',
    ),
    DebugBeanRole.component: DebugGraphKind(
      'component',
      '@Component',
      DebugGraphShape.pill,
      description: 'A @Component bean of no more special role',
    ),
    DebugBeanRole.configuration: DebugGraphKind(
      'configuration',
      '@Configuration',
      DebugGraphShape.octagon,
      description: 'A @Configuration class: it declares @Bean methods',
    ),
    DebugBeanRole.factoryMethod: DebugGraphKind(
      'factoryMethod',
      '@Bean',
      DebugGraphShape.hexagon,
      description: 'A bean made by a @Bean method of a configuration',
    ),
    DebugBeanRole.controller: DebugGraphKind(
      'controller',
      '@Controller',
      DebugGraphShape.parallelogram,
      description: 'A @Controller bean: it answers requests',
    ),
    DebugBeanRole.infrastructure: DebugGraphKind(
      'infrastructure',
      'infrastructure',
      DebugGraphShape.tagged,
      description:
          "The framework's own bean: a post-processor, a registry (with "
          'framework)',
    ),
  };

  /// A bean a condition left out, grey.
  static const skipped = DebugGraphKind(
    'skipped',
    'left out',
    DebugGraphShape.rounded,
    description: 'A bean a condition left out, grey (with skipped, in All)',
  );

  static const _edgeKinds = {
    DebugBeanEdgeKind.direct: 'injects',
    DebugBeanEdgeKind.collection: 'injects (all of a type)',
    DebugBeanEdgeKind.lazy: 'injects @Lazy',
    DebugBeanEdgeKind.provider: 'injects a provider',
    DebugBeanEdgeKind.dependsOn: '@DependsOn',
  };

  /// The kind of a node of [role].
  static DebugGraphKind kindOf(DebugBeanRole role) =>
      _kinds[role] ?? _kinds[DebugBeanRole.component]!;

  final _ownChanges = _Changes();
  late final Listenable _changes = Listenable.merge([
    graph,
    _ownChanges,
    ?routes,
  ]);
  // With the route grouping, while started: the node of each bean of a
  // route scope at the last collect, so a bean destroyed with its route
  // flashes where it was.
  final _lastNodes = <String, DebugGraphNode>{};
  Timer? _flashEnd;
  final _litAt = <String, DateTime>{};
  final _wakes = <VoidCallback>[];
  var _users = 0;
  var _seen = 0;
  var _showSkipped = false;

  @override
  String get id => 'beans';

  @override
  String get title => 'Beans';

  @override
  int get order => 10;

  @override
  Color colorOf(DebugStyle style) => style.graphLayer(id, orElse: style.good);

  @override
  List<DebugGraphKind> get kinds => [..._kinds.values, skipped];

  @override
  String get flashMeaning => 'an instance was created or destroyed';

  /// Whether the beans a condition left out are shown (in "All").
  bool get showSkipped => _showSkipped;

  set showSkipped(bool show) {
    if (show != _showSkipped) {
      _showSkipped = show;
      _ownChanges.changed();
    }
  }

  @override
  List<DebugGraphOption> get options => [
    DebugGraphOption(
      label: 'framework',
      value: graph.includeFramework,
      onChanged: (value) => graph.includeFramework = value,
    ),
    DebugGraphOption(
      label: 'skipped',
      value: _showSkipped,
      onChanged: (value) => showSkipped = value,
    ),
  ];

  @override
  List<DebugGraphChoice> get choices => routes?.choicesOf(this) ?? const [];

  @override
  Listenable get changes => _changes;

  /// Whether a view follows the beans now.
  bool get started => _users > 0;

  @override
  void Function() start() {
    final stopRoutes = routes?.start(this);
    if (_users++ == 0) {
      _seen = graph.events.lastOrNull?.sequence ?? 0;
      graph
        ..addListener(_heard)
        ..start();
    }
    var stopped = false;
    return () {
      if (stopped) {
        return;
      }
      stopped = true;
      stopRoutes?.call();
      if (--_users == 0) {
        graph
          ..removeListener(_heard)
          ..stop();
        _lastNodes.clear();
        _flashEnd?.cancel();
        _flashEnd = null;
      }
    };
  }

  // The beans created and destroyed since the last time: they glow.
  void _heard() {
    final events = graph.eventsAfter(_seen);
    if (events.isEmpty) {
      return;
    }
    for (final event in events) {
      _litAt[event.beanName] = event.at;
    }
    _seen = events.last.sequence;
    for (final wake in [..._wakes]) {
      wake();
    }
  }

  @override
  void Function() onActivity(VoidCallback wake) {
    _wakes.add(wake);
    return () => _wakes.remove(wake);
  }

  @override
  double glowOf(DebugGraphNode node) {
    final at = switch (node.source) {
      final DebugBean bean => _litAt[bean.name],
      _ => null,
    };
    if (at == null) {
      return 0;
    }
    final elapsed = DateTime.now().difference(at);
    return (1 - elapsed.inMicroseconds / flash.inMicroseconds).clamp(0, 1);
  }

  @override
  bool isLive(DebugGraphNode node, Duration window) {
    final at = switch (node.source) {
      final DebugBean bean => _litAt[bean.name],
      _ => null,
    };
    return at != null && DateTime.now().difference(at) <= window;
  }

  @override
  DebugGraphPart collect(DebugGraphScope scope) {
    final snapshot = graph.snapshot;
    final onScreen = scope == DebugGraphScope.onScreen;
    // The beans each Spring widget (on the screen) injects, and by whom.
    final injectedBy = <String, List<Element>>{};
    for (final widget in springWidgets()) {
      if (onScreen && !shows(widget.element)) {
        continue;
      }
      final node = snapshot.widgetOf(widget.beansType);
      if (node == null) {
        continue;
      }
      for (final edge in snapshot.dependenciesOf(node.name)) {
        (injectedBy[edge.to] ??= []).add(widget.element);
      }
    }
    final kept = onScreen ? snapshot.closureOf(injectedBy.keys) : null;
    final byRoute = routes?.byRoute ?? false;
    final lanes = byRoute ? routes!.beanLanes() : null;
    // The beans of a closed route that flash as they are destroyed: where
    // they were, kept while they glow.
    final flashing = <String, DebugGraphNode>{};
    if (lanes != null) {
      for (final MapEntry(key: name, value: node) in _lastNodes.entries) {
        final bean = snapshot.bean(name);
        if (bean != null &&
            lanes.ofBean(name, bean.scope) == null &&
            glowOf(node) > 0) {
          flashing[name] = node;
        }
      }
    }
    bool shown(DebugBean? bean) =>
        bean != null &&
        bean.role != DebugBeanRole.widget &&
        (kept == null ||
            kept.contains(bean.name) ||
            flashing.containsKey(bean.name));
    DebugGraphNode nodeOf(DebugBean bean) {
      if (flashing[bean.name] case final node?) {
        return node;
      }
      final widget = onScreen ? injectedBy[bean.name]?.first : null;
      final visible = onScreen && injectedBy.containsKey(bean.name)
          ? true
          : null;
      if (lanes == null) {
        return DebugGraphNode(
          id: idOf(bean.name),
          layer: id,
          kind: kindOf(bean.role).id,
          label: bean.name,
          group: bean.module,
          source: bean,
          widget: widget,
          onScreen: visible,
        );
      }
      final lane = lanes.ofBean(bean.name, bean.scope);
      return DebugGraphNode(
        id: idOf(bean.name),
        layer: id,
        kind: kindOf(bean.role).id,
        label: bean.name,
        group: lane?.key,
        groupTitle: lane?.title,
        groupOrder: lane?.order,
        groupRole: lane?.role,
        source: bean,
        widget: widget,
        onScreen: visible,
      );
    }

    final nodes = <DebugGraphNode>[
      for (final bean in snapshot.beans)
        if (shown(bean)) nodeOf(bean),
      if (!onScreen && _showSkipped)
        for (final left in snapshot.skipped)
          DebugGraphNode(
            id: skippedIdOf(left.source),
            layer: id,
            kind: skipped.id,
            label: _shortName(left.source),
            group: left.module,
            dimmed: true,
            source: left,
          ),
    ];
    final edges = <DebugGraphEdge>[
      for (final edge in snapshot.edges)
        if (_edgeKinds[edge.kind] case final kind?)
          if (shown(snapshot.bean(edge.from)) && shown(snapshot.bean(edge.to)))
            DebugGraphEdge(
              idOf(edge.to),
              idOf(edge.from),
              kind: kind,
              dashed: edge.deferred || edge.kind == DebugBeanEdgeKind.dependsOn,
            ),
      for (final MapEntry(key: name, value: elements) in injectedBy.entries)
        if (shown(snapshot.bean(name)))
          for (final element in elements)
            DebugGraphEdge(
              idOf(name),
              DebugGraphWidgets.idOf(element),
              kind: 'injected into',
            ),
    ];
    if (lanes != null && started) {
      _remember(nodes, lanes, flashing.isNotEmpty);
    }
    return DebugGraphPart(nodes, edges);
  }

  // Keeps the nodes of the beans in a route for the next collect, and
  // collects again once the beans of a closed route stop flashing.
  void _remember(
    List<DebugGraphNode> nodes,
    DebugGraphBeanLanes lanes,
    bool flashing,
  ) {
    _lastNodes.removeWhere((name, node) => glowOf(node) <= 0);
    for (final node in nodes) {
      final role = node.groupRole;
      if (node.source case final DebugBean bean
          when role != null &&
              role != DebugGraphGroupRole.app &&
              !node.dimmed) {
        _lastNodes[bean.name] = node;
      }
    }
    if (flashing) {
      _flashEnd?.cancel();
      _flashEnd = Timer(flash, _ownChanges.changed);
    }
  }

  static String _shortName(String source) =>
      source.contains('#') ? source.substring(source.indexOf('#') + 1) : source;

  @override
  List<DebugGraphDetail> detailsOf(DebugGraphNode node) =>
      switch (node.source) {
        final DebugBean bean => _detailsOfBean(bean, graph.snapshot),
        final DebugSkippedBean left => [
          DebugGraphDetail('left out by', left.failed.join(', ')),
          DebugGraphDetail('module', left.module),
          DebugGraphDetail('source', left.source),
          if (left.conditions.any((condition) => condition.matched))
            DebugGraphDetail(
              'matched',
              left.conditions.where((c) => c.matched).join(', '),
            ),
        ],
        _ => node.details,
      };

  static List<DebugGraphDetail> _detailsOfBean(
    DebugBean bean,
    DebugBeanGraphSnapshot snapshot,
  ) {
    final dependencies = snapshot.dependenciesOf(bean.name);
    final dependents = snapshot.dependentsOf(bean.name);
    final widgets = dependents
        .where((edge) => edge.kind == DebugBeanEdgeKind.widget)
        .length;
    return [
      DebugGraphDetail('type', bean.type),
      DebugGraphDetail('role', bean.role.name),
      DebugGraphDetail('module', bean.module),
      DebugGraphDetail(
        'scope',
        bean.lazy ? '${bean.scope} · lazy' : bean.scope,
      ),
      DebugGraphDetail('state', _stateOf(bean)),
      DebugGraphDetail(
        'depends on',
        '${dependencies.length} '
            '(${dependencies.where((edge) => edge.deferred).length} deferred)',
        links: [
          for (final edge in dependencies)
            _linkTo(edge.to, edge.kind, snapshot),
        ],
      ),
      DebugGraphDetail(
        'used by',
        '${dependents.length - widgets} beans · $widgets widgets',
        links: [
          for (final edge in dependents)
            edge.kind == DebugBeanEdgeKind.widget
                ? DebugGraphDetailLink(
                    _shortSource(edge.from),
                    note: 'widget',
                    hidden: 'widget',
                    tooltip: edge.from,
                  )
                : _linkTo(edge.from, edge.kind, snapshot),
        ],
      ),
      if (bean.advisors.isNotEmpty)
        DebugGraphDetail('advice', bean.advisors.join(', ')),
      if (bean.advisedMethods.isNotEmpty)
        DebugGraphDetail('advised', bean.advisedMethods.join(', ')),
      if (bean.conditions.isNotEmpty)
        DebugGraphDetail('conditions', bean.conditions.join(', ')),
      if (bean.creationOrder case final order?)
        DebugGraphDetail(
          'created',
          [
            '#${order + 1}',
            if (bean.createdAt case final at?) 'at ${_ms(at)}',
            if (bean.creationTime case final took?) 'took ${_ms(took)}',
          ].join(' · '),
        ),
      if (bean.eventListeners.isNotEmpty)
        DebugGraphDetail('listens', bean.eventListeners.join(', ')),
      if (bean.publishesEvents) const DebugGraphDetail('publishes', 'events'),
      if (bean.annotations.isNotEmpty)
        DebugGraphDetail('annotations', bean.annotations.join(', ')),
      if (bean.source case final source?)
        DebugGraphDetail('source', _shortSource(source, keepFile: true)),
    ];
  }

  // A row naming bean [name], reached by an edge of [kind]: its node, the
  // way it is injected, and why it may not be on the graph.
  static DebugGraphDetailLink _linkTo(
    String name,
    DebugBeanEdgeKind kind,
    DebugBeanGraphSnapshot snapshot,
  ) {
    final bean = snapshot.bean(name);
    return DebugGraphDetailLink(
      name,
      target: '$prefix$name',
      note: switch (kind) {
        DebugBeanEdgeKind.direct || DebugBeanEdgeKind.widget => null,
        DebugBeanEdgeKind.collection => 'in a collection',
        DebugBeanEdgeKind.lazy => '@Lazy',
        DebugBeanEdgeKind.provider => 'provider',
        DebugBeanEdgeKind.dependsOn => '@DependsOn',
      },
      hidden: bean != null && !bean.application ? 'framework' : null,
    );
  }

  // `package:app/src/a/b.dart#Name` as `Name`, or with [keepFile]
  // `b.dart#Name`; a `_NameState` of a widget as `Name`.
  static String _shortSource(String source, {bool keepFile = false}) {
    final hash = source.lastIndexOf('#');
    final name = hash < 0 ? null : source.substring(hash + 1);
    final path = hash < 0 ? source : source.substring(0, hash);
    final file = path.substring(path.lastIndexOf('/') + 1);
    if (keepFile) {
      return name == null ? file : '$file#$name';
    }
    if (name == null) {
      return file;
    }
    if (name.startsWith('_') && name.endsWith('State') && name.length > 6) {
      return name.substring(1, name.length - 5);
    }
    return name;
  }

  static String _stateOf(DebugBean bean) => switch (bean) {
    DebugBean(scope: 'singleton', created: true) => 'created',
    DebugBean(scope: 'singleton', lazy: true) => 'not created yet (lazy)',
    DebugBean(scope: 'singleton') => 'not created',
    DebugBean(:final instances) => '$instances live',
  };

  static String _ms(Duration duration) =>
      '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';

  /// Frees its notifier (the bean, when it is destroyed).
  void dispose() {
    _flashEnd?.cancel();
    _ownChanges.dispose();
  }
}

final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}
