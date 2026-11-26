// The debug timeline: the observations' stats, the view with its tabs (the
// debug panel's Timeline tab), the copied JSON and the console's
// `timeline` segment.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

ObservationContext _stopped(String name, int ms, {Object? error}) =>
    ObservationContext(name, contextualName: '$name call')
      ..startedAt = Duration.zero
      ..duration = Duration(milliseconds: ms)
      ..error = error;

final class _Start {
  _Start({int beans = 12}) {
    trace = SplashTrace(SplashStages(clock: () => now), log: false);
    final stages = trace.stages;
    stages.enter(SplashStage.page);
    now = const Duration(milliseconds: 300);
    stages.enter(SplashStage.engine);
    now = const Duration(milliseconds: 900);
    stages.enter(SplashStage.starting);
    final refresh = trace.start('spring.context.refresh');
    for (var i = 0; i < beans; i++) {
      final bean = trace.start('spring.beans.instantiate')
        ..tag('beanName', 'bean$i');
      now += Duration(milliseconds: i + 1);
      bean.end();
    }
    now = const Duration(milliseconds: 3200);
    refresh.end();
    trace.recordEvent('ContextRefreshedEvent');
    stages.enter(SplashStage.ready);
    now = const Duration(milliseconds: 4100);
    stages.enter(SplashStage.app);
  }

  Duration now = Duration.zero;
  late final SplashTrace trace;
}

Future<DebugTimeline> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  int beans = 12,
  void Function(_Start start)? after,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final observations = TimelineObservations();
  addTearDown(observations.dispose);
  final start = _Start(beans: beans);
  after?.call(start);
  final timeline = DebugTimeline(
    trace: start.trace,
    observations: observations,
  );
  await _view(tester, timeline);
  return timeline;
}

Future<void> _view(WidgetTester tester, DebugTimeline timeline) =>
    tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => TimelineView(timeline: timeline),
      ),
    );

void main() {
  group('TimelineObservations', () {
    test('aggregates the stopped observations per name', () {
      final observations = TimelineObservations(history: 3, capacity: 4);
      addTearDown(observations.dispose);
      for (final ms in [10, 30, 20, 40]) {
        observations.onStop(_stopped('a', ms));
      }
      observations
        ..onStop(_stopped('b', 5, error: StateError('x')))
        ..onStop(ObservationContext('running'));
      final a = observations.stats['a']!;
      expect(a.count, 4);
      expect(a.average, const Duration(milliseconds: 25));
      expect(a.max, const Duration(milliseconds: 40));
      expect(a.last, const Duration(milliseconds: 40));
      expect(a.recent, const [
        Duration(milliseconds: 30),
        Duration(milliseconds: 20),
        Duration(milliseconds: 40),
      ]);
      expect(observations.recent, hasLength(4));
      expect(observations.last?.name, 'b');
      expect(observations.last?.error, isA<StateError>());
      expect(observations.stats.containsKey('running'), isFalse);
    });

    testWidgets('notifies at most once per interval', (tester) async {
      final observations = TimelineObservations();
      addTearDown(observations.dispose);
      var notified = 0;
      observations.addListener(() => notified++);
      for (var i = 0; i < 50; i++) {
        observations.onStop(_stopped('a', i));
      }
      expect(notified, 0);
      await tester.pump(observations.interval);
      expect(notified, 1);
      observations.onStop(_stopped('a', 1));
      await tester.pump(observations.interval ~/ 2);
      expect(notified, 1);
      await tester.pump(observations.interval);
      expect(notified, 2);
    });
  });

  testWidgets("the console's timeline segment: how long the start took", (
    tester,
  ) async {
    final timeline = await _pump(tester);
    final segment = TimelineSegment(timeline);
    expect(segment.read().toString(), 'start 4.1s');
  });

  testWidgets('Start shows the stages and groups the beans, slowest first', (
    tester,
  ) async {
    await _pump(tester);
    for (final stage in ['page', 'engine', 'starting', 'ready', 'app']) {
      expect(find.text(stage), findsOneWidget);
    }
    expect(find.text('context.refresh'), findsOneWidget);
    expect(find.text('▾ beans 12'), findsOneWidget);
    expect(find.text('bean11'), findsOneWidget);
    expect(find.text('bean2'), findsOneWidget);
    expect(find.text('bean1'), findsNothing);
    expect(find.text('… 2 more'), findsOneWidget);
    expect(find.text('events 1'), findsOneWidget);
    await tester.tap(find.text('… 2 more'));
    await tester.pump();
    expect(find.text('bean0'), findsOneWidget);
    await tester.tap(find.text('▾ beans 12'));
    await tester.pump();
    expect(find.text('▸ beans 12'), findsOneWidget);
    expect(find.text('bean11'), findsNothing);
  });

  testWidgets('an event long after the start does not stretch it', (
    tester,
  ) async {
    await _pump(
      tester,
      after: (start) {
        start.now = const Duration(seconds: 100);
        start.trace.recordEvent('AppLifecycleStateEvent hidden');
      },
    );
    expect(find.textContaining('4.1s · zoom'), findsOneWidget);
    // The axis ends with the start, not at the event 100 s later.
    expect(find.text('0ms'), findsOneWidget);
    expect(find.text('10.0s'), findsNothing);
    expect(find.text('100.0s'), findsNothing);
    expect(find.text('events 1'), findsOneWidget);
  });

  testWidgets('Observations and Events list theirs', (tester) async {
    final timeline = await _pump(tester);
    timeline.observations.onStop(_stopped('db.query', 12));
    await tester.pump(timeline.observations.interval);
    await tester.tap(find.text('Observations'));
    await tester.pump();
    expect(find.text('db.query'), findsOneWidget);
    await tester.tap(find.text('db.query'));
    await tester.pump();
    expect(find.byType(TimelineSparkline), findsOneWidget);
    // The test font is wide: the tab is scrolled to.
    await tester.ensureVisible(find.text('Events'));
    await tester.tap(find.text('Events'));
    await tester.pump();
    expect(find.text('ContextRefreshedEvent'), findsOneWidget);
  });

  testWidgets('closed and opened again: the tab it was left on', (
    tester,
  ) async {
    final timeline = await _pump(tester);
    await tester.tap(find.text('Observations'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(find.byType(TimelineView), findsNothing);
    await _view(tester, timeline);
    expect(timeline.viewTab, 1);
    expect(find.byType(TimelineSparkline), findsNothing);
    expect(find.text('ContextRefreshedEvent'), findsNothing);
  });

  testWidgets('Copy JSON puts the steps and the stats on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    final timeline = await _pump(tester);
    timeline.observations.onStop(_stopped('db.query', 12));
    await tester.pump(timeline.observations.interval);
    await tester.tap(find.text('Copy JSON'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    final json = jsonDecode(copied!) as Map<String, Object?>;
    expect((json['stages']! as Map)['app'], 4100);
    expect(
      [for (final step in json['steps']! as List) (step as Map)['name']],
      containsAll(['spring.context.refresh', 'spring.event']),
    );
    expect(
      (((json['observations']! as Map)['stats'] as Map)['db.query']
          as Map)['count'],
      1,
    );
  });

  testWidgets('the section embeds the view', (
    tester,
  ) async {
    final timeline = await _pump(tester);
    final section = DebugTimelineSection(timeline);
    expect(section.title, 'Timeline');
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => Builder(builder: section.build),
      ),
    );
    expect(find.byType(TimelineView), findsOneWidget);
    expect(find.text('Off'), findsNothing);
  });
}
