import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart' show Axis;
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layout.dart';

/// The application graph as a tree from top to bottom, for a layer whose
/// edges go from a parent to its children (a widget tree): the plates
/// nothing points at are the roots, left to right in the input's order;
/// a plate's first parent holds it, one row under the parent; each
/// subtree takes the width of its widest row of children, the parent
/// centred over them. In linear time, for thousands of plates.
///
/// With [DebugGraphLayoutInput.primary], the tree is of the layout's own
/// layer alone, by its own edges; the plates of the other layers (beans,
/// signals that the widgets read) make a forest of their own above it, so
/// their edges run down into the tree and never take a widget from its
/// parent. An edge that is not a parent's is drawn straight.
///
/// Lanes are not drawn, unless [banded]: then each lane is a band of its
/// own, one under the other in the lanes' order (the route grouping: the
/// current screen, its dialogs, the screens under it, the app), its title
/// over a tree of its plates alone, the other layers' plates above it as
/// before.
final class TreeDebugGraphLayout implements DebugGraphLayout {
  /// The layout with [rowGap] between rows and [siblingGap] between
  /// neighbours; with [banded], a band for each lane.
  const TreeDebugGraphLayout({
    this.rowGap = 36,
    this.siblingGap = 10,
    this.banded = false,
  });

  /// The room between two rows, where the edges run.
  final double rowGap;

  /// The room between two plates side by side.
  final double siblingGap;

  /// Whether each lane is a band of its own, its tree inside it.
  final bool banded;

  @override
  DebugGraphPlacement place(DebugGraphLayoutInput input) {
    final n = input.count;
    if (!banded || input.laneCount == 0) {
      final placed = _place(input, List<bool>.filled(n, true));
      return DebugGraphPlacement(
        positions: placed.positions,
        routes: [for (final _ in input.edges) const <Offset>[]],
        lanes: const [],
        size: Size(placed.width, placed.height),
        flow: Axis.vertical,
      );
    }
    final positions = List<Offset>.filled(n, Offset.zero);
    final bands = <(double, double)>[];
    var top = 0.0;
    var width = 0.0;
    for (var lane = 0; lane < input.laneCount; lane++) {
      final member = [for (var i = 0; i < n; i++) input.lanes[i] == lane];
      if (!member.contains(true)) {
        bands.add((top, 0));
        continue;
      }
      final placed = _place(input, member);
      final shift = Offset(0, top + input.laneHeader);
      for (var i = 0; i < n; i++) {
        if (member[i]) {
          positions[i] = placed.positions[i] + shift;
        }
      }
      final height = input.laneHeader + placed.height;
      bands.add((top, height));
      width = math.max(width, placed.width);
      top += height + rowGap;
    }
    final height = math.max(0.0, top - rowGap);
    return DebugGraphPlacement(
      positions: positions,
      routes: [for (final _ in input.edges) const <Offset>[]],
      lanes: [
        for (final (bandTop, bandHeight) in bands)
          Rect.fromLTWH(0, bandTop, width, bandHeight),
      ],
      size: Size(width, height),
      flow: Axis.vertical,
    );
  }

  // The plates [member] keeps: the tree of the layout's layer, the other
  // layers' plates above it.
  _Forest _place(DebugGraphLayoutInput input, List<bool> member) {
    final n = input.count;
    final primary = input.primary ?? List<bool>.filled(n, true);
    final positions = List<Offset>.filled(n, Offset.zero);
    final others = _forest(input, [
      for (var i = 0; i < n; i++) member[i] && !primary[i],
    ]);
    final tree = _forest(input, [
      for (var i = 0; i < n; i++) member[i] && primary[i],
    ]);
    final width = math.max(others.width, tree.width);
    final gap = others.height > 0 && tree.height > 0 ? rowGap * 1.5 : 0.0;
    for (var i = 0; i < n; i++) {
      if (!member[i]) {
        continue;
      }
      positions[i] = primary[i]
          ? tree.positions[i] +
                Offset((width - tree.width) / 2, others.height + gap)
          : others.positions[i] + Offset((width - others.width) / 2, 0);
    }
    return _Forest(positions, width, others.height + gap + tree.height);
  }

