// The materials of the properties: by name, the first load once and
// timed, a material of its own for every use, eager ones with the splash,
// a failure the others survive, the uses by scene for the debug tab.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

import 'support/fakes.dart';

void main() {
  late RecordingEvents events;
  late FakeMaterialLoader loader;
  late FakeBackend backend;

  SceneMaterials materials(
    Map<String, SceneMaterialProperties> declared, {
    SceneLoad preload = SceneLoad.lazy,
  }) => SceneMaterials(
    properties: SceneProperties(materials: declared, preload: preload),
    engine: SceneEngine(backend: backend, events: events),
    loader: loader,
    events: events,
  );

  setUp(() {
    events = RecordingEvents();
    loader = FakeMaterialLoader();
    backend = FakeBackend();
  });

  test('by name; an unknown name lists the known', () {
    final scene = materials({
      'glass': const SceneMaterialProperties(source: 'assets/glass.fmat'),
      'neon': const SceneMaterialProperties(source: 'assets/neon.fmat'),
    });

    expect(scene.names, ['glass', 'neon']);
    expect(scene['glass'].location, 'assets/glass.fmat');
    expect(scene.contains('wall'), isFalse);
    expect(
      () => scene['wall'],
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('"wall"'), contains('glass, neon')),
        ),
      ),
    );
    expect(
      () => materials({})['wall'],
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('none is declared'),
        ),
      ),
    );
  });

  test('a material without a source names its key', () {
    expect(
      () => materials({'glass': const SceneMaterialProperties()}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('spring.flutter.scene.materials.glass.source'),
        ),
      ),
    );
  });

  test(
    'the first use loads it once, starts the engine, and is timed',
    () async {
      final glass = materials({
        'glass': const SceneMaterialProperties(source: 'assets/glass.fmat'),
      })['glass'];
      final states = <SceneMaterialState>[];
      glass.addListener(() => states.add(glass.state));

      final made = await Future.wait([glass.create(), glass.create()]);

      expect(identical(made[0], made[1]), isFalse);
      expect(loader.loaded, ['assets/glass.fmat', 'assets/glass.fmat']);
      expect(backend.starts, 1);
      expect(states, [SceneMaterialState.loading, SceneMaterialState.ready]);
      expect(glass.took, isNotNull);
      expect(glass.loadedWithSplash, isFalse);
      expect(glass.shading, 'unlit');
      expect(glass.opaque, isFalse);
      expect(glass.parameters, ['tint', 'time']);
      expect(events.names, [
        'SceneMaterialLoading',
        'SceneEngineStarting',
        'SceneEngineReady',
        'SceneMaterialLoaded',
      ]);
    },
  );

  test('every use gets a material of its own', () async {
    final glass = materials({
      'glass': const SceneMaterialProperties(source: 'a'),
    })['glass'];

    final first = await glass.create();
    final second = await glass.create();
    final third = await glass.create();

    expect({first, second, third}, hasLength(3));
  });

  test('eager by its own key, else by the common one', () {
    final scene = materials({
      'glass': const SceneMaterialProperties(
        source: 'a',
        preload: SceneLoad.eager,
      ),
      'neon': const SceneMaterialProperties(source: 'b'),
    });
    expect(scene.eager.map((material) => material.name), ['glass']);

    final all = materials({
      'glass': const SceneMaterialProperties(source: 'a'),
      'neon': const SceneMaterialProperties(
        source: 'b',
        preload: SceneLoad.lazy,
      ),
    }, preload: SceneLoad.eager);
    expect(all.eager.map((material) => material.name), ['glass']);
  });

  test(
    'preload: the eager ones in a row; the first use takes the one made',
    () async {
      final scene = materials({
        'glass': const SceneMaterialProperties(
          source: 'a',
          preload: SceneLoad.eager,
        ),
        'lazy': const SceneMaterialProperties(source: 'b'),
        'neon': const SceneMaterialProperties(
          source: 'c',
          preload: SceneLoad.eager,
        ),
      });
      final progress = <double>[];

      await scene.preload(progress: progress.add);

      expect(loader.loaded, ['a', 'c']);
      expect(progress, [0.5, 1.0]);
      expect(scene['glass'].loadedWithSplash, isTrue);
      expect(scene['lazy'].state, SceneMaterialState.idle);
      expect(
        [
          for (final event
              in events.events.whereType<SceneMaterialLoadingEvent>())
            event.arguments,
        ],
        [
          ['glass', 1, 2],
          ['neon', 2, 2],
        ],
      );

      final first = await scene['glass'].create();
      expect(loader.loaded, ['a', 'c'], reason: 'the preloaded one is used');
      final second = await scene['glass'].create();
      expect(loader.loaded, ['a', 'c', 'a']);
      expect(identical(first, second), isFalse);
    },
  );

  test('a material that fails is published and the rest load', () async {
    loader = FakeMaterialLoader(failing: {'missing'});
    final scene = materials({
      'glass': const SceneMaterialProperties(
        source: 'missing',
        preload: SceneLoad.eager,
      ),
      'neon': const SceneMaterialProperties(
        source: 'c',
        preload: SceneLoad.eager,
      ),
    });

    await scene.preload();

    expect(scene['glass'].state, SceneMaterialState.failed);
    expect(scene['glass'].failure, isStateError);
    expect(scene['neon'].state, SceneMaterialState.ready);
    final failed = events.events.whereType<SceneFailedEvent>().single;
    expect(failed.step, SceneStep.material);
    expect(failed.name, 'glass');
    expect(failed.defaultMessage, '{0} did not load');
    await expectLater(scene['glass'].create(), throwsStateError);
  });

  test('a failed material loads again on reload', () async {
    final failing = {'a'};
    loader = FakeMaterialLoader(failing: failing);
    final glass = materials({
      'glass': const SceneMaterialProperties(source: 'a'),
    })['glass'];
    await expectLater(glass.create(), throwsStateError);

    failing.clear();
    await glass.reload();

    expect(glass.state, SceneMaterialState.ready);
  });

  test('no material without an engine', () async {
    backend = FakeBackend(fails: true);
    final glass = materials({
      'glass': const SceneMaterialProperties(source: 'a'),
    })['glass'];

    await expectLater(glass.create(), throwsStateError);
    expect(loader.loaded, isEmpty);
    expect(glass.state, SceneMaterialState.failed);
  });

  test('the uses by scene, told after the build', () async {
    final glass = materials({
      'glass': const SceneMaterialProperties(source: 'a'),
    })['glass'];
    var told = 0;
    glass.addListener(() => told++);

    glass
      ..use('match-header')
      ..use('match-header')
      ..use('page');
    expect(told, 0, reason: 'not while the scene is built');
    await Future<void>.delayed(Duration.zero);

    expect(told, 1);
    expect(glass.uses, {'match-header': 2, 'page': 1});
    expect(glass.useCount, 3);

    glass
      ..release('page')
      ..release('match-header');
    await Future<void>.delayed(Duration.zero);
    expect(glass.uses, {'match-header': 1});
  });

  test('hidden: the debug switch, told at once', () {
    final glass = materials({
      'glass': const SceneMaterialProperties(source: 'a'),
    })['glass'];
    var told = 0;
    glass.addListener(() => told++);

    glass
      ..hidden = true
      ..hidden = true;

    expect(glass.hidden, isTrue);
    expect(told, 1);
  });
}
