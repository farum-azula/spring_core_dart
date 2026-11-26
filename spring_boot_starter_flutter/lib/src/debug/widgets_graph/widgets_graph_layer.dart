import 'dart:async';
import 'dart:collection';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show ApplicationContext;
import 'package:spring_boot_starter_flutter/src/debug/debug_markers.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_routes.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_screen.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/tree_debug_graph_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/app_widget_files.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/debug_navigator_stack.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/widget_highlight.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/widget_properties.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/widget_rebuilds.dart';
import 'package:spring_boot_starter_flutter/src/spring_widgets.dart';

/// What the widgets layer knows of a widget it walked past: the context of
/// a [WidgetNodeKind]'s choice.
final class WidgetVisit {
  /// The visit of [element].
  const WidgetVisit(this.element, {required this.app, required this.screen});

  /// The widget's element.
  final Element element;

  /// Whether the widget is the application's.
  final bool app;

  /// Whether it is the first of the application's in a route.
  final bool screen;
}

/// A kind of node of the widgets layer and which widgets are of it: the
/// layer asks the kinds in turn, the first that matches names the node.
final class WidgetNodeKind {
  /// The [kind] of the widgets [matches] holds for.
  const WidgetNodeKind(this.kind, this.matches);

  /// The kind, its legend label and shape.
  final DebugGraphKind kind;

  /// Whether a widget is of it.
  final bool Function(WidgetVisit visit) matches;
}

/// The application's widgets as a layer of the application graph
/// (`widgetsGraphLayer`): a tree from top to bottom
/// ([TreeDebugGraphLayout]) of the widgets of the application's own
/// classes ([AppWidgetFiles]), Flutter's wrappers (a `Padding`, an `Align`,
/// a `Builder`) folded into the application's widget above them;
/// "framework widgets" shows every element. A route's first widget is a
/// screen; a Spring widget, a stateful and a stateless widget each have
/// their shape. Widgets of one type under one parent fold into one plate
/// (`ReviewTile ×10`), a branch collapses into its head.
///
/// A widget that builds flashes, and the branches that build most often
/// are outlined; a tap tells its type, key, size and place, state, route,
/// beans, rebuilds over five seconds and build time, then the values of the
/// widget and of its `State` ([properties]: Flutter's diagnostics, the
/// public fields the generator reads), outlines it over the app and
/// selects it in the Flutter tab's inspector.
///
/// Its node ids are [DebugGraphWidgets.idOf] of the widget's element
/// (`widget:<identity>`), shared with the layers that tie their nodes to
/// widgets: the signals layer merges its readers into them
/// ([DebugGraphNode.sameAs]), the beans layer draws its edges to them.
/// [nodeIdOf] gives the node of any element, of a `State` or of a widget:
/// the node it is folded into.
///
/// With the route grouping of [routes] (the default of the app's graph)
/// each widget is in the lane of its route, a band of the tree for each:
/// the current screen, the dialogs over it, the screens under it, and
/// `App` for the widgets above the navigator (a shell's, a layout's); the
/// widgets of one type fold under one parent, as without it.
///
/// It walks the tree when a view starts showing it and then at most every
/// [walkEvery] after a frame, only while shown; every rebuild is heard in
/// a debug build (elsewhere, what changed between two walks). Hidden it
/// keeps nothing and hears nothing.
final class WidgetsGraphLayer extends DebugGraphLayer {
  /// The layer of the app's tree, its beans told from [context].
  WidgetsGraphLayer({
    this.context,
    this.routes,
    Element? Function()? root,
    this.files,
    Duration Function()? clock,
    this.walkEvery = const Duration(milliseconds: 250),
    this.hotRebuilds = hotFrom,
    this.hotWindow = window,
    this.properties = const [DiagnosticsWidgetProperties()],
  }) : _root = root ?? (() => WidgetsBinding.instance.rootElement),
       rebuilds = WidgetRebuilds(clock: clock);

  /// Where a widget's card takes the values of its `properties` and
  /// `state properties` blocks, asked in turn; Flutter's diagnostics by
  /// default.
  final List<WidgetProperties> properties;

  /// Where the beans of a Spring widget are named from.
  final ApplicationContext? context;

  /// How the graph groups its nodes, and the routes for the route
  /// grouping; `null`: the widgets are one tree, grouped by parent.
  final DebugGraphRoutes? routes;

  /// How often at most the tree is walked again, after frames.
  final Duration walkEvery;

