// The debug panel's Logs tab beyond showing records: the text selects and
// copies, records are picked whole and copied as the console prints them,
// and the log export writes `.log` and `.jsonl` files named after the app,
// handed to the first available `DebugFileExport` (the app's, a browser
// download, the Downloads folder, the clipboard), made in slices that leave
// the frames their turn. The export is in the build only by its switch and
// only with the panel or the console.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

final class _Export implements DebugFileExport, Ordered {
  _Export({this.available = true, this.fails = false});

  @override
  final bool available;

  final bool fails;

  @override
  int get order => 0;

  final files = <(String, Uint8List, String)>[];

  @override
  Future<String> export(
    String fileName,
    Uint8List bytes,
    String mimeType,
  ) async {
    if (fails) {
      throw StateError('full');
    }
    files.add((fileName, bytes, mimeType));
    return 'Shared $fileName';
  }
}

final class _Slow implements DebugLogFormat {
  _Slow(this.cost);

  final Duration cost;
  int sinceTurn = 0;

  @override
  String get extension => 'slow';

  @override
  String get mimeType => 'text/plain';

  @override
  String format(SpringLogRecord record) {
    final watch = Stopwatch()..start();
    while (watch.elapsed < cost) {}
    sinceTurn++;
    return '${record.message}\n';
  }
}

const _properties =
    'spring.application.name=Neon Shop\n'
    'logging.pattern.console=%d{HH:mm:ss} %5p [%logger] %m\n'
    'spring.output.ansi.enabled=always\n';

final List<BeanModule> _panelAndExport = [
  springBootStarterFlutterDebugAutoConfiguration,
  springBootStarterFlutterDebugLogsExportAutoConfiguration,
];

