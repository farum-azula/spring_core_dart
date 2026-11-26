// A WidgetBuildTracker of the first interface is still attached through
// attach; a WidgetAwareBuildTracker is told the widget's element, by both
// kinds of Spring widgets.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner;

final class _Tracking implements WidgetBuildTracking {
  @override
  T track<T>(T Function() build) => build();

  @override
  void dispose() {}
}

/// A tracker written against the first interface: it only has attach.
final class _OldTracker implements WidgetBuildTracker {
  final List<String> calls = [];

  @override
  WidgetBuildTracking attach(VoidCallback rebuild) {
    calls.add('attach');
    return _Tracking();
  }
}

final class _AwareTracker implements WidgetAwareBuildTracker {
  final List<String> calls = [];

  @override
  WidgetBuildTracking attach(VoidCallback rebuild) {
    calls.add('attach');
    return _Tracking();
  }

  @override
  WidgetBuildTracking attachTo(VoidCallback rebuild, BuildContext context) {
    calls.add('attachTo ${context.widget.runtimeType}');
    return _Tracking();
  }
}

class _Label extends SpringStatelessWidget<()> {
  const _Label();

  @override
  Widget build(BuildContext context) =>
      const Text('label', textDirection: TextDirection.ltr);
}

class _Page extends SpringStatefulWidget<()> {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends SpringState<_Page, ()> {
  @override
  Widget build(BuildContext context) => const _Label();
}

Type _typeOf<T>() => T;

void main() {
  final old = _OldTracker();
  final aware = _AwareTracker();
  final runner = const ApplicationContextRunner()
      .withBean<WidgetBuildTracker>(() => old, name: 'oldTracker')
      .withBean<WidgetBuildTracker>(() => aware, name: 'awareTracker')
      // What the generator writes for the widgets above.
      .withBean<SpringWidgetBindings>(
        () => SpringWidgetBindings([
          SpringWidgetBinding(
            widget: '_Label',
            beans: _typeOf<()>(),
            types: const [],
            resolve: (_) => (),
          ),
        ]),
      );

  setUp(() {
    old.calls.clear();
    aware.calls.clear();
  });

  testWidgets('without an element both are attached through attach', (
    tester,
  ) async {
    runner.run((context) {
      final trackings = WidgetBuildTrackings(() {});
      expect(trackings.track(context.context, () => 1), 1);
      trackings.dispose();
    });
    expect(old.calls, ['attach']);
    expect(aware.calls, ['attach']);
  });

  testWidgets('the Spring widgets tell the aware one their element; the old '
      'one is attached as before', (tester) async {
    await runner.runAsync((context) async {
      await tester.pumpWidget(
        SpringScope(applicationContext: context.context, child: const _Page()),
      );
      expect(find.text('label'), findsOneWidget);
    });
    expect(old.calls, ['attach', 'attach']);
    expect(aware.calls, unorderedEquals(['attachTo _Page', 'attachTo _Label']));
  });
}
