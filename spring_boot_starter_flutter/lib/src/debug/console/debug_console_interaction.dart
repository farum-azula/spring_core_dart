import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The toggle at the right of the debug console's header between its
/// panes passing the pointer through to the app and interacting: a pill
/// that says which they do now ([interacts]; `Interact ⌥` while ⌥, Alt,
/// is [held]), in a box a finger hits ([size] square at least). A tap
/// calls [onToggle].
class DebugConsoleInteractionToggle extends StatelessWidget {
  /// The toggle, interacting by [interacts], [held] while ⌥ makes it.
  const DebugConsoleInteractionToggle({
    required this.interacts,
    required this.held,
    required this.onToggle,
    required this.style,
    super.key,
  });

  /// The least side of the box it takes a tap in.
  static const double size = 44;

  static const _corner = BorderRadius.all(Radius.circular(12));

  /// Whether the panes interact now.
  final bool interacts;

  /// Whether they interact only while ⌥ (Alt) is held.
  final bool held;

  /// Switches the console's interaction.
  final VoidCallback onToggle;

  /// The header's text style.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = DebugStyle.of(context);
    final colour = interacts ? theme.accent : theme.muted;
    final label = interacts
        ? (held ? 'Interact ⌥' : 'Interact')
        : 'Pass-through';
    return Semantics(
      button: true,
      toggled: interacts,
      label: 'Console panes: $label',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('debug-console-interaction'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: size, minHeight: size),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: interacts ? colour.withValues(alpha: 0.2) : null,
                border: Border.all(color: colour),
                borderRadius: _corner,
              ),
              child: Text(
                label,
                key: const ValueKey('debug-console-interaction-label'),
                style: style.copyWith(color: colour),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
