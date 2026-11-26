import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_markers.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_routes.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/app_widget_files.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/widgets_graph_layer.dart';

/// The navigator stack as one walk over the widget tree saw it, for the
/// route grouping of the application graph ([DebugGraphRoutes.stack]):
/// the routes that have widgets of the application, each a lane
/// ([routes]), and where each starts in the tree ([startingAt]).
///
/// Read from Flutter's own tree, so any navigator counts (the navigation
/// starter's, a `MaterialApp`'s, a nested one): each entry of a
/// navigator's overlay is a route's; the routes under an opaque one are
/// offstage (their tickers off). Of a navigator's routes the top one of
/// the pages API (or, without pages, the lowest one shown) is the current
/// screen, those over it dialogs, those under it below. A route that
/// holds a navigator of its own (a shell) is no lane: its widgets are the
/// app's, its navigator's routes take its place in the stack. A route is
/// named by its page's name and its first widget of the application
/// (`/m/9102782543 · MatchScreen`), read with `ModalRoute.settingsOf`,
/// whose dependency never rebuilds the widget.
final class DebugNavigatorStack {
  DebugNavigatorStack._(this.routes, this._starts, this.signature);

  /// No route.
  static final empty = DebugNavigatorStack._(const [], HashMap.identity(), 0);

  /// The lanes of the routes, in order: the current screen, the dialogs
  /// over it, the routes under it (the nearest first); `App` is not among
  /// them.
  final List<DebugGraphRoute> routes;

  final Map<Element, DebugGraphRoute> _starts;

  /// A number that changes when the routes, their roles or their places
  /// do.
  final int signature;

  /// The lane whose subtree starts at [element] (an entry of a navigator's
  /// overlay): its route's, or `App` for a route that holds a navigator
  /// of its own; `null` for any other element.
  DebugGraphRoute? startingAt(Element element) => _starts[element];

  /// The lane of [element]: of the nearest route around it, `App` above
  /// every navigator.
  DebugGraphRoute laneOf(Element element) {
    if (_starts[element] case final own?) {
      return own;
    }
    if (!element.mounted || _starts.isEmpty) {
      return DebugGraphRoute.app;
    }
    DebugGraphRoute? found;
    element.visitAncestorElements((ancestor) {
      found = _starts[ancestor];
      return found == null;
    });
    return found ?? DebugGraphRoute.app;
  }

  /// The stack under [root]: the application's widgets told by [files].
  static DebugNavigatorStack read(
    Element? root, {
    required AppWidgetFiles files,
  }) {
    if (root == null) {
      return empty;
    }
    final navigators = <_Navigator>[];
    final stack = <(Element, _Walk)>[(root, const _Walk())];
    while (stack.isNotEmpty) {
      final (element, walk) = stack.removeLast();
      final widget = element.widget;
      if (widget.key is DebugToolSubtree) {
        continue;
      }
      final tickerOff =
          walk.tickerOff || (widget is TickerMode && !widget.enabled);
      final entry = walk.entry;
      if (entry != null &&
          entry.screen == null &&
          WidgetsGraphLayer.isAppElement(element, files)) {
        entry
          ..screen = element
          ..offstage = tickerOff
          ..settings = ModalRoute.settingsOf(element);
      }
      var navigatorAbove = walk.navigatorAbove || widget is Navigator;
      var level = walk.overlayLevel == 1 ? 2 : 0;
      _Navigator? navigator;
      if (widget is Overlay && navigatorAbove) {
        navigatorAbove = false;
        level = 1;
        navigator = _Navigator(entry);
        navigators.add(navigator);
        if (entry != null) {
          entry.nested = true;
          // A route with no widget of the application's above its own
          // navigator: its settings read here.
          if (entry.screen == null && entry.settings == null) {
            entry
              ..offstage = tickerOff
              ..settings = ModalRoute.settingsOf(element);
          }
        }
      }
      final children = <Element>[];
      element.visitChildren(children.add);
      final next = _Walk(
        entry: entry,
        tickerOff: tickerOff,
        navigatorAbove: navigatorAbove,
        overlayLevel: level,
        navigator: navigator ?? walk.navigator,
      );
      for (var i = children.length - 1; i >= 0; i--) {
        if (level == 2 && next.navigator != null) {
          // An entry of the navigator's overlay.
          final own = _Entry(children[i], index: i);
          next.navigator!.entries.add(own);
          stack.add((
            children[i],
            _Walk(entry: own, tickerOff: tickerOff),
          ));
        } else {
          stack.add((children[i], next));
        }
      }
    }
    return _stackOf(navigators);
  }

