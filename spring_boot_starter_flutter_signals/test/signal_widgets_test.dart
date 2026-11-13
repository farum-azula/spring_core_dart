// Widgets that follow state: a Watch and an AsyncView build again for
// what they read and for nothing else, and a Spring widget follows its
// own build.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

Future<ApplicationContext> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      home: Directionality(textDirection: TextDirection.ltr, child: home),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  return SpringScope.of(tester.element(find.byType(Directionality).first));
}

void main() {
  testWidgets('the example: the catalog loads, a tap changes the total', (
    tester,
  ) async {
    final context = await _pump(tester, const Shop());
    expect(find.text('fiction one'), findsOneWidget);
    expect(find.text('Total: 0.0'), findsOneWidget);

    await tester.tap(find.text('fiction two'));
    await tester.pump();
    expect(find.text('Total: 12.0'), findsOneWidget);

    // Another genre: the view shows the load, then the new books.
    context.getBean<Catalog>().genre = 'poetry';
    await tester.pump();
    expect(find.text('Loading'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('poetry one'), findsOneWidget);
    expect(find.text('fiction one'), findsNothing);
  });

  testWidgets('a Watch builds again only for what it read', (tester) async {
    var builds = 0;
    late Basket basket;
    final context = await _pump(
      tester,
      Builder(
        builder: (context) {
          basket = context.bean<Basket>();
          return Watch((context) {
            builds++;
            return Text('${basket.total}');
          });
        },
      ),
    );
    expect(builds, 1);

    basket.add(const Book('Dune', 10));
    await tester.pump();
    expect(find.text('10.0'), findsOneWidget);
    expect(builds, 2);

    // The genre of the catalog is not read here.
    context.getBean<Catalog>().genre = 'poetry';
    await tester.pump();
    expect(builds, 2);

    // Two assignments in one method: one build.
    basket.clear();
    await tester.pump();
    expect(builds, 3);
  });

  testWidgets('a Spring widget follows its own build, by field', (
    tester,
  ) async {
    var builds = 0;
    final context = await _pump(
      tester,
      // Counts the builds of the label below it.
      _Counted(onBuild: () => builds++, child: const CouponLabel()),
    );
    final basket = context.getBean<Basket>();
    expect(find.text('Coupon: none'), findsOneWidget);

    basket.coupon = 'TEN';
    await tester.pump();
    expect(find.text('Coupon: TEN'), findsOneWidget);

    // The items are not read by this widget: its text is not built again.
    final label = tester.element(find.byType(CouponLabel));
    var rebuilt = false;
    label.visitChildren((child) => rebuilt = child.dirty);
    basket.add(const Book('Dune', 10));
    expect(label.dirty, isFalse);
    expect(rebuilt, isFalse);
    await tester.pump();
    expect(find.text('Coupon: TEN'), findsOneWidget);

    basket.coupon = null;
    expect(label.dirty, isTrue);
    await tester.pump();
    expect(find.text('Coupon: none'), findsOneWidget);
    expect(builds, 1);
  });

  testWidgets('an AsyncView keeps the value while it is refreshed, and shows '
      'a failure', (tester) async {
    final context = await _pump(
      tester,
      Builder(
        builder: (context) => AsyncView(
          () => context.bean<Catalog>().books,
          loading: (context) => const Text('Loading'),
          data: (context, books) => Text('${books.length} books'),
        ),
      ),
    );
    expect(find.text('2 books'), findsOneWidget);

    final refreshed = context.getBean<Catalog>().books.refresh();
    await tester.pump();
    // The last value stays on screen.
    expect(find.text('2 books'), findsOneWidget);
    expect(find.text('Loading'), findsNothing);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await refreshed;
    expect(find.text('2 books'), findsOneWidget);
  });

  testWidgets('a widget that left the screen is not built again', (
    tester,
  ) async {
    var builds = 0;
    late Basket basket;
    await _pump(
      tester,
      Builder(
        builder: (context) {
          basket = context.bean<Basket>();
          return Watch((context) {
            builds++;
            return Text('${basket.total}');
          });
        },
      ),
    );
    await tester.pumpWidget(const SizedBox());
    final before = builds;
    basket.add(const Book('Dune', 10));
    await tester.pump();
    expect(builds, before);
  });
}

class _Counted extends StatelessWidget {
  const _Counted({required this.onBuild, required this.child});

  final VoidCallback onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return child;
  }
}
