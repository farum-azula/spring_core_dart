import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_assembly.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_memory.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_view.dart';

/// A debug console pane of the application graph ([DebugGraphView],
/// compact): the console's `graph` pane (`debugGraphPane`, every layer the
/// build has), or a starter's pane preset to its own layer (the signals
/// starter's `signals`). Nearly opaque, so the graph reads over any page.
///
/// Its layers collect only while it shows: hidden, it is not built and
/// nothing listens. The `graph` pane is in the build only when
/// `spring.flutter.debug.console.panes` names `graph` or holds `*`, with a
/// layer in the build (`spring.flutter.debug.graph.layers`).
class DebugGraphPane extends DebugConsolePane {
  /// The pane over [layers], called [title], starting with [settings].
  DebugGraphPane(
    List<DebugGraphLayer> layers, {
    this.title = 'Graph',
    this.settings = const DebugGraphSettings(),
  }) : layers = [...layers]..sort((a, b) => a.order.compareTo(b.order));

  /// The layers, by their order.
  final List<DebugGraphLayer> layers;

  @override
  final String title;

  /// What it shows at the start.
  final DebugGraphSettings settings;

  /// What the pane's graph keeps while the app runs (settings, place,
  /// legend, cards): each pane its own, apart from the panel's Graph tab.
  final DebugGraphMemory memory = DebugGraphMemory();

  @override
  double get minHeight => DebugConsoleView.lineHeight * 5;

  @override
  double get initialHeight => DebugConsoleView.lineHeight * 14;

  /// Starts every layer while the pane shows; the view starts them too
  /// while it is built, and a layer counts its users.
  @override
  void Function() start() {
    final stops = [for (final layer in layers) layer.start()];
    return () {
      for (final stop in stops) {
        stop();
      }
    };
  }

  @override
  Widget build(BuildContext context, DebugConsole console) => DebugGraphView(
    layers: layers,
    compact: true,
    settings: settings,
    memory: memory,
    fit: DebugGraphFit.width,
  );
}
