import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_screen.dart';

/// What a view of the application graph shows: the scope, the layers
/// switched on, the groups chosen, "live only", the lanes collapsed and
/// the repeats opened. Each change makes a new one.
@immutable
final class DebugGraphSettings {
  /// Settings of these values.
  const DebugGraphSettings({
    this.scope = DebugGraphScope.onScreen,
    this.hiddenLayers = const {},
    this.groups = const {},
    this.liveOnly = false,
    this.liveWindow = const Duration(seconds: 5),
    this.collapsed = const {},
    this.opened = const {},
  });

  /// Which nodes.
  final DebugGraphScope scope;

  /// The ids of the layers switched off.
  final Set<String> hiddenLayers;

  /// The lanes shown, each with what touches it ([DebugGraphLane.key]),
  /// chosen in the `Groups` list; empty: every lane.
  final Set<String> groups;

  /// Whether the nodes that did not change, run or build within
  /// [liveWindow] are hidden.
  final bool liveOnly;

  /// What "live only" counts as live.
  final Duration liveWindow;

  /// The lanes folded into one plate each, by [DebugGraphLane.key].
  final Set<String> collapsed;

  /// The repeats opened, by their fold's key.
  final Set<String> opened;

  /// These settings with what is given changed.
  DebugGraphSettings copyWith({
    DebugGraphScope? scope,
    Set<String>? hiddenLayers,
    Set<String>? groups,
    bool? liveOnly,
    Set<String>? collapsed,
    Set<String>? opened,
  }) => DebugGraphSettings(
    scope: scope ?? this.scope,
    hiddenLayers: hiddenLayers ?? this.hiddenLayers,
    groups: groups ?? this.groups,
    liveOnly: liveOnly ?? this.liveOnly,
    liveWindow: liveWindow,
    collapsed: collapsed ?? this.collapsed,
    opened: opened ?? this.opened,
  );

  /// With [value] in [set] taken out, or put in when it was not.
  static Set<String> toggled(Set<String> set, String value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};
}

/// The nodes and edges of the layers shown, before filters and folds:
/// what [DebugGraphFilter]s choose from.
final class DebugGraphNodes {
  /// [nodes] (unique ids) and the [edges] between them by index.
  DebugGraphNodes(
    this.nodes,
    this.edges,
    this.layers,
    this.settings, {
    this.aliases = const {},
  });

  /// Every node, the layers' in their order.
  final List<DebugGraphNode> nodes;

  /// Every edge whose ends are both in [nodes]: indexes and the edge.
  final List<(int, int, DebugGraphEdge)> edges;

  /// The layers by id.
  final Map<String, DebugGraphLayer> layers;

  /// What the view shows.
  final DebugGraphSettings settings;

  /// The nodes merged into a node of another layer ([DebugGraphNode.sameAs]),
  /// by the index of the node they were merged into.
  final Map<int, List<DebugGraphNode>> aliases;

  late final List<List<int>> _out = _adjacency(forward: true);
  late final List<List<int>> _in = _adjacency(forward: false);

  List<List<int>> _adjacency({required bool forward}) {
    final lists = List<List<int>>.generate(nodes.length, (_) => []);
    for (final (from, to, _) in edges) {
      if (forward) {
        lists[from].add(to);
      } else {
        lists[to].add(from);
      }
    }
    return lists;
  }

  /// What comes after [index]: the nodes its edges point at.
  List<int> after(int index) => _out[index];

  /// What comes before [index]: the nodes whose edges point at it.
  List<int> before(int index) => _in[index];

  /// [from] and every node reachable from them, following edges forward
  /// ([forward]) or back, through the nodes [through] lets pass.
  Set<int> reach(
    Iterable<int> from, {
    required bool forward,
    bool Function(int index)? through,
  }) {
    final seen = <int>{...from};
    final queue = [...seen];
    for (var i = 0; i < queue.length; i++) {
      for (final next in forward ? after(queue[i]) : before(queue[i])) {
        if ((through == null || through(next)) && seen.add(next)) {
          queue.add(next);
        }
      }
    }
    return seen;
  }
}

