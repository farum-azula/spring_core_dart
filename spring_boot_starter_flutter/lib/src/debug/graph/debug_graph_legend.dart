import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_assembly.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_memory.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_scene.dart';

/// An entry of the application graph's legend: what it shows, what the
/// pointer over it tells, and which nodes it stands for. Selected (a tap),
/// the graph highlights its nodes and dims the rest
/// ([DebugGraphLegend.marksOf]).
///
/// A layer's entries ([of]) are each of its kinds
/// ([DebugGraphKindEntry]), its flash when it has one
/// ([DebugGraphFlashEntry], [DebugGraphLayer.flashMeaning]) and its hot
/// outline when it has one ([DebugGraphHotEntry],
/// [DebugGraphLayer.heatMeaning]).
abstract class DebugGraphLegendEntry {
  /// An entry of [layer].
  const DebugGraphLegendEntry(this.layer);

  /// The layer whose nodes it stands for.
  final DebugGraphLayer layer;

  /// Its name inside its layer: a kind's id, `flash`, `hot`.
  String get id;

  /// Its key, the same in every view and run: what the selection
  /// ([DebugGraphMemory.legend]) keeps.
  String get key => '${layer.id}\u0000$id';

  /// What it says.
  String get label;

  /// What its widget's key ends with (`legend <layer id> <name>`): a
  /// kind's id, `flash`, `hot`.
  String get name;

  /// What the pointer over it tells.
  String get description;

  /// What it shows before its label, in [style].
  Widget icon(DebugStyle style);

  /// Whether [node] (of any layer) is one it stands for; [liveWindow] is
  /// what "Live only" counts as live.
  bool matches(DebugGraphNode node, Duration liveWindow);

  /// The entries of [layer]: its kinds, its flash, its hot outline.
  static List<DebugGraphLegendEntry> of(DebugGraphLayer layer) => [
    for (final kind in layer.kinds) DebugGraphKindEntry(layer, kind),
    if (layer.flashMeaning case final meaning?)
      DebugGraphFlashEntry(layer, meaning),
    if (layer.heatMeaning case final meaning?)
      DebugGraphHotEntry(layer, meaning),
  ];
}

/// The legend entry of a kind of node: its shape in its layer's colour.
final class DebugGraphKindEntry extends DebugGraphLegendEntry {
  /// The entry of [kind] of [layer].
  const DebugGraphKindEntry(super.layer, this.kind);

  /// The kind.
  final DebugGraphKind kind;

  @override
  String get id => 'kind\u0000${kind.id}';

  @override
  String get name => kind.id;

  @override
  String get label => kind.label;

  @override
  String get description => kind.description ?? kind.label;

  @override
  Widget icon(DebugStyle style) => DebugGraphShapeIcon(
    kind.shape,
    color: layer.colorOf(style),
    fill: style.background,
  );

  @override
  bool matches(DebugGraphNode node, Duration liveWindow) =>
      node.layer == layer.id && node.kind == kind.id;
}

/// The legend entry of a layer's flash, `a signal ticked` after a pulse on
/// a link: its nodes that flashed within the live window.
final class DebugGraphFlashEntry extends DebugGraphLegendEntry {
  /// The entry of the flash of [layer], meaning [meaning].
  const DebugGraphFlashEntry(super.layer, this.meaning);

  /// What a flash means.
  final String meaning;

  @override
  String get id => 'flash';

  @override
  String get name => id;

  @override
  String get label => meaning;

  @override
  String get description =>
      'The node flashes in the theme\'s graph-flash and a pulse runs along '
      'its edges: $meaning. Selected: the nodes that did in the last '
      'seconds.';

  @override
  Widget icon(DebugStyle style) => CustomPaint(
    size: const Size(18, 10),
    painter: _PulsePainter(style.graphFlash, style.muted),
  );

  @override
  bool matches(DebugGraphNode node, Duration liveWindow) =>
      node.layer == layer.id && layer.isLive(node, liveWindow);
}

/// The legend entry of a layer's hot outline, `rebuilt 3+ in 5 s`: its
/// nodes that are hot now.
final class DebugGraphHotEntry extends DebugGraphLegendEntry {
  /// The entry of the hot outline of [layer], meaning [meaning].
  const DebugGraphHotEntry(super.layer, this.meaning);

  /// What the outline means.
  final String meaning;

  @override
  String get id => 'hot';

  @override
  String get name => id;

  @override
  String get label => meaning;

  @override
  String get description =>
      'Outlined in the theme\'s graph-hot, with the links between: '
      '$meaning. The pointer over such a node tells why.';

