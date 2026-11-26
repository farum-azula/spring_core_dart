import 'package:flutter/widgets.dart' show BuildContext, immutable;

/// The outline of a node of the application graph: inside one layer (one
/// colour) each kind of node has its own ([DebugGraphKind.shape]), so a
/// `@Computed` value reads apart from a `@Signal` field, a repository
/// apart from a service.
enum DebugGraphShape {
  /// A rectangle with rounded corners.
  rounded,

  /// A rectangle whose ends are half circles.
  pill,

  /// A rectangle with square corners.
  rectangle,

  /// A rectangle with its corners cut.
  octagon,

  /// A rectangle whose left and right ends are points.
  hexagon,

  /// A rectangle whose sides lean to the right.
  parallelogram,

  /// A rectangle with a band on its left edge.
  tagged,
}

/// What a lane of the graph's own stands for ([DebugGraphNode.groupRole]):
/// with the route grouping, its place in the navigator stack. The group
/// filter lists the lanes by role, `Current · Dialog · Below (n) · App`.
enum DebugGraphGroupRole {
  /// The screen in front: the top route of the navigator.
  current,

  /// A route over the current screen that does not cover it (a dialog, a
  /// sheet, a menu).
  dialog,

  /// A route under the current screen; the "On screen" scope hides it.
  below,

  /// What the routes share: the singletons, the widgets above the
  /// navigator.
  app,
}

/// A kind of node of a [DebugGraphLayer]: what the legend calls it, the
/// shape it is drawn in and what the legend tells of it.
@immutable
final class DebugGraphKind {
  /// The kind [id], called [label] in the legend, drawn as [shape],
  /// explained by [description].
  const DebugGraphKind(this.id, this.label, this.shape, {this.description});

  /// What a node names it by ([DebugGraphNode.kind]).
  final String id;

  /// What the legend calls it: `computed`.
  final String label;

  /// Its outline.
  final DebugGraphShape shape;

  /// What the pointer over its legend entry tells: `a value worked out
  /// from other state, again when what it read changes`; `null`: the
  /// label alone.
  final String? description;
}

/// One line of what the graph tells of a node: in its tooltip (the first
/// lines) and in the card beside it after a tap (the first values in its
/// one line, every line once opened).
@immutable
final class DebugGraphDetail {
  /// [label] and its [value], with [links] listed under it, in the block
  /// [section] of the card; [more] tells the whole value.
  const DebugGraphDetail(
    this.label,
    this.value, {
    this.links = const [],
    this.section,
    this.more,
  });

  /// What the line is about: `value`.
  final String label;

  /// What it says: `TEN`.
  final String value;

  /// The nodes it names, one row each under the line (a bean's
  /// dependencies, a widget's beans): a tap on one selects its node.
  final List<DebugGraphDetailLink> links;

  /// The titled block of the card the line is in (a widget's
  /// `properties`), after the lines without one; `null`: none.
  final String? section;

  /// The whole of a value [value] shortens (a long string, the items of a
  /// list), worked out only when a tap on the row opens it; `null`: the
  /// value is whole.
  final String Function()? more;
}

/// A node a [DebugGraphDetail] names: [label], what it is ([note]: the
/// kind of a dependency, `@Lazy`), the node [target] that a tap on it
/// selects when it is on the graph. One that is not on the graph shows
/// dimmed, with [hidden] telling why (`framework`); `not shown` by default.
final class DebugGraphDetailLink {
  /// The row [label].
  const DebugGraphDetailLink(
    this.label, {
    this.target,
    this.note,
    this.hidden,
    this.tooltip,
  });

  /// The name shown.
  final String label;

  /// The id of the node it stands for.
  final String? target;

  /// What follows the name, muted.
  final String? note;

  /// Why its node may not be on the graph; `null`: `not shown`.
  final String? hidden;

  /// The whole of what [label] shortens (a path), shown on hover.
  final String? tooltip;
}

/// A node of the application graph, as a layer gives it
/// ([DebugGraphLayer.collect]).
@immutable
final class DebugGraphNode {
  /// The node [id] of [layer].
  const DebugGraphNode({
    required this.id,
    required this.layer,
    required this.kind,
    required this.label,
    this.group,
    this.groupTitle,
    this.groupOrder,
    this.groupRole,
    this.details = const [],
    this.repeatKey,
    this.repeatScope,
    this.widget,
    this.source,
    this.sink = false,
    this.dimmed = false,
    this.sameAs,
    this.onScreen,
  });

  /// Unique in the whole graph, every layer's nodes together: a layer
  /// starts its ids with its own id (`signals:Basket.total`), so an edge of
  /// another layer can name it.
  final String id;

  /// The id of the layer that gives it ([DebugGraphLayer.id]).
  final String layer;

  /// One of its layer's [DebugGraphLayer.kinds] (its [DebugGraphKind.id]).
  final String kind;

  /// What its plate says.
  final String label;

  /// The lane it is in (a bean, a widget's type); `null`: the lane of the
  /// nodes without one, last.
  final String? group;

  /// What the lane says at its left; `null`: [group].
  final String? groupTitle;

  /// The place of its [group] among the lanes, low first. A group with an
  /// order is the graph's, not its layer's: the nodes of every layer that
  /// name it share one lane (a screen's widgets, the beans of its route
  /// scope and their signals), and the ordered lanes come before the
  /// layers' own. `null`: the lane is its layer's.
  final int? groupOrder;

