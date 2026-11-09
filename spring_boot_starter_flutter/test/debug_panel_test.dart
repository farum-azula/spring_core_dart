// The debug panel: the module the build puts in by
// spring.flutter.debug.enabled, opened by debug.open (keys or taps,
// overridden in spring.flutter.shortcuts), its sections, and off in a
// running app with enabled=false; the frame meter and the motion switch,
// modules of their own with their own keys, the meter without the panel.
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
  List<BeanModule>? debug,
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
          ...debug ??
              [
                springBootStarterFlutterDebugAutoConfiguration,
                springBootStarterFlutterDebugFrameMeterAutoConfiguration,
                springBootStarterFlutterDebugMotionAutoConfiguration,
              ],
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
      'Motion',
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
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    await tester.tap(find.text('Frames'));
    await tester.pump();
    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(context.getBean<DebugFrameMeter>().on, isTrue);
    // In the panel itself; the overlays hide while it is open.
    expect(find.byType(FrameMeterGauge), findsOneWidget);

    // Motion off: the app under the panel has animations disabled.
    await tester.tap(find.text('Motion'));
    await tester.pump();
    await tester.tap(find.text('Off').last);
    await tester.pump();
    expect(context.getBean<DebugMotion>().animations, isFalse);
    expect(
      MediaQuery.disableAnimationsOf(
        tester.element(find.byType(Navigator).first),
      ),
      isTrue,
    );

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

  testWidgets('the frame meter alone: ⌘⇧X and five taps and a hold', (
    tester,
  ) async {
    final context = await _start(tester, '', [
      springBootStarterFlutterDebugFrameMeterAutoConfiguration,
    ]);
    expect(context.containsBean('debugPanel'), isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(FrameMeterGauge), findsOneWidget);
    // The panel's keys do nothing: it is not in the app.
    await _keys(tester);
    expect(find.text('Debug'), findsNothing);

    for (var i = 0; i < 5; i++) {
      final tap = await tester.startGesture(const Offset(100, 100));
      await tap.up();
      await tester.pump(const Duration(milliseconds: 100));
    }
    final hold = await tester.startGesture(const Offset(100, 100));
    await tester.pump(const Duration(seconds: 2));
    await hold.up();
    await tester.pump();
    expect(find.byType(FrameMeterGauge), findsNothing);
  });

  testWidgets('⌘⇧M turns the motion off; enabled=false, no switch', (
    tester,
  ) async {
    final context = await _start(
      tester,
      'spring.flutter.debug.frame-meter.enabled=false',
    );
    expect(context.containsBean('debugFrameMeter'), isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(context.getBean<DebugMotion>().animations, isFalse);
    // The panel's Frames tab says the meter is not there.
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    await tester.tap(find.text('Frames'));
    await tester.pump();
    expect(find.textContaining('not in this build'), findsOneWidget);
  });
}
