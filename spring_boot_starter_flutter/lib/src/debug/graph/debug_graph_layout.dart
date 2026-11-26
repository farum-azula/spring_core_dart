import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart' show Axis;

/// Where the plates of the application graph go: one of the layouts the
/// view can use, picked by the first layer shown
/// ([DebugGraphLayer.layout]) or given to the view. The built-in ones
/// are [LayeredDebugGraphLayout] (left to right, for what reads what) and
/// [TreeDebugGraphLayout] (top to bottom, for a tree of widgets).
///
/// A layout is run only when what is shown changes (a node, an edge, a
/// filter, a fold), never for a value or a flash. The same input gives the
/// same placement.
abstract interface class DebugGraphLayout {
  /// Places [input].
  DebugGraphPlacement place(DebugGraphLayoutInput input);
}

/// What a [DebugGraphLayout] places: the size of each plate, the edges
/// between them by index, the lane of each.
final class DebugGraphLayoutInput {
  /// [widths].length plates.
  DebugGraphLayoutInput({
    required this.widths,
    required this.heights,
    required this.edges,
    required this.lanes,
    required this.laneCount,
    required this.sinks,
    this.laneHeader = 0,
    this.primary,
  });

  /// The width of each plate.
  final List<double> widths;

  /// The height of each plate.
  final List<double> heights;

  /// The edges, from a plate to the plate its arrow points at.
  final List<(int, int)> edges;

  /// The lane of each plate, from 0 (the top lane).
  final List<int> lanes;

  /// How many lanes.
  final int laneCount;

  /// The plates that only read: the layered layout puts them in its last
  /// column.
  final List<bool> sinks;

  /// The room at the top of each lane for its title.
  final double laneHeader;

  /// The plates of the layer whose layout this is (`null`: all): the tree
  /// layout builds its tree of them alone, the others above it.
  final List<bool>? primary;

  /// How many plates.
  int get count => widths.length;
}

/// Where a [DebugGraphLayout] put the plates and how the edges run.
final class DebugGraphPlacement {
  /// A placement of these values.
  const DebugGraphPlacement({
    required this.positions,
    required this.routes,
    required this.lanes,
    required this.size,
    required this.flow,
    this.crossings = 0,
  });

  /// The top left of each plate.
  final List<Offset> positions;

  /// For each edge, in the input's order: the points it passes through
  /// between its two plates (none: straight from one to the other).
  final List<List<Offset>> routes;

  /// The band of each lane, across the whole width; empty for a layout
  /// without lanes.
  final List<Rect> lanes;

  /// The size of the whole.
  final Size size;

  /// Which way the edges run: [Axis.horizontal] from a plate's right edge
  /// to the next one's left, [Axis.vertical] from its bottom to the next
  /// one's top.
  final Axis flow;

  /// How many times edges cross between neighbouring columns (the layered
  /// layout).
  final int crossings;
}
