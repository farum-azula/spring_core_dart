// The debug panel: the module the build puts in by
// spring.flutter.debug.enabled, opened by debug.open (keys or taps,
// overridden in spring.flutter.shortcuts), its sections, and off in a
// running app with enabled=false.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<ApplicationContext> _start(
  WidgetTester tester, [
  String properties = '',
]) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            const [],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n'
                'app.api-token=abc\n$properties',
              ),
            },
          ),
        ],
        // In the generator's order: by package, so the panel's before the
        // logging's.
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterDebugAutoConfiguration,
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

Future<void> _keys(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('Ctrl+Shift+D opens it; its tabs; Close closes it', (
    tester,
  ) async {
    final context = await _start(tester);
    final panel = context.getBean<DebugPanel>();
    expect(find.text('Debug'), findsNothing);
    await _keys(tester);
    expect(panel.isOpen, isTrue);
    for (final tab in [
      'Logs',
      'Frames',
      'Configuration',
      'Beans',
      'Theme',
      'Start',
    ]) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    // The logs of the start, newest first.
    expect(find.textContaining('Started application'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Debug'), findsNothing);
  });

  testWidgets('four taps and a fifth held three seconds open it', (
    tester,
  ) async {
    final context = await _start(tester);
    for (var i = 0; i < 4; i++) {
      final tap = await tester.startGesture(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 50));
      await tap.up();
      await tester.pump(const Duration(milliseconds: 100));
    }
    final hold = await tester.startGesture(const Offset(100, 100));
    await tester.pump(const Duration(seconds: 3));
    await hold.up();
    await tester.pump();
    expect(context.getBean<DebugPanel>().isOpen, isTrue);
  });

  testWidgets('spring.flutter.shortcuts.debug.open replaces the keys', (
    tester,
  ) async {
    final context = await _start(
      tester,
      'spring.flutter.shortcuts.debug.open=taps:2',
    );
    await _keys(tester);
    expect(context.getBean<DebugPanel>().isOpen, isFalse);
    for (var i = 0; i < 2; i++) {
      final tap = await tester.startGesture(const Offset(100, 100));
      await tap.up();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(context.getBean<DebugPanel>().isOpen, isTrue);
  });

  testWidgets('frames turn the meter on; the configuration hides secrets', (
    tester,
  ) async {
    final context = await _start(tester);
    final panel = context.getBean<DebugPanel>()..toggle();
    await tester.pump();
    await tester.tap(find.text('Frames'));
    await tester.pump();
    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(panel.frameMeter, isTrue);
    expect(find.byType(FrameMeter), findsOneWidget);

    final rows = context.getBean<DebugConfigurationSection>().properties();
    final token = rows.firstWhere((row) => row.$1 == 'app.api-token');
    expect(token.$2, '******');
  });

  testWidgets('enabled=false in a running app: no panel', (tester) async {
    final context = await _start(tester, 'spring.flutter.debug.enabled=false');
    expect(context.containsBean('debugPanel'), isFalse);
    await _keys(tester);
    expect(find.text('Debug'), findsNothing);
  });
}
