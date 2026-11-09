import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_motion.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// The debug panel's state (the `debugPanel` bean): whether it is open.
/// The switches of its tabs are beans of their own, each in the build by
/// its own property: [DebugFrameMeter], [DebugMotion].
/// The action `debug.open` toggles it: by default ⌘⇧D (Ctrl+Shift+D) or
/// four quick taps and a fifth held three seconds, on every platform;
/// `spring.flutter.shortcuts.debug.open` names other keys or taps.
///
/// The panel is in the app only when `spring.flutter.debug.enabled` lets
/// the build put it there; see [DebugPanelSection] for its sections.
class DebugPanel extends ChangeNotifier implements KeyedShortcutHandler {
  bool _open = false;

  @override
  String get action => 'debug.open';

  @override
  List<String> get keys => const ['primary+shift+d', 'taps:4+hold:3s'];

  @override
  bool handle(ShortcutInvocation invocation) {
    toggle();
    return true;
  }

  /// Whether the panel shows.
  bool get isOpen => _open;

  /// Opens the panel, or closes it.
  void toggle() {
    _open = !_open;
    notifyListeners();
  }

  /// Closes the panel.
  void close() {
    if (_open) {
      _open = false;
      notifyListeners();
    }
  }
}

/// A section of the debug panel: a bean of this type is a tab, in the
/// order of the beans (`@Order`, `Ordered`). The starter has the logs, the
/// frames, the configuration, the beans, the themes and the start; an app
/// adds its own.
///
/// ```dart
/// @Component()
/// class CartSection implements DebugPanelSection {
///   CartSection(this.cart);
///   final Cart cart;
///
///   @override
///   String get title => 'Cart';
///
///   @override
///   Widget build(BuildContext context) => Text('${cart.items.length} items');
/// }
/// ```
abstract interface class DebugPanelSection {
  /// The tab's title.
  String get title;

  /// The section's content, below the tabs.
  Widget build(BuildContext context);
}
