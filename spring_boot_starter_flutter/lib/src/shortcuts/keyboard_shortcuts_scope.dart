import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_intent.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/touch_pattern.dart';

/// Listens for the app's configured shortcuts ([KeyboardShortcuts]), keys
/// and touch patterns, and runs their handlers. The starter puts it around the app's navigator;
/// an app with its own `MaterialApp` puts it in the `builder`.
class KeyboardShortcutsScope extends StatelessWidget {
  /// Listens for [shortcuts] above [child].
  const KeyboardShortcutsScope({
    required this.shortcuts,
    required this.child,
    super.key,
  });

  /// The app's shortcuts.
  final KeyboardShortcuts shortcuts;

  /// The app below.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bindings = shortcuts.bindings(defaultTargetPlatform);
    if (bindings.isEmpty) {
      return child;
    }
    final gestures = {
      for (final MapEntry(key: action, value: keys) in bindings.entries)
        if (keys.whereType<ShortcutGesture>().isNotEmpty)
          action: [
            for (final key in keys.whereType<ShortcutGesture>()) key.pattern,
          ],
    };
    Widget content = Shortcuts(
      shortcuts: {
        for (final MapEntry(key: action, value: keys) in bindings.entries)
          for (final key in keys)
            if (key is! ShortcutGesture)
              key.activator: ShortcutIntent.of(action, key.activator),
      },
      child: Actions(
        actions: {ShortcutIntent: _Dispatch(shortcuts)},
        child: child,
      ),
    );
    if (gestures.isNotEmpty) {
      content = TouchPatternDetector(
        patterns: gestures,
        onMatch: (action, context) {
          if (shortcuts.handles(action)) {
            shortcuts.dispatch(ShortcutInvocation(action, context));
          }
        },
        child: content,
      );
    }
    return content;
  }
}

final class _Dispatch extends ContextAction<ShortcutIntent> {
  _Dispatch(this.shortcuts);

  final KeyboardShortcuts shortcuts;

  @override
  bool isEnabled(ShortcutIntent intent, [BuildContext? context]) =>
      intent.allowed && shortcuts.handles(intent.action);

  @override
  bool invoke(ShortcutIntent intent, [BuildContext? context]) =>
      shortcuts.dispatch(
        ShortcutInvocation(
          intent.action,
          FocusManager.instance.primaryFocus?.context ?? context,
        ),
      );
}