  /// What its [group] stands for, when it has a [groupOrder]: the screen
  /// in front, what is over it, what is under it, what they share. The
  /// group filter lists the lanes by role, and the "On screen" scope hides
  /// the lanes of [DebugGraphGroupRole.below].
  final DebugGraphGroupRole? groupRole;

  /// What its tooltip and detail tell when its layer has nothing newer
  /// ([DebugGraphLayer.detailsOf]).
  final List<DebugGraphDetail> details;

  /// Nodes of one group with one repeat key fold into one plate
  /// (`PlayerReviews ×10`) until it is tapped open; `null`: never folded.
  final String? repeatKey;

  /// What narrows the fold of [repeatKey] inside the group: only the nodes
  /// of one scope fold together (the widgets of one type under one parent,
  /// in a lane of a whole screen); `null`: the whole group.
  final String? repeatScope;

  /// The widget the node stands for, for the "On screen" scope: the node
  /// is on the screen while the widget's box is in the app's window. `null`:
  /// a node of no widget, kept by what it reads and what reads it.
  final BuildContext? widget;

  /// What its layer knows it by (a member, a widget's tracking), for the
  /// layer's own [DebugGraphLayer.detailsOf] and [DebugGraphLayer.glowOf].
  final Object? source;

  /// Whether it only reads: the layered layout puts it in the last column.
  final bool sink;

  /// The id of another layer's node that stands for the same thing (a
  /// widget that read state is the widgets layer's node of that widget):
  /// when that node is shown this one is merged into it, its edges moved
  /// to it and its details told with it; when it is not, this node shows
  /// as itself.
  final String? sameAs;

  /// Whether the layer saw it on the screen, when it computed that itself
  /// (the widgets layer, in one pass over the tree); `null`: the "On
  /// screen" scope reads [widget]'s place ([DebugGraphScreen.shows]).
  final bool? onScreen;

  /// Drawn grey, in the theme's muted colour instead of its layer's: a
  /// node that stands for what is not there (a bean a condition left
  /// out).
  final bool dimmed;

  /// The lane's title.
  String? get laneTitle => groupTitle ?? group;
}

/// An edge of the application graph, from [from] to [to] by their
/// [DebugGraphNode.id]s: what is read to its reader, a parent to its
/// child, a bean to the bean it injects. An edge whose ends are not both
/// shown is not drawn, so a layer may name another layer's nodes.
@immutable
final class DebugGraphEdge {
  /// The edge from [from] to [to].
  const DebugGraphEdge(
    this.from,
    this.to, {
    this.kind = 'reads',
    this.dashed = false,
  });

  /// The id of the node it starts at.
  final String from;

  /// The id of the node its arrow points at.
  final String to;

  /// What it means, for the detail of its ends (`reads`, `injects`).
  final String kind;

  /// Drawn dashed: a weaker tie (a lazy injection, a read not followed).
  final bool dashed;
}

/// What a layer gives for a scope: its nodes, and the edges it knows of,
/// its own and those that tie its nodes to another layer's.
@immutable
final class DebugGraphPart {
  /// [nodes] and [edges].
  const DebugGraphPart(this.nodes, this.edges);

  /// Nothing.
  static const empty = DebugGraphPart([], []);

  /// The nodes.
  final List<DebugGraphNode> nodes;

  /// The edges.
  final List<DebugGraphEdge> edges;
}

/// A switch of a layer's own, a checkbox of the graph's `Options` menu
/// under the layer's title ([DebugGraphLayer.options]): the beans layer's
/// `framework`, which adds the framework's beans to the application's.
@immutable
final class DebugGraphOption {
  /// The switch [label], on when [value], turned by [onChanged].
  const DebugGraphOption({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  /// What its checkbox says.
  final String label;

  /// Whether it is on now.
  final bool value;

  /// Called with the value a tap asks for; the layer then notifies its
  /// [DebugGraphLayer.changes] or gives other nodes at the next collect.
  final void Function(bool value) onChanged;
}

/// A single choice of a layer's own, one of several values, in the graph's
/// `Options` menu under the layer's title ([DebugGraphLayer.choices]): its
/// [label] over a radio row for each of its [choices], the one of [value]
/// marked. `Group by: Route | Module` picks what a node's group is.
///
/// ```dart
/// @override
/// List<DebugGraphChoice> get choices => [
///   DebugGraphChoice(
///     label: 'Group by',
///     choices: const ['Route', 'Module'],
///     value: _groupBy,
///     onChanged: (choice) {
///       _groupBy = choice;
///       _changes.changed();             // the graph collects again
///     },
///   ),
/// ];
/// ```
@immutable
final class DebugGraphChoice {
  /// The choice [label] among [choices], [value] chosen, changed by
  /// [onChanged].
  const DebugGraphChoice({
    required this.label,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  /// What its heading in the menu says: `Group by`.
  final String label;

  /// The values to choose from, in the menu's order: `Route`, `Module`.
  final List<String> choices;

  /// The value chosen now, one of [choices].
  final String value;

  /// Called with the value a tap chooses (not with the one chosen
  /// already); the layer then notifies its [DebugGraphLayer.changes] or
  /// gives other nodes at the next collect.
  final void Function(String value) onChanged;
}
