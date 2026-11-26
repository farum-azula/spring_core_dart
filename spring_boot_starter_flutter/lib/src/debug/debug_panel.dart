import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_motion.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// The debug panel's state (the `debugPanel` bean): whether it is open,
/// and the tab shown, kept while it is closed: it opens again where it
/// was left.
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
  int _tab = 0;

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

  /// The index of the tab shown, among the sections in their order.
  int get tab => _tab;

  /// Shows the tab of index [value].
  set tab(int value) {
    if (value != _tab) {
      _tab = value;
      notifyListeners();
    }
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
///
/// The panel lists the sections in a menu: on a wide screen a side menu
/// always open, on a phone a drawer opened from the header. A section
/// that implements [GroupedDebugPanelSection] is listed under its group's
/// header; one that does not is listed under `Other` when others have a
/// group, and the menu has no headers when none has.
abstract interface class DebugPanelSection {
  /// The section's title in the menu.
  String get title;

  /// The section's content, right of the menu or under the header.
  Widget build(BuildContext context);
}

/// A [DebugPanelSection] listed under a group of the panel's menu: the
/// groups follow each other in the order of their first section, and a
/// group lists its sections in their order. A section that only
/// implements [DebugPanelSection] keeps working, under `Other`.
///
/// The starter's groups are `Logs & state`, `Performance`, `App` and
/// `Tools`; a section of an app may join one of them or name its own.
///
/// ```dart
/// @Component()
/// class CartSection implements GroupedDebugPanelSection {
///   @override
///   String get group => 'App';
///   ...
/// }
/// ```
abstract interface class GroupedDebugPanelSection implements DebugPanelSection {
  /// The header the section is listed under.
  String get group;
}
