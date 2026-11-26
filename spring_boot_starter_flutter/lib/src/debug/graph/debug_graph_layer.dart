import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';

/// Which nodes the application graph shows.
enum DebugGraphScope {
  /// The widgets whose box is in the app's window (not offstage, not
  /// transparent, not scrolled out; the debug panel over the app does not
  /// hide them), everything they read up the graph, and what else listens
  /// to the same sources (an effect).
  onScreen,

  /// Every node the layers know.
  all,
}

/// A layer of the application graph (the debug panel's Graph tab, the
/// console's `graph` pane): a bean that gives nodes and edges of one
/// colour, its own kinds of node each in a shape of its own.
///
/// The graph collects only while it shows: [start] runs when a view of it
/// shows and what it returns when the last hides; while started, the layer
/// notifies [changes] when its nodes or edges change (not their values),
/// and the graph asks [collect] again, at most a few times a second. A
/// layer that knows how one of its nodes ties to another layer's node
/// gives that edge too (by the other node's id); an edge whose ends are
/// not both shown is not drawn.
///
/// A layer is in the build only by its own switch, and the graph's engine
/// only with a layer: a layer's module brings the Graph tab and the
/// `graph` pane with it (`debugGraphSectionDefinitions`,
/// `debugGraphPaneDefinitions` of the starter's auto-configuration), the
/// first module there makes them.
///
/// ```dart
/// // The routes of the app as a layer: each page a node, an edge from a
/// // page to the pages it opens.
/// @Component()
/// @ConditionalOnProperty('app.debug.routes-graph', havingValue: 'true')
/// class RoutesGraphLayer extends DebugGraphLayer {
///   RoutesGraphLayer(this.routes);
///
///   final AppRoutes routes;               // a ChangeNotifier
///
///   @override
///   String get id => 'routes';
///
///   @override
///   String get title => 'Routes';
///
///   // Its colour: the debug theme's `graph-routes`, else one of the
///   // theme's palette ([colorOf]).
///
///   @override
///   List<DebugGraphKind> get kinds => const [
///     DebugGraphKind(
///       'page',
///       'page',
///       DebugGraphShape.rounded,
///       description: 'a page of the app',
///     ),
///     DebugGraphKind('dialog', 'dialog', DebugGraphShape.pill),
///   ];
///
///   @override
///   Listenable get changes => routes;
///
///   @override
///   DebugGraphPart collect(DebugGraphScope scope) => DebugGraphPart(
///     [
///       for (final route in routes.all)
///         DebugGraphNode(
///           id: 'routes:${route.path}',
///           layer: id,
///           kind: route.dialog ? 'dialog' : 'page',
///           label: route.path,
///           group: route.section,
///         ),
///     ],
///     [
///       for (final route in routes.all)
///         for (final target in route.opens)
///           DebugGraphEdge('routes:${route.path}', 'routes:$target'),
///     ],
///   );
/// }
/// ```
///
/// Spring has no counterpart.
abstract class DebugGraphLayer {
  /// A layer.
  const DebugGraphLayer();

  /// Its name: what its nodes' ids start with, and what
  /// `spring.flutter.debug.graph.layers` picks a built-in layer by.
  String get id;

  /// What its switch above the graph and the legend say.
  String get title;

  /// Its place among the layers: their switches and their lanes, low
  /// first.
  int get order => 0;

  /// The colour of its nodes, from the debug theme: by default the theme's
  /// `graph-<id>` ([DebugStyle.graphLayer]), set or else a colour of the
  /// theme's palette picked by [id]. A layer with a colour of its own
  /// passes it as `orElse` (the built-in layers: green beans, cyan blue
  /// widgets, orange signals).
  Color colorOf(DebugStyle style) => style.graphLayer(id);

  /// Its kinds of node, in the legend's order.
  List<DebugGraphKind> get kinds;

  /// Its own switches, checkboxes of the graph's `Options` menu under its
  /// title while it is shown, read again whenever the menu builds; none by
  /// default. A tap calls [DebugGraphOption.onChanged] and the graph
  /// collects again.
  List<DebugGraphOption> get options => const [];

  /// Its own single choices (`Group by: Route | Module`), radio rows of the
  /// graph's `Options` menu under its title after its [options], read again
  /// whenever the menu builds; none by default. A tap calls
  /// [DebugGraphChoice.onChanged] and the graph collects again.
  List<DebugGraphChoice> get choices => const [];

  /// What a flash of one of its nodes means, the label of the legend's
  /// pulse entry of the layer: `a signal ticked`; `null` (the default): no
  /// entry, its nodes do not flash ([glowOf]).
  String? get flashMeaning => null;

  /// What the hot outline of one of its nodes means, the label of the
  /// legend's outline entry of the layer: `rebuilt 3+ in 5 s`; `null` (the
  /// default): no entry, none is hot ([heatOf]).
  String? get heatMeaning => null;

  /// Why [node] is hot, the line its tooltip adds in the theme's
  /// `graph-hot`: `PageBackdrop: 14 rebuilds in 5 s`; `null` (the default):
  /// nothing added.
  String? hotNoteOf(DebugGraphNode node) => null;

  /// How the graph is laid out while it is the first layer shown; `null`
  /// (the default): left to right ([LayeredDebugGraphLayout]).
  DebugGraphLayout? get layout => null;

  /// Starts collecting, while a view shows; returns what stops it.
  void Function() start() => _nothing;

  static void _nothing() {}

  /// Notifies when its nodes or edges change, while started.
  Listenable get changes;

  /// Its nodes and edges for [scope]. For [DebugGraphScope.onScreen] a
  /// layer may leave out what it knows cannot be on the screen; the graph
  /// keeps a node that stands for a widget ([DebugGraphNode.widget]) only
  /// while its box is in the window, whatever the layer gives.
  DebugGraphPart collect(DebugGraphScope scope);

  /// What the tooltip and the detail of [node] tell, read when they show;
  /// [DebugGraphNode.details] by default.
  List<DebugGraphDetail> detailsOf(DebugGraphNode node) => node.details;

  /// How lit [node] is now: 1 when it just changed or ran, down to 0 a
  /// second later; 0 by default. A lit node flashes and a pulse runs along
  /// its edges out.
  double glowOf(DebugGraphNode node) => 0;

  /// Whether [node] changed, ran or was built within [window]: "Live only"
  /// hides the others. `true` by default.
  bool isLive(DebugGraphNode node, Duration window) => true;

  /// Calls [wake] soon after something of the layer lights up, while
  /// started: the view draws frames then, and stops when nothing glows.
  /// Returns what stops the calls; nothing by default.
  void Function() onActivity(VoidCallback wake) => _nothing;

  /// How hot [node] is, from 0 to 1: a branch that rebuilds often. The
  /// view outlines hot nodes and the links between them in the theme's
  /// `graph-hot`, read a few times a second; 0 by default.
  double heatOf(DebugGraphNode node) => 0;

  /// Whether its groups are lanes: bands with their titles and choices of
  /// the `Groups` filter. `false` for a layer whose groups only scope its
  /// repeats (the widgets layer's, a widget's children). `true` by
  /// default.
  bool get lanes => true;

  /// Told which of its nodes was tapped (`null`: none any more), for a
  /// layer that shows it in the app too (the widgets layer outlines the
  /// widget); nothing by default.
  void select(DebugGraphNode? node) {}
}
