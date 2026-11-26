// The debug console's `signals` pane: in the build only when
// `console.panes` lists it, the application graph preset to the signals
// layer, a flash on a tick, a tapped node in one line, and nothing
// collected hidden.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show
        ApplicationContextRunner,
        doesNotHaveBean,
        hasSingleBean,
        springBootTest;

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

/// A clock a test moves by hand.
final class _Clock {
  Duration now = Duration.zero;
  Duration call() => now;
}

final Finder _graphPaint = find.byKey(const ValueKey('debug graph'));

void main() {
  test('in the build only when console.panes names signals or holds *, '
      'with the console as its parent', () {
    final source = File(
      'lib/spring_auto_configuration.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(
      source,
      contains(
        "AutoConfigurationBuild.named('spring.flutter.debug.console.panes',"
        "'signals',whenMissing:BuildInclusion.never,parents:["
        "AutoConfigurationBuild('spring.flutter.debug.console.enabled',"
        'whenMissing:BuildInclusion.never,),],),)'
        'finalBeanModulespringBootStarterFlutterSignalsDebugConsolePaneAutoConfiguration',
      ),
    );
    // The example lists no pane: none of its code is in its build.
    expect(
      File('example/spring_gen/example.spring.debug.dart').readAsStringSync(),
      isNot(contains('DebugConsolePaneAutoConfiguration')),
    );
  });

  test('the bean: named signals by its annotation, order 20; off with the '
      'console', () {
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterSignalsAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterFlutterSignalsDebugConsolePaneAutoConfiguration,
        );
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<SignalsPane>());
      expect(context, hasSingleBean<SignalsGraphLayer>());
      expect(context, hasSingleBean<SignalsDebugRecorder>());
      expect(context, hasSingleBean<SignalWidgetNames>());
      final pane = context.context.findAnnotationOnBean<ConsolePane>(
        'signalsPane',
      );
      expect(pane?.pane, 'signals');
      expect(pane?.value, 20);
      expect(context.getBean<SignalsPane>().title, 'Signals');
      expect(
        context.getBean<SignalsPane>().layers.single,
        same(context.getBean<SignalsGraphLayer>()),
        reason: 'the graph pane preset to the signals layer',
      );
      expect(context.getBean<SignalsPane>().backgroundOpacity, isNull);
      expect(
        context.getBean<SignalBuildTracker>().names,
        isNotNull,
        reason: 'the pane names the widgets too',
      );
      expect(SignalProbes.current, isNull, reason: 'nothing shows yet');
    });
    runner
        .withPropertyValues(['spring.flutter.debug.console.enabled=false'])
        .run((context) => expect(context, doesNotHaveBean<SignalsPane>()));
  });

  group('the pane', () {
    final app = springBootTest(springApplication);

    late _Clock clock;
    late SignalsDebugRecorder recorder;
    late SignalsGraphLayer layer;
    late SignalsPane pane;
    late DebugConsole console;

    setUp(() {
      clock = _Clock();
      recorder = SignalsDebugRecorder(clock: clock.call);
      layer = SignalsGraphLayer(app.getBean<SignalBeans>(), recorder);
      pane = SignalsPane(layer);
      console = DebugConsole();
    });

    tearDown(() {
      console.dispose();
      layer.dispose();
    });

    Widget host() => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 600,
          height: pane.initialHeight,
          child: Builder(builder: (context) => pane.build(context, console)),
        ),
      ),
    );

    test('hidden it costs nothing: it collects only between start and its '
        'stop', () {
      final basket = app.getBean<Basket>();
      expect(SignalProbes.current, isNull);
      basket.coupon = 'HIDDEN';
      app.getBean<SignalRuntime>().queues.primary.flush();
      expect(recorder.readers, isEmpty);
      final stop = pane.start();
      expect(SignalProbes.current, same(recorder));
      stop();
      expect(SignalProbes.current, isNull);
      basket.coupon = null;
      app.getBean<SignalRuntime>().queues.primary.flush();
      expect(
        recorder.writesOf(
          (basket as SignalBeanHolder).signalBean.members['coupon']!
              as ValueMember,
        ),
        0,
      );
    });

    testWidgets('shows the signals graph, compact, in its height; a tick '
        'flashes the node and the frames stop when it faded; a tapped node '
        'in one line; nothing left when it hides', (tester) async {
      final stop = pane.start();
      final basket = app.getBean<Basket>()
        ..coupon = 'TEN'
        ..add(const Book('Dune', 10));
      app.getBean<SignalRuntime>().queues.primary.flush();
      expect(basket.total, greaterThan(0));

      await tester.pumpWidget(host());
      final view = tester.widget<DebugGraphView>(find.byType(DebugGraphView));
      expect(view.compact, isTrue);
      expect(view.layers, [layer]);
      expect(view.settings.liveOnly, isFalse, reason: 'off by default');
      await tester.tap(find.text('All'));
      await tester.pump();
      final state = tester.state<DebugGraphViewState>(
        find.byType(DebugGraphView),
      );
      expect(state.graph!.lanes.map((lane) => lane.title), contains('Basket'));

      // A tick: the frames start, the coupon is lit, they stop after it
      // faded.
      clock.now = const Duration(seconds: 10);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      basket.coupon = 'FIVE';
      app.getBean<SignalRuntime>().queues.primary.flush();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it animates');
      final scene = state.scene!;
      final coupon = scene.graph.items.indexWhere((n) => n.label == 'coupon');
      final painter =
          tester.widget<CustomPaint>(_graphPaint).painter! as DebugGraphPainter;
      expect(painter.lastFrame!.lit[coupon], 1);
      clock.now = const Duration(milliseconds: 11200);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'faded');

      // A tap on the coupon: its card, one line beside it.
      final at = MatrixUtils.transformPoint(
        state.transform,
        scene.rects[coupon].center,
      );
      // A double tap opens the plate's card.
      await tester.tapAt(tester.getTopLeft(_graphPaint) + at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tester.getTopLeft(_graphPaint) + at);
      await tester.pump();
      expect(find.text('Basket · coupon'), findsOneWidget);
      expect(find.textContaining(RegExp("^'FIVE'")), findsOneWidget);

      // The double tap's wait for a third tap runs out.
      await tester.pump(const Duration(milliseconds: 300));

      // Hidden: not built, and stopped.
      await tester.pumpWidget(const SizedBox());
      stop();
      expect(SignalProbes.current, isNull);
      basket.coupon = null;
      app.getBean<SignalRuntime>().queues.primary.flush();
    });
  });
}
