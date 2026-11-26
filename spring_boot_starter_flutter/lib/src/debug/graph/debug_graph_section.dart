import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_memory.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_view.dart';

/// The debug panel's Graph tab (`debugGraphSection`, under `App`): the
/// application graph of every [DebugGraphLayer] bean the build has, each
/// with its switch above the graph ([DebugGraphView]). In the build only
/// with a layer (`spring.flutter.debug.graph.layers`), the panel and
/// `spring.flutter.debug.graph.enabled`; the layers collect only while the
/// tab shows.
final class DebugGraphSection implements GroupedDebugPanelSection, Ordered {
  /// The tab over [layers].
  DebugGraphSection(List<DebugGraphLayer> layers)
    : layers = [...layers]..sort((a, b) => a.order.compareTo(b.order));

  /// The layers, by their order.
  final List<DebugGraphLayer> layers;

  /// What the tab's graph keeps while the app runs (settings, place,
  /// legend, cards), apart from the console's panes.
  final DebugGraphMemory memory = DebugGraphMemory();

  @override
  String get title => 'Graph';

  @override
  String get group => 'App';

  @override
  int get order => 35;

  @override
  Widget build(BuildContext context) => DebugGraphView(
    layers: layers,
    memory: memory,
    fit: DebugGraphFit.width,
  );
}