  /// How many rebuilds within [hotWindow] make a widget hot
  /// (`spring.flutter.debug.graph.hot.rebuilds`).
  final int hotRebuilds;

  /// The window of the rebuild counts and of the hot branches
  /// (`spring.flutter.debug.graph.hot.window`).
  final Duration hotWindow;

  /// The rebuilds heard.
  final WidgetRebuilds rebuilds;

  final Element? Function() _root;

  /// The application's files; worked out at the first walk when not given.
  AppWidgetFiles? files;
  final _Changes _changes = _Changes();
  int _users = 0;
  Timer? _timer;
  bool _dirty = false;
  bool _frameHooked = false;
  bool _everything = false;
  _Tree _tree = _Tree.empty;
  final Map<Element, Duration> _lastAt = HashMap.identity();
  final Map<Element, Queue<Duration>> _hits = HashMap.identity();
  final Map<Element, int> _hitFrame = HashMap.identity();
  int _frame = 0;
  final List<VoidCallback> _wakers = [];
  Duration? _wokenAt;
  bool _waking = false;
  Map<Element, (int, Duration?, Duration?)>? _counts;
  Duration? _countedAt;
  Map<Element, double>? _heat;
  Map<Element, (String, int)> _hotSources = HashMap.identity();
  final WidgetHighlight _highlight = WidgetHighlight();
  // The property rows of the widgets whose card is open, read again after
  // the next walk: a card rebuilt on every frame of a pan reads none.
  final Map<Element, List<DebugGraphDetail>> _propertyRows = HashMap.identity();

  /// The window of the rebuild counts and of the hot branches by
  /// default ([hotWindow]).
  static const window = Duration(seconds: 5);

  /// How many rebuilds within the window make a widget hot by default
  /// ([hotRebuilds]).
  static const hotFrom = 3;

  /// A route's first widget of the application's.
  static const screen = DebugGraphKind(
    'screen',
    'route / screen',
    DebugGraphShape.octagon,
    description: "A route's first widget of the application's: a screen",
  );

  /// A `SpringStatelessWidget` or `SpringStatefulWidget`: beans injected.
  static const spring = DebugGraphKind(
    'spring',
    'Spring widget',
    DebugGraphShape.pill,
    description:
        'A SpringStatelessWidget or SpringStatefulWidget: beans injected',
  );

  /// A stateful widget.
  static const stateful = DebugGraphKind(
    'stateful',
    'stateful',
    DebugGraphShape.rounded,
    description: "A StatefulWidget of the application's: a State of its own",
  );

  /// A stateless widget.
  static const stateless = DebugGraphKind(
    'stateless',
    'stateless',
    DebugGraphShape.rectangle,
    description: "A StatelessWidget of the application's",
  );

  /// Another element: Flutter's own, shown with "framework widgets".
  static const framework = DebugGraphKind(
    'framework',
    'framework',
    DebugGraphShape.parallelogram,
    description: "A widget of Flutter's own (with framework widgets)",
  );

  /// The kinds in the order they are asked.
  static final List<WidgetNodeKind> nodeKinds = [
    WidgetNodeKind(screen, (visit) => visit.screen),
    WidgetNodeKind(
      spring,
      (visit) =>
          visit.element.widget is SpringStatelessWidget ||
          visit.element.widget is SpringStatefulWidget,
    ),
    WidgetNodeKind(
      stateful,
      (visit) => visit.app && visit.element is StatefulElement,
    ),
    WidgetNodeKind(stateless, (visit) => visit.app),
    WidgetNodeKind(framework, (visit) => true),
  ];

  /// Whether the widget of [element] is the application's: a Spring
  /// widget, or one whose `build` makes what is created in [files] (not a
  /// builder: [DebugGraphWidgets.builders]).
  static bool isAppElement(Element element, AppWidgetFiles files) {
    Widget? child;
    var count = 0;
    element.visitChildren((each) {
      count++;
      child = each.widget;
    });
    return _isApp(element, count == 1 ? child : null, files);
  }

  static bool _isApp(Element element, Widget? child, AppWidgetFiles files) {
    final widget = element.widget;
    if (widget is SpringStatelessWidget || widget is SpringStatefulWidget) {
      return true;
    }
    if (element is! ComponentElement || element is ProxyElement) {
      return false;
    }
    if (!files.known || child == null) {
      return false;
    }
    return !DebugGraphWidgets.isBuilder(widget) && files.created(child);
  }

