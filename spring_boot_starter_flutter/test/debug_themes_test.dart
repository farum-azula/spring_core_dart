// Debug themes: the built-in `default`; one declared under
// spring.flutter.debug.themes drawing the console, the panel and the frame
// meter; a DebugTheme bean; the Theme tab switching them live in a row of
// their own; an unknown key, a bad colour and a missing selected theme
// failing the start, naming the property; no debug themes in a build
// without the panel and the console.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

// A debug theme made in code.
final class _Mint implements DebugTheme {
  static const background = Color(0xFF0B3D2E);
  static const accent = Color(0xFF7CFFCB);

  @override
  String get name => 'mint';

  @override
  DebugStyle styleOf(BuildContext context) =>
      DebugStyle.fromApp(context, background: background, accent: accent);
}

const _night = '''
spring.flutter.debug.themes.night.background=#101820
spring.flutter.debug.themes.night.text=#F2AA4C
spring.flutter.debug.themes.night.dim=#7A6A50
spring.flutter.debug.themes.night.level-info=#123456
spring.flutter.debug.themes.night.logger=#654321
spring.flutter.debug.themes.night.good=#00FF7F
spring.flutter.debug.themes.night.font-family=NightMono
spring.flutter.debug.themes.night.font-size=13
''';

const _nightBackground = Color(0xFF101820);
const _nightText = Color(0xFFF2AA4C);

Future<void> _pump(
  WidgetTester tester, {
  String properties = '',
  bool panel = true,
  bool console = true,
  bool mint = false,
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              if (mint)
                BeanDefinition<_Mint>(
                  name: 'mint',
                  types: const [_Mint, DebugTheme],
                  create: (_) => _Mint(),
                ),
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n'
                'spring.flutter.debug.console.enabled=true\n'
                '$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          if (panel) springBootStarterFlutterDebugAutoConfiguration,
          if (console) springBootStarterFlutterDebugConsoleAutoConfiguration,
          if (console)
            springBootStarterFlutterDebugConsoleLogsAutoConfiguration,
          springBootStarterFlutterDebugFrameMeterAutoConfiguration,
          springBootStarterLoggingAutoConfiguration,
        ],
        bannerMode: BannerMode.off,
      ),
      home: const _Home(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<ApplicationContext> _start(
  WidgetTester tester, {
  String properties = '',
  bool panel = true,
  bool console = true,
  bool mint = false,
}) async {
  await _pump(
    tester,
    properties: properties,
    panel: panel,
    console: console,
    mint: mint,
  );
  final context = SpringScope.of(tester.element(find.byType(_Home)));
  addTearDown(context.getBean<LogBuffer>().clear);
  return context;
}

final _console = find.byKey(const ValueKey('debug-console'));

// The fill of the console's background.
Color? _consoleFill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: _console, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).color;
}

// The fills around the debug panel's title.
List<Color> _panelFills(WidgetTester tester) => [
  for (final box in tester.widgetList<ColoredBox>(
    find.ancestor(
      of: find.text('Debug').first,
      matching: find.byType(ColoredBox),
    ),
  ))
    box.color,
];

