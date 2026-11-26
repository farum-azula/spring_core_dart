import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_assembly.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/layered_debug_graph_layout.dart';

/// What a frame of the graph lights: each lit plate with how lit it is
/// (1 now, 0 a second later), and on each link out of a lit plate a pulse
/// at [DebugGraphFrame.pulses]' place along it (0 at its start, 1 at its
/// arrow).
final class DebugGraphFrame {
  /// A frame of these.
  const DebugGraphFrame(this.lit, this.pulses);

  /// The plates lit, by index, with how lit.
  final Map<int, double> lit;

  /// The pulses: the link's index, where along it, how bright.
  final List<(int, double, double)> pulses;

  /// Whether nothing glows.
  bool get dark => lit.isEmpty;
}

/// The application graph laid out and measured, with its still picture:
/// what the painter draws and taps and the pointer are matched against.
/// Made again only when the graph's structure, the theme or the size of
/// the plates changes.
final class DebugGraphScene {
  DebugGraphScene._(
    this._graph,
    this.placement,
    this.rects,
    this.paths,
    this.arrows,
    this.lanes,
    this.size,
    this._labels,
    this._style,
    this._colors,
    this._shapes,
    this.compact,
  ) : _metrics = [
        for (final path in paths)
          switch (path.computeMetrics().iterator) {
            final metrics when metrics.moveNext() => metrics.current,
            _ => null,
          },
      ];