  /// What the node of [widget] says: its type, with its key when short
  /// (`ReviewTile [3]`).
  static String labelOf(Widget widget) =>
      _Tree._labelOf(widget, '${widget.runtimeType}');

  @override
  String get id => 'widgets';

  @override
  String get title => 'Widgets';

  @override
  int get order => 10;

  @override
  Color colorOf(DebugStyle style) => style.graphLayer(id, orElse: style.logger);

  @override
  String get flashMeaning => 'a widget built';

  @override
  String get heatMeaning => 'rebuilt $hotRebuilds+ in ${_seconds(hotWindow)} s';

  @override
  String? hotNoteOf(DebugGraphNode node) {
    final source = node.source;
    if (source is! _WidgetNode || heatOf(node) <= 0) {
      return null;
    }
    final (label, count) = _hotSources[source.element] ?? ('', 0);
    final note = '$label: $count rebuilds in ${_seconds(hotWindow)} s';
    return label == source.label ? note : 'above $note';
  }

  static String _seconds(Duration window) => window.inMilliseconds % 1000 == 0
      ? '${window.inSeconds}'
      : (window.inMilliseconds / 1000).toStringAsFixed(1);

  @override
  List<DebugGraphKind> get kinds => [for (final rule in nodeKinds) rule.kind];

  @override
  DebugGraphLayout get layout => _byRoute
      ? const TreeDebugGraphLayout(banded: true)
      : const TreeDebugGraphLayout();

  /// Its groups are lanes with the route grouping, and only scope its
  /// repeats without it.
  @override
  bool get lanes => _byRoute;

  bool get _byRoute => routes?.byRoute ?? false;

  @override
  List<DebugGraphChoice> get choices => routes?.choicesOf(this) ?? const [];

  @override
  List<DebugGraphOption> get options => [
    DebugGraphOption(
      label: 'framework widgets',
      value: _everything,
      onChanged: (value) {
        _everything = value;
        _walk(notify: true);
      },
    ),
  ];

  @override
  Listenable get changes => _changes;

  /// Whether a view shows it now.
  bool get started => _users > 0;

  @override
  void Function() start() {
    final stopRoutes = routes?.start(this);
    if (_users++ == 0) {
      routes?.addListener(_routesChanged);
      rebuilds
        ..onRebuild = _heard
        ..start();
      _walk();
      _timer = Timer.periodic(walkEvery, (_) {
        if (_dirty) {
          _dirty = false;
          _walk(notify: true);
        }
      });
      _hookFrame();
    }
    var stopped = false;
    return () {
      if (stopped) {
        return;
      }
      stopped = true;
      stopRoutes?.call();
      if (--_users == 0) {
        routes?.removeListener(_routesChanged);
        _timer?.cancel();
        _timer = null;
        rebuilds.stop();
        _tree = _Tree.empty;
        _lastAt.clear();
        _hits.clear();
        _hitFrame.clear();
        _counts = null;
        _heat = null;
        _propertyRows.clear();
        _highlight.hide();
      }
    };
  }

  // The grouping or the navigator stack changed: the lanes are read again.
  void _routesChanged() => _walk(notify: true);

