import 'package:flutter/widgets.dart';

/// The intent of a configured shortcut: the [action] to run.
final class ShortcutIntent extends Intent {
  /// The intent of [action]; [whileTyping] when its keys (with Ctrl, ⌘ or
  /// Alt) cannot be meant as text.
  const ShortcutIntent(this.action, {this.whileTyping = true});

  /// The intent of [action] pressed with [activator].
  factory ShortcutIntent.of(String action, ShortcutActivator activator) =>
      ShortcutIntent(
        action,
        whileTyping: switch (activator) {
          SingleActivator(:final control, :final meta, :final alt) =>
            control || meta || alt,
          _ => false,
        },
      );

  /// The action's name.
  final String action;

  /// Whether the keys work in a text field: a plain key (`slash`,
  /// `char:?`) types there instead.
  final bool whileTyping;

  /// Whether the intent may run now: not a plain key while a text field
  /// has the focus.
  bool get allowed {
    if (whileTyping) {
      return true;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused == null ||
        (focused.widget is! EditableText &&
            focused.findAncestorWidgetOfExactType<EditableText>() == null);
  }
}
