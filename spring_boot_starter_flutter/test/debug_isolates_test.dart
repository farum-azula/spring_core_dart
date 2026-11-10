// The task manager of the isolates and the engine's threads: the engine's
// rows from Flutter's frame times and from round trips to its threads,
// measured only while read; the small table over the app and the full one
// in the debug panel, read only while they show; the shortcut, the copied
// JSON, and the rows in the `isolateLoads` of a running app.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

// A frame that took [build] and [raster] µs.
FrameTiming _frame({
  int build = 2000,
  int raster = 3000,
  int layerCache = 0,
  int pictureCache = 0,
}) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: build,
  rasterStart: build,
  rasterFinish: build + raster,
  rasterFinishWallTime: build + raster,
  layerCacheBytes: layerCache,
  pictureCacheBytes: pictureCache,
);

// A probe that counts what it is asked.
final class _Probe implements EngineLoadProbe {
  int started = 0;
  int ticks = 0;
  int stopped = 0;

  @override
  void start() => started++;

  @override
  void tick() => ticks++;

  @override
  void stop() => stopped++;

  @override
  List<IsolateLoad> loads() => const [
    IsolateLoad(name: 'probe', kind: 'engine'),
  ];
}

// A source with [rows], counting its reads.
final class _Source implements IsolateLoadSource {
  _Source(this.rows);

  List<IsolateLoad> rows;
  int reads = 0;

  @override
  List<IsolateLoad> loads() {
    reads++;
    return rows;
  }
}

const _rows = [
  IsolateLoad(
    name: 'main',
    kind: 'main',
    busy: 0.42,
    lag: Duration(microseconds: 1200),
    maxLag: Duration(milliseconds: 35),
    memory: 48 * 1024 * 1024,
    details: {'frames': 120, 'buildMicros': 2500, 'buildMaxMicros': 9000},
  ),
  IsolateLoad(name: 'task-1', kind: 'task', busy: 1, active: 2),
  IsolateLoad(
    name: 'raster',
    kind: 'engine',
    busy: 0.07,
    details: {'rasterMicros': 3000, 'layerCacheBytes': 2 * 1024 * 1024},
  ),
  IsolateLoad(
    name: 'platform',
    kind: 'engine',
    lag: Duration(microseconds: 300),
    maxLag: Duration(milliseconds: 2),
  ),
];

Future<(DebugIsolates, _Source)> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  List<IsolateLoad> rows = _rows,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = _Source(rows);
  final isolates = DebugIsolates(loads: IsolateLoads([source]));
  addTearDown(isolates.dispose);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => DebugDock(
        overlays: [isolates],
        child: const SizedBox.expand(),
      ),
    ),
  );
  return (isolates, source);
}

Future<void> _section(WidgetTester tester, DebugIsolates isolates) =>
    tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) =>
            Builder(builder: DebugIsolatesSection(isolates).build),
      ),
    );

