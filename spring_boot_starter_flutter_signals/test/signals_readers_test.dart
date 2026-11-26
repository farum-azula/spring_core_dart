// The readers of the signals graph when the debug panel opens over an app
// already built: its widgets stay mounted under the panel and are not
// built again by it, yet the graph (On screen, the panel over them), the
// list and the console's pane show them as readers with their edges.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

// The app under the panel: a Spring widget and a Watch that read the
// basket, as the Dota home page's header and backdrop read their beans.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    final basket = context.bean<Basket>();
    return Column(
      children: [
        const CouponLabel(),
        Watch((context) => Text('Items: ${basket.items.length}')),
        const _Quiet(),
      ],
    );
  }
}

// Followed, but reads nothing: no reader.
class _Quiet extends StatelessWidget {
  const _Quiet();

  @override
  Widget build(BuildContext context) => Watch((context) => const Text('-'));
}

class _Host extends StatelessWidget {
  const _Host({required this.open, required this.panel});

  final bool open;
  final Widget Function(BuildContext context) panel;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const _Page(),
      if (open)
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xFF16181D),
            child: Builder(builder: panel),
          ),
        ),
    ],
  );
}

void main() {
  late SignalsDebugRecorder recorder;
  late ApplicationContext context;

  Future<void> pump(
    WidgetTester tester, {
    required bool open,
    required Widget Function(BuildContext) panel,
  }) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: _Host(open: open, panel: panel),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    context = SpringScope.of(tester.element(find.byType(_Page)));
  }

  List<String> edgesOf(DebugGraphPart part) {
    final labels = {for (final node in part.nodes) node.id: node.label};
    return [
      for (final edge in part.edges)
        '${labels[edge.from]} → ${labels[edge.to]}',
    ]..sort();
  }

  List<String> linksOf(DebugGraph graph) => [
    for (final link in graph.links)
      '${graph.items[link.from].label} → ${graph.items[link.to].label}',
  ]..sort();

  DebugGraph shownGraph(WidgetTester tester) =>
      tester.state<DebugGraphViewState>(find.byType(DebugGraphView)).graph!;

  testWidgets('the panel opens over a built app: its widgets, mounted under '
      'it, are readers with edges in the graph and the list', (tester) async {
    late SignalsGraphLayer layer;
    late SignalsDebugSection tab;
    Widget section(BuildContext c) => tab.build(c);
    await pump(tester, open: false, panel: (_) => const SizedBox());
    recorder = context.getBean<SignalsDebugRecorder>();
    layer = context.getBean<SignalsGraphLayer>();
    tab = SignalsDebugSection(
      context.getBean<SignalBeans>(),
      recorder: recorder,
      graph: layer,
    );
    expect(SignalProbes.current, isNull, reason: 'nothing collects yet');

    // The panel opens on the Graph sub-tab; nothing in the app changes.
    await pump(tester, open: true, panel: section);
    await tester.tap(find.text('Graph'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    final beans = context.getBean<SignalBeans>().live.toList();
    expect(
      edgesOf(layer.collect(DebugGraphScope.all)),
      containsAll(['coupon → CouponLabel', 'items → Watch in _Page']),
    );
    // On screen, though the panel covers them.
    final graph = shownGraph(tester);
    expect(
      graph.items.map((n) => n.label),
      containsAll(['CouponLabel', 'Watch in _Page']),
    );
    expect(linksOf(graph), contains('coupon → CouponLabel'));
    expect(
      graph.items.map((n) => n.label),
      isNot(contains('Watch in _Quiet')),
      reason: 'it read nothing',
    );
    expect(
      SignalsTree.lines(recorder, beans).map((line) => line.label),
      containsAll([
        startsWith('CouponLabel · '),
        startsWith('Watch in _Page · '),
      ]),
    );

    // Still readers a few seconds later, the app covered and idle.
    await tester.pump(const Duration(seconds: 3));
    recorder.pruneEnded();
    expect(
      edgesOf(layer.collect(DebugGraphScope.all)),
      contains('coupon → CouponLabel'),
    );
    await pump(tester, open: false, panel: section);
    expect(SignalProbes.current, isNull);
  });

  testWidgets("the console's pane over a built app shows the readers too", (
    tester,
  ) async {
    late SignalsPane pane;
    final console = DebugConsole();
    addTearDown(console.dispose);
    Widget shown(BuildContext c) => SizedBox(
      height: pane.initialHeight,
      child: pane.build(c, console),
    );
    await pump(tester, open: false, panel: shown);
    recorder = context.getBean<SignalsDebugRecorder>();
    pane = SignalsPane(context.getBean<SignalsGraphLayer>());
    final stop = pane.start();
    await pump(tester, open: true, panel: shown);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      linksOf(shownGraph(tester)),
      containsAll(['coupon → CouponLabel', 'items → Watch in _Page']),
    );
    await pump(tester, open: false, panel: shown);
    stop();
    expect(SignalProbes.current, isNull);
  });
}