  /// The scene of [graph] in [style], laid out by [layout], whose own layer
  /// is [primaryLayer] when it is a layer's.
  factory DebugGraphScene.of(
    DebugGraph graph, {
    required DebugStyle style,
    DebugGraphLayout layout = const LayeredDebugGraphLayout(),
    bool compact = false,
    String? primaryLayer,
  }) {
    final size = math.max(
      (style.code.fontSize ?? 11) * (compact ? 0.9 : 1),
      9.5,
    );
    final text = style.code.copyWith(fontSize: size, color: style.foreground);
    final padH = compact ? 6.0 : 8.0;
    final padV = compact ? 3.0 : 5.0;
    final labels = [
      for (final item in graph.items)
        TextPainter(
          text: TextSpan(text: item.label, style: text),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 220),
    ];
    final laneStyle = text.copyWith(
      fontSize: size * 1.05,
      color: style.foreground.withValues(alpha: 0.9),
      fontWeight: FontWeight.w700,
    );
    final laneRoleStyle = laneStyle.copyWith(
      color: style.muted,
      fontWeight: FontWeight.w600,
    );
    // A layer whose groups are no lanes has no titles to measure.
    final laneLayers = {
      for (final layer in graph.layers)
        if (layer.lanes) layer.id,
    };
    final laneLabels = [
      for (final lane in graph.lanes)
        TextPainter(
          text: !laneLayers.contains(lane.layer)
              ? TextSpan(text: '', style: laneStyle)
              : TextSpan(
                  style: laneStyle,
                  children: [
                    if (_roleLabel(lane.role) case final role?
                        when role != lane.title)
                      TextSpan(text: '$role  ', style: laneRoleStyle),
                    TextSpan(text: lane.title),
                    // A tap on the title folds the lane, and opens it.
                    if (lane.group != null)
                      TextSpan(
                        text: _collapsedIn(graph, lane) ? '  [+]' : '  [-]',
                        style: laneRoleStyle,
                      ),
                  ],
                ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 260),
    ];
    final header = laneLabels.isEmpty
        ? 0.0
        : laneLabels.map((label) => label.height).reduce(math.max) + 2;
    final placement = layout.place(
      DebugGraphLayoutInput(
        widths: [for (final label in labels) label.width + padH * 2],
        heights: [for (final label in labels) label.height + padV * 2],
        edges: [for (final link in graph.links) (link.from, link.to)],
        lanes: [for (final item in graph.items) item.lane],
        laneCount: graph.lanes.length,
        sinks: [for (final item in graph.items) item.sink],
        laneHeader: header,
        primary: primaryLayer == null
            ? null
            : [for (final item in graph.items) item.layer == primaryLayer],
      ),
    );
    const margin = Offset(12, 10);
    final rects = [
      for (var i = 0; i < graph.items.length; i++)
        (placement.positions[i] + margin) &
            Size(labels[i].width + padH * 2, labels[i].height + padV * 2),
    ];
    final paths = <Path>[];
    final arrows = <Path>[];
    for (var e = 0; e < graph.links.length; e++) {
      final link = graph.links[e];
      final (path, arrow) = _edge(
        rects[link.from],
        rects[link.to],
        [for (final point in placement.routes[e]) point + margin],
        placement.flow,
      );
      paths.add(path);
      arrows.add(arrow);
    }
    final lanes = <DebugGraphLaneBand>[];
    for (var l = 0; l < placement.lanes.length && l < graph.lanes.length; l++) {
      final band = placement.lanes[l];
      if (band.height <= 0) {
        laneLabels[l].dispose();
        continue;
      }
      final rect = band.shift(margin).inflate(4);
      final label = laneLabels[l];
      lanes.add(
        DebugGraphLaneBand(
          graph.lanes[l],
          rect,
          Rect.fromLTWH(rect.left + 6, rect.top + 3, label.width, label.height),
          label,
        ),
      );
    }
    for (var l = placement.lanes.length; l < laneLabels.length; l++) {
      laneLabels[l].dispose();
    }
    final colors = {
      for (final layer in graph.layers) layer.id: layer.colorOf(style),
    };
    final shapes = {
      for (final layer in graph.layers)
        for (final kind in layer.kinds)
          '${layer.id}\u0000${kind.id}': kind.shape,
    };
    return DebugGraphScene._(
      graph,
      placement,
      rects,
      paths,
      arrows,
      lanes,
      Size(
        placement.size.width + margin.dx * 2,
        placement.size.height + margin.dy * 2,
      ),
      labels,
      style,
      colors,
      shapes,
      compact,
    );
  }

  static bool _collapsedIn(DebugGraph graph, DebugGraphLane lane) => graph.items
      .any((item) => item.folded && item.key == 'lane\u0000${lane.key}');

  // The curve from [from] to [to] through [route], and its arrowhead.
  static (Path, Path) _edge(Rect from, Rect to, List<Offset> route, Axis flow) {
    final horizontal = flow == Axis.horizontal;
    final firstAim = route.isEmpty ? null : route.first;
    final lastAim = route.isEmpty ? null : route.last;
    final Offset start;
    final Offset end;
    if (horizontal) {
      final forward = (firstAim?.dx ?? to.left) >= from.right - 1;
      start = forward ? from.centerRight : from.centerLeft;
      final arrivesLeft = (lastAim?.dx ?? start.dx) <= to.left + 1;
      end = arrivesLeft ? to.centerLeft : to.centerRight;
    } else {
      final down = (firstAim?.dy ?? to.top) >= from.bottom - 1;
      start = down ? from.bottomCenter : from.topCenter;
      final arrivesTop = (lastAim?.dy ?? start.dy) <= to.top + 1;
      end = arrivesTop ? to.topCenter : to.bottomCenter;
    }
    final path = Path()..moveTo(start.dx, start.dy);
    var at = start;
    var control = start;
    for (final point in [...route, end]) {
      final Offset c1;
      final Offset c2;
      if (horizontal) {
        final bend = (point.dx - at.dx) / 2;
        c1 = Offset(at.dx + bend, at.dy);
        c2 = Offset(point.dx - bend, point.dy);
      } else {
        final bend = (point.dy - at.dy) / 2;
        c1 = Offset(at.dx, at.dy + bend);
        c2 = Offset(point.dx, point.dy - bend);
      }
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, point.dx, point.dy);
      control = c2 == point ? at : c2;
      at = point;
    }
    var direction = end - control;
    if (direction.distance < 0.01) {
      direction = horizontal ? const Offset(1, 0) : const Offset(0, 1);
    }
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    const length = 7.0;
    const half = 3.5;
    final base = end - unit * length;
    final arrow = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo((base + normal * half).dx, (base + normal * half).dy)
      ..lineTo((base - normal * half).dx, (base - normal * half).dy)
      ..close();
    return (path, arrow);
  }