/// A step of the application graph that keeps some nodes: the scope, the
/// group, "live only". The view runs them in turn, each on what the one
/// before kept; an application or a layer adds its own by giving the view
/// its list.
abstract interface class DebugGraphFilter {
  /// Of [kept] (indexes into [graph]'s nodes), the nodes to keep.
  Set<int> keep(DebugGraphNodes graph, Set<int> kept);
}

/// The "On screen" scope: the nodes of widgets on the screen
/// ([DebugGraphScreen.shows]), everything before them, and the nodes of
/// no widget that the same sources reach without feeding a widget (an
/// effect that listens to them), with what they read. A graph with no
/// node of a widget is kept whole.
final class DebugGraphScopeFilter implements DebugGraphFilter {
  /// The filter, telling whether a widget shows by [shows].
  const DebugGraphScopeFilter({this.shows = DebugGraphScreen.shows});

  /// Whether a widget is on the screen.
  final bool Function(BuildContext widget) shows;

  @override
  Set<int> keep(DebugGraphNodes graph, Set<int> kept) {
    if (graph.settings.scope == DebugGraphScope.all) {
      return kept;
    }
    final nodes = graph.nodes;
    // The lanes of the routes under the current screen are not on it.
    kept = {
      for (final i in kept)
        if (nodes[i].groupRole != DebugGraphGroupRole.below) i,
    };
    bool screenBound(int i) => nodes[i].widget != null;
    final visible = <int>{};
    var anyWidget = false;
    for (final i in kept) {
      if (nodes[i].widget case final widget?) {
        anyWidget = true;
        if (nodes[i].onScreen ?? shows(widget)) {
          visible.add(i);
        }
      }
    }
    if (!anyWidget) {
      return kept;
    }
    bool passes(int i) => kept.contains(i) && !screenBound(i);
    final upstream = graph.reach(visible, forward: false, through: passes);
    // The nodes of no widget that lead to a widget are there for it.
    final feeders = graph.reach(
      [
        for (final i in kept)
          if (screenBound(i)) i,
      ],
      forward: false,
      through: passes,
    );
    final listeners = {
      for (final i in graph.reach(upstream, forward: true, through: passes))
        if (!screenBound(i) && !feeders.contains(i)) i,
    };
    return {
      ...upstream,
      ...graph.reach(listeners, forward: false, through: passes),
    }..retainWhere(kept.contains);
  }
}

/// The group filter: the lanes chosen ([DebugGraphSettings.groups]), with
/// what their nodes come from and what comes from them; none chosen,
/// every lane. A chosen lane no node has now (its route closed) is left
/// out of the choice, so it never filters the graph down to nothing.
final class DebugGraphGroupFilter implements DebugGraphFilter {
  /// The filter.
  const DebugGraphGroupFilter();

  @override
  Set<int> keep(DebugGraphNodes graph, Set<int> kept) {
    final chosen = graph.settings.groups;
    if (chosen.isEmpty) {
      return kept;
    }
    final groups = {
      for (final node in graph.nodes)
        if (chosen.contains(DebugGraphLane.keyOf(node)))
          DebugGraphLane.keyOf(node),
    };
    if (groups.isEmpty) {
      return kept;
    }
    final own = {
      for (final i in kept)
        if (groups.contains(DebugGraphLane.keyOf(graph.nodes[i]))) i,
    };
    return {
      ...own,
      for (final i in own) ...graph.after(i),
      for (final i in own) ...graph.before(i),
    }..retainWhere(kept.contains);
  }
}

/// "Live only": the nodes their layer saw change, run or build within
/// [DebugGraphSettings.liveWindow] ([DebugGraphLayer.isLive]); the others
/// are hidden, not dimmed.
final class DebugGraphLiveFilter implements DebugGraphFilter {
  /// The filter.
  const DebugGraphLiveFilter();

