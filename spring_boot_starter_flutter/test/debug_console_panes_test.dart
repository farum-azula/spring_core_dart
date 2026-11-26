// The debug console's panes: the shown panes by their order under the
// header, the `logs` pane on top max-lines high, each its own height (the
// commands pane six lines and its input), a divider between neighbours; a
// hidden pane not built, not started, its place given to the next; with
// none shown the header alone, without a handle; the handle on the lower edge stretching and shrinking the
// lowest, by touch and by mouse; a divider moving the room between its
// two neighbours only; each at least its least, the console within the
// screen; the heights kept while the app runs; taps on the panes still the
// app's; a shown pane the build does not have failing the start; the
// console's background behind the header and every shown pane, a pane's
// own opacity when it gives one.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class _Home extends StatelessWidget {
  const _Home(this.onTap);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: const SizedBox.expand(),
  );
}

// A pane of a test, registered with `@ConsolePane` in its bean definition:
// counts its starts, stops and builds.
final class _Probe extends DebugConsolePane {
  _Probe(
    this.title, {
    this.initialHeight = 2 * _line,
    this.backgroundOpacity,
  });

  @override
  final String title;

  @override
  final double initialHeight;

  @override
  final double? backgroundOpacity;

  int starts = 0;
  int stops = 0;
  int builds = 0;

  @override
  void Function() start() {
    starts++;
    return () => stops++;
  }

  @override
  Widget build(BuildContext context, DebugConsole console) {
    builds++;
    return Text(title, style: DebugStyle.of(context).code);
  }
}

Future<DebugConsole> _start(
  WidgetTester tester, {
  String panes = 'logs,commands',
  String shown = 'logs,commands',
  Map<String, (int, _Probe)> probes = const {},
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              for (final MapEntry(key: name, value: (order, probe))
                  in probes.entries)
                BeanDefinition<_Probe>(
                  name: '${name}Pane',
                  types: const [_Probe, DebugConsolePane],
                  annotations: [ConsolePane(name, order: order)],
                  create: (_) => probe,
                ),
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                'spring.flutter.app.type=widgets\n'
                'spring.flutter.debug.console.enabled=true\n'
                'spring.flutter.debug.console.max-lines=4\n'
                'spring.flutter.debug.console.slide-duration=0\n'
                'spring.flutter.debug.console.panes=$panes\n'
                'spring.flutter.debug.console.shown-panes=$shown\n',
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterDebugConsoleAutoConfiguration,
          springBootStarterFlutterDebugConsoleLogsAutoConfiguration,
          springBootStarterFlutterDebugConsoleCommandsAutoConfiguration,
          springBootStarterLoggingAutoConfiguration,
        ],
        bannerMode: BannerMode.off,
      ),
      home: _Home(onTap ?? () {}),
    ),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(_Home)));
  addTearDown(context.getBean<LogBuffer>().clear);
  final console = context.getBean<DebugConsole>()..shown = true;
  await tester.pump();
  return console;
}

const _line = DebugConsoleView.lineHeight;
const _input = DebugConsoleInputField.height;
final _console = find.byKey(const ValueKey('debug-console'));
final _logs = find.byKey(const ValueKey('debug-console-logs'));
final _commands = find.byKey(const ValueKey('debug-console-pane-commands'));
final _output = find.byKey(const ValueKey('debug-console-commands'));
final _handle = find.byKey(const ValueKey('debug-console-handle'));
final _divider = find.byKey(const ValueKey('debug-console-divider-commands'));

Finder _pane(String name) => find.byKey(ValueKey('debug-console-pane-$name'));

Finder _background(String part) =>
    find.byKey(ValueKey('debug-console-background-$part'));

Finder _dividerOf(String name) =>
    find.byKey(ValueKey('debug-console-divider-$name'));

double _height(WidgetTester tester, Finder finder) =>
    tester.getSize(finder).height;

