import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class Basket extends ChangeNotifier {
  int count = 3;

  void add() {
    count++;
    notifyListeners();
  }

  bool get listened => hasListeners;
}

class Clock {
  Clock(this.name);
  final String name;
}

class Missing {}

/// Positional record.
class BasketBadge extends SpringStatelessWidget<(Basket, Clock)> {
  const BasketBadge({this.prefix = '', super.key});
  final String prefix;

  @override
  Widget build(BuildContext context, (Basket, Clock) beans) {
    final (basket, clock) = beans;
    return Text(
      '$prefix${basket.count} at ${clock.name}',
      textDirection: TextDirection.ltr,
    );
  }
}

/// Named record: the field name picks among several clocks.
class NamedBadge extends SpringStatelessWidget<({Clock utc})> {
  const NamedBadge({super.key});

  @override
  Widget build(BuildContext context, ({Clock utc}) beans) =>
      Text(beans.utc.name, textDirection: TextDirection.ltr);
}

/// A stateful widget whose State gets the beans.
class BasketPage extends SpringStatefulWidget<(Basket, Clock)> {
  const BasketPage({super.key});

  @override
  State<BasketPage> createState() => _BasketPageState();
}

class _BasketPageState extends SpringState<BasketPage, (Basket, Clock)> {
  late final int countAtStart;
  int taps = 0;

  @override
  void initState() {
    super.initState();
    final (basket, _) = beans; // available in initState
    countAtStart = basket.count;
  }

  @override
  Widget build(BuildContext context) {
    final (basket, clock) = beans;
    return GestureDetector(
      onTap: () => setState(() => taps++),
      child: Text(
        'start $countAtStart, now ${basket.count} at ${clock.name}, taps $taps',
        textDirection: TextDirection.ltr,
      ),
    );
  }
}

class Unbound extends SpringStatelessWidget<(Basket,)> {
  const Unbound({super.key});

  @override
  Widget build(BuildContext context, (Basket,) beans) => const SizedBox();
}

/// What the generator writes for the widgets above.
final bindings = BeanDefinition<SpringWidgetBindings>(
  name: 'flutterSpringWidgetBindings#test',
  types: const [SpringWidgetBindings],
  create: (_) => SpringWidgetBindings([
    SpringWidgetBinding(
      widget: 'BasketBadge',
      beans: _typeOf<(Basket, Clock)>(),
      types: const [Basket, Clock],
      resolve: (f) => (
        SpringWidgetBinding.bean<Basket>(f),
        SpringWidgetBinding.bean<Clock>(f),
      ),
      values: (r) {
        final (basket, clock) = r as (Basket, Clock);
        return [basket, clock];
      },
    ),
    // BasketPage's state shares the record type of BasketBadge: one binding.
    SpringWidgetBinding(
      widget: 'NamedBadge',
      beans: _typeOf<({Clock utc})>(),
      types: const [Clock],
      resolve: (f) => (utc: SpringWidgetBinding.bean<Clock>(f, 'utc')),
    ),
  ]),
);

Type _typeOf<T>() => T;

SpringApplication app({List<BeanDefinition<Object>> extra = const []}) =>
    SpringApplication([
      BeanModule('test', [
        BeanDefinition<Basket>(
          name: 'basket',
          types: const [Basket],
          create: (_) => Basket(),
        ),
        BeanDefinition<Clock>(
          name: 'local',
          types: const [Clock],
          primary: true,
          create: (_) => Clock('local'),
        ),
        bindings,
        ...extra,
      ]),
    ], bannerMode: BannerMode.off);

