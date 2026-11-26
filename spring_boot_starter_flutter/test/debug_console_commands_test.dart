// The debug console's `commands` pane: only when `panes` names it; what
// the commands printed over its input line; a line sent with Enter runs
// its command and prints what it returns under the line typed; `help`,
// the one command built in, lists every command, the application's
// included; an unknown command and a failing one as errors; an
// application's command before the framework's of the same name; up and
// down through the history; the keys typed not reaching the app.
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

// Registered with `@ConsoleCommand` in its bean definition; its getter
// agrees.
final class _Ping extends DebugConsoleCommand {
  _Ping(this.name);

  @override
  final String name;

  List<String>? args;

  @override
  String get usage => '<words>';

  @override
  String get help => 'Answers.';

  @override
  Future<Iterable<String>> run(DebugConsoleCall call) async {
    args = call.args;
    if (call.args.firstOrNull == 'fail') {
      throw StateError('down');
    }
    return ['pong ${call.args.join(' ')}'];
  }
}

// A plain key the app binds: not run while the input has the focus.
final class _KeyAction implements KeyedShortcutHandler {
  int runs = 0;

  @override
  String get action => 'test.k';

  @override
  List<String> get keys => const ['k'];

  @override
  bool handle(ShortcutInvocation invocation) {
    runs++;
    return true;
  }
}

Future<ApplicationContext> _start(
  WidgetTester tester, {
  bool input = true,
  List<Object> beans = const [],
  String properties = '',
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              for (final (i, bean) in beans.indexed)
                switch (bean) {
                  final _Ping ping => BeanDefinition<_Ping>(
                    name: 'ping$i',
                    types: const [_Ping, DebugConsoleCommand],
                    annotations: [ConsoleCommand(ping.name)],
                    create: (_) => ping,
                  ),
                  final _KeyAction action => BeanDefinition<_KeyAction>(
                    name: 'keyAction',
                    types: const [
                      _KeyAction,
                      ShortcutHandler,
                      KeyedShortcutHandler,
                    ],
                    create: (_) => action,
                  ),
                  _ => throw ArgumentError(bean),
                },
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n'
                'spring.flutter.debug.console.interaction=interact\n'
                'spring.flutter.debug.console.slide-duration=0\n'
                '${input ? 'spring.flutter.debug.console.panes=logs,commands\n'
                          'spring.flutter.debug.console.shown-panes=logs,commands\n' : ''}'
                '$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleFilterAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsAutoConfiguration,
          if (input)
            springBootStarterFlutterDebugConsoleCommandsAutoConfiguration,
          springBootStarterLoggingAutoConfiguration,
        ],
        bannerMode: BannerMode.off,
      ),
      home: const _Home(),
    ),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(_Home)));
  context.getBean<LogBuffer>().clear();
  addTearDown(context.getBean<LogBuffer>().clear);
  context.getBean<DebugConsole>().shown = true;
  await tester.pump();
  return context;
}

final _input = find.byKey(const ValueKey('debug-console-input'));
final _commands = find.byKey(const ValueKey('debug-console-commands'));

// The row of [word] in a list of commands: its word's span, and its
// arguments' when it has them.
({TextSpan command, TextSpan? usage}) _usage(WidgetTester tester, String word) {
  for (final text in tester.widgetList<Text>(
    find.descendant(of: _commands, matching: find.byType(Text)),
  )) {
    final spans = (text.textSpan as TextSpan?)?.children;
    if (spans != null &&
        spans.isNotEmpty &&
        (spans.first as TextSpan).text == word) {
      return (
        command: spans.first as TextSpan,
        usage: spans.length > 1 ? spans[1] as TextSpan : null,
      );
    }
  }
  throw StateError('no row of $word');
}

