// The debug console's header: the segments the build has (`segments`), of
// which `header` shows some, in its order (`*` for every other one; a
// name `segments` does not have fails the start); shown, hidden and moved
// while the app runs; numbers in the theme's primary colour and
// states green, amber or red; the segments started only while the console
// shows, read again at most once a frame however often they change; a
// segment with nothing to show (`scene-fps` without a scene) left out.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

// A segment of a test: counts its starts, stops and reads; [changed] calls
// back as the segment's own would.
// Registered as a plain bean, without `@ConsoleSegment`: named by its
// getter.
final class _Probe extends DebugConsoleSegment {
  _Probe(this.name, this.value);

  @override
  final String name;

  DebugConsoleValue? value;
  int starts = 0;
  int stops = 0;
  int reads = 0;
  void Function()? changed;

  @override
  void Function() start(void Function() changed) {
    starts++;
    this.changed = changed;
    return () {
      stops++;
      this.changed = null;
    };
  }

  @override
  DebugConsoleValue? read() {
    reads++;
    return value;
  }
}

Future<ApplicationContext> _start(
  WidgetTester tester, {
  String properties = '',
  List<_Probe> probes = const [],
  Map<_Probe, ConsoleSegment> annotations = const {},
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              for (final probe in probes)
                BeanDefinition<_Probe>(
                  name: 'probe-${probe.name}',
                  types: const [_Probe, DebugConsoleSegment],
                  annotations: [?annotations[probe]],
                  create: (_) => probe,
                ),
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n'
                'spring.flutter.debug.console.slide-duration=0\n'
                '$properties',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootAutoConfiguration,
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleFpsAutoConfiguration,
          springBootStarterFlutterDebugConsoleFramesLostAutoConfiguration,
          springBootStarterFlutterDebugConsoleFilterAutoConfiguration,
          springBootStarterFlutterDebugConsoleIsolatesAutoConfiguration,
          springBootStarterFlutterDebugConsoleTimelineAutoConfiguration,
          springBootStarterFlutterDebugIsolatesAutoConfiguration,
          springBootStarterFlutterDebugTimelineAutoConfiguration,
          springBootStarterLoggingAutoConfiguration,
        ],
        bannerMode: BannerMode.off,
      ),
      home: const _Home(),
    ),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(_Home)));
  addTearDown(context.getBean<LogBuffer>().clear);
  return context;
}

final _header = find.byKey(const ValueKey('debug-console-header'));

// The header's text, its unbreakable spaces read as spaces.
String _text(WidgetTester tester) => tester
    .widget<Text>(_header)
    .textSpan!
    .toPlainText()
    .replaceAll('\u00A0', ' ');

// The span of the header whose text is [text].
TextSpan _span(WidgetTester tester, String text) {
  TextSpan? found;
  tester.widget<Text>(_header).textSpan!.visitChildren((span) {
    if (span is TextSpan && span.text?.replaceAll('\u00A0', ' ') == text) {
      found = span;
      return false;
    }
    return true;
  });
  return found!;
}

