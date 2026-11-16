// The conditions under which scenes draw less: the mode of each in
// spring.flutter.scene.when, the least one winning; a touch screen; frames
// slow for long enough while scenes move, which then holds for the run.
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner;

import 'support/fakes.dart';

final class _Condition extends ChangeNotifier implements SceneCondition {
  _Condition(this.name);

  @override
  final String name;

  bool _holds = false;

  @override
  bool get holds => _holds;

  set holds(bool value) {
    _holds = value;
    notifyListeners();
  }

  @override
  String get state => _holds ? 'holds' : 'does not hold';
}

FrameTiming _frame(int start, int cpu) => FrameTiming(
  vsyncStart: start,
  buildStart: start,
  buildFinish: start + cpu ~/ 2,
  rasterStart: start + cpu ~/ 2,
  rasterFinish: start + cpu,
  rasterFinishWallTime: start + cpu,
);

List<FrameTiming> _second(int from, int cpu) => [
  for (var i = 0; i < 30; i++) _frame(from + i * 33333, cpu),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SceneAvailability availability(
    Map<String, SceneRenderMode>? when,
    List<SceneCondition> conditions, {
    SceneRenderMode render = SceneRenderMode.animated,
  }) => SceneAvailability(
    properties: SceneProperties(render: render, when: when),
    engine: SceneEngine(backend: FakeBackend(), events: RecordingEvents()),
    conditions: conditions,
  );

  test('a condition that holds gives its mode; the least one wins', () {
    final touch = _Condition('touch');
    final slow = _Condition('slow');
    final scenes = availability(
      {'touch': SceneRenderMode.still, 'slow': SceneRenderMode.off},
      [touch, slow],
    );
    var notified = 0;
    scenes.addListener(() => notified++);
    expect(scenes.render, SceneRenderMode.animated);
    expect(scenes.animates, isTrue);
    touch.holds = true;
    expect(scenes.render, SceneRenderMode.still);
    expect(scenes.animates, isFalse);
    expect(scenes.draws, isTrue);
    expect(
      [for (final (c, mode) in scenes.held) '${c.name} ${mode.name}'],
      [
        'touch still',
      ],
    );
    slow.holds = true;
    expect(scenes.render, SceneRenderMode.off);
    expect(scenes.reason, SceneUnavailable.off);
    expect(notified, 2);
  });

  test('a condition not named in when changes nothing', () {
    final touch = _Condition('touch')..holds = true;
    expect(availability(null, [touch]).render, SceneRenderMode.animated);
    expect(
      availability(const {}, [touch], render: SceneRenderMode.still).render,
      SceneRenderMode.still,
    );
  });

  test('a condition never makes scenes draw more than render asks', () {
    final touch = _Condition('touch')..holds = true;
    expect(
      availability(
        {'touch': SceneRenderMode.animated},
        [touch],
        render: SceneRenderMode.still,
      ).render,
      SceneRenderMode.still,
    );
  });

  test('touch: what the device is, or what a test says', () {
    expect(TouchSceneCondition(touch: true).holds, isTrue);
    expect(TouchSceneCondition(touch: false).holds, isFalse);
    expect(TouchSceneCondition().name, 'touch');
  });

  group('slow', () {
    test('frames slow for long enough while scenes move: holds', () {
      final frames = SceneFrames()..join(#view, 30, () => false);
      final slow = SlowFramesSceneCondition(
        frames: frames,
        frameTime: const Duration(milliseconds: 16),
        after: const Duration(seconds: 2),
      );
      var notified = 0;
      slow.addListener(() => notified++);
      slow.timings(_second(0, 25000));
      expect(slow.holds, isFalse);
      expect(slow.middle, const Duration(milliseconds: 25));
      slow.timings(_second(1000000, 25000));
      slow.timings(_second(2000000, 25000));
      expect(slow.holds, isTrue);
      expect(notified, 1);
      // For the rest of the run.
      slow.timings(_second(3000000, 2000));
      expect(slow.holds, isTrue);
      frames.dispose();
    });

    test('a fast batch starts the count again', () {
      final frames = SceneFrames()..join(#view, 30, () => false);
      final slow = SlowFramesSceneCondition(
        frames: frames,
        after: const Duration(seconds: 2),
      );
      slow
        ..timings(_second(0, 25000))
        ..timings(_second(1000000, 4000))
        ..timings(_second(2000000, 25000));
      expect(slow.holds, isFalse);
      frames.dispose();
    });

    test('nothing moves: nothing is measured', () {
      final slow = SlowFramesSceneCondition(
        frames: SceneFrames(),
        after: Duration.zero,
      );
      slow.timings(_second(0, 50000));
      expect(slow.holds, isFalse);
      expect(slow.middle, isNull);
    });
  });

  test('the properties: when and slow, the beans of the conditions', () {
    const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterSceneAutoConfiguration)
        .withBean<SceneBackend>(FakeBackend.new)
        .withBean<SceneMaterialLoader>(FakeMaterialLoader.new)
        .withPropertyValues([
          'spring.flutter.scene.when.touch=still',
          'spring.flutter.scene.when.slow=off',
          'spring.flutter.scene.slow.frame-time=20ms',
          'spring.flutter.scene.slow.after=5s',
        ])
        .run((context) {
          expect(context.startupFailure, isNull);
          final properties = context.getBean<SceneProperties>();
          expect(properties.when, {
            'touch': SceneRenderMode.still,
            'slow': SceneRenderMode.off,
          });
          expect(
            properties.slow.frameTime,
            const Duration(milliseconds: 20),
          );
          final slow = context.getBean<SlowFramesSceneCondition>();
          expect(slow.frameTime, const Duration(milliseconds: 20));
          expect(slow.after, const Duration(seconds: 5));
          expect(
            [
              for (final condition
                  in context.getBean<SceneAvailability>().conditions)
                condition.name,
            ],
            containsAll(['touch', 'slow']),
          );
        });
  });
}
