// The buffer of async work and the flush schedules of the application, on
// the code the generator writes, with a real store and two users.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:signals_checks/matrix.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'support.dart';

final _denied = throwsA(isA<AccessDeniedException>());

(List<T>, void Function()) _follow<T>(T Function() read) {
  final seen = <T>[];
  final stop = signals.effect(() => seen.add(read()));
  addTearDown(stop);
  return (seen, stop);
}

Future<void> _settle([int milliseconds = 5]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  late ConfigurableApplicationContext app;
  late Cart cart;
  setUp(() async {
    app = await startApp();
    cart = app.getBean<Cart>();
    await app.getBean<Shelf>().setUp();
  });
  tearDown(() => app.closeAsync());

  group('@SignalBuffer', () {
    test('others and readers see the old values until it ends, then one '
        'change', () async {
      final (seen, _) = _follow(() => '${cart.count}/${cart.other}');
      final gate = Completer<void>();
      final running = cart.fill(4, gate.future);
      await _settle();
      expect(cart.count, 0);
      expect(cart.lines, isEmpty);
      expect(seen, ['0/0']);
      gate.complete();
      await running;
      await told();
      expect(seen, ['0/0', '4/4']);
      expect(cart.lines, ['4']);
    });

    test('its own code reads what it wrote', () async {
      expect(await cart.readsOwn(5), [5, 0]);
    });

    test('an error drops its writes by default', () async {
      await expectLater(cart.fails(6), throwsStateError);
      await told();
      expect(cart.count, 0);
    });

    test('buffer.on-error: publish tells them', () async {
      final publishing = await startApp([
        '--spring.flutter.signals.buffer.on-error=publish',
      ]);
      addTearDown(publishing.closeAsync);
      final bean = publishing.getBean<Cart>();
      await expectLater(bean.fails(6), throwsStateError);
      await told();
      expect(bean.count, 6);
    });

    test('nested, also through this: one buffer, told once', () async {
      final (seen, _) = _follow(() => '${cart.count}/${cart.other}');
      await cart.outer(1);
      await told();
      expect(seen, ['0/0', '2/3']);
    });

    test(
      'a timer or a future that outlives it writes as any code does',
      () async {
        await cart.leavesWork();
        await told();
        expect(cart.count, 1);
        await _settle(30);
        expect([cart.count, cart.other], [2, 3]);
      },
    );

    test(
      'a loader without a buffer shows both changes; with one, none',
      () async {
        final (seen, _) = _follow(() => cart.loading);
        var gate = Completer<void>();
        var running = cart.showLoader(gate.future);
        await told();
        expect(seen, [false, true]);
        gate.complete();
        await running;
        await told();
        expect(seen, [false, true, false]);
        seen.clear();
        gate = Completer<void>();
        running = cart.loaderBuffered(gate.future);
        await told();
        gate.complete();
        await running;
        await told();
        expect(seen, isEmpty, reason: 'documented: a buffer hides the loader');
      },
    );

    test('inside @Transactional: published by the commit', () async {
      await cart.inTransaction(7);
      await told();
      expect(cart.count, 7);
    });

    test('inside @Transactional: dropped by the rollback', () async {
      await expectLater(cart.inTransaction(8, fail: true), throwsStateError);
      await told();
      expect(cart.count, 0);
    });

    test('with @PreAuthorize: refused writes nothing', () async {
      await expectLater(asAda(() => cart.guardedFill(3)), _denied);
      expect(cart.count, 0);
      await asRoot(() => cart.guardedFill(3));
      await told();
      expect(cart.count, 3);
    });

    test(
      'with @PostFilter and @PostAuthorize: writes told, result checked',
      () async {
        expect(
          (await asAda(cart.filteredWithWrites)).map((n) => n.owner),
          ['ada'],
        );
        await expectLater(asBob(cart.authorizedWithWrites), _denied);
        await told();
        expect(cart.count, 1);
      },
    );

    test('with a guard and a cache: one body, writes told once', () async {
      expect(await asAda(cart.cachedLoad), 1);
      expect(await asBob(cart.cachedLoad), 1);
      await told();
      expect(cart.count, 10);
      await expectLater(asNobody(cart.cachedLoad), throwsA(anything));
      cart.evictLoads();
      expect(await asAda(cart.cachedLoad), 2);
      await told();
      expect(cart.count, 20);
    });

    test('with @Scheduled: readers see whole runs only', () async {
      final (seen, _) = _follow(() => cart.ticks);
      await _settle(40);
      expect(seen.length, greaterThan(1));
      expect(seen, everyElement(predicate<int>((ticks) => ticks.isEven)));
    });

    test('with @EventListener', () async {
      final (seen, _) = _follow(() => '${cart.count}/${cart.other}');
      app.publishEvent(CartEvent(app, 9));
      await _settle();
      expect(seen.last, '9/9');
      expect(seen, isNot(contains('9/0')));
    });

    test('SignalBuffer.run for code that is no bean', () async {
      final (seen, _) = _follow(() => '${cart.count}/${cart.other}');
      final gate = Completer<void>();
      final running = Checkout(cart).run(5, gate.future);
      await _settle();
      expect(cart.count, 0);
      gate.complete();
      await running;
      await told();
      expect(seen, ['0/0', '5/5']);
    });

    test('a scope that ends while it runs: its on-scope-end applies', () async {
      final bean = app.getBean<ScopedCart>();
      final (flushed, _) = _follow(() => bean.flushed);
      final gate = Completer<void>();
      final running = bean.fill(3, gate.future);
      await _settle();
      app.beanFactory.destroyScopedBean('scopedCart');
      expect(bean.value, 0, reason: 'discard');
      await told();
      expect(flushed, [0, 3], reason: 'flush');
      gate.complete();
      await running;
      expect(bean.value, 0);
    });
  });

  group('a flush schedule of the application', () {
    late Delayed delayed;
    late ScheduleLog log;

    setUp(() {
      delayed = app.getBean<Delayed>();
      log = app.getBean<ScheduleLog>();
    });

    test('a debounce: told 20 ms after the last write of a burst', () async {
      final (seen, _) = _follow(() => '${delayed.value}/${delayed.other}');
      for (var i = 1; i <= 4; i++) {
        delayed.value = i;
        delayed.other = i;
        await _settle(8);
      }
      expect(seen, ['0/0']);
      expect(log.schedules, 8);
      await _settle(40);
      expect(seen, ['0/0', '4/4']);
      expect(log.flushes, 1);
    });

    test('with a guard: a refused write reaches no queue', () async {
      expect(() => asAda(() => delayed.adminAssigns(5)), _denied);
      expect(log.schedules, 0);
      asRoot(() => delayed.adminAssigns(5));
      await _settle(40);
      expect(delayed.value, 5);
      expect(log.flushes, 1);
    });

    test('in a transaction: handed to the queue at the commit', () async {
      final template = TransactionTemplate(
        app.getBean<PlatformTransactionManager>(),
      );
      await template.execute((_) async => delayed.value = 4);
      expect(log.schedules, 1);
      await _settle(40);
      expect(log.flushes, 1);
    });

    test('closing the context cancels it: no flush after the close', () async {
      final own = await startApp();
      final bean = own.getBean<Delayed>();
      final ownLog = own.getBean<ScheduleLog>();
      bean
        ..value = 2
        ..other = 2;
      await own.closeAsync();
      expect(ownLog.schedules, 2);
      expect(ownLog.cancels, 1, reason: 'the last call\'s cancel');
      await _settle(40);
      expect(ownLog.flushes, 0);
    });

    test('a bean and a flush: property for one queue fail the start', () async {
      await expectLater(
        startApp(['--spring.flutter.signals.queues.delayed.flush=frame']),
        throwsA(
          predicate(
            (Object error) =>
                '$error'.contains("signal queue 'delayed'") &&
                '$error'.contains('Keep one'),
          ),
        ),
      );
    });
  });

  group('a reader runs again as the user it was made for', () {
    test('refused before the value was ever computed: run again when it '
        'is, as ada, and refused again', () async {
      final guarded = app.getBean<Guarded>();
      final reader = asAda(() => app.getBean<EarlyReader>());
      expect(reader.seen, ['refused']);
      expect(asRoot(() => guarded.pre), 10);
      await told();
      await asRoot(() async {
        guarded.raise(2);
        await told();
      });
      expect(reader.seen, everyElement('refused'));
      expect(reader.seen.length, greaterThan(1));
    });

    test(
      'an uncaught refusal of a re-run goes to the handler, no value',
      () async {
        final guarded = app.getBean<Guarded>();
        final errors = app.getBean<SignalErrors>();
        final readers = asAda(() => app.getBean<OwnedReaders>());
        expect(readers.strict, ['level=1']);
        await asRoot(() async {
          guarded.raise(2);
          await told();
        });
        expect(readers.strict, ['level=1']);
        expect(
          errors.errors.map((e) => (e.member, e.cause.runtimeType)),
          contains(('strictly', AuthorizationDeniedException)),
        );
        expect('${errors.errors}', isNot(contains('20')));
      },
    );

    test('allowed: the value; @PostFilter: only its own elements', () async {
      final guarded = app.getBean<Guarded>();
      final readers = asAda(() => app.getBean<OwnedReaders>());
      expect(readers.mine.last, ['1']);
      await asRoot(() async {
        expect(guarded.mine.map((n) => n.id), isEmpty);
        guarded.notes = const [
          Note('1', 'ada'),
          Note('5', 'ada'),
          Note('6', 'root'),
        ];
        await told();
      });
      expect(readers.mine.last, ['1', '5']);
    });

    test('a cached value of root is not served to a refused re-run', () async {
      final combo = app.getBean<Combo>();
      final readers = asAda(() => app.getBean<OwnedReaders>());
      expect(readers.cached, ['refused']);
      await asRoot(() async {
        expect(combo.guarded(), 3);
        combo.base = 2;
        await told();
      });
      expect(readers.cached, everyElement('refused'));
    });

    test(
      'a singleton @Effect runs as the program-wide user of the moment',
      () async {
        final vault = app.getBean<Vault>();
        trace.clear();
        await asRoot(() async {
          expect(vault.guarded, 10);
          await told();
        });
        expect(trace, contains(contains('VaultEffect as (nobody) refused')));
        expect(trace, isNot(contains(contains('VaultEffect as root'))));
        final holder = SecurityContextHolder.getContextHolderStrategy();
        holder.setContext(ctx('root', ['ADMIN']));
        addTearDown(holder.clearContext);
        await told();
        trace.clear();
        await asAda(() async {
          vault.secret = 3;
          await told();
        });
        expect(
          trace,
          contains(contains('VaultEffect as root read guarded=30')),
        );
      },
    );
  });

  test('two applications in one process keep their own settings', () async {
    final publishing = await startApp([
      '--spring.flutter.signals.buffer.on-error=publish',
      '--spring.flutter.signals.transaction.mode=direct',
    ]);
    final other = publishing.getBean<Cart>();
    await publishing.getBean<Shelf>().setUp();
    await expectLater(cart.fails(1), throwsStateError);
    await expectLater(other.fails(2), throwsStateError);
    await told();
    expect([cart.count, other.count], [0, 2]);
    final shelf = app.getBean<Shelf>();
    final otherShelf = publishing.getBean<Shelf>();
    await expectLater(shelf.fails(3), throwsStateError);
    await expectLater(otherShelf.fails(4), throwsStateError);
    expect([shelf.value, otherShelf.value], [0, 4]);
    await publishing.closeAsync();
    await expectLater(cart.fails(5), throwsStateError);
    await expectLater(shelf.fails(6), throwsStateError);
    await told();
    expect([cart.count, shelf.value], [0, 0]);
  });
}
