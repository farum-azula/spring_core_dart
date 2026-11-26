// The widgets layer of the application graph: only the application's
// widgets (Flutter's wrappers folded into them), every element with
// "framework widgets", repeats folded, the tree layout, a flash and the
// counts of rebuilds, the hot branch, On screen vs All (scrolled out,
// offstage, a route under another, a scene drawn elsewhere), the details,
// the outline over the app, the node of any element, the build switch.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class ReviewTile extends StatelessWidget {
  const ReviewTile(this.n, {super.key});

  final int n;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(1), child: Text('review $n'));
}

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => CounterState();
}

class CounterState extends State<Counter> {
  int count = 0;

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 40, height: 20, child: Text('$count'));
}

class Page extends StatelessWidget {
  const Page({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        const Counter(),
        Align(
          child: Builder(
            builder: (context) => Column(
              children: [for (var i = 0; i < 10; i++) ReviewTile(i)],
            ),
          ),
        ),
        Container(height: 4),
      ],
    ),
  );
}

// A widget drawn elsewhere (as a 3D scene's are): under an Offstage marked
// PaintedElsewhere, and one under a plain Offstage.
class Scenery extends StatelessWidget {
  const Scenery({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

class Hidden extends StatelessWidget {
  const Hidden({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

class Far extends StatelessWidget {
  const Far({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 40);
}

class Paused extends StatelessWidget {
  const Paused({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

class Screens extends StatelessWidget {
  const Screens({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        SizedBox(
          height: 100,
          child: ListView(
            children: const [
              ReviewTile(0),
              SizedBox(height: 150),
              Far(),
            ],
          ),
        ),
        SizedBox(
          height: 20,
          child: Stack(
            children: [
              Offstage(key: const PaintedElsewhere(), child: const Scenery()),
              const Offstage(child: Hidden()),
              const TickerMode(enabled: false, child: Paused()),
            ],
          ),
        ),
      ],
    ),
  );
}

// A widget of a library that only calls a builder of the app's, as a
// starter's `Watch`.
class Relay extends StatelessWidget {
  const Relay({required this.builder, super.key});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

WidgetsGraphLayer layerOf(WidgetTester tester, {Duration Function()? clock}) =>
    WidgetsGraphLayer(
      root: () => tester.binding.rootElement,
      clock: clock,
    );

List<String> labelsOf(DebugGraphPart part) => [
  for (final node in part.nodes) node.label,
];

final class _Clock {
  Duration now = const Duration(seconds: 100);
  Duration call() => now;
}

void main() {
  testWidgets('only the application\'s widgets, Flutter\'s wrappers folded '
      'into them; repeats folded; every element with "framework widgets"', (
    tester,
  ) async {
    await tester.pumpWidget(const Page());
    final layer = layerOf(tester);
    final stop = layer.start();
    addTearDown(stop);
    expect(layer.files!.known, isTrue, reason: 'creation locations');
    final part = layer.collect(DebugGraphScope.all);
    expect(labelsOf(part).toSet(), {'Page', 'Counter', 'ReviewTile'});
    expect(labelsOf(part).where((l) => l == 'ReviewTile'), hasLength(10));
    final page = part.nodes.firstWhere((n) => n.label == 'Page');
    final tile = part.nodes.firstWhere((n) => n.label == 'ReviewTile');
    expect(tile.group, page.id, reason: 'Align and Builder folded away');
    expect(
      part.edges.where((e) => e.from == page.id),
      hasLength(11),
      reason: 'Page → Counter and the ten tiles',
    );
    expect(
      part.nodes.firstWhere((n) => n.label == 'Counter').kind,
      'stateful',
    );
    expect(tile.kind, 'stateless');
    expect(page.id, DebugGraphWidgets.idOf(tester.element(find.byType(Page))));

    final graph = const DebugGraphAssembler().assemble(
      [(layer, part)],
      const DebugGraphSettings(scope: DebugGraphScope.all),
    );
    expect(
      graph.items.map((i) => i.label),
      containsAll(['Page', 'Counter', 'ReviewTile ×10']),
    );
    expect(graph.lanes, isNotEmpty);
    expect(layer.lanes, isFalse, reason: 'groups are no lanes');

    // Every element.
    layer.options.single.onChanged(true);
    final everything = layer.collect(DebugGraphScope.all);
    expect(
      labelsOf(everything),
      containsAll(['Padding', 'Align', 'Builder', 'Container']),
    );
    expect(
      everything.nodes.firstWhere((n) => n.label == 'Align').kind,
      'framework',
    );
  });

  testWidgets('a builder a starter registers is no widget of the app\'s; '
      'Flutter\'s are built in, a starter\'s are not', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Relay(builder: (_) => const ReviewTile(0)),
      ),
    );
    final layer = layerOf(tester);
    final stop = layer.start();
    addTearDown(stop);
    expect(labelsOf(layer.collect(DebugGraphScope.all)), contains('Relay'));
    expect(DebugGraphWidgets.builders, containsAll(['Builder', 'Visibility']));
    expect(DebugGraphWidgets.builders, isNot(contains('Watch')));
    expect(DebugGraphWidgets.builders, isNot(contains('AsyncView')));

    const relays = DebugGraphBuilders({'Relay'});
    DebugGraphWidgets.addBuilders(relays);
    addTearDown(() => DebugGraphWidgets.removeBuilders(relays));
    expect(DebugGraphWidgets.isBuilderType('Relay<int>'), isTrue);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Relay(builder: (_) => const ReviewTile(1)),
      ),
    );
    final fresh = layerOf(tester);
    final stopFresh = fresh.start();
    addTearDown(stopFresh);
    final labels = labelsOf(fresh.collect(DebugGraphScope.all));
    expect(labels, isNot(contains('Relay')));
    expect(labels, contains('ReviewTile'));
    DebugGraphWidgets.removeBuilders(relays);
    expect(DebugGraphWidgets.isBuilderType('Relay'), isFalse);
  });

  testWidgets('a tree from top to bottom: parents above their children', (
    tester,
  ) async {
    await tester.pumpWidget(const Page());
    final layer = layerOf(tester);
    final stop = layer.start();
    addTearDown(stop);
    expect(layer.layout, isA<TreeDebugGraphLayout>());
    final graph = const DebugGraphAssembler().assemble(
      [(layer, layer.collect(DebugGraphScope.all))],
      const DebugGraphSettings(scope: DebugGraphScope.all),
    );
    final scene = DebugGraphScene.of(
      graph,
      style: DebugStyle.fromApp(tester.element(find.byType(Page))),
      layout: layer.layout,
    );
    addTearDown(scene.dispose);
    expect(scene.placement.flow, Axis.vertical);
    final page = graph.indexOf(
      DebugGraphWidgets.idOf(tester.element(find.byType(Page))),
    )!;
    for (final link in graph.links.where((l) => l.from == page)) {
      expect(scene.rects[link.to].top, greaterThan(scene.rects[page].bottom));
    }
    expect(scene.lanes, isEmpty, reason: 'no lane bands in a tree');

    // A branch collapses into its head.
    final collapsed = const DebugGraphAssembler().assemble(
      [(layer, layer.collect(DebugGraphScope.all))],
      DebugGraphSettings(
        scope: DebugGraphScope.all,
        collapsed: {DebugGraphBranchFold.keyOf(graph.items[page].key)},
      ),
    );
    expect(collapsed.items.single.label, 'Page ▸ 12');
  });

  testWidgets('a rebuild flashes its node and is counted, with its build '
      'time; a widget built often is hot, and the branch above it', (
    tester,
  ) async {
    final clock = _Clock();
    await tester.pumpWidget(const Page());
    final layer = layerOf(tester, clock: clock.call);
    final stop = layer.start();
    addTearDown(stop);
    var woken = 0;
    final stopWaking = layer.onActivity(() => woken++);
    addTearDown(stopWaking);
    DebugGraphNode nodeOf(String label) => layer
        .collect(DebugGraphScope.all)
        .nodes
        .firstWhere((n) => n.label == label);
    expect(layer.glowOf(nodeOf('Counter')), 0);
    final state = tester.state<CounterState>(find.byType(Counter));
    for (var i = 0; i < 4; i++) {
      state.bump();
      await tester.pump();
    }
    expect(layer.rebuilds.hearsEach, isTrue, reason: 'a debug build');
    expect(woken, greaterThan(0));
    expect(layer.glowOf(nodeOf('Counter')), 1);
    expect(layer.isLive(nodeOf('Counter'), const Duration(seconds: 5)), isTrue);
    expect(layer.isLive(nodeOf('Page'), const Duration(seconds: 5)), isFalse);
    final details = {
      for (final d in layer.detailsOf(nodeOf('Counter'))) d.label: d.value,
    };
    expect(details['rebuilds'], '4 in 5s');
    expect(details['build'], contains('last'));
    expect(details['state'], 'CounterState');
    expect(layer.heatOf(nodeOf('Counter')), 1);
    expect(layer.heatOf(nodeOf('Page')), 1, reason: 'the branch above');
    expect(layer.heatOf(nodeOf('ReviewTile')), 0);
    clock.now += const Duration(seconds: 2);
    expect(layer.glowOf(nodeOf('Counter')), 0, reason: 'faded');
  });

  testWidgets('a hot branch cools as its rebuilds leave the window, with '
      'no card open', (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(const Page());
    final layer = layerOf(tester, clock: clock.call);
    final stop = layer.start();
    addTearDown(stop);
    DebugGraphNode nodeOf(String label) => layer
        .collect(DebugGraphScope.all)
        .nodes
        .firstWhere((n) => n.label == label);
    final state = tester.state<CounterState>(find.byType(Counter));
    for (var i = 0; i < 4; i++) {
      state.bump();
      await tester.pump();
    }
    expect(layer.heatOf(nodeOf('Counter')), 1);
    clock.now += layer.hotWindow + layer.walkEvery;
    expect(layer.heatOf(nodeOf('Counter')), 0);
    expect(layer.heatOf(nodeOf('Page')), 0);
  });

  testWidgets('details: type, key, size and place, route; a tap outlines '
      'the widget over the app and selects it in the inspector', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => Navigator(
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            pageBuilder: (context, _, _) =>
                const Center(child: Counter(key: ValueKey('one'))),
          ),
        ),
      ),
    );
    final layer = layerOf(tester);
    final stop = layer.start();
    addTearDown(stop);
    final counter = layer
        .collect(DebugGraphScope.all)
        .nodes
        .firstWhere((n) => n.label == 'Counter [one]');
    expect(counter.kind, 'screen', reason: 'the first of a route');
    final details = {
      for (final d in layer.detailsOf(counter)) d.label: d.value,
    };
    expect(details['type'], 'Counter');
    expect(details['key'], contains('one'));
    expect(details['size'], '40.0 × 20.0');
    expect(details['position'], isNotNull);
    expect(details['route'], contains('(top)'));
    expect(details['created'], contains('debug_widgets_graph_test.dart'));

    layer.select(counter);
    await tester.pump();
    expect(layer.highlighted, tester.getRect(find.byType(Counter)));
    expect(
      WidgetInspectorService.instance.selection.currentElement,
      tester.element(find.byType(Counter)),
    );
    layer.select(null);
    await tester.pump();
    expect(layer.highlighted, isNull);
  });

  testWidgets('On screen: what shows and the branch above it; not what is '
      'scrolled out, offstage or under a TickerMode that is off; a widget '
      'drawn elsewhere (PaintedElsewhere) shows. All: every mounted one', (
    tester,
  ) async {
    await tester.pumpWidget(const Screens());
    final layer = layerOf(tester);
    final stop = layer.start();
    addTearDown(stop);
    expect(find.byType(Far, skipOffstage: false), findsOneWidget);
    final onScreen = layer.collect(DebugGraphScope.onScreen);
    final shown = {
      for (final node in onScreen.nodes)
        if (node.onScreen ?? false) node.label,
    };
    expect(shown, containsAll(['Screens', 'ReviewTile', 'Scenery']));
    expect(shown, isNot(contains('Far')));
    expect(shown, isNot(contains('Hidden')));
    expect(shown, isNot(contains('Paused')));
    // The same, one widget at a time.
    expect(
      DebugGraphScreen.shows(
        tester.element(find.byType(Scenery, skipOffstage: false)),
      ),
      isTrue,
    );
    expect(
      DebugGraphScreen.shows(
        tester.element(find.byType(Hidden, skipOffstage: false)),
      ),
      isFalse,
    );
    expect(
      DebugGraphScreen.shows(
        tester.element(find.byType(Paused, skipOffstage: false)),
      ),
      isFalse,
    );
    final graph = const DebugGraphAssembler().assemble(
      [(layer, onScreen)],
      const DebugGraphSettings(),
    );
    expect(
      graph.items.map((i) => i.label).toSet(),
      {'Screens', 'ReviewTile', 'Scenery'},
    );
    final all = const DebugGraphAssembler().assemble(
      [(layer, layer.collect(DebugGraphScope.all))],
      const DebugGraphSettings(scope: DebugGraphScope.all),
    );
    expect(
      all.items.map((i) => i.label),
      containsAll(['Far', 'Hidden', 'Paused']),
    );
  });

  testWidgets('the node of any element, State or widget: the node it is '
      'folded into; nothing kept once hidden', (tester) async {
    await tester.pumpWidget(const Page());
    final layer = layerOf(tester);
    final stop = layer.start();
    final page = DebugGraphWidgets.idOf(tester.element(find.byType(Page)));
    expect(layer.nodeIdOf(tester.element(find.byType(Align))), page);
    expect(layer.nodeIdOf(tester.element(find.byType(Container))), page);
    expect(
      layer.nodeIdOf(tester.state(find.byType(Counter))),
      DebugGraphWidgets.idOf(tester.element(find.byType(Counter))),
    );
    expect(layer.nodeIdOf(tester.widget(find.byType(Page))), page);
    stop();
    expect(layer.nodeIdOf(tester.element(find.byType(Align))), isNull);
    expect(layer.rebuilds.hearsEach, isFalse);
    expect(debugOnRebuildDirtyWidget, isNull, reason: 'the hook given back');
  });

  testWidgets('in the Graph tab: the tree, its legend and switch', (
    tester,
  ) async {
    late WidgetsGraphLayer layer;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            const SizedBox(height: 200, child: Page()),
            Expanded(
              child: KeyedSubtree(
                key: const DebugToolSubtree(),
                child: Builder(
                  builder: (context) {
                    layer = layerOf(tester);
                    return DebugGraphView(
                      layers: [layer],
                      settings: const DebugGraphSettings(
                        scope: DebugGraphScope.all,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<DebugGraphViewState>(
      find.byType(DebugGraphView),
    );
    expect(state.scene!.placement.flow, Axis.vertical);
    await tester.tap(find.text('Options'));
    await tester.pump();
    expect(find.text('framework widgets'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debug graph popup barrier')));
    await tester.pump();
    await tester.tap(find.text('Legend'));
    await tester.pump();
    expect(find.byKey(const ValueKey('legend widgets spring')), findsOneWidget);
    expect(
      state.graph!.items.map((i) => i.label),
      isNot(contains('DebugGraphView')),
      reason: 'the debug tools are not the app',
    );
    expect(find.text('all groups'), findsNothing, reason: 'no lanes');
  });

  testWidgets('2000 elements: walked and collected fast', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Column(
            children: [for (var i = 0; i < 500; i++) ReviewTile(i)],
          ),
        ),
      ),
    );
    var elements = 0;
    void count(Element element) {
      elements++;
      element.visitChildren(count);
    }

    tester.binding.rootElement!.visitChildren(count);
    expect(elements, greaterThan(2000));
    final layer = layerOf(tester);
    final stop = layer.start();
    addTearDown(stop);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      layer
        ..walkNow()
        ..collect(DebugGraphScope.onScreen);
    }
    final each = watch.elapsedMicroseconds / 5;
    // ignore: avoid_print
    print(
      'widgets layer: $elements elements walked and collected (On '
      'screen) in ${(each / 1000).toStringAsFixed(1)} ms',
    );
    expect(each, lessThan(500000));
  });

  test('build switch: by spring.flutter.debug.graph.layers (widgets, * or '
      'not set) inside the graph\'s and the panel\'s; the pane inside the '
      'console\'s', () {
    final source = File(
      'lib/spring_auto_configuration.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(
      source,
      contains(
        "AutoConfigurationBuild.named('spring.flutter.debug.graph.layers',"
        "'widgets',whenMissing:BuildInclusion.always,parents:["
        "AutoConfigurationBuild('spring.flutter.debug.graph.enabled'),"
        "AutoConfigurationBuild('spring.flutter.debug.enabled'),],),)"
        'finalBeanModulespringBootStarterFlutterDebugWidgetsGraphAutoConfiguration',
      ),
    );
    expect(
      source,
      contains(
        "AutoConfigurationBuild.named('spring.flutter.debug.graph.layers',"
        "'widgets',whenMissing:BuildInclusion.always,),],),)"
        'finalBeanModulespringBootStarterFlutterDebugConsoleWidgetsGraphPaneAutoConfiguration',
      ),
    );
  });
}
