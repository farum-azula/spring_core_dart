import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart' show Axis;
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layout.dart';

/// The application graph from left to right in columns: each plate one
/// column after the furthest plate it comes from (the longest path), the
/// plates that only read in the last column; in each column the plates
/// ordered by the mean place of their neighbours, to cross few edges.
/// Each lane is a band across every column, the lanes one under the
/// other in the input's order; a plate stays in its lane's band, moved
/// close to its neighbours without overlapping another. An edge that
/// spans columns passes through a point in each column between, in its
/// lanes' bands.
final class LayeredDebugGraphLayout implements DebugGraphLayout {
  /// The layout with [columnGap] between columns, [nodeGap] between plates
  /// of a lane, [laneGap] between lanes, [sweeps] passes of ordering.
  const LayeredDebugGraphLayout({
    this.columnGap = 64,
    this.nodeGap = 8,
    this.laneGap = 10,
    this.lanePadding = 6,
    this.sweeps = 12,
  });

  /// The room between columns, where the edges run.
  final double columnGap;

  /// The room between two plates of a lane in a column.
  final double nodeGap;

  /// The room between two lanes.
  final double laneGap;

  /// The room inside a lane's band around its plates.
  final double lanePadding;

  /// How many passes order the columns (down and up in turn).
  final int sweeps;

  @override
  DebugGraphPlacement place(DebugGraphLayoutInput input) =>
      _Layered(input, this).run();
}

final class _Layered {
  _Layered(this.input, this.settings) : n = input.count;

  final DebugGraphLayoutInput input;
  final LayeredDebugGraphLayout settings;
  final int n;

  static const _pointHeight = 4.0;

  late List<double> _heights;
  late List<int> _lanes;

