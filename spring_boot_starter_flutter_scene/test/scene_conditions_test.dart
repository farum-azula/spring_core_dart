// The conditions under which scenes draw less: the mode of each in
// spring.flutter.scene.when, the least one winning; a touch screen; scenes
// too slow here, decided by their own frames before they show and never by
// switching them off in front of the user.
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
  bool get settled => true;

  @override
  String get state => _holds ? 'holds' : 'does not hold';
}

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
    var now = Duration.zero;
    SlowFramesSceneCondition slow(SceneFrames frames) =>
        SlowFramesSceneCondition(frames: frames, clock: () => now);

    // [count] beats of the scenes of [ms] each, a 60th of a second apart.
    void beats(SlowFramesSceneCondition condition, int count, double ms) {
      for (var i = 0; i < count; i++) {
        now += const Duration(microseconds: 16667);
        condition.drawn(Duration(microseconds: (ms * 1000).round()));
      }
    }

    setUp(() => now = Duration.zero);

    test('not named in when: follows nothing, waits for nothing', () {
      final condition = slow(SceneFrames());
      expect(condition.settled, isTrue);
      expect(condition.holds, isFalse);
      expect(condition.state, 'not followed');
    });

    test('decided before the scenes show, the first frames left out', () {
      final condition = slow(SceneFrames())..start();
      var notified = 0;
      condition.addListener(() => notified++);
      expect(condition.settled, isFalse, reason: 'the scenes wait for it');
      // The engine builds its programs on the first frames: slow, left out.
      beats(condition, condition.warmUp, 40);
      expect(condition.settled, isFalse);
      beats(condition, condition.probe - 1, 3);
      expect(condition.settled, isFalse);
      expect(condition.state, contains('${condition.probe - 1} of '));
      beats(condition, 1, 3);
      expect(condition.settled, isTrue);
      expect(condition.holds, isFalse);
      expect(condition.middle, const Duration(milliseconds: 3));
      expect(notified, 1, reason: 'the scenes show');
    });

    test('scenes too slow here: it holds before they show', () {
      final condition = slow(SceneFrames())..start();
      beats(condition, condition.warmUp + condition.probe, 11);
      expect(condition.settled, isTrue);
      expect(condition.holds, isTrue);
      expect(condition.state, startsWith('slow: 11.0 ms a beat'));
    });

    test('a probe slow to come ends after three seconds with what it has', () {
      final condition = slow(SceneFrames())..start();
      beats(condition, condition.warmUp, 3);
      for (var i = 0; i < 4; i++) {
        now += const Duration(seconds: 1);
        condition.drawn(const Duration(milliseconds: 20));
      }
      expect(condition.settled, isTrue);
      expect(condition.holds, isTrue);
    });

    test('after they show, slow beats only mark it; it holds when no scene '
        'moves', () {
      final frames = SceneFrames()..join(#scene, 60, () => true);
      final condition = slow(frames)..start();
      beats(condition, condition.warmUp + condition.probe, 3);
      expect(condition.holds, isFalse);
      // Slow for longer than `after` while the scene is on the screen.
      beats(condition, 60 * 4, 12);
      expect(condition.holds, isFalse, reason: 'never in front of the user');
      expect(condition.state, contains('holds when no scene moves'));
      frames.leave(#scene);
      expect(condition.holds, isTrue);
      frames.dispose();
    });

    test('a slow moment after they show is forgotten by a quick one', () {
      final frames = SceneFrames()..join(#scene, 60, () => true);
      final condition = slow(frames)..start();
      beats(condition, condition.warmUp + condition.probe, 3);
      beats(condition, 60 * 2, 12);
      beats(condition, 60, 2);
      beats(condition, 60 * 2, 12);
      frames.leave(#scene);
      expect(condition.holds, isFalse);
      frames.dispose();
    });

    test('the scenes that move wait while it finds out, if when names it', () {
      final condition = slow(SceneFrames())..start();
      expect(
        availability({'slow': SceneRenderMode.still}, [condition]).deciding,
        isTrue,
      );
      expect(availability(null, [condition]).deciding, isFalse);
      beats(condition, condition.warmUp + condition.probe, 3);
      expect(
        availability({'slow': SceneRenderMode.still}, [condition]).deciding,
        isFalse,
      );
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
          'spring.flutter.scene.slow.probe=30',
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
          expect(slow.probe, 30);
          expect(slow.settled, isFalse, reason: 'when names it: measuring');
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