  /// The plates, links and lanes.
  DebugGraph get graph => _graph;
  DebugGraph _graph;

  /// Takes [graph], of the same structure as [graph] (the same
  /// `DebugGraph.signature`), instead: the plates stay where they are,
  /// their nodes are those of the newer collect.
  void useGraph(DebugGraph graph) {
    assert(graph.signature == _graph.signature, 'not the same structure');
    _graph = graph;
  }

  /// Where the layout put them.
  final DebugGraphPlacement placement;

  /// The plate of each item.
  final List<Rect> rects;

  /// The curve of each link, in [DebugGraph.links]' order.
  final List<Path> paths;

  /// The arrowhead of each link.
  final List<Path> arrows;

  /// The lanes' bands and titles.
  final List<DebugGraphLaneBand> lanes;

  /// The size of the whole.
  final Size size;

  /// Whether the plates are the small ones.
  final bool compact;

  final List<ui.PathMetric?> _metrics;
  final List<TextPainter> _labels;
  final DebugStyle _style;
  final Map<String, Color> _colors;
  final Map<String, DebugGraphShape> _shapes;
  ui.Picture? _still;
  int? _stillSelected;
  Map<int, double>? _stillHeat;
  Set<int>? _stillMarked;
  Set<int> _dimmed = const {};

  /// The highest share of the flash colour in a lit plate's fill.
  static const maxFlashTint = 0.25;

  /// The colour of plate [index]: its layer's, the theme's muted one for
  /// a plate of dimmed nodes only ([DebugGraphNode.dimmed]).
  Color colorOf(int index) {
    final item = graph.items[index];
    if (item.nodes.isNotEmpty && item.nodes.every((node) => node.dimmed)) {
      return _style.muted;
    }
    return _colors[item.layer] ?? _style.accent;
  }

  /// The shape of plate [index]: its kind's.
  DebugGraphShape shapeOf(int index) {
    final item = graph.items[index];
    return _shapes['${item.layer}\u0000${item.kind}'] ??
        DebugGraphShape.rounded;
  }