  DebugGraphPlacement run() {
    // The edges as given (none twice, none to itself), turned around when
    // one closes a cycle.
    final seen = <int, int>{};
    final proper = <(int, int)>[];
    final edgeIndex = <int>[];
    for (final (from, to) in input.edges) {
      if (from == to || from < 0 || to < 0 || from >= n || to >= n) {
        edgeIndex.add(-1);
        continue;
      }
      edgeIndex.add(
        seen.putIfAbsent(from * n + to, () {
          proper.add((from, to));
          return proper.length - 1;
        }),
      );
    }
    final reversed = _breakCycles(proper);
    final directed = [
      for (var i = 0; i < proper.length; i++)
        reversed[i] ? (proper[i].$2, proper[i].$1) : proper[i],
    ];
    final layerOf = List<int>.of(_columns(directed));
    final columnCount = n == 0 ? 0 : layerOf.reduce(math.max) + 1;

    // A point in each column an edge passes, in its first lane for the
    // first half of the way, then in its last.
    final widths = List<double>.of(input.widths);
    _heights = List<double>.of(input.heights);
    _lanes = List<int>.of(input.lanes);
    final chainsByProper = <List<int>>[];
    var next = n;
    for (final (from, to) in directed) {
      final chain = [from];
      final middle = (layerOf[from] + layerOf[to]) / 2;
      for (var column = layerOf[from] + 1; column < layerOf[to]; column++) {
        layerOf.add(column);
        widths.add(0);
        _heights.add(_pointHeight);
        _lanes.add(column < middle ? _lanes[from] : _lanes[to]);
        chain.add(next++);
      }
      chain.add(to);
      chainsByProper.add(chain);
    }
    final total = next;
    final preds = List<List<int>>.generate(total, (_) => []);
    final succs = List<List<int>>.generate(total, (_) => []);
    for (final chain in chainsByProper) {
      for (var i = 0; i + 1 < chain.length; i++) {
        succs[chain[i]].add(chain[i + 1]);
        preds[chain[i + 1]].add(chain[i]);
      }
    }

    var columns = List<List<int>>.generate(columnCount, (_) => []);
    for (var id = 0; id < total; id++) {
      columns[layerOf[id]].add(id);
    }
    final pos = List<double>.filled(total, 0);
    for (final column in columns) {
      column.sort((a, b) {
        final byLane = _lanes[a].compareTo(_lanes[b]);
        return byLane != 0 ? byLane : a.compareTo(b);
      });
      _index(column, pos);
    }

    // Mean-place sweeps, down and up, keeping the order that crosses
    // least.
    var best = [for (final column in columns) List<int>.of(column)];
    var bestCrossings = _crossings(columns, succs, pos);
    for (var sweep = 0; sweep < settings.sweeps && bestCrossings > 0; sweep++) {
      if (sweep.isEven) {
        for (var c = 1; c < columnCount; c++) {
          _order(columns[c], preds, pos);
        }
      } else {
        for (var c = columnCount - 2; c >= 0; c--) {
          _order(columns[c], succs, pos);
        }
      }
      final crossings = _crossings(columns, succs, pos);
      if (crossings < bestCrossings) {
        bestCrossings = crossings;
        best = [for (final column in columns) List<int>.of(column)];
      }
    }
    columns = best;
    for (final column in columns) {
      _index(column, pos);
    }

    // Left to right: the columns side by side; a point as wide as its
    // column.
    final x = List<double>.filled(total, 0);
    var left = 0.0;
    for (final column in columns) {
      var widest = 0.0;
      for (final id in column) {
        widest = math.max(widest, widths[id]);
      }
      for (final id in column) {
        x[id] = left;
        if (id >= n) {
          widths[id] = widest;
        }
      }
      left += widest + settings.columnGap;
    }
    final width = columns.isEmpty ? 0.0 : left - settings.columnGap;

    // Top to bottom: each lane a band as high as its fullest column, the
    // plates of a column stacked in it, then moved towards their
    // neighbours within it.
    final laneCount = math.max(input.laneCount, 1);
    final segments = [
      for (final column in columns)
        [
          for (var lane = 0; lane < laneCount; lane++)
            [
              for (final id in column)
                if (_lanes[id] == lane) id,
            ],
        ],
    ];
    final laneHeight = List<double>.filled(laneCount, 0);
    for (final column in segments) {
      for (var lane = 0; lane < laneCount; lane++) {
        laneHeight[lane] = math.max(laneHeight[lane], _stacked(column[lane]));
      }
    }
    final laneTop = List<double>.filled(laneCount, 0);
    final bands = <Rect>[];
    var at = 0.0;
    final padding = settings.lanePadding;
    for (var lane = 0; lane < laneCount; lane++) {
      final empty = laneHeight[lane] == 0;
      final top = at;
      laneTop[lane] = top + (empty ? 0 : input.laneHeader + padding);
      final bottom = empty ? top : laneTop[lane] + laneHeight[lane] + padding;
      bands.add(Rect.fromLTRB(0, top, width, bottom));
      at = bottom + (empty ? 0 : settings.laneGap);
    }
    final height = laneCount == 0 || n == 0 ? 0.0 : at - settings.laneGap;

    final centre = List<double>.filled(total, 0);
    for (final column in segments) {
      for (var lane = 0; lane < laneCount; lane++) {
        final ids = column[lane];
        for (var i = 0; i < ids.length; i++) {
          centre[ids[i]] = i == 0
              ? laneTop[lane] + _heights[ids[i]] / 2
              : centre[ids[i - 1]] + _separation(ids[i - 1], ids[i]);
        }
      }
    }
    for (var pass = 0; pass < 6; pass++) {
      final down = pass.isEven;
      final order = down
          ? [for (var c = 1; c < columnCount; c++) c]
          : [for (var c = columnCount - 2; c >= 0; c--) c];
      for (final c in order) {
        for (var lane = 0; lane < laneCount; lane++) {
          _align(
            segments[c][lane],
            down ? preds : succs,
            centre,
            laneTop[lane],
            laneTop[lane] + laneHeight[lane],
          );
        }
      }
    }

    final positions = [
      for (var id = 0; id < n; id++)
        Offset(x[id], centre[id] - _heights[id] / 2),
    ];
    final routes = [
      for (final index in edgeIndex)
        if (index < 0)
          const <Offset>[]
        else
          _route(
            reversed[index]
                ? chainsByProper[index].reversed.toList()
                : chainsByProper[index],
            reversed[index],
            x,
            widths,
            centre,
          ),
    ];
    return DebugGraphPlacement(
      positions: positions,
      routes: routes,
      lanes: bands,
      size: Size(width, height),
      flow: Axis.horizontal,
      crossings: bestCrossings,
    );
  }

