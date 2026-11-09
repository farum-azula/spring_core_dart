import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// The frame meter over the running app, turned on and off (the
/// `debugFrameMeter` bean): by the action `debug.frame-meter`, by default
/// ⌘⇧X (Ctrl+Shift+X) or five quick taps and a sixth held two seconds;
/// `spring.flutter.shortcuts.debug.frame-meter` names other keys or taps.
/// The debug panel's Frames tab switches it too.
///
/// It is in the app only when `spring.flutter.debug.frame-meter.enabled`
/// lets the build put it there, with the debug panel or without it.
class DebugFrameMeter extends ChangeNotifier
    implements KeyedShortcutHandler, DebugOverlay {
  /// Off, in the corner [position] (`spring.flutter.frame-meter.position`
  /// in the app).
  DebugFrameMeter({this._position = FrameMeterPosition.topRight});

  bool _on = false;
  FrameMeterPosition _position;

  @override
  String get action => 'debug.frame-meter';

  @override
  List<String> get keys => const ['primary+shift+x', 'taps:5+hold:2s'];

  @override
  bool handle(ShortcutInvocation invocation) {
    on = !on;
    return true;
  }

  /// Whether the meter shows.
  bool get on => _on;

  set on(bool value) {
    if (value != _on) {
      _on = value;
      notifyListeners();
    }
  }

  @override
  String get id => 'frame-meter';

  @override
  String get title => 'Frames';

  @override
  DebugOverlayCorner get corner => _position;

  @override
  int get order => 0;

  @override
  bool get shown => on;

  @override
  set shown(bool value) => on = value;

  @override
  Size get size => const Size(170, 64);

  @override
  Widget build(BuildContext context) => const FrameMeterGauge();

  /// The corner the meter shows in.
  FrameMeterPosition get position => _position;

  /// Moves the meter to [value].
  set position(FrameMeterPosition value) {
    if (value != _position) {
      _position = value;
      notifyListeners();
    }
  }
}

/// Puts the frame meter of [meter] over the app when it is on.
final class DebugFrameMeterCustomizer implements FlutterAppCustomizer {
  /// The meter's switch [meter].
  const DebugFrameMeterCustomizer(this.meter);

  /// The switch.
  final DebugFrameMeter meter;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => ListenableBuilder(
      listenable: meter,
      child: inner == null ? child! : inner(context, child),
      builder: (context, app) =>
          meter.on ? FrameMeter(position: meter.position, child: app!) : app!,
    );
  }
}
