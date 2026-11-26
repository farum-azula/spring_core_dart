// The debug console's views of the network recorder: the `network` pane
// (a line per request, newest at the bottom, coloured by the debug theme,
// following the newest until scrolled up, a tap showing one line) and the
// `net` header segment (requests in flight, failed, the last WebSocket
// heartbeat; zeros muted). Each is in the build only when the console's
// list names it, with the console and the recorder switches; in a running
// app it makes the recorder when the panel has not; hidden, nothing
// listens and nothing is drawn.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_web_dart/testing.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

final class _Transport implements HttpTransport {
  @override
  Future<HttpResponse> send(HttpRequest request) async =>
      HttpResponse(200, body: const [1, 2, 3], request: request);

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      throw UnimplementedError();

  @override
  void close() {}
}

final _t0 = DateTime(2026, 11, 25, 12);

HttpExchange _exchange(
  DebugNetworkJournal journal,
  String path, {
  String method = 'GET',
  int? status = 200,
  Duration? total = const Duration(milliseconds: 120),
  int size = 1229,
  bool failed = false,
}) => journal.add(
  HttpExchange(
      id: journal.nextId(),
      url: Uri.parse('https://api.neon.books$path'),
      started: _t0,
      method: method,
      requestHeaders: const [],
      requestSize: 0,
    )
    ..statusCode = status
    ..totalTime = total
    ..responseSize = size
    ..error = failed ? 'connection failed: refused' : null
    ..state = failed
        ? HttpExchangeState.failed
        : total == null
        ? HttpExchangeState.waiting
        : HttpExchangeState.done,
);

DebugNetworkJournal _journal() =>
    DebugNetworkJournal(schedule: (notify) => notify());

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

Future<void> _pumpView(
  WidgetTester tester,
  DebugNetworkJournal journal, {
  bool hasNetworkTab = false,
  double height = 6 * NetworkConsoleView.lineExtent,
}) async {
  tester.view
    ..physicalSize = const Size(800, 600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 600,
          height: height,
          child: NetworkConsoleView(
            journal: journal,
            hasNetworkTab: hasNetworkTab,
          ),
        ),
      ),
    ),
  );
}

Color? _color(WidgetTester tester, Finder line, String text) => tester
    .widget<Text>(find.descendant(of: line, matching: find.text(text)))
    .style
    ?.color;

