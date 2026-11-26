import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/app_widget_files.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/debug_navigator_stack.dart';

/// What the lanes of the application graph are ([DebugGraphRoutes.grouping],
/// the `Group by` choice of the graph's `Options`).
enum DebugGraphGrouping {
  /// The navigator stack: the current screen, the dialogs over it, the
  /// screens under it, and `App` for what they share.
  route,

  /// The layers' own groups: the beans by module, the signals by bean, the
  /// widgets as one tree.
  module,
}

/// A lane of the route grouping: a route of the navigator stack, or `App`
/// ([app]). Its [key] is the same in every layer, so a screen's widgets,
/// the beans of its route scope and their signals share one lane.
@immutable
final class DebugGraphRoute {
  /// The lane [key], called [title], of [role] at [order].
  const DebugGraphRoute({
    required this.key,
    required this.title,
    required this.role,
    required this.order,
    this.pageKey,
  });

  /// What the routes share: the singletons, their signals, the widgets
  /// above the navigator (and those of a route that holds a navigator of
  /// its own: a shell). Last.
  static const app = DebugGraphRoute(
    key: 'app',
    title: 'App',
    role: DebugGraphGroupRole.app,
    order: 1 << 20,
  );

  /// The lane's key ([DebugGraphNode.group]).
  final String key;

  /// What the lane says: `/m/9102782543 · MatchScreen`.
  final String title;

  /// Its place in the stack.
  final DebugGraphGroupRole role;

  /// Its place among the lanes ([DebugGraphNode.groupOrder]).
  final int order;

  /// The key of the route's page ([Page.key]) for a route of the pages
  /// API: what a [DebugGraphRouteBeans] names the route by. `null` for a
  /// route pushed without a page (a dialog).
  final LocalKey? pageKey;
}

/// Where the application graph learns which route a scoped bean lives in:
/// implemented by what keeps beans per route (the navigation starter's
/// `RouteScopes`, registered with this type). Read only while a view of
/// the graph collects with the route grouping, so it must keep nothing for
/// it: it answers from what it holds anyway.
abstract interface class DebugGraphRouteBeans {
  /// The names of the scopes whose beans live per route (`route`): a bean
  /// of one of them that lives in no route now has no lane.
  Set<String> get routeScopeNames;

  /// The beans of those scopes alive now, by the key of their route's page
  /// ([Page.key]), each by its bean name.
  Map<LocalKey, Map<String, Object>> liveBeansByPage();
}

/// The lanes of the beans for one collect ([DebugGraphRoutes.beanLanes]).
final class DebugGraphBeanLanes {
  DebugGraphBeanLanes._(this._byName, this._byInstance, this._scopes);

  final Map<String, DebugGraphRoute> _byName;
  final Map<Object, DebugGraphRoute> _byInstance;
  final Set<String> _scopes;

  /// The lane of the bean [name] of [scope]: the topmost route it lives
  /// in; `App` for a bean of no route scope; `null` for a bean of a route
  /// scope that lives in no route now.
  DebugGraphRoute? ofBean(String name, String? scope) =>
      _byName[name] ?? (_scopes.contains(scope) ? null : DebugGraphRoute.app);

  /// The lane of the instance [bean] of [scope]: the route whose scope
  /// holds it; else as [ofBean] without a name.
  DebugGraphRoute? ofInstance(Object? bean, String? scope) =>
      (bean == null ? null : _byInstance[bean]) ??
      (_scopes.contains(scope) ? null : DebugGraphRoute.app);
}

/// How the application graph groups its nodes, shared by its layers
/// (`debugGraphRoutes`): by the navigator stack ([DebugGraphGrouping.route],
/// the default) or by the layers' own groups. It gives the `Group by`
/// choice ([choicesOf]) and, for the route grouping, the lanes: the
/// navigator stack read from the widget tree ([stack]), the route of a
/// widget ([laneOf]) and of a bean ([beanLanes], from the
/// [DebugGraphRouteBeans]).
///
/// It reads only while a layer of a view uses it ([start]): the stack once
/// after the frames that may have changed it, at most every [readEvery],
/// telling its listeners when it changed. Nothing is kept or heard while
/// no view shows, and nothing at all with the module grouping.
final class DebugGraphRoutes extends ChangeNotifier {
  /// The grouping of the graph, the routes' beans told by [beans], the
  /// tree from [root].
  DebugGraphRoutes({
    this.beans = const [],
    Element? Function()? root,
    this.readEvery = const Duration(milliseconds: 250),
    this._grouping = DebugGraphGrouping.route,
  }) : _root = root ?? (() => WidgetsBinding.instance.rootElement);

  /// What tells the beans of each route.
  final List<DebugGraphRouteBeans> beans;

  /// How often at most the stack is read again, after frames.
  final Duration readEvery;