  /// The plate whose rectangle holds [at], or `null`.
  int? itemAt(Offset at) {
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].contains(at)) {
        return i;
      }
    }
    return null;
  }

  /// The lane whose title holds [at], or `null`.
  DebugGraphLane? laneTitleAt(Offset at) {
    for (final band in lanes) {
      if (band.lane.group != null && band.titleRect.inflate(3).contains(at)) {
        return band.lane;
      }
    }
    return null;
  }

  /// The fill of plate [index] with [lamp] of the flash colour in it, at
  /// most [maxFlashTint]: a lit plate is tinted, never filled.
  Color fillOf(int index, double lamp) {
    final base = Color.lerp(
      _style.background,
      colorOf(index),
      compact ? 0.2 : 0.16,
    )!;
    return Color.lerp(
      base,
      _style.graphFlash,
      maxFlashTint * lamp.clamp(0, 1),
    )!;
  }

  /// What is lit now, as the layers tell it.
  DebugGraphFrame frame() {
    final lit = <int, double>{};
    final layers = {for (final layer in graph.layers) layer.id: layer};
    for (var i = 0; i < graph.items.length; i++) {
      var lamp = 0.0;
      for (final nodes in [graph.items[i].nodes, graph.items[i].aliases]) {
        for (final node in nodes) {
          final glow = layers[node.layer]?.glowOf(node) ?? 0;
          if (glow > lamp) {
            lamp = glow;
          }
        }
      }
      if (lamp > 0) {
        lit[i] = math.min(lamp, 1);
      }
    }
    final pulses = <(int, double, double)>[];
    if (lit.isNotEmpty) {
      for (var e = 0; e < graph.links.length; e++) {
        final lamp = lit[graph.links[e].from];
        if (lamp != null) {
          pulses.add((e, 1 - lamp, lamp));
        }
      }
    }
    return DebugGraphFrame(lit, pulses);
  }

  /// Whether plate [index] is dimmed in the still picture last recorded:
  /// out of the tapped plate's chain, or not one of the legend's marked.
  bool dimmedNow(int index) => _dimmed.contains(index);

  /// The still picture: lanes, links and plates; with [selected], its
  /// chain bright and the rest dimmed; with [marked] (the plates of the
  /// legend entries selected), those with a border and a glow in the
  /// theme's accent and the rest dimmed; the plates of [heat] (a hot
  /// branch, by index, 0 to 1) and the links between them outlined in the
  /// theme's `graph-hot`. Recorded once for each.
  ui.Picture still({
    int? selected,
    Map<int, double> heat = const {},
    Set<int>? marked,
  }) {
    final kept = _still;
    if (kept != null &&
        selected == _stillSelected &&
        identical(heat, _stillHeat) &&
        identical(marked, _stillMarked)) {
      return kept;
    }
    kept?.dispose();
    _stillSelected = selected;
    _stillHeat = heat;
    _stillMarked = marked;
    final chain = selected == null ? null : graph.chainOf(selected);
    _dimmed = {
      for (var i = 0; i < rects.length; i++)
        if ((chain != null && !chain.contains(i)) ||
            (marked != null && !marked.contains(i)))
          i,
    };
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // A lane is a faint tint, a thin outline and its title: seen as one
    // group, while the app under a console pane still shows through.
    final laneFill = Paint()
      ..color = _style.foreground.withValues(alpha: 0.035);
    final laneLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _style.line;
    for (final band in lanes) {
      final rrect = RRect.fromRectAndRadius(
        band.rect,
        const Radius.circular(6),
      );
      canvas
        ..drawRRect(rrect, laneFill)
        ..drawRRect(rrect, laneLine);
      band.title.paint(canvas, band.titleRect.topLeft);
    }
    for (var e = 0; e < paths.length; e++) {
      final link = graph.links[e];
      final inChain =
          (chain == null ||
              (chain.contains(link.from) && chain.contains(link.to))) &&
          (marked == null ||
              (marked.contains(link.from) && marked.contains(link.to)));
      final color = inChain
          ? (chain == null && marked == null
                ? _style.muted.withValues(alpha: 0.7)
                : _style.accent)
          : _style.muted.withValues(alpha: 0.15);
      final hot = heat[link.from] != null && heat[link.to] != null
          ? math.min(heat[link.from]!, heat[link.to]!)
          : 0.0;
      _paintLink(
        canvas,
        e,
        hot > 0 && inChain
            ? Color.lerp(color, _style.graphHot, 0.4 + 0.6 * hot)!
            : color,
        (chain != null || marked != null) && inChain ? 1.8 : 1.2 + hot * 1.5,
      );
    }
    for (var i = 0; i < rects.length; i++) {
      final dim = _dimmed.contains(i);
      if (heat[i] case final hot? when hot > 0 && !dim) {
        canvas.drawPath(
          outline(shapeOf(i), rects[i].inflate(2.5), compact: compact),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 + hot * 1.5
            ..color = _style.graphHot.withValues(alpha: 0.5 + 0.5 * hot),
        );
      }
      paintItem(
        canvas,
        i,
        0,
        dim: dim,
        selected: i == selected,
        marked: marked != null && !dim,
      );
    }
    return _still = recorder.endRecording();
  }

  void _paintLink(Canvas canvas, int edge, Color color, double width) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    if (graph.links[edge].dashed) {
      final metric = _metrics[edge];
      if (metric != null) {
        for (var at = 0.0; at < metric.length; at += 8) {
          canvas.drawPath(
            metric.extractPath(at, math.min(at + 4, metric.length)),
            stroke,
          );
        }
      }
    } else {
      canvas.drawPath(paths[edge], stroke);
    }
    canvas.drawPath(arrows[edge], Paint()..color = color);
  }

  /// The outline of [shape] in [rect].
  static Path outline(
    DebugGraphShape shape,
    Rect rect, {
    bool compact = false,
  }) {
    final h = rect.height;
    final cut = math.min(h * 0.3, rect.width * 0.2);
    switch (shape) {
      case DebugGraphShape.rounded:
        return Path()..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(compact ? 4 : 6)),
        );
      case DebugGraphShape.pill:
        return Path()..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(h / 2)),
        );
      case DebugGraphShape.rectangle:
      case DebugGraphShape.tagged:
        return Path()..addRect(rect);
      case DebugGraphShape.octagon:
        return Path()
          ..moveTo(rect.left + cut, rect.top)
          ..lineTo(rect.right - cut, rect.top)
          ..lineTo(rect.right, rect.top + cut)
          ..lineTo(rect.right, rect.bottom - cut)
          ..lineTo(rect.right - cut, rect.bottom)
          ..lineTo(rect.left + cut, rect.bottom)
          ..lineTo(rect.left, rect.bottom - cut)
          ..lineTo(rect.left, rect.top + cut)
          ..close();
      case DebugGraphShape.hexagon:
        final point = math.min(h / 2, rect.width * 0.25);
        return Path()
          ..moveTo(rect.left + point, rect.top)
          ..lineTo(rect.right - point, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.right - point, rect.bottom)
          ..lineTo(rect.left + point, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
      case DebugGraphShape.parallelogram:
        final lean = math.min(h * 0.4, rect.width * 0.2);
        return Path()
          ..moveTo(rect.left + lean, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.right - lean, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
    }
  }

  /// Paints plate [index], [lamp] lit: a lit plate gets a brighter border,
  /// a glow around it and at most [maxFlashTint] of the flash colour in its
  /// fill; a [marked] one (of a legend entry selected) a border and a glow
  /// in the theme's accent.
  void paintItem(
    Canvas canvas,
    int index,
    double lamp, {
    bool dim = false,
    bool selected = false,
    bool marked = false,
  }) {
    final color = colorOf(index);
    final rect = rects[index];
    final shape = shapeOf(index);
    final path = outline(shape, rect, compact: compact);
    final alpha = dim ? 0.3 : 1.0;
    final flash = _style.graphFlash;
    if (graph.items[index].folded) {
      final behind = outline(
        shape,
        rect.shift(const Offset(3, 3)),
        compact: compact,
      );
      canvas
        ..drawPath(
          behind,
          Paint()..color = fillOf(index, 0).withValues(alpha: alpha),
        )
        ..drawPath(
          behind,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.6 * alpha),
        );
    }
    if (marked) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = _style.accent.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    if (lamp > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = flash.withValues(alpha: 0.45 * lamp)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawPath(
      path,
      Paint()..color = fillOf(index, lamp).withValues(alpha: alpha),
    );
    if (shape == DebugGraphShape.tagged) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, 3, rect.height),
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected || marked ? 2 : 1 + lamp * 1.2
        ..color =
            (selected || (marked && lamp == 0)
                    ? _style.accent
                    : Color.lerp(color, flash, lamp)!)
                .withValues(alpha: alpha),
    );
    final label = _labels[index];
    final at = Offset(
      rect.left + (rect.width - label.width) / 2,
      rect.top + (rect.height - label.height) / 2,
    );
    if (dim) {
      canvas.saveLayer(rect, Paint()..color = const Color(0x55000000));
      label.paint(canvas, at);
      canvas.restore();
    } else {
      label.paint(canvas, at);
    }
  }

  /// Paints the pulse of link [edge] at [t] along it, [alpha] bright, in
  /// the flash colour.
  void paintPulse(Canvas canvas, int edge, double t, double alpha) {
    final metric = _metrics[edge];
    final flash = _style.graphFlash;
    canvas.drawPath(
      paths[edge],
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = flash.withValues(alpha: 0.6 * alpha),
    );
    if (metric == null) {
      return;
    }
    final tangent = metric.getTangentForOffset(metric.length * t);
    if (tangent == null) {
      return;
    }
    canvas
      ..drawCircle(
        tangent.position,
        6,
        Paint()..color = flash.withValues(alpha: 0.25 * alpha),
      )
      ..drawCircle(
        tangent.position,
        3,
        Paint()..color = flash.withValues(alpha: alpha),
      );
  }

  /// Frees the still picture and the labels.
  void dispose() {
    _still?.dispose();
    _still = null;
    for (final label in _labels) {
      label.dispose();
    }
    for (final band in lanes) {
      band.title.dispose();
    }
  }
}

