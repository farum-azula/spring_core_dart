import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_assembly.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_card.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_fit_action.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_legend.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_memory.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_scene.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_toolbar.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/layered_debug_graph_layout.dart';

/// The application graph of [layers]: one toolbar row above it, the graph
/// filling the room left, a card beside the plate tapped.
///
/// The toolbar: the layers' switches (each with its colour's square), the
/// scope (On screen, All) and Fit; `Options ▾`, a menu of checkboxes for
/// what is changed rarely ("Live only", every layer's own options and
/// single choices, [DebugGraphLayer.options], [DebugGraphLayer.choices]);
/// `Groups ▾`, a list of the lanes to show with a search field, the
/// groups chosen last first (`Groups: all`, `Groups: 3`); `Legend`, which
/// opens the legend over the graph ([DebugGraphLegend]). In the panel the
/// row wraps; in the console ([compact]) the labels are short and the
/// pointer over a button tells its full name.
///
/// The graph fits itself (as [fit] says) only the first time a view opens
/// with something to show (its [memory] has no place yet) and on Fit:
/// never on a tap, a selection, a fold, a filter, a refresh of the layers,
/// a flash or a resize. The scale never changes but by the user; when the
/// layout changes, the graph is shifted so that the plate tapped (else the
/// one nearest the middle) stays where it was, and when the room shrinks
/// or the graph changed so much that it would be out of sight, it is
/// shifted back just into the room. A wheel or a drag pans it, ⌘ or Ctrl
/// with the wheel and a pinch zoom it; the wheel is the graph's alone,
/// nothing around it scrolls. A tap on a plate highlights everything
/// before and after it and opens its card ([DebugGraphDetails]) beside
/// it, a tap on another plate another card: one line, a tap opens its
/// rows, `×` closes it, `Close all cards` in Options closes them all; a
/// card follows its plate as the graph pans and zooms. A tap on a folded
/// plate (`PlayerReviews ×10`, a collapsed lane) opens it; a tap on a
/// lane's title collapses the lane. The pointer over a plate shows its
/// tooltip, with why it is hot when it is ([DebugGraphLayer.hotNoteOf]).
///
/// What it shows, where, the legend's selection and the cards open are
/// kept in [memory], held by a bean, so the view opens again as it was
/// left while the app runs.
///
/// It lays the graph out only when what is shown changes, paints the still
/// picture once per layout and, while something glows, only the lit
/// plates and pulses over it, at most once a frame. The layers collect
/// only while it shows; not shown, it costs nothing. Give it a bounded
/// height and no scrolling parent.
class DebugGraphView extends StatefulWidget {
  /// The graph of [layers].
  const DebugGraphView({
    required this.layers,
    this.compact = false,
    this.settings = const DebugGraphSettings(),
    this.layout,
    this.assembler = const DebugGraphAssembler(),
    this.refresh = const Duration(milliseconds: 300),
    this.memory,
    this.fit = DebugGraphFit.whole,
    super.key,
  });

  /// How the first fit and Fit place the graph: [DebugGraphFit.whole] (the
  /// panel), [DebugGraphFit.width] (a console pane).
  final DebugGraphFit fit;

  /// What it keeps while the app runs, held by a bean (the Graph tab's,
  /// a console pane's); `null`: a memory of its own, lost with it. Its
  /// settings, once set, win over [settings].
  final DebugGraphMemory? memory;

  /// The layers it can show, each with its switch, in their order.
  final List<DebugGraphLayer> layers;

  /// The small look of a console pane.
  final bool compact;

  /// What it shows at the start.
  final DebugGraphSettings settings;

  /// How it is laid out; `null`: the first layer's, else left to right.
  final DebugGraphLayout? layout;

  /// How the layers' nodes become plates: the filters and folds.
  final DebugGraphAssembler assembler;

  /// How often "On screen" and "Live only" are read again while shown.
  final Duration refresh;

  /// The scale under which a fit never goes.
  static const double minScale = 0.05;

  /// The scale over which neither a fit nor a zoom goes.
  static const double maxScale = 4;

  @override
  State<DebugGraphView> createState() => DebugGraphViewState();
}

