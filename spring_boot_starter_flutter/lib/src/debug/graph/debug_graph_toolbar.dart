import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_assembly.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_memory.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';

/// A button of the application graph's toolbar: [label], [selected] or
/// not, a square of [color] before it (a layer's switch, filled while the
/// layer shows), [trailing] after it (`▾` for a menu). [compact]: the
/// console's small look.
class DebugGraphToolButton extends StatelessWidget {
  /// The button [label], calling [onTap].
  const DebugGraphToolButton(
    this.label, {
    required this.onTap,
    this.selected = false,
    this.color,
    this.trailing,
    this.compact = false,
    super.key,
  });

  /// What it says.
  final String label;

  /// Whether it is on.
  final bool selected;

  /// Called on a tap.
  final VoidCallback onTap;

  /// The colour of the square before the label; `null`: none.
  final Color? color;

  /// What follows the label: `▾`.
  final String? trailing;

  /// The small look.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = (compact ? style.code.copyWith(fontSize: 10) : style.text)
        .copyWith(
          color: selected ? style.accent : style.foreground,
          fontWeight: selected && compact ? FontWeight.w600 : null,
        );
    final square = color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? style.accent.withValues(alpha: 0.14) : null,
          border: Border.all(color: selected ? style.accent : style.line),
          borderRadius: BorderRadius.circular(compact ? 3 : 4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (square != null)
              Container(
                width: compact ? 7 : 9,
                height: compact ? 7 : 9,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: selected ? square : null,
                  border: Border.all(color: square, width: 1.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Text(label, style: text),
            if (trailing case final trailing?)
              Text(' $trailing', style: text.copyWith(color: style.muted)),
          ],
        ),
      ),
    );
  }
}

/// A row of a menu of the graph: a checkbox (or, [radio], a radio button)
/// and [label]; a tap calls [onTap].
class DebugGraphCheckRow extends StatelessWidget {
  /// The row [label], [checked] or not.
  const DebugGraphCheckRow(
    this.label, {
    required this.checked,
    required this.onTap,
    this.radio = false,
    this.color,
    this.compact = false,
    this.indent = 0,
    super.key,
  });

  /// What it says.
  final String label;

  /// Whether it is checked.
  final bool checked;

  /// Called on a tap.
  final VoidCallback onTap;

  /// A radio button instead of a checkbox: one of a choice.
  final bool radio;

  /// A square of this colour before the label (a group's layer).
  final Color? color;

  /// The small look.
  final bool compact;