// The text the failed start shows.
String _failures(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join('\n');

Future<String> _failedStart(WidgetTester tester, String properties) async {
  await _pump(tester, properties: properties);
  expect(find.byType(_Home), findsNothing);
  return '${tester.takeException()}${_failures(tester)}';
}

void main() {
  testWidgets('default: the built-in look, selected and offered', (
    tester,
  ) async {
    final context = await _start(tester);
    final themes = context.getBean<DebugThemes>();
    expect(themes.selected, 'default');
    expect(themes.names, ['default']);
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    final element = tester.element(_console);
    final style = DebugStyle.of(element);
    final builtIn = DebugStyle.fromApp(element);
    expect(style.background, builtIn.background);
    expect(style.command, builtIn.command);
    expect(
      style.command,
      style.background.computeLuminance() < 0.5
          ? DebugConsoleColors.dark.orange
          : DebugConsoleColors.light.orange,
    );
  });

  testWidgets('a declared theme draws the console: its fill, records, '
      'header and font; the rest the built-in theme\'s', (tester) async {
    final context = await _start(
      tester,
      properties: '${_night}spring.flutter.debug.theme=night\n',
    );
    expect(context.getBean<DebugThemes>().names, ['night', 'default']);
    context.getBean<LogBuffer>().write(
      SpringLogRecord(SpringLogLevel.info, 'probe', 'an info'),
    );
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    await tester.pump();
    final style = DebugStyle.of(tester.element(_console));
    expect(style.background, _nightBackground);
    expect(style.foreground, _nightText);
    expect(style.muted, const Color(0xFF7A6A50));
    expect(style.good, const Color(0xFF00FF7F));
    expect(style.code.fontFamily, 'NightMono');
    expect(style.code.fontSize, 13);
    expect(style.text.fontFamily, 'NightMono');
    expect(style.time, DebugConsoleColors.faint(_nightText));
    expect(style.command, DebugConsoleColors.dark.orange, reason: 'not set');
    expect(_consoleFill(tester), _nightBackground.withValues(alpha: 0.9));

    final record = tester.widget<Text>(find.textContaining('an info'));
    final spans = (record.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans[2].style!.color, const Color(0xFF123456), reason: 'level');
    expect(spans[4].style!.color, const Color(0xFF654321), reason: 'logger');
    expect(record.textSpan!.style!.fontFamily, 'NightMono');
    expect(record.textSpan!.style!.color, _nightText);
  });

  testWidgets('a declared theme draws the panel and the frame meter', (
    tester,
  ) async {
    final context = await _start(
      tester,
      properties: '${_night}spring.flutter.debug.theme=night\n',
    );
    context.getBean<DebugFrameMeter>().on = true;
    await tester.pump();
    final gauge = tester.widget<FrameMeterGauge>(find.byType(FrameMeterGauge));
    expect(gauge.look!.background, _nightBackground.withValues(alpha: 0.85));
    expect(gauge.look!.foreground, _nightText);
    expect(gauge.look!.good, const Color(0xFF00FF7F));
    expect(gauge.look!.bad, isNull, reason: "not set: the app theme's");
    expect(gauge.textStyle!.fontFamily, 'NightMono');

    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    expect(_panelFills(tester), contains(_nightBackground));
    expect(
      tester.widget<Text>(find.text('Debug').first).style!.color,
      _nightText,
    );
    expect(
      tester.widget<Text>(find.text('Close')).style!.fontFamily,
      'NightMono',
    );
  });

  testWidgets('without its own theme the frame meter keeps the app\'s look', (
    tester,
  ) async {
    final context = await _start(tester);
    context.getBean<DebugFrameMeter>().on = true;
    await tester.pump();
    final gauge = tester.widget<FrameMeterGauge>(find.byType(FrameMeterGauge));
    expect(gauge.look, const FrameMeterTheme());
    expect(gauge.textStyle, isNull);
  });

  testWidgets('a DebugTheme bean is offered and selected by its name', (
    tester,
  ) async {
    final context = await _start(
      tester,
      mint: true,
      properties: 'spring.flutter.debug.theme=mint\n',
    );
    final themes = context.getBean<DebugThemes>();
    expect(themes.names, ['mint', 'default']);
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    expect(_consoleFill(tester), _Mint.background.withValues(alpha: 0.9));
    expect(DebugStyle.of(tester.element(_console)).number, _Mint.accent);
  });

  testWidgets('the Theme tab offers the debug themes in a row of their own '
      'and switches them live', (tester) async {
    final context = await _start(tester, mint: true, properties: _night);
    final themes = context.getBean<DebugThemes>();
    context.getBean<DebugPanel>()
      ..tab = context.getSortedBeans<DebugPanelSection>().indexWhere(
        (section) => section is DebugThemeSection,
      )
      ..toggle();
    await tester.pump();
    final row = find.byKey(const ValueKey('debug-themes'));
    expect(find.text('Debug theme: default'), findsOneWidget);
    for (final name in ['night', 'mint', 'default']) {
      expect(
        find.descendant(of: row, matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(tester.getTopLeft(find.text('Theme: system')).dy),
    );

    await tester.tap(find.descendant(of: row, matching: find.text('night')));
    await tester.pump();
    expect(themes.selected, 'night');
    expect(find.text('Debug theme: night'), findsOneWidget);
    expect(_panelFills(tester), contains(_nightBackground));

    await tester.tap(find.descendant(of: row, matching: find.text('mint')));
    await tester.pump();
    expect(themes.selected, 'mint');
    context.getBean<DebugPanel>().close();
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    expect(_consoleFill(tester), _Mint.background.withValues(alpha: 0.9));
  });

  testWidgets('an unknown key fails the start, naming it', (tester) async {
    final failure = await _failedStart(
      tester,
      'spring.flutter.debug.themes.night.colour=#FFFFFF\n',
    );
    expect(failure, contains('spring.flutter.debug.themes.night.colour'));
    expect(failure, contains('not a key of a debug theme'));
  });

  testWidgets('a value that is not a colour fails the start, naming it', (
    tester,
  ) async {
    final failure = await _failedStart(
      tester,
      'spring.flutter.debug.themes.night.background=dusk\n',
    );
    expect(failure, contains('spring.flutter.debug.themes.night.background'));
    expect(failure, contains("'dusk' is not a colour"));
  });

  testWidgets('a selected theme no one has fails the start, naming the '
      'property', (tester) async {
    final failure = await _failedStart(
      tester,
      'spring.flutter.debug.theme=nope\n',
    );
    expect(failure, contains('spring.flutter.debug.theme'));
    expect(failure, contains("no debug theme 'nope'"));
  });

  testWidgets('a layer takes the theme\'s graph-<id>, else its own colour', (
    tester,
  ) async {
    final context = await _start(
      tester,
      properties:
          'spring.flutter.debug.theme=night\n'
          'spring.flutter.debug.themes.night.good=#00FF7F\n'
          'spring.flutter.debug.themes.night.graph-widgets=#112233\n',
    );
    final element = tester.element(find.byType(_Home));
    final night = context.getBean<DebugThemes>().value.styleOf(element);
    final widgets = WidgetsGraphLayer();
    addTearDown(widgets.dispose);
    expect(widgets.colorOf(night), const Color(0xFF112233));
    expect(night.graphLayer('beans', orElse: night.good), night.good);
    final plain = DebugStyle.fromApp(element);
    expect(widgets.colorOf(plain), plain.logger);
    expect(plain.graphLayers, isEmpty);
  });

  testWidgets('in a build with the console alone: debug themes too', (
    tester,
  ) async {
    final context = await _start(tester, panel: false, properties: _night);
    expect(context.getBean<DebugThemes>().names, ['night', 'default']);
  });

  testWidgets('without the panel and the console: no debug themes', (
    tester,
  ) async {
    final context = await _start(
      tester,
      panel: false,
      console: false,
      properties: 'spring.flutter.debug.theme=nope\n',
    );
    expect(context.getBeansOfType<DebugThemes>(), isEmpty);
    expect(context.getBeansOfType<DebugTheme>(), isEmpty);
    expect(find.byType(DebugThemeScope), findsNothing);
  });
}