void main() {
  testWidgets('build gets the record of beans', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: app,
        child: const BasketBadge(prefix: 'Basket: '),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Basket: 3 at local'), findsOneWidget);
  });

  testWidgets('a named field picks among several beans by name', (
    tester,
  ) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => SpringApplication([
          BeanModule('test', [
            BeanDefinition<Clock>(
              name: 'local',
              types: const [Clock],
              create: (_) => Clock('local'),
            ),
            BeanDefinition<Clock>(
              name: 'utc',
              types: const [Clock],
              create: (_) => Clock('UTC'),
            ),
            BeanDefinition<Basket>(
              name: 'basket',
              types: const [Basket],
              create: (_) => Basket(),
            ),
            bindings,
          ]),
        ], bannerMode: BannerMode.off),
        child: const NamedBadge(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UTC'), findsOneWidget);
  });

  testWidgets('a widget without a generated binding explains the fix', (
    tester,
  ) async {
    await tester.pumpWidget(
      SpringApplicationWidget(application: app, child: const Unbound()),
    );
    await tester.pumpAndSettle();
    final error = tester.takeException();
    expect('$error', contains('No generated beans for Unbound'));
    expect('$error', contains('build_runner'));
  });

  testWidgets('a missing bean fails the start', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => app(
          extra: [
            BeanDefinition<SpringWidgetBindings>(
              name: 'flutterSpringWidgetBindings#other',
              types: const [SpringWidgetBindings],
              create: (_) => SpringWidgetBindings([
                SpringWidgetBinding(
                  widget: 'package:app/x.dart#NeedsMissing',
                  beans: _typeOf<(Missing,)>(),
                  types: const [Missing],
                  resolve: (f) => (f.getBean<Missing>(),),
                ),
              ]),
            ),
          ],
        ),
        failure: (_, error) => Text('$error', textDirection: TextDirection.ltr),
        child: const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Missing'), findsOneWidget);
    expect(find.textContaining('NeedsMissing'), findsOneWidget);
  });

  group('Listenable beans', () {
    testWidgets('a SpringStatelessWidget rebuilds when one notifies', (
      tester,
    ) async {
      await tester.pumpWidget(
        SpringApplicationWidget(application: app, child: const BasketBadge()),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 at local'), findsOneWidget);
      SpringScope.of(tester.element(find.byType(BasketBadge)))
          .getBean<Basket>()
          .add();
      await tester.pump();
      expect(find.text('4 at local'), findsOneWidget);
    });

    testWidgets('a SpringState rebuilds when one notifies', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(application: app, child: const BasketPage()),
      );
      await tester.pumpAndSettle();
      SpringScope.of(tester.element(find.byType(BasketPage)))
          .getBean<Basket>()
          .add();
      await tester.pump();
      expect(find.text('start 3, now 4 at local, taps 0'), findsOneWidget);
    });

    testWidgets('removed widgets stop listening', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(application: app, child: const BasketBadge()),
      );
      await tester.pumpAndSettle();
      final basket = SpringScope.of(tester.element(find.byType(BasketBadge)))
          .getBean<Basket>();
      expect(basket.listened, isTrue);
      await tester.pumpWidget(
        SpringApplicationWidget(application: app, child: const SizedBox()),
      );
      await tester.pumpAndSettle();
      // The old context was replaced (another widget tree); the basket of
      // the first one has no listeners left.
      expect(basket.listened, isFalse);
    });
  });

  group('SpringState', () {
    testWidgets('beans from initState on, kept with the state', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(application: app, child: const BasketPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('start 3, now 3 at local, taps 0'), findsOneWidget);
      final context = SpringScope.of(tester.element(find.byType(BasketPage)));
      context.getBean<Basket>().count = 5;
      await tester.tap(find.byType(BasketPage));
      await tester.pump();
      expect(find.text('start 3, now 5 at local, taps 1'), findsOneWidget);
    });

    testWidgets('another application context gives other beans', (
      tester,
    ) async {
      final first = await app().runAsync(const []);
      final second = await app().runAsync(const []);
      second.getBean<Basket>().count = 9;
      addTearDown(first.close);
      addTearDown(second.close);
      await tester.pumpWidget(
        SpringScope(applicationContext: first, child: const BasketPage()),
      );
      expect(find.textContaining('now 3'), findsOneWidget);
      await tester.pumpWidget(
        SpringScope(applicationContext: second, child: const BasketPage()),
      );
      // The same State (countAtStart stays), the beans of the new context.
      expect(find.text('start 3, now 9 at local, taps 0'), findsOneWidget);
    });
  });

  testWidgets('build can be called with fakes directly', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) => const BasketBadge().build(context, (
          Basket()..count = 7,
          Clock('fake'),
        )),
      ),
    );
    expect(find.text('7 at fake'), findsOneWidget);
  });
}