  // The routes of each navigator, their roles, and the lanes in order.
  static DebugNavigatorStack _stackOf(List<_Navigator> navigators) {
    final starts = HashMap<Element, DebugGraphRoute>.identity();
    final leaves = <_Route>[];
    final roleOf = HashMap<RouteSettings, DebugGraphGroupRole>.identity();
    var position = 0;
    for (final navigator in navigators) {
      final routes = <_Route>[];
      final bySettings = HashMap<RouteSettings, _Route>.identity();
      final around = navigator.parent?.settings;
      // The entries in the overlay's order, bottom first.
      navigator.entries.sort((a, b) => a.index.compareTo(b.index));
      for (final entry in navigator.entries) {
        final settings = entry.settings;
        if (settings == null || identical(settings, around)) {
          continue;
        }
        final route = bySettings[settings] ??= () {
          final made = _Route(settings, entry);
          routes.add(made);
          return made;
        }();
        route.entries.add(entry);
        route.nested |= entry.nested;
      }
      if (routes.isEmpty) {
        continue;
      }
      // The current screen: the top page shown, else the lowest route
      // shown, else the top one.
      var current = -1;
      for (var i = routes.length - 1; i >= 0 && current < 0; i--) {
        if (!routes[i].first.offstage && routes[i].settings is Page) {
          current = i;
        }
      }
      for (var i = 0; i < routes.length && current < 0; i++) {
        if (!routes[i].first.offstage) {
          current = i;
        }
      }
      if (current < 0) {
        current = routes.length - 1;
      }
      final outer = around == null ? null : roleOf[around];
      for (var i = 0; i < routes.length; i++) {
        final own = i == current
            ? DebugGraphGroupRole.current
            : (i > current
                  ? DebugGraphGroupRole.dialog
                  : DebugGraphGroupRole.below);
        final role = switch (outer) {
          DebugGraphGroupRole.below => DebugGraphGroupRole.below,
          DebugGraphGroupRole.dialog when own != DebugGraphGroupRole.below =>
            DebugGraphGroupRole.dialog,
          _ => own,
        };
        final route = routes[i]
          ..role = role
          ..position = position++;
        roleOf[route.settings] = role;
        if (route.nested) {
          for (final entry in route.entries) {
            starts[entry.element] = DebugGraphRoute.app;
          }
        } else {
          leaves.add(route);
        }
      }
    }
    int rank(DebugGraphGroupRole role) => role.index;
    leaves.sort((a, b) {
      final byRole = rank(a.role).compareTo(rank(b.role));
      if (byRole != 0) {
        return byRole;
      }
      // The routes under the screen, the nearest first.
      return a.role == DebugGraphGroupRole.below
          ? b.position.compareTo(a.position)
          : a.position.compareTo(b.position);
    });
    final lanes = <DebugGraphRoute>[];
    var signature = 17;
    for (var i = 0; i < leaves.length; i++) {
      final route = leaves[i];
      final settings = route.settings;
      final pageKey = settings is Page ? settings.key : null;
      final label = WidgetsGraphLayer.labelOf(route.first.screen!.widget);
      final name = settings.name;
      final lane = DebugGraphRoute(
        key: pageKey != null
            ? 'route:$pageKey'
            : 'route:#${identityHashCode(settings)}',
        title: name == null || name.isEmpty ? label : '$name · $label',
        role: route.role,
        order: i,
        pageKey: pageKey,
      );
      lanes.add(lane);
      for (final entry in route.entries) {
        starts[entry.element] = lane;
      }
      signature = Object.hash(signature, lane.key, lane.title, lane.role);
    }
    for (final MapEntry(key: element, value: lane) in starts.entries) {
      signature = Object.hash(signature, identityHashCode(element), lane.key);
    }
    return DebugNavigatorStack._(lanes, starts, signature);
  }
}

// The walk's state down a branch.
final class _Walk {
  const _Walk({
    this.entry,
    this.tickerOff = false,
    this.navigatorAbove = false,
    this.overlayLevel = 0,
    this.navigator,
  });

  final _Entry? entry;
  final bool tickerOff;
  final bool navigatorAbove;
  final int overlayLevel;
  final _Navigator? navigator;
}

// A navigator's overlay, inside the entry [parent] (`null`: at the top).
final class _Navigator {
  _Navigator(this.parent);

  final _Entry? parent;
  final List<_Entry> entries = [];
}

// An entry of a navigator's overlay: its first widget of the application,
// whether it is offstage, the settings of its route.
final class _Entry {
  _Entry(this.element, {required this.index});

  final Element element;
  final int index;
  Element? screen;
  bool offstage = false;
  RouteSettings? settings;
  bool nested = false;
}

// A route of a navigator: its entries (a modal barrier and its page).
final class _Route {
  _Route(this.settings, this.first);

  final RouteSettings settings;
  final _Entry first;
  final List<_Entry> entries = [];
  bool nested = false;
  DebugGraphGroupRole role = DebugGraphGroupRole.below;
  int position = 0;
}