Future<ApplicationContext> _start(
  WidgetTester tester, {
  String properties = _properties,
  List<BeanModule>? debug,
  List<BeanDefinition<Object>> beans = const [],
}) async {
  tester.view
    ..physicalSize = const Size(1400, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            beans,
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          ...debug ?? _panelAndExport,
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

// The panel open on the Logs tab with [messages] alone in the buffer, the
// oldest first.
Future<LogBuffer> _logs(
  WidgetTester tester,
  ApplicationContext context,
  List<String> messages,
) async {
  final buffer = context.getBean<LogBuffer>()..clear();
  for (final message in messages) {
    buffer.write(SpringLogRecord(SpringLogLevel.info, 'neon.shop', message));
  }
  context.getBean<DebugPanel>().toggle();
  await tester.pump();
  await tester.pump();
  return buffer;
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

Finder _record(String message) =>
    find.textContaining(message, findRichText: true);

final _plainLine = RegExp(r'^\d\d:\d\d:\d\d  INFO \[neon\.shop\] (.+)$');

SpringLogRecord _at(
  String message, {
  Object? error,
  StackTrace? stackTrace,
  SpringLogLevel level = SpringLogLevel.info,
}) => SpringLogRecord(
  level,
  'neon.shop',
  message,
  error: error,
  stackTrace: stackTrace,
  time: DateTime(2026, 11, 25, 9, 5, 2, 42),
);

/// The `build:` argument of [module] as the starter writes it.
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
  group('text selection', () {
    testWidgets('the records select as text and copy with the context menu '
        'and Ctrl+C', (tester) async {
      _clipboard(tester);
      final context = await _start(tester);
      await _logs(tester, context, ['first order', 'second order']);
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      expect(
        find.descendant(
          of: find.byType(SelectableRegion),
          matching: _record('first order'),
        ),
        findsOneWidget,
      );

      region.selectAll();
      await tester.pump();
      await tester.tapAt(
        tester.getTopLeft(_record('second order')) + const Offset(4, 4),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(_clipboardText, contains('first order'));
      expect(_clipboardText, contains('second order'));

      _clipboardText = null;
      await tester.tap(_record('first order'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      region.selectAll();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(_clipboardText, contains('second order'));
    });
  });

  group('pick mode', () {
    testWidgets('a long press marks a record, a tap another; Copy copies them '
        'as the console prints them, no colours; Clear selection ends it', (
      tester,
    ) async {
      _clipboard(tester);
      final context = await _start(tester);
      await _logs(tester, context, ['first', 'second', 'third']);
      expect(find.textContaining('marked'), findsNothing);

      await tester.longPress(_record('first'));
      await tester.pump();
      expect(find.text('1 marked'), findsOneWidget);
      // In the pick mode a tap marks.
      await tester.tap(_record('third'));
      await tester.pump();
      expect(find.text('2 marked'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pump();
      final lines = _clipboardText!.split('\n');
      expect(_clipboardText, isNot(contains('\x1B')));
      expect(lines, hasLength(2));
      expect(
        [
          for (final line in lines) _plainLine.firstMatch(line)?.group(1),
        ],
        ['first', 'third'],
        reason: _clipboardText,
      );
      expect(find.text('Copied 2 records'), findsOneWidget);

      await tester.tap(_record('third'));
      await tester.pump();
      expect(find.text('1 marked'), findsOneWidget);
      await tester.tap(find.text('Clear selection'));
      await tester.pump();
      expect(find.textContaining('marked'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a click with Shift or ⌘ marks a record', (tester) async {
      final context = await _start(tester);
      await _logs(tester, context, ['first', 'second']);
      for (final key in [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.tap(_record('second'), kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(key);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('1 marked'), findsOneWidget, reason: '$key');
        await tester.tap(find.text('Clear selection'));
        await tester.pump();
      }
      // Without a modifier, a click selects text and marks nothing.
      await tester.tap(_record('second'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('marked'), findsNothing);
    });
  });

  group('formats', () {
    test('.log: the console pattern, without ANSI, error lines after', () {
      final format = PlainDebugLogFormat(
        () => LogPattern(
          '%clr(%d{HH:mm:ss.SSS}){faint} %red(%5p) [%logger] %m',
          ansi: true,
        ),
      );
      expect(format.extension, 'log');
      expect(format.mimeType, 'text/plain');
      expect(
        format.format(_at('paid')),
        '09:05:02.042  INFO [neon.shop] paid\n',
      );
      final withError = format.format(
        _at('failed', error: StateError('boom'), level: SpringLogLevel.error),
      );
      expect(withError, isNot(contains('\x1B')));
      expect(
        withError,
        startsWith('09:05:02.042 ERROR [neon.shop] failed\n'),
      );
      expect(withError, contains('Bad state: boom'));
      expect(withError, endsWith('\n'));
    });

    test('.jsonl: one object a line, exactly its fields', () {
      const format = JsonLinesDebugLogFormat();
      expect(format.extension, 'jsonl');
      final stack = StackTrace.fromString('#0 main (file.dart:1:1)');
      final line = format.format(
        _at(
          'failed',
          error: StateError('boom'),
          stackTrace: stack,
          level: SpringLogLevel.warning,
        ),
      );
      expect(line, endsWith('}\n'));
      expect('\n'.allMatches(line), hasLength(1));
      expect(jsonDecode(line), {
        'time': DateTime(2026, 11, 25, 9, 5, 2, 42).toUtc().toIso8601String(),
        'level': 'WARN',
        'logger': 'neon.shop',
        'message': 'failed',
        'error': 'Bad state: boom',
        'stack': '#0 main (file.dart:1:1)',
      });
      expect((jsonDecode(line) as Map<String, Object?>)['time'], endsWith('Z'));
      expect(jsonDecode(format.format(_at('paid'))), {
        'time': DateTime(2026, 11, 25, 9, 5, 2, 42).toUtc().toIso8601String(),
        'level': 'INFO',
        'logger': 'neon.shop',
        'message': 'paid',
        'error': null,
        'stack': null,
      });
    });

    test('a file is its records, one after the other, UTF-8', () async {
      final export = DebugLogExport(
        formats: const [JsonLinesDebugLogFormat()],
        files: const DebugFileExports([]),
        appName: 'shop',
      );
      final bytes = await export.encode([
        _at('één'),
        _at('two'),
      ], export.format('jsonl'));
      final lines = const LineSplitter().convert(utf8.decode(bytes));
      expect(
        [
          for (final line in lines)
            (jsonDecode(line) as Map<String, Object?>)['message'],
        ],
        ['één', 'two'],
      );
    });
  });

  group('file names', () {
    DebugLogExport named(String app) => DebugLogExport(
      formats: [
        PlainDebugLogFormat(() => LogPattern('%m')),
        const JsonLinesDebugLogFormat(),
      ],
      files: const DebugFileExports([]),
      appName: app,
      clock: () => DateTime(2026, 3, 7, 9, 5, 2),
    );

    test('<app>-logs-<yyyyMMdd-HHmmss>.<ext>', () {
      final export = named('neon_shop');
      expect(
        export.fileName(export.format('log')),
        'neon_shop-logs-20260307-090502.log',
      );
      expect(
        export.fileName(export.format('.jsonl')),
        'neon_shop-logs-20260307-090502.jsonl',
      );
    });

    test('what a file name cannot hold becomes -; nothing left: app', () {
      final export = named(' Neon Shop: Café/2 ');
      expect(
        export.fileName(export.format('log')),
        'Neon-Shop-Caf-2-logs-20260307-090502.log',
      );
      expect(named('///').appName, 'app');
    });

    test('a format it does not have names the others', () {
      expect(
        () => named('shop').format('csv'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('log, jsonl'),
          ),
        ),
      );
    });
  });

  group('the chain of DebugFileExport', () {
    final written = <String>[];
    final downloaded = <String>[];
    List<DebugFileExport> builtIns({required bool web}) => [
      BrowserDebugFileExport(
        web: web,
        download: (name, _, _) => downloaded.add(name),
      ),
      DownloadsDebugFileExport(
        web: web,
        write: (name, _) async {
          written.add(name);
          return '/Users/me/Downloads/$name';
        },
      ),
    ];

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      written.clear();
      downloaded.clear();
    });

    test('the web: a browser download', () async {
      final chain = DebugFileExports(builtIns(web: true));
      expect(chain.current, isA<BrowserDebugFileExport>());
      expect(
        await chain.export('a.log', Uint8List(1), 'text/plain'),
        'Downloaded a.log',
      );
      expect(downloaded, ['a.log']);
    });

    for (final desktop in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test('${desktop.name}: the Downloads folder, its path told', () async {
        debugDefaultTargetPlatformOverride = desktop;
        final chain = DebugFileExports(builtIns(web: false));
        expect(chain.current, isA<DownloadsDebugFileExport>());
        expect(
          await chain.export('a.log', Uint8List(1), 'text/plain'),
          'Saved /Users/me/Downloads/a.log',
        );
        expect(written, ['a.log']);
      });
    }

    for (final phone in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${phone.name}: nothing silently on the clipboard; it '
          'says what to add; the clipboard only when the app adds it', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = phone;
        _clipboard(tester);
        final chain = DebugFileExports(builtIns(web: false));
        expect(chain.current, isNull);
        final told = await chain.export(
          'a.log',
          Uint8List.fromList(utf8.encode('line one\n')),
          'text/plain',
        );
        expect(told, contains('DebugFileExport'));
        expect(_clipboardText, isNull);
        final opted = DebugFileExports([
          ...builtIns(web: false),
          const ClipboardDebugFileExport(),
        ]);
        expect(
          await opted.export(
            'a.log',
            Uint8List.fromList(utf8.encode('line one\n')),
            'text/plain',
          ),
          contains('copied to the clipboard'),
        );
        expect(_clipboardText, 'line one\n');
        debugDefaultTargetPlatformOverride = null;
      });

      test('${phone.name}: an app exporter of an order before them', () async {
        debugDefaultTargetPlatformOverride = phone;
        final share = _Export();
        final chain = DebugFileExports([share, ...builtIns(web: false)]);
        expect(chain.current, same(share));
        expect(
          await chain.export('a.log', Uint8List(1), 'text/plain'),
          'Shared a.log',
        );
      });
    }

    test('one that throws: the next one available takes the file', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final chain = DebugFileExports([
        _Export(fails: true),
        _Export(available: false),
        ...builtIns(web: false),
      ]);
      expect(
        await chain.export('a.log', Uint8List(1), 'text/plain'),
        'Saved /Users/me/Downloads/a.log',
      );
    });

    test('none available, or every one failing: it says so', () async {
      expect(
        await const DebugFileExports([]).export('a', Uint8List(0), 'x'),
        DebugFileExports.noneAvailable,
      );
      expect(
        await DebugFileExports([
          _Export(fails: true),
        ]).export('a', Uint8List(0), 'x'),
        'The export failed: Bad state: full',
      );
    });
  });

  test(
    'a large buffer is made in slices: the event loop keeps its turns',
    () async {
      final records = [
        for (var i = 0; i < 100000; i++)
          SpringLogRecord(
            SpringLogLevel.info,
            'neon.shop.checkout',
            'order $i placed with a few words more to format',
          ),
      ];
      final export = DebugLogExport(
        formats: const [JsonLinesDebugLogFormat()],
        files: const DebugFileExports([]),
        appName: 'shop',
      );
      var turns = 0;
      final timer = Timer.periodic(Duration.zero, (_) => turns++);
      final bytes = await export.encode(records, export.format('jsonl'));
      timer.cancel();
      expect('\n'.allMatches(utf8.decode(bytes)), hasLength(records.length));
      expect(turns, greaterThan(10));
    },
  );

  test('a slice holds the event loop at most its 4 ms, however slow a '
      'record is to format', () async {
    // Each record takes 1 ms: at most 5 between two turns. A loaded
    // machine only makes fewer fit.
    final format = _Slow(const Duration(milliseconds: 1));
    final export = DebugLogExport(
      formats: [format],
      files: const DebugFileExports([]),
      appName: 'shop',
    );
    var most = 0;
    var turns = 0;
    final timer = Timer.periodic(Duration.zero, (_) {
      most = format.sinceTurn > most ? format.sinceTurn : most;
      format.sinceTurn = 0;
      turns++;
    });
    await export.encode([for (var i = 0; i < 200; i++) _at('$i')], format);
    timer.cancel();
    expect(most, inInclusiveRange(1, 5));
    expect(turns, greaterThanOrEqualTo(200 ~/ 5 - 1));
  });

  group('in the tab', () {
    testWidgets('Export .jsonl: the records the filter shows, to the first '
        'exporter, named after the app; what it says shows', (tester) async {
      final share = _Export();
      final context = await _start(
        tester,
        beans: [
          BeanDefinition<_Export>(
            name: 'shareExport',
            types: const [_Export, DebugFileExport, Ordered],
            create: (_) => share,
          ),
        ],
      );
      await _logs(tester, context, ['paid', 'shipped', 'refunded']);
      await tester.enterText(find.byType(EditableText), 'ed');
      await tester.pump();
      await tester.tap(find.text('Export .jsonl'));
      await tester.pump();
      await tester.pump();
      expect(share.files, hasLength(1));
      final (name, bytes, mime) = share.files.single;
      expect(name, matches(RegExp(r'^Neon-Shop-logs-\d{8}-\d{6}\.jsonl$')));
      expect(mime, 'application/jsonl');
      expect(
        [
          for (final line in const LineSplitter().convert(utf8.decode(bytes)))
            (jsonDecode(line) as Map<String, Object?>)['message'],
        ],
        ['shipped', 'refunded'],
      );
      expect(find.text('Shared $name'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Shared $name'), findsNothing);
    });

    testWidgets('Export .log: the marked records alone, as the console '
        'prints them', (tester) async {
      final share = _Export();
      final context = await _start(
        tester,
        beans: [
          BeanDefinition<_Export>(
            name: 'shareExport',
            types: const [_Export, DebugFileExport, Ordered],
            create: (_) => share,
          ),
        ],
      );
      await _logs(tester, context, ['paid', 'shipped', 'refunded']);
      await tester.longPress(_record('refunded'));
      await tester.pump();
      await tester.tap(find.text('Export .log'));
      await tester.pump();
      await tester.pump();
      final text = utf8.decode(share.files.single.$2);
      expect(text, isNot(contains('\x1B')));
      expect(_plainLine.firstMatch(text.trim())?.group(1), 'refunded');
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the build switch', () {
    test('its key, debug builds when not set, inside the '
        "panel's switch or the console's", () {
      expect(
        _build('springBootStarterFlutterDebugLogsExportAutoConfiguration'),
        "AutoConfigurationBuild('spring.flutter.debug.logs.export.enabled', "
        "parents: [AutoConfigurationBuild('spring.flutter.debug.enabled')])",
      );
      expect(
        _build(
          'springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration',
        ),
        "AutoConfigurationBuild('spring.flutter.debug.logs.export.enabled', "
        "parents: [AutoConfigurationBuild('spring.flutter.debug.console.enabled', "
        'whenMissing: BuildInclusion.never)])',
      );
    });

    testWidgets('the panel without its module: no export bean, no button', (
      tester,
    ) async {
      final context = await _start(
        tester,
        debug: [springBootStarterFlutterDebugAutoConfiguration],
      );
      expect(context.getBeansOfType<DebugLogExport>(), isEmpty);
      expect(context.getBeansOfType<DebugFileExport>(), isEmpty);
      expect(context.getBeansOfType<DebugLogFormat>(), isEmpty);
      expect(context.getBeansOfType<DebugFileExports>(), isEmpty);
      await _logs(tester, context, ['paid']);
      expect(find.textContaining('Export'), findsNothing);
    });

    testWidgets('its module without the panel or the console: no bean', (
      tester,
    ) async {
      final context = await _start(
        tester,
        debug: [
          springBootStarterFlutterDebugLogsExportAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration,
        ],
      );
      expect(context.getBeansOfType<DebugLogExport>(), isEmpty);
      expect(context.getBeansOfType<DebugFileExport>(), isEmpty);
    });

    testWidgets('enabled=false in a running app whose build has it: no bean', (
      tester,
    ) async {
      final context = await _start(
        tester,
        properties:
            '$_properties'
            'spring.flutter.debug.logs.export.enabled=false\n',
      );
      expect(context.getBeansOfType<DebugLogExport>(), isEmpty);
      await _logs(tester, context, ['paid']);
      expect(find.textContaining('Export'), findsNothing);
    });

    testWidgets('with the panel: the built-in formats and exports, in order', (
      tester,
    ) async {
      final context = await _start(tester);
      final export = context.getBean<DebugLogExport>();
      expect([for (final f in export.formats) f.extension], ['log', 'jsonl']);
      expect(
        [for (final e in export.files.exports) e.runtimeType],
        [BrowserDebugFileExport, DownloadsDebugFileExport],
      );
      expect(export.appName, 'Neon-Shop');
    });

    testWidgets('with the console alone: the export for its commands', (
      tester,
    ) async {
      final context = await _start(
        tester,
        properties:
            '$_properties'
            'spring.flutter.debug.console.enabled=true\n',
        debug: [
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration,
        ],
      );
      expect(context.getBeansOfType<DebugLogExport>(), hasLength(1));
    });

    testWidgets('with the panel and the console: one of each bean', (
      tester,
    ) async {
      final context = await _start(
        tester,
        properties:
            '$_properties'
            'spring.flutter.debug.console.enabled=true\n',
        debug: [
          springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration,
          springBootStarterFlutterDebugLogsExportAutoConfiguration,
        ],
      );
      expect(context.getBeansOfType<DebugLogExport>(), hasLength(1));
      expect(context.getBeansOfType<DebugFileExport>(), hasLength(2));
      expect(context.getBeansOfType<DebugLogFormat>(), hasLength(2));
    });
  });
}
