import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts_scope.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// Puts the app's [KeyboardShortcuts] around its navigator, inside the
/// app's own `builder`.
final class KeyboardShortcutsCustomizer implements FlutterAppCustomizer {
  /// Installs [shortcuts].
  const KeyboardShortcutsCustomizer(this.shortcuts);

  /// The app's shortcuts.
  final KeyboardShortcuts shortcuts;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => KeyboardShortcutsScope(
      shortcuts: shortcuts,
      child: inner == null ? child! : inner(context, child),
    );
  }
}