void main() {
  group('the build switches', () {
    test('the pane: named in panes, inside the console and the recorder', () {
      expect(
        _build(
          'springBootStarterFlutterDebugConsoleNetworkPaneAutoConfiguration',
        ),
        "AutoConfigurationBuild.named('spring.flutter.debug.console.panes', "
        "'network', whenMissing: BuildInclusion.never, parents: ["
        "AutoConfigurationBuild('spring.flutter.debug.console.enabled', "
        'whenMissing: BuildInclusion.never), '
        "AutoConfigurationBuild('spring.flutter.debug.network.enabled', "
        'whenMissing: BuildInclusion.never)])',
      );
    });

    test('the segment: named in segments, inside the console and the '
        'recorder', () {
      expect(
        _build(
          'springBootStarterFlutterDebugConsoleNetworkSegmentAutoConfiguration',
        ),
        "AutoConfigurationBuild.named('spring.flutter.debug.console.segments', "
        "'net', whenMissing: BuildInclusion.never, parents: ["
        "AutoConfigurationBuild('spring.flutter.debug.console.enabled', "
        'whenMissing: BuildInclusion.never), '
        "AutoConfigurationBuild('spring.flutter.debug.network.enabled', "
        'whenMissing: BuildInclusion.never)])',
      );
    });
  });

  group('in a running app', () {
    final http = _Transport();
    final sockets = MockWebSocketTransport();

    Future<ApplicationContext> start(
      WidgetTester tester, {
      String properties = '',
      bool panel = false,
      bool pane = true,
      bool segment = true,
    }) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => SpringApplication(
            [
              BeanModule(
                'test',
                [
                  BeanDefinition<HttpTransport>(
                    name: 'httpTransport',
                    create: (_) => http,
                  ),
                  BeanDefinition<WebSocketTransport>(
                    name: 'webSocketTransport',
                    create: (_) => sockets,
                  ),
                ],
                resources: {
                  'application.properties': EmbeddedResource.text(
                    'spring.flutter.app.type=widgets\n'
                    'spring.flutter.debug.console.panes=network\n'
                    'spring.flutter.debug.console.segments=fps,net\n'
                    '$properties',
                  ),
                },
              ),
            ],
            autoConfigurations: [
              springBootStarterFlutterAutoConfiguration,
              if (panel) ...[
                springBootStarterFlutterDebugAutoConfiguration,
                springBootStarterFlutterDebugNetworkAutoConfiguration,
              ],
              springBootStarterFlutterDebugConsoleAutoConfiguration,
              springBootStarterFlutterDebugConsoleFpsAutoConfiguration,
              if (pane)
                springBootStarterFlutterDebugConsoleNetworkPaneAutoConfiguration,
              if (segment)
                springBootStarterFlutterDebugConsoleNetworkSegmentAutoConfiguration,
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

    testWidgets('the console alone makes the recorder: the transports are '
        'recorded, the pane and the segment read one journal', (tester) async {
      final context = await start(tester);
      final transport = context.getBean<HttpTransport>();
      expect(transport, isA<RecordingHttpTransport>());
      expect(
        context.getBean<WebSocketTransport>(),
        isA<RecordingWebSocketTransport>(),
      );
      final journal = context.getBean<DebugNetworkJournal>();
      final console = context.getBean<DebugConsole>();
      expect(console.namedPanes.keys, contains('network'));
      expect(console.namedSegments.keys, ['fps', 'net']);
      final pane = console.namedPanes['network']! as NetworkConsolePane;
      expect(pane.journal, same(journal));
      expect(pane.hasNetworkTab, isFalse, reason: 'no panel');
      expect(
        (console.namedSegments['net']! as NetworkConsoleSegment).journal,
        same(journal),
      );
      expect(context.getBeansOfType<DebugNetworkRecorder>(), hasLength(1));

      await tester.runAsync(
        () => transport.send(
          HttpRequest(
            method: HttpMethod.get,
            url: Uri.parse('https://api.neon.books/books'),
          ),
        ),
      );
      console
        ..showPane('network', shown: true)
        ..shown = true;
      await tester.pump();
      await tester.pump();
      expect(find.text('/books'), findsOneWidget);
      final header = tester
          .widget<Text>(find.byKey(const ValueKey('debug-console-header')))
          .textSpan!
          .toPlainText()
          .replaceAll(' ', ' ');
      expect(header, contains('net 0 in flight · 0 failed · 0 errors'));
    });

    testWidgets('with the panel too: one recorder and journal, and the pane '
        'hints to the Network tab', (tester) async {
      final context = await start(tester, panel: true);
      expect(context.getBeansOfType<DebugNetworkRecorder>(), hasLength(1));
      expect(context.getBeansOfType<DebugNetworkJournal>(), hasLength(1));
      final pane =
          context.getBean<DebugConsole>().namedPanes['network']!
              as NetworkConsolePane;
      expect(pane.hasNetworkTab, isTrue);
      expect(
        pane.journal,
        same(context.getBean<DebugNetworkSection>().journal),
      );
    });

    testWidgets('the segment alone also makes the recorder', (tester) async {
      final context = await start(tester, pane: false);
      expect(context.getBean<HttpTransport>(), isA<RecordingHttpTransport>());
      expect(context.getBeansOfType<NetworkConsolePane>(), isEmpty);
    });

    testWidgets('neither module: no recorder, the transports as they are', (
      tester,
    ) async {
      final context = await start(
        tester,
        pane: false,
        segment: false,
        properties: 'spring.flutter.debug.console.segments=fps\n',
      );
      expect(context.getBean<HttpTransport>(), same(http));
      expect(context.containsBean('debugNetworkJournal'), isFalse);
    });

    testWidgets('network.enabled=false in a running app: none of them', (
      tester,
    ) async {
      final context = await start(
        tester,
        properties:
            'spring.flutter.debug.network.enabled=false\n'
            'spring.flutter.debug.console.segments=fps\n'
            'spring.flutter.debug.console.panes=\n',
      );
      expect(context.getBean<HttpTransport>(), same(http));
      expect(context.getBeansOfType<NetworkConsolePane>(), isEmpty);
      expect(context.getBeansOfType<NetworkConsoleSegment>(), isEmpty);
    });

    testWidgets('hidden, nothing listens: a change schedules no frame; '
        'shown, at most one; hidden again, none', (tester) async {
      final context = await start(tester);
      final journal = context.getBean<DebugNetworkJournal>();
      final console = context.getBean<DebugConsole>();
      for (var i = 0; i < 20; i++) {
        _exchange(journal, '/$i');
      }
      expect(tester.binding.hasScheduledFrame, isFalse);

      console
        ..showPane('network', shown: true)
        ..showSegment('net', shown: true)
        ..shown = true;
      await tester.pump();
      await tester.pump();
      expect(find.byType(NetworkConsoleView), findsOneWidget);
      var heard = 0;
      void count() => heard++;
      journal.addListener(count);
      for (var i = 0; i < 20; i++) {
        _exchange(journal, '/more$i');
      }
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(heard, 1, reason: 'twenty changes, one redraw');
      expect(find.text('/more19'), findsOneWidget);
      journal.removeListener(count);

      console.showPane('network', shown: false);
      await tester.pump();
      expect(find.byType(NetworkConsoleView), findsNothing);
      console.shown = false;
      await tester.pump();
      await tester.pump();
      _exchange(journal, '/hidden');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('the pane', () {
    testWidgets('a line per request, newest at the bottom: method, path, '
        'status, time, size', (tester) async {
      final journal = _journal();
      _exchange(journal, '/api/user');
      _exchange(journal, '/api/cart', method: 'POST', status: 201);
      await _pumpView(tester, journal);

      final user = find.byKey(NetworkConsoleView.lineKey(1));
      final cart = find.byKey(NetworkConsoleView.lineKey(2));
      for (final text in ['GET', '/api/user', '200', '120 ms', '1.2 KB']) {
        expect(
          find.descendant(of: user, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(
        tester.getTopLeft(cart).dy,
        greaterThan(tester.getTopLeft(user).dy),
      );
      expect(find.byKey(NetworkConsoleView.statusKey), findsNothing);
    });

    testWidgets("the debug theme's colours: methods, statuses, a slow time", (
      tester,
    ) async {
      final journal = _journal();
      _exchange(journal, '/ok');
      _exchange(journal, '/missing', method: 'POST', status: 404);
      _exchange(
        journal,
        '/broken',
        method: 'DELETE',
        status: 500,
        total: const Duration(milliseconds: 1200),
      );
      _exchange(journal, '/down', status: null, failed: true);
      _exchange(journal, '/waiting', total: null, status: null);
      await _pumpView(tester, journal);
      final style = DebugStyle.of(tester.element(find.text('/ok')));
      Finder line(int id) => find.byKey(NetworkConsoleView.lineKey(id));

      expect(_color(tester, line(1), 'GET'), style.methodRead);
      expect(_color(tester, line(2), 'POST'), style.methodWrite);
      expect(_color(tester, line(1), '200'), style.good);
      expect(_color(tester, line(2), '404'), style.warning);
      expect(_color(tester, line(3), '500'), style.bad);
      expect(_color(tester, line(4), 'ERR'), style.bad);
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: line(5), matching: find.text('…')),
            )
            .map((text) => text.style?.color),
        everyElement(style.muted),
        reason: 'pending',
      );
      expect(_color(tester, line(1), '120 ms'), style.muted);
      expect(_color(tester, line(3), '1.20 s'), style.warning);
    });

    testWidgets('a WebSocket: one line with its uptime and last heartbeat', (
      tester,
    ) async {
      final journal = _journal();
      final sockets = MockWebSocketTransport();
      await tester.runAsync(() async {
        final session = await RecordingWebSocketTransport(
          sockets,
          journal,
        ).connect(Uri.parse('wss://rt.neon.books/socket'));
        session.messages.listen((_) {});
        session.sendMessage('[null,"1","phoenix","heartbeat",{}]');
        sockets.lastConnection.push('[null,"1","phoenix","phx_reply",{}]');
        await Future<void>.delayed(Duration.zero);
      });
      await _pumpView(tester, journal);
      final line = find.byKey(NetworkConsoleView.lineKey(1));
      expect(
        find.descendant(of: line, matching: find.text('WS')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('0 s')),
        findsOneWidget,
        reason: 'the uptime',
      );
      expect(
        find.descendant(of: line, matching: find.textContaining(' ms ws')),
        findsOneWidget,
        reason: 'the last heartbeat',
      );
    });

    testWidgets('a tap shows the line in one line, with the hint to the '
        'Network tab; a second tap hides it', (tester) async {
      final journal = _journal();
      _exchange(journal, '/api/user');
      _exchange(journal, '/down', status: null, failed: true);
      await _pumpView(tester, journal, hasNetworkTab: true);

      await tester.tap(find.text('/down'));
      await tester.pump();
      final status = tester.widget<Text>(
        find.byKey(NetworkConsoleView.statusKey),
      );
      expect(status.maxLines, 1);
      expect(
        status.data,
        'GET https://api.neon.books/down · ERR · total 120 ms · sent 0 B · '
        'received 1.2 KB · connection failed: refused · more in the '
        "panel's Network tab",
      );
      await tester.tap(find.text('/down'));
      await tester.pump();
      expect(find.byKey(NetworkConsoleView.statusKey), findsNothing);
    });

    testWidgets('follows the newest; scrolled up it keeps the lines read and '
        'says it is paused; back at the bottom it follows again', (
      tester,
    ) async {
      final journal = _journal();
      for (var i = 0; i < 30; i++) {
        _exchange(journal, '/r$i');
      }
      await _pumpView(tester, journal);
      expect(find.text('/r29'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 60));
      await tester.pump();
      final paused = tester.widget<Text>(
        find.byKey(NetworkConsoleView.statusKey),
      );
      expect(paused.data, 'paused: scroll to the bottom to follow');
      _exchange(journal, '/new');
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byKey(NetworkConsoleView.statusKey), findsNothing);
      expect(find.text('/new'), findsOneWidget);
    });

    testWidgets('scrolled up, a new request does not move the lines read', (
      tester,
    ) async {
      final journal = _journal();
      for (var i = 0; i < 30; i++) {
        _exchange(journal, '/r$i');
      }
      await _pumpView(tester, journal);
      await tester.drag(find.byType(ListView), const Offset(0, 60));
      await tester.pump();
      final shown = [
        for (final element in find.byType(Text).evaluate())
          (element.widget as Text).data,
      ];
      _exchange(journal, '/new');
      await tester.pump();
      expect(find.text('/new'), findsNothing);
      expect([
        for (final element in find.byType(Text).evaluate())
          (element.widget as Text).data,
      ], shown);
    });

    testWidgets('nothing yet', (tester) async {
      await _pumpView(tester, _journal());
      expect(find.text('No requests yet'), findsOneWidget);
    });
  });

  group('the segment', () {
    test(
      'zeros muted; in flight a number, failures red, 4xx and 5xx '
      'amber errors; the last heartbeat when an open WebSocket has one',
      () async {
        final journal = _journal();
        final segment = NetworkConsoleSegment(journal);
        expect(
          segment.read(),
          const DebugConsoleValue.of([
            DebugConsoleValue(
              '0',
              unit: 'in flight',
              tone: DebugConsoleTone.muted,
            ),
            DebugConsoleValue(
              '0',
              unit: 'failed',
              tone: DebugConsoleTone.muted,
            ),
            DebugConsoleValue(
              '0',
              unit: 'errors',
              tone: DebugConsoleTone.muted,
            ),
          ], label: 'net'),
        );
        expect('${segment.read()}', 'net 0 in flight · 0 failed · 0 errors');

        _exchange(journal, '/a', total: null, status: null);
        _exchange(journal, '/b', total: null, status: null);
        _exchange(journal, '/c', status: 503);
        _exchange(journal, '/d', status: null, failed: true);
        final sockets = MockWebSocketTransport();
        final session = await RecordingWebSocketTransport(
          sockets,
          journal,
        ).connect(Uri.parse('wss://a.neon/ws'));
        session.messages.listen((_) {});
        session.sendMessage('[null,"1","phoenix","heartbeat",{}]');
        sockets.lastConnection.push('[null,"1","phoenix","phx_reply",{}]');
        await Future<void>.delayed(Duration.zero);

        final value = segment.read();
        expect(value.parts.map((p) => p.tone), [
          DebugConsoleTone.number,
          DebugConsoleTone.bad,
          DebugConsoleTone.warning,
          DebugConsoleTone.number,
        ]);
        expect(
          '$value',
          matches(
            RegExp(r'^net 2 in flight · 1 failed · 1 error · \d+ ms ws$'),
          ),
        );
      },
    );

    test('a 403 is a response: an error, not failed', () {
      final journal = _journal();
      final segment = NetworkConsoleSegment(journal);
      _exchange(journal, '/private', status: 403);
      expect(journal.summary.failed, 0);
      expect(journal.summary.errors, 1);
      expect('${segment.read()}', 'net 0 in flight · 0 failed · 1 error');
    });

    test('listens only while started', () {
      final journal = _journal();
      final segment = NetworkConsoleSegment(journal);
      var heard = 0;
      final stop = segment.start(() => heard++);
      _exchange(journal, '/a');
      expect(heard, 1);
      stop();
      _exchange(journal, '/b');
      expect(heard, 1);
    });
  });
}