void main() {
  testWidgets('by default: fps, frames lost and the filter, in that order; '
      'no scene-fps without the scene starter', (tester) async {
    final context = await _start(tester);
    final console = context.getBean<DebugConsole>();
    expect(console.namedSegments.keys, ['fps', 'frames-lost', 'filter']);
    console.shown = true;
    await tester.pump();
    expect(_text(tester), 'fps idle  lost 0  logs all');
  });

  testWidgets('too narrow for one line: wrapped between segments, never '
      'inside one, nothing cut', (tester) async {
    tester.view
      ..physicalSize = const Size(200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final context = await _start(tester);
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    final header = tester.widget<Text>(_header);
    expect(header.maxLines, isNull);
    expect(header.overflow, isNull);
    expect(tester.getSize(_header).height, greaterThan(20));
    final plain = header.textSpan!.toPlainText();
    expect(plain, contains('lost\u00A00'));
    expect(plain, contains('logs\u00A0all'));
  });

  testWidgets('segments picks the build\'s by name, in its order; * '
      'stands for the others, in their order; a name no segment has is left '
      'out; the header shows them all when not set', (tester) async {
    final ping = _Probe('ping', const DebugConsoleValue('42', label: 'ping'));
    final pong = _Probe('pong', const DebugConsoleValue('7', label: 'pong'));
    var context = await _start(
      tester,
      probes: [ping, pong],
      properties: 'spring.flutter.debug.console.segments=filter,nothing,ping',
    );
    var console = context.getBean<DebugConsole>();
    expect(console.namedSegments.keys, ['filter', 'ping']);
    expect(console.header, ['filter', 'ping']);
    await tester.pumpWidget(const SizedBox());

    context = await _start(
      tester,
      probes: [ping, pong],
      properties: 'spring.flutter.debug.console.segments=pong,*',
    );
    console = context.getBean<DebugConsole>();
    expect(
      console.namedSegments.keys,
      // The application's first, as it registers its beans first; then
      // the framework's, a module each, in their modules' order.
      ['pong', 'ping', 'filter', 'fps', 'frames-lost', 'isolates', 'timeline'],
    );
    expect(console.header, console.namedSegments.keys);
  });

  testWidgets('the isolates and timeline segments leave with the task '
      'manager and the timeline turned off in a running app', (tester) async {
    final context = await _start(
      tester,
      properties:
          'spring.flutter.debug.console.segments=*\n'
          'spring.flutter.debug.isolates.enabled=false\n'
          'spring.flutter.debug.timeline.enabled=false',
    );
    expect(context.getBeansOfType<IsolatesSegment>(), isEmpty);
    expect(context.getBeansOfType<TimelineSegment>(), isEmpty);
    expect(
      context.getBean<DebugConsole>().namedSegments.keys,
      ['filter', 'fps', 'frames-lost'],
    );
  });

  testWidgets('header shows some of them, in its order; the others are in '
      'the build, hidden, and measure nothing', (tester) async {
    final ping = _Probe('ping', const DebugConsoleValue('42', label: 'ping'));
    final pong = _Probe('pong', const DebugConsoleValue('7', label: 'pong'));
    final context = await _start(
      tester,
      probes: [ping, pong],
      properties:
          'spring.flutter.debug.console.segments=fps,ping,pong\n'
          'spring.flutter.debug.console.header=pong,fps',
    );
    final console = context.getBean<DebugConsole>()..shown = true;
    await tester.pump();
    expect(console.namedSegments.keys, ['fps', 'ping', 'pong']);
    expect(console.header, ['pong', 'fps']);
    expect(console.segmentOrder, ['pong', 'fps', 'ping']);
    expect(_text(tester), 'pong 7  fps idle');
    expect(ping.starts, 0, reason: 'hidden');
    expect(pong.starts, 1);

    console.showSegment('ping');
    await tester.pump();
    expect(_text(tester), 'pong 7  fps idle  ping 42');
    expect(ping.starts, 1);

    console.moveSegment('ping', -2);
    await tester.pump();
    expect(console.header, ['ping', 'pong', 'fps']);
    expect(_text(tester), 'ping 42  pong 7  fps idle');

    console.showSegment('pong', shown: false);
    await tester.pump();
    expect(_text(tester), 'ping 42  fps idle');
    expect(pong.stops, 1, reason: 'a hidden segment measures nothing');
  });

  testWidgets('a header name that segments does not have fails the start, '
      'naming both keys', (tester) async {
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
                  'spring.flutter.debug.console.segments=fps\n'
                  'spring.flutter.debug.console.header=fps,isolates',
                ),
              },
            ),
          ],
          autoConfigurations: [
            springBootStarterFlutterAutoConfiguration,
            springBootStarterFlutterDebugConsoleAutoConfiguration,
            springBootStarterFlutterDebugConsoleFpsAutoConfiguration,
            springBootStarterLoggingAutoConfiguration,
          ],
          bannerMode: BannerMode.off,
        ),
        home: const _Home(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(_Home), findsNothing);
    final failure = tester.takeException().toString() + _failures(tester);
    expect(
      failure,
      contains(
        "spring.flutter.debug.console.header names 'isolates', which "
        'spring.flutter.debug.console.segments does not have',
      ),
    );
  });

  testWidgets("a number in the theme's primary colour, a state green, amber "
      'or red, a label muted', (tester) async {
    final number = _Probe('n', const DebugConsoleValue('42', label: 'n'));
    final good = _Probe(
      'g',
      const DebugConsoleValue('ok', tone: DebugConsoleTone.good),
    );
    final warning = _Probe(
      'w',
      const DebugConsoleValue('slow', tone: DebugConsoleTone.warning),
    );
    final bad = _Probe(
      'b',
      const DebugConsoleValue('lost', tone: DebugConsoleTone.bad),
    );
    final context = await _start(
      tester,
      probes: [number, good, warning, bad],
      properties: 'spring.flutter.debug.console.segments=n,g,w,b',
    );
    context.getBean<DebugConsole>().shown = true;
    await tester.pump();
    final style = DebugStyle.of(tester.element(_header));
    expect(_span(tester, '42').style!.color, style.number);
    expect(_span(tester, '42').style!.fontWeight, FontWeight.bold);
    expect(_span(tester, 'n ').style!.color, style.muted);
    expect(_span(tester, 'ok').style!.color, style.good);
    expect(_span(tester, 'slow').style!.color, style.warning);
    expect(_span(tester, 'lost').style!.color, style.bad);
  });

  testWidgets('started only while shown; many changes, one read a frame; '
      'nothing to show is left out', (tester) async {
    final ping = _Probe('ping', const DebugConsoleValue('1', label: 'ping'));
    final empty = _Probe('empty', null);
    final context = await _start(
      tester,
      probes: [ping, empty],
      properties: 'spring.flutter.debug.console.segments=ping,empty',
    );
    final console = context.getBean<DebugConsole>();
    expect(ping.starts, 0, reason: 'hidden: not started');
    expect(ping.reads, 0);

    console.shown = true;
    await tester.pump();
    expect(ping.starts, 1);
    expect(_text(tester), 'ping 1');
    final reads = ping.reads;

    ping.value = const DebugConsoleValue('2', label: 'ping');
    for (var i = 0; i < 100; i++) {
      ping.changed!();
    }
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(ping.reads, reads + 1, reason: 'one read for 100 changes');
    expect(_text(tester), 'ping 2');
    expect(tester.binding.hasScheduledFrame, isFalse);

    console.shown = false;
    await tester.pump();
    expect(ping.stops, 1, reason: 'hidden again: stopped');
    expect(empty.stops, 1);
  });

  testWidgets('frames-lost: green without a lost frame', (tester) async {
    final frames = FrameStats();
    final segment = FramesLostSegment(frames);
    final stop = segment.start(() {});
    addTearDown(stop);
    expect(
      segment.read(),
      const DebugConsoleValue('0', label: 'lost', tone: DebugConsoleTone.good),
    );
    expect(
      FpsSegment(frames).read(),
      const DebugConsoleValue(
        'idle',
        label: 'fps',
        tone: DebugConsoleTone.text,
      ),
    );
  });

  test('the filter: its level and text', () {
    final filter = DebugLogFilter(level: SpringLogLevel.warning, text: 'cart');
    expect(
      FilterSegment(filter).read().toString(),
      'logs warning "cart"',
    );
  });

  testWidgets('a sampled segment tells only of a new value', (tester) async {
    var value = 1;
    final segment = _Sampled(() => value);
    var changes = 0;
    final stop = segment.start(() => changes++);
    await tester.pump(const Duration(seconds: 1));
    expect(changes, 0);
    value = 2;
    await tester.pump(const Duration(milliseconds: 300));
    expect(changes, 1);
    stop();
    value = 3;
    await tester.pump(const Duration(seconds: 1));
    expect(changes, 1, reason: 'stopped');
  });

  testWidgets("the annotation's name, else the getter; a getter that "
      'disagrees with the annotation fails the start', (tester) async {
    final annotated = _Probe('ping', const DebugConsoleValue('1'));
    final context = await _start(
      tester,
      probes: [annotated],
      annotations: {annotated: const ConsoleSegment('ping')},
      properties: 'spring.flutter.debug.console.segments=ping',
    );
    expect(context.getBean<DebugConsole>().namedSegments.keys, ['ping']);
    await tester.pumpWidget(const SizedBox());

    final wrong = _Probe('pong', const DebugConsoleValue('1'));
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => SpringApplication(
          [
            BeanModule(
              'test',
              [
                BeanDefinition<_Probe>(
                  name: 'wrong',
                  types: const [_Probe, DebugConsoleSegment],
                  annotations: const [ConsoleSegment('ping')],
                  create: (_) => wrong,
                ),
              ],
              resources: {
                'application.properties': EmbeddedResource.text(
                  'spring.flutter.app.type=widgets',
                ),
              },
            ),
          ],
          autoConfigurations: [
            springBootStarterFlutterAutoConfiguration,
            springBootStarterFlutterDebugConsoleAutoConfiguration,
            springBootStarterLoggingAutoConfiguration,
          ],
          bannerMode: BannerMode.off,
        ),
        home: const _Home(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(_Home), findsNothing);
    expect(
      tester.takeException().toString() + _failures(tester),
      contains("named 'ping' by its annotation and 'pong' by its name getter"),
    );
  });
}

// The text the failed start shows.
String _failures(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join('\n');

final class _Sampled extends SampledDebugConsoleSegment {
  _Sampled(this.value);

  final int Function() value;

  @override
  DebugConsoleValue read() => DebugConsoleValue('${value()}');
}
