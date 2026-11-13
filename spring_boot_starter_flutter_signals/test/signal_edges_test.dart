// The edges of followed state, on beans made for them (cases/cases.dart,
// as generated): state from a base class and a mixin, late and injected
// fields, a constructor and @PostConstruct, scopes, a method that throws,
// an asynchronous one, effects that write or fail, a cycle.
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show springBootTest;

import 'cases/cases.dart';
import 'spring_gen/cases/cases.spring.dart';

/// The errors reported to Flutter while [body] runs (an effect that
/// throws reports its error there).
List<Object> _reported(void Function() body) {
  final errors = <Object>[];
  final before = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exception);
  try {
    body();
  } finally {
    FlutterError.onError = before;
  }
  return errors;
}

/// What [read] gives each time something it read changes.
(List<T>, void Function()) _follow<T>(T Function() read) {
  final seen = <T>[];
  return (seen, signals.effect(() => seen.add(read())));
}

void main() {
  // An application of this package's own test directory is not given the
  // package's auto-configuration, as its example is: it is named here.
  final app = springBootTest(
    SpringApplication(
      [$application],
      autoConfigurations: [
        springBootAutoConfiguration,
        springBootStarterFlutterAutoConfiguration,
        springBootStarterFlutterSignalsAutoConfiguration,
      ],
    ),
  );

  test('state of a base class and of a mixin is followed', () {
    final bean = app.getBean<Inherited>();
    final (costs, stop) = _follow(() => bean.cost);
    addTearDown(stop);
    expect(bean.seen, [0]);

    bean.count = 2;
    bean.price = 3;
    expect(bean.twice, 4);
    expect(costs, [0, 2, 6]);
    expect(bean.seen, [0, 2]);
  });

  test('an override with the annotation is the one followed', () {
    final bean = app.getBean<Overriding>();
    final (values, stop) = _follow(() => bean.twice);
    addTearDown(stop);
    bean.count = 2;
    expect(values, [0, 6]);
  });

  test('a late field: read before it is assigned fails as always, then it '
      'is followed', () {
    final bean = app.getBean<Late>();
    expect(() => bean.name, throwsA(isA<Error>()));
    // The computed value fails with the same error, not a wrapper of it.
    expect(() => bean.shown, throwsA(isA<Error>()));

    // What read it before is told of the first assignment.
    final (names, stopNames) = _follow(() {
      try {
        return bean.name;
      } on Error {
        return '(none)';
      }
    });
    addTearDown(stopNames);
    final state = app.getBean<SignalBeans>().find(bean)!;
    expect((state.members['name']! as ValueMember).unset, isTrue);

    bean.name = 'Ada';
    expect(names, ['(none)', 'Ada']);
    final (shown, stop) = _follow(() => bean.shown);
    addTearDown(stop);
    bean.name = 'Grace';
    bean.nick = 'G';
    expect(shown, ['Ada', 'Grace', 'G']);
    expect(names, ['(none)', 'Ada', 'Grace']);
  });

  test('a field the container injects is a signal like any other', () {
    final bean = app.getBean<Injected>();
    expect(bean.settings.currency, 'EUR');
    expect(bean.limit, 3);
    expect(bean.doubled, 6);
    // Called as @PostConstruct, and run as an effect.
    expect(bean.started, 2);

    bean.limit = 5;
    expect(bean.doubled, 10);
    expect(bean.started, 3);
  });

  test('a constructor and @PostConstruct read and write the fields', () {
    final bean = app.getBean<Constructed>();
    expect(bean.initial, 10);
    expect(bean.ready, 12);
    expect(bean.count, 6);
    final (values, stop) = _follow(() => bean.twice);
    addTearDown(stop);
    bean.count = 7;
    expect(values, [12, 14]);
  });

  test('each prototype has its own state', () {
    final first = app.getBean<Draft>();
    final second = app.getBean<Draft>();
    expect(identical(first, second), isFalse);
    expect([first.runs, second.runs], [1, 1]);

    first.text = 'a';
    expect([first.runs, second.runs], [2, 1]);
    expect(second.text, '');

    // Both are shown while they are held (the container never destroys a
    // prototype: its state goes with the last reference to it).
    final beans = app.getBean<SignalBeans>();
    expect(
      beans.live,
      containsAll([beans.find(first)!, beans.find(second)!]),
    );
  });

  test('a scoped bean: its state ends with its scope, a new one starts '
      'clean', () {
    final scope = app.getBean<ScreenScope>().scope;
    final beans = app.getBean<SignalBeans>();
    final first = app.getBean<ScreenState>();
    first.taps = 3;
    expect(first.runs, 2);
    final state = beans.find(first)!;
    expect(beans.live, contains(state));

    scope.destroy();

    expect(state.closed, isTrue);
    expect(beans.live, isNot(contains(state)));
    expect(first.destroyed, isTrue);
    // Its @PreDestroy still read the field.
    expect(first.tapsAtDestroy, 3);
    first.taps = 4;
    expect(first.runs, 2);

    final second = app.getBean<ScreenState>();
    expect(identical(first, second), isFalse);
    expect(second.taps, 0);
    second.taps = 1;
    expect(second.runs, 2);
    scope.destroy();
  });

  test('fields of any type; collections by their declared type', () {
    final bean = app.getBean<Shapes>();
    final (pairs, stopPairs) = _follow(() => bean.pair);
    final (titles, stopTitles) = _follow(() => bean.titles.length);
    final (ids, stopIds) = _follow(() => bean.ids.length);
    final (lazy, stopLazy) = _follow(() => bean.lazy.length);
    addTearDown(stopPairs);
    addTearDown(stopTitles);
    addTearDown(stopIds);
    addTearDown(stopLazy);

    bean.pair = (2, 'b');
    bean.pair = (2, 'b');
    expect(pairs, [(1, 'a'), (2, 'b')]);

    // A list behind a type alias, and a set, tell of a change in place.
    bean.titles.add('Dune');
    bean.ids.add(1);
    expect(titles, [0, 1]);
    expect(ids, [0, 1]);
    expect(bean.titles, isA<List<String>>());

    // An Iterable is no collection changed in place: only an assignment.
    bean.lazy = [1, 2];
    expect(lazy, [0, 2]);

    // A field declared as a collection class of its own keeps its type:
    // it is followed by assignment, not in place.
    final (fast, stopFast) = _follow(() => bean.fast.length);
    addTearDown(stopFast);
    expect(bean.fast, isA<HashSet<int>>());
    bean.fast.add(1);
    expect(fast, [0]);
    bean.fast = HashSet.of([1, 2]);
    expect(fast, [0, 2]);
    expect(bean.line, isA<ListQueue<int>>());
    expect(bean.byName, isA<LinkedHashMap<String, int>>());
    expect(bean.frozen, isA<UnmodifiableListView<int>>());

    var called = 0;
    bean.listener = (value) => called += value;
    bean.listener!(2);
    expect(called, 2);
    bean.index = {
      'a': [1],
    };
    expect(bean.index!['a'], [1]);
    bean.any = 'x';
    bean.thing = 1;
    expect([bean.any, bean.thing], ['x', 1]);
  });

  test('the rest of a class is as it was: private and static members, '
      'operators, a generic method, toString', () {
    final bean = app.getBean<Shapes>()..amount = 0;
    bean.inc();
    expect(bean.hidden, greaterThan(0));
    expect(bean.amount, 1);
    expect(bean + 2, 3);
    expect(bean(), 1);
    expect(bean.pick<String>('a', second: 'b'), 'b');
    expect('$bean', 'Shapes(1)');
    Shapes.shared = 4;
    expect(Shapes.shared, 4);
  });

  test('a setter that is no field is one change', () {
    final bean = app.getBean<Shapes>();
    final (seen, stop) = _follow(() => '${bean.amount}/${bean.thing}');
    addTearDown(stop);
    seen.clear();
    bean.both = 9;
    expect(seen, ['9/9']);
  });

  test('a method that throws: what it assigned is told once, the error is '
      "the caller's", () {
    final bean = app.getBean<Steps>();
    bean.seen.clear();
    expect(bean.fail, throwsStateError);
    expect(bean.seen, ['7/7']);
    expect([bean.a, bean.b], [7, 7]);
  });

  test('an asynchronous method is one change up to its first await; after '
      'it each assignment is its own', () async {
    final bean = app.getBean<Steps>();
    bean
      ..a = 0
      ..b = 0;
    bean.seen.clear();
    await bean.later();
    expect(bean.seen, ['1/1', '2/1', '2/2']);
  });

  test('an effect may write what it reads, until it holds', () {
    final bean = app.getBean<Clamped>();
    bean.level = 50;
    expect(bean.level, 10);
    bean.level = 5;
    expect(bean.level, 5);
  });

  test('an effect that throws: the error is reported, not thrown at the '
      'assignment that ran it; the effect lives on', () {
    final bean = app.getBean<Fragile>();
    expect(_reported(() => bean.value = -1), [isArgumentError]);
    expect(bean.value, -1);
    expect(_reported(() => bean.value = 1), isEmpty);
    expect(_reported(() => bean.value = -2), [isArgumentError]);
    bean.value = 0;
  });

  test('computed values that read each other in a circle fail when read', () {
    final bean = app.getBean<Looping>();
    expect(bean.second, 1);
    bean.seed = 1;
    expect(() => bean.second, throwsA(anything));
    bean.seed = 0;
    expect(bean.second, 1);
  });

  test('without the auto-configuration of the starter the application '
      'says that nothing is followed', () async {
    final warnings = <String>[];
    final stop = SpringLog.listen((record) {
      if (record.level == SpringLogLevel.warning) {
        warnings.add(record.message);
      }
    });
    addTearDown(stop);
    final context = await SpringApplication(
      [$application],
      autoConfigurations: [
        springBootAutoConfiguration,
        springBootStarterFlutterAutoConfiguration,
      ],
    ).runAsync(const []);
    addTearDown(context.closeAsync);

    final bean = context.getBean<Inherited>();
    bean.count = 2;
    // Plain fields: nothing ran for the change.
    expect(bean.seen, isEmpty);
    expect(
      warnings,
      contains(
        allOf(
          contains("The bean 'inherited' has members annotated for advice"),
          contains('no advice matches it'),
        ),
      ),
    );
  });

  group('with the advice of another starter on the same bean (a '
      'transaction)', () {
    late Ledger ledger;
    late Audit audit;

    setUp(() {
      ledger = app.getBean<Ledger>();
      audit = app.getBean<Audit>();
      ledger
        ..balance = 0
        ..version = 0;
      audit.log.clear();
      ledger.seen.clear();
    });

    test('both run for a method, and its readers are told once', () {
      ledger.deposit(5);
      expect(audit.log, ['begin deposit', 'commit deposit']);
      expect(ledger.seen, ['5/1']);
    });

    test("the bean's own calls skip the other advice, as in any bean; "
        'the state is followed all the same, in one change', () {
      ledger.depositTwice(1);
      expect(audit.log, isEmpty);
      expect(ledger.seen, ['2/2']);
    });

    test('a method that fails: the other advice rolls back, the fields '
        'keep what was assigned and their readers were told', () {
      expect(ledger.failing, throwsStateError);
      expect(audit.log, ['begin failing', 'rollback failing']);
      expect(ledger.balance, 100);
      expect(ledger.seen, ['100/0']);
    });

    test('an asynchronous method: one change up to its first await', () async {
      await ledger.transfer(3);
      expect(audit.log, ['begin transfer', 'commit transfer']);
      expect(ledger.seen, ['-3/0', '-3/1']);
    });

    test('on a computed value the other advice runs when it is computed, '
        'not for each read of the kept one', () async {
      ledger.balance = 4;
      expect(await ledger.doubled, 8);
      expect(await ledger.doubled, 8);
      expect(await ledger.doubled, 8);
      expect(audit.log, ['begin doubled', 'commit doubled']);

      ledger.balance = 1;
      expect(await ledger.doubled, 2);
      expect(audit.log, [
        'begin doubled',
        'commit doubled',
        'begin doubled',
        'commit doubled',
      ]);
    });

    test('an advice with an earlier order (method security) runs for '
        'every read of a computed value, and a kept one is not handed to '
        'a caller it refuses', () {
      final guard = app.getBean<Guard>()
        ..owner = true
        ..checks = 0;
      addTearDown(() => guard.owner = true);
      ledger.balance = 4;
      final computed = ledger.totals;

      expect(ledger.total, 4);
      expect(ledger.total, 4);
      // Checked twice, computed once.
      expect(guard.checks, 2);
      expect(ledger.totals, computed + 1);

      guard.owner = false;
      expect(() => ledger.total, throwsStateError);
      expect(ledger.totals, computed + 1);

      guard.owner = true;
      expect(ledger.total, 4);
      expect(ledger.totals, computed + 1);
    });
  });

  group('a guarded value over a plain field (method security)', () {
    late Guard guard;
    late Vault vault;
    late Reader reader;

    setUp(() {
      guard = app.getBean<Guard>()..owner = true;
      vault = app.getBean<Vault>()..secret = 0;
      reader = app.getBean<Reader>();
      reader.seen.clear();
      addTearDown(() => guard.owner = true);
    });

    test('the field itself is anybody\'s: only reads through the guarded '
        'member are refused', () {
      guard.owner = false;
      // The reader bean's effect is refused meanwhile, and says so.
      expect(_reported(() => vault.secret = 1), [isStateError]);
      expect(vault.secret, 1);
      expect(() => vault.report, throwsStateError);
      guard.owner = true;
      expect(vault.report, 2);
    });

    test("the bean's own read of it is not guarded, as a call on this is "
        'not in any bean: a value made from it is whoever reads that', () {
      expect(vault.summary, 1);
      guard.owner = false;
      // Kept, and not guarded itself.
      expect(vault.summary, 1);
      _reported(() => vault.secret = 4);
      expect(vault.summary, 9);
      expect(() => vault.report, throwsStateError);
    });

    test('a value of another bean made from it: refused for a caller who '
        'may not read it, and computed again for the next who may', () {
      vault.secret = 1;
      expect(reader.view, 3);
      guard.owner = false;
      // Kept: the value is the reader bean's, which is not guarded.
      expect(reader.view, 3);
      _reported(() => vault.secret = 2);
      expect(() => reader.view, throwsStateError);
      expect(() => reader.view, throwsStateError);
      guard.owner = true;
      // The refusal was not kept.
      expect(reader.view, 5);
      vault.secret = 3;
      expect(reader.view, 7);
    });

    test('an effect of another bean that reads it: run by a change of a '
        'caller who may not read it, it is refused and reported; the '
        'assignment goes through and the effect goes on following', () {
      vault.secret = 1;
      expect(reader.seen, [2]);
      guard.owner = false;
      expect(_reported(() => vault.secret = 2), [isStateError]);
      expect(vault.secret, 2);
      expect(reader.seen, [2]);
      guard.owner = true;
      vault.secret = 3;
      expect(reader.seen, [2, 6]);
    });

    test('a guarded effect: run by whoever changes what it read, refused '
        'and reported for one who may not, alive for the next', () {
      final watchman = app.getBean<Watchman>();
      watchman.door = 0;
      watchman.noted.clear();
      guard.owner = false;
      expect(_reported(() => watchman.door = 1), [isStateError]);
      expect(watchman.door, 1);
      expect(watchman.noted, isEmpty);
      guard.owner = true;
      watchman.door = 2;
      expect(watchman.noted, [2]);
    });
  });

  test('an @EventListener method of such a bean', () {
    final bean = app.getBean<Listening>();
    final (heard, stop) = _follow(() => bean.heard);
    addTearDown(stop);
    app.context.publishEvent(Ping(bean));
    expect(heard, [0, 1]);
  });
}