// A drag of [handle] by [dy], in small moves, by [kind].
Future<void> _drag(
  WidgetTester tester,
  Finder handle,
  double dy, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(handle),
    kind: kind,
  );
  const steps = 4;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('max-lines high at the start; the commands pane six lines '
      'and its input', (
    tester,
  ) async {
    final console = await _start(tester);
    expect(_height(tester, _logs), 4 * _line);
    expect(_height(tester, _commands), 6 * _line + _input);
    expect(console.paneHeight('logs'), 4 * _line);
    expect(console.paneHeight('commands'), 6 * _line + _input);
    expect(
      console.size.height,
      closeTo(_height(tester, _console), 0.01),
      reason: 'what the dock counts',
    );
  });

  testWidgets('stacked under the logs by their order, whatever shown-panes '
      'says; a divider above each', (tester) async {
    final alpha = _Probe('Alpha');
    final zeta = _Probe('Zeta');
    final console = await _start(
      tester,
      panes: '*',
      shown: 'zeta,commands,alpha,logs',
      probes: {'zeta': (20, zeta), 'alpha': (5, alpha)},
    );
    expect(console.namedPanes.keys, ['logs', 'alpha', 'commands', 'zeta']);
    expect(console.panes, ['logs', 'alpha', 'commands', 'zeta']);
    final tops = [
      for (final finder in [_logs, _pane('alpha'), _commands, _pane('zeta')])
        tester.getTopLeft(finder).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    for (final name in ['alpha', 'commands', 'zeta']) {
      expect(_dividerOf(name), findsOneWidget, reason: name);
    }
    expect(
      tester.getBottomLeft(_logs).dy,
      lessThanOrEqualTo(tester.getTopLeft(_dividerOf('alpha')).dy),
    );
    expect(alpha.starts, 1);
    expect(zeta.starts, 1);
    expect(
      console.size.height,
      closeTo(_height(tester, _console), 0.01),
      reason: 'what the dock counts',
    );
  });

  testWidgets('a hidden pane is not built nor started, and the next moves '
      'up; shown again it is started and keeps its height', (tester) async {
    final alpha = _Probe('Alpha');
    final console = await _start(
      tester,
      panes: 'logs,alpha,commands',
      shown: 'logs,alpha,commands',
      probes: {'alpha': (5, alpha)},
    );
    final alphaTop = tester.getTopLeft(_dividerOf('alpha')).dy;
    final total = _height(tester, _console);
    await _drag(tester, _dividerOf('commands'), -_line);
    expect(console.paneHeight('alpha'), _line);

    console.showPane('alpha', shown: false);
    await tester.pump();
    expect(_pane('alpha'), findsNothing);
    expect(find.text('Alpha'), findsNothing);
    expect(alpha.stops, 1);
    final builds = alpha.builds;
    expect(tester.getTopLeft(_divider).dy, alphaTop, reason: 'moved up');
    expect(console.panes, ['logs', 'commands']);
    expect(_height(tester, _console), lessThan(total), reason: 'freed');
    expect(console.size.height, closeTo(_height(tester, _console), 0.01));

    console.shown = false;
    await tester.pump();
    console.shown = true;
    await tester.pump();
    expect(alpha.builds, builds, reason: 'hidden costs nothing');
    expect(alpha.starts, 1);

    console.showPane('alpha');
    await tester.pump();
    expect(alpha.starts, 2);
    expect(_height(tester, _pane('alpha')), _line, reason: 'its height');
  });

  testWidgets('the console hidden stops its panes', (tester) async {
    final alpha = _Probe('Alpha');
    final console = await _start(
      tester,
      panes: 'alpha',
      shown: 'alpha',
      probes: {'alpha': (5, alpha)},
    );
    expect((alpha.starts, alpha.stops), (1, 0));
    console.shown = false;
    await tester.pump();
    expect((alpha.starts, alpha.stops), (1, 1));
  });

  testWidgets('the lower edge stretches the lowest pane by touch, shrinks '
      'it by mouse, never under its least', (tester) async {
    final console = await _start(tester);
    final top = tester.getTopLeft(_console).dy;
    await _drag(tester, _handle, 3 * _line);
    expect(console.paneHeight('commands'), 9 * _line + _input);
    expect(_height(tester, _commands), 9 * _line + _input);
    expect(_height(tester, _logs), 4 * _line, reason: 'the logs stay');
    expect(tester.getTopLeft(_console).dy, top, reason: 'grows downwards');
    expect(console.size.height, closeTo(_height(tester, _console), 0.01));

    await _drag(tester, _handle, -2 * _line, kind: PointerDeviceKind.mouse);
    expect(console.paneHeight('commands'), 7 * _line + _input);

    await _drag(tester, _handle, -40 * _line, kind: PointerDeviceKind.mouse);
    expect(console.paneHeight('commands'), _line + _input);
  });

  testWidgets('the logs alone: no divider; the edge stretches them, never '
      'under a line', (tester) async {
    final console = await _start(tester, shown: 'logs');
    expect(_divider, findsNothing);
    expect(_commands, findsNothing);
    await _drag(tester, _handle, 2 * _line);
    expect(_height(tester, _logs), 6 * _line);
    await _drag(tester, _handle, -40 * _line, kind: PointerDeviceKind.mouse);
    expect(console.paneHeight('logs'), _line);
  });

  testWidgets('no pane shown: the header alone, its background kept, no '
      'handle; a pane shown later expands it', (tester) async {
    final console = await _start(tester, shown: '');
    expect(console.panes, isEmpty);
    expect(_logs, findsNothing);
    expect(_commands, findsNothing);
    expect(_handle, findsNothing);
    expect(find.byKey(const ValueKey('debug-console-select')), findsNothing);
    final strip = _height(tester, _console);
    expect(strip, lessThan(2 * _line + 16));
    expect(console.size.height, closeTo(strip, 0.01));
    final background = tester.widget<DecoratedBox>(
      find.descendant(of: _console, matching: find.byType(DecoratedBox)).first,
    );
    expect((background.decoration as BoxDecoration).color, isNotNull);

    console.showPane('logs');
    await tester.pump();
    await tester.pump();
    expect(_logs, findsOneWidget);
    expect(_handle, findsOneWidget);
    expect(_height(tester, _console), greaterThan(strip + 4 * _line));
    expect(console.size.height, closeTo(_height(tester, _console), 0.01));
  });

  testWidgets('the background behind every part, the header and each shown '
      'pane with its divider and the handle, edge to edge', (tester) async {
    final console = await _start(
      tester,
      panes: '*',
      shown: 'logs,alpha,commands,zeta',
      probes: {
        'alpha': (5, _Probe('Alpha')),
        'zeta': (20, _Probe('Zeta', initialHeight: 5 * _line)),
      },
    );
    final whole = tester.getRect(_console);
    final parts = ['header', ...console.panes];
    final backgrounds = [
      for (final part in parts) tester.getRect(_background(part)),
    ];
    expect(backgrounds.first.top, whole.top);
    expect(backgrounds.last.bottom, closeTo(whole.bottom, 0.01));
    for (final (i, background) in backgrounds.indexed) {
      expect(background.left, whole.left, reason: parts[i]);
      expect(background.right, whole.right, reason: parts[i]);
      if (i > 0) {
        expect(
          background.top,
          closeTo(backgrounds[i - 1].bottom, 0.01),
          reason: 'no gap above ${parts[i]}',
        );
      }
    }
    bool behind(Rect background, Finder finder) {
      final rect = tester.getRect(finder);
      return background.inflate(0.01).contains(rect.topLeft) &&
          background.inflate(0.01).contains(rect.bottomRight);
    }

    expect(
      behind(
        backgrounds.first,
        find.byKey(const ValueKey('debug-console-header')),
      ),
      isTrue,
    );
    for (final (i, name) in console.panes.indexed) {
      final background = backgrounds[i + 1];
      expect(behind(background, _pane(name)), isTrue, reason: name);
      if (i > 0) {
        expect(behind(background, _dividerOf(name)), isTrue, reason: name);
      }
    }
    expect(behind(backgrounds.last, _handle), isTrue);

    // The backgrounds take no taps: through them, to the app.
    for (final part in parts) {
      expect(
        find.ancestor(
          of: _background(part),
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsWidgets,
        reason: part,
      );
    }
  });

  testWidgets("a pane's own background opacity; the others the console's", (
    tester,
  ) async {
    final console = await _start(
      tester,
      panes: 'logs,graph,clamped',
      shown: 'logs,graph,clamped',
      probes: {
        'graph': (5, _Probe('Graph', backgroundOpacity: 0.95)),
        'clamped': (6, _Probe('Clamped', backgroundOpacity: 3)),
      },
    );
    double alpha(String part) =>
        ((tester.widget<DecoratedBox>(_background(part)).decoration
                    as BoxDecoration)
                .color!)
            .a;
    expect(alpha('header'), closeTo(0.9, 0.01), reason: 'the default');
    expect(alpha('logs'), closeTo(0.9, 0.01), reason: 'interacting');
    expect(alpha('graph'), closeTo(0.95, 0.01));
    expect(alpha('clamped'), 1);
    console.interaction = DebugConsoleInteraction.passThrough;
    await tester.pump();
    await tester.pump();
    expect(alpha('header'), closeTo(0.9, 0.01));
    for (final pane in ['logs', 'graph', 'clamped']) {
      expect(alpha(pane), closeTo(0.7, 0.01), reason: 'passing through');
    }
  });

  testWidgets('the lower edge stops at the screen', (tester) async {
    final console = await _start(tester);
    await _drag(tester, _handle, 5000);
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(_console).dy, lessThanOrEqualTo(screen));
    expect(console.paneHeight('commands'), lessThan(screen));
  });

  testWidgets('a divider moves the room between its two neighbours only, '
      'each at least its least', (tester) async {
    final alpha = _Probe('Alpha', initialHeight: 3 * _line);
    final console = await _start(
      tester,
      panes: 'logs,alpha,commands',
      shown: 'logs,alpha,commands',
      probes: {'alpha': (5, alpha)},
    );
    final total = _height(tester, _console);
    await _drag(tester, _dividerOf('alpha'), _line);
    expect(console.paneHeight('logs'), 5 * _line);
    expect(console.paneHeight('alpha'), 2 * _line);
    expect(console.paneHeight('commands'), 6 * _line + _input);
    expect(_height(tester, _console), total, reason: 'the same height');

    await _drag(tester, _divider, -_line);
    expect(console.paneHeight('alpha'), _line);
    expect(console.paneHeight('commands'), 7 * _line + _input);
    expect(console.paneHeight('logs'), 5 * _line, reason: 'not a neighbour');

    await _drag(tester, _divider, 20 * _line, kind: PointerDeviceKind.mouse);
    expect(console.paneHeight('commands'), _line + _input);
    expect(console.paneHeight('alpha'), 7 * _line);

    await _drag(tester, _dividerOf('alpha'), -20 * _line);
    expect(console.paneHeight('logs'), _line);
    expect(console.paneHeight('alpha'), 11 * _line);
  });

  testWidgets('the heights stay while the app runs: hidden and shown again', (
    tester,
  ) async {
    final console = await _start(tester);
    await _drag(tester, _handle, 2 * _line);
    await _drag(tester, _divider, -_line);
    console.shown = false;
    await tester.pump();
    expect(_console, findsNothing);
    console.shown = true;
    await tester.pump();
    expect(_height(tester, _logs), 3 * _line);
    expect(_height(tester, _commands), 9 * _line + _input);
  });

  testWidgets('taps on the records and the output reach the app; on a '
      'handle they do not', (tester) async {
    var taps = 0;
    await _start(tester, onTap: () => taps++);
    await tester.tapAt(tester.getCenter(_output));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 1);
    await tester.tapAt(tester.getCenter(_logs));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 2);
    await tester.tapAt(tester.getCenter(_handle));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 2);
  });

  testWidgets('moves within one frame add up to one height', (tester) async {
    final console = await _start(tester, shown: 'logs');
    var changes = 0;
    console.addListener(() => changes++);
    final gesture = await tester.startGesture(tester.getCenter(_handle));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, 4));
    }
    await tester.pump();
    await gesture.up();
    expect(changes, greaterThan(0));
    expect(console.paneHeight('logs'), 4 * _line + 20);
    expect(_height(tester, _logs), 4 * _line + 20);
  });

  testWidgets('a shown pane that panes does not have fails the start', (
    tester,
  ) async {
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
                  'spring.flutter.debug.console.panes=commands\n'
                  'spring.flutter.debug.console.shown-panes=commands,network',
                ),
              },
            ),
          ],
          autoConfigurations: [
            springBootStarterFlutterAutoConfiguration,
            springBootStarterFlutterDebugConsoleAutoConfiguration,
            springBootStarterFlutterDebugConsoleCommandsAutoConfiguration,
            springBootStarterLoggingAutoConfiguration,
          ],
          bannerMode: BannerMode.off,
        ),
        home: _Home(() {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(_Home), findsNothing);
    final failure =
        '${tester.takeException()}'
        '${[for (final text in tester.widgetList<Text>(find.byType(Text))) text.data ?? text.textSpan?.toPlainText() ?? ''].join('\n')}';
    expect(
      failure,
      contains(
        "spring.flutter.debug.console.shown-panes names 'network', which "
        'spring.flutter.debug.console.panes does not have',
      ),
    );
  });

  test('fitHeights: the upper ones give way first, none under its least', () {
    expect(
      DebugConsoleView.fitHeights([100, 50, 50], [10, 10, 10], 150),
      [50, 50, 50],
    );
    expect(
      DebugConsoleView.fitHeights([100, 50, 50], [10, 10, 10], 50),
      [10, 10, 30],
    );
    expect(
      DebugConsoleView.fitHeights([100, 50], [10, 10], 500),
      [100, 50],
    );
  });
}
