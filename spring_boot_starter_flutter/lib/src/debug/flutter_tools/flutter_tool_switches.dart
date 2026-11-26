import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/flutter_tools_mode.dart';

/// A switch of the Flutter tab: one of Flutter's debug tools, on or off
/// for as long as the app runs. Its state is where Flutter keeps it (a
/// `debugPaint*` flag, the binding's inspector), so a tool switched from
/// DevTools shows here too.
abstract interface class DebugFlutterSwitch {
  /// The tool's name.
  String get title;

  /// What it shows.
  String get hint;

  /// What it needs from the build.
  List<FlutterToolRequirement> get requirements;

  /// Whether it is on.
  bool get on;

  /// Turns it on or off.
  set on(bool value);
}

/// A switch drawn over the app or around it while it is on (the
/// performance overlay, the semantics debugger, the inspector).
abstract interface class DebugFlutterLayer implements DebugFlutterSwitch {
  /// [app] with the tool.
  Widget wrap(Widget app);
}

/// Marks every render object of every view to paint again, so a changed
/// paint flag shows at once.
void repaintEverything() {
  void visit(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(visit);
  }

  RendererBinding.instance.renderViews.forEach(visit);
}

/// One of Flutter's debug paint flags (`debugPaintSizeEnabled`, ...), read
/// by [read] and written by [write]; the app repaints when it changes.
/// Debug builds only.
final class PaintFlagSwitch implements DebugFlutterSwitch {
  /// The flag [title] read by [read] and written by [write].
  const PaintFlagSwitch({
    required this.title,
    required this.hint,
    required this.read,
    required this.write,
  });

  @override
  final String title;

  @override
  final String hint;

  /// Reads the flag.
  final bool Function() read;

  /// Writes the flag.
  final void Function(bool value) write;

  @override
  List<FlutterToolRequirement> get requirements => const [
    DebugBuildRequirement(),
  ];

  @override
  bool get on => read();

  @override
  set on(bool value) {
    write(value);
    repaintEverything();
  }
}

/// Flutter's performance overlay (`PerformanceOverlay`) over the top of
/// the app: the raster and UI threads' frame times. Not on the web, whose
/// engine draws none.
final class PerformanceOverlaySwitch implements DebugFlutterLayer {
  bool _on = false;

  @override
  String get title => 'Performance overlay';

  @override
  String get hint => "The raster and UI threads' frame times.";

  @override
  List<FlutterToolRequirement> get requirements => const [
    NotOnWebRequirement(
      'Not on the web: its engine draws no performance overlay; the '
      "frame meter and the browser's profiler measure the frames there.",
    ),
  ];

  @override
  bool get on => _on;

  @override
  set on(bool value) => _on = value;

  @override
  Widget wrap(Widget app) => Stack(
    children: [
      app,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(child: PerformanceOverlay.allEnabled()),
      ),
    ],
  );
}

/// Flutter's semantics debugger (`SemanticsDebugger`) over the app: what
/// a screen reader finds, in place of the app.
final class SemanticsDebuggerSwitch implements DebugFlutterLayer {
  bool _on = false;

  @override
  String get title => 'Semantics debugger';

  @override
  String get hint => 'What a screen reader finds, drawn in place of the app.';

  @override
  List<FlutterToolRequirement> get requirements => const [];

  @override
  bool get on => _on;

  @override
  set on(bool value) => _on = value;

  @override
  Widget wrap(Widget app) => SemanticsDebugger(child: app);
}

/// Flutter's widget inspector (`WidgetInspector`) in select mode: a tap
/// on the app selects the widget under it instead of reaching it. It is
/// the binding's `debugShowWidgetInspectorOverride`, the switch DevTools
/// turns too; the app is wrapped below the debug panel, so the panel
/// stays usable. Debug builds only.
final class WidgetInspectorSwitch implements DebugFlutterLayer {
  /// The switch.
  const WidgetInspectorSwitch();

  ValueNotifier<bool> get _override =>
      WidgetsBinding.instance.debugShowWidgetInspectorOverrideNotifier;

  @override
  String get title => 'Widget inspector';

  @override
  String get hint =>
      'Tap the app to select a widget: its type, size, position and '
      'ancestors show below.';

  @override
  List<FlutterToolRequirement> get requirements => const [
    DebugBuildRequirement(),
  ];

  @override
  bool get on => _override.value;

  @override
  set on(bool value) => _override.value = value;

  @override
  Widget wrap(Widget app) => WidgetInspector(
    tapBehaviorButtonBuilder: null,
    exitWidgetSelectionButtonBuilder: (
      context, {
      required onPressed,
      required semanticsLabel,
      required key,
    }) => _StopSelecting(key: key, label: semanticsLabel, onTap: onPressed),
    moveExitWidgetSelectionButtonBuilder: null,
    child: app,
  );
}

class _StopSelecting extends StatelessWidget {
  const _StopSelecting({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: style.background.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Stop selecting',
            style: style.text.copyWith(fontSize: 12),
          ),
        ),
      ),
    );
  }
}

/// The switches of the Flutter tab, in their order.
List<DebugFlutterSwitch> defaultFlutterSwitches() => [
  const WidgetInspectorSwitch(),
  PerformanceOverlaySwitch(),
  SemanticsDebuggerSwitch(),
  PaintFlagSwitch(
    title: 'Paint size',
    hint: "Each box's size, padding and alignment (debugPaintSizeEnabled).",
    read: () => debugPaintSizeEnabled,
    write: (value) => debugPaintSizeEnabled = value,
  ),
  PaintFlagSwitch(
    title: 'Baselines',
    hint: "Each text's baselines (debugPaintBaselinesEnabled).",
    read: () => debugPaintBaselinesEnabled,
    write: (value) => debugPaintBaselinesEnabled = value,
  ),
  PaintFlagSwitch(
    title: 'Layer borders',
    hint: "Each layer's bounds (debugPaintLayerBordersEnabled).",
    read: () => debugPaintLayerBordersEnabled,
    write: (value) => debugPaintLayerBordersEnabled = value,
  ),
  PaintFlagSwitch(
    title: 'Pointers',
    hint: 'What is hit by a pointer, flashing (debugPaintPointersEnabled).',
    read: () => debugPaintPointersEnabled,
    write: (value) => debugPaintPointersEnabled = value,
  ),
  PaintFlagSwitch(
    title: 'Repaint rainbow',
    hint:
        'Each repaint boundary in a new color when it repaints '
        '(debugRepaintRainbowEnabled).',
    read: () => debugRepaintRainbowEnabled,
    write: (value) => debugRepaintRainbowEnabled = value,
  ),
  PaintFlagSwitch(
    title: 'Invert oversized images',
    hint:
        'Images decoded larger than they are drawn, inverted and flipped '
        '(debugInvertOversizedImages).',
    read: () => debugInvertOversizedImages,
    write: (value) => debugInvertOversizedImages = value,
  ),
];
