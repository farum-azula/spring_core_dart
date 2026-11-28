// The debug console's `logs` pane, listed and shown by default: hidden
// until its action shows it, the
// newest records coloured segment by segment as the console colours them,
// wrapped, as wide as the screen allows, scrolling back and following the
// newest, by the debug panel's filter (one bean, live) or, without the
// panel, by the configuration's; its background's opacity, taps going
// through it to the app, nothing listened to while hidden, and the module
// out of a running app with enabled=false. The header, the input and the
// commands: debug_console_header_test.dart, debug_console_commands_test.dart,
// debug_console_panes_test.dart.
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class _Home extends StatelessWidget {
  const _Home({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: const SizedBox.expand(),
  );
}

Future<ApplicationContext> _start(
  WidgetTester tester, {
  String properties = '',
  bool panel = true,
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            const [],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          if (panel) springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleFilterAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsAutoConfiguration,
          springBootStarterLoggingAutoConfiguration,
        ],
        bannerMode: BannerMode.off,
      ),
      home: _Home(onTap: onTap),
    ),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(_Home)));
  // The logging system's buffer outlives the test.
  addTearDown(context.getBean<LogBuffer>().clear);
  return context;
}

// The key left of `1` (any layout: it is matched where it lies, see
// keyboard_shortcuts_test.dart).
Future<void> _keys(WidgetTester tester) async {
  await tester.sendKeyEvent(
    LogicalKeyboardKey.backquote,
    physicalKey: PhysicalKeyboardKey.backquote,
  );
  await tester.pump();
}

final _view = find.byType(DebugConsoleView);

final _records = find.byKey(const ValueKey('debug-console-records'));

List<TextSpan> _segments(WidgetTester tester, String message) => [
  for (final part
      in (tester.widget<Text>(find.textContaining(message)).textSpan!
              as TextSpan)
          .children!)
    part as TextSpan,
];

// The record with [message] shows whole: on more than one line, and none
// of it cut.
void _expectWrapped(WidgetTester tester, String message) {
  final text = find.textContaining(message);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.maxLines, isNull);
  expect(paragraph.overflow, TextOverflow.clip);
  expect(tester.getSize(text).height, greaterThan(30), reason: 'wrapped');
  expect(
    tester.getRect(text).right,
    lessThanOrEqualTo(tester.getRect(_view).right),
  );
}

void _log(ApplicationContext context, SpringLogLevel level, String message) =>
    context.getBean<LogBuffer>().write(
      SpringLogRecord(level, 'probe', message),
    );

