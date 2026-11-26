// The debug panel's Flutter tab: each of Flutter's debug tools switched
// live (the flag it sets, the app repainted or wrapped), kept while the
// panel is closed, the tab only with the panel and by its own switch, and
// what a profile or release build, or the web, cannot run.
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

int _paints = 0;

// The rainbow's color moves at each repaint; the binding wants it back.
final HSVColor _rainbowStart = debugCurrentRepaintColor;

class _Counter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => _paints++;

  @override
  bool shouldRepaint(_Counter oldDelegate) => false;
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('home $taps'),
      SizedBox(
        width: 50,
        height: 50,
        child: RepaintBoundary(child: CustomPaint(painter: _Counter())),
      ),
    ],
  );
}

final List<BeanModule> _withPanel = [
  springBootStarterFlutterDebugAutoConfiguration,
  springBootStarterFlutterDebugFlutterToolsAutoConfiguration,
];

Future<ApplicationContext> _start(
  WidgetTester tester, {
  String properties = '',
  List<BeanModule>? debug,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(_resetFlutter);
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
          ...debug ?? _withPanel,
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

// Flutter's test binding checks the flags are back when a test ends.
void _resetFlutter() {
  debugPaintSizeEnabled = false;
  debugPaintBaselinesEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugPaintPointersEnabled = false;
  debugRepaintRainbowEnabled = false;
  debugCurrentRepaintColor = _rainbowStart;
  debugInvertOversizedImages = false;
  timeDilation = 1;
  WidgetsBinding.instance.debugShowWidgetInspectorOverride = false;
  WidgetsBinding.instance.debugExcludeRootWidgetInspector = false;
}

Future<void> _openTab(WidgetTester tester, ApplicationContext context) async {
  final panel = context.getBean<DebugPanel>();
  if (!panel.isOpen) {
    panel.toggle();
  }
  await tester.pump();
  await tester.tap(find.text('Flutter'));
  await tester.pump();
}

Widget _alone(DebugFlutterToolsSection section) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(1200, 2400)),
    child: Builder(builder: section.build),
  ),
);

