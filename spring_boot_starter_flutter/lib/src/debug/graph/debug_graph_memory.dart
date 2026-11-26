import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_assembly.dart';

/// What a view of the application graph keeps while the app runs, so that
/// it opens again as it was left: its settings (layers, scope, "Live
/// only", the groups chosen, the lanes, branches and repeats folded or
/// opened), where the graph is (pan and zoom), the legend entries
/// selected and whether the legend is open, the groups chosen last, and
/// the cards open.
///
/// A bean holds it, not the view: the panel's Graph tab
/// (`DebugGraphSection.memory`), each console pane of the graph
/// (`DebugGraphPane.memory`: `graph`, `signals`) and the Signals tab
/// (`SignalsGraphLayer.viewMemory`) each keep their own. The options of a
/// layer (`framework`, `framework widgets`) are on the layer's bean and
/// shared by every view. Kept in memory only; a restart forgets it.
final class DebugGraphMemory extends ChangeNotifier {
  /// An empty memory: the view fits the graph when it first opens.
  DebugGraphMemory();

  /// How many groups [recentGroups] keeps.
  static const recentLimit = 12;

  /// The settings shown; `null` until a view opens (it starts with its
  /// own `settings`).
  DebugGraphSettings? settings;

  /// Where the graph was placed in its room (its scale and offset), by the
  /// user, the first fit or Fit; `null`: never placed, the view fits it
  /// once there is something to fit. Restored as it is when the view
  /// opens again, whatever the size of its room then.
  Matrix4? transform;

  /// Whether the view fits the graph by itself whenever it or its room
  /// changes (the toolbar's Auto, on by default); a pan or a zoom by the
  /// user turns it off, and the place is kept from then on.
  bool autoFit = true;

  /// Whether the legend is open over the graph.
  bool legendOpen = false;

  /// The plate whose chain is highlighted (`DebugGraphItem.key`).
  String? selected;

  /// The plates with an open card, in the order they were opened.
  final Set<String> cards = <String>{};

  /// The cards opened into labelled rows.
  final Set<String> expanded = <String>{};

  final Set<String> _legend = {};
  final List<String> _recentGroups = [];

  /// The keys of the legend entries selected
  /// (`DebugGraphLegendEntry.key`): their nodes are highlighted, the rest
  /// dimmed.
  Set<String> get legend => Set.unmodifiable(_legend);

  /// Whether the legend entry [key] is selected.
  bool isSelected(String key) => _legend.contains(key);

  /// Selects the legend entry [key], or unselects it when it was.
  void toggleLegend(String key) {
    if (!_legend.remove(key)) {
      _legend.add(key);
    }
    notifyListeners();
  }

  /// Unselects every legend entry.
  void clearLegend() {
    if (_legend.isNotEmpty) {
      _legend.clear();
      notifyListeners();
    }
  }

  /// Closes every card.
  void closeCards() {
    cards.clear();
    expanded.clear();
    notifyListeners();
  }

  /// The groups chosen last in the `Groups` list (`DebugGraphLane.key`),
  /// the last first: listed before the others.
  List<String> get recentGroups => List.unmodifiable(_recentGroups);

  /// Notes the group [key] as chosen now.
  void choseGroup(String key) {
    _recentGroups
      ..remove(key)
      ..insert(0, key);
    if (_recentGroups.length > recentLimit) {
      _recentGroups.removeLast();
    }
  }
}
