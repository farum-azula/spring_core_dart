// spring.flutter.theme.remember: the theme chosen is kept by the
// ThemeChoiceStore bean and shown again on the next run, before the app
// shows; off, nothing is kept or restored.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Memory implements ThemeChoiceStore {
  String? kept;

  @override
  Future<String?> read() async => kept;

  @override
  Future<void> write(String choice) async => kept = choice;
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<ThemeSelection> _start(
  WidgetTester tester,
  _Memory store, [
  String properties = '',
]) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              BeanDefinition<ThemeChoiceStore>(
                name: 'memory',
                types: const [ThemeChoiceStore],
                create: (_) => store,
              ),
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.theme.active=light\n$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
        bannerMode: BannerMode.off,
      ),
      home: const _Home(),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
  return SpringScope.of(
    tester.element(find.byType(_Home)),
  ).getBean<ThemeSelection>();
}

void main() {
  testWidgets('chosen, kept, shown again on the next run', (tester) async {
    final store = _Memory();
    final first = await _start(tester, store);
    expect(first.active, 'light');
    first.select('dark');
    await tester.pump();
    expect(store.kept, 'dark');

    final second = await _start(tester, store);
    expect(second.active, 'dark');
  });

  testWidgets('remember=false: nothing kept, nothing restored', (
    tester,
  ) async {
    final store = _Memory()..kept = 'dark';
    final selection = await _start(
      tester,
      store,
      'spring.flutter.theme.remember=false',
    );
    expect(selection.active, 'light');
    selection.select('system');
    await tester.pump();
    expect(store.kept, 'dark');
  });

  testWidgets('a kept theme that is gone is ignored', (tester) async {
    final store = _Memory()..kept = 'ocean';
    final selection = await _start(tester, store);
    expect(selection.active, 'light');
  });
}
