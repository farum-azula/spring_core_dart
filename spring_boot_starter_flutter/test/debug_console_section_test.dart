// The debug panel's Console tab: under Tools, a switch for each segment
// and each pane the build has, applied live to the `debugConsole` bean
// (where the state lives, starting as `header` and `shown-panes` say);
// a drag moves a segment in the header. Every pane listed, `logs` too,
// each switch selected exactly while its pane shows, whatever changed it.
// Only with the panel and the console.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

// A command of the app that shows or hides a pane: `pane <name> on|off`.
final class _PaneCommand extends DebugConsoleCommand {
  const _PaneCommand();

  @override
  String get usage => '<pane> on|off';

  @override
  String get help => 'Shows or hides a pane.';

  @override
  Iterable<String> run(DebugConsoleCall call) {
    call.console.showPane(call.args[0], shown: call.args[1] == 'on');
    return const [];
  }
}

Future<ApplicationContext> _start(
  WidgetTester tester, {
  String panes = 'commands',
  String properties = '',
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              BeanDefinition<_PaneCommand>(
                name: 'paneCommand',
                types: const [_PaneCommand, DebugConsoleCommand],
                annotations: const [ConsoleCommand('pane')],
                create: (_) => const _PaneCommand(),
              ),
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n'
                'spring.flutter.debug.console.enabled=true\n'
                'spring.flutter.debug.console.segments=fps,frames-lost,filter\n'
                'spring.flutter.debug.console.header=filter,fps\n'
                'spring.flutter.debug.console.panes=$panes\n'
                '$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleFpsAutoConfiguration,
          springBootStarterFlutterDebugConsoleFramesLostAutoConfiguration,
          springBootStarterFlutterDebugConsoleFilterAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsAutoConfiguration,
          springBootStarterFlutterDebugConsoleCommandsAutoConfiguration,
          springBootStarterFlutterDebugConsoleSectionAutoConfiguration,
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

Finder _tab(String title) => find.descendant(
  of: find.byType(DebugPanelMenu),
  matching: find.text(title),
);

Future<DebugConsole> _openTab(WidgetTester tester) async {
  final context = SpringScope.of(tester.element(find.byType(_Home)));
  context.getBean<DebugPanel>().toggle();
  await tester.pump();
  await tester.tap(_tab('Console'));
  await tester.pump();
  return context.getBean<DebugConsole>();
}

bool _selected(WidgetTester tester, String key) =>
    tester.widget<DebugChip>(find.byKey(ValueKey(key))).selected;

void main() {
  testWidgets('under Tools; the start state from the properties', (
    tester,
  ) async {
    final context = await _start(tester);
    final section = context.getBean<DebugConsoleSection>();
    expect(section.group, 'Tools');
    expect(section.title, 'Console');
    final console = await _openTab(tester);
    expect(console.header, ['filter', 'fps']);
    expect(_selected(tester, 'debug-console-segment-filter'), isTrue);
    expect(_selected(tester, 'debug-console-segment-fps'), isTrue);
    expect(_selected(tester, 'debug-console-segment-frames-lost'), isFalse);
    expect(_selected(tester, 'debug-console-pane-switch-commands'), isFalse);
    expect(find.text('Commands'), findsOneWidget, reason: "the pane's title");
  });

  testWidgets('a segment switched on and off, live', (tester) async {
    await _start(tester);
    final console = await _openTab(tester);
    await tester.tap(find.byKey(const ValueKey('debug-console-segment-fps')));
    await tester.pump();
    expect(console.header, ['filter']);
    expect(_selected(tester, 'debug-console-segment-fps'), isFalse);
    await tester.tap(
      find.byKey(const ValueKey('debug-console-segment-frames-lost')),
    );
    await tester.pump();
    expect(console.header, ['filter', 'frames-lost']);
  });

  testWidgets('a pane switched on and off, live: the console builds it or '
      'not', (tester) async {
    await _start(tester);
    final console = await _openTab(tester);
    final chip = find.byKey(
      const ValueKey('debug-console-pane-switch-commands'),
    );
    await tester.tap(chip);
    await tester.pump();
    expect(console.panes, ['commands']);
    expect(_selected(tester, 'debug-console-pane-switch-commands'), isTrue);

    // Closed, the panel shows the console with its pane.
    final context = SpringScope.of(tester.element(find.byType(_Home)));
    context.getBean<DebugPanel>().toggle();
    console.shown = true;
    await tester.pump();
    expect(
      find.byKey(const ValueKey('debug-console-pane-commands')),
      findsOneWidget,
    );
    console.shown = false;
    await tester.pump();

    await _openTab(tester);
    await tester.tap(chip);
    await tester.pump();
    expect(console.panes, isEmpty);
  });

  testWidgets('the logs pane listed and switched like any other: every pane '
      'hidden leaves the header alone', (tester) async {
    await _start(
      tester,
      panes: 'logs,commands',
      properties: 'spring.flutter.debug.console.shown-panes=logs\n',
    );
    final console = await _openTab(tester);
    expect(console.namedPanes.keys, ['logs', 'commands']);
    expect(
      find.byKey(const ValueKey('debug-console-pane-switch-logs')),
      findsOneWidget,
    );
    expect(find.text('Logs'), findsWidgets, reason: "the pane's title");
    expect(_selected(tester, 'debug-console-pane-switch-logs'), isTrue);
    expect(_selected(tester, 'debug-console-pane-switch-commands'), isFalse);

    await tester.tap(
      find.byKey(const ValueKey('debug-console-pane-switch-logs')),
    );
    await tester.pump();
    expect(console.panes, isEmpty);
    expect(_selected(tester, 'debug-console-pane-switch-logs'), isFalse);

    final context = SpringScope.of(tester.element(find.byType(_Home)));
    context.getBean<DebugPanel>().toggle();
    console.shown = true;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('debug-console-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('debug-console-logs')), findsNothing);
    expect(find.byKey(const ValueKey('debug-console-handle')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('debug-console'))).height,
      closeTo(console.size.height, 0.01),
      reason: 'the strip',
    );
    console.shown = false;
    await tester.pump();

    await _openTab(tester);
    await tester.tap(
      find.byKey(const ValueKey('debug-console-pane-switch-logs')),
    );
    await tester.pump();
    expect(console.panes, ['logs']);
    expect(_selected(tester, 'debug-console-pane-switch-logs'), isTrue);
  });

  testWidgets('each pane switch selected exactly while its pane shows: from '
      'shown-panes at the start, then whatever changes it', (tester) async {
    await _start(
      tester,
      panes: 'logs,commands',
      properties: 'spring.flutter.debug.console.shown-panes=commands\n',
    );
    final console = await _openTab(tester);
    void expectSwitches({required bool logs, required bool commands}) {
      expect(console.showsPane('logs'), logs);
      expect(console.showsPane('commands'), commands);
      expect(_selected(tester, 'debug-console-pane-switch-logs'), logs);
      expect(_selected(tester, 'debug-console-pane-switch-commands'), commands);
    }

    expectSwitches(logs: false, commands: true);

    // Changed on the bean while the tab shows.
    console.showPane('logs');
    await tester.pump();
    expectSwitches(logs: true, commands: true);

    // Another switch leaves this one as it is.
    await tester.tap(
      find.byKey(const ValueKey('debug-console-pane-switch-commands')),
    );
    await tester.pump();
    expectSwitches(logs: true, commands: false);

    // A command typed into the console, the tab opened again after it.
    final context = SpringScope.of(tester.element(find.byType(_Home)));
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    final commands = context.getBean<CommandsPane>();
    await commands.run('pane logs off', console);
    await commands.run('pane commands on', console);
    await tester.pump();
    expect(
      commands.output.lines.where(
        (line) => line.kind == DebugConsoleLineKind.error,
      ),
      isEmpty,
    );
    await _openTab(tester);
    expectSwitches(logs: false, commands: true);
  });

  testWidgets('a drag moves a segment in the header: a mouse at once, a '
      'touch after a long press', (tester) async {
    await _start(tester);
    final console = await _openTab(tester);
    expect(console.segmentOrder, ['filter', 'fps', 'frames-lost']);
    Finder chip(String name) =>
        find.byKey(ValueKey('debug-console-segment-$name'));

    final mouse = await tester.startGesture(
      tester.getCenter(chip('fps')),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-10, 0));
    await mouse.moveTo(tester.getTopLeft(chip('filter')) + const Offset(2, 8));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('debug-console-segment-drop')),
      findsOneWidget,
    );
    await mouse.up();
    await tester.pump();
    expect(console.header, ['fps', 'filter']);

    final touch = await tester.startGesture(tester.getCenter(chip('filter')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await touch.moveTo(tester.getTopRight(chip('frames-lost')));
    await tester.pump();
    await touch.up();
    await tester.pump();
    expect(console.segmentOrder, ['fps', 'frames-lost', 'filter']);
    expect(console.header, ['fps', 'filter']);
  });

  testWidgets('the console off in a running app: no tab', (tester) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.console.enabled=false',
    );
    expect(context.getBeansOfType<DebugConsoleSection>(), isEmpty);
    context.getBean<DebugPanel>().toggle();
    await tester.pump();
    expect(_tab('Console'), findsNothing);
  });

  testWidgets('the panel off in a running app: no tab', (tester) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.debug.enabled=false',
    );
    expect(context.getBeansOfType<DebugConsoleSection>(), isEmpty);
    expect(context.getBeansOfType<DebugConsole>(), hasLength(1));
  });
}
