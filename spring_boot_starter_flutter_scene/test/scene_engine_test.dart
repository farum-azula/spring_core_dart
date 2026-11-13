// The engine's one start: its states, its events, a failure that does not
// throw; and what the availability says of it.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

import 'support/fakes.dart';

void main() {
  test('starts once, however many ask', () async {
    final backend = FakeBackend();
    final events = RecordingEvents();
    final engine = SceneEngine(backend: backend, events: events);
    final states = <SceneEngineState>[];
    engine.addListener(() => states.add(engine.state));

    expect(engine.state, SceneEngineState.idle);
    final results = await Future.wait([engine.start(), engine.start()]);

    expect(results, [true, true]);
    expect(backend.starts, 1);
    expect(engine.isReady, isTrue);
    expect(engine.took, isNotNull);
    expect(states, [SceneEngineState.starting, SceneEngineState.ready]);
    expect(events.names, ['SceneEngineStarting', 'SceneEngineReady']);
  });

  test('a failed start is kept, published and not thrown', () async {
    final events = RecordingEvents();
    final engine = SceneEngine(
      backend: FakeBackend(fails: true),
      events: events,
    );

    expect(await engine.start(), isFalse);
    expect(engine.hasFailed, isTrue);
    expect(engine.failure, isStateError);
    expect(events.names, [
      'SceneEngineStarting',
      'SceneFailed',
      'SceneUnavailable',
    ]);
    final unavailable = events.events.last as SceneUnavailableEvent;
    expect(unavailable.reason, SceneUnavailable.engine);
  });

  group('the availability', () {
    SceneAvailability availability(
      SceneProperties properties, {
      bool fails = false,
    }) => SceneAvailability(
      properties: properties,
      engine: SceneEngine(
        backend: FakeBackend(fails: fails),
        events: RecordingEvents(),
      ),
    );

    test('draws once the engine started', () async {
      final scenes = availability(const SceneProperties());
      var notified = 0;
      scenes.addListener(() => notified++);

      expect(scenes.draws, isTrue);
      expect(scenes.isReady, isFalse);
      await scenes.engine.start();
      expect(scenes.isReady, isTrue);
      expect(scenes.animates, isTrue);
      expect(notified, 2);
    });

    test('render: off', () {
      final scenes = availability(
        const SceneProperties(render: SceneRenderMode.off),
      );
      expect(scenes.draws, isFalse);
      expect(scenes.reason, SceneUnavailable.off);
    });

    test('render: still draws, and does not animate', () {
      final scenes = availability(
        const SceneProperties(render: SceneRenderMode.still),
      );
      expect(scenes.draws, isTrue);
      expect(scenes.animates, isFalse);
    });

    test('a failed engine', () async {
      final scenes = availability(const SceneProperties(), fails: true);
      await scenes.engine.start();
      expect(scenes.draws, isFalse);
      expect(scenes.reason, SceneUnavailable.engine);
    });

    test('the frame ceiling', () {
      final scenes = availability(const SceneProperties(maxFrameRate: 30));
      expect(scenes.frameRate(), 30);
      expect(scenes.frameRate(12), 12);
      expect(scenes.frameRate(60), 30);
    });
  });
}