  @override
  Widget icon(DebugStyle style) => CustomPaint(
    size: const Size(18, 10),
    painter: _HotPainter(style.graphHot, style.background),
  );

  @override
  bool matches(DebugGraphNode node, Duration liveWindow) =>
      node.layer == layer.id && layer.heatOf(node) > 0;
}

/// The legend of the application graph, opened over the graph by the
/// toolbar's `Legend`: each layer shown with its colour and its entries
/// ([DebugGraphLegendEntry.of]). A tap selects an entry or unselects it
/// (several may be), `Clear` unselects all; the selection lasts while the
/// app runs, in the view's [memory]. The pointer over an entry (a long
/// press on a touch screen) tells what it is and how many of its nodes
/// [graph] shows, in a line of a fixed height under the entries, so they
/// never move while it changes. Where there is room the entries stand in
/// two columns; the wheel over the legend scrolls only the legend.
class DebugGraphLegend extends StatefulWidget {
  /// The legend of [layers] over [graph].
  const DebugGraphLegend(
    this.layers, {
    required this.graph,
    required this.memory,
    this.liveWindow = const Duration(seconds: 5),
    this.compact = false,
    this.onClose,
    super.key,
  });

  /// The layers shown.
  final List<DebugGraphLayer> layers;

  /// The graph shown, for the counts.
  final DebugGraph graph;

  /// Where the selection is kept.
  final DebugGraphMemory memory;

  /// What "Live only" counts as live: the flash entries' window.
  final Duration liveWindow;

  /// The small look of a console pane.
  final bool compact;

  /// Called by its `×`.
  final VoidCallback? onClose;

  /// The plates of [graph] that one of [selected] stands for, by index (a
  /// plate's own nodes or those merged into it); `null` when [selected] is
  /// empty: nothing is highlighted, nothing dimmed.
  static Set<int>? marksOf(
    DebugGraph graph,
    List<DebugGraphLegendEntry> selected,
    Duration liveWindow,
  ) {
    if (selected.isEmpty) {
      return null;
    }
    bool marks(DebugGraphNode node) =>
        selected.any((entry) => entry.matches(node, liveWindow));
    return {
      for (var i = 0; i < graph.items.length; i++)
        if (graph.items[i].nodes.any(marks) ||
            graph.items[i].aliases.any(marks))
          i,
    };
  }

  /// How many nodes of [graph] [entry] stands for, folded ones counted.
  static int countOf(
    DebugGraph graph,
    DebugGraphLegendEntry entry,
    Duration liveWindow,
  ) {
    var count = 0;
    for (final item in graph.items) {
      for (final nodes in [item.nodes, item.aliases]) {
        for (final node in nodes) {
          if (entry.matches(node, liveWindow)) {
            count++;
          }
        }
      }
    }
    return count;
  }

  @override
  State<DebugGraphLegend> createState() => _DebugGraphLegendState();
}

class _DebugGraphLegendState extends State<DebugGraphLegend> {
  // The entry under the pointer: only the hint line listens, so the
  // entries above it neither rebuild nor move while it changes.
  final ValueNotifier<DebugGraphLegendEntry?> _hovered = ValueNotifier(null);