void main() {
  testWidgets('hidden at the start; the action, its keys and its id', (
    tester,
  ) async {
    final context = await _start(tester);
    final overlay = context.getBean<DebugConsole>();
    expect(overlay.shown, isFalse);
    expect(_view, findsNothing);
    expect(overlay.action, 'debug.console');
    expect(overlay.keys, ['backquote', 'section', 'taps:8+hold:2s']);
    expect(overlay.id, 'console');
    expect(overlay.corner, DebugCorner.topLeft);
    expect(overlay.opacity, 0.9);
    expect(context.getBean<LogsPane>().maxLines, 12);
    expect(overlay.width, 1);
  });

  testWidgets('the logs pane is listed and shown by default, on top', (
    tester,
  ) async {
    final context = await _start(tester);
    final overlay = context.getBean<DebugConsole>();
    final logs = context.getBean<LogsPane>();
    expect(overlay.namedPanes, {'logs': logs});
    expect(overlay.panes, ['logs']);
    expect(logs.title, 'Logs');
    expect(
      context.getBean<FlutterDebugProperties>().console.panes,
      ['logs'],
    );
  });

  testWidgets('the key left of 1 shows the newest records, again hides them', (
    tester,
  ) async {
    final context = await _start(tester);
    _log(context, SpringLogLevel.info, 'hello console');
    await _keys(tester);
    expect(context.getBean<DebugConsole>().shown, isTrue);
    expect(_view, findsOneWidget);
    expect(find.textContaining('hello console'), findsOneWidget);
    expect(find.textContaining('Started application'), findsOneWidget);

    // Records logged while shown: drawn in the next frame.
    _log(context, SpringLogLevel.error, 'a new one');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('a new one'), findsOneWidget);

    await _keys(tester);
    expect(_view, findsNothing);
  });

  testWidgets('eight taps and a ninth held two seconds show it', (
    tester,
  ) async {
    final context = await _start(tester);
    for (var i = 0; i < 8; i++) {
      final tap = await tester.startGesture(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 50));
      await tap.up();
      await tester.pump(const Duration(milliseconds: 100));
    }
    final hold = await tester.startGesture(const Offset(400, 400));
    await tester.pump(const Duration(seconds: 2));
    await hold.up();
    await tester.pump();
    expect(context.getBean<DebugConsole>().shown, isTrue);
  });

  testWidgets('max-lines high, the newest at the bottom, each segment in '
      "the console's colour", (tester) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.console.max-lines=4',
    );
    context.getBean<LogBuffer>().clear();
    for (final (level, message) in [
      (SpringLogLevel.info, 'old one'),
      (SpringLogLevel.debug, 'a debug'),
      (SpringLogLevel.info, 'an info'),
      (SpringLogLevel.warning, 'a warning'),
      (SpringLogLevel.error, 'an error'),
    ]) {
      _log(context, level, message);
    }
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    expect(find.textContaining('old one'), findsNothing);
    expect(
      tester.getTopLeft(find.textContaining('an error')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('a warning')).dy),
    );
    final style = DebugStyle.of(tester.element(_view));
    final faint = style.time;
    for (final (message, level) in [
      ('a debug', style.levelDebug),
      ('an info', style.levelInfo),
      ('a warning', style.levelWarning),
      ('an error', style.levelError),
    ]) {
      final parts = _segments(tester, message);
      expect(
        [for (final part in parts) part.text],
        [
          isA<String>(),
          ' ',
          isIn(['DEBUG', 'INFO', 'WARNING', 'ERROR']),
          ' ',
          'probe',
          ':',
          ' $message',
        ],
      );
      expect(parts[0].style!.color, faint, reason: 'the time');
      expect(parts[2].style!.color, level, reason: 'the level');
      expect(parts[4].style!.color, style.logger, reason: 'the logger');
      expect(parts[5].style!.color, faint, reason: 'the colon');
      expect(parts[6].style, isNull, reason: "the message: the text's own");
    }
  });

  testWidgets('each record marked on its left by one line in its level\'s '
      'colour, down all its wrapped lines', (tester) async {
    final context = await _start(tester);
    _log(context, SpringLogLevel.error, 'broken ${'word ' * 60}end');
    _log(context, SpringLogLevel.info, 'fine');
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    final style = DebugStyle.of(tester.element(_view));
    final bars = [
      for (final box in tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('debug-console-records')),
          matching: find.byType(DecoratedBox),
        ),
      ))
        if ((box.decoration as BoxDecoration).border case final Border border)
          border.left.color,
    ];
    // The newest first; under them what the start logged.
    expect(bars.take(2), [
      style.level(SpringLogLevel.info),
      style.level(SpringLogLevel.error),
    ]);
  });

  testWidgets('wide screen: width of it, long records wrapped, nothing cut', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final context = await _start(tester);
    final long = 'a long message ${'word ' * 80}end';
    _log(context, SpringLogLevel.info, long);
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    expect(
      tester.getSize(_view).width,
      moreOrLessEquals(1600 - 16),
    );
    _expectWrapped(tester, long);
  });

  testWidgets('phone: all of its width, long records wrapped', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final context = await _start(tester);
    _log(context, SpringLogLevel.info, 'a phone line ${'word ' * 30}end');
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    expect(tester.getSize(_view).width, 390 - 16);
    _expectWrapped(tester, 'a phone line');
  });

  testWidgets('width: the fraction of a wide screen', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.console.width=0.5',
    );
    final overlay = context.getBean<DebugConsole>();
    expect(overlay.width, 0.5);
    overlay.shown = true;
    await tester.pump();
    expect(tester.getSize(_view).width, moreOrLessEquals((1600 - 16) * 0.5));
  });

  testWidgets('scrolls back by drag and wheel, keeps the lines read, follows '
      'again at the bottom', (tester) async {
    final context = await _start(
      tester,
      properties:
          'spring.flutter.debug.console.max-lines=4\n'
          'spring.flutter.debug.console.interaction=interact\n'
          'spring.flutter.debug.console.slide-duration=0',
    );
    context.getBean<LogBuffer>().clear();
    for (var i = 0; i < 60; i++) {
      _log(context, SpringLogLevel.info, 'row $i.');
    }
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    expect(find.textContaining('row 59.'), findsOneWidget);
    expect(find.textContaining('row 40.'), findsNothing);

    // A drag down shows older records; new ones wait.
    await tester.drag(_records, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('row 59.'), findsNothing);
    expect(find.textContaining('paused'), findsOneWidget);
    _log(context, SpringLogLevel.info, 'while scrolled');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('while scrolled'), findsNothing);
    expect(find.textContaining('paused'), findsOneWidget);

    // A wheel turn up goes further back, to the oldest.
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final at = tester.getCenter(_records);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -5000)));
    await tester.pump();
    expect(find.textContaining('row 0.'), findsOneWidget);

    // Down to the bottom: the newest again, followed.
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 10000)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('while scrolled'), findsOneWidget);
    expect(find.textContaining('paused'), findsNothing);
    _log(context, SpringLogLevel.info, 'followed');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('followed'), findsOneWidget);
  });

  testWidgets('a wheel turn elsewhere is the app\'s, a tap after a scroll '
      'still reaches it', (tester) async {
    var taps = 0;
    final context = await _start(
      tester,
      onTap: () => taps++,
      properties:
          'spring.flutter.debug.console.max-lines=4\n'
          'spring.flutter.debug.console.interaction=interact',
    );
    for (var i = 0; i < 30; i++) {
      _log(context, SpringLogLevel.info, 'row $i.');
    }
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(400, 550)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -500)));
    await tester.pump();
    expect(find.textContaining('row 29.'), findsOneWidget);
    expect(find.textContaining('paused'), findsNothing);

    await tester.drag(_records, const Offset(0, 100));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(_records));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 1);
  });

  testWidgets('a filter changed while scrolled up: back to the newest', (
    tester,
  ) async {
    final context = await _start(
      tester,
      properties:
          'spring.flutter.debug.console.max-lines=4\n'
          'spring.flutter.debug.console.interaction=interact\n'
          'spring.flutter.debug.console.slide-duration=0',
    );
    for (var i = 0; i < 30; i++) {
      _log(context, SpringLogLevel.info, 'row $i.');
    }
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    await tester.drag(_records, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.textContaining('paused'), findsOneWidget);
    context.getBean<DebugLogFilter>().text = 'row';
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('paused'), findsNothing);
    expect(find.textContaining('row 29.'), findsOneWidget);
  });

  testWidgets("the debug panel's filter, live", (tester) async {
    final context = await _start(tester);
    _log(context, SpringLogLevel.info, 'an info');
    _log(context, SpringLogLevel.error, 'an error');
    final overlay = context.getBean<DebugConsole>();
    final filter = context.getBean<DebugLogFilter>();
    expect(context.getBean<LogsPane>().filter, same(filter));

    // Error chosen in the Logs tab.
    final panel = context.getBean<DebugPanel>()..toggle();
    await tester.pump();
    await tester.tap(find.text('Error'));
    await tester.pump();
    panel.close();
    overlay.shown = true;
    await tester.pump();
    expect(find.textContaining('an error'), findsOneWidget);
    expect(find.textContaining('an info'), findsNothing);
    expect(find.textContaining('logs\u00A0error'), findsOneWidget);

    // Changed while the console shows: in the next frame.
    filter
      ..level = SpringLogLevel.trace
      ..text = 'info';
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('an info'), findsOneWidget);
    expect(find.textContaining('an error'), findsNothing);
  });

  testWidgets('the configuration starts the filter of both', (tester) async {
    final context = await _start(
      tester,
      properties:
          'spring.flutter.debug.console.filter.level=warning\n'
          'spring.flutter.debug.console.filter.text=probe',
    );
    final filter = context.getBean<DebugLogFilter>();
    expect(filter.level, SpringLogLevel.warning);
    expect(filter.text, 'probe');
    expect(context.getBean<DebugLogsSection>().filter, same(filter));
  });

  testWidgets("without the panel: the configuration's filter", (tester) async {
    final context = await _start(
      tester,
      panel: false,
      properties:
          'spring.flutter.debug.console.filter.level=warning\n'
          'spring.flutter.debug.console.position=bottom-right',
    );
    expect(context.containsBean('debugPanel'), isFalse);
    final overlay = context.getBean<DebugConsole>();
    expect(context.getBean<LogsPane>().filter.level, SpringLogLevel.warning);
    expect(overlay.corner, DebugCorner.bottomRight);
    _log(context, SpringLogLevel.info, 'an info');
    _log(context, SpringLogLevel.warning, 'a warning');
    await _keys(tester);
    expect(find.textContaining('a warning'), findsOneWidget);
    expect(find.textContaining('an info'), findsNothing);
  });

  testWidgets('the debug panel off in a running app: the same, by the '
      'configuration', (tester) async {
    final context = await _start(
      tester,
      properties:
          'spring.flutter.debug.enabled=false\n'
          'spring.flutter.debug.console.filter.level=error',
    );
    expect(context.containsBean('debugPanel'), isFalse);
    expect(
      context.getBean<LogsPane>().filter.level,
      SpringLogLevel.error,
    );
  });

  testWidgets('opacity: of the background; the records stay opaque', (
    tester,
  ) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.console.opacity=0.4',
    );
    _log(context, SpringLogLevel.info, 'readable');
    final overlay = context.getBean<DebugConsole>();
    expect(overlay.opacity, 0.4);
    overlay.shown = true;
    await tester.pump();
    final background = tester.widget<DecoratedBox>(
      find.descendant(of: _view, matching: find.byType(DecoratedBox)).first,
    );
    expect(
      (background.decoration as BoxDecoration).color!.a,
      moreOrLessEquals(0.4, epsilon: 0.01),
    );
    final parts = _segments(tester, 'readable');
    expect(parts[2].style!.color!.a, 1, reason: 'the level');
    expect(parts[4].style!.color!.a, 1, reason: 'the logger');
    expect(
      tester
          .widget<Text>(find.textContaining('readable'))
          .textSpan!
          .style!
          .color!
          .a,
      1,
    );
  });

  test('opacity out of 0 to 1, max-lines under 1 and width out of 0.2 to 1 '
      'are brought in range', () {
    expect(DebugConsole(width: 0).width, 0.2);
    expect(DebugConsole(width: 2).width, 1);
    expect(DebugConsole(opacity: 3).opacity, 1);
    expect(DebugConsole(opacity: -1).opacity, 0);
    expect(LogsPane(filter: DebugLogFilter(), maxLines: 0).maxLines, 1);
  });

  testWidgets('taps on the records reach the app', (tester) async {
    var taps = 0;
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.console.slide-duration=0',
      onTap: () => taps++,
    );
    _log(context, SpringLogLevel.info, 'over the app');
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    final line = tester.getCenter(find.textContaining('over the app'));
    final background = tester.getRect(_view);
    expect(background.contains(line), isTrue);
    await tester.tapAt(line);
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 1);
    await tester.tapAt(background.bottomRight - const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 2);
  });

  testWidgets('hidden, records build nothing; a burst shown is one rebuild', (
    tester,
  ) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.console.slide-duration=0',
    );
    final overlay = context.getBean<DebugConsole>();
    for (var i = 0; i < 50; i++) {
      _log(context, SpringLogLevel.info, 'hidden $i');
    }
    await tester.pump();
    expect(_view, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);

    overlay.shown = true;
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      _log(context, SpringLogLevel.info, 'burst $i');
    }
    // The buffer's one event, then one frame.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(find.textContaining('burst 99'), findsOneWidget);
    expect(find.textContaining('burst 87'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('hidden while the debug panel is open, listed in its '
      'Overlays tab', (tester) async {
    final context = await _start(tester);
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    expect(_view, findsOneWidget);
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    expect(_view, findsNothing);
    expect(
      context.getBean<DebugOverlaysSection>().overlays,
      contains(context.getBean<DebugConsole>()),
    );
  });

  testWidgets('enabled=false in a running app: no console', (tester) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.console.enabled=false',
    );
    expect(context.containsBean('debugConsole'), isFalse);
    await _keys(tester);
    expect(_view, findsNothing);
  });
}
