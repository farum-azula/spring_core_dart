// The stages of the start (page to app): reached once, in order, buffered
// until the context publishes them; the frame pacer that yields to the
// splash while the beans are made; the trace of the start.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Publisher implements ApplicationEventPublisher {
  final events = <Object>[];

  @override
  void publishEvent<T extends Object>(T event) => events.add(event);
}

final class _Slow {
  _Slow();
}

SpringApplication _app(String properties, {int beans = 0}) => SpringApplication(
  [
    BeanModule(
      'test',
      [
        for (var i = 0; i < beans; i++)
          BeanDefinition<_Slow>(
            name: 'slow$i',
            types: const [_Slow],
            create: (_) {
              final watch = Stopwatch()..start();
              while (watch.elapsedMilliseconds < 3) {}
              return _Slow();
            },
          ),
      ],
      resources: {
        'application.properties': EmbeddedResource.text(properties),
      },
    ),
  ],
  bannerMode: BannerMode.off,
);

Future<ApplicationContext> _pump(
  WidgetTester tester,
  SpringApplication application,
) async {
  const child = SizedBox(key: ValueKey('child'));
  await tester.pumpWidget(
    SpringApplicationWidget(application: () => application, child: child),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byKey(const ValueKey('child'))));
}

void main() {
  test('stages are reached once, in order, the latest is the value', () {
    var now = Duration.zero;
    final stages = SplashStages(clock: () => now);
    final seen = <SplashStage>[];
    stages.addListener(() => seen.add(stages.value));
    expect(stages.value, SplashStage.splash);
    now = const Duration(milliseconds: 10);
    stages.enter(SplashStage.splash);
    now = const Duration(milliseconds: 30);
    stages
      ..enter(SplashStage.starting)
      ..enter(SplashStage.starting)
      ..enter(SplashStage.splash);
    expect(seen, [SplashStage.splash, SplashStage.starting]);
    expect(stages.at(SplashStage.starting), const Duration(milliseconds: 30));
    expect(stages.at(SplashStage.ready), isNull);
    expect(stages.reached.keys, [SplashStage.splash, SplashStage.starting]);
  });

  test("the page's stages come first; the clock goes on from them", () {
    final stages = SplashStages(
      reached: {
        SplashStage.engine: const Duration(milliseconds: 900),
        SplashStage.page: const Duration(milliseconds: 40),
      },
    );
    expect(stages.reached.keys, [SplashStage.page, SplashStage.engine]);
    expect(stages.value, SplashStage.engine);
    expect(stages.now, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
  });

  test('events wait for the context, then follow each stage', () {
    final stages = SplashStages(clock: () => Duration.zero)
      ..enter(SplashStage.splash)
      ..enter(SplashStage.starting);
    final publisher = _Publisher();
    stages.publishTo(publisher);
    stages
      ..publishTo(_Publisher())
      ..enter(SplashStage.ready);
    expect(
      [for (final e in publisher.events.cast<SplashStageEvent>()) e.stage],
      [SplashStage.splash, SplashStage.starting, SplashStage.ready],
    );
    expect((publisher.events.first as SplashStageEvent).source, stages);
  });

  testWidgets('the pacer yields a frame once its budget is spent', (
    tester,
  ) async {
    final pacer = FramePacer(budget: const Duration(hours: 1));
    expect(pacer.pace(), isNull);
    final spent = FramePacer(budget: Duration.zero);
    final frame = spent.pace();
    expect(frame, isNotNull);
    var done = false;
    unawaited(frame!.then((_) => done = true));
    await tester.pump();
    expect(done, isTrue);
  });

  testWidgets('a start goes through the stages; the bean has them', (
    tester,
  ) async {
    final context = await _pump(tester, _app(''));
    final stages = context.getBean<SplashStages>();
    // Without a splash the hand-off may come after the app: no `splash`.
    expect(stages.reached.keys, [
      SplashStage.starting,
      SplashStage.ready,
      SplashStage.exit,
      SplashStage.app,
    ]);
  });

  testWidgets('yield-frames makes the beans between frames', (tester) async {
    final context = await _pump(
      tester,
      _app(
        'spring.flutter.splash.yield-frames=true\n'
        'spring.flutter.splash.frame-budget=1ms',
        beans: 5,
      ),
    );
    expect(context.getBeansOfType<_Slow>(), hasLength(5));
    expect(context.getBean<SplashStages>().value, SplashStage.app);
  });

  testWidgets('trace records each bean and ends with the app', (tester) async {
    final context = await _pump(
      tester,
      _app('spring.flutter.splash.trace=true', beans: 2),
    );
    expect(context.getBean<SplashStages>().value, SplashStage.app);
  });

  test('a trace measures the beans and reports the stages', () {
    var now = Duration.zero;
    final stages = SplashStages(clock: () => now);
    final trace = SplashTrace(stages);
    final step = trace.start('spring.beans.instantiate')
      ..tag('beanName', 'repository');
    step.end();
    expect(trace.steps.single.name, 'spring.beans.instantiate');
    expect(trace.steps.single.tags, [('beanName', 'repository')]);
    for (final stage in SplashStage.values) {
      now += const Duration(milliseconds: 5);
      stages.enter(stage);
    }
    // Each stage a step, from it to the next; the app of no length.
    final staged = trace.steps.skip(1).toList();
    expect(
      [for (final step in staged) step.name],
      [for (final stage in SplashStage.values) SplashTrace.stepOf(stage)],
    );
    expect(staged.first.startedAt, const Duration(milliseconds: 5));
    expect(staged.first.duration, const Duration(milliseconds: 5));
    expect(staged.last.duration, Duration.zero);
  });

  test('without beans, a bean is no step; an event is one of no length', () {
    var now = Duration.zero;
    final stages = SplashStages(clock: () => now);
    final trace = SplashTrace(stages, beans: false, log: false);
    trace.start('spring.beans.instantiate').end();
    expect(trace.steps, isEmpty);
    now = const Duration(milliseconds: 7);
    trace.recordEvent(const _Event());
    expect(trace.steps.single.name, SplashTrace.event);
    expect(trace.steps.single.startedAt, const Duration(milliseconds: 7));
    expect(trace.steps.single.tags, [('type', '_Event')]);
  });
}

final class _Event {
  const _Event();
}
