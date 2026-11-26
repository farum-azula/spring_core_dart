import 'package:flutter/scheduler.dart' as scheduler;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/flutter_tool_switches.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/flutter_tools_mode.dart';

/// Flutter's own debug tools in the running app (the `debugFlutterTools`
/// bean), switched from the debug panel's Flutter tab: the widget
/// inspector, the performance overlay, the semantics debugger, the
/// `debugPaint*` flags and slow animations (`timeDilation`). A tool stays
/// as it was left while the app runs, the panel closed or not; the tools
/// are turned off when the context closes.
///
/// It is in the app only when `spring.flutter.debug.flutter-tools.enabled`
/// lets the build put it there, and with the debug panel only. Every tool
/// off, it adds nothing to a frame.
class DebugFlutterTools extends ChangeNotifier {
  /// The tools [switches] (by default [defaultFlutterSwitches]) in [mode]
  /// (by default the running build's).
  DebugFlutterTools({
    this.mode = FlutterToolsMode.current,
    List<DebugFlutterSwitch>? switches,
  }) : switches = switches ?? defaultFlutterSwitches();

  /// The build the app runs in.
  final FlutterToolsMode mode;

  /// The switches, in the tab's order.
  final List<DebugFlutterSwitch> switches;

  /// The slow-animation factors offered: `1` is the normal speed.
  static const List<double> dilations = [1, 2, 5, 10];

  /// The switches drawn over or around the app.
  Iterable<DebugFlutterLayer> get layers =>
      switches.whereType<DebugFlutterLayer>();

  /// What, besides this object, changes a switch: the binding's inspector
  /// switch, turned by DevTools or the inspector's own button too.
  late final Listenable changes = Listenable.merge([
    this,
    WidgetsBinding.instance.debugShowWidgetInspectorOverrideNotifier,
  ]);

  /// Why [tool] cannot work in this build, `null` when it can.
  String? unavailable(DebugFlutterSwitch tool) =>
      unmetRequirement(tool.requirements, mode);

  /// Turns [tool] on or off; nothing when this build cannot run it.
  void flip(DebugFlutterSwitch tool, bool on) {
    if (unavailable(tool) != null || tool.on == on) {
      return;
    }
    tool.on = on;
    notifyListeners();
  }

  /// How many times slower the animations run (`timeDilation`).
  double get dilation => scheduler.timeDilation;

  set dilation(double value) {
    if (value != scheduler.timeDilation) {
      scheduler.timeDilation = value;
      notifyListeners();
    }
  }

  /// Turns every tool off and the animations back to their speed.
  void reset() {
    for (final tool in switches) {
      if (unavailable(tool) == null && tool.on) {
        tool.on = false;
      }
    }
    scheduler.timeDilation = 1;
    notifyListeners();
  }
}