void _mock(
  WidgetTester tester,
  MethodChannel channel,
  Future<Object?> Function(MethodCall call)? handler,
) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    handler,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<ApplicationContext> _start(
  WidgetTester tester, [
  String properties = '',
]) async {
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
        // In the generator's order: spring_boot_dart's, with its
        // `isolateLoads`, before the starter's.
        autoConfigurations: [
          springBootAutoConfiguration,
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterDebugAutoConfiguration,
          springBootStarterFlutterDebugIsolatesAutoConfiguration,
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

void main() {
  group('FrameLoadProbe', () {
    testWidgets('main gets the build times, raster how busy it is', (
      tester,
    ) async {
      var now = Duration.zero;
      final probe = FrameLoadProbe(clock: () => now)..start();
      addTearDown(probe.stop);
      final report = tester.binding.platformDispatcher.onReportTimings!;
      now = const Duration(seconds: 1);
      report([
        for (var i = 0; i < 9; i++) _frame(),
        _frame(
          build: 12000,
          raster: 23000,
          layerCache: 4096,
          pictureCache: 512,
        ),
      ]);
      now = const Duration(seconds: 2);
      final [main, raster] = probe.loads();
      expect(main.name, 'main');
      expect(main.kind, 'main');
      // The sampler's row has them: this one only adds its details.
      expect(main.busy, isNull);
      expect(main.lag, isNull);
      expect(main.maxLag, isNull);
      expect(main.details, {
        'frames': 10,
        'buildMicros': 3000,
        'buildMaxMicros': 12000,
      });
      expect(raster.name, 'raster');
      expect(raster.kind, 'engine');
      // 50 ms of raster in the 2 s measured.
      expect(raster.busy, closeTo(0.025, 1e-9));
      expect(raster.details, {
        'rasterMicros': 5000,
        'rasterMaxMicros': 23000,
        'layerCacheBytes': 4096,
        'pictureCacheBytes': 512,
      });
    });

    testWidgets('only the frames of the window count', (tester) async {
      var now = Duration.zero;
      final probe = FrameLoadProbe(
        window: const Duration(seconds: 5),
        clock: () => now,
      )..start();
      addTearDown(probe.stop);
      final report = tester.binding.platformDispatcher.onReportTimings!;
      // Nothing measured yet: no share of no time.
      expect(probe.loads().last.busy, isNull);
      now = const Duration(seconds: 1);
      report([_frame(raster: 500000)]);
      now = const Duration(seconds: 5);
      report([_frame(raster: 250000)]);
      now = const Duration(seconds: 10);
      final [main, raster] = probe.loads();
      expect(main.details['frames'], 1);
      // 250 ms of raster in the 5 s of the window.
      expect(raster.busy, closeTo(0.05, 1e-9));
      now = const Duration(seconds: 20);
      final [idle, still] = probe.loads();
      expect(idle.details, {'frames': 0});
      expect(still.busy, 0);
    });

    testWidgets('listens to the timings only between start and stop', (
      tester,
    ) async {
      // Never started: nothing to remove.
      final probe = FrameLoadProbe()..stop();
      final report = tester.binding.platformDispatcher.onReportTimings!;
      report([_frame()]);
      expect(probe.loads().first.details, {'frames': 0});
      probe.start();
      report([_frame()]);
      expect(probe.loads().first.details['frames'], 1);
      probe.stop();
      report([_frame()]);
      expect(probe.loads().first.details, {'frames': 0});
      probe.stop();
    });
  });

  group('RoundTripProbe', () {
    test('lag is the average round trip, maxLag the longest', () async {
      var now = Duration.zero;
      final trips = <Completer<void>>[];
      final probe = RoundTripProbe(
        'platform',
        [() => (trips..add(Completer<void>())).last.future],
        clock: () => now,
      )..start();
      expect(trips, hasLength(1));
      // Asked this instant: no lag yet.
      expect(probe.loads().single.toJson(), {
        'name': 'platform',
        'kind': 'engine',
      });
      // One under way: the next tick does not ask again.
      probe.tick();
      expect(trips, hasLength(1));
      now += const Duration(milliseconds: 2);
      trips.last.complete();
      await pumpEventQueue();
      probe.tick();
      now += const Duration(milliseconds: 6);
      trips.last.complete();
      await pumpEventQueue();
      final load = probe.loads().single;
      expect(load.lag, const Duration(milliseconds: 4));
      expect(load.maxLag, const Duration(milliseconds: 6));
      expect(load.busy, isNull);
    });

    test('a trip that waits longer than any before is the maxLag', () async {
      var now = Duration.zero;
      final trips = <Completer<void>>[];
      final probe = RoundTripProbe(
        'io',
        [() => (trips..add(Completer<void>())).last.future],
        clock: () => now,
      )..start();
      now += const Duration(milliseconds: 1);
      trips.last.complete();
      await pumpEventQueue();
      probe.tick();
      now += const Duration(seconds: 3);
      final load = probe.loads().single;
      expect(load.lag, const Duration(milliseconds: 1));
      expect(load.maxLag, const Duration(seconds: 3));
    });

    test('a trip that fails is not asked again: the next one is', () async {
      var now = Duration.zero;
      var missing = 0;
      var answered = 0;
      final probe = RoundTripProbe(
        'platform',
        [
          () {
            missing++;
            throw MissingPluginException();
          },
          () async {
            answered++;
            now += const Duration(milliseconds: 1);
          },
        ],
        clock: () => now,
      )..start();
      await pumpEventQueue();
      probe.tick();
      await pumpEventQueue();
      expect(missing, 1);
      expect(answered, 2);
      expect(probe.loads().single.lag, const Duration(milliseconds: 1));
    });

    test('nothing answers: a row without a lag, never an error', () async {
      var asked = 0;
      final probe = RoundTripProbe('platform', [
        () async {
          asked++;
          throw PlatformException(code: 'error');
        },
      ])..start();
      await pumpEventQueue();
      probe
        ..tick()
        ..tick();
      await pumpEventQueue();
      expect(asked, 1);
      expect(probe.loads().single.toJson(), {
        'name': 'platform',
        'kind': 'engine',
      });
    });

    test('an answer that comes after the stop is dropped', () async {
      final trip = Completer<void>();
      final probe = RoundTripProbe('io', [() => trip.future])..start();
      probe.stop();
      trip.complete();
      await pumpEventQueue();
      expect(probe.loads().single.lag, isNull);
      expect(probe.loads().single.maxLag, isNull);
    });

    testWidgets('platform: the keyboard channel, or the one iOS answers', (
      tester,
    ) async {
      final calls = <String>[];
      _mock(tester, SystemChannels.keyboard, (call) async {
        calls.add(call.method);
        return <int, int>{};
      });
      final keyboard = RoundTripProbe.platform()..start();
      await tester.pump();
      expect(calls, ['getKeyboardState']);
      expect(keyboard.loads().single.name, 'platform');
      expect(keyboard.loads().single.lag, isNotNull);

      // iOS: no keyboard state.
      _mock(tester, SystemChannels.keyboard, (call) async {
        throw MissingPluginException();
      });
      _mock(tester, SystemChannels.platform, (call) async {
        calls.add(call.method);
        return true;
      });
      final ios = RoundTripProbe.platform()..start();
      await tester.pump();
      expect(calls.last, 'LiveText.isLiveTextInputAvailable');
      expect(ios.loads().single.lag, isNotNull);

      // Neither: the row, without a lag.
      _mock(tester, SystemChannels.platform, (call) async {
        throw MissingPluginException();
      });
      final none = RoundTripProbe.platform()..start();
      await tester.pump();
      expect(none.loads().single.lag, isNull);
      expect(none.loads().single.maxLag, isNull);
    });

    testWidgets('io: a picture of one pixel is decoded', (tester) async {
      final probe = RoundTripProbe.io();
      await tester.runAsync(() async {
        await RoundTripProbe.decodeImage();
        probe.start();
        for (var i = 0; i < 50 && probe.loads().single.lag == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(probe.loads().single.name, 'io');
      expect(probe.loads().single.lag, isNotNull);
    });
  });

  group('FlutterEngineLoads', () {
    testWidgets('measures from the first read until nobody reads', (
      tester,
    ) async {
      final probe = _Probe();
      final loads = FlutterEngineLoads(
        probes: [probe],
        interval: const Duration(seconds: 2),
        idleAfter: const Duration(seconds: 10),
      );
      addTearDown(loads.stop);
      // Nobody reads: nothing starts.
      await tester.pump(const Duration(minutes: 1));
      expect(loads.isRunning, isFalse);
      expect(probe.started, 0);

      expect(loads.loads().single.name, 'probe');
      expect(loads.isRunning, isTrue);
      expect(probe.started, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(probe.ticks, 2);
      // Every read keeps it going.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 4));
        loads.loads();
      }
      expect(loads.isRunning, isTrue);
      expect(probe.started, 1);
      expect(probe.stopped, 0);
      // No read for longer than idleAfter: stopped.
      await tester.pump(const Duration(seconds: 13));
      expect(loads.isRunning, isFalse);
      expect(probe.stopped, 1);
      final ticks = probe.ticks;
      await tester.pump(const Duration(minutes: 1));
      expect(probe.ticks, ticks);
      // The next read starts it again.
      loads.loads();
      expect(probe.started, 2);
      loads.stop();
      expect(probe.stopped, 2);
    });

    testWidgets('a browser has no platform and no io row', (tester) async {
      final web = FlutterEngineLoads(
        probes: FlutterEngineLoads.probesOf(web: true),
      );
      addTearDown(web.stop);
      expect([for (final load in web.loads()) load.name], ['main', 'raster']);
      expect(web.loads().first.busy, isNull);
      expect(web.loads().first.lag, isNull);
      web.stop();

      final probes = FlutterEngineLoads.probesOf(web: false);
      expect(probes.first, isA<FrameLoadProbe>());
      expect(
        [
          for (final probe in probes.whereType<RoundTripProbe>()) probe.name,
        ],
        ['platform', 'io'],
      );
      expect(probes, hasLength(3));
    });
  });

  group('IsolateLoadsWatch', () {
    testWidgets('reads only while someone listens', (tester) async {
      final source = _Source(_rows);
      final watch = IsolateLoadsWatch(
        IsolateLoads([source]),
        interval: const Duration(milliseconds: 500),
      );
      addTearDown(watch.dispose);
      await tester.pump(const Duration(seconds: 5));
      expect(source.reads, 0);
      expect(watch.value, isEmpty);
      var notified = 0;
      void listener() => notified++;
      watch.addListener(listener);
      // At once, for the first frame of who listens.
      expect(source.reads, 1);
      expect(watch.value, hasLength(4));
      expect(watch.isReading, isTrue);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(source.reads, 4);
      expect(notified, 3);
      watch.removeListener(listener);
      expect(watch.isReading, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(source.reads, 4);
    });
  });

  testWidgets('the table over the app: a line per row, read while shown', (
    tester,
  ) async {
    final (isolates, source) = await _pump(tester);
    expect(find.byType(DebugIsolatesGauge), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    // Hidden: nothing is read, so nothing is measured.
    expect(source.reads, 0);

    isolates.shown = true;
    await tester.pump();
    expect(source.reads, 1);
    for (final name in ['main', 'task-1', 'raster', 'platform']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('1.2ms'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('7%'), findsOneWidget);
    expect(find.text('0.3ms'), findsOneWidget);
    // In the order `isolateLoads` gives them.
    expect(
      tester.getTopLeft(find.text('main')).dy,
      lessThan(tester.getTopLeft(find.text('task-1')).dy),
    );
    expect(
      tester.getTopLeft(find.text('raster')).dy,
      lessThan(tester.getTopLeft(find.text('platform')).dy),
    );

    // Read again every interval, and shown.
    source.rows = const [IsolateLoad(name: 'main', kind: 'main', busy: 0.9)];
    await tester.pump(const Duration(seconds: 1));
    expect(source.reads, 2);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('raster'), findsNothing);

    isolates.shown = false;
    await tester.pump();
    final reads = source.reads;
    await tester.pump(const Duration(seconds: 5));
    expect(source.reads, reads);
  });

  testWidgets('a phone: at most eight rows, then how many more', (
    tester,
  ) async {
    final (isolates, _) = await _pump(
      tester,
      size: const Size(360, 640),
      rows: [
        for (var i = 1; i <= 11; i++)
          IsolateLoad(name: 'task-$i', kind: 'task'),
      ],
    );
    isolates.shown = true;
    await tester.pump();
    expect(find.text('task-8'), findsOneWidget);
    expect(find.text('task-9'), findsNothing);
    expect(find.text('… 3 more'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(DebugIsolatesGauge)).width,
      DebugIsolatesGauge.width,
    );
    expect(isolates.size, DebugIsolatesGauge.sizeOf(9));
    expect(
      tester.getSize(find.byType(DebugIsolatesGauge)).height,
      isolates.size.height,
    );
  });

  testWidgets('the shortcut shows and hides the table', (tester) async {
    final (isolates, _) = await _pump(tester);
    expect(isolates.action, 'debug.isolates');
    expect(isolates.keys, ['primary+shift+i', 'taps:7+hold:2s']);
    expect(isolates.id, 'isolates');
    expect(
      isolates.handle(const ShortcutInvocation('debug.isolates', null)),
      isTrue,
    );
    expect(isolates.shown, isTrue);
    await tester.pump();
    expect(find.byType(DebugIsolatesGauge), findsOneWidget);
    isolates.handle(const ShortcutInvocation('debug.isolates', null));
    await tester.pump();
    expect(find.byType(DebugIsolatesGauge), findsNothing);
  });

  testWidgets('the section: every value of every row, read while open', (
    tester,
  ) async {
    final (isolates, source) = await _pump(tester);
    final section = DebugIsolatesSection(isolates);
    expect(section.title, 'Isolates');
    expect(source.reads, 0);
    await _section(tester, isolates);
    expect(source.reads, 1);
    expect(find.byType(IsolatesView), findsOneWidget);
    for (final text in [
      // The columns.
      'name', 'kind', 'busy', 'lag', 'max lag', 'active', 'memory',
      // main.
      '42%', '1.2ms', '35ms', '48.0 MB',
      'frames 120 · build 2.5ms · buildMax 9.0ms',
      // task-1.
      'task-1', 'task', '100%', '2',
      // raster.
      'raster', '7%', 'raster 3.0ms · layerCache 2.0 MB',
      // platform.
      'platform', '0.3ms', '2.0ms',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('engine'), findsNWidgets(2));
    expect(find.text('main'), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 2));
    expect(source.reads, 3);

    // The switch of the table over the app.
    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(isolates.shown, isTrue);
    expect(find.text('On'), findsOneWidget);

    // Another tab: no reads.
    await tester.pumpWidget(const SizedBox());
    final reads = source.reads;
    await tester.pump(const Duration(seconds: 5));
    expect(source.reads, reads);
  });

  testWidgets('the section on a phone scrolls the table sideways', (
    tester,
  ) async {
    final (isolates, _) = await _pump(tester, size: const Size(320, 640));
    await _section(tester, isolates);
    expect(tester.takeException(), isNull);
    expect(find.text('memory'), findsOneWidget);
    expect(find.text('No isolates'), findsNothing);
  });

  testWidgets('Copy JSON puts the rows on the clipboard', (tester) async {
    String? copied;
    _mock(tester, SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    final (isolates, _) = await _pump(tester);
    await _section(tester, isolates);
    await tester.tap(find.text('Copy JSON'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    expect(jsonDecode(copied!), [for (final load in _rows) load.toJson()]);
    expect((jsonDecode(copied!) as List).first, {
      'name': 'main',
      'kind': 'main',
      'busy': 0.42,
      'lagMicros': 1200,
      'maxLagMicros': 35000,
      'memory': 48 * 1024 * 1024,
      'details': {'frames': 120, 'buildMicros': 2500, 'buildMaxMicros': 9000},
    });
  });

  test('sizes and details are written for people', () {
    expect(formatIsolateMemory(null), '–');
    expect(formatIsolateMemory(512), '512 B');
    expect(formatIsolateMemory(1536), '1.5 KB');
    expect(formatIsolateMemory(300 * 1024 * 1024), '300 MB');
    expect(formatIsolateMemory(3 * 1024 * 1024 * 1024), '3.0 GB');
    expect(formatIsolateBusy(null), '–');
    expect(formatIsolateLag(null), '–');
    expect(formatIsolateLag(const Duration(seconds: 2)), '2.0s');
    expect(formatIsolateDetail('queued', 3), 'queued 3');
    expect(formatIsolateDetail('buildMicros', 'slow'), 'buildMicros slow');
  });

  group('in an app', () {
    testWidgets("isolateLoads has the engine's rows beside the isolate's", (
      tester,
    ) async {
      _mock(tester, SystemChannels.keyboard, (call) async => <int, int>{});
      final context = await _start(
        tester,
        'spring.flutter.debug.isolates.position=top-left\n'
        'spring.flutter.debug.isolates.interval=250ms',
      );
      final engine = context.getBean<FlutterEngineLoads>();
      final sampler = context.getBean<IsolateLoadSampler>();
      final loads = context.getBean<IsolateLoads>();
      expect(loads.sources, contains(engine));
      expect(loads.sources, contains(sampler));
      // Nobody has read yet: nothing measures.
      expect(engine.isRunning, isFalse);
      expect(sampler.isRunning, isFalse);

      final isolates = context.getBean<DebugIsolates>();
      expect(isolates.corner, DebugOverlayCorner.topLeft);
      expect(isolates.rows.interval, const Duration(milliseconds: 250));
      expect(isolates.rows.loads, same(loads));

      // Ctrl+Shift+I shows the table, which reads.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(isolates.shown, isTrue);
      expect(find.byType(DebugIsolatesGauge), findsOneWidget);
      expect(engine.isRunning, isTrue);
      expect(sampler.isRunning, isTrue);

      tester.binding.platformDispatcher.onReportTimings!([_frame()]);
      await tester.pump(const Duration(seconds: 1));
      final rows = {for (final load in loads.all()) load.name: load};
      expect(rows.keys, ['main', 'raster', 'platform', 'io']);
      // One row of the sampler's lag and the engine's frames.
      final main = rows['main']!;
      expect(main.kind, 'main');
      expect(main.lag, isNotNull);
      expect(main.busy, isNotNull);
      expect(main.details['frames'], greaterThan(0));
      expect(main.details['buildMicros'], isNotNull);
      expect(rows['raster']!.kind, 'engine');
      expect(rows['raster']!.busy, isNotNull);
      expect(rows['platform']!.lag, isNotNull);
      for (final name in rows.keys) {
        expect(find.text(name), findsOneWidget, reason: name);
      }

      // The debug panel has its tab, and hides the table meanwhile.
      context.getBean<DebugPanel>().toggle();
      await tester.pump();
      expect(find.byType(DebugIsolatesGauge), findsNothing);
      // The test font is wide: the tab is scrolled to.
      await tester.ensureVisible(find.text('Isolates'));
      await tester.tap(find.text('Isolates'));
      await tester.pump();
      expect(find.byType(IsolatesView), findsOneWidget);
      expect(find.text('raster'), findsOneWidget);

      // Closed and hidden: nothing reads, and after a while the engine's
      // probes stop. (The sampler stops alike, by a clock of its own that
      // a test's time does not move.)
      context.getBean<DebugPanel>().close();
      isolates.shown = false;
      await tester.pump();
      expect(isolates.rows.isReading, isFalse);
      await tester.pump(const Duration(seconds: 40));
      expect(engine.isRunning, isFalse);
      sampler.stop();
    });

    testWidgets('enabled=false in a running app: no task manager', (
      tester,
    ) async {
      final context = await _start(
        tester,
        'spring.flutter.debug.isolates.enabled=false',
      );
      expect(context.containsBean('debugIsolates'), isFalse);
      expect(context.containsBean('debugIsolatesSection'), isFalse);
      expect(context.containsBean('flutterEngineLoads'), isFalse);
      expect(context.getBean<IsolateLoads>().sources, isNotEmpty);
    });
  });
}
