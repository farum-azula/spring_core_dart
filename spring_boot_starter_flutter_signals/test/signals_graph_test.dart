// The signals layer of the application graph: the fields, computed values
// and effects of the example's beans, a lane per bean, the widgets that
// read them folded by type, a Watch named after the widget it is in, a
// tick that lights a node (the flash and the pulse), "live only", and the
// Graph sub-tab of the Signals tab; the module of the layer behind its own
// switch, with the Graph tab and the `graph` pane.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show
        ApplicationContextRunner,
        doesNotHaveBean,
        hasSingleBean,
        springBootTest;

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

/// A clock a test moves by hand.
final class _Clock {
  Duration now = Duration.zero;
  Duration call() => now;
}

// A plain widget with a Watch in it.
class _Tile extends StatelessWidget {
  const _Tile();

  @override
  Widget build(BuildContext context) {
    final basket = context.bean<Basket>();
    return Watch((context) => Text('${basket.items.length}'));
  }
}

void main() {
  group('the layer of the example', () {
    late _Clock clock;
    late SignalsDebugRecorder recorder;
    late SignalsGraphLayer layer;
    late void Function() stop;
    final app = springBootTest(springApplication);

    setUp(() {
      clock = _Clock();
      recorder = SignalsDebugRecorder(clock: clock.call);
      layer = SignalsGraphLayer(app.getBean<SignalBeans>(), recorder);
      stop = layer.start();
    });

    tearDown(() {
      stop();
      layer.dispose();
    });

    void use(Basket basket) {
      basket
        ..coupon = 'TEN'
        ..add(const Book('Dune', 10));
      app.getBean<SignalRuntime>().queues.primary.flush();
      expect(basket.total, greaterThan(0));
    }

    test('fields, computed values and the effect in the bean\'s lane, '
        'each kind its own; an edge from what is read to its reader', () {
      use(app.getBean<Basket>());
      final part = layer.collect(DebugGraphScope.all);
      final byLabel = {for (final node in part.nodes) node.label: node};
      expect(byLabel['coupon']!.kind, 'signal');
      expect(byLabel['total']!.kind, 'computed');
      expect(byLabel['save()']!.kind, 'effect');
      expect(byLabel['save()']!.sink, isTrue);
      for (final label in ['coupon', 'total', 'save()']) {
        expect(byLabel[label]!.group, 'Basket');
        expect(byLabel[label]!.layer, 'signals');
      }
      String label(String id) =>
          part.nodes.firstWhere((node) => node.id == id).label;
      final edges = {
        for (final edge in part.edges)
          '${label(edge.from)} → ${label(edge.to)}',
      };
      expect(
        edges,
        containsAll(['coupon → total', 'items → total', 'items → save()']),
      );
      expect(
        layer.kinds.map((kind) => kind.shape).toSet(),
        hasLength(layer.kinds.length),
        reason: 'a shape per kind',
      );
      expect(layer.detailsOf(byLabel['coupon']!).first.value, "'TEN'");
    });

    testWidgets('widgets in the Widgets lane, those of one type folded '
        '(CouponLabel ×3) until opened; a Watch named after the widget it '
        'is in, never "a widget"', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => springApplication,
          home: const Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                CouponLabel(key: ValueKey(0)),
                CouponLabel(key: ValueKey(1)),
                CouponLabel(key: ValueKey(2)),
                _Tile(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      recorder.pruneEnded();
      final part = layer.collect(DebugGraphScope.all);
      final widgets = [
        for (final node in part.nodes)
          if (node.group == SignalsGraphLayer.widgetsGroup) node,
      ];
      expect(
        widgets.map((node) => node.label),
        containsAll([
          'CouponLabel [0]',
          'CouponLabel [1]',
          'CouponLabel [2]',
          'Watch in _Tile',
        ]),
      );
      expect(widgets.map((node) => node.label), isNot(contains('a widget')));
      expect(
        widgets.firstWhere((node) => node.label == 'Watch in _Tile').kind,
        'watch',
      );
      expect(
        widgets.firstWhere((node) => node.label == 'CouponLabel [0]').kind,
        'widget',
      );
      expect(widgets.every((node) => node.widget != null), isTrue);
      final graph = const DebugGraphAssembler().assemble(
        [(layer, part)],
        const DebugGraphSettings(scope: DebugGraphScope.all),
      );
      final fold = graph.items.singleWhere((item) => item.folded);
      expect(fold.label, 'CouponLabel ×3');
      final opened = const DebugGraphAssembler().assemble(
        [(layer, part)],
        fold.fold!.open(const DebugGraphSettings(scope: DebugGraphScope.all)),
      );
      expect(
        opened.items.where((item) => item.label.startsWith('CouponLabel')),
        hasLength(3),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with the widgets layer: a reader widget is that layer\'s '
        'node (no second one), the edge from what it read goes to it, its '
        'details tell its reads and its beans; without it the reader shows '
        'as its own node', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => springApplication,
          home: const Directionality(
            textDirection: TextDirection.ltr,
            child: Column(children: [CouponLabel(), _Tile()]),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      final context = SpringScope.of(tester.element(find.byType(CouponLabel)));
      final widgets = WidgetsGraphLayer(
        context: context,
        root: () => tester.binding.rootElement,
      );
      final stopWidgets = widgets.start();
      addTearDown(stopWidgets);
      final unified = SignalsGraphLayer(
        context.getBean<SignalBeans>(),
        recorder,
        widgets: widgets,
      );
      final label = tester.element(find.byType(CouponLabel));
      const settings = DebugGraphSettings(scope: DebugGraphScope.all);
      final both = const DebugGraphAssembler().assemble([
        (widgets, widgets.collect(DebugGraphScope.all)),
        (unified, unified.collect(DebugGraphScope.all)),
      ], settings);
      final labels = [for (final item in both.items) item.label];
      expect(
        labels.where((l) => l.startsWith('CouponLabel')),
        hasLength(1),
        reason: 'one node for the widget',
      );
      final widgetNode = both.indexOf(DebugGraphWidgets.idOf(label))!;
      expect(both.items[widgetNode].layer, 'widgets');
      expect(both.items[widgetNode].aliases, isNotEmpty);
      final coupon = both.items.indexWhere((i) => i.label == 'coupon');
      expect(
        both.links.any((l) => l.from == coupon && l.to == widgetNode),
        isTrue,
        reason: 'what it read, to the widget\'s node',
      );
      final details = {
        for (final d in DebugGraphDetails.linesOf(both, widgetNode))
          d.label: d.value,
      };
      expect(details['type'], 'CouponLabel');
      expect(details['beans'], '1', reason: 'one bean, listed under the line');
      expect(details['reads'], contains('coupon'));
      // The Watch in a plain widget joins the widget it is in.
      expect(labels, isNot(contains('Watch in _Tile')));
      expect(labels, contains('_Tile'));

      final alone = const DebugGraphAssembler().assemble([
        (unified, unified.collect(DebugGraphScope.all)),
      ], settings);
      expect(
        alone.items.map((i) => i.label),
        containsAll(['CouponLabel', 'Watch in _Tile']),
        reason: 'without the widgets layer shown, its own readers',
      );
      unified.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    test('a tick lights its node, fading in a second; the layer wakes the '
        'view; live only keeps what changed within its window', () async {
      final basket = app.getBean<Basket>();
      use(basket);
      var woken = 0;
      final stopWaking = layer.onActivity(() => woken++);
      addTearDown(stopWaking);
      DebugGraphNode coupon() => layer
          .collect(DebugGraphScope.all)
          .nodes
          .firstWhere((node) => node.label == 'coupon');
      clock.now = const Duration(seconds: 10);
      expect(layer.glowOf(coupon()), 0);
      basket.coupon = 'FIVE';
      app.getBean<SignalRuntime>().queues.primary.flush();
      await Future<void>.delayed(Duration.zero);
      expect(woken, greaterThan(0));
      expect(layer.glowOf(coupon()), 1);
      clock.now = const Duration(milliseconds: 10500);
      expect(layer.glowOf(coupon()), closeTo(0.5, 0.01));
      clock.now = const Duration(seconds: 11);
      expect(layer.glowOf(coupon()), 0);
      expect(layer.isLive(coupon(), const Duration(seconds: 5)), isTrue);
      clock.now = const Duration(seconds: 20);
      expect(layer.isLive(coupon(), const Duration(seconds: 5)), isFalse);
      basket.coupon = null;
      app.getBean<SignalRuntime>().queues.primary.flush();
    });

    test('collects only while started: the probe attached, a change of '
        'what reads what told', () async {
      stop();
      expect(SignalProbes.current, isNull);
      final again = layer.start();
      expect(SignalProbes.current, same(recorder));
      final second = layer.start();
      again();
      expect(SignalProbes.current, same(recorder), reason: 'one user left');
      second();
      expect(SignalProbes.current, isNull);
      stop = layer.start();
    });

    testWidgets('the Signals tab: Fields, Graph (the signals layer alone) '
        'and List', (tester) async {
      use(app.getBean<Basket>());
      final section = SignalsDebugSection(
        app.getBean<SignalBeans>(),
        recorder: recorder,
        graph: layer,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 800,
            height: 600,
            child: Builder(builder: section.build),
          ),
        ),
      );
      expect(find.text('Fields'), findsOneWidget);
      expect(find.text('Basket  ·  singleton'), findsOneWidget);
      expect(find.byType(DebugGraphView), findsNothing);
      await tester.tap(find.text('Graph'));
      await tester.pump();
      final view = tester.widget<DebugGraphView>(find.byType(DebugGraphView));
      expect(view.layers, [layer]);
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(
        tester
            .state<DebugGraphViewState>(find.byType(DebugGraphView))
            .graph!
            .lanes
            .map((lane) => lane.title),
        contains('Basket'),
      );
      await tester.tap(find.text('List'));
      await tester.pump();
      expect(find.byType(DebugGraphView), findsNothing);
      expect(find.textContaining('coupon'), findsWidgets);
      await tester.pumpWidget(const SizedBox());

      // Without the layer in the build: no Graph sub-tab.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 800,
            height: 600,
            child: Builder(
              builder: SignalsDebugSection(
                app.getBean<SignalBeans>(),
                recorder: recorder,
              ).build,
            ),
          ),
        ),
      );
      expect(find.text('Graph'), findsNothing);
      expect(find.text('List'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('the layer\'s module: by spring.flutter.debug.graph.layers (signals, '
      '* or not set), inside the graph\'s, the Signals tab\'s and the '
      'panel\'s switches; the `graph` pane inside the console\'s', () {
    final source = File(
      'lib/spring_auto_configuration.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(
      source,
      contains(
        "AutoConfigurationBuild.named('spring.flutter.debug.graph.layers',"
        "'signals',whenMissing:BuildInclusion.always,parents:["
        "AutoConfigurationBuild('spring.flutter.debug.graph.enabled'),"
        "AutoConfigurationBuild('spring.flutter.signals.debug.enabled'),"
        "AutoConfigurationBuild('spring.flutter.debug.enabled'),],),)"
        'finalBeanModulespringBootStarterFlutterSignalsDebugGraphAutoConfiguration',
      ),
    );
    expect(
      source,
      contains(
        "AutoConfigurationBuild.named('spring.flutter.debug.console.panes',"
        "'graph',whenMissing:BuildInclusion.never,parents:["
        "AutoConfigurationBuild('spring.flutter.debug.console.enabled',"
        'whenMissing:BuildInclusion.never,),'
        "AutoConfigurationBuild.named('spring.flutter.debug.graph.layers',"
        "'signals',whenMissing:BuildInclusion.always,),],),)"
        'finalBeanModulespringBootStarterFlutterSignalsDebugGraphPaneAutoConfiguration',
      ),
    );
    final generated = File(
      'example/spring_gen/example.spring.debug.dart',
    ).readAsStringSync();
    expect(
      generated,
      contains('springBootStarterFlutterSignalsDebugGraphAutoConfiguration'),
      reason: 'in a debug build by default',
    );
    expect(
      generated,
      isNot(
        contains(
          'springBootStarterFlutterSignalsDebugGraphPaneAutoConfiguration',
        ),
      ),
      reason: 'the example has no console',
    );
  });

  test('the beans: the layer, the Graph tab with the panel; the `graph` '
      'pane named graph, order 25', () {
    final tab = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterDebugAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterSignalsAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterFlutterSignalsDebugAutoConfiguration,
        )
        .withAutoConfiguration(
          springBootStarterFlutterSignalsDebugGraphAutoConfiguration,
        );
    tab.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<SignalsGraphLayer>());
      expect(context, hasSingleBean<DebugGraphSection>());
      final section = context.getBean<DebugGraphSection>();
      expect(section.title, 'Graph');
      expect(section.group, 'App');
      expect(section.layers.single, same(context.getBean<SignalsGraphLayer>()));
      expect(
        context.getBean<SignalsDebugSection>().graph,
        same(context.getBean<SignalsGraphLayer>()),
        reason: 'the Signals tab has its Graph sub-tab',
      );
      expect(SignalProbes.current, isNull, reason: 'nothing shows yet');
    });
    tab
        .withPropertyValues(['spring.flutter.debug.graph.enabled=false'])
        .run(
          (context) => expect(context, doesNotHaveBean<DebugGraphSection>()),
        );

    const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterSignalsAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterFlutterSignalsDebugGraphPaneAutoConfiguration,
        )
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context, hasSingleBean<DebugGraphPane>());
          expect(context, doesNotHaveBean<DebugGraphSection>());
          final pane = context.context.findAnnotationOnBean<ConsolePane>(
            'debugGraphPane',
          );
          expect(pane?.pane, 'graph');
          expect(pane?.value, 25);
          expect(context.getBean<DebugGraphPane>().layers, hasLength(1));
        });
  });

  test('two beans of one class, each with its effect: an effect node of '
      'its own each, with the edge from what that bean read', () {
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<Object>(
          name: 'draft',
          scope: ScopeType.prototype,
          annotatedMethods: [
            IntrospectedMethod<Object>(
              'watch',
              invoke: (bean, _) {
                (bean as _Draft).watch();
                return null;
              },
              isVoid: true,
              annotations: const [Effect()],
            ),
          ],
          create: (_) => _Draft(),
        ),
      );
    final beans = SignalBeans();
    addTearDown(beans.dispose);
    final effects = SignalEffects.of(
      beans,
      SignalRuntime(queues: SignalQueues(const SignalQueueSettings())),
    )..setBeanFactory(factory);
    final recorder = SignalsDebugRecorder();
    final layer = SignalsGraphLayer(beans, recorder);
    final stop = layer.start();
    addTearDown(() {
      stop();
      layer.dispose();
    });
    final first = _Draft();
    final second = _Draft();
    effects
      ..postProcessAfterInitialization(first, 'draft')
      ..postProcessAfterInitialization(second, 'draft');

    final part = layer.collect(DebugGraphScope.all);
    final byId = {for (final node in part.nodes) node.id: node};
    String name(String id) => '${byId[id]!.group}.${byId[id]!.label}';
    expect(
      [for (final edge in part.edges) '${name(edge.from)} → ${name(edge.to)}']
        ..sort(),
      ['Draft #1.text → Draft #1.watch()', 'Draft #2.text → Draft #2.watch()'],
    );
  });
}

// A bean on signals as the generator writes it, with a debug tool in the
// build: its effect reads its field.
final class _Draft implements SignalBeanHolder {
  @override
  final SignalBean signalBean = ProbedSignalBean('Draft');

  late final ValueMember _text = signalBean.field('text', () => '');

  void watch() => signalBean.effectBody('watch', () => _text.read());

  @override
  Map<String, SignalMember Function()> get signalMembers => {
    'text': () => _text,
  };

  @override
  List<String> get eagerSignals => const [];

  @override
  List<String> get signalQueues => const [];
}
