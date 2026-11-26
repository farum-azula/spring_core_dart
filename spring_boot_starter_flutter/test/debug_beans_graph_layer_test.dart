// The beans layer of the application graph (`beansGraphLayer`): the
// application's beans by default, a lane per module, a shape per role, the
// framework and the beans left out behind the layer's chips; solid and
// dashed edges from a bean to the beans that inject it; what a tapped bean
// tells; a flash when a route's bean is created and destroyed; "On
// screen" as the beans the Spring widgets on the screen inject and their
// closure; and the layer only in the builds and apps that have it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support/bean_graph_shop.dart';

const _all = DebugGraphSettings(scope: DebugGraphScope.all);

Map<String, DebugGraphNode> _nodes(DebugGraphPart part) => {
  for (final node in part.nodes) node.id: node,
};

DebugGraphEdge _edge(DebugGraphPart part, String from, String to) =>
    part.edges.singleWhere(
      (edge) =>
          edge.from == BeansGraphLayer.idOf(from) &&
          edge.to == BeansGraphLayer.idOf(to),
    );

Map<String, String> _details(
  BeansGraphLayer layer,
  DebugGraphPart part,
  String name,
) => {
  for (final detail in layer.detailsOf(
    _nodes(part)[BeansGraphLayer.idOf(name)]!,
  ))
    detail.label: detail.value,
};

class _StoreBadge extends SpringStatelessWidget<(Store,)> {
  const _StoreBadge();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20);
}

