import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// The action `debug.graph.fit` (the bean `debugGraphFit`): fits every
/// application graph on the screen as its Fit button does, the debug
/// panel's Graph tab and the console's graph panes. ⌘⇧Z by default (Ctrl
/// with Shift and Z elsewhere); `spring.flutter.shortcuts.debug.graph.fit`
/// names other keys. A view listens while it is built; with none on the
/// screen the press does nothing.
final class DebugGraphFitAction extends ChangeNotifier
    implements KeyedShortcutHandler {
  @override
  String get action => 'debug.graph.fit';

  @override
  List<String> get keys => const ['primary+shift+z'];

  @override
  bool handle(ShortcutInvocation invocation) {
    if (!hasListeners) {
      return false;
    }
    notifyListeners();
    return true;
  }
}