  // The points of [chain] between its ends: through each point's column
  // from one side to the other, in the way the edge goes.
  List<Offset> _route(
    List<int> chain,
    bool backwards,
    List<double> x,
    List<double> widths,
    List<double> centre,
  ) => [
    for (var i = 1; i + 1 < chain.length; i++) ...[
      Offset(
        backwards ? x[chain[i]] + widths[chain[i]] : x[chain[i]],
        centre[chain[i]],
      ),
      Offset(
        backwards ? x[chain[i]] : x[chain[i]] + widths[chain[i]],
        centre[chain[i]],
      ),
    ],
  ];

  double _stacked(List<int> ids) {
    if (ids.isEmpty) {
      return 0;
    }
    var height = _heights[ids.first] / 2 + _heights[ids.last] / 2;
    for (var i = 1; i < ids.length; i++) {
      height += _separation(ids[i - 1], ids[i]);
    }
    return ids.length == 1 ? _heights[ids.first] : height;
  }

  // The edges that close a cycle (found by a depth-first walk in the
  // order of the plates), to be turned around.
  List<bool> _breakCycles(List<(int, int)> edges) {
    final out = List<List<int>>.generate(n, (_) => []);
    for (var i = 0; i < edges.length; i++) {
      out[edges[i].$1].add(i);
    }
    final reversed = List<bool>.filled(edges.length, false);
    // 0: not seen, 1: on the path, 2: done.
    final state = List<int>.filled(n, 0);
    for (var root = 0; root < n; root++) {
      if (state[root] != 0) {
        continue;
      }
      final stack = <(int, int)>[(root, 0)];
      state[root] = 1;
      while (stack.isNotEmpty) {
        final (node, next) = stack.removeLast();
        if (next < out[node].length) {
          stack.add((node, next + 1));
          final edge = out[node][next];
          final to = edges[edge].$2;
          if (state[to] == 1) {
            reversed[edge] = true;
          } else if (state[to] == 0) {
            state[to] = 1;
            stack.add((to, 0));
          }
        } else {
          state[node] = 2;
        }
      }
    }
    return reversed;
  }

  // The longest path from a plate nothing comes to: one column after the
  // furthest plate it comes from; the sinks in the last.
  List<int> _columns(List<(int, int)> edges) {
    final column = List<int>.filled(n, 0);
    final incoming = List<int>.filled(n, 0);
    final out = List<List<int>>.generate(n, (_) => []);
    for (final (from, to) in edges) {
      out[from].add(to);
      incoming[to]++;
    }
    final ready = [
      for (var id = 0; id < n; id++)
        if (incoming[id] == 0) id,
    ];
    for (var i = 0; i < ready.length; i++) {
      final node = ready[i];
      for (final to in out[node]) {
        column[to] = math.max(column[to], column[node] + 1);
        if (--incoming[to] == 0) {
          ready.add(to);
        }
      }
    }
    if (n == 0) {
      return column;
    }
    final last = column.reduce(math.max);
    for (var id = 0; id < n; id++) {
      if (input.sinks[id] && out[id].isEmpty) {
        column[id] = last;
      }
    }
    return column;
  }

  static void _index(List<int> column, List<double> pos) {
    for (var i = 0; i < column.length; i++) {
      pos[column[i]] = i.toDouble();
    }
  }