  @override
  Set<int> keep(DebugGraphNodes graph, Set<int> kept) {
    if (!graph.settings.liveOnly) {
      return kept;
    }
    final window = graph.settings.liveWindow;
    return {
      for (final i in kept)
        if (graph.layers[graph.nodes[i].layer]?.isLive(
              graph.nodes[i],
              window,
            ) ??
            true)
          i,
    };
  }
}

/// Where a node folds: the plate of several nodes, what it says, and how a
/// tap opens it and a chip folds it back.
@immutable
final class DebugGraphFoldGroup {
  /// The fold [key], called [label], [folded] or opened.
  const DebugGraphFoldGroup({
    required this.key,
    required this.label,
    required this.folded,
    required this.open,
    required this.close,
    required this.closeLabel,
  });

  /// Its key: the nodes of one key are one plate while [folded].
  final String key;

  /// What the plate says: `PlayerReviews ×10`.
  final String label;

  /// Whether its nodes are one plate now.
  final bool folded;

  /// The settings with it opened.
  final DebugGraphSettings Function(DebugGraphSettings settings) open;

  /// The settings with it folded again.
  final DebugGraphSettings Function(DebugGraphSettings settings) close;

  /// What the chip that folds it back says.
  final String closeLabel;
}

/// A step of the application graph that folds nodes into one plate: a
/// collapsed lane, repeats. The view asks them in turn; the first that
/// gives a node a fold decides it.
abstract interface class DebugGraphFold {
  /// The fold of node [index] of [graph] among [kept], or `null`.
  DebugGraphFoldGroup? foldOf(DebugGraphNodes graph, Set<int> kept, int index);
}

/// A collapsed lane: every node of a lane of
/// [DebugGraphSettings.collapsed] in one plate, `Basket (6)`.
final class DebugGraphLaneFold implements DebugGraphFold {
  /// The fold.
  const DebugGraphLaneFold();

  @override
  DebugGraphFoldGroup? foldOf(
    DebugGraphNodes graph,
    Set<int> kept,
    int index,
  ) {
    final node = graph.nodes[index];
    final lane = DebugGraphLane.keyOf(node);
    if (node.group == null || !graph.settings.collapsed.contains(lane)) {
      return null;
    }
    final count = _counts(graph, kept)[lane] ?? 0;
    return DebugGraphFoldGroup(
      key: 'lane\u0000$lane',
      label: '${node.laneTitle} ($count)',
      folded: true,
      open: (settings) => settings.copyWith(
        collapsed: DebugGraphSettings.toggled(settings.collapsed, lane),
      ),
      close: (settings) => settings.copyWith(
        collapsed: DebugGraphSettings.toggled(settings.collapsed, lane),
      ),
      closeLabel: 'collapse ${node.laneTitle}',
    );
  }
}

/// A collapsed branch: a node of [DebugGraphSettings.collapsed] (by
/// [keyOf]) and every node of its layer after it along the edges, in one
/// plate, `SiteHeader ▸ 12`, until it is tapped open. For a layer whose
/// edges go from a parent to its children (the widgets layer).
final class DebugGraphBranchFold implements DebugGraphFold {
  /// The fold.
  const DebugGraphBranchFold();

  /// The key of the branch of node [id] in [DebugGraphSettings.collapsed].
  static String keyOf(String id) => 'branch\u0000$id';

  static final Expando<Map<int, int>> _heads = Expando('collapsed branches');
  static final Expando<Map<int, int>> _counts = Expando('branch sizes');

  // For each node folded into a collapsed branch, the index of its head:
  // worked out once for a graph.
  static Map<int, int> _headsOf(DebugGraphNodes graph, Set<int> kept) =>
      _heads[graph] ??= () {
        final heads = <int, int>{};
        final collapsed = graph.settings.collapsed;
        for (final i in kept) {
          if (!collapsed.contains(keyOf(graph.nodes[i].id))) {
            continue;
          }
          final layer = graph.nodes[i].layer;
          for (final j in graph.reach(
            [i],
            forward: true,
            through: (j) => kept.contains(j) && graph.nodes[j].layer == layer,
          )) {
            heads.putIfAbsent(j, () => i);
          }
        }
        return heads;
      }();

