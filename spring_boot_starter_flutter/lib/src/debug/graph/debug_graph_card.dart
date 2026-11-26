import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_assembly.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';

/// The card of a tapped plate, beside it over the graph (several may be
/// open, one per plate): closed, one short line, its title and the first
/// values its layer tells (`shown · Map(0) · 1 write · 0 reads/5s`); a
/// tap opens it into labelled rows, wrapped, with the chips that fold it
/// back or collapse its branch or lane, another closes it into its line.
/// Lines of a section ([DebugGraphDetail.section], a widget's
/// `properties`) stand in a titled block after the others; a shortened
/// value opens on a tap. `×` closes the card.
class DebugGraphDetails extends StatelessWidget {
  /// The card of plate [index] of [graph].
  const DebugGraphDetails(
    this.graph,
    this.index, {
    required this.settings,
    required this.onSettings,
    this.compact = false,
    this.expanded = false,
    this.selected = false,
    this.onExpand,
    this.onClose,
    this.onLink,
    super.key,
  });

  /// The graph shown.
  final DebugGraph graph;

  /// The plate tapped.
  final int index;

  /// What the view shows.
  final DebugGraphSettings settings;

  /// Called with the settings a chip makes.
  final ValueChanged<DebugGraphSettings> onSettings;

  /// The small look of a console pane.
  final bool compact;

  /// Opened into labelled rows.
  final bool expanded;

  /// Whether its plate's chain is highlighted: its border in the accent.
  final bool selected;

  /// Called by a tap on it: open it, or close it into its line.
  final VoidCallback? onExpand;

  /// Called by its `×`.
  final VoidCallback? onClose;

  /// Called by a tap on a row a line lists ([DebugGraphDetail.links]) whose
  /// node is on the graph.
  final ValueChanged<DebugGraphDetailLink>? onLink;

  /// Whether the node [id] is on [graph].
  static bool shows(DebugGraph graph, String id) => graph.items.any(
    (item) => item.nodes.any((node) => node.id == id),
  );

  /// How many values its closed line tells at most.
  static const summaryValues = 3;

  /// The lines of plate [index] of [graph]: its layer's lines of its node,
  /// or the nodes folded in it.
  static List<DebugGraphDetail> linesOf(DebugGraph graph, int index) {
    final item = graph.items[index];
    final layer = graph.layers.where((layer) => layer.id == item.layer);
    if (item.nodes.length > 1) {
      return [
        DebugGraphDetail('folded', '${item.nodes.length} nodes'),
        DebugGraphDetail(
          'nodes',
          item.nodes.take(8).map((node) => node.label).join(', ') +
              (item.nodes.length > 8 ? ', …' : ''),
        ),
      ];
    }
    List<DebugGraphDetail> of(DebugGraphNode node) {
      final layer = graph.layers.where((layer) => layer.id == node.layer);
      return layer.isEmpty ? node.details : layer.first.detailsOf(node);
    }

    final own = layer.isEmpty
        ? item.node.details
        : layer.first.detailsOf(item.node);
    // What another layer tells of the same node (a widget's reads), less
    // the lines its own layer already has.
    String key(DebugGraphDetail line) => '${line.section}\u0000${line.label}';
    final told = {for (final line in own) key(line)};
    return [
      ...own,
      for (final alias in item.aliases)
        for (final line in of(alias))
          if (told.add(key(line))) line,
    ];
  }

  /// [lines] in the order the card shows them: those of no section first,
  /// then each section's, the sections in the order they first come.
  static List<(String?, List<DebugGraphDetail>)> sectionsOf(
    List<DebugGraphDetail> lines,
  ) {
    final sections = <String?, List<DebugGraphDetail>>{null: []};
    for (final line in lines) {
      (sections[line.section] ??= []).add(line);
    }
    return [
      for (final MapEntry(:key, :value) in sections.entries)
        if (value.isNotEmpty) (key, value),
    ];
  }

  /// The closed card's line of [lines]: their first values.
  static String summaryOf(List<DebugGraphDetail> lines) => [
    for (final line in lines.take(summaryValues))
      if (line.value.isNotEmpty) line.value,
  ].join(' · ');