/// The band of a lane across the graph, and its title at its left.
final class DebugGraphLaneBand {
  /// The band of [lane].
  const DebugGraphLaneBand(this.lane, this.rect, this.titleRect, this.title);

  /// The lane.
  final DebugGraphLane lane;

  /// Its band.
  final Rect rect;

  /// Where its title is: a tap there collapses the lane (and opens it).
  final Rect titleRect;

  /// Its title.
  final TextPainter title;
}

/// Paints a [DebugGraphScene] under [transform]: its still picture, then
/// what is lit, on each of [repaint]'s changes (at most once a frame).
class DebugGraphPainter extends CustomPainter {
  /// The painter of [scene].
  DebugGraphPainter(
    this.scene, {
    required this.transform,
    required Listenable repaint,
    this.selected,
    this.animating,
    this.heat = const {},
    this.marked,
  }) : super(repaint: repaint);

  /// The hot plates, by index, 0 to 1.
  final Map<int, double> heat;

  /// The plates of the legend entries selected; `null`: none selected.
  final Set<int>? marked;

  /// What it paints.
  final DebugGraphScene scene;

  /// Where the scene is: its scale and offset in the viewport.
  final ValueListenable<Matrix4> transform;

  /// The plate tapped.
  final int? selected;

  /// Whether to read the layers' glows (only while something may glow).
  final ValueListenable<bool>? animating;

