import 'package:flutter/widgets.dart';

/// One press of a shortcut, as its handlers get it.
final class ShortcutInvocation {
  /// The press of [action] in [context].
  const ShortcutInvocation(this.action, this.context);

  /// The action's name (`search.open`).
  final String action;

  /// The focused widget's context, below the app's navigator when a page
  /// has the focus; `null` when nothing has it.
  final BuildContext? context;

  @override
  String toString() => 'ShortcutInvocation($action)';
}
