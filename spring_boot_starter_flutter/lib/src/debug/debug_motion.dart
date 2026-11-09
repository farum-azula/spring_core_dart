import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// Every animation of the running app on, or off as the device's "reduce
/// motion" turns it off (the `debugMotion` bean): by the action
/// `debug.motion`, by default ⌘⇧M (Ctrl+Shift+M);
/// `spring.flutter.shortcuts.debug.motion` names other keys or taps. The
/// debug panel's Motion tab switches it too.
///
/// It is in the app only when `spring.flutter.debug.motion.enabled` lets
/// the build put it there, with the debug panel or without it.
class DebugMotion extends ChangeNotifier implements KeyedShortcutHandler {
  bool _animations = true;

  @override
  String get action => 'debug.motion';

  @override
  List<String> get keys => const ['primary+shift+m'];

  @override
  bool handle(ShortcutInvocation invocation) {
    animations = !animations;
    return true;
  }

  /// Whether the app moves: `false` makes every animation instant.
  bool get animations => _animations;

  set animations(bool value) {
    if (value != _animations) {
      _animations = value;
      notifyListeners();
    }
  }
}

/// Turns the app's animations off (`MediaQuery.disableAnimations`) while
/// [motion] says so.
final class DebugMotionCustomizer implements FlutterAppCustomizer {
  /// The switch [motion].
  const DebugMotionCustomizer(this.motion);

  /// The switch.
  final DebugMotion motion;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => ListenableBuilder(
      listenable: motion,
      child: inner == null ? child! : inner(context, child),
      builder: (context, app) => motion.animations
          ? app!
          : MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: true),
              child: app!,
            ),
    );
  }
}
