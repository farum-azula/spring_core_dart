import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// Handles a keyboard shortcut's [action]: a bean that implements it is
/// one of the action's handlers, like a `@Shortcut` method. It may
/// implement `Ordered` for its place among them.
///
/// ```dart
/// @Component()
/// class ThemeToggle implements ShortcutHandler {
///   ThemeToggle(this.selection);
///   final ThemeSelection selection;
///
///   @override
///   String get action => 'theme.toggle';
///
///   @override
///   bool handle(ShortcutInvocation invocation) {
///     selection.toggle();
///     return true;
///   }
/// }
/// ```
abstract interface class ShortcutHandler {
  /// The action handled (`theme.toggle`).
  String get action;

  /// Handles [invocation]; `false` passes it on to the next handler.
  bool handle(ShortcutInvocation invocation);
}