  /// The title of plate [index] of [graph]: its lane's title and its own.
  static String titleOf(DebugGraph graph, int index) {
    final item = graph.items[index];
    final lane = graph.lanes[item.lane];
    return [if (lane.title.isNotEmpty) lane.title, item.label].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = compact ? style.code.copyWith(fontSize: 10) : style.code;
    final lines = linesOf(graph, index);
    final title = titleOf(graph, index);
    final controls = [
      _Glyph(
        '×',
        key: const ValueKey('debug graph card close'),
        style: text.copyWith(color: style.muted),
        onTap: onClose,
      ),
    ];
    final head = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          expanded ? '▾ ' : '▸ ',
          style: text.copyWith(color: style.muted),
        ),
        Flexible(
          child: Text(
            title,
            style: text.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!expanded && lines.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              summaryOf(lines),
              style: text.copyWith(color: style.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        ...controls,
      ],
    );
    return GestureDetector(
      key: const ValueKey('debug graph card'),
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: style.background.withValues(alpha: 0.96),
          border: Border.all(color: selected ? style.accent : style.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: expanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  head,
                  const SizedBox(height: 4),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (section, lines) in sectionsOf(lines)) ...[
                            if (section != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 2,
                                ),
                                child: Text(
                                  section,
                                  style: text.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            for (final (line, key) in _keyed(
                              section,
                              lines,
                            )) ...[
                              _DetailRow(
                                line,
                                key: key,
                                labelWidth: compact ? 64 : 80,
                                style: style,
                                text: text,
                              ),
                              if (line.links.isNotEmpty)
                                _DetailLinks(
                                  line.links,
                                  indent: compact ? 64 : 80,
                                  row: (link) => _linkRow(link, style, text),
                                  style: text.copyWith(color: style.accent),
                                ),
                            ],
                          ],
                          _actions(style, text),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : head,
      ),
    );
  }

  // A row of a line's list: the name, its note muted; on the graph, a tap
  // selects its node, else dimmed with why it is not there.
  Widget _linkRow(DebugGraphDetailLink link, DebugStyle style, TextStyle text) {
    final target = link.target;
    final shown = target != null && shows(graph, target);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: shown ? () => onLink?.call(link) : null,
      child: _Hover(
        tooltip: link.tooltip,
        style: text.copyWith(color: style.muted, fontSize: 9),
        indent: compact ? 64 : 80,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: link.label,
                style: text.copyWith(
                  color: shown ? style.accent : style.muted,
                ),
              ),
              if (link.note case final note?)
                TextSpan(
                  text: '  $note',
                  style: text.copyWith(color: style.muted),
                ),
              if (!shown)
                TextSpan(
                  text: '  · ${link.hidden ?? 'not shown'}',
                  style: text.copyWith(
                    color: style.muted.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(DebugStyle style, TextStyle text) {
    final item = graph.items[index];
    final fold = item.fold;
    final lanes =
        graph.layers
            .where((layer) => layer.id == item.layer)
            .firstOrNull
            ?.lanes ??
        true;
    final chips = <(String, DebugGraphSettings Function())>[
      if (fold != null && !fold.folded)
        (fold.closeLabel, () => fold.close(settings)),
      if (!item.folded &&
          !lanes &&
          graph.links.any(
            (link) =>
                link.from == index && graph.items[link.to].layer == item.layer,
          ))
        (
          'collapse branch',
          () => settings.copyWith(
            collapsed: DebugGraphSettings.toggled(
              settings.collapsed,
              DebugGraphBranchFold.keyOf(item.key),
            ),
          ),
        ),
    ];
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final (label, settings) in chips)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSettings(settings()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: style.line),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(label, style: text.copyWith(color: style.accent)),
              ),
            ),
        ],
      ),
    );
  }
}

// The rows of [section] with their keys: the section, the label and how
// many rows of that label came before (a label may repeat).
List<(DebugGraphDetail, Key)> _keyed(
  String? section,
  List<DebugGraphDetail> lines,
) {
  final seen = <String, int>{};
  return [
    for (final line in lines)
      (
        line,
        ValueKey((
          section,
          line.label,
          seen[line.label] = (seen[line.label] ?? -1) + 1,
        )),
      ),
  ];
}