void main() {
  testWidgets('the Flutter tab is a tab of the panel', (tester) async {
    final context = await _start(tester);
    await _openTab(tester, context);
    expect(find.text('Widget inspector'), findsOneWidget);
    expect(find.text('Slow animations'), findsOneWidget);
    expect(find.text('DevTools'), findsOneWidget);
  });

  for (final (title, read) in <(String, bool Function())>[
    ('Paint size', () => debugPaintSizeEnabled),
    ('Baselines', () => debugPaintBaselinesEnabled),
    ('Layer borders', () => debugPaintLayerBordersEnabled),
    ('Pointers', () => debugPaintPointersEnabled),
    ('Repaint rainbow', () => debugRepaintRainbowEnabled),
    ('Invert oversized images', () => debugInvertOversizedImages),
  ]) {
    testWidgets('$title sets its flag and repaints the app', (tester) async {
      final context = await _start(tester);
      await _openTab(tester, context);
      final before = _paints;
      await tester.tap(find.text(title));
      await tester.pump();
      expect(read(), isTrue);
      expect(_paints, greaterThan(before));
      final on = _paints;
      await tester.tap(find.text(title));
      await tester.pump();
      expect(read(), isFalse);
      expect(_paints, greaterThan(on));
    });
  }

  testWidgets('the performance overlay and the semantics debugger wrap the '
      'app, which keeps its state', (tester) async {
    final context = await _start(tester);
    tester.state<_HomeState>(find.byType(_Home)).taps = 3;
    await _openTab(tester, context);
    await tester.tap(find.text('Performance overlay'));
    await tester.pump();
    expect(find.byType(PerformanceOverlay), findsOneWidget);
    await tester.tap(find.text('Semantics debugger'));
    await tester.pump();
    expect(find.byType(SemanticsDebugger), findsOneWidget);
    expect(tester.state<_HomeState>(find.byType(_Home)).taps, 3);
    await tester.tap(find.text('Performance overlay'));
    await tester.tap(find.text('Semantics debugger'));
    await tester.pump();
    expect(find.byType(PerformanceOverlay), findsNothing);
    expect(find.byType(SemanticsDebugger), findsNothing);
    expect(tester.state<_HomeState>(find.byType(_Home)).taps, 3);
  });

  testWidgets('the inspector selects under the panel and the tab shows the '
      'selection', (tester) async {
    final context = await _start(tester);
    await _openTab(tester, context);
    expect(find.textContaining('Nothing selected'), findsOneWidget);
    await tester.tap(find.text('Widget inspector'));
    await tester.pump();
    expect(WidgetsBinding.instance.debugShowWidgetInspectorOverride, isTrue);
    // One inspector, below the panel: WidgetsApp's own is left out.
    expect(find.byType(WidgetInspector), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WidgetInspector),
        matching: find.text('Widget inspector'),
      ),
      findsNothing,
    );
    final selection = WidgetInspectorService.instance.selection;
    selection.current = tester.renderObject(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is _Counter),
    );
    await tester.pump();
    expect(find.text('CustomPaint'), findsOneWidget);
    expect(find.textContaining('50.0 x 50.0 at ('), findsOneWidget);
    expect(find.text('  RepaintBoundary'), findsWidgets);
    expect(find.text('  _Home'), findsOneWidget);
    selection.clear();
    await tester.tap(find.text('Widget inspector'));
    await tester.pump();
    expect(WidgetsBinding.instance.debugShowWidgetInspectorOverride, isFalse);
    expect(find.byType(WidgetInspector), findsNothing);
  });

  testWidgets('slow animations set timeDilation', (tester) async {
    final context = await _start(tester);
    await _openTab(tester, context);
    await tester.tap(find.text('5x'));
    await tester.pump();
    expect(timeDilation, 5);
    await tester.tap(find.text('1x'));
    await tester.pump();
    expect(timeDilation, 1);
  });

  testWidgets('the tools stay on while the panel is closed, and it shows '
      'them on again', (tester) async {
    final context = await _start(tester);
    await _openTab(tester, context);
    await tester.tap(find.text('Paint size'));
    await tester.tap(find.text('10x'));
    await tester.pump();
    context.getBean<DebugPanel>().close();
    await tester.pump();
    expect(debugPaintSizeEnabled, isTrue);
    expect(timeDilation, 10);
    await _openTab(tester, context);
    final tools = context.getBean<DebugFlutterTools>();
    expect(tools.switches.firstWhere((t) => t.title == 'Paint size').on, true);
    expect(tools.dilation, 10);
  });

  testWidgets('closing the context turns the tools off', (tester) async {
    final context = await _start(tester);
    final tools = context.getBean<DebugFlutterTools>();
    tools.flip(tools.switches.firstWhere((t) => t.title == 'Paint size'), true);
    tools.dilation = 2;
    await tester.pumpWidget(const SizedBox());
    expect(debugPaintSizeEnabled, isFalse);
    expect(timeDilation, 1);
  });

  testWidgets('without the panel there is no tab and nothing around the app', (
    tester,
  ) async {
    final context = await _start(
      tester,
      debug: [springBootStarterFlutterDebugFlutterToolsAutoConfiguration],
    );
    expect(context.containsBean('debugFlutterTools'), isFalse);
    expect(context.containsBean('debugFlutterToolsCustomizer'), isFalse);
  });

  testWidgets('spring.flutter.debug.flutter-tools.enabled=false turns it off '
      'in a running app', (tester) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.flutter-tools.enabled=false',
    );
    expect(context.containsBean('debugFlutterTools'), isFalse);
    expect(context.containsBean('debugFlutterToolsSection'), isFalse);
    expect(context.containsBean('debugPanel'), isTrue);
  });

  testWidgets('a profile or release build shows the debug-only tools off, '
      'with the reason, and never sets their flags', (tester) async {
    addTearDown(_resetFlutter);
    for (final build in ['profile', 'release']) {
      final tools = DebugFlutterTools(
        mode: FlutterToolsMode(build: build, debug: false, web: false),
      );
      await tester.pumpWidget(
        _alone(DebugFlutterToolsSection(tools, lookup: () async => null)),
      );
      await tester.pump();
      expect(
        find.text(
          'Debug builds only: Flutter leaves it out of a $build build.',
        ),
        findsNWidgets(8),
      );
      await tester.tap(find.text('Paint size'));
      await tester.pump();
      expect(debugPaintSizeEnabled, isFalse);
      for (final tool in tools.switches) {
        tools.flip(tool, true);
      }
      expect(debugPaintSizeEnabled, isFalse);
      expect(debugRepaintRainbowEnabled, isFalse);
      expect(
        WidgetsBinding.instance.debugShowWidgetInspectorOverride,
        isFalse,
      );
      // What every build can run still runs.
      expect(
        tools.switches.firstWhere((t) => t.title == 'Performance overlay').on,
        isTrue,
      );
      expect(
        find.text(
          'The VM service is off in this $build build, so DevTools cannot '
          'connect.',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('on the web the performance overlay and DevTools say why not', (
    tester,
  ) async {
    final tools = DebugFlutterTools(
      mode: const FlutterToolsMode(build: 'debug', debug: true, web: true),
    );
    var looked = false;
    await tester.pumpWidget(
      _alone(
        DebugFlutterToolsSection(
          tools,
          lookup: () async {
            looked = true;
            return null;
          },
        ),
      ),
    );
    expect(find.textContaining('Not on the web'), findsOneWidget);
    expect(
      find.textContaining('Not available from inside the app on the web'),
      findsOneWidget,
    );
    expect(looked, isFalse);
  });

  testWidgets('DevTools: the command with the VM service address', (
    tester,
  ) async {
    final tools = DebugFlutterTools(
      mode: const FlutterToolsMode(build: 'debug', debug: true, web: false),
    );
    await tester.pumpWidget(
      _alone(
        DebugFlutterToolsSection(
          tools,
          lookup: () async => Uri.parse('ws://127.0.0.1:5000/abc=/ws'),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('dart devtools ws://127.0.0.1:5000/abc=/ws'),
      findsOneWidget,
    );
    expect(find.text('Copy'), findsOneWidget);
  });
}
