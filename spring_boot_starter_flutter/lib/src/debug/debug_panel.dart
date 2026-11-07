import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// The debug panel's state (the `debugPanel` bean): whether it is open,
/// and the switches it sets for the running app, such as the frame meter.
/// The action `debug.open` toggles it: by default ⌘⇧D (Ctrl+Shift+D) or
/// four quick taps and a fifth held three seconds, on every platform;
/// `spring.flutter.shortcuts.debug.open` names other keys or taps.
///
/// The panel is in the app only when `spring.flutter.debug.enabled` lets
/// the build put it there; see [DebugPanelSection] for its sections.
class DebugPanel extends ChangeNotifier implements KeyedShortcutHandler {
  bool _open = false;
  bool _frameMeter = false;
  FrameMeterPosition _position = FrameMeterPosition.topRight;

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

  /// Whether the frame meter shows over the app.
  bool get frameMeter => _frameMeter;

  set frameMeter(bool value) {
    if (value != _frameMeter) {
      _frameMeter = value;
      notifyListeners();
    }
  }

  /// The corner the frame meter shows in.
  FrameMeterPosition get frameMeterPosition => _position;

  set frameMeterPosition(FrameMeterPosition value) {
    if (value != _position) {
      _position = value;
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