  /// Room before the box.
  final double indent;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = (compact ? style.code.copyWith(fontSize: 10) : style.text)
        .copyWith(color: checked ? style.foreground : style.muted);
    final box = compact ? 9.0 : 11.0;
    final square = color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(4 + indent, 2, 6, 2),
        child: Row(
          children: [
            Container(
              width: box,
              height: box,
              margin: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: checked ? style.accent : style.muted,
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(radio ? box : 2),
              ),
              child: checked
                  ? Container(
                      width: box - 5,
                      height: box - 5,
                      decoration: BoxDecoration(
                        color: style.accent,
                        borderRadius: BorderRadius.circular(radio ? box : 1),
                      ),
                    )
                  : null,
            ),
            if (square != null)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: square,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Flexible(
              child: Text(
                label,
                style: text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An action of the graph's `Options` menu: [label], doing [run] (the
/// engine's `Close all cards`).
@immutable
final class DebugGraphMenuAction {
  /// The action [label].
  const DebugGraphMenuAction(this.label, this.run);

  /// What its row says.
  final String label;

  /// What it does.
  final VoidCallback run;
}

/// A section of the graph's `Options` menu: a [title] (the engine's
/// `Graph`, a layer's title) over its [options], [choices] and [actions].
@immutable
final class DebugGraphOptionSection {
  /// The section [title].
  const DebugGraphOptionSection(
    this.title, {
    this.options = const [],
    this.choices = const [],
    this.actions = const [],
  });

  /// What its heading says.
  final String title;

  /// Its switches, checkboxes.
  final List<DebugGraphOption> options;

  /// Its single choices, a heading and radio rows each.
  final List<DebugGraphChoice> choices;

  /// Its actions, a row each.
  final List<DebugGraphMenuAction> actions;

  /// Whether it has nothing to show.
  bool get isEmpty => options.isEmpty && choices.isEmpty && actions.isEmpty;
}

/// The graph's `Options` menu: each section's heading, its switches as
/// checkboxes and its single choices as radio rows, rendered alike for
/// the engine's and every layer's. A tap calls the option's `onChanged`,
/// then [onChanged].
class DebugGraphOptionsMenu extends StatelessWidget {
  /// The menu of [sections].
  const DebugGraphOptionsMenu(
    this.sections, {
    required this.onChanged,
    this.compact = false,
    super.key,
  });

  /// What it lists; the empty ones are left out.
  final List<DebugGraphOptionSection> sections;

  /// Called after an option changed.
  final VoidCallback onChanged;

  /// The small look.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final heading = (compact ? style.code.copyWith(fontSize: 10) : style.text)
        .copyWith(color: style.muted, fontWeight: FontWeight.w600);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final section in sections)
            if (!section.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                child: Text(section.title, style: heading),
              ),
              for (final option in section.options)
                DebugGraphCheckRow(
                  option.label,
                  checked: option.value,
                  compact: compact,
                  onTap: () {
                    option.onChanged(!option.value);
                    onChanged();
                  },
                ),
              for (final choice in section.choices) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                  child: Text(
                    choice.label,
                    style: heading.copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
                for (final value in choice.choices)
                  DebugGraphCheckRow(
                    value,
                    checked: value == choice.value,
                    radio: true,
                    indent: 8,
                    compact: compact,
                    onTap: () {
                      if (value != choice.value) {
                        choice.onChanged(value);
                        onChanged();
                      }
                    },
                  ),
              ],
              for (final action in section.actions)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    action.run();
                    onChanged();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                    child: Text(
                      action.label,
                      style: heading.copyWith(
                        color: style.accent,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

/// The graph's `Groups` list: a search field (a part of a group's title,
/// any case), `all` first, then the groups chosen last
/// ([DebugGraphMemory.recentGroups]) and the others in the graph's order,
/// each a checkbox. Built lazily, row by row: hundreds of groups scroll
/// smoothly.
class DebugGraphGroupsList extends StatefulWidget {
  /// The list of [lanes], [chosen] checked (none: `all`), each change told
  /// to [onChanged].
  const DebugGraphGroupsList({
    required this.lanes,
    required this.chosen,
    required this.onChanged,
    required this.maxHeight,
    required this.memory,
    this.colorOf,
    this.compact = false,
    super.key,
  });

  /// The groups to choose from.
  final List<DebugGraphLane> lanes;

  /// The groups chosen, by [DebugGraphLane.key]; empty: all.
  final Set<String> chosen;

  /// Called with the groups chosen after a tap.
  final ValueChanged<Set<String>> onChanged;

  /// The most height it takes.
  final double maxHeight;

  /// Where the groups chosen last are kept.
  final DebugGraphMemory memory;

  /// The colour of a group's layer.
  final Color Function(DebugGraphLane lane)? colorOf;

  /// The small look.
  final bool compact;

  @override
  State<DebugGraphGroupsList> createState() => _DebugGraphGroupsListState();
}

class _DebugGraphGroupsListState extends State<DebugGraphGroupsList> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<DebugGraphLane> _ordered() {
    final query = _query.text.trim().toLowerCase();
    final byKey = {for (final lane in widget.lanes) lane.key: lane};
    final recent = [
      for (final key in widget.memory.recentGroups) ?byKey[key],
    ];
    final first = {for (final lane in recent) lane.key};
    return [
      ...recent,
      for (final lane in widget.lanes)
        if (!first.contains(lane.key)) lane,
    ].where((lane) => lane.title.toLowerCase().contains(query)).toList();
  }

  void _toggle(DebugGraphLane lane) {
    widget.memory.choseGroup(lane.key);
    widget.onChanged(DebugGraphSettings.toggled(widget.chosen, lane.key));
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final compact = widget.compact;
    final text = compact ? style.code.copyWith(fontSize: 10) : style.text;
    final row = compact ? 18.0 : 22.0;
    final lanes = _ordered();
    final room = math.max(row, widget.maxHeight - row * 2 - 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: style.line),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Stack(
            children: [
              ListenableBuilder(
                listenable: _query,
                builder: (context, _) => _query.text.isEmpty
                    ? Text(
                        'Search ${widget.lanes.length} groups',
                        style: text.copyWith(color: style.muted),
                      )
                    : const SizedBox.shrink(),
              ),
              EditableText(
                key: const ValueKey('debug graph groups search'),
                controller: _query,
                focusNode: _focus,
                style: text.copyWith(color: style.foreground),
                cursorColor: style.accent,
                backgroundCursorColor: style.muted,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        DebugGraphCheckRow(
          'all',
          checked: widget.chosen.isEmpty,
          compact: compact,
          onTap: () => widget.onChanged(const {}),
        ),
        SizedBox(
          height: math.min(lanes.length * row, room),
          child: ListView.builder(
            itemExtent: row,
            itemCount: lanes.length,
            itemBuilder: (context, index) {
              final lane = lanes[index];
              return DebugGraphCheckRow(
                lane.title,
                key: ValueKey('debug graph group ${lane.key}'),
                checked: widget.chosen.contains(lane.key),
                color: widget.colorOf?.call(lane),
                compact: compact,
                onTap: () => _toggle(lane),
              );
            },
          ),
        ),
      ],
    );
  }
}
