import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_route.dart';

final _navigator = GlobalKey<NavigatorState>();

PageRouteBuilder<void> _page(String name) => PageRouteBuilder<void>(
  settings: RouteSettings(name: name),
  transitionDuration: const Duration(milliseconds: 200),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) => _Probe(name),
);

final _routes = <String, ModalRoute<Object?>?>{};

class _Probe extends StatelessWidget {
  const _Probe(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    _routes[name] = ModalRoute.of(context);
    return const SizedBox.expand();
  }
}

Future<void> _app(WidgetTester tester) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Navigator(
      key: _navigator,
      onGenerateInitialRoutes: (_, _) => [_page('profile')],
    ),
  ),
);

void main() {
  setUp(_routes.clear);

  testWidgets('a route on top is not leaving', (tester) async {
    await _app(tester);

    expect(sceneRouteLeaving(_routes['profile']), isFalse);
    expect(sceneRouteLeaving(null), isFalse);
  });

  testWidgets('a page pushed over it: leaving from the first frame of the '
      'transition, and while covered', (tester) async {
    await _app(tester);
    final profile = _routes['profile'];

    _navigator.currentState!.push(_page('matches'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sceneRouteLeaving(profile), isTrue);

    await tester.pumpAndSettle();
    expect(sceneRouteLeaving(profile), isTrue);
    expect(sceneRouteLeaving(_routes['matches']), isFalse);
  });

  testWidgets('back on top once the page over it is popped', (tester) async {
    await _app(tester);
    final profile = _routes['profile'];
    _navigator.currentState!.push(_page('matches'));
    await tester.pumpAndSettle();
    final matches = _routes['matches'];

    _navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sceneRouteLeaving(matches), isTrue, reason: 'popped: leaving');

    await tester.pumpAndSettle();
    expect(sceneRouteLeaving(profile), isFalse);
  });

  testWidgets('a dialog over it does not hide it', (
    tester,
  ) async {
    await _app(tester);
    final profile = _routes['profile'];

    _navigator.currentState!.push(
      RawDialogRoute<void>(
        pageBuilder: (context, _, _) => const _Probe('dialog'),
      ),
    );
    await tester.pumpAndSettle();

    expect(sceneRouteLeaving(profile), isFalse);
  });
}
