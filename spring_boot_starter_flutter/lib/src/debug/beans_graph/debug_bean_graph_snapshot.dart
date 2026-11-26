import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_edge.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_module.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_skipped_bean.dart';

/// The beans of the application at one moment, as the [DebugBeanGraph]
/// read them: the nodes ([beans], widgets among them), their [modules],
/// the [edges] "depends on", and the beans [skipped] by a condition.
///
/// Immutable: the graph makes a new one after a change.
final class DebugBeanGraphSnapshot {
  /// A snapshot of these values.
  DebugBeanGraphSnapshot({
    required List<DebugBean> beans,
    required List<DebugBeanModule> modules,
    required List<DebugBeanEdge> edges,
    required List<DebugSkippedBean> skipped,
    required this.includesFramework,
  }) : beans = List.unmodifiable(beans),
       modules = List.unmodifiable(modules),
       edges = List.unmodifiable(edges),
       skipped = List.unmodifiable(skipped);

  /// An empty snapshot.
  static final empty = DebugBeanGraphSnapshot(
    beans: const [],
    modules: const [],
    edges: const [],
    skipped: const [],
    includesFramework: false,
  );

  /// The beans, and the Spring widgets that inject beans
  /// ([DebugBean.role] `widget`), in definition order.
  final List<DebugBean> beans;

  /// The modules of [beans].
  final List<DebugBeanModule> modules;

  /// "depends on" between [beans].
  final List<DebugBeanEdge> edges;

  /// The beans left out by a condition.
  final List<DebugSkippedBean> skipped;

  /// Whether the framework's beans are in, or only the application's.
  final bool includesFramework;

  late final _byName = {for (final bean in beans) bean.name: bean};

  late final _byBeansType = <Type, DebugBean>{
    for (final bean in beans)
      if (bean.beansType != null) bean.beansType!: bean,
  };

  late final _from = _index((edge) => edge.from);

  late final _to = _index((edge) => edge.to);

  Map<String, List<DebugBeanEdge>> _index(
    String Function(DebugBeanEdge edge) key,
  ) {
    final index = <String, List<DebugBeanEdge>>{};
    for (final edge in edges) {
      (index[key(edge)] ??= []).add(edge);
    }
    return index;
  }

  /// The bean (or widget) named [name], if it is in.
  DebugBean? bean(String name) => _byName[name];

  /// The widget node of the Spring widgets whose beans are a record of
  /// [beansType] (a widget's `beansType`).
  DebugBean? widgetOf(Type beansType) => _byBeansType[beansType];

  /// The edges from [name]: what it depends on.
  List<DebugBeanEdge> dependenciesOf(String name) => _from[name] ?? const [];

  /// The edges to [name]: what depends on it.
  List<DebugBeanEdge> dependentsOf(String name) => _to[name] ?? const [];

  /// [roots] and every bean they depend on, directly or through others,
  /// following the edges of [kinds] (all by default): the beans behind
  /// the widgets on screen, from the widgets' names.
  Set<String> closureOf(
    Iterable<String> roots, {
    Set<DebugBeanEdgeKind> kinds = const {...DebugBeanEdgeKind.values},
  }) {
    final reached = <String>{};
    final pending = [...roots];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!reached.add(name)) {
        continue;
      }
      for (final edge in dependenciesOf(name)) {
        if (kinds.contains(edge.kind)) {
          pending.add(edge.to);
        }
      }
    }
    return reached;
  }
}