  // After each frame while shown: the tree may have changed.
  void _hookFrame() {
    if (_frameHooked || !started) {
      return;
    }
    _frameHooked = true;
    try {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _frameHooked = false;
        _frame++;
        _dirty = true;
        _hookFrame();
      });
    } on Object {
      _frameHooked = false;
    }
  }

  void _heard(Element element) {
    final owner = _tree.owner[element];
    if (owner == null) {
      return;
    }
    final now = rebuilds.now;
    _lastAt[owner] = now;
    // Once a frame for a node, however many of its elements built.
    final frame = _frame;
    if (_hitFrame[owner] != frame) {
      _hitFrame[owner] = frame;
      final hits = _hits[owner] ??= Queue();
      hits.addLast(now);
      if (hits.length > 512) {
        hits.removeFirst();
      }
    }
    if (_wakers.isEmpty || _waking) {
      return;
    }
    final woken = _wokenAt;
    if (woken != null && now - woken < const Duration(milliseconds: 100)) {
      return;
    }
    _wokenAt = now;
    _waking = true;
    scheduleMicrotask(() {
      _waking = false;
      for (final wake in List.of(_wakers)) {
        wake();
      }
    });
  }

  @override
  void Function() onActivity(VoidCallback wake) {
    _wakers.add(wake);
    return () => _wakers.remove(wake);
  }

  /// Walks the tree now; tells [changes] when [notify] and it changed.
  void walkNow() => _walk(notify: true);

  void _walk({bool notify = false}) {
    final root = _root();
    final files = this.files ??= AppWidgetFiles.of(root);
    final tree = _Tree.walk(
      root,
      files: files,
      everything: _everything,
      rebuilds: rebuilds,
      stack: _byRoute ? routes!.stack : null,
    );
    final changed = tree.signature != _tree.signature;
    _tree = tree;
    _propertyRows.clear();
    rebuilds.prune();
    _lastAt.removeWhere((element, _) => !element.mounted);
    _hits.removeWhere((element, _) => !element.mounted);
    _hitFrame.removeWhere((element, _) => !element.mounted);
    if (notify && changed) {
      _counts = null;
      _heat = null;
      _changes.changed();
    }
  }

  /// The id of the node [holder] is in: an element, a `BuildContext`, a
  /// `State` or a widget the last walk passed; the node of the nearest
  /// shown widget at or above it. `null` when the layer has not walked
  /// past it (hidden, or newer than the last walk).
  String? nodeIdOf(Object holder) {
    final element = switch (holder) {
      final Element element => element,
      final State<StatefulWidget> state when state.mounted =>
        state.context as Element,
      final Widget widget => _tree.byWidget[widget],
      _ => null,
    };
    if (element == null) {
      return null;
    }
    final owner = _tree.owner[element];
    if (owner != null) {
      return DebugGraphWidgets.idOf(owner);
    }
    if (!element.mounted) {
      return null;
    }
    Element? found;
    element.visitAncestorElements((ancestor) {
      found = _tree.owner[ancestor];
      return found == null;
    });
    return found == null ? null : DebugGraphWidgets.idOf(found!);
  }

  @override
  DebugGraphPart collect(DebugGraphScope scope) {
    if (_tree.nodes.isEmpty && started) {
      _walk();
    }
    final nodes = _tree.nodes;
    final onScreen = scope == DebugGraphScope.onScreen ? _visible(nodes) : null;
    return DebugGraphPart(
      [
        for (var i = 0; i < nodes.length; i++)
          DebugGraphNode(
            id: DebugGraphWidgets.idOf(nodes[i].element),
            layer: id,
            kind: nodes[i].kind.id,
            label: nodes[i].label,
            group: switch ((nodes[i].lane, nodes[i].parent)) {
              (final lane?, _) => lane.key,
              (null, final parent?) => DebugGraphWidgets.idOf(parent),
              (null, null) => null,
            },
            groupTitle: nodes[i].lane?.title,
            groupOrder: nodes[i].lane?.order,
            groupRole: nodes[i].lane?.role,
            repeatScope: switch ((nodes[i].lane, nodes[i].parent)) {
              (_?, final parent?) => DebugGraphWidgets.idOf(parent),
              _ => null,
            },
            repeatKey: nodes[i].type,
            widget: nodes[i].element,
            source: nodes[i],
            onScreen: onScreen?[i],
          ),
      ],
      [
        for (final node in nodes)
          if (node.parent case final parent?)
            DebugGraphEdge(
              DebugGraphWidgets.idOf(parent),
              DebugGraphWidgets.idOf(node.element),
              kind: 'child',
            ),
      ],
    );
  }

  // Which nodes are on the screen, in one pass over the render tree: a
  // node whose box shows, not under a TickerMode that is off, and every
  // node above one that shows.
  List<bool> _visible(List<_WidgetNode> nodes) {
    final shown = _shownNow();
    final visible = List<bool>.filled(nodes.length, false);
    final index = HashMap<Element, int>.identity();
    for (var i = 0; i < nodes.length; i++) {
      index[nodes[i].element] = i;
      final node = nodes[i];
      if (node.tickerOff || !node.element.mounted) {
        continue;
      }
      RenderObject? object;
      try {
        object = (node.marker ?? node.element).findRenderObject();
      } on Object {
        object = null;
      }
      visible[i] = object == null || shown == null || shown.contains(object);
    }
    for (var i = nodes.length - 1; i >= 0; i--) {
      if (visible[i]) {
        if (index[nodes[i].parent] case final parent?) {
          visible[parent] = true;
        }
      }
    }
    return visible;
  }

  // The render objects on the screen. Read in the middle of a frame (the
  // graph built while the debug panel opens or closes), what the frame
  // makes is not laid out yet: the last reading serves, or none (all
  // shown), and the screen is read again once the frame is done, telling
  // [changes] when it differs.
  Set<RenderObject>? _shown;
  bool _shownPending = false;

  Set<RenderObject>? _shownNow() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.persistentCallbacks &&
        phase != SchedulerPhase.midFrameMicrotasks) {
      return _shown = _readScreen();
    }
    if (!_shownPending) {
      _shownPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _shownPending = false;
        final before = _shown;
        final now = _shown = _readScreen();
        if (before == null ||
            before.length != now.length ||
            !before.containsAll(now)) {
          _changes.changed();
        }
      });
    }
    return _shown;
  }

  static Set<RenderObject> _readScreen() =>
      DebugGraphScreen.shownObjects(RendererBinding.instance.renderViews);

  // The rebuilds within the window of each node, with its last and mean
  // build time: worked out at most every quarter second.
  Map<Element, (int, Duration?, Duration?)> _countsNow() {
    final now = rebuilds.now;
    final at = _countedAt;
    final kept = _counts;
    if (kept != null && at != null && now - at < walkEvery) {
      return kept;
    }
    final counts = HashMap<Element, (int, Duration?, Duration?)>.identity();
    for (final MapEntry(key: owner, value: hits) in _hits.entries) {
      while (hits.isNotEmpty && now - hits.first > hotWindow) {
        hits.removeFirst();
      }
      final own = rebuilds.of(owner);
      counts[owner] = (hits.length, own?.lastTook, own?.averageTook);
    }
    _countedAt = now;
    _heat = null;
    return _counts = counts;
  }

  @override
  double heatOf(DebugGraphNode node) {
    final source = node.source;
    if (source is! _WidgetNode) {
      return 0;
    }
    // Counted again once the counts are older than a walk, which clears
    // the heat: the rebuilds that left the window cool their branch.
    final at = _countedAt;
    if (at == null || rebuilds.now - at >= walkEvery) {
      _countsNow();
    }
    final heat = _heat ??= () {
      final counts = _countsNow();
      var most = 0;
      for (final (count, _, _) in counts.values) {
        if (count > most) {
          most = count;
        }
      }
      final heat = HashMap<Element, double>.identity();
      // Which hot widget makes each node hot, for its tooltip.
      final sources = _hotSources = HashMap.identity();
      if (most < hotRebuilds) {
        return heat;
      }
      // A hot widget, and the branch above it.
      final nodes = _tree.nodes;
      for (var i = nodes.length - 1; i >= 0; i--) {
        final element = nodes[i].element;
        final own = counts[element]?.$1 ?? 0;
        final value = own >= hotRebuilds ? own / most : 0.0;
        final kept = heat[element] ?? 0;
        if (value > kept) {
          sources[element] = (nodes[i].label, own);
        }
        final mine = value > kept ? value : kept;
        if (mine > 0) {
          heat[element] = mine;
          if (nodes[i].parent case final parent?) {
            if ((heat[parent] ?? 0) < mine) {
              heat[parent] = mine;
              if (sources[element] case final source?) {
                sources[parent] = source;
              }
            }
          }
        }
      }
      return heat;
    }();
    return heat[source.element] ?? 0;
  }

  @override
  double glowOf(DebugGraphNode node) {
    final source = node.source;
    if (source is! _WidgetNode) {
      return 0;
    }
    final at = _lastAt[source.element];
    if (at == null) {
      return 0;
    }
    final age = rebuilds.now - at;
    const fade = Duration(seconds: 1);
    return age >= fade ? 0 : 1 - age.inMicroseconds / fade.inMicroseconds;
  }

  @override
  bool isLive(DebugGraphNode node, Duration window) {
    final source = node.source;
    if (source is! _WidgetNode) {
      return false;
    }
    final at = _lastAt[source.element];
    return at != null && rebuilds.now - at <= window;
  }

  @override
  List<DebugGraphDetail> detailsOf(DebugGraphNode node) {
    final source = node.source;
    if (source is! _WidgetNode || !source.element.mounted) {
      return node.details;
    }
    final element = source.element;
    final widget = element.widget;
    final box = element.findRenderObject();
    final (count, last, average) = _countsNow()[element] ?? (0, null, null);
    final beans = _beansOf(widget);
    return [
      DebugGraphDetail('type', '${widget.runtimeType}'),
      if (widget.key case final key?) DebugGraphDetail('key', '$key'),
      if (box is RenderBox && box.hasSize && box.attached) ...[
        DebugGraphDetail(
          'size',
          '${box.size.width.toStringAsFixed(1)} × '
              '${box.size.height.toStringAsFixed(1)}',
        ),
        DebugGraphDetail('position', _position(box)),
      ],
      if (element case StatefulElement(:final state))
        DebugGraphDetail('state', '${state.runtimeType}'),
      if (source.route case final route?) DebugGraphDetail('route', route),
      if (beans.isNotEmpty)
        DebugGraphDetail(
          'beans',
          '${beans.length}',
          links: [
            for (final bean in beans)
              DebugGraphDetailLink(bean, target: 'beans:$bean'),
          ],
        ),
      DebugGraphDetail(
        'rebuilds',
        '$count in ${_seconds(hotWindow)}s'
            '${rebuilds.hearsEach ? '' : ' (seen between walks)'}',
      ),
      if (last != null)
        DebugGraphDetail(
          'build',
          '${_took(last)} last'
              '${average == null ? '' : ' · ${_took(average)} avg'}',
        ),
      if (AppWidgetFiles.locationOf(widget) case final where?)
        DebugGraphDetail('created', where.split('/').last),
      ...(_propertyRows[element] ??= _propertiesOf(element)),
    ];
  }

  // The rows of [element]'s properties blocks, each source in turn, a name
  // a source before told left out; the widget's block first, then its
  // State's, then any other a source adds.
  List<DebugGraphDetail> _propertiesOf(Element element) {
    final told = <String>{};
    final sections = <String?, List<DebugGraphDetail>>{
      WidgetProperties.widget: [],
      WidgetProperties.state: [],
    };
    for (final source in properties) {
      for (final row in source.rowsOf(element)) {
        if (told.add('${row.section}\u0000${row.label}')) {
          (sections[row.section] ??= []).add(row);
        }
      }
    }
    return [for (final rows in sections.values) ...rows];
  }

  static String _position(RenderBox box) {
    final at = box.localToGlobal(Offset.zero);
    return '${at.dx.toStringAsFixed(1)}, ${at.dy.toStringAsFixed(1)}';
  }

  static String _took(Duration took) => took.inMicroseconds < 1000
      ? '${took.inMicroseconds}µs'
      : '${(took.inMicroseconds / 1000).toStringAsFixed(1)}ms';

  // The beans of a Spring widget, by name when the context knows them.
  List<String> _beansOf(Widget widget) {
    final beansType = switch (widget) {
      final SpringStatelessWidget<Record> spring => spring.beansType,
      final SpringStatefulWidget<Record> spring => spring.beansType,
      _ => null,
    };
    final context = this.context;
    if (beansType == null || context == null) {
      return const [];
    }
    final binding = SpringWidgetBindings.bindingOf(context, beansType);
    if (binding == null) {
      return ['$beansType'];
    }
    return [
      for (final type in binding.types)
        switch (context.getBeanNamesForType(type)) {
          [final name] => name,
          [] => '$type',
          final names => '$type (${names.join(', ')})',
        },
    ];
  }

  @override
  void select(DebugGraphNode? node) {
    final source = node?.source;
    if (source is! _WidgetNode || !source.element.mounted) {
      _highlight.hide();
      return;
    }
    _highlight.show(source.element, _root());
  }

  /// The rectangle outlined over the app now, in the app's coordinates;
  /// `null`: none.
  Rect? get highlighted => _highlight.rect;

  /// Frees what it keeps (the bean, when it is destroyed).
  void dispose() {
    _timer?.cancel();
    rebuilds.dispose();
    _highlight.hide();
    _changes.dispose();
  }
}

