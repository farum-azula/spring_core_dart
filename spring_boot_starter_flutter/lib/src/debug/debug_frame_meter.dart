import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// The frame meter over the running app, compact (one line, `60 (120
/// 3D)`, over the strip of bars), turned on and off (the
/// `debugFrameMeter` bean): by the action `debug.frame-meter`, by default
/// ⌘⇧X (Ctrl+Shift+X) or five quick taps and a sixth held two seconds;
/// `spring.flutter.shortcuts.debug.frame-meter` names other keys or taps.
/// The debug panel's Frames tab switches it too. Over the debug overlays
/// it is drawn in the colours the debug theme sets (`DebugStyle.meter`),
/// the app theme's `frame-meter` look for the rest.
///
/// It is in the app only when `spring.flutter.debug.frame-meter.enabled`
/// lets the build put it there, with the debug panel or without it.
class DebugFrameMeter extends ChangeNotifier
    implements KeyedShortcutHandler, DebugOverlay {
  /// Off, in the corner [position] (`spring.flutter.frame-meter.position`
  /// in the app).
  DebugFrameMeter({this._position = DebugCorner.topRight});

  bool _on = false;
  DebugCorner _position;

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
  DebugCorner get corner => _position;

  @override
  int get order => 0;

  @override
  bool get shown => on;

  @override
  set shown(bool value) => on = value;

  @override
  Size get size => const Size(110, 34);

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return FrameMeterGauge(
      look: style.meter,
      number: style.meterNumber,
      textStyle: style.meterText,
    );
  }

  /// The corner the meter shows in.
  DebugCorner get position => _position;

  /// Moves the meter to [value].
  set position(DebugCorner value) {
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
