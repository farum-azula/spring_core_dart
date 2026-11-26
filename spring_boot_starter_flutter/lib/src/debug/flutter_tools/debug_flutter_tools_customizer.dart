import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/debug_flutter_tools.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// Puts the Flutter tools that draw ([DebugFlutterTools.layers]) around
/// the app, inside the debug panel and the overlays: the inspector selects
/// the app's widgets, never the panel's. Every layer off, the app is as it
/// was.
///
/// In a debug build it keeps `WidgetsApp` from adding its own inspector
/// over the whole app (`debugExcludeRootWidgetInspector`): the inspector
/// is this one, for the tab and for DevTools alike.
final class DebugFlutterToolsCustomizer
    implements FlutterAppCustomizer, Ordered {
  /// The layers of [tools].
  DebugFlutterToolsCustomizer(this.tools);

  /// The tools.
  final DebugFlutterTools tools;

  // The app keeps its state while a layer comes or goes around it.
  final GlobalKey _app = GlobalKey(debugLabel: 'DebugFlutterTools.app');

  // The first customizer is the innermost: around the app's pages, under
  // the overlays and the panel.
  @override
  int get order => Ordered.highestPrecedence + 1000;

  @override
  void customize(FlutterAppSettings app) {
    WidgetsBinding.instance.debugExcludeRootWidgetInspector = tools.mode.debug;
    final inner = app.builder;
    app.builder = (context, child) => ListenableBuilder(
      listenable: tools.changes,
      child: KeyedSubtree(
        key: _app,
        child: inner == null ? child! : inner(context, child),
      ),
      builder: (context, app) => tools.layers
          .where((layer) => layer.on && tools.unavailable(layer) == null)
          .fold(app!, (app, layer) => layer.wrap(app)),
    );
  }
}