final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}

// A widget shown as a node.
final class _WidgetNode {
  _WidgetNode({
    required this.element,
    required this.parent,
    required this.kind,
    required this.label,
    required this.type,
    required this.tickerOff,
    required this.marker,
    required this.route,
    required this.lane,
  });

  final Element element;
  final Element? parent;
  final DebugGraphKind kind;
  final String label;
  final String type;
  final bool tickerOff;
  final Element? marker;
  final String? route;
  final DebugGraphRoute? lane;
}

// The walk's state down a branch.
final class _Branch {
  const _Branch({
    this.owner,
    this.tickerOff = false,
    this.marker,
    this.route,
    this.inRoute = false,
    this.screenFound = false,
    this.overlayLevel = 0,
    this.lane,
  });

  final Element? owner;
  final bool tickerOff;
  final Element? marker;
  final String? route;
  final bool inRoute;
  final bool screenFound;
  final int overlayLevel;
  final DebugGraphRoute? lane;
}

// The tree as one walk saw it: the nodes in depth-first order (a parent
// before its children), and the node each element is folded into.
final class _Tree {
  _Tree(this.nodes, this.owner, this.byWidget, this.signature);

  static final empty = _Tree(
    const [],
    HashMap.identity(),
    HashMap.identity(),
    0,
  );

