// The application graph's engine with a fake layer: the layouts (columns,
// lanes, the tree), the assembly (merge, scope, group, live only, folds),
// the view (fit and centre on open and on resize, the wheel pans and
// zooms and nothing around it scrolls, the legend, colours per layer and
// shapes per kind, arrows, the chain of a tap, lanes, folding repeats,
// tooltip), the soft flash, the SPI's start and stop, the build switches.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// A layer of nodes and edges set by the test.
final class FakeLayer extends DebugGraphLayer {
  FakeLayer(
    this.id, {
    this.nodes = const [],
    this.edges = const [],
    this.color = const Color(0xFF00FF00),
    this.title = 'Fake',
    this.layout,
  });

  @override
  final String id;

  @override
  final String title;

  final Color color;

  List<DebugGraphNode> nodes;
  List<DebugGraphEdge> edges;

  @override
  final DebugGraphLayout? layout;

  final ChangeNotifier _changes = ChangeNotifier();
  int started = 0;
  int stopped = 0;
  final Map<String, double> glows = {};
  final Set<String> live = {};
  final List<VoidCallback> wakers = [];
  final List<DebugGraphScope> scopes = [];

  @override
  Color colorOf(DebugStyle style) => color;

  @override
  List<DebugGraphKind> get kinds => const [
    DebugGraphKind('a', 'kind a', DebugGraphShape.rounded),
    DebugGraphKind('b', 'kind b', DebugGraphShape.hexagon),
  ];

  @override
  Listenable get changes => _changes;

  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  void changed() => _changes.notifyListeners();

  @override
  void Function() start() {
    started++;
    return () => stopped++;
  }

  @override
  DebugGraphPart collect(DebugGraphScope scope) {
    scopes.add(scope);
    return DebugGraphPart(nodes, edges);
  }

  @override
  double glowOf(DebugGraphNode node) => glows[node.id] ?? 0;

  @override
  bool isLive(DebugGraphNode node, Duration window) => live.contains(node.id);

  @override
  void Function() onActivity(VoidCallback wake) {
    wakers.add(wake);
    return () => wakers.remove(wake);
  }

  @override
  List<DebugGraphDetail> detailsOf(DebugGraphNode node) => [
    DebugGraphDetail('value', 'of ${node.label}'),
  ];
}

/// A layer whose card has two rows that open, in [rows], [whole] the
/// opened text of `b`.
final class _OpeningLayer extends FakeLayer {
  _OpeningLayer(super.id, {super.nodes});

  List<String> rows = ['a', 'b'];
  String whole = 'b whole one';

  @override
  List<DebugGraphDetail> detailsOf(DebugGraphNode node) => [
    for (final label in rows)
      DebugGraphDetail(
        label,
        '$label short',
        more: () => label == 'b' ? whole : '$label whole',
      ),
  ];
}

/// A layer that keeps what it is told is selected.
final class _SelectingLayer extends FakeLayer {
  _SelectingLayer(super.id, {super.nodes});

  final List<String?> selections = [];

  @override
  void select(DebugGraphNode? node) => selections.add(node?.id);
}

/// A layer whose card lists the node's targets as links (`W0`, `W1`, …).
final class _LinkedLayer extends FakeLayer {
  _LinkedLayer(super.id, {super.nodes, super.edges});

  @override
  List<DebugGraphDetail> detailsOf(DebugGraphNode node) => [
    DebugGraphDetail(
      'used by',
      '',
      links: [
        for (final edge in edges.where((e) => e.from == node.id))
          DebugGraphDetailLink(edge.to.toUpperCase(), target: edge.to),
      ],
    ),
  ];
}

DebugGraphNode node(
  String id, {
  String layer = 'f',
  String kind = 'a',
  String? group,
  String? repeat,
  BuildContext? widget,
  bool sink = false,
}) => DebugGraphNode(
  id: id,
  layer: layer,
  kind: kind,
  label: id,
  group: group,
  repeatKey: repeat,
  widget: widget,
  sink: sink,
);

DebugGraphLayoutInput input(
  int count,
  List<(int, int)> edges, {
  List<int>? lanes,
  List<bool>? sinks,
}) => DebugGraphLayoutInput(
  widths: List.filled(count, 80),
  heights: List.filled(count, 20),
  edges: edges,
  lanes: lanes ?? List.filled(count, 0),
  laneCount: lanes == null ? 1 : lanes.reduce((a, b) => a > b ? a : b) + 1,
  sinks: sinks ?? List.filled(count, false),
  laneHeader: 12,
);

Widget host(Widget child, {double width = 600, double height = 400}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, height: height, child: child),
      ),
    );

DebugGraphViewState stateOf(WidgetTester tester) =>
    tester.state<DebugGraphViewState>(find.byType(DebugGraphView));

final Finder graphPaint = find.byKey(const ValueKey('debug graph'));

