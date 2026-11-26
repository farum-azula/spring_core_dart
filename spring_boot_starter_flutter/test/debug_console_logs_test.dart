// The debug console's `logs` pane selects as the Logs tab does: a long press
// or a click with Shift or ⌘ marks a whole record and starts the selection,
// whose bar copies, exports and clears; text selects and copies while it
// lasts; a plain tap on a record or on the background stays the app's
// until then. The `export [log|jsonl]` command exports the marked records,
// else those the filter shows, and is in the build only with the log
// export, the logs pane and the commands pane. The selection and the
// command follow the logs pane: shown only while it shows, built only
// with it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
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

final class _Export implements DebugFileExport, Ordered {
  final files = <(String, Uint8List)>[];

  @override
  bool get available => true;

  @override
  int get order => 0;

  @override
  Future<String> export(
    String fileName,
    Uint8List bytes,
    String mimeType,
  ) async {
    files.add((fileName, bytes));
    return 'Shared $fileName';
  }

  List<String> lines(int i) =>
      const LineSplitter().convert(utf8.decode(files[i].$2));
}

final List<BeanModule> _withExport = [
  springBootStarterFlutterDebugConsoleAutoConfiguration,
  springBootStarterFlutterDebugConsoleLogsAutoConfiguration,
  springBootStarterFlutterDebugConsoleCommandsAutoConfiguration,
  springBootStarterFlutterDebugConsoleExportCommandAutoConfiguration,
  springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration,
];

Future<ApplicationContext> _start(
  WidgetTester tester, {
  List<BeanModule>? debug,
  _Export? export,
  String properties = '',
  VoidCallback? onTap,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              if (export != null)
                BeanDefinition<_Export>(
                  name: 'shareExport',
                  types: const [_Export, DebugFileExport, Ordered],
                  create: (_) => export,
                ),
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n'
                'spring.application.name=shop\n'
                'spring.flutter.debug.console.enabled=true\n'
                'spring.flutter.debug.console.panes=logs,commands\n'
                'spring.flutter.debug.console.shown-panes=logs,commands\n'
                'spring.flutter.debug.console.interaction=interact\n'
                'spring.flutter.debug.console.slide-duration=0\n'
                'logging.pattern.console=%d{HH:mm:ss} %5p [%logger] %m\n'
                'spring.output.ansi.enabled=always\n'
                '$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          ...debug ?? _withExport,
          springBootStarterLoggingAutoConfiguration,
        ],
        bannerMode: BannerMode.off,
      ),
      home: _Home(onTap: onTap),
    ),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(_Home)));
  context.getBean<LogBuffer>().clear();
  addTearDown(context.getBean<LogBuffer>().clear);
  return context;
}

Future<void> _show(
  WidgetTester tester,
  ApplicationContext context,
  List<String> messages,
) async {
  for (final message in messages) {
    context.getBean<LogBuffer>().write(
      SpringLogRecord(SpringLogLevel.info, 'neon.shop', message),
    );
  }
  context.getBean<DebugConsole>().shown = true;
  await tester.pump();
  await tester.pump();
}

final _input = find.byKey(const ValueKey('debug-console-input'));
final _commands = find.byKey(const ValueKey('debug-console-commands'));
final _view = find.byType(DebugConsoleView);

Finder _record(String message) => find.textContaining(message);

Future<void> _type(WidgetTester tester, String line) async {
  await tester.tap(_input);
  await tester.pump();
  await tester.enterText(_input, line);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
  await tester.pump();
}

String? _clipboardText;