  @override
  DebugGraphFoldGroup? foldOf(
    DebugGraphNodes graph,
    Set<int> kept,
    int index,
  ) {
    final heads = _headsOf(graph, kept);
    final head = heads[index];
    if (head == null) {
      return null;
    }
    final node = graph.nodes[head];
    final key = keyOf(node.id);
    final count = _counts[heads] ??= () {
      final counts = <int, int>{};
      for (final h in heads.values) {
        counts[h] = (counts[h] ?? 0) + 1;
      }
      return counts;
    }();
    return DebugGraphFoldGroup(
      key: key,
      label: '${node.label} ▸ ${count[head]}',
      folded: true,
      open: (settings) => settings.copyWith(
        collapsed: DebugGraphSettings.toggled(settings.collapsed, key),
      ),
      close: (settings) => settings.copyWith(
        collapsed: DebugGraphSettings.toggled(settings.collapsed, key),
      ),
      closeLabel: 'collapse branch',
    );
  }
}

/// Repeats: the nodes of one lane (and one [DebugGraphNode.repeatScope])
/// with one [DebugGraphNode.repeatKey], two or more, in one plate
/// (`PlayerReviews ×10`) until it is tapped open.
final class DebugGraphRepeatFold implements DebugGraphFold {
  /// The fold.
  const DebugGraphRepeatFold();

  @override
  DebugGraphFoldGroup? foldOf(
    DebugGraphNodes graph,
    Set<int> kept,
    int index,
  ) {
    final node = graph.nodes[index];
    final repeat = node.repeatKey;
    if (repeat == null) {
      return null;
    }
    final lane = _repeatLaneOf(node);
    final count = _counts(graph, kept)['$lane\u0000$repeat'] ?? 0;
    if (count < 2) {
      return null;
    }
    final key = 'repeat\u0000$lane\u0000$repeat';
    return DebugGraphFoldGroup(
      key: key,
      label: '$repeat ×$count',
      folded: !graph.settings.opened.contains(key),
      open: (settings) => settings.copyWith(
        opened: DebugGraphSettings.toggled(settings.opened, key),
      ),
      close: (settings) => settings.copyWith(
        opened: DebugGraphSettings.toggled(settings.opened, key),
      ),
      closeLabel: 'fold $repeat ×$count',
    );
  }
}

final Expando<Map<String, int>> _countsOfGraph = Expando('fold counts');

// The lane of [node] narrowed to its repeat scope, for its repeats.
String _repeatLaneOf(DebugGraphNode node) => switch (node.repeatScope) {
  final scope? => '${DebugGraphLane.keyOf(node)}\u0000$scope',
  null => DebugGraphLane.keyOf(node),
};