// A labelled row of the open card, keyed by its section and label so an
// opened row stays with its row when the rows change; one whose value is
// shortened opens on a tap into the whole of it ([DebugGraphDetail.more]),
// told as it is at each build, and closes on another.
class _DetailRow extends StatefulWidget {
  const _DetailRow(
    this.line, {
    required this.labelWidth,
    required this.style,
    required this.text,
    super.key,
  });

  final DebugGraphDetail line;
  final double labelWidth;
  final DebugStyle style;
  final TextStyle text;

  @override
  State<_DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<_DetailRow> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final style = widget.style;
    final text = widget.text;
    final more = line.more;
    final opens = more != null;
    final whole = _open && more != null ? more() : null;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: widget.labelWidth,
            child: Text(line.label, style: text.copyWith(color: style.muted)),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (opens)
                    TextSpan(
                      text: whole == null ? '▸ ' : '▾ ',
                      style: text.copyWith(color: style.muted),
                    ),
                  TextSpan(text: whole ?? line.value),
                ],
              ),
              style: text,
            ),
          ),
        ],
      ),
    );
    return opens
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: row,
          )
        : row;
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.label, {required this.style, this.onTap, super.key});

  final String label;
  final TextStyle style;
  final VoidCallback? onTap;

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

/// Where a card goes beside the plate at [target] (in the graph's room):
/// right of it, else left, else under it; inside the room, at most
/// [maxWidth] wide.
class DebugGraphCardPlacement extends SingleChildLayoutDelegate {
  /// The placement beside [target].
  const DebugGraphCardPlacement(this.target, {this.maxWidth = 300});

  /// The plate's rectangle in the room.
  final Rect target;

  /// The widest a card is.
  final double maxWidth;

  /// The room between the plate and the card.
  static const gap = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, math.min(maxWidth, constraints.maxWidth - gap)),
          math.max(0, constraints.maxHeight * 0.7),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = target.right + gap;
    var y = target.top;
    if (x + childSize.width > size.width) {
      x = target.left - gap - childSize.width;
      if (x < 0) {
        x = target.left;
        y = target.bottom + gap / 2;
      }
    }
    return Offset(
      x.clamp(0, math.max(0, size.width - childSize.width)).toDouble(),
      y.clamp(0, math.max(0, size.height - childSize.height)).toDouble(),
    );
  }

  @override
  bool shouldRelayout(DebugGraphCardPlacement oldDelegate) =>
      oldDelegate.target != target || oldDelegate.maxWidth != maxWidth;
}

// The rows of a line's list: the first [_shown], then "N more", a tap on
// which shows them all.
class _DetailLinks extends StatefulWidget {
  const _DetailLinks(
    this.links, {
    required this.indent,
    required this.row,
    required this.style,
  });

  final List<DebugGraphDetailLink> links;
  final double indent;
  final Widget Function(DebugGraphDetailLink link) row;
  final TextStyle style;

  @override
  State<_DetailLinks> createState() => _DetailLinksState();
}

class _DetailLinksState extends State<_DetailLinks> {
  static const _shown = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final links = widget.links;
    final cut = !_all && links.length > _shown + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final link in cut ? links.take(_shown) : links) widget.row(link),
        if (cut)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: EdgeInsets.only(left: widget.indent, bottom: 2),
              child: Text(
                '${links.length - _shown} more…',
                style: widget.style,
              ),
            ),
          ),
      ],
    );
  }
}

// [child] at [indent], with [tooltip] (the whole of a shortened name)
// under it while the pointer is over it.
class _Hover extends StatefulWidget {
  const _Hover({
    required this.child,
    required this.indent,
    required this.style,
    this.tooltip,
  });

  final Widget child;
  final double indent;
  final TextStyle style;
  final String? tooltip;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final tooltip = widget.tooltip;
    final body = Padding(
      padding: EdgeInsets.only(left: widget.indent, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.child,
          if (_over && tooltip != null) Text(tooltip, style: widget.style),
        ],
      ),
    );
    return tooltip == null
        ? body
        : MouseRegion(
            onEnter: (_) => setState(() => _over = true),
            onExit: (_) => setState(() => _over = false),
            child: body,
          );
  }
}
