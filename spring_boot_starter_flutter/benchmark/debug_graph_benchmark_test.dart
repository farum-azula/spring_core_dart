// Timings of the application graph's engine (debug / JIT, so slower than
// a release build): the layered layout of 300 signal nodes (20 beans of 5
// fields, 4 computed values and 2 effects, 80 widgets reading them, a lane
// per bean), the tree layout of 2000 widgets, the assembly of the 300
// nodes (merge, filters, folds), the scene (labels measured, laid out,
// the still picture recorded), a frame of flashes over it, and the widgets
// layer over 2000 elements (walk, On screen, assembly, scene). Not part of
// the tests (outside test/); run with
//   flutter test benchmark/debug_graph_benchmark_test.dart
//
// November 2026, Apple M5, median of 7 (three runs): layout of 300 nodes
// 4.1-4.3 ms, tree of 2000 0.9-1.1 ms, assembly of 300 nodes 0.5-0.6 ms,
// the scene of 300 nodes 9-10 ms (once per change of structure), the
// still picture 1.3-1.4 ms (once per scene and selection), a frame with
// 10 lit plates and their pulses 0.07-0.1 ms. The widgets layer over a
// tree of 2031 elements (500 of the app's): a walk 1.0 ms, On screen in one
// pass over the boxes 0.5 ms, the assembly of its 500 nodes 0.6 ms, their
// tree scene 3.5-4 ms. Hidden, the graph has no timer, listener, probe or
// rebuild hook: nothing.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Layer extends DebugGraphLayer {
  _Layer(this.part);

  final DebugGraphPart part;
  final Set<String> lit = {};

  @override
  String get id => 'signals';

  @override
  String get title => 'Signals';

  @override
  Color colorOf(DebugStyle style) => style.logger;

  @override
  List<DebugGraphKind> get kinds => const [
    DebugGraphKind('signal', 'signal', DebugGraphShape.rounded),
    DebugGraphKind('computed', 'computed', DebugGraphShape.hexagon),
    DebugGraphKind('effect', 'effect', DebugGraphShape.parallelogram),
    DebugGraphKind('widget', 'widget', DebugGraphShape.pill),
  ];

  @override
  Listenable get changes => const _Never();

  @override
  DebugGraphPart collect(DebugGraphScope scope) => part;

  @override
  double glowOf(DebugGraphNode node) => lit.contains(node.id) ? 0.7 : 0;
}

final class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

DebugGraphPart signals300() {
  var r = 42;
  int next(int max) => (r = (r * 1103515245 + 12345) & 0x7fffffff) % max;
  final nodes = <DebugGraphNode>[];
  final edges = <DebugGraphEdge>[];
  final fields = <String>[];
  final computed = <String>[];
  for (var bean = 0; bean < 20; bean++) {
    final own = <String>[];
    final group = 'Bean$bean';
    for (var i = 0; i < 5; i++) {
      final id = 'signals:$group.field$i';
      nodes.add(
        DebugGraphNode(
          id: id,
          layer: 'signals',
          kind: 'signal',
          label: 'field$i',
          group: group,
        ),
      );
      fields.add(id);
      own.add(id);
    }
    for (var i = 0; i < 4; i++) {
      final id = 'signals:$group.computed$i';
      nodes.add(
        DebugGraphNode(
          id: id,
          layer: 'signals',
          kind: 'computed',
          label: 'computed$i',
          group: group,
        ),
      );
      for (var k = 0; k <= next(3); k++) {
        edges.add(DebugGraphEdge(own[next(own.length)], id));
      }
      computed.add(id);
      own.add(id);
    }
    for (var i = 0; i < 2; i++) {
      final id = 'signals:$group.effect$i()';
      nodes.add(
        DebugGraphNode(
          id: id,
          layer: 'signals',
          kind: 'effect',
          label: 'effect$i()',
          group: group,
          sink: true,
        ),
      );
      edges.add(DebugGraphEdge(own[next(own.length)], id));
    }
  }
  for (var widget = 0; widget < 80; widget++) {
    final id = 'signals:widget$widget';
    nodes.add(
      DebugGraphNode(
        id: id,
        layer: 'signals',
        kind: 'widget',
        label: 'Widget$widget',
        group: 'widgets',
        sink: true,
      ),
    );
    for (var k = 0; k <= next(3); k++) {
      final pool = next(2) == 0 ? computed : fields;
      edges.add(DebugGraphEdge(pool[next(pool.length)], id));
    }
  }
  return DebugGraphPart(nodes, edges);
}