// How many nodes of [kept] each lane has, and each lane's repeats (by
// `lane\u0000repeatKey`): counted once for a graph.
Map<String, int> _counts(DebugGraphNodes graph, Set<int> kept) =>
    _countsOfGraph[graph] ??= () {
      final counts = <String, int>{};
      for (final i in kept) {
        final node = graph.nodes[i];
        final lane = DebugGraphLane.keyOf(node);
        counts[lane] = (counts[lane] ?? 0) + 1;
        if (node.repeatKey case final repeat?) {
          final key = '${_repeatLaneOf(node)}\u0000$repeat';
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
      return counts;
    }();

/// A lane of the application graph: the nodes of one group of one layer,
/// or of one group of the graph's own ([DebugGraphNode.groupOrder]) from
/// every layer, a band across every column with its title at the left.
@immutable
final class DebugGraphLane {
  /// The lane [key] of [layer], called [title].
  const DebugGraphLane(
    this.key,
    this.layer,
    this.title, {
    this.group,
    this.order,
    this.role,
  });

  /// The lane of [node]: its group, of its layer unless the group is the
  /// graph's ([DebugGraphNode.groupOrder]).
  static String keyOf(DebugGraphNode node) =>
      node.group != null && node.groupOrder != null
      ? '\u0000${node.group}'
      : '${node.layer}\u0000${node.group ?? ''}';

  /// Its key: [keyOf] of its nodes.
  final String key;

  /// The layer; of a lane of the graph's own, a layer whose groups are
  /// lanes among those of its nodes.
  final String layer;

  /// What its left says; empty for the nodes of no group.
  final String title;

  /// The group; `null` for the nodes of none.
  final String? group;

  /// Its place among the lanes of the graph's own
  /// ([DebugGraphNode.groupOrder]); `null` for a layer's lane.
  final int? order;

  /// What it stands for ([DebugGraphNode.groupRole]); `null` for a layer's
  /// lane.
  final DebugGraphGroupRole? role;

  /// Whether it is the graph's own, shared by the layers.
  bool get shared => order != null;
}

/// A plate of the application graph: one node, or the nodes folded into
/// it.
@immutable
final class DebugGraphItem {
  /// The plate of [nodes].
  const DebugGraphItem({
    required this.key,
    required this.nodes,
    required this.label,
    required this.lane,
    this.fold,
    this.aliases = const [],
  });

  /// The node's id, or the fold's key.
  final String key;

  /// What it stands for.
  final List<DebugGraphNode> nodes;

  /// What it says.
  final String label;

  /// The index of its lane.
  final int lane;

  /// The fold it is (folded) or belongs to (opened).
  final DebugGraphFoldGroup? fold;

  /// The nodes of other layers merged into it ([DebugGraphNode.sameAs]):
  /// their glow lights it, their details are told with its own.
  final List<DebugGraphNode> aliases;

  /// Whether it stands for several nodes.
  bool get folded => fold?.folded ?? false;

  /// The first of its nodes.
  DebugGraphNode get node => nodes.first;

  /// Its layer's id.
  String get layer => node.layer;

  /// Its kind's id.
  String get kind => node.kind;

  /// Whether all of its nodes only read.
  bool get sink => nodes.every((node) => node.sink);
}

/// An edge between two plates: the edges of their nodes, once.
@immutable
final class DebugGraphLink {
  /// The link from plate [from] to plate [to].
  const DebugGraphLink(this.from, this.to, {this.dashed = false});

  /// The plate it starts at.
  final int from;

  /// The plate its arrow points at.
  final int to;

  /// Whether every edge of it is dashed.
  final bool dashed;
}

/// The application graph as a view shows it: the layers' nodes filtered
/// and folded into plates, the links between them, the lanes. Made by
/// [DebugGraphAssembler.assemble] whenever a layer or the settings change;
/// laid out again only when its [signature] changes.
final class DebugGraph {
  DebugGraph._(this.items, this.links, this.lanes, this.layers, this.all);

  /// The plates, lane by lane.
  final List<DebugGraphItem> items;

  /// The links between them.
  final List<DebugGraphLink> links;

  /// The lanes, in order: the graph's own by their
  /// [DebugGraphLane.order], then the layers' in the layers' order, each
  /// layer's in the order its nodes first name them, the nodes of no group
  /// last.
  final List<DebugGraphLane> lanes;

  /// The layers shown, in order.
  final List<DebugGraphLayer> layers;

  /// Every lane of the layers shown before the filters, for the group
  /// filter's choices.
  final List<DebugGraphLane> all;

  /// A number that changes when the plates or the links do.
  late final int signature = Object.hash(
    Object.hashAll([for (final item in items) item.key]),
    Object.hashAll([
      for (final link in links) Object.hash(link.from, link.to, link.dashed),
    ]),
    Object.hashAll([for (final item in items) item.label]),
    Object.hashAll([
      for (final item in items)
        for (final node in item.nodes)
          if (node.dimmed) node.id,
    ]),
  );

  /// The plate [key] names, or `null`.
  int? indexOf(String key) {
    for (var i = 0; i < items.length; i++) {
      if (items[i].key == key) {
        return i;
      }
    }
    return null;
  }

  /// Plate [index] and every plate before it and after it along the
  /// links: what a tap on it highlights.
  Set<int> chainOf(int index) {
    final out = List<List<int>>.generate(items.length, (_) => []);
    final into = List<List<int>>.generate(items.length, (_) => []);
    for (final link in links) {
      out[link.from].add(link.to);
      into[link.to].add(link.from);
    }
    Set<int> walk(List<List<int>> next) {
      final seen = {index};
      final queue = [index];
      for (var i = 0; i < queue.length; i++) {
        for (final other in next[queue[i]]) {
          if (seen.add(other)) {
            queue.add(other);
          }
        }
      }
      return seen;
    }

    return {...walk(out), ...walk(into)};
  }
}

/// Makes the [DebugGraph] a view shows from its layers: their parts for
/// the scope, merged (an edge kept only when both its ends are), the
/// [filters] in turn, then the [folds].
final class DebugGraphAssembler {
  /// The assembler of these steps; the built-in ones by default.
  const DebugGraphAssembler({
    this.filters = defaultFilters,
    this.folds = defaultFolds,
  });

  /// The scope, the group, "live only".
  static const List<DebugGraphFilter> defaultFilters = [
    DebugGraphScopeFilter(),
    DebugGraphGroupFilter(),
    DebugGraphLiveFilter(),
  ];

  /// A collapsed lane first, then a collapsed branch, then repeats.
  static const List<DebugGraphFold> defaultFolds = [
    DebugGraphLaneFold(),
    DebugGraphBranchFold(),
    DebugGraphRepeatFold(),
  ];

  /// The steps that keep nodes.
  final List<DebugGraphFilter> filters;

  /// The steps that fold nodes.
  final List<DebugGraphFold> folds;

  /// The graph of [parts] (each layer's), with [settings].
  DebugGraph assemble(
    List<(DebugGraphLayer, DebugGraphPart)> parts,
    DebugGraphSettings settings,
  ) {
    final nodes = <DebugGraphNode>[];
    final indexOf = <String, int>{};
    final layers = <String, DebugGraphLayer>{};
    final ids = {
      for (final (_, part) in parts)
        for (final node in part.nodes)
          if (node.sameAs == null) node.id,
    };
    final merged = <DebugGraphNode>[];
    for (final (layer, part) in parts) {
      layers[layer.id] = layer;
      for (final node in part.nodes) {
        if (node.sameAs case final same? when ids.contains(same)) {
          merged.add(node);
          continue;
        }
        if (!indexOf.containsKey(node.id)) {
          indexOf[node.id] = nodes.length;
          nodes.add(node);
        }
      }
    }
    // A node merged into another layer's: its edges are that node's.
    final aliases = <int, List<DebugGraphNode>>{};
    for (final node in merged) {
      final into = indexOf[node.sameAs]!;
      indexOf[node.id] = into;
      (aliases[into] ??= []).add(node);
    }
    final edges = <(int, int, DebugGraphEdge)>[];
    final seen = <int>{};
    for (final (_, part) in parts) {
      for (final edge in part.edges) {
        final from = indexOf[edge.from];
        final to = indexOf[edge.to];
        if (from != null &&
            to != null &&
            from != to &&
            seen.add(from * nodes.length + to)) {
          edges.add((from, to, edge));
        }
      }
    }
    final graph = DebugGraphNodes(
      nodes,
      edges,
      layers,
      settings,
      aliases: aliases,
    );

    // Every lane, for the group filter's choices: the graph's own by their
    // order, then the layers', then the nodes of no group.
    final laneIndex = <String, int>{};
    final shared = <DebugGraphLane>[];
    final all = <DebugGraphLane>[];
    final loose = <DebugGraphLane>[];
    for (final node in nodes) {
      final key = DebugGraphLane.keyOf(node);
      final at = laneIndex[key];
      if (at != null) {
        // A lane of the graph's own is titled by a layer whose groups are
        // lanes.
        if (at >= 0 &&
            !(layers[shared[at].layer]?.lanes ?? true) &&
            (layers[node.layer]?.lanes ?? false)) {
          final lane = shared[at];
          shared[at] = DebugGraphLane(
            key,
            node.layer,
            lane.title,
            group: lane.group,
            order: lane.order,
            role: lane.role,
          );
        }
        continue;
      }
      final order = node.group == null ? null : node.groupOrder;
      final lane = DebugGraphLane(
        key,
        node.layer,
        node.laneTitle ?? '',
        group: node.group,
        order: order,
        role: order == null ? null : node.groupRole,
      );
      if (order != null) {
        laneIndex[key] = shared.length;
        shared.add(lane);
      } else {
        laneIndex[key] = -1;
        (node.group == null ? loose : all).add(lane);
      }
    }
    final firstSeen = {
      for (var i = 0; i < shared.length; i++) shared[i].key: i,
    };
    shared.sort((a, b) {
      final byOrder = a.order!.compareTo(b.order!);
      return byOrder != 0
          ? byOrder
          : firstSeen[a.key]!.compareTo(firstSeen[b.key]!);
    });
    all
      ..insertAll(0, shared)
      ..addAll(loose);

    var kept = <int>{for (var i = 0; i < nodes.length; i++) i};
    for (final filter in filters) {
      kept = filter.keep(graph, kept);
    }

    // The lanes of what is kept, in the order of all.
    final keptLanes = {for (final i in kept) DebugGraphLane.keyOf(nodes[i])};
    final lanes = [
      for (final lane in all)
        if (keptLanes.contains(lane.key)) lane,
    ];
    final laneOf = {for (var i = 0; i < lanes.length; i++) lanes[i].key: i};

    // The plates, lane by lane, each node once in its fold.
    final ordered = kept.toList()
      ..sort((a, b) {
        final byLane = laneOf[DebugGraphLane.keyOf(nodes[a])]!.compareTo(
          laneOf[DebugGraphLane.keyOf(nodes[b])]!,
        );
        return byLane != 0 ? byLane : a.compareTo(b);
      });
    final items = <DebugGraphItem>[];
    final itemOf = List<int>.filled(nodes.length, -1);
    final foldItems = <String, int>{};
    final foldNodes = <String, List<DebugGraphNode>>{};
    for (final i in ordered) {
      final node = nodes[i];
      DebugGraphFoldGroup? fold;
      for (final step in folds) {
        fold = step.foldOf(graph, kept, i);
        if (fold != null) {
          break;
        }
      }
      final lane = laneOf[DebugGraphLane.keyOf(node)]!;
      if (fold != null && fold.folded) {
        final at = foldItems[fold.key];
        if (at != null) {
          foldNodes[fold.key]!.add(node);
          items[at].aliases.addAll(aliases[i] ?? const []);
          itemOf[i] = at;
          continue;
        }
        foldItems[fold.key] = items.length;
        foldNodes[fold.key] = [node];
        itemOf[i] = items.length;
        items.add(
          DebugGraphItem(
            key: fold.key,
            nodes: foldNodes[fold.key]!,
            label: fold.label,
            lane: lane,
            fold: fold,
            aliases: [...?aliases[i]],
          ),
        );
        continue;
      }
      itemOf[i] = items.length;
      items.add(
        DebugGraphItem(
          key: node.id,
          nodes: [node],
          label: node.label,
          lane: lane,
          fold: fold,
          aliases: aliases[i] ?? const [],
        ),
      );
    }

    // The links: every edge of the plates' nodes, once, none inside one.
    final linkIndex = <int, int>{};
    final links = <DebugGraphLink>[];
    for (final (from, to, edge) in edges) {
      final a = itemOf[from];
      final b = itemOf[to];
      if (a < 0 || b < 0 || a == b) {
        continue;
      }
      final key = a * items.length + b;
      final at = linkIndex[key];
      if (at == null) {
        linkIndex[key] = links.length;
        links.add(DebugGraphLink(a, b, dashed: edge.dashed));
      } else if (links[at].dashed && !edge.dashed) {
        links[at] = DebugGraphLink(a, b);
      }
    }
    return DebugGraph._(items, links, lanes, [
      for (final (layer, _) in parts) layer,
    ], all);
  }
}