  // The tree of the plates [member] keeps, by the edges between them.
  _Forest _forest(DebugGraphLayoutInput input, List<bool> member) {
    final n = input.count;
    final children = List<List<int>>.generate(n, (_) => []);
    final incoming = List<int>.filled(n, 0);
    for (final (from, to) in input.edges) {
      if (from != to &&
          from >= 0 &&
          to >= 0 &&
          from < n &&
          to < n &&
          member[from] &&
          member[to]) {
        children[from].add(to);
        incoming[to]++;
      }
    }
    // Breadth first from the roots: a plate's first finder is its parent.
    final parent = List<int>.filled(n, -2);
    final depth = List<int>.filled(n, 0);
    final roots = <int>[];
    final tree = List<List<int>>.generate(n, (_) => []);
    void walk(int root) {
      parent[root] = -1;
      roots.add(root);
      final queue = [root];
      for (var i = 0; i < queue.length; i++) {
        final node = queue[i];
        for (final child in children[node]) {
          if (parent[child] == -2) {
            parent[child] = node;
            depth[child] = depth[node] + 1;
            tree[node].add(child);
            queue.add(child);
          }
        }
      }
    }

    for (var id = 0; id < n; id++) {
      if (member[id] && incoming[id] == 0 && parent[id] == -2) {
        walk(id);
      }
    }
    for (var id = 0; id < n; id++) {
      if (member[id] && parent[id] == -2) {
        walk(id);
      }
    }
    final positions = List<Offset>.filled(n, Offset.zero);
    if (roots.isEmpty) {
      return _Forest(positions, 0, 0);
    }

    // The width of each subtree, children before parents (deepest first).
    final order = [
      for (var i = 0; i < n; i++)
        if (member[i]) i,
    ]..sort((a, b) => depth[b].compareTo(depth[a]));
    final span = List<double>.filled(n, 0);
    for (final id in order) {
      var childrenSpan = 0.0;
      for (final child in tree[id]) {
        childrenSpan += span[child];
      }
      if (tree[id].isNotEmpty) {
        childrenSpan += siblingGap * (tree[id].length - 1);
      }
      span[id] = math.max(input.widths[id], childrenSpan);
    }

    // The rows, each as high as its highest plate.
    var rows = 0;
    for (final id in order) {
      rows = math.max(rows, depth[id] + 1);
    }
    final rowHeight = List<double>.filled(rows, 0);
    for (final id in order) {
      rowHeight[depth[id]] = math.max(rowHeight[depth[id]], input.heights[id]);
    }
    final rowTop = List<double>.filled(rows, 0);
    for (var r = 1; r < rows; r++) {
      rowTop[r] = rowTop[r - 1] + rowHeight[r - 1] + rowGap;
    }

    // Left to right: each subtree from its left, the parent centred.
    final left = List<double>.filled(n, 0);
    var at = 0.0;
    for (final root in roots) {
      left[root] = at;
      at += span[root] + siblingGap * 2;
    }
    final queue = [...roots];
    for (var i = 0; i < queue.length; i++) {
      final id = queue[i];
      positions[id] = Offset(
        left[id] + (span[id] - input.widths[id]) / 2,
        rowTop[depth[id]] + (rowHeight[depth[id]] - input.heights[id]) / 2,
      );
      var childrenSpan = 0.0;
      for (final child in tree[id]) {
        childrenSpan += span[child];
      }
      if (tree[id].isNotEmpty) {
        childrenSpan += siblingGap * (tree[id].length - 1);
      }
      var x = left[id] + (span[id] - childrenSpan) / 2;
      for (final child in tree[id]) {
        left[child] = x;
        x += span[child] + siblingGap;
        queue.add(child);
      }
    }
    return _Forest(
      positions,
      at - siblingGap * 2,
      rowTop[rows - 1] + rowHeight[rows - 1],
    );
  }
}

final class _Forest {
  const _Forest(this.positions, this.width, this.height);

  final List<Offset> positions;
  final double width;
  final double height;
}