void main() {
  group('layouts', () {
    test('columns by the longest path, sinks in the last; a long edge '
        'through points; no crossings in simple cases', () {
      const layout = LayeredDebugGraphLayout();
      final placed = layout.place(
        input(
          6,
          [(0, 2), (2, 3), (1, 4), (3, 5)],
          sinks: [false, false, false, false, true, true],
        ),
      );
      final x = placed.positions.map((p) => p.dx).toList();
      expect(x[0], x[1]);
      expect(x[2], greaterThan(x[0]));
      expect(x[3], greaterThan(x[2]));
      expect(x[4], x[5], reason: 'the sinks share the last column');
      expect(placed.routes[2], hasLength(4), reason: 'two points between');
      expect(placed.flow, Axis.horizontal);
      expect(layout.place(input(4, [(0, 3), (1, 2)])).crossings, 0);
      expect(
        layout.place(input(4, [(0, 1), (0, 2), (1, 3), (2, 3)])).crossings,
        0,
      );
    });

    test('each lane a band across every column, the bands one under the '
        'other, a plate inside its lane', () {
      final placed = const LayeredDebugGraphLayout().place(
        input(6, [(0, 3), (1, 4), (2, 5)], lanes: [0, 1, 0, 2, 2, 1]),
      );
      expect(placed.lanes, hasLength(3));
      for (var l = 1; l < 3; l++) {
        expect(
          placed.lanes[l].top,
          greaterThanOrEqualTo(placed.lanes[l - 1].bottom),
        );
        expect(placed.lanes[l].width, placed.size.width);
      }
      const lanes = [0, 1, 0, 2, 2, 1];
      for (var i = 0; i < 6; i++) {
        final band = placed.lanes[lanes[i]];
        expect(placed.positions[i].dy, greaterThanOrEqualTo(band.top));
        expect(placed.positions[i].dy + 20, lessThanOrEqualTo(band.bottom));
      }
    });

    test('a cycle is laid out; the same input, the same placement', () {
      final cycle = const LayeredDebugGraphLayout().place(
        input(3, [(0, 1), (1, 2), (2, 0)]),
      );
      expect(cycle.positions.map((p) => p.dx).toSet(), hasLength(3));
      final a = const LayeredDebugGraphLayout().place(_synthetic(7));
      final b = const LayeredDebugGraphLayout().place(_synthetic(7));
      expect(a.positions, b.positions);
      expect(a.routes, b.routes);
    });

    test('the tree: parents above their children, centred over them, no '
        'two plates of a row overlap', () {
      final placed = const TreeDebugGraphLayout().place(
        input(5, [(0, 1), (0, 2), (1, 3), (1, 4)]),
      );
      final p = placed.positions;
      expect(placed.flow, Axis.vertical);
      expect(p[1].dy, greaterThan(p[0].dy));
      expect(p[3].dy, greaterThan(p[1].dy));
      expect(p[3].dy, p[4].dy);
      expect(p[4].dx, greaterThanOrEqualTo(p[3].dx + 80));
      expect(
        p[1].dx + 40,
        closeTo((p[3].dx + p[4].dx) / 2 + 40, 0.01),
        reason: 'centred over its children',
      );
      expect(placed.lanes, isEmpty);
    });

    test('the tree of its own layer: another layer\'s plates above it, '
        'their edges never take a plate from its parent', () {
      final placed = const TreeDebugGraphLayout().place(
        DebugGraphLayoutInput(
          widths: List.filled(4, 80),
          heights: List.filled(4, 20),
          edges: const [(3, 2), (0, 1), (0, 2)],
          lanes: List.filled(4, 0),
          laneCount: 1,
          sinks: List.filled(4, false),
          primary: const [true, true, true, false],
        ),
      );
      final p = placed.positions;
      expect(p[3].dy, lessThan(p[0].dy), reason: 'the other layer above');
      expect(p[1].dy, p[2].dy, reason: 'both children of 0');
      expect(p[2].dy, greaterThan(p[0].dy));
    });

    test('300 signal nodes and a tree of 2000 are laid out fast', () {
      final signals = _synthetic(42);
      final tree = _tree(2000);
      int median(DebugGraphLayout layout, DebugGraphLayoutInput input) {
        for (var i = 0; i < 2; i++) {
          layout.place(input);
        }
        final times = <int>[];
        for (var i = 0; i < 5; i++) {
          final watch = Stopwatch()..start();
          layout.place(input);
          times.add(watch.elapsedMicroseconds);
        }
        return (times..sort())[times.length ~/ 2];
      }

      final layered = median(const LayeredDebugGraphLayout(), signals);
      final treed = median(const TreeDebugGraphLayout(), tree);
      // ignore: avoid_print
      print(
        'layout: 300 signal nodes ${(layered / 1000).toStringAsFixed(1)} '
        'ms, a tree of 2000 ${(treed / 1000).toStringAsFixed(1)} ms',
      );
      // Wide budgets: they catch a slower algorithm, not a busy machine.
      expect(layered, lessThan(500000));
      expect(treed, lessThan(500000));
    });
  });

  group('assembly', () {
    DebugGraph assemble(
      List<FakeLayer> layers, [
      DebugGraphSettings settings = const DebugGraphSettings(
        scope: DebugGraphScope.all,
      ),
      bool Function(BuildContext)? shows,
    ]) =>
        DebugGraphAssembler(
          filters: [
            DebugGraphScopeFilter(shows: shows ?? (_) => true),
            const DebugGraphGroupFilter(),
            const DebugGraphLiveFilter(),
          ],
        ).assemble([
          for (final l in layers) (l, l.collect(settings.scope)),
        ], settings);

    test('the layers merged: an edge of one layer to another\'s node is '
        'kept, one to a node not shown is not', () {
      final a = FakeLayer('a', nodes: [node('a:1', layer: 'a')]);
      final b = FakeLayer(
        'b',
        nodes: [node('b:1', layer: 'b')],
        edges: const [
          DebugGraphEdge('a:1', 'b:1'),
          DebugGraphEdge('c:1', 'b:1'),
        ],
      );
      final graph = assemble([a, b]);
      expect(graph.items.map((i) => i.key), ['a:1', 'b:1']);
      expect(graph.links, hasLength(1));
      expect(graph.layers, [a, b]);
    });

    test('repeats fold into one plate, ×N, and open by their fold', () {
      final layer = FakeLayer(
        'f',
        nodes: [
          node('src'),
          for (var i = 0; i < 10; i++)
            node('tile$i', group: 'widgets', repeat: 'PlayerReviews'),
          node('header', group: 'widgets', repeat: 'Header'),
        ],
        edges: [
          for (var i = 0; i < 10; i++) DebugGraphEdge('src', 'tile$i'),
        ],
      );
      final folded = assemble([layer]);
      final plate = folded.items.singleWhere((i) => i.folded);
      expect(plate.label, 'PlayerReviews ×10');
      expect(plate.nodes, hasLength(10));
      expect(folded.items, hasLength(3), reason: 'src, the fold, header');
      expect(folded.links, hasLength(1), reason: 'ten edges, one link');
      final opened = assemble(
        [
          layer,
        ],
        plate.fold!.open(const DebugGraphSettings(scope: DebugGraphScope.all)),
      );
      expect(opened.items, hasLength(12));
      expect(opened.items.where((i) => i.folded), isEmpty);
      expect(
        opened.items.firstWhere((i) => i.key == 'tile3').fold?.closeLabel,
        'fold PlayerReviews ×10',
      );
    });

    test('a collapsed lane is one plate; the group filter keeps a lane and '
        'what touches it', () {
      final layer = FakeLayer(
        'f',
        nodes: [
          node('x1', group: 'X'),
          node('x2', group: 'X'),
          node('y1', group: 'Y'),
          node('z1', group: 'Z'),
        ],
        edges: const [DebugGraphEdge('x1', 'y1'), DebugGraphEdge('x2', 'x1')],
      );
      final lane = DebugGraphLane.keyOf(layer.nodes.first);
      final collapsed = assemble([
        layer,
      ], DebugGraphSettings(scope: DebugGraphScope.all, collapsed: {lane}));
      expect(collapsed.items.first.label, 'X (2)');
      expect(collapsed.items.first.folded, isTrue);
      expect(collapsed.links, hasLength(1), reason: 'x2 → x1 is inside');
      final only = assemble([
        layer,
      ], DebugGraphSettings(scope: DebugGraphScope.all, groups: {lane}));
      expect(only.items.map((i) => i.key), ['x1', 'x2', 'y1']);
      final gone = assemble(
        [
          layer,
        ],
        const DebugGraphSettings(scope: DebugGraphScope.all, groups: {'gone'}),
      );
      expect(
        gone.items.map((i) => i.key),
        containsAll(['x1', 'x2', 'y1', 'z1']),
        reason: 'a chosen lane that is gone filters nothing',
      );
      final both = assemble(
        [
          layer,
        ],
        DebugGraphSettings(scope: DebugGraphScope.all, groups: {lane, 'gone'}),
      );
      expect(both.items.map((i) => i.key), ['x1', 'x2', 'y1']);
    });

    test('"live only" hides the quiet nodes', () {
      final layer = FakeLayer('f', nodes: [node('a'), node('b')])
        ..live.add('a');
      final graph = assemble([
        layer,
      ], const DebugGraphSettings(scope: DebugGraphScope.all, liveOnly: true));
      expect(graph.items.map((i) => i.key), ['a']);
    });
  });

  group('the view', () {
    late FakeLayer layer;

    setUp(() {
      layer = FakeLayer(
        'f',
        nodes: [
          node('field', group: 'Basket'),
          node('total', group: 'Basket', kind: 'b'),
          node('badge', group: 'widgets', sink: true),
          node('lonely', group: 'Other'),
        ],
        edges: const [
          DebugGraphEdge('field', 'total'),
          DebugGraphEdge('total', 'badge'),
        ],
      );
    });

    const all = DebugGraphSettings(scope: DebugGraphScope.all);

    testWidgets('fits, centred across and at the top, on open and on Fit; a '
        'resize after a pan '
        'keeps the graph where it was', (tester) async {
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final room = tester.getSize(graphPaint);
      Rect shown() {
        final size = state.scene!.size;
        return MatrixUtils.transformRect(
          state.transform,
          Offset.zero & size,
        );
      }

      void expectFitted(Size room) {
        final rect = shown();
        expect(rect.left, greaterThanOrEqualTo(-0.5));
        expect(rect.top, greaterThanOrEqualTo(-0.5));
        expect(rect.right, lessThanOrEqualTo(room.width + 0.5));
        expect(rect.bottom, lessThanOrEqualTo(room.height + 0.5));
        expect(rect.center.dx, closeTo(room.width / 2, 0.5));
        expect(rect.top, closeTo(0, 0.5), reason: 'at the top');
      }

      expectFitted(room);
      // A drag moves it (past the touch slop); it stays where it was
      // dragged.
      await tester.drag(graphPaint, const Offset(80, 30));
      await tester.pump();
      expect(shown().center.dx, greaterThan(room.width / 2 + 50));
      // A resize keeps it where it was, in sight.
      final dragged = shown().center;
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all), width: 420),
      );
      expect(shown().center, dragged);
      // Fit fits it again.
      await tester.drag(graphPaint, const Offset(40, 0));
      await tester.tap(find.text('Fit'));
      await tester.pump();
      expectFitted(tester.getSize(graphPaint));
      // The double tap's wait for a second tap runs out.
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('a wheel over the graph pans it, ⌘ or Ctrl with it zooms; '
        'nothing around it scrolls', (tester) async {
      final outer = ScrollController();
      addTearDown(outer.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(
            controller: outer,
            children: [
              SizedBox(
                height: 400,
                child: DebugGraphView(layers: [layer], settings: all),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      final state = stateOf(tester);
      final before = state.transform.clone();
      final at = tester.getCenter(graphPaint);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
      await tester.pump();
      expect(outer.offset, 0, reason: 'the list did not scroll');
      expect(
        state.transform.getTranslation().y,
        closeTo(before.getTranslation().y - 60, 0.01),
      );
      expect(state.transform.getMaxScaleOnAxis(), before.getMaxScaleOnAxis());
      final scale = state.transform.getMaxScaleOnAxis();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(state.transform.getMaxScaleOnAxis(), greaterThan(scale));
      expect(outer.offset, 0);
    });

    testWidgets('the legend: each layer in its colour, each kind in its '
        'shape; plates in their layer\'s colour and kind\'s shape', (
      tester,
    ) async {
      final other = FakeLayer(
        'o',
        title: 'Other layer',
        color: const Color(0xFFFF00FF),
        nodes: [node('o:1', layer: 'o', kind: 'b')],
        edges: const [DebugGraphEdge('total', 'o:1')],
      );
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer, other], settings: all)),
      );
      await tester.tap(find.text('Legend'));
      await tester.pump();
      expect(find.text('Fake'), findsWidgets, reason: 'switch and legend');
      expect(find.text('Other layer'), findsWidgets);
      expect(find.byKey(const ValueKey('legend f a')), findsOneWidget);
      expect(find.byKey(const ValueKey('legend o b')), findsOneWidget);
      final icons = tester.widgetList<DebugGraphShapeIcon>(
        find.byType(DebugGraphShapeIcon),
      );
      expect(
        icons.map((i) => (i.shape, i.color)),
        containsAll([
          (DebugGraphShape.rounded, const Color(0xFF00FF00)),
          (DebugGraphShape.hexagon, const Color(0xFF00FF00)),
          (DebugGraphShape.hexagon, const Color(0xFFFF00FF)),
        ]),
      );
      final scene = stateOf(tester).scene!;
      final graph = scene.graph;
      int at(String key) => graph.indexOf(key)!;
      expect(scene.colorOf(at('field')), const Color(0xFF00FF00));
      expect(scene.colorOf(at('o:1')), const Color(0xFFFF00FF));
      expect(scene.shapeOf(at('field')), DebugGraphShape.rounded);
      expect(scene.shapeOf(at('total')), DebugGraphShape.hexagon);
      expect(
        graph.links.any((l) => l.from == at('total') && l.to == at('o:1')),
        isTrue,
        reason: 'the edge across layers',
      );

      // A layer switched off: its nodes and its legend go.
      await tester.tap(find.text('Other layer').first);
      await tester.pump();
      expect(stateOf(tester).graph!.indexOf('o:1'), isNull);
      expect(find.byKey(const ValueKey('legend o b')), findsNothing);
      expect(other.stopped, 1, reason: 'it stops collecting');
    });

    testWidgets('an arrow on each link; a tap highlights the chain before '
        'and after the plate and tells it', (tester) async {
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final scene = state.scene!;
      expect(scene.arrows, hasLength(scene.graph.links.length));
      for (var e = 0; e < scene.arrows.length; e++) {
        final target = scene.rects[scene.graph.links[e].to];
        final bounds = scene.arrows[e].getBounds();
        expect(
          (bounds.right - target.left).abs() < 1 ||
              (bounds.left - target.right).abs() < 1,
          isTrue,
          reason: 'the arrow ends at its target',
        );
      }
      final total = scene.graph.indexOf('total')!;
      expect(
        scene.graph.chainOf(total),
        {scene.graph.indexOf('field'), total, scene.graph.indexOf('badge')},
      );
      final centre = MatrixUtils.transformPoint(
        state.transform,
        scene.rects[total].center,
      );
      await _doubleTapAt(tester, tester.getTopLeft(graphPaint) + centre);
      expect(find.text('Basket · total'), findsOneWidget);
      expect(find.text('of total'), findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(graphPaint).painter! as DebugGraphPainter;
      expect(painter.selected, total);
      // The double tap's wait for a second tap runs out.
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('lanes: one band per group across the columns, its title at '
        'the left; a tap on the title collapses it, again opens it', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final scene = state.scene!;
      expect(scene.lanes.map((b) => b.lane.title), [
        'Basket',
        'widgets',
        'Other',
      ]);
      for (final band in scene.lanes) {
        expect(band.titleRect.left, lessThan(band.rect.left + 10));
        for (var i = 0; i < scene.graph.items.length; i++) {
          if (scene.graph.lanes[scene.graph.items[i].lane].key ==
              band.lane.key) {
            expect(band.rect.contains(scene.rects[i].center), isTrue);
          }
        }
      }
      final title = MatrixUtils.transformPoint(
        state.transform,
        scene.lanes.first.titleRect.center,
      );
      await tester.tapAt(tester.getTopLeft(graphPaint) + title);
      await tester.pump(kDoubleTapTimeout);
      expect(state.graph!.items.first.label, 'Basket (2)');
      final again = MatrixUtils.transformPoint(
        state.transform,
        state.scene!.lanes.first.titleRect.center,
      );
      await tester.tapAt(tester.getTopLeft(graphPaint) + again);
      await tester.pump(kDoubleTapTimeout);
      expect(state.graph!.items.first.label, 'field');
    });

    testWidgets('repeats folded until tapped open, folded back by the '
        'detail\'s chip', (tester) async {
      layer.nodes = [
        node('src'),
        for (var i = 0; i < 10; i++)
          node('tile$i', group: 'widgets', repeat: 'PlayerReviews', sink: true),
      ];
      layer.edges = [
        for (var i = 0; i < 10; i++) DebugGraphEdge('src', 'tile$i'),
      ];
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final fold = state.graph!.indexOf(
        state.graph!.items.firstWhere((i) => i.folded).key,
      )!;
      expect(state.graph!.items[fold].label, 'PlayerReviews ×10');
      final at = MatrixUtils.transformPoint(
        state.transform,
        state.scene!.rects[fold].center,
      );
      await tester.tapAt(tester.getTopLeft(graphPaint) + at);
      await tester.pump(kDoubleTapTimeout);
      expect(state.graph!.items, hasLength(11));
      // Opened, the column runs below the room: Fit shows it whole.
      await tester.tap(find.text('Fit'));
      await tester.pump();
      final tile = state.graph!.indexOf('tile4')!;
      final tileAt = MatrixUtils.transformPoint(
        state.transform,
        state.scene!.rects[tile].center,
      );
      await _doubleTapAt(tester, tester.getTopLeft(graphPaint) + tileAt);
      // The card opens with its rows and chips.
      await tester.tap(find.text('fold PlayerReviews ×10'));
      await tester.pump();
      expect(state.graph!.items, hasLength(2));
      // The double tap's wait for a second tap runs out.
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('hiding a layer stops it alone and clears what it was '
        'told is selected; showing it starts it alone', (tester) async {
      final other = _SelectingLayer('g', nodes: [node('g1', layer: 'g')]);
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer, other], settings: all)),
      );
      final state = stateOf(tester);
      final g1 = state.scene!.graph.indexOf('g1')!;
      await _doubleTapAt(
        tester,
        tester.getTopLeft(graphPaint) +
            MatrixUtils.transformPoint(
              state.transform,
              state.scene!.rects[g1].center,
            ),
      );
      await tester.pump(kDoubleTapTimeout);
      expect(other.selections.last, 'g1');
      state.apply(all.copyWith(hiddenLayers: {'g'}));
      await tester.pump();
      expect((layer.started, layer.stopped), (1, 0));
      expect((other.started, other.stopped), (1, 1));
      expect(other.selections.last, isNull);
      state.apply(all);
      await tester.pump();
      expect((layer.started, layer.stopped), (1, 0));
      expect((other.started, other.stopped), (2, 1));
    });

    testWidgets('a collect of the same structure replaces the nodes, '
        'without a new layout', (tester) async {
      layer.nodes = [
        for (final n in layer.nodes)
          DebugGraphNode(
            id: n.id,
            layer: n.layer,
            kind: n.kind,
            label: n.label,
            group: n.group,
            sink: n.sink,
            source: 1,
          ),
      ];
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final layouts = state.layouts;
      layer.nodes = [
        for (final n in layer.nodes)
          DebugGraphNode(
            id: n.id,
            layer: n.layer,
            kind: n.kind,
            label: n.label,
            group: n.group,
            sink: n.sink,
            source: 2,
          ),
      ];
      layer.changed();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(state.layouts, layouts);
      final total = state.graph!.indexOf('total')!;
      expect(state.graph!.items[total].nodes.single.source, 2);
      expect(state.scene!.graph.items[total].nodes.single.source, 2);
    });

    testWidgets('a tooltip follows its plate, not its place in a new scene', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final total = state.graph!.indexOf('total')!;
      final at =
          tester.getTopLeft(graphPaint) +
          MatrixUtils.transformPoint(
            state.transform,
            state.scene!.rects[total].center,
          );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await mouse.moveTo(at);
      await tester.pump();
      expect(find.text('value  of total'), findsOneWidget);
      layer.nodes = [
        for (final n in layer.nodes)
          if (n.id != 'total') n,
        node('zz-new', group: 'Basket'),
      ];
      layer.changed();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(find.text('value  of total'), findsNothing);
      final shown = find.byKey(const ValueKey('debug graph tooltip'));
      expect(shown, findsNothing, reason: 'the plate it was over is gone');
      await mouse.removePointer();
    });

    testWidgets('an opened row of a card stays with its row and tells its '
        'value now', (tester) async {
      final opening = _OpeningLayer('o', nodes: [node('p', layer: 'o')]);
      await tester.pumpWidget(
        host(DebugGraphView(layers: [opening], settings: all)),
      );
      final state = stateOf(tester);
      final p = state.scene!.graph.indexOf('p')!;
      await _doubleTapAt(
        tester,
        tester.getTopLeft(graphPaint) +
            MatrixUtils.transformPoint(
              state.transform,
              state.scene!.rects[p].center,
            ),
      );
      await tester.pump(kDoubleTapTimeout);
      await tester.tap(find.textContaining('b short'));
      await tester.pump();
      expect(find.textContaining('b whole one'), findsOneWidget);
      opening
        ..rows = ['b', 'a']
        ..whole = 'b whole two'
        ..nodes = [...opening.nodes, node('q', layer: 'o')]
        ..changed();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(find.textContaining('b whole two'), findsOneWidget);
      expect(find.textContaining('a short'), findsOneWidget);
      expect(find.textContaining('a whole'), findsNothing);
    });

    testWidgets('a tooltip over a plate', (tester) async {
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final total = state.graph!.indexOf('total')!;
      final at =
          tester.getTopLeft(graphPaint) +
          MatrixUtils.transformPoint(
            state.transform,
            state.scene!.rects[total].center,
          );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await mouse.moveTo(at);
      await tester.pump();
      expect(find.byKey(const ValueKey('debug graph tooltip')), findsOneWidget);
      expect(find.text('value  of total'), findsOneWidget);
      await mouse.removePointer();
    });

    testWidgets('On screen: the widgets in the window, not those scrolled '
        'out or offstage, with what they read and what listens to the '
        'same sources; the panel over them hides nothing; All: every node', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final keys = [for (var i = 0; i < 3; i++) GlobalKey()];
      DebugGraphLayer? screenLayer;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: ListView(
                      controller: scroll,
                      children: [
                        SizedBox(key: keys[0], height: 50),
                        const SizedBox(height: 200),
                        SizedBox(key: keys[1], height: 50),
                      ],
                    ),
                  ),
                  Offstage(child: SizedBox(key: keys[2], height: 20)),
                ],
              ),
              // The debug panel over the whole app.
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF000000)),
              ),
            ],
          ),
        ),
      );
      // ListView keeps the far child built in its cache extent.
      expect(keys[1].currentContext, isNotNull);
      screenLayer = FakeLayer(
        'f',
        nodes: [
          node('shown', group: 'w', widget: keys[0].currentContext, sink: true),
          node(
            'scrolled',
            group: 'w',
            widget: keys[1].currentContext,
            sink: true,
          ),
          node(
            'offstage',
            group: 'w',
            widget: keys[2].currentContext,
            sink: true,
          ),
          node('source'),
          node('feedsScrolled'),
          node('effect', sink: true),
          node('unrelated'),
        ],
        edges: const [
          DebugGraphEdge('source', 'shown'),
          DebugGraphEdge('source', 'effect'),
          DebugGraphEdge('feedsScrolled', 'scrolled'),
          DebugGraphEdge('source', 'offstage'),
        ],
      );
      final graph = const DebugGraphAssembler().assemble(
        [(screenLayer, screenLayer.collect(DebugGraphScope.onScreen))],
        const DebugGraphSettings(),
      );
      expect(
        graph.items.map((i) => i.key).toSet(),
        {'shown', 'source', 'effect'},
      );
      expect(DebugGraphScreen.shows(keys[0].currentContext!), isTrue);
      expect(DebugGraphScreen.shows(keys[1].currentContext!), isFalse);
      expect(DebugGraphScreen.shows(keys[2].currentContext!), isFalse);

      // Scrolled: the other one shows.
      scroll.jumpTo(220);
      await tester.pump();
      expect(DebugGraphScreen.shows(keys[1].currentContext!), isTrue);
      final all = const DebugGraphAssembler().assemble(
        [(screenLayer, screenLayer.collect(DebugGraphScope.all))],
        const DebugGraphSettings(scope: DebugGraphScope.all),
      );
      expect(all.items, hasLength(7));
    });

    testWidgets('live only hides, from the view\'s Options', (tester) async {
      layer.live.add('field');
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      expect(stateOf(tester).graph!.items, hasLength(4));
      await tester.tap(find.text('Options'));
      await tester.pump();
      await tester.tap(find.text('Live only'));
      await tester.pump();
      expect(stateOf(tester).graph!.items.map((i) => i.key), ['field']);
    });

    testWidgets('a lit plate: a brighter border, a glow and at most a '
        'quarter of the flash colour in its fill, never a solid fill; the '
        'frames stop once it faded', (tester) async {
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      final state = stateOf(tester);
      final scene = state.scene!;
      final field = scene.graph.indexOf('field')!;
      final style = DebugStyle.fromApp(tester.element(graphPaint));
      final dark = scene.fillOf(field, 0);
      final lit = scene.fillOf(field, 1);
      expect(lit, isNot(dark));
      expect(lit, isNot(style.graphFlash));
      expect(
        lit,
        Color.lerp(dark, style.graphFlash, DebugGraphScene.maxFlashTint),
      );
      expect(DebugGraphScene.maxFlashTint, lessThanOrEqualTo(0.25));

      layer.glows['field'] = 1;
      for (final wake in [...layer.wakers]) {
        wake();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it animates');
      final painter =
          tester.widget<CustomPaint>(graphPaint).painter! as DebugGraphPainter;
      expect(painter.lastFrame!.lit[field], 1);
      expect(painter.lastFrame!.pulses, isNotEmpty, reason: 'along its edge');
      layer.glows.clear();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'faded');

      // Painted for real: the plate's centre is near its dark fill.
      layer.glows['field'] = 1;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      scene.paintItem(canvas, field, 1);
      final picture = recorder.endRecording();
      final rect = scene.rects[field];
      final image = await tester.runAsync(
        () => picture.toImage(rect.right.ceil() + 4, rect.bottom.ceil() + 4),
      );
      final bytes = (await tester.runAsync(
        () => image!.toByteData(),
      ))!;
      final x = (rect.left + 3).round();
      final y = rect.center.dy.round();
      final offset = (y * image!.width + x) * 4;
      final pixel = Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
      expect(
        (pixel.r - style.graphFlash.r).abs() +
            (pixel.g - style.graphFlash.g).abs() +
            (pixel.b - style.graphFlash.b).abs(),
        greaterThan(0.3),
        reason: 'not filled with the flash colour',
      );
      picture.dispose();
      image.dispose();
    });

    testWidgets('the SPI: a layer collects only while the view shows, a '
        'change of its structure lays the graph out again, a change of '
        'nothing does not', (tester) async {
      await tester.pumpWidget(
        host(DebugGraphView(layers: [layer], settings: all)),
      );
      expect(layer.started, 1);
      expect(layer.stopped, 0);
      final state = stateOf(tester);
      final layouts = state.layouts;
      layer.changed();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(state.layouts, layouts, reason: 'the same nodes and edges');
      layer.nodes = [...layer.nodes, node('new', group: 'Basket')];
      layer.changed();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(state.layouts, layouts + 1);
      expect(state.graph!.indexOf('new'), isNotNull);
      await tester.pumpWidget(const SizedBox());
      expect(layer.stopped, 1, reason: 'hidden, it stops');
      expect(layer.wakers, isEmpty);
    });

    testWidgets('the console pane: compact, nearly opaque, its layers '
        'started while it shows', (tester) async {
      final pane = DebugGraphPane([layer]);
      expect(pane.title, 'Graph');
      expect(pane.backgroundOpacity, isNull);
      final stop = pane.start();
      expect(layer.started, 1);
      stop();
      expect(layer.stopped, 1);
      final console = DebugConsole();
      addTearDown(console.dispose);
      await tester.pumpWidget(
        host(Builder(builder: (context) => pane.build(context, console))),
      );
      expect(
        tester.widget<DebugGraphView>(find.byType(DebugGraphView)).compact,
        isTrue,
      );
    });

    testWidgets('a card lists links: eight and "N more…" of a long list, a '
        'tap on a link selects its node', (tester) async {
      final linked = _LinkedLayer(
        'f',
        nodes: [
          node('total', group: 'Basket'),
          for (var i = 0; i < 12; i++) node('w$i', group: 'widgets'),
        ],
        edges: [
          for (var i = 0; i < 12; i++) DebugGraphEdge('total', 'w$i'),
        ],
      );
      await tester.pumpWidget(
        host(
          DebugGraphView(layers: [linked], settings: all),
          width: 900,
          height: 700,
        ),
      );
      final state = stateOf(tester);
      final scene = state.scene!;
      final total = scene.graph.indexOf('total')!;
      final centre = MatrixUtils.transformPoint(
        state.transform,
        scene.rects[total].center,
      );
      await _doubleTapAt(tester, tester.getTopLeft(graphPaint) + centre);
      for (var i = 0; i < 8; i++) {
        expect(find.textContaining('W$i'), findsOneWidget);
      }
      expect(find.textContaining('W8'), findsNothing);
      expect(find.text('4 more…'), findsOneWidget);

      await tester.tap(find.text('4 more…'));
      await tester.pump();
      expect(find.textContaining('W11'), findsOneWidget);

      await tester.tap(find.textContaining('W3'));
      await tester.pump();
      final painter =
          tester.widget<CustomPaint>(graphPaint).painter! as DebugGraphPainter;
      expect(painter.selected, stateOf(tester).scene!.graph.indexOf('w3'));
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('the action debug.graph.fit fits a graph on the screen as Fit '
        'does; with none shown it is not handled', (tester) async {
      final context = await tester.runAsync(
        () => SpringApplication([
          BeanModule('test', [
            BeanDefinition<DebugGraphFitAction>(
              name: 'debugGraphFit',
              types: const [DebugGraphFitAction],
              create: (_) => DebugGraphFitAction(),
            ),
          ]),
        ], bannerMode: BannerMode.off).runAsync(const []),
      );
      addTearDown(() => context!.close());
      final action = context!.getBean<DebugGraphFitAction>();
      expect(action.handle(ShortcutInvocation(action.action, null)), isFalse);
      expect(action.keys, ['primary+shift+z']);

      await tester.pumpWidget(
        SpringScope(
          applicationContext: context,
          child: host(DebugGraphView(layers: [layer], settings: all)),
        ),
      );
      final state = stateOf(tester);
      Offset centre() => MatrixUtils.transformRect(
        state.transform,
        Offset.zero & state.scene!.size,
      ).center;
      final fitted = centre();
      await tester.drag(graphPaint, const Offset(90, 40));
      await tester.pump();
      expect(centre(), isNot(fitted));

      expect(action.handle(ShortcutInvocation(action.action, null)), isTrue);
      await tester.pump();
      expect(centre().dx, closeTo(fitted.dx, 0.5));
      expect(centre().dy, closeTo(fitted.dy, 0.5));

      await tester.pumpWidget(const SizedBox());
      expect(action.handle(ShortcutInvocation(action.action, null)), isFalse);
      await tester.pump(kDoubleTapTimeout);
    });
  });

  test('build switches: the tab and the pane come only with a layer\'s '
      'module; the starter alone has no module of the graph', () {
    final source = File(
      'lib/spring_auto_configuration.dart',
    ).readAsStringSync();
    expect(source, contains('debugGraphSectionDefinitions'));
    expect(source, contains('debugGraphPaneDefinitions'));
    expect(
      source,
      isNot(contains("BeanModule('springBootStarterFlutterDebugGraph")),
      reason: 'no module of its own: a layer brings it',
    );
    final generated = File(
      'example/spring_gen/example.spring.debug.dart',
    ).readAsStringSync();
    expect(generated, isNot(contains('DebugGraph')));
  });
}

