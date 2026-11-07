import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// The look of the debug panel, from the active theme (a dark grey panel
/// when there is none): the panel's own widgets and a section's.
@immutable
final class DebugStyle {
  /// The look of the theme above [context].
  factory DebugStyle.of(BuildContext context) {
    final theme = SpringTheme.maybeOf(context);
    final colors = theme?.colorScheme;
    TextStyle style(String name, double size) =>
        theme?.textStyle(name) ?? TextStyle(fontSize: size);
    final foreground = colors?.onSurface ?? const Color(0xFFE6E6E6);
    return DebugStyle._(
      background: (colors?.surface ?? const Color(0xFF16181D)).withValues(
        alpha: 1,
      ),
      foreground: foreground,
      muted: colors?.onSurfaceVariant ?? const Color(0xFF9A9FAA),
      accent: colors?.primary ?? const Color(0xFF4FC3F7),
      warning: colors?.tertiary ?? const Color(0xFFFFC107),
      error: colors?.error ?? const Color(0xFFF44336),
      line: colors?.outlineVariant ?? const Color(0xFF30343C),
      title: style('titlemedium', 16).copyWith(color: foreground),
      text: style('bodysmall', 12).copyWith(color: foreground),
      code: (theme?.textStyle('code') ?? const TextStyle(fontSize: 11))
          .copyWith(color: foreground, fontSize: 11),
    );
  }

  const DebugStyle._({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.warning,
    required this.error,
    required this.line,
    required this.title,
    required this.text,
    required this.code,
  });

  /// The panel's fill.
  final Color background;

  /// The text.
  final Color foreground;

  /// Secondary text.
  final Color muted;

  /// What is selected or on.
  final Color accent;

  /// Warnings.
  final Color warning;

  /// Errors.
  final Color error;

  /// Lines between rows.
  final Color line;

  /// Titles.
  final TextStyle title;

  /// Text.
  final TextStyle text;

  /// Logs, keys and values.
  final TextStyle code;
}

/// A tappable label of the panel: a tab, a filter, a switch.
class DebugChip extends StatelessWidget {
  /// [label], [selected] or not, calling [onTap].
  const DebugChip(
    this.label, {
    required this.onTap,
    this.selected = false,
    super.key,
  });

  /// The label.
  final String label;

  /// Whether it is selected.
  final bool selected;

  /// Called when tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? style.accent.withValues(alpha: 0.18) : null,
          border: Border.all(color: selected ? style.accent : style.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: style.text.copyWith(
            color: selected ? style.accent : style.foreground,
          ),
        ),
      ),
    );
  }
}

/// A one-line filter of a section's rows.
class DebugFilter extends StatefulWidget {
  /// A filter calling [onChanged] with its text.
  const DebugFilter({required this.onChanged, super.key});

  /// Called with the text.
  final ValueChanged<String> onChanged;

  @override
  State<DebugFilter> createState() => _DebugFilterState();
}

class _DebugFilterState extends State<DebugFilter> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: style.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.text.isEmpty
                ? Text('Filter', style: style.text.copyWith(color: style.muted))
                : const SizedBox.shrink(),
          ),
          EditableText(
            controller: _controller,
            focusNode: _focus,
            style: style.text,
            cursorColor: style.accent,
            backgroundCursorColor: style.muted,
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
