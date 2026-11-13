// The models of the properties: by name, loaded once, eager ones in a
// row with their events, a failure that the others survive.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

import 'support/fakes.dart';

void main() {
  late RecordingEvents events;
  late FakeImporter importer;
  late FakeBackend backend;

  SceneModels models(
    Map<String, SceneModelProperties> declared, {
    SceneLoad preload = SceneLoad.lazy,
    Map<String, List<int>>? files,
  }) => SceneModels(
    properties: SceneProperties(models: declared, preload: preload),
    resources: FakeResources(
      files ??
          {
            for (final model in declared.values) ?model.source: [1, 2, 3],
          },
    ),
    engine: SceneEngine(backend: backend, events: events),
    importer: importer,
    events: events,
  );

  setUp(() {
    events = RecordingEvents();
    importer = FakeImporter();
    backend = FakeBackend();
  });

  test('by name; an unknown name lists the known', () {
    final scene = models({
      'hero': const SceneModelProperties(source: 'resources:hero.glb'),
      'shop': const SceneModelProperties(source: 'resources:shop.glb'),
    });

    expect(scene.names, ['hero', 'shop']);
    expect(scene['hero'].location, 'resources:hero.glb');
    expect(scene.contains('boss'), isFalse);
    expect(
      () => scene['boss'],
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('"boss"'), contains('hero, shop')),
        ),
      ),
    );
  });

  test('a model without a source names its key', () {
    expect(
      () => models({'hero': const SceneModelProperties()}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('spring.flutter.scene.models.hero.source'),
        ),
      ),
    );
  });

  test('loads once and starts the engine for it', () async {
    final hero = models({
      'hero': const SceneModelProperties(source: 'resources:hero.glb'),
    })['hero'];
    final states = <SceneModelState>[];
    hero.addListener(() => states.add(hero.state));

    final loads = await Future.wait([hero.load(), hero.load()]);

    expect(identical(loads[0], loads[1]), isTrue);
    expect(hero.template, same(loads[0]));
    expect(hero.bytes, 3);
    expect(importer.imported, ['hero']);
    expect(backend.starts, 1);
    expect(states, [SceneModelState.loading, SceneModelState.ready]);
    expect(events.names, [
      'SceneModelLoading',
      'SceneEngineStarting',
      'SceneEngineReady',
      'SceneModelLoaded',
    ]);
  });

  test('eager by its own key, else by the common one', () {
    final scene = models({
      'hero': const SceneModelProperties(
        source: 'a',
        preload: SceneLoad.eager,
      ),
      'shop': const SceneModelProperties(source: 'b'),
    });
    expect(scene.eager.map((model) => model.name), ['hero']);

    final all = models({
      'hero': const SceneModelProperties(source: 'a'),
      'shop': const SceneModelProperties(source: 'b', preload: SceneLoad.lazy),
    }, preload: SceneLoad.eager);
    expect(all.eager.map((model) => model.name), ['hero']);
  });

  test(
    'preload: the eager ones in a row, with their place and progress',
    () async {
      final scene = models({
        'hero': const SceneModelProperties(
          source: 'a',
          preload: SceneLoad.eager,
        ),
        'lazy': const SceneModelProperties(source: 'b'),
        'shop': const SceneModelProperties(
          source: 'c',
          preload: SceneLoad.eager,
        ),
      });
      final progress = <double>[];

      await scene.preload(progress: progress.add);

      expect(importer.imported, ['hero', 'shop']);
      expect(progress, [0.5, 1.0]);
      expect(scene['lazy'].state, SceneModelState.idle);
      final loading = events.events
          .whereType<SceneModelLoadingEvent>()
          .toList();
      expect(
        [for (final event in loading) event.arguments],
        [
          ['hero', 1, 2],
          ['shop', 2, 2],
        ],
      );
    },
  );

  test('a model that fails is published and the rest load', () async {
    final scene = models(
      {
        'hero': const SceneModelProperties(
          source: 'missing',
          preload: SceneLoad.eager,
        ),
        'shop': const SceneModelProperties(
          source: 'c',
          preload: SceneLoad.eager,
        ),
      },
      files: {
        'c': [1],
      },
    );

    await scene.preload();

    expect(scene['hero'].state, SceneModelState.failed);
    expect(scene['hero'].failure, isStateError);
    expect(scene['shop'].state, SceneModelState.ready);
    final failed = events.events.whereType<SceneFailedEvent>().single;
    expect(failed.step, SceneStep.model);
    expect(failed.name, 'hero');
    await expectLater(scene['hero'].load(), throwsStateError);
  });

  test('no model without an engine', () async {
    backend = FakeBackend(fails: true);
    final hero = models({
      'hero': const SceneModelProperties(source: 'a'),
    })['hero'];

    await expectLater(hero.load(), throwsStateError);
    expect(importer.imported, isEmpty);
    expect(hero.state, SceneModelState.failed);
  });

  group('a model at an address', () {
    SceneModels remote(
      String source, {
      FakeTransport? transport,
      bool allowInsecure = false,
    }) => SceneModels(
      properties: SceneProperties(
        models: {'hero': SceneModelProperties(source: source)},
      ),
      resources: FakeResources(const {}),
      engine: SceneEngine(backend: backend, events: events),
      importer: importer,
      events: events,
      transport: transport,
      allowInsecure: allowInsecure,
    );

    test('is read with one GET through the app\'s transport', () async {
      final transport = FakeTransport();
      final hero = remote(
        'https://cdn.example.com/hero.glb',
        transport: transport,
      )['hero'];

      await hero.load();

      expect(hero.resource, isA<RemoteModelResource>());
      expect(transport.requests.single.method, HttpMethod.get);
      expect(
        transport.requests.single.url,
        Uri.parse('https://cdn.example.com/hero.glb'),
      );
      expect(hero.bytes, 2);
      // The app's transport is the app's to close.
      expect(transport.closed, isFalse);
    });

    test('http is refused unless allowed', () async {
      final transport = FakeTransport();
      final refused = remote(
        'http://cdn.example.com/hero.glb',
        transport: transport,
      )['hero'];
      await expectLater(
        refused.load(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('spring.remote.allow-insecure'),
          ),
        ),
      );
      expect(transport.requests, isEmpty);

      final allowed = remote(
        'http://cdn.example.com/hero.glb',
        transport: transport,
        allowInsecure: true,
      )['hero'];
      await allowed.load();
      expect(transport.requests, hasLength(1));
    });

    test('a status that is not a success fails the load', () async {
      final hero = remote(
        'https://cdn.example.com/hero.glb',
        transport: FakeTransport(status: 404),
      )['hero'];
      await expectLater(
        hero.load(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
      expect(hero.state, SceneModelState.failed);
    });
  });

  test('hidden: the debug switch notifies', () {
    final hero = models({
      'hero': const SceneModelProperties(source: 'a'),
    })['hero'];
    var notified = 0;
    hero.addListener(() => notified++);

    hero.hidden = true;
    hero.hidden = true;

    expect(hero.hidden, isTrue);
    expect(notified, 1);
  });
}
