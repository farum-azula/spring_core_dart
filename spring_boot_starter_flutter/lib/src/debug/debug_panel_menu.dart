import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The sections of the debug panel as the menu lists them: groups in the
/// order of their first section, each with its sections in order, and the
/// sections without a group last, under `Other`; with no group at all,
/// one list without a header.
final class DebugPanelMenuGroups {
  /// The groups of [sections], in the order of the beans.
  factory DebugPanelMenuGroups.of(List<DebugPanelSection> sections) {
    final byName = <String?, List<int>>{};
    for (final (index, section) in sections.indexed) {
      byName.putIfAbsent(_groupOf(section), () => []).add(index);
    }
    final ungrouped = byName.remove(null);
    return DebugPanelMenuGroups._([
      for (final MapEntry(:key, :value) in byName.entries) (key, value),
      if (ungrouped != null) (byName.isEmpty ? null : other, ungrouped),
    ]);
  }

  const DebugPanelMenuGroups._(this.groups);

  /// The header of the sections without a group, when others have one.
  static const other = 'Other';

  /// Each group's header (`null`: none) and the indexes of its sections.
  final List<(String?, List<int>)> groups;

  /// The indexes of the sections as the menu shows them, top to bottom.
  List<int> get order => [for (final (_, indexes) in groups) ...indexes];

  static String? _groupOf(DebugPanelSection section) => switch (section) {
    GroupedDebugPanelSection(:final group) => group,
    _ => null,
  };
}

/// The debug panel's menu: the sections listed top to bottom under their
/// groups' headers, the one shown [selected] in the theme's accent. A
/// tap calls [onSelected] with a section's index; with the menu focused
/// (after a tap), the up and down arrows move the selection.
class DebugPanelMenu extends StatefulWidget {
  /// The menu of [sections], [width] wide.
  const DebugPanelMenu({
    required this.sections,
    required this.selected,
    required this.onSelected,
    this.width = defaultWidth,
    super.key,
  });

  /// How wide the menu is when no width is given.
  static const double defaultWidth = 200;

  /// The sections, in the order of the beans.
  final List<DebugPanelSection> sections;

  /// The index of the section shown.
  final int selected;

  /// Called with the index of the section picked.
  final ValueChanged<int> onSelected;

  /// How wide it is.
  final double width;

  @override
  State<DebugPanelMenu> createState() => _DebugPanelMenuState();
}

class _DebugPanelMenuState extends State<DebugPanelMenu> {
  final _focus = FocusNode(debugLabel: 'debug panel menu');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(List<int> order, KeyEvent event) {
    if (event is KeyUpEvent || order.isEmpty) {
      return KeyEventResult.ignored;
    }
    final step = _steps[event.logicalKey];
    if (step == null) {
      return KeyEventResult.ignored;
    }
    final at = order.indexOf(widget.selected);
    widget.onSelected(order[(at + step).clamp(0, order.length - 1)]);
    return KeyEventResult.handled;
  }

  static final _steps = {
    LogicalKeyboardKey.arrowDown: 1,
    LogicalKeyboardKey.arrowUp: -1,
  };

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final groups = DebugPanelMenuGroups.of(widget.sections);
    final order = groups.order;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) => _onKey(order, event),
      child: SizedBox(
        width: widget.width,
        child: ListView(
          padding: const EdgeInsets.only(right: 8),
          children: [
            for (final (header, indexes) in groups.groups) ...[
              if (header != null) _MenuHeader(header, style: style),
              for (final index in indexes)
                _MenuItem(
                  widget.sections[index].title,
                  selected: index == widget.selected,
                  style: style,
                  onTap: () {
                    _focus.requestFocus();
                    widget.onSelected(index);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader(this.label, {required this.style});

  final String label;
  final DebugStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
    child: Text(label, style: style.text.copyWith(color: style.muted)),
  );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem(
    this.label, {
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final DebugStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? style.accent.withValues(alpha: 0.18) : null,
          border: Border(
            left: BorderSide(
              color: selected ? style.accent : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: style.text.copyWith(
            color: selected ? style.accent : style.foreground,
          ),
        ),
      ),
    ),
  );
}

/// The button of the panel's header that opens the menu on a phone:
/// three lines in the theme's text colour.
class DebugPanelMenuButton extends StatelessWidget {
  /// A button calling [onTap].
  const DebugPanelMenuButton({required this.onTap, super.key});

  /// Called when tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final line = Container(width: 18, height: 2, color: style.foreground);
    return Semantics(
      button: true,
      label: 'Menu',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [line, line, line],
          ),
        ),
      ),
    );
  }
}
