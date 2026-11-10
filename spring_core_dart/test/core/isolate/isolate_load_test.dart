import 'dart:async';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void _spin(Duration time) {
  final watch = Stopwatch()..start();
  while (watch.elapsed < time) {}
}

void main() {
  group('IsolateLoadSampler', () {
    test(
      'nothing measured before the first read; then a free isolate',
      () async {
        final sampler = IsolateLoadSampler(
          interval: const Duration(milliseconds: 10),
        );
        addTearDown(sampler.stop);
        expect(sampler.isRunning, isFalse);
        final first = sampler.load();
        expect(first.name, 'main');
        expect(first.kind, 'main');
        expect(first.busy, isNull);
        expect(first.lag, isNull);
        expect(sampler.isRunning, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 200));
        final free = sampler.load();
        expect(free.busy, lessThan(0.5));
        expect(free.lag, isNotNull);
        expect(free.memory, greaterThan(0));
      },
    );

    test('a blocked event loop shows as lag and a busy share', () async {
      final sampler = IsolateLoadSampler(
        interval: const Duration(milliseconds: 10),
      )..load();
      addTearDown(sampler.stop);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 12));
        _spin(const Duration(milliseconds: 60));
      }
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final busy = sampler.load();
      expect(busy.maxLag, greaterThan(const Duration(milliseconds: 30)));
      expect(busy.busy, greaterThan(0.4));
    });

    test('stops by itself when nobody reads', () async {
      final sampler = IsolateLoadSampler(
        interval: const Duration(milliseconds: 5),
        idleAfter: const Duration(milliseconds: 30),
      )..load();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(sampler.isRunning, isFalse);
      // The next read starts it again.
      sampler.load();
      expect(sampler.isRunning, isTrue);
      sampler.stop();
    });

    test('the name and the kind of its isolate', () {
      IsolateInfo.current = const IsolateInfo(
        name: 'isolate-2',
        index: 2,
        primary: false,
      );
      addTearDown(() => IsolateInfo.current = const IsolateInfo());
      final sampler = IsolateLoadSampler();
      addTearDown(sampler.stop);
      final load = sampler.load();
      expect(load.name, 'isolate-2');
      expect(load.kind, 'server');
      expect(load.memory, isNull, reason: 'the process row is the primary');
    });
  });

  test('IsolateLoad crosses as JSON', () {
    const load = IsolateLoad(
      name: 'task-1',
      kind: 'task',
      busy: 0.5,
      lag: Duration(milliseconds: 3),
      maxLag: Duration(milliseconds: 9),
      active: 1,
      memory: 1024,
      details: {'queued': 4},
    );
    final back = IsolateLoad.fromJson(load.toJson());
    expect(back.toJson(), load.toJson());
    expect(back.lag, const Duration(milliseconds: 3));
    expect(
      const IsolateLoad(name: 'a', kind: 'b').toJson(),
      {'name': 'a', 'kind': 'b'},
    );
  });

  group('IsolateLoads', () {
    test('asks every source in order, then what is tracked', () async {
      final loads = IsolateLoads([
        _Source(const [IsolateLoad(name: 'main', kind: 'main')]),
        _Source(const [
          IsolateLoad(name: 'isolate-1', kind: 'server'),
          IsolateLoad(name: 'isolate-2', kind: 'server'),
        ]),
      ]);
      final done = Completer<int>();
      final tracked = loads.track('report', done.future);
      expect(loads.all().map((l) => l.name), [
        'main',
        'isolate-1',
        'isolate-2',
        'report',
      ]);
      expect(loads.all().last.kind, 'tracked');
      done.complete(7);
      expect(await tracked, 7);
      expect(loads.all().map((l) => l.name), [
        'main',
        'isolate-1',
        'isolate-2',
      ]);
    });

    test('loads of one name are one row', () {
      final loads = IsolateLoads([
        _Source(const [
          IsolateLoad(name: 'main', kind: 'main', busy: 0.2, details: {'a': 1}),
        ]),
        _Source(const [
          IsolateLoad(
            name: 'main',
            kind: 'web',
            busy: 0.9,
            active: 4,
            details: {'b': 2},
          ),
        ]),
      ]);
      final row = loads.all().single;
      expect(row.kind, 'main');
      expect(row.busy, 0.2, reason: 'the first source that knows it');
      expect(row.active, 4);
      expect(row.details, {'a': 1, 'b': 2});
    });

    test('a tracked failure still ends the row', () async {
      final loads = IsolateLoads(const []);
      await expectLater(
        loads.track('x', Future<void>.error(StateError('no'))),
        throwsStateError,
      );
      expect(loads.all(), isEmpty);
    });
  });

  test('IsolateReports: own reports and the other isolates by id', () {
    final reports = IsolateReports([_Reporter('qps', 5), _Reporter('n', 1)])
      ..put('isolate-1', {'qps': 7})
      ..put('isolate-2', {'other': 0});
    expect(reports.own(), {'qps': 5, 'n': 1});
    expect(reports.of('qps', own: 'main'), {'main': 5, 'isolate-1': 7});
    reports.remove('isolate-1');
    expect(reports.of('qps', own: 'main'), {'main': 5});
    // By number, whatever the order they reported in.
    reports
      ..put('isolate-10', {'qps': 1})
      ..put('isolate-2', {'qps': 2})
      ..put('isolate-1', {'qps': 3});
    expect(reports.of('qps', own: 'main').keys, [
      'main',
      'isolate-1',
      'isolate-2',
      'isolate-10',
    ]);
  });
}

final class _Source implements IsolateLoadSource {
  _Source(this._loads);
  final List<IsolateLoad> _loads;
  @override
  List<IsolateLoad> loads() => _loads;
}

final class _Reporter implements IsolateReporter {
  _Reporter(this.id, this.value);
  @override
  final String id;
  final Object? value;
  @override
  Object? report() => value;
}