  // Orders [column] by lane, and in a lane by the mean place of each
  // plate's [neighbours] (its own place when it has none).
  void _order(List<int> column, List<List<int>> neighbours, List<double> pos) {
    final bary = <int, double>{};
    for (final id in column) {
      final around = neighbours[id];
      if (around.isEmpty) {
        bary[id] = pos[id];
      } else {
        var sum = 0.0;
        for (final other in around) {
          sum += pos[other];
        }
        bary[id] = sum / around.length;
      }
    }
    column.sort((a, b) {
      final byLane = _lanes[a].compareTo(_lanes[b]);
      if (byLane != 0) {
        return byLane;
      }
      final byPlace = bary[a]!.compareTo(bary[b]!);
      return byPlace != 0 ? byPlace : pos[a].compareTo(pos[b]);
    });
    _index(column, pos);
  }

  // The crossings between each pair of neighbouring columns: the
  // inversions of the targets' places, the edges sorted by their sources'.
  static int _crossings(
    List<List<int>> columns,
    List<List<int>> succs,
    List<double> pos,
  ) {
    var total = 0;
    for (var c = 0; c + 1 < columns.length; c++) {
      final pairs = <(int, int)>[
        for (final from in columns[c])
          for (final to in succs[from]) (pos[from].toInt(), pos[to].toInt()),
      ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
      final size = columns[c + 1].length;
      final tree = List<int>.filled(size + 1, 0);
      var seen = 0;
      for (final (_, to) in pairs) {
        var atOrAbove = 0;
        for (var i = to + 1; i > 0; i -= i & -i) {
          atOrAbove += tree[i];
        }
        total += seen - atOrAbove;
        for (var i = to + 1; i <= size; i += i & -i) {
          tree[i]++;
        }
        seen++;
      }
    }
    return total;
  }

  double _separation(int a, int b) {
    final gap = a >= n || b >= n ? settings.nodeGap / 2 : settings.nodeGap;
    return (_heights[a] + _heights[b]) / 2 + gap;
  }

  // Moves the plates of [ids] (one lane of one column) towards the mean
  // height of their [neighbours], keeping their order, their room and
  // their lane's band from [top] to [bottom]: the closest heights in
  // order (pool adjacent violators over the heights less the room above
  // each), each pooled block kept in the band.
  void _align(
    List<int> ids,
    List<List<int>> neighbours,
    List<double> centre,
    double top,
    double bottom,
  ) {
    final count = ids.length;
    if (count == 0) {
      return;
    }
    final offset = List<double>.filled(count, 0);
    for (var i = 1; i < count; i++) {
      offset[i] = offset[i - 1] + _separation(ids[i - 1], ids[i]);
    }
    final least = top + _heights[ids.first] / 2;
    final most = bottom - _heights[ids.last] / 2 - offset[count - 1];
    final wanted = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final id = ids[i];
      final around = neighbours[id];
      var target = centre[id];
      if (around.isNotEmpty) {
        var sum = 0.0;
        for (final other in around) {
          sum += centre[other];
        }
        target = sum / around.length;
      }
      wanted[i] = target - offset[i];
    }
    final values = <double>[];
    final weights = <int>[];
    for (final value in wanted) {
      values.add(value);
      weights.add(1);
      while (values.length > 1 &&
          values[values.length - 2] > values[values.length - 1]) {
        final w = weights.removeLast();
        final v = values.removeLast();
        final pw = weights.last;
        values.last = (values.last * pw + v * w) / (pw + w);
        weights.last = pw + w;
      }
    }
    var i = 0;
    for (var block = 0; block < values.length; block++) {
      final value = most < least
          ? least
          : values[block].clamp(least, most).toDouble();
      for (var k = 0; k < weights[block]; k++, i++) {
        centre[ids[i]] = value + offset[i];
      }
    }
  }
}