  final List<_WidgetNode> nodes;
  final Map<Element, Element> owner;
  final Map<Widget, Element> byWidget;
  final int signature;

  static _Tree walk(
    Element? root, {
    required AppWidgetFiles files,
    required bool everything,
    required WidgetRebuilds rebuilds,
    DebugNavigatorStack? stack,
  }) {
    final nodes = <_WidgetNode>[];
    final owner = HashMap<Element, Element>.identity();
    final byWidget = HashMap<Widget, Element>.identity();
    var signature = 17;
    if (root == null) {
      return _Tree(nodes, owner, byWidget, 0);
    }
    final pending = <(Element, _Branch)>[
      (root, _Branch(lane: stack == null ? null : DebugGraphRoute.app)),
    ];
    while (pending.isNotEmpty) {
      final (element, branch) = pending.removeLast();
      final widget = element.widget;
      if (widget.key is DebugToolSubtree) {
        continue;
      }
      final lane = stack?.startingAt(element) ?? branch.lane;
      final children = <Element>[];
      element.visitChildren(children.add);
      final child = children.length == 1 ? children.first.widget : null;
      rebuilds.seen(element, child);
      final app = WidgetsGraphLayer._isApp(element, child, files);
      final screen = app && branch.inRoute && !branch.screenFound;
      final shown = app || everything;
      final tickerOff =
          branch.tickerOff || (widget is TickerMode && !widget.enabled);
      final marker =
          branch.marker ?? (widget.key is PaintedElsewhere ? element : null);
      if (shown) {
        final type = '${widget.runtimeType}';
        final visit = WidgetVisit(element, app: app, screen: screen);
        final kind = WidgetsGraphLayer.nodeKinds
            .firstWhere((rule) => rule.matches(visit))
            .kind;
        nodes.add(
          _WidgetNode(
            element: element,
            parent: branch.owner,
            kind: kind,
            label: _labelOf(widget, type),
            type: type,
            tickerOff: tickerOff,
            marker: marker,
            route: branch.route,
            lane: lane,
          ),
        );
        owner[element] = element;
        byWidget[widget] = element;
        signature = Object.hash(
          signature,
          identityHashCode(element),
          identityHashCode(branch.owner),
          kind.id,
          lane?.key,
          lane?.role,
          lane?.order,
        );
      } else if (branch.owner case final above?) {
        owner[element] = above;
      }
      final next = _Branch(
        owner: shown ? element : branch.owner,
        tickerOff: tickerOff,
        marker: marker,
        route: branch.route,
        inRoute: branch.inRoute,
        screenFound: branch.screenFound || screen,
        overlayLevel: widget is Overlay
            ? 1
            : (branch.overlayLevel == 1 ? 2 : 0),
        lane: lane,
      );
      for (var i = children.length - 1; i >= 0; i--) {
        pending.add((
          children[i],
          next.overlayLevel == 2
              ? _Branch(
                  owner: next.owner,
                  tickerOff: next.tickerOff,
                  marker: next.marker,
                  route:
                      'route ${i + 1} of ${children.length}'
                      '${i == children.length - 1 ? ' (top)' : ''}',
                  inRoute: true,
                  lane: lane,
                )
              : next,
        ));
      }
    }
    return _Tree(nodes, owner, byWidget, signature);
  }

  static String _labelOf(Widget widget, String type) => switch (widget.key) {
    ValueKey<Object?>(value: final int value) => '$type [$value]',
    ValueKey<Object?>(value: final Enum value) => '$type [${value.name}]',
    ValueKey<Object?>(value: final String value)
        when RegExp(r'^[A-Za-z0-9_.:\-]{1,24}$').hasMatch(value) =>
      '$type [$value]',
    _ => type,
  };
}