/// The state of a [DebugGraphView]: what it shows and where.
class DebugGraphViewState extends State<DebugGraphView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onFrame);
  final ValueNotifier<int> _frames = ValueNotifier(0);
  final ValueNotifier<bool> _animating = ValueNotifier(false);
  late final DebugGraphMemory _memory = widget.memory ?? DebugGraphMemory();
  late final ValueNotifier<Matrix4> _transform = ValueNotifier(
    _memory.transform?.clone() ?? Matrix4.identity(),
  );
  final Map<DebugGraphLayer, void Function()> _stops = {};
  final Map<DebugGraphLayer, List<void Function()>> _listening = {};
  Timer? _refresh;
  bool _queued = false;

  DebugGraph? _graph;
  DebugGraphScene? _scene;
  int? _styleKey;
  DebugGraphPainter? _painter;
  Map<int, double> _heat = const {};
  Set<int>? _marked;
  // The plate under the pointer, by its key (an index would name another
  // plate once the scene is made again), and where the pointer is.
  (String, Offset)? _hover;

  final GlobalKey _root = GlobalKey();
  final Map<String, GlobalKey> _anchors = {};
  String? _popup;
  (String, String)? _hint;

  Size? _viewport;
  DebugGraphScene? _sighted;
  late bool _fitPending = _memory.autoFit || _memory.transform == null;
  bool _gesture = false;
  Matrix4 _gestureStart = Matrix4.identity();
  Offset _gestureFocal = Offset.zero;

  static const _options = 'options';
  static const _groups = 'groups';

  /// What it shows now.
  DebugGraphSettings get settings => _settings;

  DebugGraphSettings get _settings => _memory.settings ?? widget.settings;

  set _settings(DebugGraphSettings settings) => _memory.settings = settings;

  String? get _selected => _memory.selected;

  set _selected(String? key) => _memory.selected = key;

  /// What it keeps while the app runs.
  DebugGraphMemory get memory => _memory;

  /// The graph as shown now.
  DebugGraph? get graph => _graph;

  /// The laid-out graph as painted now.
  DebugGraphScene? get scene => _scene;

  /// Where the graph is in its room: its scale and offset.
  Matrix4 get transform => _transform.value;

  /// The plates of the legend entries selected, by index; `null`: none
  /// selected.
  Set<int>? get marked => _marked;

  /// How many times the graph was laid out.
  int layouts = 0;

  @override
  void initState() {
    super.initState();
    _memory.settings ??= widget.settings;
    _startLayers();
    _refresh = Timer.periodic(widget.refresh, (_) => _reread());
    _memory.addListener(_remembered);
    // The action `debug.graph.fit` (⌘⇧Z) fits every graph on the screen.
    _fitAction =
        SpringScope.maybeOf(
            context,
            listen: false,
          )?.getBeansOfType<DebugGraphFitAction>().values.firstOrNull
          ?..addListener(fit);
    if (_selected != null) {
      // Opened again with a plate tapped: the layer shows it again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _tell(_selected);
        }
      });
    }
  }

  @override
  void didUpdateWidget(DebugGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.layers, widget.layers)) {
      _stopLayers();
      _startLayers();
      _change();
    }
  }

  // Where the user (or a fit, or the shift that keeps the plate tapped in
  // place) put the graph: what the memory keeps. Keeping it in sight in a
  // smaller room changes only what is shown, never this.
  void _place(Matrix4 transform) {
    _transform.value = transform;
    _memory.transform = transform.clone();
  }

  DebugGraphFitAction? _fitAction;

  @override
  void dispose() {
    _fitAction?.removeListener(fit);
    _memory.removeListener(_remembered);
    if (widget.memory == null) {
      _memory.dispose();
    }
    _refresh?.cancel();
    for (final layer in widget.layers) {
      layer.select(null);
    }
    _stopLayers();
    _ticker.dispose();
    _frames.dispose();
    _animating.dispose();
    _transform.dispose();
    _scene?.dispose();
    super.dispose();
  }

  List<DebugGraphLayer> get _shown => [
    for (final layer in widget.layers)
      if (!_settings.hiddenLayers.contains(layer.id)) layer,
  ];

  void _startLayers() {
    for (final layer in _shown) {
      _startLayer(layer);
    }
  }

  void _startLayer(DebugGraphLayer layer) {
    if (_stops.containsKey(layer)) {
      return;
    }
    _stops[layer] = layer.start();
    layer.changes.addListener(_queue);
    _listening[layer] = [
      () => layer.changes.removeListener(_queue),
      layer.onActivity(_wake),
    ];
  }

  void _stopLayers() {
    for (final layer in [..._stops.keys]) {
      _stopLayer(layer);
    }
  }

  void _stopLayer(DebugGraphLayer layer) {
    _stops.remove(layer)?.call();
    for (final stop in _listening.remove(layer) ?? const <void Function()>[]) {
      stop();
    }
  }

  void _wake() {
    if (mounted && !_ticker.isActive) {
      _animating.value = true;
      unawaited(_ticker.start());
    }
  }

  // The legend's selection changed (here or in another view).
  void _remembered() {
    if (mounted) {
      setState(() {});
    }
  }

  // Drawn each frame while something glows; stopped once nothing does
  // (after the first frames, which paint what woke it).
  void _onFrame(Duration elapsed) {
    _frames.value++;
    if (elapsed > const Duration(milliseconds: 50) &&
        (_painter?.lastFrame?.dark ?? true)) {
      _ticker.stop();
      _animating.value = false;
    }
  }

  // A layer changed: read again soon, once however many changed.
  void _queue() {
    if (_queued) {
      return;
    }
    _queued = true;
    Timer.run(() {
      _queued = false;
      if (mounted) {
        _change();
      }
    });
  }

  // "On screen" and "Live only" move with the app: read again while shown,
  // and so do the hot branches and the legend's marks of what flashed.
  void _reread() {
    if (!mounted) {
      return;
    }
    if (_settings.scope == DebugGraphScope.onScreen || _settings.liveOnly) {
      _change();
    }
    _rereadHeat();
    if (_memory.legend.isNotEmpty && _updateMarks()) {
      setState(() {});
    }
  }

  // The hot branches, by tenths: drawn again only when they change.
  void _rereadHeat() {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    final layers = {for (final layer in scene.graph.layers) layer.id: layer};
    final heat = <int, double>{};
    for (var i = 0; i < scene.graph.items.length; i++) {
      var hot = 0.0;
      for (final node in scene.graph.items[i].nodes) {
        final value = layers[node.layer]?.heatOf(node) ?? 0;
        if (value > hot) {
          hot = value;
        }
      }
      if (hot > 0) {
        heat[i] = (hot * 10).ceilToDouble() / 10;
      }
    }
    if (!mapEquals(heat, _heat)) {
      setState(() => _heat = heat);
    }
  }

  /// The hot plates now, by index.
  Map<int, double> get heat => _heat;

  // The plates of the legend entries selected, set again only when they
  // differ (the still picture is kept by its identity).
  bool _updateMarks() {
    final scene = _scene;
    if (scene == null) {
      return false;
    }
    final memory = _memory;
    final chosen = memory.legend.isEmpty
        ? const <DebugGraphLegendEntry>[]
        : [
            for (final layer in scene.graph.layers)
              for (final entry in DebugGraphLegendEntry.of(layer))
                if (memory.isSelected(entry.key)) entry,
          ];
    final marked = DebugGraphLegend.marksOf(
      scene.graph,
      chosen,
      _settings.liveWindow,
    );
    if (setEquals(marked, _marked)) {
      return false;
    }
    _marked = marked;
    return true;
  }

  // Tells the layers which node is tapped, for those that show it in the
  // app too.
  void _tell(String? key) {
    final graph = _scene?.graph;
    final index = key == null ? null : graph?.indexOf(key);
    final item = index == null ? null : graph!.items[index];
    for (final layer in _shown) {
      layer.select(item != null && item.layer == layer.id ? item.node : null);
    }
  }

  // The graph made again. Of the same structure, it replaces the nodes
  // (and the scene's) without a build: the cards read the newest
  // `DebugGraphNode.source`; else it is built and laid out again.
  void _change() {
    final graph = _assemble();
    if (graph.signature != _graph?.signature) {
      setState(() => _graph = graph);
      return;
    }
    _graph = graph;
    final scene = _scene;
    if (scene != null && scene.graph.signature == graph.signature) {
      scene.useGraph(graph);
    }
  }

  DebugGraph _assemble() => widget.assembler.assemble([
    for (final layer in _shown) (layer, layer.collect(_settings.scope)),
  ], _settings);

  /// Shows [settings] instead; the graph stays where it is. Only the
  /// layers it hides or shows are stopped or started; a layer it hides is
  /// told that nothing of it is selected any more.
  void apply(DebugGraphSettings settings) {
    final before = _shown.toSet();
    _settings = settings;
    final after = _shown.toSet();
    for (final layer in before.difference(after)) {
      layer.select(null);
      _stopLayer(layer);
    }
    after.difference(before).forEach(_startLayer);
    final graph = _assemble();
    setState(() => _graph = graph);
  }

  /// Fits and centres the graph in its room.
  void fit() {
    setState(() => _fitPending = true);
  }

  // The toolbar's Auto: on, fitted now and whenever it changes.
  void _toggleAuto() {
    setState(() {
      _memory.autoFit = !_memory.autoFit;
      if (_memory.autoFit) {
        _fitPending = true;
      }
    });
  }

  // The user moves or zooms the graph: Auto ends, the place is theirs.
  void _manual() {
    if (_memory.autoFit) {
      setState(() => _memory.autoFit = false);
    }
  }

  DebugGraphScene _sceneFor(DebugStyle style) {
    final graph = _graph ??= _assemble();
    final styleKey = Object.hash(
      style.code.fontSize,
      style.code.fontFamily,
      style.foreground,
      style.background,
      style.graphFlash,
      widget.compact,
    );
    final scene = _scene;
    if (scene != null &&
        scene.graph.signature == graph.signature &&
        styleKey == _styleKey) {
      if (!identical(scene.graph, graph)) {
        scene.useGraph(graph);
      }
      return scene;
    }
    _styleKey = styleKey;
    layouts++;
    final owner = widget.layout == null
        ? _shown.where((layer) => layer.layout != null).firstOrNull
        : null;
    final layout =
        widget.layout ?? owner?.layout ?? const LayeredDebugGraphLayout();
    final built = DebugGraphScene.of(
      graph,
      style: style,
      layout: widget.compact && layout is LayeredDebugGraphLayout
          ? const LayeredDebugGraphLayout(columnGap: 44, nodeGap: 6)
          : layout,
      compact: widget.compact,
      primaryLayer: owner?.id,
    );
    if (scene != null && !_fitPending && !_memory.autoFit) {
      _keepInPlace(scene, built);
    }
    scene?.dispose();
    return _scene = built;
  }

  // The graph laid out again: the plate tapped (else one with a card,
  // else the one nearest the middle of the room) stays where it was on
  // the screen; the scale is left as it is.
  void _keepInPlace(DebugGraphScene old, DebugGraphScene built) {
    final viewport = _viewport;
    if (viewport == null || old.graph.items.isEmpty) {
      return;
    }
    final kept = {for (final item in built.graph.items) item.key};
    String? anchor;
    for (final key in [?_selected, ..._memory.cards]) {
      if (kept.contains(key) && old.graph.indexOf(key) != null) {
        anchor = key;
        break;
      }
    }
    if (anchor == null) {
      final middle = _toScene(viewport.center(Offset.zero));
      var nearest = double.infinity;
      for (var i = 0; i < old.graph.items.length; i++) {
        final key = old.graph.items[i].key;
        if (!kept.contains(key)) {
          continue;
        }
        final distance = (old.rects[i].center - middle).distanceSquared;
        if (distance < nearest) {
          nearest = distance;
          anchor = key;
        }
      }
    }
    if (anchor == null) {
      return;
    }
    final delta =
        old.rects[old.graph.indexOf(anchor)!].center -
        built.rects[built.graph.indexOf(anchor)!].center;
    if (delta.distanceSquared < 0.01) {
      return;
    }
    _place(
      (_memory.transform ?? _transform.value).clone()
        ..translateByDouble(delta.dx, delta.dy, 0, 1),
    );
  }

  // Fits [scene] in [viewport] as the view's [DebugGraphFit] does; false
  // when there is nothing to fit.
  bool _fitTo(Size viewport, DebugGraphScene scene) {
    final size = scene.size;
    if (scene.graph.items.isEmpty || size.isEmpty || viewport.isEmpty) {
      return false;
    }
    _place(widget.fit.place(size, viewport));
    return true;
  }

  // Shows the graph where it was placed, or, when that leaves it wholly
  // out of [viewport] (a smaller room, a graph that changed), with its
  // edge pulled back into the room. The scale and the place kept are left
  // as they are: in a room big enough again (a pane growing back as the
  // console opens) the graph shows where it was left.
  void _keepInSight(Size viewport, DebugGraphScene scene) {
    final placed = _memory.transform ?? _transform.value;
    if (scene.graph.items.isEmpty || viewport.isEmpty) {
      return;
    }
    final shown = MatrixUtils.transformRect(placed, Offset.zero & scene.size);
    final margin = math.min(48.0, viewport.shortestSide / 4);
    double shift(double low, double high, double room) =>
        high <= 0 ? margin - high : (low >= room ? room - margin - low : 0);
    final dx = shift(shown.left, shown.right, viewport.width);
    final dy = shift(shown.top, shown.bottom, viewport.height);
    final next = dx == 0 && dy == 0
        ? placed.clone()
        : (Matrix4.identity()
            ..translateByDouble(dx, dy, 0, 1)
            ..multiply(placed));
    if (next != _transform.value) {
      _transform.value = next;
    }
  }

  Offset _toScene(Offset local) =>
      MatrixUtils.transformPoint(Matrix4.inverted(_transform.value), local);

  void _zoom(Offset focal, double factor) {
    _manual();
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(
      DebugGraphView.minScale,
      DebugGraphView.maxScale,
    );
    final applied = target / current;
    _place(
      Matrix4.identity()
        ..translateByDouble(focal.dx, focal.dy, 0, 1)
        ..scaleByDouble(applied, applied, 1, 1)
        ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
        ..multiply(_transform.value),
    );
  }

  void _pan(Offset delta) {
    _manual();
    _place(
      Matrix4.identity()
        ..translateByDouble(delta.dx, delta.dy, 0, 1)
        ..multiply(_transform.value),
    );
  }

  // The wheel pans, with ⌘ or Ctrl it zooms; a browser's pinch zooms. The
  // signal is the graph's alone: nothing around it scrolls.
  void _signal(PointerSignalEvent event) {
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      switch (event) {
        case PointerScrollEvent(:final scrollDelta, :final localPosition):
          final keys = HardwareKeyboard.instance;
          if (keys.isControlPressed || keys.isMetaPressed) {
            _zoom(localPosition, math.exp(-scrollDelta.dy / 300));
          } else {
            _pan(-scrollDelta);
          }
        case PointerScaleEvent(:final scale, :final localPosition):
          _zoom(localPosition, scale);
        default:
          break;
      }
    });
  }

  void _scaleStart(ScaleStartDetails details) {
    _gesture = true;
    _gestureStart = _transform.value.clone();
    _gestureFocal = details.localFocalPoint;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    _manual();
    final focal = details.localFocalPoint;
    final current = _gestureStart.getMaxScaleOnAxis();
    final target = (current * details.scale).clamp(
      DebugGraphView.minScale,
      DebugGraphView.maxScale,
    );
    final factor = target / current;
    _place(
      Matrix4.identity()
        ..translateByDouble(focal.dx, focal.dy, 0, 1)
        ..scaleByDouble(factor, factor, 1, 1)
        ..translateByDouble(-_gestureFocal.dx, -_gestureFocal.dy, 0, 1)
        ..multiply(_gestureStart),
    );
  }

  void _scaleEnd(ScaleEndDetails details) {
    _gesture = false;
    if (_fitPending) {
      setState(() {});
    }
  }

  void _tapAt(Offset local) {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    final at = _toScene(local);
    if (scene.laneTitleAt(at) case final lane?) {
      apply(
        _settings.copyWith(
          collapsed: DebugGraphSettings.toggled(_settings.collapsed, lane.key),
        ),
      );
      return;
    }
    final index = scene.itemAt(at);
    if (index == null) {
      setState(() => _selected = null);
      _tell(null);
      return;
    }
    final item = scene.graph.items[index];
    final fold = item.fold;
    if (item.folded && fold != null) {
      apply(fold.open(_settings));
      return;
    }
    // A second tap on the same plate soon after the first is a double tap:
    // its card opens, and closes again; it stays selected. Told here, not
    // by a double-tap recognizer, which the graph's pan and zoom would
    // win in a browser, and so a single tap selects at once.
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null &&
        last.key == item.key &&
        now.difference(last.at) <= kDoubleTapTimeout) {
      _lastTap = null;
      _toggleCard(item);
      return;
    }
    _lastTap = (key: item.key, at: now);
    // A tap selects the plate and lights its chain, a second tap ends it.
    setState(() {
      _selected = _selected == item.key ? null : item.key;
    });
    _tell(_selected);
  }

  ({String key, DateTime at})? _lastTap;

  // A double tap on a plate opens its card, and closes it again.
  void _toggleCard(DebugGraphItem item) {
    if (_memory.cards.contains(item.key)) {
      _closeCard(item.key);
      return;
    }
    // A card opens with its rows; a tap on its title closes it into a line.
    setState(() {
      _memory.cards.add(item.key);
      _memory.expanded.add(item.key);
      _selected = item.key;
    });
    _tell(_selected);
  }

  // A row of a card names a node on the graph: it is selected and its
  // chain lit, where it is; the view does not move.
  void _selectNode(DebugGraphScene scene, String? id) {
    if (id == null) {
      return;
    }
    for (final item in scene.graph.items) {
      if (item.nodes.any((node) => node.id == id)) {
        setState(() => _selected = item.key);
        _tell(_selected);
        return;
      }
    }
  }

  void _closeCard(String key) {
    setState(() {
      _memory.cards.remove(key);
      _memory.expanded.remove(key);
      if (_selected == key) {
        _selected = null;
      }
    });
    if (_selected == null) {
      _tell(null);
    }
  }

  void _closeCards() {
    _memory.closeCards();
    setState(() => _selected = null);
    _tell(null);
  }

  void _hoverAt(Offset local) {
    final scene = _scene;
    final index = scene?.itemAt(_toScene(local));
    final hover = index == null ? null : (scene!.graph.items[index].key, local);
    if (hover?.$1 != _hover?.$1) {
      setState(() => _hover = hover);
    } else if (hover != null) {
      _hover = hover;
    }
  }

  GlobalKey _anchor(String id) => _anchors.putIfAbsent(id, GlobalKey.new);

  // Where the toolbar's button [id] is in the view, from the last layout.
  Rect? _rectOf(String id) {
    final box = _anchors[id]?.currentContext?.findRenderObject();
    final root = _root.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        root is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !root.attached) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: root) & box.size;
  }

  void _togglePopup(String id) => setState(() {
    _popup = _popup == id ? null : id;
    _hint = null;
  });

  // An option of the Options menu changed: collect again, the menu shows
  // its new values.
  void _optionChanged() {
    _change();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final scene = _sceneFor(style);
    _updateMarks();
    final selected = _selected == null ? null : scene.graph.indexOf(_selected!);
    final lanes = _lanesOf(scene.graph);
    if (_popup == _groups && lanes.length < 2 && _settings.groups.isEmpty) {
      _popup = null;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.biggest;
        final popup = _popup;
        final hint = _hint;
        return Stack(
          key: _root,
          children: [
            Positioned.fill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _toolbar(style, lanes),
                  SizedBox(height: widget.compact ? 2 : 4),
                  Expanded(child: _viewportOf(style, scene, selected)),
                ],
              ),
            ),
            if (popup != null) ...[
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('debug graph popup barrier'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _popup = null),
                ),
              ),
              _popupOf(popup, style, lanes, room),
            ],
            if (hint != null && popup == null)
              _hintOf(hint.$1, hint.$2, style, room),
          ],
        );
      },
    );
  }

  Widget _popupOf(
    String popup,
    DebugStyle style,
    List<DebugGraphLane> lanes,
    Size room,
  ) {
    final anchor = _rectOf(popup) ?? const Rect.fromLTWH(0, 0, 0, 24);
    final width = math.max(
      0.0,
      math.min(room.width - 8, widget.compact ? 240.0 : 300.0),
    );
    final top = anchor.bottom + 2;
    final maxHeight = math.max(60.0, room.height - top - 4);
    final left = anchor.left
        .clamp(0.0, math.max(0.0, room.width - width))
        .toDouble();
    final s = _settings;
    final layers = {for (final layer in widget.layers) layer.id: layer};
    final menus = <String, Widget Function()>{
      _options: () => DebugGraphOptionsMenu(
        [
          DebugGraphOptionSection(
            'Graph',
            options: [
              DebugGraphOption(
                label: 'Live only',
                value: s.liveOnly,
                onChanged: (value) => apply(s.copyWith(liveOnly: value)),
              ),
            ],
            actions: [
              if (_memory.cards.isNotEmpty)
                DebugGraphMenuAction(
                  'Close all cards (${_memory.cards.length})',
                  _closeCards,
                ),
            ],
          ),
          for (final layer in _shown)
            DebugGraphOptionSection(
              layer.title,
              options: layer.options,
              choices: layer.choices,
            ),
        ],
        compact: widget.compact,
        onChanged: _optionChanged,
      ),
      _groups: () => DebugGraphGroupsList(
        lanes: lanes,
        chosen: s.groups,
        maxHeight: maxHeight - 12,
        memory: _memory,
        compact: widget.compact,
        colorOf: (lane) => layers[lane.layer]?.colorOf(style) ?? style.accent,
        onChanged: (groups) => apply(_settings.copyWith(groups: groups)),
      ),
    };
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          key: ValueKey('debug graph $popup'),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: style.background.withValues(alpha: 0.98),
            border: Border.all(color: style.line),
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 8),
            ],
          ),
          child: menus[popup]?.call() ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _hintOf(String id, String text, DebugStyle style, Size room) {
    final anchor = _rectOf(id);
    if (anchor == null) {
      return const SizedBox.shrink();
    }
    const width = 260.0;
    return Positioned(
      left: anchor.left.clamp(0.0, math.max(0.0, room.width - width)),
      top: anchor.bottom + 3,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: width),
          child: Container(
            key: const ValueKey('debug graph hint'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: style.background.withValues(alpha: 0.96),
              border: Border.all(color: style.line),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              text,
              style: style.code.copyWith(fontSize: 10, color: style.foreground),
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewportOf(DebugStyle style, DebugGraphScene scene, int? selected) =>
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: style.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final resized = size != _viewport;
              _viewport = size;
              // Fitted only the first time the view opens with something to
              // show and no place kept, and on Fit; never in the middle of
              // a gesture. Else shown where it was placed, kept in sight.
              // Auto: fitted again whenever the graph or its room changes.
              if (_memory.autoFit &&
                  !_fitPending &&
                  (resized || _sighted?.size != scene.size)) {
                _fitPending = true;
              }
              if (_fitPending && !_gesture) {
                if (_fitTo(size, scene)) {
                  _fitPending = false;
                }
              } else if (!_gesture &&
                  (resized || !identical(scene, _sighted))) {
                _keepInSight(size, scene);
              }
              _sighted = scene;
              final painter = _painter = DebugGraphPainter(
                scene,
                transform: _transform,
                repaint: Listenable.merge([_transform, _frames]),
                selected: selected,
                animating: _animating,
                heat: _heat,
                marked: _marked,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      onPointerSignal: _signal,
                      child: MouseRegion(
                        onHover: (event) => _hoverAt(event.localPosition),
                        onExit: (_) => setState(() => _hover = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) => _tapAt(details.localPosition),
                          onScaleStart: _scaleStart,
                          onScaleUpdate: _scaleUpdate,
                          onScaleEnd: _scaleEnd,
                          child: RepaintBoundary(
                            child: CustomPaint(
                              key: const ValueKey('debug graph'),
                              painter: painter,
                              size: size,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (scene.graph.items.isEmpty)
                    Center(
                      child: Text(
                        _settings.scope == DebugGraphScope.onScreen
                            ? 'Nothing on the screen reads anything yet: '
                                  'try All.'
                            : 'Nothing yet: the graph fills while the app '
                                  'runs.',
                        style: style.text.copyWith(color: style.muted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Positioned.fill(child: _cards(scene)),
                  if (_memory.legendOpen)
                    Positioned(
                      top: 4,
                      right: 4,
                      width: math.max(
                        0,
                        math.min(
                          size.width - 8,
                          widget.compact ? 280.0 : 360.0,
                        ),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.max(0, size.height - 8),
                        ),
                        child: DebugGraphLegend(
                          _shown,
                          graph: scene.graph,
                          memory: _memory,
                          liveWindow: _settings.liveWindow,
                          compact: widget.compact,
                          onClose: () =>
                              setState(() => _memory.legendOpen = false),
                        ),
                      ),
                    ),
                  if (_hover case (final key, final at))
                    if (scene.graph.indexOf(key) case final index?)
                      _tooltip(style, scene.graph, index, at, size),
                ],
              );
            },
          ),
        ),
      );

  // The cards open, each beside its plate, following it as the graph pans
  // and zooms; the last opened on top.
  Widget _cards(DebugGraphScene scene) => ValueListenableBuilder<Matrix4>(
    valueListenable: _transform,
    builder: (context, transform, _) => Stack(
      children: [
        for (final key in _memory.cards)
          if (scene.graph.indexOf(key) case final index?)
            // A card waits while its plate is out of the room.
            if (_inRoom(
              MatrixUtils.transformRect(transform, scene.rects[index]),
            ))
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: DebugGraphCardPlacement(
                    MatrixUtils.transformRect(transform, scene.rects[index]),
                    maxWidth: widget.compact ? 260 : 320,
                  ),
                  child: DebugGraphDetails(
                    scene.graph,
                    index,
                    key: ValueKey('debug graph card $key'),
                    settings: _settings,
                    onSettings: apply,
                    compact: widget.compact,
                    expanded: _memory.expanded.contains(key),
                    selected: _selected == key,
                    onExpand: () => setState(() {
                      if (!_memory.expanded.remove(key)) {
                        _memory.expanded.add(key);
                      }
                    }),
                    onClose: () => _closeCard(key),
                    onLink: (link) => _selectNode(scene, link.target),
                  ),
                ),
              ),
      ],
    ),
  );

  bool _inRoom(Rect plate) =>
      _viewport == null || plate.overlaps(Offset.zero & _viewport!);

  Widget _tooltip(
    DebugStyle style,
    DebugGraph graph,
    int index,
    Offset at,
    Size room,
  ) {
    const width = 260.0;
    final item = graph.items[index];
    final lines = DebugGraphDetails.linesOf(graph, index).take(4).toList();
    String? hot;
    if (_heat[index] != null) {
      final layers = {for (final layer in graph.layers) layer.id: layer};
      for (final node in [...item.nodes, ...item.aliases]) {
        hot = layers[node.layer]?.hotNoteOf(node);
        if (hot != null) {
          break;
        }
      }
    }
    final height = 14.0 * (lines.length + (hot == null ? 1 : 2)) + 14;
    return Positioned(
      left: math.max(0, math.min(at.dx + 14, room.width - width)),
      top: math.max(0, math.min(at.dy + 14, room.height - height)),
      width: width,
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('debug graph tooltip'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: style.background.withValues(alpha: 0.95),
            border: Border.all(
              color: hot == null ? style.line : style.graphHot,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                style: style.code.copyWith(fontWeight: FontWeight.w600),
              ),
              if (hot != null)
                Text(
                  hot,
                  key: const ValueKey('debug graph tooltip hot'),
                  style: style.code.copyWith(
                    fontSize: 10,
                    color: style.graphHot,
                  ),
                ),
              for (final line in lines)
                Text(
                  '${line.label}  ${line.value}',
                  style: style.code.copyWith(
                    fontSize: 10,
                    color: style.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // The lanes of the group filter: the groups of the layers whose groups
  // are lanes.
  List<DebugGraphLane> _lanesOf(DebugGraph graph) {
    final lanes = {
      for (final layer in graph.layers)
        if (layer.lanes) layer.id,
    };
    return [
      for (final lane in graph.all)
        if (lane.group != null && lanes.contains(lane.layer)) lane,
    ];
  }

  // One row: the layers' switches, the scope, Fit, Options, Groups,
  // Legend; it wraps rather than scrolls.
  Widget _toolbar(DebugStyle style, List<DebugGraphLane> lanes) {
    final s = _settings;
    final compact = widget.compact;
    final legend = _memory.legend;
    Widget button(
      String id,
      String label, {
      required String hint,
      required VoidCallback onTap,
      bool selected = false,
      Color? color,
      String? trailing,
    }) => MouseRegion(
      onEnter: (_) => setState(() => _hint = (id, hint)),
      onExit: (_) {
        if (_hint?.$1 == id) {
          setState(() => _hint = null);
        }
      },
      child: DebugGraphToolButton(
        label,
        key: _anchor(id),
        onTap: onTap,
        selected: selected,
        color: color,
        trailing: trailing,
        compact: compact,
      ),
    );

    return Wrap(
      spacing: compact ? 4 : 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.layers.length > 1)
          for (final layer in widget.layers)
            button(
              'layer ${layer.id}',
              layer.title,
              color: layer.colorOf(style),
              selected: !s.hiddenLayers.contains(layer.id),
              hint: '${layer.title}: show or hide its nodes',
              onTap: () => apply(
                s.copyWith(
                  hiddenLayers: DebugGraphSettings.toggled(
                    s.hiddenLayers,
                    layer.id,
                  ),
                ),
              ),
            ),
        button(
          'scope screen',
          compact ? 'Screen' : 'On screen',
          selected: s.scope == DebugGraphScope.onScreen,
          hint:
              'On screen: the widgets in the window, what they read and '
              'what listens to it',
          onTap: () => apply(s.copyWith(scope: DebugGraphScope.onScreen)),
        ),
        button(
          'scope all',
          'All',
          selected: s.scope == DebugGraphScope.all,
          hint: 'All: every node the layers know',
          onTap: () => apply(s.copyWith(scope: DebugGraphScope.all)),
        ),
        button(
          'fit',
          'Fit',
          hint: 'Fit: the whole graph in its room, once',
          onTap: fit,
        ),
        button(
          'auto',
          'Auto',
          hint:
              'Auto: fit the graph whenever it or its room changes; '
              'a pan or a zoom turns it off',
          selected: _memory.autoFit,
          onTap: _toggleAuto,
        ),
        button(
          _options,
          compact ? 'Opts' : 'Options',
          trailing: '▾',
          selected: _popup == _options,
          hint: 'Options: Live only, each layer\'s own switches and choices',
          onTap: () => _togglePopup(_options),
        ),
        // Kept while groups are chosen, so a choice can always be undone.
        if (lanes.length > 1 || s.groups.isNotEmpty)
          button(
            _groups,
            '${compact ? 'Grp' : 'Groups'}: '
            '${s.groups.isEmpty ? 'all' : s.groups.length}',
            trailing: '▾',
            selected: _popup == _groups || s.groups.isNotEmpty,
            hint:
                'Groups: show some lanes only, with what touches them '
                '(${lanes.length} groups)',
            onTap: () => _togglePopup(_groups),
          ),
        button(
          'legend',
          'Legend',
          trailing: legend.isEmpty ? null : '${legend.length}',
          selected: _memory.legendOpen,
          hint:
              'Legend: what the colours, shapes and marks mean; tap an '
              'entry to highlight its nodes',
          onTap: () => setState(() {
            _memory.legendOpen = !_memory.legendOpen;
            _hint = null;
          }),
        ),
      ],
    );
  }
}

/// How the application graph's first fit and its Fit button place the
/// graph in its room: its scale and offset for the graph's [Size] in the
/// room's. The scale is never over 1 (a small graph keeps its size) nor
/// under [DebugGraphView.minScale].
abstract class DebugGraphFit {
  /// A fit.
  const DebugGraphFit();

  /// The whole graph in the room, centred across, at the top: the panel's
  /// Graph tab.
  static const DebugGraphFit whole = WholeDebugGraphFit();

  /// The graph as wide as the room, centred across, at the top, whatever
  /// the room's height (what is below is panned to): a console pane.
  static const DebugGraphFit width = WidthDebugGraphFit();

  /// The scale for a graph of [graph] in a room of [room].
  double scaleOf(Size graph, Size room);

  /// The transform that places a graph of [graph] in a room of [room]:
  /// scaled by [scaleOf], centred across, at the top.
  Matrix4 place(Size graph, Size room) {
    final scale = scaleOf(
      graph,
      room,
    ).clamp(DebugGraphView.minScale, 1.0).toDouble();
    final dx = (room.width - graph.width * scale) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, 0, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }
}

/// [DebugGraphFit.whole]: the whole graph in the room.
final class WholeDebugGraphFit extends DebugGraphFit {
  /// The fit.
  const WholeDebugGraphFit();

  @override
  double scaleOf(Size graph, Size room) =>
      math.min(room.width / graph.width, room.height / graph.height);
}

/// [DebugGraphFit.width]: the graph as wide as the room.
final class WidthDebugGraphFit extends DebugGraphFit {
  /// The fit.
  const WidthDebugGraphFit();

  @override
  double scaleOf(Size graph, Size room) => room.width / graph.width;
}