  final Element? Function() _root;
  DebugGraphGrouping _grouping;
  AppWidgetFiles? _files;
  DebugNavigatorStack? _stack;
  bool _stale = true;
  final Map<DebugGraphLayer, int> _users = {};
  Timer? _timer;
  bool _frameHooked = false;
  bool _disposed = false;

  /// The labels of the choice, by grouping.
  static const labels = {
    DebugGraphGrouping.route: 'Route',
    DebugGraphGrouping.module: 'Module',
  };

  /// What the lanes are.
  DebugGraphGrouping get grouping => _grouping;

  set grouping(DebugGraphGrouping grouping) {
    if (grouping == _grouping) {
      return;
    }
    _grouping = grouping;
    _stale = true;
    _schedule();
    notifyListeners();
  }

  /// Whether the lanes are the navigator stack.
  bool get byRoute => _grouping == DebugGraphGrouping.route;

  /// The `Group by: Route | Module` choice.
  DebugGraphChoice get choice => DebugGraphChoice(
    label: 'Group by',
    choices: [
      for (final grouping in DebugGraphGrouping.values) labels[grouping]!,
    ],
    value: labels[_grouping]!,
    onChanged: (value) => grouping = DebugGraphGrouping.values.firstWhere(
      (grouping) => labels[grouping] == value,
      orElse: () => _grouping,
    ),
  );

  /// The choice for [layer]'s `Options`: given once, to the first of the
  /// layers started now (by their order), so the menu lists it once.
  List<DebugGraphChoice> choicesOf(DebugGraphLayer layer) {
    DebugGraphLayer? first;
    for (final user in _users.keys) {
      if (first == null ||
          user.order < first.order ||
          (user.order == first.order && user.id.compareTo(first.id) < 0)) {
        first = user;
      }
    }
    return first == null || identical(first, layer) ? [choice] : const [];
  }

  /// Starts reading for [layer], while a view shows it; returns what stops
  /// it.
  void Function() start(DebugGraphLayer layer) {
    final wasIdle = _users.isEmpty;
    _users[layer] = (_users[layer] ?? 0) + 1;
    if (wasIdle) {
      _stale = true;
      _schedule();
    }
    var stopped = false;
    return () {
      if (stopped) {
        return;
      }
      stopped = true;
      final left = (_users[layer] ?? 1) - 1;
      if (left > 0) {
        _users[layer] = left;
        return;
      }
      _users.remove(layer);
      if (_users.isEmpty) {
        _timer?.cancel();
        _timer = null;
        _stack = null;
        _stale = true;
      }
    };
  }

  // While started with the route grouping: after frames, the stack is
  // read again at most every [readEvery], and the listeners told when it
  // changed.
  void _schedule() {
    if (_users.isEmpty || !byRoute || _disposed) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(readEvery, (_) {
      if (!_stale || !byRoute) {
        return;
      }
      final before = _stack?.signature;
      final now = _read();
      if (now.signature != before) {
        notifyListeners();
      }
    });
    _hookFrame();
  }

  void _hookFrame() {
    if (_frameHooked || _users.isEmpty || !byRoute || _disposed) {
      return;
    }
    _frameHooked = true;
    try {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _frameHooked = false;
        _stale = true;
        _hookFrame();
      });
    } on Object {
      _frameHooked = false;
    }
  }

  DebugNavigatorStack _read() {
    final root = _root();
    final files = _files ??= AppWidgetFiles.of(root);
    _stale = _users.isEmpty;
    return _stack = DebugNavigatorStack.read(root, files: files);
  }

  /// The navigator stack now: read again after a frame (while started) or
  /// at each call (while not).
  DebugNavigatorStack get stack =>
      !_stale && _stack != null ? _stack! : _read();

  /// The lane of [element]: of the route it is in, `App` above the
  /// navigator.
  DebugGraphRoute laneOf(Element element) => stack.laneOf(element);

  /// The lanes of the beans now: of the route each lives in, by what the
  /// [beans] tell, the topmost route first.
  DebugGraphBeanLanes beanLanes() {
    final routes = stack.routes;
    final byName = <String, DebugGraphRoute>{};
    final byInstance = HashMap<Object, DebugGraphRoute>.identity();
    final scopes = <String>{};
    for (final source in beans) {
      scopes.addAll(source.routeScopeNames);
      final live = source.liveBeansByPage();
      if (live.isEmpty) {
        continue;
      }
      for (final route in routes) {
        final named = route.pageKey == null ? null : live[route.pageKey];
        if (named == null) {
          continue;
        }
        for (final MapEntry(key: name, value: bean) in named.entries) {
          byName.putIfAbsent(name, () => route);
          byInstance.putIfAbsent(bean, () => route);
        }
      }
    }
    return DebugGraphBeanLanes._(byName, byInstance, scopes);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
