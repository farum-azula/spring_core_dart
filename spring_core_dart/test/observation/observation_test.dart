import 'dart:async';

import 'package:spring_core_dart/observation.dart';
import 'package:test/test.dart';

class Recording extends ObservationHandler {
  Recording(this.label, this.log, {this.only});

  final String label;
  final List<String> log;
  final String? only;

  @override
  bool supportsContext(ObservationContext context) =>
      only == null || context.name == only;

  @override
  void onStart(ObservationContext context) =>
      log.add('$label start ${context.name}');

  @override
  void onError(ObservationContext context) =>
      log.add('$label error ${context.name} ${context.error}');

  @override
  void onStop(ObservationContext context) =>
      log.add('$label stop ${context.name}');
}

class Stopped extends ObservationHandler {
  final contexts = <ObservationContext>[];

  @override
  void onStop(ObservationContext context) => contexts.add(context);
}

void main() {
  late List<String> log;
  late Duration now;
  Duration clock() => now;

  setUp(() {
    log = [];
    now = Duration.zero;
  });

  test('handlers: start and error in order, stop in reverse', () {
    final registry = ObservationRegistry(
      handlers: [Recording('a', log), Recording('b', log)],
    );
    expect(
      () => registry.observe('work', () => throw StateError('boom')),
      throwsStateError,
    );
    expect(log, [
      'a start work',
      'b start work',
      'a error work Bad state: boom',
      'b error work Bad state: boom',
      'b stop work',
      'a stop work',
    ]);
  });

  test('supportsContext picks the observations a handler hears of', () {
    ObservationRegistry(handlers: [Recording('a', log, only: 'mine')])
      ..observe('mine', () {})
      ..observe('other', () {});
    expect(log, ['a start mine', 'a stop mine']);
  });

  test('context: name, tags, timing; start and stop once', () {
    final stopped = Stopped();
    final registry = ObservationRegistry(handlers: [stopped], clock: clock);
    now = const Duration(milliseconds: 5);
    final observation = registry
        .start(
          'orders.load',
          contextualName: 'load',
          lowCardinalityKeyValues: {'source': 'remote'},
        )
        .lowCardinalityKeyValue('outcome', 'ok')
        .start();
    expect(observation.context.isRunning, isTrue);
    now = const Duration(milliseconds: 12);
    observation
      ..stop()
      ..stop();
    final context = stopped.contexts.single;
    expect(context.name, 'orders.load');
    expect(context.contextualName, 'load');
    expect(context.lowCardinalityKeyValues, {
      'source': 'remote',
      'outcome': 'ok',
    });
    expect(context.startedAt, const Duration(milliseconds: 5));
    expect(context.duration, const Duration(milliseconds: 7));
    expect(context.isRunning, isFalse);
    expect(context.error, isNull);
  });

  test('a Future result stops the observation when it completes', () async {
    final stopped = Stopped();
    final registry = ObservationRegistry(handlers: [stopped], clock: clock);
    final completer = Completer<int>();
    final future = registry.observe('wait', () => completer.future);
    expect(future, isA<Future<int>>());
    expect(stopped.contexts, isEmpty);
    now = const Duration(milliseconds: 30);
    completer.complete(42);
    expect(await future, 42);
    expect(stopped.contexts.single.duration, const Duration(milliseconds: 30));
  });

  test('a failed Future is recorded and passed on', () async {
    final stopped = Stopped();
    final registry = ObservationRegistry(handlers: [stopped]);
    Future<int> fail() async => throw ArgumentError('bad');
    await expectLater(registry.observe('fail', fail), throwsArgumentError);
    expect(stopped.contexts.single.error, isA<ArgumentError>());
    expect(stopped.contexts.single.stackTrace, isNotNull);
  });

  test('observations nest across async gaps', () async {
    final stopped = Stopped();
    final registry = ObservationRegistry(handlers: [stopped]);
    expect(registry.currentObservation, isNull);
    await registry.observe('outer', () async {
      await Future<void>.delayed(Duration.zero);
      await registry.observe('inner', () async {
        await Future<void>.delayed(Duration.zero);
        expect(registry.currentObservation?.context.name, 'inner');
        registry.observe('innermost', () {});
      });
      expect(registry.currentObservation?.context.name, 'outer');
      final sibling = registry.start('sibling');
      await Future<void>.delayed(Duration.zero);
      sibling.stop();
    });
    expect(registry.currentObservation, isNull);
    final byName = {for (final c in stopped.contexts) c.name: c};
    expect(byName['outer']!.parent, isNull);
    expect(byName['inner']!.parent, same(byName['outer']));
    expect(byName['innermost']!.parent, same(byName['inner']));
    expect(byName['sibling']!.parent, same(byName['outer']));
    expect(
      stopped.contexts.map((c) => c.name),
      ['innermost', 'inner', 'sibling', 'outer'],
    );
    final ids = stopped.contexts.map((c) => c.id).toSet();
    expect(ids, hasLength(4));
  });

  test('an explicit parent wins over the current observation', () {
    final stopped = Stopped();
    final registry = ObservationRegistry(handlers: [stopped]);
    final root = registry.start('root');
    registry.observe('other', () {
      registry.observation('child', parent: root).observe(() {});
    });
    root.stop();
    final byName = {for (final c in stopped.contexts) c.name: c};
    expect(byName['child']!.parent, same(root.context));
  });

  test('scoped makes an observation current without starting it', () {
    final stopped = Stopped();
    final registry = ObservationRegistry(handlers: [stopped]);
    final observation = registry.observation('idle');
    observation.scoped(() {
      expect(registry.currentObservation, same(observation));
    });
    expect(observation.context.startedAt, isNull);
    observation.stop();
    expect(stopped.contexts, isEmpty);
  });

  test('handlers added later hear of later observations', () {
    final registry = ObservationRegistry()
      ..observe('before', () {})
      ..addHandler(Recording('a', log))
      ..observe('after', () {});
    expect(log, ['a start after', 'a stop after']);
    expect(registry.handlers, hasLength(1));
  });

  group('noop', () {
    test('the noop registry runs the work and records nothing', () async {
      const registry = ObservationRegistry.noop;
      expect(registry.isNoop, isTrue);
      expect(registry.observe('x', () => 1), 1);
      expect(await registry.observe('y', () async => 2), 2);
      expect(
        () => registry.observe('z', () => throw StateError('e')),
        throwsStateError,
      );
      final observation = registry.start('s')
        ..lowCardinalityKeyValue('k', 'v')
        ..error(StateError('ignored'))
        ..stop();
      expect(observation, same(Observation.noop));
      expect(observation.isNoop, isTrue);
      expect(observation.context.lowCardinalityKeyValues, isEmpty);
      expect(registry.currentObservation, isNull);
      expect(
        () => registry.addHandler(Recording('a', log)),
        throwsUnsupportedError,
      );
    });

    test('a registry without handlers creates noop observations', () {
      final registry = ObservationRegistry();
      expect(registry.isNoop, isFalse);
      expect(registry.start('x'), same(Observation.noop));
    });
  });
}