void _clipboard(WidgetTester tester) {
  _clipboardText = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        _clipboardText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') {
        return {'text': _clipboardText};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

final _plainLine = RegExp(r'^\d\d:\d\d:\d\d  INFO \[neon\.shop\] (.+)$');

String? _messageOf(String line) =>
    (jsonDecode(line) as Map<String, Object?>)['message'] as String?;

/// The `build:` argument of [module] as the starter writes it, on one
/// line.
String _build(String module) {
  final source = File('lib/spring_auto_configuration.dart').readAsStringSync();
  final declaration = RegExp(
    'final BeanModule\\s+$module\\b',
  ).firstMatch(source)!;
  final annotation = source.lastIndexOf(
    '@AutoConfigurationModule(',
    declaration.start,
  );
  final start = source.indexOf('AutoConfigurationBuild', annotation);
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') {
      depth++;
    } else if (source[i] == ')' && --depth == 0) {
      return source
          .substring(start, i + 1)
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(', )', ')')
          .replaceAll(', ]', ']')
          .replaceAll('( ', '(')
          .replaceAll('[ ', '[');
    }
  }
  throw StateError('unbalanced');
}

void main() {
  group('the log pane', () {
    testWidgets('a tap on a record or the background stays the app\'s; a '
        'long press marks the record and starts the selection', (
      tester,
    ) async {
      _clipboard(tester);
      var taps = 0;
      final context = await _start(tester, onTap: () => taps++);
      await _show(tester, context, ['first', 'second', 'third']);
      final console = context.getBean<LogsPane>();
      expect(find.text('Select'), findsOneWidget);

      await tester.tap(_record('second'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(taps, 1);
      expect(console.selecting, isFalse);

      await tester.longPress(_record('first'));
      await tester.pump();
      expect(taps, 1, reason: 'a long press is the console\'s');
      expect(console.selecting, isTrue);
      expect(find.text('1 marked'), findsOneWidget);

      // Selecting, a tap on a record marks it...
      await tester.tap(_record('third'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('2 marked'), findsOneWidget);
      expect(taps, 1);
      // ...and one beside the panes still reaches the app.
      final background = tester.getRect(_view);
      await tester.tapAt(background.topLeft + const Offset(3, 3));
      await tester.pump(const Duration(milliseconds: 500));
      expect(taps, 2);

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(_clipboardText, isNot(contains('\x1B')));
      expect(
        [
          for (final line in _clipboardText!.split('\n'))
            _plainLine.firstMatch(line)?.group(1),
        ],
        ['first', 'third'],
      );
      expect(find.text('copied 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(console.selecting, isFalse);
      expect(console.marks.isEmpty, isTrue);
      expect(find.text('Select'), findsOneWidget);
      await tester.tap(_record('second'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(taps, 3, reason: 'cleared, taps go through again');
    });

    testWidgets('a click with Shift or ⌘ on a record marks it, and does not '
        'reach the app', (tester) async {
      var taps = 0;
      final context = await _start(tester, onTap: () => taps++);
      await _show(tester, context, ['first', 'second']);
      final console = context.getBean<LogsPane>();
      for (final key in [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.tap(_record('second'), kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(key);
        await tester.pump(const Duration(milliseconds: 500));
        expect(console.marks.count, 1, reason: '$key');
        expect(taps, 0, reason: '$key');
        await tester.tap(find.text('Clear'));
        await tester.pump();
      }
      await tester.tap(_record('second'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(console.marks.isEmpty, isTrue);
      expect(taps, 1);
    });

    testWidgets('the marks of records the buffer dropped no longer count; '
        'cleared while scrolled up, the held lines go', (tester) async {
      final context = await _start(tester);
      await _show(tester, context, ['first', 'second', 'third']);
      final pane = context.getBean<LogsPane>();
      final buffer = context.getBean<LogBuffer>();
      pane.marks.toggle(buffer.records.first);
      pane.marks.toggle(buffer.records.last);
      expect(pane.marks.count, 2);
      buffer.capacity = 2;
      buffer.write(SpringLogRecord(SpringLogLevel.info, 'neon.shop', 'fourth'));
      await tester.pump();
      await tester.pump();
      expect(pane.marks.count, 1, reason: 'first was evicted');
      buffer.clear();
      await tester.pump();
      await tester.pump();
      expect(pane.marks.count, 0);
      expect(find.textContaining('third'), findsNothing);
      expect(find.textContaining('fourth'), findsNothing);
      buffer.capacity = 1000;
    });

    testWidgets('Select: the text selects and copies with Ctrl+C', (
      tester,
    ) async {
      _clipboard(tester);
      final context = await _start(tester);
      await _show(tester, context, ['first order', 'second order']);
      await tester.tap(find.text('Select'));
      await tester.pump();
      expect(context.getBean<LogsPane>().selecting, isTrue);
      expect(find.text('Clear'), findsOneWidget);
      // A mouse drags across the records: their text selects.
      final from = tester.getTopLeft(_record('first order'));
      final to = tester.getBottomRight(_record('second order'));
      final mouse = await tester.startGesture(
        from + const Offset(1, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await mouse.moveTo(to - const Offset(1, 4));
      await tester.pump();
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(context.getBean<LogsPane>().marks.isEmpty, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(_clipboardText, contains('first order'));
      expect(_clipboardText, contains('second order'));
    });

    testWidgets('while it selects new records do not move the lines', (
      tester,
    ) async {
      final context = await _start(tester);
      await _show(tester, context, ['first', 'second']);
      await tester.longPress(_record('first'));
      await tester.pump();
      final at = tester.getTopLeft(_record('first'));
      await _show(tester, context, ['later']);
      expect(_record('later'), findsNothing);
      expect(tester.getTopLeft(_record('first')), at);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      await tester.pump();
      expect(_record('later'), findsOneWidget);
    });

    testWidgets('its .jsonl exports the marked records; what it tells shows', (
      tester,
    ) async {
      final export = _Export();
      final context = await _start(tester, export: export);
      await _show(tester, context, ['paid', 'shipped', 'refunded']);
      await tester.longPress(_record('shipped'));
      await tester.pump();
      await tester.tap(find.text('.jsonl'));
      await tester.pump();
      await tester.pump();
      expect(
        [for (final line in export.lines(0)) _messageOf(line)],
        [
          'shipped',
        ],
      );
      expect(export.files.single.$1, endsWith('.jsonl'));
      expect(
        find.text('Shared ${export.files.single.$1}'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('export', () {
    testWidgets('help lists it', (tester) async {
      final context = await _start(tester);
      await _show(tester, context, []);
      expect(context.getBean<CommandsPane>().commands.keys, contains('export'));
      await _type(tester, 'help export');
      expect(
        find.descendant(
          of: _commands,
          matching: find.textContaining('Exports the marked records'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('jsonl: the records the filter shows; what it tells printed', (
      tester,
    ) async {
      final export = _Export();
      final context = await _start(tester, export: export);
      await _show(tester, context, ['paid', 'shipped', 'refunded']);
      context.getBean<DebugLogFilter>().text = 'ed';
      await tester.pump();
      await _type(tester, 'export jsonl');
      expect(
        [for (final line in export.lines(0)) _messageOf(line)],
        [
          'shipped',
          'refunded',
        ],
      );
      final name = export.files.single.$1;
      expect(name, matches(RegExp(r'^shop-logs-\d{8}-\d{6}\.jsonl$')));
      expect(
        find.descendant(of: _commands, matching: find.text('Shared $name')),
        findsOneWidget,
      );
    });

    testWidgets('log (the default): the marked records, as the console '
        'prints them', (tester) async {
      final export = _Export();
      final context = await _start(tester, export: export);
      await _show(tester, context, ['paid', 'shipped', 'refunded']);
      await tester.longPress(_record('refunded'));
      await tester.pump();
      await tester.longPress(_record('paid'));
      await tester.pump();
      await _type(tester, 'export');
      final lines = export.lines(0);
      expect(export.files.single.$1, endsWith('.log'));
      expect(lines.join('\n'), isNot(contains('\x1B')));
      expect(
        [for (final line in lines) _plainLine.firstMatch(line)?.group(1)],
        [
          'paid',
          'refunded',
        ],
      );
    });

    testWidgets('a format it does not have: an error naming the others', (
      tester,
    ) async {
      final context = await _start(tester, export: _Export());
      await _show(tester, context, ['paid']);
      await _type(tester, 'export csv');
      expect(
        find.descendant(
          of: _commands,
          matching: find.text('export: no format csv: [log|jsonl]'),
        ),
        findsOneWidget,
      );
    });

    test('its switch: the commands pane, inside the console, the logs pane '
        'and the log export; the logs pane in by default', () {
      expect(
        _build(
          'springBootStarterFlutterDebugConsoleExportCommandAutoConfiguration',
        ),
        "AutoConfigurationBuild.named('spring.flutter.debug.console.panes', "
        "'commands', whenMissing: BuildInclusion.never, parents: ["
        "AutoConfigurationBuild('spring.flutter.debug.console.enabled', "
        'whenMissing: BuildInclusion.never), '
        "AutoConfigurationBuild.named('spring.flutter.debug.console.panes', "
        "'logs', whenMissing: BuildInclusion.always), "
        "AutoConfigurationBuild('spring.flutter.debug.logs.export.enabled')])",
      );
      expect(
        _build('springBootStarterFlutterDebugConsoleLogsAutoConfiguration'),
        "AutoConfigurationBuild.named('spring.flutter.debug.console.panes', "
        "'logs', whenMissing: BuildInclusion.always, parents: ["
        "AutoConfigurationBuild('spring.flutter.debug.console.enabled', "
        'whenMissing: BuildInclusion.never)])',
      );
    });

    testWidgets('the logs pane hidden: no Select in the header, nothing of '
        'it built; shown again, both back', (tester) async {
      final context = await _start(tester);
      await _show(tester, context, ['paid']);
      final console = context.getBean<DebugConsole>();
      expect(find.text('Select'), findsOneWidget);
      console.showPane('logs', shown: false);
      await tester.pump();
      await tester.pump();
      expect(find.text('Select'), findsNothing);
      expect(find.byType(DebugConsoleLogsView), findsNothing);
      expect(_record('paid'), findsNothing);
      console.showPane('logs');
      await tester.pump();
      await tester.pump();
      expect(find.text('Select'), findsOneWidget);
      expect(_record('paid'), findsOneWidget);
    });

    testWidgets('without the logs pane in the build: no pane, no selection, '
        'no export command', (tester) async {
      final context = await _start(
        tester,
        debug: [
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleCommandsAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration,
        ],
        properties:
            'spring.flutter.debug.console.panes=commands\n'
            'spring.flutter.debug.console.shown-panes=commands\n',
      );
      await _show(tester, context, ['paid']);
      expect(context.getBeansOfType<LogsPane>(), isEmpty);
      expect(context.getBeansOfType<ExportCommand>(), isEmpty);
      expect(context.getBean<DebugConsole>().namedPanes.keys, ['commands']);
      expect(find.text('Select'), findsNothing);
      expect(_record('paid'), findsNothing);
      expect(_input, findsOneWidget);
    });

    testWidgets('without its module: no command, help does not list it, the '
        'pane selects without export words', (tester) async {
      final context = await _start(
        tester,
        debug: [
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsAutoConfiguration,
          springBootStarterFlutterDebugConsoleCommandsAutoConfiguration,
        ],
      );
      await _show(tester, context, ['paid']);
      expect(context.getBeansOfType<ExportCommand>(), isEmpty);
      expect(context.getBean<CommandsPane>().commands.keys, ['help']);
      await tester.longPress(_record('paid'));
      await tester.pump();
      expect(find.text('1 marked'), findsOneWidget);
      expect(find.text('.log'), findsNothing);
    });

    testWidgets('logs.export.enabled=false in a running app: no command', (
      tester,
    ) async {
      final context = await _start(
        tester,
        properties: 'spring.flutter.debug.logs.export.enabled=false\n',
      );
      expect(context.getBeansOfType<ExportCommand>(), isEmpty);
      expect(context.getBeansOfType<DebugLogExport>(), isEmpty);
    });
  });
}
