import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';

/// The keys of a shortcut's [action] as the platform writes them: `⌘K` on
/// macOS and iOS, `Ctrl+K` elsewhere; nothing when the action has no
/// keys. It follows `spring.flutter.shortcuts`, so a label never names
/// keys the app does not listen for.
///
/// ```dart
/// Row(children: [Text('Search'), ShortcutLabel('search.open')])
/// ```
class ShortcutLabel extends StatelessWidget {
  /// The label of [action]'s first keys.
  const ShortcutLabel(this.action, {this.style, super.key});

  /// The action's name.
  final String action;

  /// The text's style.
  final TextStyle? style;

  /// The label of [action] in [context]'s app; `null` when it has no keys.
  static String? of(BuildContext context, String action) {
    final keys = SpringScope.of(
      context,
      listen: false,
    ).getBean<KeyboardShortcuts>().keysOf(action, defaultTargetPlatform);
    return keys.isEmpty ? null : keys.first.label(defaultTargetPlatform);
  }

  @override
  Widget build(BuildContext context) {
    final label = of(context, action);
    return label == null ? const SizedBox.shrink() : Text(label, style: style);
  }
}