  /// The last frame painted, for tests.
  DebugGraphFrame? lastFrame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..transform(transform.value.storage)
      ..drawPicture(
        scene.still(selected: selected, heat: heat, marked: marked),
      );
    if (animating?.value ?? true) {
      final frame = lastFrame = scene.frame();
      for (final (edge, t, alpha) in frame.pulses) {
        scene.paintPulse(canvas, edge, t, alpha);
      }
      for (final MapEntry(key: item, value: lamp) in frame.lit.entries) {
        final dim = scene.dimmedNow(item);
        scene.paintItem(
          canvas,
          item,
          lamp,
          dim: dim,
          selected: item == selected,
          marked: marked != null && !dim,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DebugGraphPainter oldDelegate) =>
      !identical(oldDelegate.scene, scene) ||
      oldDelegate.selected != selected ||
      !identical(oldDelegate.heat, heat) ||
      !identical(oldDelegate.marked, marked) ||
      !identical(oldDelegate.transform, transform);
}

// What a lane of the navigator's stack is, before its title.
String? _roleLabel(DebugGraphGroupRole? role) => switch (role) {
  DebugGraphGroupRole.current => 'Screen',
  DebugGraphGroupRole.dialog => 'Dialog',
  DebugGraphGroupRole.below => 'Below',
  DebugGraphGroupRole.app => 'App',
  null => null,
};