void main() {
  late Shop shop;
  late BeansGraphLayer layer;

  setUp(() {
    shop = startShop();
    layer = BeansGraphLayer(
      shop.graph,
      springWidgets: () => const [],
      shows: (_) => true,
    );
  });

  tearDown(() {
    layer.dispose();
    shop.graph.dispose();
    shop.context.close();
  });

  test('by default the application\'s beans, each module a lane, each role '
      'a shape of its own', () {
    final nodes = _nodes(layer.collect(DebugGraphScope.all));
    expect(
      nodes.keys,
      unorderedEquals([
        for (final name in [
          'advising',
          'shopConfig',
          'basket',
          'store',
          'clock',
          'audit',
          'ordersController',
          'screenState',
          'shopWidgetBindings',
        ])
          'beans:$name',
      ]),
      reason: 'no widget node: the widgets layer has them',
    );
    expect(nodes['beans:basket']!.group, 'shop/basket');
    expect(nodes['beans:store']!.group, 'shop/store');
    expect(nodes['beans:clock']!.group, 'shop');
    expect(nodes['beans:basket']!.kind, 'service');
    expect(nodes['beans:store']!.kind, 'repository');
    expect(nodes['beans:clock']!.kind, 'factoryMethod');
    expect(nodes['beans:shopConfig']!.kind, 'configuration');
    expect(nodes['beans:ordersController']!.kind, 'controller');
    expect(nodes['beans:audit']!.kind, 'component');
    final shapes = {for (final kind in layer.kinds) kind.id: kind.shape};
    expect(
      {
        for (final role in DebugBeanRole.values)
          if (role != DebugBeanRole.widget)
            shapes[BeansGraphLayer.kindOf(role).id],
      },
      hasLength(7),
      reason: 'a shape per role',
    );
  });

  test('the framework chip adds the auto-configurations\' beans; the '
      'skipped chip the beans left out, grey', () {
    final options = {for (final option in layer.options) option.label: option};
    expect(options['framework']!.value, isFalse);
    options['framework']!.onChanged(true);
    final framework = _nodes(layer.collect(DebugGraphScope.all));
    expect(framework['beans:metrics']!.group, 'shopAutoConfiguration');
    expect(framework['beans:metrics']!.kind, 'infrastructure');
    expect(framework.keys.where((id) => id.contains('skipped:')), isEmpty);
    layer.options.singleWhere((o) => o.label == 'skipped').onChanged(true);
    final all = _nodes(layer.collect(DebugGraphScope.all));
    final devTools = all[BeansGraphLayer.skippedIdOf('devTools')]!;
    expect(devTools.dimmed, isTrue);
    expect(devTools.group, 'shop/dev');
    expect(all[BeansGraphLayer.skippedIdOf('metricsExporter')]!.dimmed, isTrue);
    expect(
      layer.detailsOf(devTools).first.value,
      contains('@Profile (dev)'),
    );
  });

  test('an edge from a bean to the bean that injects it: solid, dashed '
      'for a lazy point, a provider and @DependsOn', () {
    final part = layer.collect(DebugGraphScope.all);
    final store = _edge(part, 'store', 'basket');
    expect(store.dashed, isFalse);
    expect(store.kind, 'injects');
    final clock = _edge(part, 'clock', 'basket');
    expect(clock.dashed, isTrue);
    expect(clock.kind, 'injects @Lazy');
    final audit = _edge(part, 'audit', 'basket');
    expect(audit.dashed, isTrue);
    expect(audit.kind, 'injects a provider');
    final dependsOn = _edge(part, 'audit', 'ordersController');
    expect(dependsOn.dashed, isTrue);
    expect(dependsOn.kind, '@DependsOn');
  });

  test('a tapped bean tells its type, role, module, scope, state, advice, '
      'conditions, creation and ties', () {
    final part = layer.collect(DebugGraphScope.all);
    final basket = _details(layer, part, 'basket');
    expect(basket['type'], 'ShopBasket');
    expect(basket['role'], 'service');
    expect(basket['module'], 'shop/basket');
    expect(basket['scope'], 'singleton');
    expect(basket['state'], 'created');
    expect(basket['advice'], 'notifyListenersAdvisor');
    expect(basket['advised'], 'checkout @Transactional @PreAuthorize');
    expect(basket['depends on'], '3 (2 deferred)');
    expect(basket['used by'], '1 beans · 1 widgets');
    expect(basket['created'], startsWith('#'));
    expect(basket['created'], contains('took'));
    expect(basket['publishes'], 'events');
    expect(_details(layer, part, 'clock')['state'], 'not created yet (lazy)');
    expect(_details(layer, part, 'clock')['scope'], 'singleton · lazy');
    expect(_details(layer, part, 'screenState')['state'], '0 live');
    expect(
      _details(layer, part, 'store')['conditions'],
      contains('shop.store.enabled'),
    );
    expect(_details(layer, part, 'audit')['listens'], 'Audit.onReady');
  });

  test('a route bean flashes when created and when destroyed, only while '
      'a view shows the layer', () async {
    var wakes = 0;
    final stopWaking = layer.onActivity(() => wakes++);
    addTearDown(stopWaking);
    final stop = layer.start();
    expect(shop.graph.running, isTrue);
    final node = _nodes(
      layer.collect(DebugGraphScope.all),
    )[BeansGraphLayer.idOf('screenState')]!;
    expect(layer.glowOf(node), 0);
    shop.context.getBean<ScreenState>();
    await settle();
    expect(wakes, 1);
    expect(layer.glowOf(node), greaterThan(0.5));
    expect(layer.isLive(node, const Duration(seconds: 5)), isTrue);
    expect(
      _details(
        layer,
        layer.collect(DebugGraphScope.all),
        'screenState',
      )['state'],
      '1 live',
    );
    shop.scope.destroy();
    await settle();
    expect(wakes, 2);
    expect(
      _details(
        layer,
        layer.collect(DebugGraphScope.all),
        'screenState',
      )['state'],
      '0 live',
    );
    stop();
    expect(shop.graph.running, isFalse);
    expect(shop.graph.recorder, isNull);
    shop.context.getBean<ScreenState>();
    await settle();
    expect(wakes, 2, reason: 'nothing followed once stopped');
  });

  testWidgets('On screen: the beans the Spring widgets on the screen inject '
      'and their closure, tied to the widgets\' nodes', (tester) async {
    await tester.pumpWidget(
      const Row(
        textDirection: TextDirection.ltr,
        children: [
          SizedBox(key: Key('shown')),
          SizedBox(key: Key('hidden')),
        ],
      ),
    );
    final shown = tester.element(find.byKey(const Key('shown')));
    final hidden = tester.element(find.byKey(const Key('hidden')));
    final onScreen = BeansGraphLayer(
      shop.graph,
      springWidgets: () => [
        (element: shown, beansType: typeOf<(Basket,)>()),
        (element: hidden, beansType: typeOf<(Basket,)>()),
      ],
      shows: (widget) => identical(widget, shown),
    );
    addTearDown(onScreen.dispose);
    final part = onScreen.collect(DebugGraphScope.onScreen);
    final nodes = _nodes(part);
    expect(
      nodes.keys,
      unorderedEquals([
        'beans:basket',
        'beans:store',
        'beans:clock',
        'beans:audit',
      ]),
    );
    expect(nodes['beans:basket']!.widget, same(shown));
    expect(nodes['beans:basket']!.onScreen, isTrue);
    final assembled = const DebugGraphAssembler().assemble([
      (onScreen, part),
    ], const DebugGraphSettings());
    expect(
      assembled.items.map((item) => item.key),
      containsAll([
        'beans:basket',
        'beans:store',
        'beans:clock',
        'beans:audit',
      ]),
      reason: 'the engine keeps them without the widgets layer',
    );
    expect(nodes['beans:store']!.widget, isNull);
    expect(
      part.edges
          .where((edge) => edge.to.startsWith('widget:'))
          .map((e) => (e.from, e.to)),
      [('beans:basket', DebugGraphWidgets.idOf(shown))],
    );
    final none = BeansGraphLayer(
      shop.graph,
      springWidgets: () => [(element: hidden, beansType: typeOf<(Basket,)>())],
      shows: (_) => false,
    );
    addTearDown(none.dispose);
    expect(none.collect(DebugGraphScope.onScreen).nodes, isEmpty);
    expect(
      none.collect(DebugGraphScope.all).nodes,
      hasLength(9),
      reason: 'All shows every bean',
    );
  });

  testWidgets('the layer\'s chips in the view: framework adds beans', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 900,
            height: 600,
            child: DebugGraphView(layers: [layer], settings: _all),
          ),
        ),
      ),
    );
    await tester.pump();
    final view = tester.state<DebugGraphViewState>(find.byType(DebugGraphView));
    bool shows(String name) =>
        view.graph!.items.any((item) => item.key.contains(name));
    expect(shows('beans:basket'), isTrue);
    expect(shows('beans:metrics'), isFalse);
    await tester.tap(find.text('Options'));
    await tester.pump();
    await tester.tap(find.text('framework'));
    await tester.pump();
    expect(shop.graph.includeFramework, isTrue);
    expect(shows('beans:metrics'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  group('in an app', () {
    Future<ApplicationContext> run(
      WidgetTester tester,
      List<BeanModule> debug, [
      String properties = '',
    ]) async {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => SpringApplication(
            [
              BeanModule(
                'test',
                [
                  BeanDefinition<Store>(
                    name: 'store',
                    source: 'package:shop/src/store/store.dart#Store',
                    create: (_) => Store(),
                  ),
                  BeanDefinition<SpringWidgetBindings>(
                    name: 'testWidgetBindings',
                    source: 'package:shop/main.dart#widgetBindings',
                    create: (_) => SpringWidgetBindings([
                      SpringWidgetBinding(
                        widget: 'package:shop/src/store/store_badge.dart#StoreBadge',
                        beans: typeOf<(Store,)>(),
                        types: const [Store],
                        resolve: (factory) => (factory.getBean<Store>(),),
                      ),
                    ]),
                  ),
                ],
                resources: {
                  'application.properties': EmbeddedResource.text(
                    'spring.flutter.app.type=widgets\n$properties',
                  ),
                },
              ),
            ],
            autoConfigurations: [
              springBootStarterFlutterAutoConfiguration,
              ...debug,
              springBootStarterLoggingAutoConfiguration,
            ],
            bannerMode: BannerMode.off,
          ),
          home: const Center(child: _StoreBadge()),
        ),
      );
      await tester.pumpAndSettle();
      return SpringScope.of(tester.element(find.byType(_StoreBadge)));
    }

    testWidgets('with the panel: the layer and the Graph tab; On screen '
        'finds the Spring widget on the screen', (tester) async {
      final context = await run(tester, [
        springBootStarterFlutterDebugAutoConfiguration,
        springBootStarterFlutterDebugBeansGraphAutoConfiguration,
      ]);
      final layer = context.getBean<BeansGraphLayer>();
      expect(context.getBean<DebugGraphSection>().layers, contains(layer));
      final part = layer.collect(DebugGraphScope.onScreen);
      final store = _nodes(part)[BeansGraphLayer.idOf('store')]!;
      expect(store.widget, same(tester.element(find.byType(_StoreBadge))));
      // The app's graph groups by route: a singleton is in `App`.
      expect(store.group, DebugGraphRoute.app.key);
    });

    testWidgets('without the panel or the console there is none', (
      tester,
    ) async {
      final context = await run(tester, [
        springBootStarterFlutterDebugBeansGraphAutoConfiguration,
      ]);
      expect(context.getBeanNamesForType(BeansGraphLayer), isEmpty);
      expect(context.getBeanNamesForType(DebugBeanGraph), isEmpty);
    });

    testWidgets('off with the Graph tab in a running app, not by a switch '
        'of its own', (tester) async {
      final kept = await run(
        tester,
        [
          springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugBeansGraphAutoConfiguration,
        ],
        'spring.flutter.debug.graph.beans.enabled=false',
      );
      expect(kept.getBeanNamesForType(DebugBeanGraph), isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      final context = await run(
        tester,
        [
          springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugBeansGraphAutoConfiguration,
        ],
        'spring.flutter.debug.graph.enabled=false',
      );
      expect(context.getBeanNamesForType(BeansGraphLayer), isEmpty);
      expect(context.getBeanNamesForType(DebugBeanGraph), isEmpty);
    });
  });
}