Future<void> _type(WidgetTester tester, String line) async {
  await tester.tap(_input);
  await tester.pump();
  await tester.enterText(_input, line);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
  await tester.pump();
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('without the pane in the build: no input line, no commands, '
      'the log pane alone', (tester) async {
    final context = await _start(tester, input: false);
    expect(_input, findsNothing);
    expect(context.getBean<DebugConsole>().namedPanes.keys, ['logs']);
    expect(context.getBeansOfType<DebugConsoleCommand>(), isEmpty);
    expect(
      find.byKey(const ValueKey('debug-console-logs')),
      findsOneWidget,
    );
  });

  testWidgets('help is the one command built in', (tester) async {
    final context = await _start(tester);
    final pane = context.getBean<CommandsPane>();
    expect(pane.commands.keys, ['help']);
    expect(context.getBeansOfType<DebugConsoleCommand>().keys, [
      'helpCommand',
    ]);
    expect(context.getBean<DebugConsole>().namedPanes, {
      'logs': context.getBean<LogsPane>(),
      'commands': pane,
    });
  });

  testWidgets('the console\'s own key, typed in its line, hides it: a key '
      'alone is not the text\'s there', (tester) async {
    final context = await _start(
      tester,
      properties: 'spring.flutter.shortcuts.debug.console=backquote',
    );
    await tester.tap(_input);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backquote);
    await tester.pump();
    expect(context.getBean<DebugConsole>().shown, isFalse);
    expect(_input, findsNothing);
  });

  testWidgets('help lists every command, the application\'s first, in two '
      'aligned columns, over the input; the line typed dim', (
    tester,
  ) async {
    final context = await _start(
      tester,
      beans: [_Ping('ping'), _Ping('reload')],
    );
    context.getBean<LogBuffer>().write(
      SpringLogRecord(SpringLogLevel.info, 'probe', 'a record'),
    );
    expect(_input, findsOneWidget);
    expect(find.text('help'), findsOneWidget, reason: 'the hint');
    await _type(tester, 'help');
    final style = DebugStyle.of(tester.element(_input));
    expect(
      find.descendant(of: _commands, matching: find.text('> help')),
      findsOneWidget,
    );
    expect(_colorOf(tester, '> help'), style.muted);
    for (final (word, usage, help) in [
      ('ping', '<words>', 'Answers.'),
      ('help', '[command]', 'Lists the commands, or tells of one.'),
    ]) {
      final row = _usage(tester, word);
      expect(row.command.style!.color, style.command, reason: word);
      if (usage.isNotEmpty) {
        expect(row.usage!.text, ' $usage');
        expect(row.usage!.style!.color, style.argument, reason: word);
      }
      expect(
        tester.widget<Text>(find.text(help).first).style?.color,
        style.foreground,
      );
    }
    expect(_usage(tester, 'reload').command.text, 'reload');
    expect(find.text('Answers.'), findsNWidgets(2), reason: 'ping, reload');
    final helps = ['Answers.', 'Lists the commands, or tells of one.'];
    final left = tester.getTopLeft(find.text(helps.first).first).dx;
    for (final help in helps) {
      expect(tester.getTopLeft(find.text(help).first).dx, left, reason: help);
    }
    expect(
      tester.getTopLeft(find.text('Answers.').first).dy,
      lessThan(
        tester.getTopLeft(find.text('Lists the commands, or tells of one.')).dy,
      ),
    );
    // The log pane: the records only, above the commands.
    final logs = find.byKey(const ValueKey('debug-console-logs'));
    expect(
      find.descendant(of: logs, matching: find.textContaining('a record')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: logs, matching: find.textContaining('help')),
      findsNothing,
    );
    expect(
      tester.getBottomLeft(logs).dy,
      lessThanOrEqualTo(tester.getTopLeft(_commands).dy),
    );
    expect(
      tester.getBottomLeft(_commands).dy,
      lessThanOrEqualTo(tester.getTopLeft(_input).dy),
    );
  });

  testWidgets('the commands pane scrolls on its own; the logs stay', (
    tester,
  ) async {
    final context = await _start(
      tester,
      beans: [_Ping('one'), _Ping('two'), _Ping('three')],
    );
    context.getBean<DebugConsole>().resize(
      panes: {
        'commands':
            2 * DebugConsoleView.lineHeight + DebugConsoleInputField.height,
      },
    );
    await tester.pump();
    context.getBean<LogBuffer>().write(
      SpringLogRecord(SpringLogLevel.info, 'probe', 'a record'),
    );
    await _type(tester, 'help');
    expect(find.text('> help'), findsNothing, reason: 'above');
    await tester.drag(_commands, const Offset(0, 300));
    await tester.pump();
    expect(find.text('> help'), findsOneWidget, reason: 'scrolled back');
    expect(find.textContaining('a record'), findsOneWidget);
  });

  testWidgets('a command gets the words after its name; what it throws and '
      'an unknown command are errors, in red', (tester) async {
    final ping = _Ping('ping');
    await _start(tester, beans: [ping]);
    await _type(tester, 'ping  a   b');
    expect(ping.args, ['a', 'b']);
    expect(find.text('pong a b'), findsOneWidget);

    await _type(tester, 'ping fail');
    final style = DebugStyle.of(tester.element(_input));
    expect(find.text('ping: Bad state: down'), findsOneWidget);
    expect(_colorOf(tester, 'ping: Bad state: down'), style.error);

    await _type(tester, 'nope');
    expect(
      find.text("nope: no such command; 'help' lists them"),
      findsOneWidget,
    );
  });

  testWidgets("an application's command replaces the framework's of its "
      'name', (tester) async {
    final mine = _Ping('help');
    await _start(tester, beans: [mine]);
    await _type(tester, 'help now');
    expect(mine.args, ['now']);
    expect(find.text('pong now'), findsOneWidget);
  });

  testWidgets('up and down go back through the lines typed, and forth to '
      'the line being typed', (tester) async {
    final context = await _start(tester, beans: [_Ping('ping')]);
    await _type(tester, 'ping one');
    await _type(tester, 'ping two');
    final commandLine = context.getBean<CommandsPane>();
    expect(commandLine.history, ['ping one', 'ping two']);
    final field = tester.widget<EditableText>(_input);
    await tester.enterText(_input, 'pi');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(field.controller.text, 'ping two');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(field.controller.text, 'ping one');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(field.controller.text, 'ping one', reason: 'the oldest');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(field.controller.text, 'ping two');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(field.controller.text, 'pi', reason: 'the line being typed');
  });

  testWidgets('history keeps its size', (tester) async {
    final context = await _start(
      tester,
      beans: [_Ping('ping')],
      properties: 'spring.flutter.debug.console.history=2',
    );
    for (final word in ['a', 'b', 'c']) {
      await _type(tester, 'ping $word');
    }
    expect(
      context.getBean<CommandsPane>().history,
      ['ping b', 'ping c'],
    );
  });

  testWidgets('while it has the focus the keys typed do not reach the app; '
      'Escape gives the focus back', (tester) async {
    final action = _KeyAction();
    await _start(tester, beans: [action]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    expect(action.runs, 1, reason: 'the app has the key');

    await tester.tap(_input);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    expect(action.runs, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    expect(action.runs, 2);
  });
}