DebugGraphLayoutInput _synthetic(int seed) {
  // 20 beans of 5 fields, 4 computed values and 2 effects; 80 widgets.
  final edges = <(int, int)>[];
  final lanes = <int>[];
  final sinks = <bool>[];
  final fields = <int>[];
  final computed = <int>[];
  var id = 0;
  var r = seed;
  int next(int max) => (r = (r * 1103515245 + 12345) & 0x7fffffff) % max;
  for (var bean = 0; bean < 20; bean++) {
    final own = <int>[];
    for (var i = 0; i < 5; i++, id++) {
      lanes.add(bean);
      sinks.add(false);
      fields.add(id);
      own.add(id);
    }
    for (var i = 0; i < 4; i++, id++) {
      lanes.add(bean);
      sinks.add(false);
      for (var k = 0; k <= next(3); k++) {
        final from = computed.isNotEmpty && next(4) == 0
            ? computed[next(computed.length)]
            : own[next(own.length)];
        edges.add((from, id));
      }
      computed.add(id);
      own.add(id);
    }
    for (var i = 0; i < 2; i++, id++) {
      lanes.add(bean);
      sinks.add(true);
      edges.add((own[next(own.length)], id));
    }
  }
  for (var widget = 0; widget < 80; widget++, id++) {
    lanes.add(20);
    sinks.add(true);
    for (var k = 0; k <= next(3); k++) {
      final pool = next(2) == 0 ? computed : fields;
      edges.add((pool[next(pool.length)], id));
    }
  }
  return DebugGraphLayoutInput(
    widths: List.filled(id, 90),
    heights: List.filled(id, 22),
    edges: edges,
    lanes: lanes,
    laneCount: 21,
    sinks: sinks,
    laneHeader: 14,
  );
}

DebugGraphLayoutInput _tree(int count) => DebugGraphLayoutInput(
  widths: List.filled(count, 90),
  heights: List.filled(count, 22),
  edges: [for (var i = 1; i < count; i++) ((i - 1) ~/ 3, i)],
  lanes: List.filled(count, 0),
  laneCount: 1,
  sinks: List.filled(count, false),
);

// A double tap at [at]: a plate's card opens (or closes).
Future<void> _doubleTapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(at);
  await tester.pump();
}
