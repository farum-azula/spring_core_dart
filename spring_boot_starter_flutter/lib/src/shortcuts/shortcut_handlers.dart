import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_intent.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// Handles a press of a shortcut on one screen; `false` passes it on.
typedef ShortcutCallback = Object? Function(ShortcutInvocation invocation);

/// Handles shortcuts while the focus is below it: a screen's own actions
/// (`editor.save`), or its own take on an app's action. It is asked
/// before the handlers above it and the app's `@Shortcut` methods; a
/// handler that returns `false`, or an action it does not have, goes on
/// to them. The keys still come from `spring.flutter.shortcuts`.
///
/// ```dart
/// ShortcutHandlers(
///   handlers: {
///     'editor.save': (_) => draft.save(),
///     'search.open': (_) => searchInThisBook(), // instead of the app's
///   },
///   child: EditorPage(draft),
/// )
/// ```
class ShortcutHandlers extends StatelessWidget {
  /// Handles [handlers] for [child].
  const ShortcutHandlers({
    required this.handlers,
    required this.child,
    super.key,
  });

  /// The handlers by action.
  final Map<String, ShortcutCallback> handlers;

  /// The screen.
  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {ShortcutIntent: _Screen(handlers, context)},
    child: child,
  );
}

final class _Screen extends ContextAction<ShortcutIntent> {
  _Screen(this.handlers, this.outer);

  final Map<String, ShortcutCallback> handlers;
  final BuildContext outer;

  Action<ShortcutIntent>? get _next =>
      outer.mounted ? Actions.maybeFind<ShortcutIntent>(outer) : null;

  @override
  bool isEnabled(ShortcutIntent intent, [BuildContext? context]) {
    if (!intent.allowed) {
      return false;
    }
    if (handlers.containsKey(intent.action)) {
      return true;
    }
    return switch (_next) {
      final ContextAction<ShortcutIntent> next => next.isEnabled(
        intent,
        outer,
      ),
      final Action<ShortcutIntent> next => next.isEnabled(intent),
      null => false,
    };
  }

  @override
  Object? invoke(ShortcutIntent intent, [BuildContext? context]) {
    final handler = handlers[intent.action];
    if (handler != null) {
      final handled = handler(
        ShortcutInvocation(
          intent.action,
          FocusManager.instance.primaryFocus?.context ?? context,
        ),
      );
      if (handled != false) {
        return true;
      }
    }
    return outer.mounted ? Actions.maybeInvoke(outer, intent) : null;
  }
}