double median(void Function() run, {int times = 7}) {
  for (var i = 0; i < 2; i++) {
    run();
  }
  final micros = <int>[];
  for (var i = 0; i < times; i++) {
    final watch = Stopwatch()..start();
    run();
    micros.add(watch.elapsedMicroseconds);
  }
  micros.sort();
  return micros[times ~/ 2] / 1000;
}

void main() {
  testWidgets('the application graph', (tester) async {
    void say(String what, double ms) =>
        // ignore: avoid_print
        print('${what.padRight(44)} ${ms.toStringAsFixed(2)} ms');

    final layer = _Layer(signals300());
    const settings = DebugGraphSettings(scope: DebugGraphScope.all);
    final graph = const DebugGraphAssembler().assemble([
      (layer, layer.part),
    ], settings);
    final input = DebugGraphLayoutInput(
      widths: List.filled(graph.items.length, 90),
      heights: List.filled(graph.items.length, 22),
      edges: [for (final link in graph.links) (link.from, link.to)],
      lanes: [for (final item in graph.items) item.lane],
      laneCount: graph.lanes.length,
      sinks: [for (final item in graph.items) item.sink],
      laneHeader: 14,
    );
    say(
      'layered layout, ${graph.items.length} nodes',
      median(() => const LayeredDebugGraphLayout().place(input)),
    );
    final tree = DebugGraphLayoutInput(
      widths: List.filled(2000, 90),
      heights: List.filled(2000, 22),
      edges: [for (var i = 1; i < 2000; i++) ((i - 1) ~/ 3, i)],
      lanes: List.filled(2000, 0),
      laneCount: 1,
      sinks: List.filled(2000, false),
    );
    say(
      'tree layout, 2000 nodes',
      median(() => const TreeDebugGraphLayout().place(tree)),
    );
    say(
      'assembly, 300 nodes',
      median(
        () => const DebugGraphAssembler().assemble([
          (layer, layer.part),
        ], settings),
      ),
    );

    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    final style = DebugStyle.fromApp(tester.element(find.byType(SizedBox)));
    say(
      'scene (measure, lay out), 300 nodes',
      median(() => DebugGraphScene.of(graph, style: style).dispose()),
    );
    final scene = DebugGraphScene.of(graph, style: style);
    say(
      'still picture, 300 nodes',
      median(() {
            scene.still(selected: 0);
            scene.still();
          }) /
          2,
    );
    layer.lit.addAll([
      for (var i = 0; i < 10; i++) graph.items[i * 20].key,
    ]);
    say(
      'a frame, 10 lit plates and their pulses',
      median(() {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final frame = scene.frame();
        for (final (edge, t, alpha) in frame.pulses) {
          scene.paintPulse(canvas, edge, t, alpha);
        }
        for (final MapEntry(key: item, value: lamp) in frame.lit.entries) {
          scene.paintItem(canvas, item, lamp);
        }
        recorder.endRecording().dispose();
      }),
    );
    scene.dispose();
  });

  testWidgets('the widgets layer over 2000 elements', (tester) async {
    void say(String what, double ms) =>
        // ignore: avoid_print
        print('${what.padRight(44)} ${ms.toStringAsFixed(2)} ms');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Column(children: [for (var i = 0; i < 500; i++) _Tile(i)]),
        ),
      ),
    );
    var elements = 0;
    void count(Element element) {
      elements++;
      element.visitChildren(count);
    }

    tester.binding.rootElement!.visitChildren(count);
    final layer = WidgetsGraphLayer(root: () => tester.binding.rootElement);
    final stop = layer.start();
    say('walk, $elements elements', median(layer.walkNow));
    say(
      'collect On screen (one pass over the boxes)',
      median(() => layer.collect(DebugGraphScope.onScreen)),
    );
    final part = layer.collect(DebugGraphScope.all);
    const settings = DebugGraphSettings(scope: DebugGraphScope.all);
    say(
      'assembly, ${part.nodes.length} widget nodes',
      median(
        () => const DebugGraphAssembler().assemble([(layer, part)], settings),
      ),
    );
    final opened = DebugGraphSettings(
      scope: DebugGraphScope.all,
      opened: {
        for (final item in const DebugGraphAssembler().assemble([
          (layer, part),
        ], settings).items)
          if (item.folded) item.key,
      },
    );
    final graph = const DebugGraphAssembler().assemble([(layer, part)], opened);
    final style = DebugStyle.fromApp(tester.binding.rootElement!);
    say(
      'scene (tree), ${graph.items.length} plates',
      median(
        () => DebugGraphScene.of(
          graph,
          style: style,
          layout: const TreeDebugGraphLayout(),
        ).dispose(),
      ),
    );
    stop();
  });
}

class _Tile extends StatelessWidget {
  const _Tile(this.n);

  final int n;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(1), child: Text('tile $n'));
}
