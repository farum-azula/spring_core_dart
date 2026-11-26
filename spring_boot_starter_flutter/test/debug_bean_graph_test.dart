// The data of the application graph's beans layer (`debugBeanGraph`): only
// the beans the application defined by default, the framework's behind a
// toggle; grouped by module; the edges "depends on" with lazy points and
// providers marked; roles, scopes, advice, conditions and the creation
// trace; the beans a widget injects and their closure; a route's beans
// coming and going while the graph runs, and no post-processor at all
// while it does not.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support/bean_graph_shop.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  late Shop shop;

  setUp(() => shop = startShop());

  tearDown(() {
    shop.graph.dispose();
    shop.context.close();
  });

  test('by default only the beans the application defined, widgets too', () {
    final snapshot = shop.graph.snapshot;
    expect(snapshot.includesFramework, isFalse);
    expect(
      [for (final bean in snapshot.beans) bean.name],
      unorderedEquals([
        'advising',
        'shopConfig',
        'basket',
        'store',
        'clock',
        'audit',
        'ordersController',
        'screenState',
        'shopWidgetBindings',
        basketBadge,
      ]),
    );
    expect(snapshot.beans.every((bean) => bean.application), isTrue);
    expect(snapshot.edges.map((edge) => edge.from), isNot(contains('metrics')));
  });

  test(
    'the framework toggle adds the auto-configurations and the context',
    () async {
      var notified = 0;
      shop.graph
        ..addListener(() => notified++)
        ..includeFramework = true;
      await settle();
      expect(notified, 1);
      final snapshot = shop.graph.snapshot;
      expect(snapshot.includesFramework, isTrue);
      final metrics = snapshot.bean('metrics')!;
      expect(metrics.application, isFalse);
      expect(metrics.module, 'shopAutoConfiguration');
      expect(metrics.role, DebugBeanRole.infrastructure);
      final arguments = snapshot.bean('springApplicationArguments')!;
      expect(arguments.module, 'registered');
      expect(arguments.created, isTrue);
      expect(
        snapshot.skipped.map((skipped) => skipped.source),
        containsAll(['devTools', 'metricsExporter']),
      );
    },
  );

  test('beans are grouped by module: the folder of the application', () {
    final modules = {
      for (final module in shop.graph.snapshot.modules)
        module.name: module.beans,
    };
    expect(modules['shop/basket'], ['basket', 'screenState', basketBadge]);
    expect(modules['shop/store'], ['store']);
    expect(
      modules['shop'],
      unorderedEquals([
        'advising',
        'shopConfig',
        'clock',
        'shopWidgetBindings',
      ]),
    );
    expect(modules['shop/audit'], ['audit']);
    shop.graph.includeFramework = true;
    final all = {
      for (final module in shop.graph.snapshot.modules) module.name: module,
    };
    expect(all['shopAutoConfiguration']!.application, isFalse);
    expect(
      all['shopAutoConfiguration']!.beans,
      unorderedEquals(['metrics', 'notifyListenersAdvisor']),
    );
    expect(all['shop/basket']!.application, isTrue);
  });

  test('roles from the stereotypes and the @Bean methods', () {
    final snapshot = shop.graph.snapshot;
    DebugBeanRole roleOf(String name) => snapshot.bean(name)!.role;
    expect(roleOf('basket'), DebugBeanRole.service);
    expect(roleOf('store'), DebugBeanRole.repository);
    expect(roleOf('shopConfig'), DebugBeanRole.configuration);
    expect(roleOf('clock'), DebugBeanRole.factoryMethod);
    expect(roleOf('ordersController'), DebugBeanRole.controller);
    expect(roleOf('audit'), DebugBeanRole.component);
    expect(roleOf('screenState'), DebugBeanRole.component);
    expect(roleOf(basketBadge), DebugBeanRole.widget);
  });

  test('a rule before the defaults gives a stereotype of its own', () {
    final graph = DebugBeanGraph(
      shop.context,
      roles: const DebugBeanRoles([
        DebugBeanAnnotationRole<Repository>(DebugBeanRole.service),
        ...DebugBeanRoles.defaults,
      ]),
    )..useApplication(shop.application);
    addTearDown(graph.dispose);
    expect(graph.snapshot.bean('store')!.role, DebugBeanRole.service);
  });

  test('edges: direct, lazy and provider points marked, the event '
      'publisher no bean', () {
    final edges = {
      for (final edge in shop.graph.snapshot.dependenciesOf('basket'))
        edge.to: edge,
    };
    expect(edges.keys, unorderedEquals(['store', 'clock', 'audit']));
    expect(edges['store']!.kind, DebugBeanEdgeKind.direct);
    expect(edges['store']!.declared, isTrue);
    expect(edges['store']!.observed, isTrue, reason: 'injected at creation');
    expect(edges['clock']!.kind, DebugBeanEdgeKind.lazy);
    expect(edges['clock']!.deferred, isTrue);
    expect(edges['clock']!.observed, isFalse, reason: 'never used');
    expect(edges['audit']!.kind, DebugBeanEdgeKind.provider);
    expect(edges['audit']!.deferred, isTrue);
    expect(
      shop.graph.snapshot.dependentsOf('store').map((edge) => edge.from),
      contains('basket'),
    );
  });

  test('an edge only the code of a hand-written definition knows of is '
      'observed, not declared', () {
    shop.graph.includeFramework = true;
    final edge = shop.graph.snapshot
        .dependenciesOf('metrics')
        .singleWhere((edge) => edge.to == 'store');
    expect(edge.declared, isFalse);
    expect(edge.observed, isTrue);
    expect(edge.kind, DebugBeanEdgeKind.direct);
  });

  test('a widget injects its record, and the closure follows the edges', () {
    final snapshot = shop.graph.snapshot;
    final widget = snapshot.widgetOf(typeOf<(Basket,)>())!;
    expect(widget.name, basketBadge);
    expect(widget.type, 'BasketBadge');
    expect(widget.scope, 'widget');
    expect(snapshot.dependenciesOf(basketBadge).single.to, 'basket');
    expect(
      snapshot.dependenciesOf(basketBadge).single.kind,
      DebugBeanEdgeKind.widget,
    );
    expect(
      snapshot.closureOf([widget.name]),
      {basketBadge, 'basket', 'store', 'clock', 'audit'},
    );
    expect(
      snapshot.closureOf(
        [widget.name],
        kinds: const {
          DebugBeanEdgeKind.widget,
          DebugBeanEdgeKind.direct,
          DebugBeanEdgeKind.collection,
        },
      ),
      {basketBadge, 'basket', 'store'},
    );
  });

  test('scopes, lazy beans not created yet, creation order and time', () {
    final snapshot = shop.graph.snapshot;
    final basket = snapshot.bean('basket')!;
    final store = snapshot.bean('store')!;
    final clock = snapshot.bean('clock')!;
    expect(basket.scope, ScopeType.singleton);
    expect(basket.created, isTrue);
    expect(clock.lazy, isTrue);
    expect(clock.pending, isTrue);
    expect(clock.creationOrder, isNull);
    expect(snapshot.bean('screenState')!.scope, 'route');
    expect(snapshot.bean('screenState')!.created, isFalse);
    expect(store.creationOrder, lessThan(basket.creationOrder!));
    expect(basket.createdAt, isNotNull);
    expect(basket.creationTime, isNotNull);
  });

  test('advice: the advisors of the created proxy and the annotated '
      'members of the generated one', () {
    final basket = shop.graph.snapshot.bean('basket')!;
    expect(basket.advisors, ['notifyListenersAdvisor']);
    expect(basket.advisedMethods, hasLength(1));
    expect(basket.advisedMethods.single.name, 'checkout');
    expect(
      basket.advisedMethods.single.annotations,
      ['Transactional', 'PreAuthorize'],
    );
    expect(basket.annotations, ['Service']);
    expect(shop.graph.snapshot.bean('store')!.advisors, isEmpty);
  });

  test('conditions: those a bean was registered under, and why a bean is '
      'missing', () {
    final snapshot = shop.graph.snapshot;
    final store = snapshot.bean('store')!;
    expect(store.conditions, hasLength(1));
    expect(store.conditions.single.matched, isTrue);
    expect(store.conditions.single.condition, contains('shop.store.enabled'));
    final devTools = snapshot.skipped.single;
    expect(devTools.source, 'devTools');
    expect(devTools.application, isTrue);
    expect(devTools.module, 'shop/dev');
    expect(devTools.failed.single.condition, contains('dev'));
    expect(snapshot.bean('devTools'), isNull);
  });

  test('events: who listens, who publishes', () {
    final snapshot = shop.graph.snapshot;
    expect(snapshot.bean('audit')!.eventListeners, ['Audit.onReady']);
    expect(snapshot.bean('basket')!.publishesEvents, isTrue);
    expect(snapshot.bean('store')!.publishesEvents, isFalse);
  });

  test('a route bean comes and goes while the graph runs', () async {
    final graph = shop.graph;
    var notified = 0;
    graph
      ..addListener(() => notified++)
      ..start();
    await settle();
    notified = 0;
    shop.context.getBean<ScreenState>();
    shop.context.getBean<Clock>();
    expect(notified, 0, reason: 'heard after the container is done');
    await settle();
    expect(notified, 1, reason: 'once for the burst');
    expect(
      [for (final event in graph.events) (event.kind, event.beanName)],
      [
        (DebugBeanEventKind.created, 'screenState'),
        (DebugBeanEventKind.created, 'clock'),
      ],
    );
    expect(graph.snapshot.bean('screenState')!.instances, 1);
    expect(graph.snapshot.bean('clock')!.created, isTrue);
    final seen = graph.events.last.sequence;
    shop.scope.destroy();
    await settle();
    expect(notified, 2);
    final after = graph.eventsAfter(seen);
    expect(after.single.kind, DebugBeanEventKind.destroyed);
    expect(after.single.beanName, 'screenState');
    expect(graph.snapshot.bean('screenState')!.created, isFalse);
  });

  test('no recorder while the graph is not running: nothing in the '
      'container', () async {
    final graph = shop.graph;
    bool installed() => shop.factory.beanPostProcessors
        .whereType<DebugBeanLifecycleRecorder>()
        .isNotEmpty;
    expect(graph.recorder, isNull);
    expect(installed(), isFalse);
    shop.context.getBean<ScreenState>();
    shop.scope.destroy();
    expect(graph.events, isEmpty);
    graph.start();
    expect(graph.recorder, isNotNull);
    expect(installed(), isTrue);
    graph.stop();
    expect(graph.recorder, isNull);
    expect(installed(), isFalse);
    shop.context.getBean<ScreenState>();
    expect(graph.events, isEmpty);
  });

  test('without the application known, every bean is the framework\'s', () {
    final graph = DebugBeanGraph(shop.context);
    addTearDown(graph.dispose);
    expect(graph.snapshot.beans, isEmpty);
    graph.includeFramework = true;
    final basket = graph.snapshot.bean('basket')!;
    expect(basket.application, isFalse);
    expect(basket.module, 'shop');
  });

  group('the auto-configuration', () {
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
          home: const _Home(),
        ),
      );
      await tester.pumpAndSettle();
      return SpringScope.of(tester.element(find.byType(_Home)));
    }

    testWidgets('with the panel: the graph knows the application by its '
        'start, and records nothing until started', (tester) async {
      final context = await run(tester, [
        springBootStarterFlutterDebugAutoConfiguration,
        springBootStarterFlutterDebugBeansGraphAutoConfiguration,
      ]);
      final graph = context.getBean<DebugBeanGraph>();
      expect(graph.recorder, isNull);
      expect([for (final bean in graph.snapshot.beans) bean.name], ['store']);
      expect(graph.snapshot.bean('store')!.module, 'shop/store');
    });

    testWidgets('the widgets layer, the debug themes and the dock leave '
        'with their view or feature turned off in a running app', (
      tester,
    ) async {
      final on = await run(tester, [
        springBootStarterFlutterDebugAutoConfiguration,
        springBootStarterFlutterDebugWidgetsGraphAutoConfiguration,
        springBootStarterFlutterDebugFrameMeterAutoConfiguration,
      ]);
      expect(on.getBeanNamesForType(WidgetsGraphLayer), isNotEmpty);
      expect(on.getBeanNamesForType(DebugThemes), isNotEmpty);
      expect(on.getBeanNamesForType(DebugDockCustomizer), isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      final off = await run(
        tester,
        [
          springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugWidgetsGraphAutoConfiguration,
          springBootStarterFlutterDebugFrameMeterAutoConfiguration,
        ],
        'spring.flutter.debug.enabled=false\n'
        'spring.flutter.debug.frame-meter.enabled=false',
      );
      expect(off.getBeanNamesForType(WidgetsGraphLayer), isEmpty);
      expect(off.getBeanNamesForType(DebugThemes), isEmpty);
      expect(off.getBeanNamesForType(DebugThemeCustomizer), isEmpty);
      expect(off.getBeanNamesForType(DebugDockCustomizer), isEmpty);
      await tester.pumpWidget(const SizedBox());
      final noTab = await run(
        tester,
        [
          springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugWidgetsGraphAutoConfiguration,
        ],
        'spring.flutter.debug.graph.enabled=false',
      );
      expect(noTab.getBeanNamesForType(WidgetsGraphLayer), isEmpty);
    });

    testWidgets('without the panel or the console there is none', (
      tester,
    ) async {
      final context = await run(tester, [
        springBootStarterFlutterDebugBeansGraphAutoConfiguration,
      ]);
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
      expect(context.getBeanNamesForType(DebugBeanGraph), isEmpty);
    });
  });
}