  // The narrowest the legend shows its entries in two columns at.
  static const _twoColumnsFrom = 240.0;

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  // The wheel over the legend is the legend's: what its list does not take
  // (at an end, or nothing to scroll) goes nowhere, not to the graph under
  // it nor to a list around the view.
  static void _keepWheel(PointerSignalEvent event) =>
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {});

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final compact = widget.compact;
    final text = (compact ? style.code.copyWith(fontSize: 10) : style.text)
        .copyWith(color: style.foreground);
    final memory = widget.memory;
    return Listener(
      onPointerSignal: _keepWheel,
      child: Container(
        key: const ValueKey('debug graph legend'),
        padding: EdgeInsets.all(compact ? 6 : 8),
        decoration: BoxDecoration(
          color: style.background.withValues(alpha: 0.96),
          border: Border.all(color: style.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListenableBuilder(
              listenable: memory,
              builder: (context, _) => Row(
                children: [
                  Expanded(
                    child: Text(
                      'Legend',
                      style: text.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (memory.legend.isNotEmpty)
                    _Link('Clear', style: text, onTap: memory.clearLegend),
                  if (widget.onClose case final close?)
                    _Link('×', style: text, onTap: close),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) => ListenableBuilder(
                    listenable: memory,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final layer in widget.layers)
                          ..._layer(
                            layer,
                            style,
                            text,
                            memory,
                            constraints.maxWidth,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _hint(style, text),
          ],
        ),
      ),
    );
  }

  // What the entry under the pointer is, in a box of two lines whatever it
  // says: the list above keeps its height while the pointer passes.
  Widget _hint(DebugStyle style, TextStyle text) {
    final hint = text.copyWith(color: style.muted);
    final lines = TextPainter(
      text: TextSpan(text: 'Ag', style: hint),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = lines.height * 2;
    lines.dispose();
    return SizedBox(
      height: height,
      child: ClipRect(
        child: ValueListenableBuilder<DebugGraphLegendEntry?>(
          valueListenable: _hovered,
          builder: (context, hovered, _) => Text(
            hovered == null
                ? 'Tap entries to highlight their nodes.'
                : '${DebugGraphLegend.countOf(widget.graph, hovered, widget.liveWindow)} '
                      'on the graph · ${hovered.description}',
            key: const ValueKey('debug graph legend hint'),
            style: hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  List<Widget> _layer(
    DebugGraphLayer layer,
    DebugStyle style,
    TextStyle text,
    DebugGraphMemory memory,
    double width,
  ) {
    // Two columns where there is room: an entry takes half the width, one
    // whose label does not fit there the whole row.
    const spacing = 4.0;
    final column = width.isFinite && width >= _twoColumnsFrom
        ? (width - spacing) / 2
        : width;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: layer.colorOf(style),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              layer.title,
              style: text.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: spacing,
        runSpacing: 2,
        children: [
          for (final entry in DebugGraphLegendEntry.of(layer))
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: column.isFinite ? column : 0,
                maxWidth: width,
              ),
              child: _entry(entry, style, text, memory),
            ),
        ],
      ),
      const SizedBox(height: 4),
    ];
  }

  Widget _entry(
    DebugGraphLegendEntry entry,
    DebugStyle style,
    TextStyle text,
    DebugGraphMemory memory,
  ) {
    final selected = memory.isSelected(entry.key);
    return MouseRegion(
      onEnter: (_) => _hovered.value = entry,
      onExit: (_) {
        if (_hovered.value?.key == entry.key) {
          _hovered.value = null;
        }
      },
      child: GestureDetector(
        key: ValueKey('legend ${entry.layer.id} ${entry.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => memory.toggleLegend(entry.key),
        onLongPress: () => _hovered.value = entry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? style.accent.withValues(alpha: 0.18) : null,
            border: Border.all(
              color: selected ? style.accent : const Color(0x00000000),
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: entry.icon(style),
              ),
              Flexible(
                child: Text(
                  entry.label,
                  style: text.copyWith(
                    color: selected ? style.accent : style.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, {required this.style, required this.onTap});

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(label, style: style),
    ),
  );
}

/// A kind's [shape], small, for the legend.
class DebugGraphShapeIcon extends StatelessWidget {
  /// [shape] outlined in [color] over [fill].
  const DebugGraphShapeIcon(
    this.shape, {
    required this.color,
    required this.fill,
    super.key,
  });

  /// The shape.
  final DebugGraphShape shape;

  /// Its outline's colour: its layer's.
  final Color color;

  /// What it is filled with.
  final Color fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(18, 10),
    painter: _ShapePainter(shape, color, fill),
  );
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.shape, this.color, this.fill);

  final DebugGraphShape shape;
  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final path = DebugGraphScene.outline(shape, rect, compact: true);
    canvas
      ..drawPath(path, Paint()..color = Color.lerp(fill, color, 0.2)!)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color,
      );
    if (shape == DebugGraphShape.tagged) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, 2.5, rect.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.fill != fill;
}

// A link with a pulse on it.
class _PulsePainter extends CustomPainter {
  const _PulsePainter(this.flash, this.line);

  final Color flash;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas
      ..drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..strokeWidth = 1.2
          ..color = line,
      )
      ..drawCircle(
        Offset(size.width * 0.6, y),
        4,
        Paint()..color = flash.withValues(alpha: 0.3),
      )
      ..drawCircle(Offset(size.width * 0.6, y), 2.2, Paint()..color = flash);
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.flash != flash || oldDelegate.line != line;
}

// A plate outlined as a hot one is.
class _HotPainter extends CustomPainter {
  const _HotPainter(this.hot, this.fill);

  final Color hot;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      const Radius.circular(3),
    );
    canvas
      ..drawRRect(rect, Paint()..color = fill)
      ..drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = hot,
      );
  }

  @override
  bool shouldRepaint(_HotPainter oldDelegate) =>
      oldDelegate.hot != hot || oldDelegate.fill != fill;
}
