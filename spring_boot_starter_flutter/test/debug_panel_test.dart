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
  testWidgets('Ctrl+Shift+D opens it; its sections; Close closes it', (
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
      expect(
        find.descendant(
          of: find.byType(DebugPanelMenu),
          matching: find.text(tab),
        ),
        findsOneWidget,
        reason: tab,
      );
    }
    // The logs of the start, the newest at the bottom.
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

  testWidgets('closed and opened again: the same tab, the same filters', (
    tester,
  ) async {
    final context = await _start(tester);
    final panel = context.getBean<DebugPanel>();
    panel.toggle();
    await tester.pump();

    // The beans' filter.
    await tester.tap(find.text('Beans'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'debugPanel');
    await tester.pump();
    panel.close();
    await tester.pump();
    panel.toggle();
    await tester.pump();
    expect(find.textContaining(' beans'), findsOneWidget, reason: 'Beans');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'debugPanel',
    );
    expect(
      find.textContaining('debugPanelCustomizer', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('debugMotion', findRichText: true),
      findsNothing,
    );

    // The configuration's filter, apart from the beans'.
    await tester.tap(find.text('Configuration'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    await tester.enterText(find.byType(EditableText), 'api-token');
    await tester.pump();
    panel.close();
    await tester.pump();
    await _keys(tester);
    expect(
      find.textContaining('app.api-token', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('spring.flutter.app.type', findRichText: true),
      findsNothing,
    );

    // The logs' level and text.
    await tester.tap(find.text('Logs'));
    await tester.pump();
    await tester.tap(find.text('Warning'));
    await tester.enterText(find.byType(EditableText), 'probe');
    await tester.pump();
    final buffer = context.getBean<LogBuffer>()
      ..write(SpringLogRecord(SpringLogLevel.warning, 'probe', 'kept'))
      ..write(SpringLogRecord(SpringLogLevel.info, 'probe', 'below'))
      ..write(SpringLogRecord(SpringLogLevel.error, 'other', 'elsewhere'));
    await tester.pump();
    panel.close();
    await tester.pump();
    expect(find.text('Debug'), findsNothing);
    await _keys(tester);
    final filter = context.getBean<DebugLogFilter>();
    expect(filter.level, SpringLogLevel.warning);
    expect(filter.text, 'probe');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'probe',
    );
    expect(find.textContaining('kept'), findsOneWidget);
    expect(find.textContaining('below'), findsNothing);
    expect(find.textContaining('elsewhere'), findsNothing);
    expect(buffer.length, greaterThan(3));
  });

  testWidgets("the logs coloured as the console colours them, segment by "
      'segment; the list scrolls', (tester) async {
    final context = await _start(tester);
    final buffer = context.getBean<LogBuffer>()..clear();
    for (final (level, message) in [
      (SpringLogLevel.trace, 'a trace'),
      (SpringLogLevel.debug, 'a debug'),
      (SpringLogLevel.info, 'an info'),
      (SpringLogLevel.warning, 'a warning'),
      (SpringLogLevel.error, 'an error'),
    ]) {
      buffer.write(SpringLogRecord(level, 'probe', message));
    }
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    await tester.pump();
    final style = DebugStyle.of(tester.element(find.textContaining('an info')));
    List<InlineSpan> segments(String message) =>
        (tester.widget<Text>(find.textContaining(message)).textSpan!
                as TextSpan)
            .children!;
    Color? colorOf(InlineSpan span) => (span as TextSpan).style?.color;
    for (final (message, level) in [
      ('a trace', style.levelDebug),
      ('a debug', style.levelDebug),
      ('an info', style.levelInfo),
      ('a warning', style.levelWarning),
      ('an error', style.levelError),
    ]) {
      final parts = segments(message);
      final texts = [for (final part in parts) (part as TextSpan).text];
      expect(texts[2], isIn(['TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR']));
      expect(texts[4], 'probe');
      expect(texts[5], ':');
      expect(texts[6], ' $message');
      expect(colorOf(parts[0]), style.time);
      expect(colorOf(parts[2]), level, reason: message);
      final bar = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.textContaining(message),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        ((bar.decoration as BoxDecoration).border! as Border).left.color,
        level,
        reason: 'the bar of $message',
      );
      expect(colorOf(parts[4]), style.logger);
      expect(colorOf(parts[5]), style.time);
      expect(colorOf(parts[6]), isNull, reason: "the text's own colour");
    }

    // Many records: the newest at the bottom, the list kept there; it
    // scrolls up to the oldest.
    for (var i = 0; i < 200; i++) {
      buffer.write(SpringLogRecord(SpringLogLevel.info, 'probe', 'row $i'));
    }
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('row 199'), findsOneWidget);
    expect(find.textContaining('a trace'), findsNothing);
    await tester.scrollUntilVisible(
      find.textContaining('a trace'),
      -500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('a trace'), findsOneWidget);
  });

  testWidgets('rows of many heights: the list stays at the very bottom as '
      'records come, without reversing it', (tester) async {
    final context = await _start(tester);
    final buffer = context.getBean<LogBuffer>()..clear();
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 120; i++) {
      final lines = i.isEven ? 'tall $i${'\nmore' * 6}' : 'row $i';
      buffer.write(SpringLogRecord(SpringLogLevel.info, 'probe', lines));
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    final list = tester.widget<ListView>(find.byType(ListView).last);
    expect(list.reverse, isFalse);
    final position = list.controller!.position;
    expect(position.pixels, position.maxScrollExtent);
    expect(find.textContaining('row 119'), findsOneWidget);
  });

  testWidgets('Clear while scrolled up shows the cleared list, not the '
      'records held', (tester) async {
    final context = await _start(tester);
    final buffer = context.getBean<LogBuffer>()..clear();
    for (var i = 0; i < 200; i++) {
      buffer.write(SpringLogRecord(SpringLogLevel.info, 'probe', 'row $i'));
    }
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    await tester.pump();
    final list = tester.widget<ListView>(find.byType(ListView).last);
    list.controller!.jumpTo(0);
    await tester.pump();
    expect(find.textContaining('row 0'), findsOneWidget);
    await tester.tap(find.widgetWithText(DebugChip, 'Clear').first);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('row 0'), findsNothing);
    buffer.write(SpringLogRecord(SpringLogLevel.info, 'probe', 'after'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('after'), findsOneWidget);
  });

  group('the menu', () {
    Finder inMenu(String title) => find.descendant(
      of: find.byType(DebugPanelMenu),
      matching: find.text(title),
    );

    void phone(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    int indexOf<T>(ApplicationContext context) => context
        .getSortedBeans<DebugPanelSection>()
        .indexWhere((section) => section is T);

    testWidgets('a wide screen: a menu always open, every section in it, a '
        'tap switches', (tester) async {
      final context = await _start(tester);
      final panel = context.getBean<DebugPanel>()..toggle();
      await tester.pump();
      expect(find.byType(DebugPanelMenu), findsOneWidget);
      expect(find.byKey(DebugHost.menuButtonKey), findsNothing);
      final sections = context.getSortedBeans<DebugPanelSection>();
      expect(sections.length, greaterThan(5));
      for (final section in sections) {
        expect(inMenu(section.title), findsOneWidget, reason: section.title);
      }
      // The menu on the left, the content right of it.
      expect(
        tester.getTopRight(find.byType(DebugPanelMenu)).dx,
        lessThan(tester.getTopLeft(find.text('Filter')).dx),
      );
      await tester.tap(inMenu('Beans'));
      await tester.pump();
      expect(panel.tab, indexOf<DebugBeansSection>(context));
      expect(find.textContaining(' beans'), findsOneWidget);
      expect(find.byType(DebugPanelMenu), findsOneWidget);
    });

    testWidgets('the selected section in the accent; up and down move it '
        'once the menu has focus', (tester) async {
      final context = await _start(tester);
      final panel = context.getBean<DebugPanel>()..toggle();
      await tester.pump();
      await tester.tap(inMenu('Logs'));
      await tester.pump();
      final style = DebugStyle.of(tester.element(inMenu('Logs')));
      expect(tester.widget<Text>(inMenu('Logs')).style!.color, style.accent);
      expect(
        tester.widget<Text>(inMenu('Frames')).style!.color,
        style.foreground,
      );
      // Logs is alone in its group here; next comes Performance's first.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(panel.tab, indexOf<DebugFramesSection>(context));
      expect(tester.widget<Text>(inMenu('Frames')).style!.color, style.accent);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(panel.tab, indexOf<DebugLogsSection>(context));
    });

    testWidgets('a phone: no menu until the button; a drawer that closes on '
        'a pick, on the scrim, on a swipe to the left', (tester) async {
      phone(tester);
      final context = await _start(tester);
      final panel = context.getBean<DebugPanel>();
      await _keys(tester);
      expect(find.byType(DebugPanelMenu), findsNothing);
      expect(find.text('Filter'), findsOneWidget, reason: 'the Logs tab');

      await tester.tap(find.byKey(DebugHost.menuButtonKey));
      await tester.pump();
      expect(find.byKey(DebugHost.drawerKey), findsOneWidget);
      expect(find.byKey(DebugHost.scrimKey), findsOneWidget);
      for (final section in context.getSortedBeans<DebugPanelSection>()) {
        expect(inMenu(section.title), findsOneWidget, reason: section.title);
      }
      await tester.tap(inMenu('Beans'));
      await tester.pump();
      expect(find.byType(DebugPanelMenu), findsNothing);
      expect(panel.tab, indexOf<DebugBeansSection>(context));
      expect(find.textContaining(' beans'), findsOneWidget);

      await tester.tap(find.byKey(DebugHost.menuButtonKey));
      await tester.pump();
      await tester.tapAt(const Offset(390, 400));
      await tester.pump();
      expect(find.byKey(DebugHost.drawerKey), findsNothing);
      expect(panel.tab, indexOf<DebugBeansSection>(context));

      await tester.tap(find.byKey(DebugHost.menuButtonKey));
      await tester.pump();
      await tester.fling(
        find.byKey(DebugHost.drawerKey),
        const Offset(-150, 0),
        800,
      );
      await tester.pump();
      expect(find.byKey(DebugHost.drawerKey), findsNothing);

      // A swipe from the left edge opens it.
      await tester.flingFrom(const Offset(4, 400), const Offset(150, 0), 800);
      await tester.pump();
      expect(find.byKey(DebugHost.drawerKey), findsOneWidget);
    });

    testWidgets('groups: a header each, in the order of their first '
        'section', (tester) async {
      final context = await _start(tester);
      context.getBean<DebugPanel>().toggle();
      await tester.pump();
      double top(String text) => tester.getTopLeft(inMenu(text)).dy;
      for (final header in ['Logs & state', 'Performance', 'App', 'Tools']) {
        expect(inMenu(header), findsOneWidget, reason: header);
      }
      expect(inMenu(DebugPanelMenuGroups.other), findsNothing);
      expect(top('Logs & state'), lessThan(top('Logs')));
      expect(top('Logs'), lessThan(top('Performance')));
      expect(top('Performance'), lessThan(top('Frames')));
      expect(top('Motion'), lessThan(top('App')));
      expect(top('App'), lessThan(top('Configuration')));
      expect(top('Beans'), lessThan(top('Start')));
      expect(top('Start'), lessThan(top('Tools')), reason: 'App, then Tools');
      expect(top('Tools'), lessThan(top('Theme')));
      expect(top('Theme'), lessThan(top('Overlays')));
    });

    test('sections without a group: under Other, last; none grouped: no '
        'header', () {
      const a = _Plain('A');
      const b = _Grouped('B', 'App');
      const c = _Plain('C');
      const d = _Grouped('D', 'Tools');
      const e = _Grouped('E', 'App');
      expect(_described(DebugPanelMenuGroups.of([a, b, c, d, e])), [
        'App: [1, 4]',
        'Tools: [3]',
        'Other: [0, 2]',
      ]);
      expect(DebugPanelMenuGroups.of([a, b, c, d, e]).order, [1, 4, 3, 0, 2]);
      expect(_described(DebugPanelMenuGroups.of([a, c])), [
        'null: [0, 1]',
      ]);
    });

    testWidgets('reopened on the section last shown, on a phone too', (
      tester,
    ) async {
      final context = await _start(tester);
      final panel = context.getBean<DebugPanel>()..toggle();
      await tester.pump();
      await tester.tap(inMenu('Theme'));
      await tester.pump();
      panel.close();
      await tester.pump();
      await _keys(tester);
      expect(panel.tab, indexOf<DebugThemeSection>(context));
      final style = DebugStyle.of(tester.element(inMenu('Theme')));
      expect(tester.widget<Text>(inMenu('Theme')).style!.color, style.accent);

      phone(tester);
      await tester.pump();
      expect(find.byType(DebugPanelMenu), findsNothing);
      panel.close();
      await tester.pump();
      await _keys(tester);
      expect(panel.tab, indexOf<DebugThemeSection>(context));
      expect(find.byKey(DebugHost.drawerKey), findsNothing);
    });
  });
}

class _Plain implements DebugPanelSection {
  const _Plain(this.title);

  @override
  final String title;

  @override
  Widget build(BuildContext context) => Text(title);
}

class _Grouped extends _Plain implements GroupedDebugPanelSection {
  const _Grouped(super.title, this.group);

  @override
  final String group;
}

List<String> _described(DebugPanelMenuGroups menu) => [
  for (final (header, indexes) in menu.groups) '$header: $indexes',
];
