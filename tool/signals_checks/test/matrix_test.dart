// Followed state with real advice, a real store and two users, on the code
// the generator writes.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_checks/matrix.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart'
    show RouteScopes;
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'support.dart';

final _denied = throwsA(isA<AccessDeniedException>());

(List<T>, void Function()) _follow<T>(T Function() read) {
  final seen = <T>[];
  final stop = signals.effect(() => seen.add(read()));
  addTearDown(stop);
  return (seen, stop);
}

void main() {
  late ConfigurableApplicationContext app;
  setUp(() async => app = await startApp());
  tearDown(() => app.closeAsync());

  group('a transaction', () {
    late Shelf shelf;
    late ShelfWatcher watcher;

    setUp(() async {
      shelf = app.getBean<Shelf>();
      watcher = app.getBean<ShelfWatcher>();
      await shelf.setUp();
      watcher.seen.clear();
    });

    test('commit: published once, after the commit', () async {
      await shelf.commits(5);
      await told();
      expect(watcher.seen, ['5/5']);
      expect(await shelf.stored(), 5);
    });

    test('rollback: nothing is published, the field is as it was', () async {
      await expectLater(shelf.fails(5), throwsStateError);
      await told();
      expect(watcher.seen, isEmpty);
      expect([shelf.value, shelf.other], [0, 0]);
      expect(await shelf.stored(), 0);
    });

    test('read-your-writes in its zone, the old value outside', () async {
      final gate = Completer<void>();
      final running = shelf.readsOwn(3, gate.future);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(shelf.value, 0);
      expect(shelf.doubled, 0);
      gate.complete();
      expect(await running, [3, 6, 3]);
      await told();
      expect(shelf.value, 3);
      expect(shelf.doubled, 6);
    });

    test('a value computed in it is not kept for anyone else', () async {
      expect(shelf.doubled, 0);
      final gate = Completer<void>();
      final running = shelf.readsOwn(4, gate.future);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(shelf.doubled, 0);
      gate.complete();
      await running;
      expect(shelf.doubled, 8);
    });

    test('a nested block that fails goes back to its savepoint', () async {
      await shelf.outerWithNested(1, 2, fail: true);
      await told();
      expect([shelf.value, shelf.other], [1, 1]);
      expect(watcher.seen, ['1/1']);
    });

    test('a nested block that commits is dropped with the outer', () async {
      await expectLater(shelf.outerThenFails(1), throwsStateError);
      await told();
      expect([shelf.value, shelf.other], [0, 0]);
      expect(watcher.seen, isEmpty);
    });

    test('a savepoint by hand, gone back to twice', () async {
      final template = TransactionTemplate(
        app.getBean<PlatformTransactionManager>(),
      );
      await template.execute((status) async {
        shelf.value = 1;
        final savepoint = await status.createSavepoint();
        shelf.value = 2;
        expect(shelf.value, 2);
        await status.rollbackToSavepoint(savepoint);
        expect(shelf.value, 1);
        shelf.value = 3;
        await status.rollbackToSavepoint(savepoint);
        expect(shelf.value, 1);
      });
      await told();
      expect(shelf.value, 1);
    });

    test('requiresNew commits on its own', () async {
      await expectLater(shelf.outerWithRequiresNew(1), throwsStateError);
      await told();
      expect([shelf.value, shelf.other], [0, 2]);
    });

    test('read-only: what it assigned is published at its end', () async {
      await shelf.readOnlyWrites(9);
      await told();
      expect(shelf.value, 9);
    });

    test('a field with buffered: false takes no part in it', () async {
      await expectLater(shelf.unbufferedInTransaction(4), throwsStateError);
      expect(shelf.unbuffered, 4);
    });

    test('a collection is copied: a rollback leaves it as it was', () async {
      await expectLater(shelf.addsItem('x', fail: true), throwsStateError);
      await told();
      expect(shelf.items, isEmpty);
      expect(shelf.counts, isEmpty);
    });

    test('a collection changed in place is published by the commit', () async {
      final (seen, _) = _follow(() => shelf.items.length);
      await shelf.addsItem('x');
      await told();
      expect(shelf.items, ['x']);
      expect(shelf.counts, {'x': 1});
      expect(seen, [0, 1]);
    });

    test('a transaction that only reads a collection tells nobody', () async {
      final (seen, _) = _follow(() => shelf.items.length);
      expect(await shelf.onlyReadsItems(), 0);
      await told();
      expect(seen, [0]);
    });

    test('mode direct: written at once, kept by a rollback', () async {
      final direct = await startApp([
        '--spring.flutter.signals.transaction.mode=direct',
      ]);
      addTearDown(direct.closeAsync);
      final bean = direct.getBean<Shelf>();
      await bean.setUp();
      await expectLater(bean.fails(5), throwsStateError);
      expect(bean.value, 5);
    });

    test('an effect that fails after the commit does not undo it', () async {
      final failing = app.getBean<Failing>();
      final errors = app.getBean<SignalErrors>();
      final template = TransactionTemplate(
        app.getBean<PlatformTransactionManager>(),
      );
      await template.execute((_) async => failing.value = 13);
      await told();
      expect(failing.value, 13);
      expect(errors.errors.single.member, 'fails');
    });
  });

  group('method security, two users', () {
    late Guarded guarded;
    late GuardedReader reader;

    setUp(() {
      guarded = app.getBean<Guarded>();
      reader = app.getBean<GuardedReader>();
    });

    for (final (name, read) in <(String, int Function(Guarded))>[
      ('@PreAuthorize', (bean) => bean.pre),
      ('@Secured', (bean) => bean.secured),
    ]) {
      test('$name on @Computed: checked per read, computed once', () {
        final value = asRoot(() => read(guarded));
        final bodies = guarded.bodies;
        expect(asRoot(() => read(guarded)), value);
        expect(guarded.bodies, bodies);
        expect(() => asAda(() => read(guarded)), _denied);
        expect(() => asNobody(() => read(guarded)), throwsA(anything));
      });
    }

    test('@PostAuthorize on @Computed', () {
      expect(asAda(() => guarded.first).owner, 'ada');
      expect(() => asBob(() => guarded.first), _denied);
    });

    test('@PostFilter on @Computed: each user their own', () {
      expect(asAda(() => guarded.mine).map((n) => n.id), ['1']);
      expect(asBob(() => guarded.mine).map((n) => n.id), ['2']);
      expect(guarded.notes, hasLength(2));
    });

    test('@PreFilter: only what the caller may hand in', () {
      asAda(
        () => guarded.replace([const Note('8', 'ada'), const Note('9', 'bob')]),
      );
      expect(guarded.notes.map((n) => n.id), ['8']);
    });

    test('a guarded method that assigns', () {
      expect(() => asAda(() => guarded.raise(5)), _denied);
      expect(guarded.level, 1);
      asRoot(() => guarded.raise(5));
      expect(guarded.level, 5);
    });

    test('a call on this skips the check, as in Spring', () {
      expect(asAda(guarded.viaThis), 10);
    });

    for (final (name, read) in <(String, Object? Function(GuardedReader))>[
      ('@PreAuthorize', (bean) => bean.fromPre),
      ('@Secured', (bean) => bean.fromSecured),
    ]) {
      test('$name read by another bean is not served to another user', () {
        expect(asRoot(() => read(reader)), isNotNull);
        expect(() => asAda(() => read(reader)), _denied);
        expect(asRoot(() => read(reader)), isNotNull);
      });
    }

    test('a filtered list read by another bean is per user', () {
      expect(asAda(() => reader.fromMine), ['1']);
      expect(asBob(() => reader.fromMine), ['2']);
      expect(asAda(() => reader.fromMine), ['1']);
    });

    test('@PostAuthorize read by another bean is per user', () {
      expect(asAda(() => reader.fromFirst), '1');
      expect(() => asBob(() => reader.fromFirst), _denied);
    });

    test('a value made from the current user is per user', () {
      expect(asAda(() => reader.whoAsks), 'ada');
      expect(asBob(() => reader.whoAsks), 'bob');
      expect(asNobody(() => reader.whoAsks), 'nobody');
    });

    test('caller-bound: false shares it, as asked', () async {
      final shared = await startApp([
        '--spring.flutter.signals.caller-bound=false',
      ]);
      addTearDown(shared.closeAsync);
      final bean = shared.getBean<GuardedReader>();
      expect(asAda(() => bean.whoAsks), 'ada');
      expect(asBob(() => bean.whoAsks), 'ada');
    });

    test('a user switch on the program re-runs what depends on it', () {
      final holder = SecurityContextHolder.getContextHolderStrategy();
      addTearDown(holder.clearContext);
      holder.setContext(ctx('ada', ['USER']));
      final (seen, _) = _follow(() => reader.whoAsks);
      holder.setContext(ctx('bob', ['USER']));
      expect(seen, ['ada', 'bob']);
    });

    test('@OnWatched with a guard: refused goes to the handler', () async {
      final errors = app.getBean<SignalErrors>();
      final watch = app.getBean<GuardedWatch>();
      final (_, stop) = asAda(() => _follow(() => watch.door));
      await asAda(told);
      expect(watch.calls, isEmpty);
      expect(errors.errors.single.kind, SignalExecutionKind.watched);
      stop();
    });
  });

  group('cache with security and transactions', () {
    late Combo combo;

    setUp(() => combo = app.getBean<Combo>());

    test('a cached value is not served to a user the guard refuses', () {
      expect(asRoot(combo.guarded), 3);
      expect(combo.bodies, 1);
      expect(asRoot(combo.guarded), 3);
      expect(combo.bodies, 1);
      expect(() => asAda(combo.guarded), _denied);
    });

    test('a cached list is filtered for each user', () {
      expect(asAda(combo.filtered).map((n) => n.owner), ['ada']);
      expect(asBob(combo.filtered).map((n) => n.owner), ['bob']);
      expect(combo.bodies, 1);
    });

    test('security + cache + transaction on one method', () async {
      expect(await asAda(() => combo.load('ada')), 'ada:1');
      expect(await asAda(() => combo.load('ada')), 'ada:1');
      expect(await asBob(() => combo.load('bob')), 'bob:2');
      await told();
      expect(combo.base, 3);
      await expectLater(
        asNobody(() => combo.load('x')),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('@CachePut on a @Computed runs each call', () {
      expect(combo.put(), 5);
      combo.base = 2;
      expect(combo.put(), 10);
    });

    test('@CacheEvict and @Caching', () {
      expect(combo.cached(), 1);
      combo.evict(4);
      expect(combo.cached(), 4);
      combo.both(6);
      expect(combo.cached(), 6);
    });

    test('a reader of a cache hit hears of a later change', () async {
      expect(asRoot(combo.guarded), 3);
      final (seen, _) = asRoot(() => _follow(combo.guarded));
      asRoot(() => combo.base = 2);
      await asRoot(told);
      expect(seen.length, 2);
    });
  });

  group('@Effect and @OnWatched with advice', () {
    test(
      'each runs with its advice, as the user it was made for',
      () async {
        final source = app.getBean<RunSource>();
        final errors = app.getBean<SignalErrors>();
        final runs = asRoot(() => app.getBean<AdvisedRuns>());
        await asRoot(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        expect(
          runs.runs,
          containsAll(['secured', 'pre', 'aspect', 'tx true 0']),
        );
        expect(
          app.getBean<OuterAspect>().calls,
          contains('outer aspectEffect'),
        );
        runs.runs.clear();
        await asAda(() async {
          source.value = 1;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
        // Made for root: run again as root, whoever changed the value.
        expect(
          runs.runs,
          containsAll(['secured', 'pre', 'aspect', 'tx true 1']),
        );
        expect(errors.errors, isEmpty);
        runs.runs.clear();
        await asRoot(() async {
          source.value = 2;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
        expect(runs.runs, containsAll(['secured', 'pre']));
        expect(errors.errors, isEmpty);
      },
    );

    test(
      '@OnWatched in a transaction, @OnUnwatched through an aspect',
      () async {
        final runs = asRoot(() => app.getBean<AdvisedRuns>());
        final (_, stop) = _follow(() => runs.watchedByAdvice);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(runs.runs, contains('watch tx true'));
        stop();
        await told();
        expect(runs.runs, contains('unwatch aspect'));
      },
    );
  });

  group('guard, cache and transaction on one @Computed', () {
    late FullStack stack;

    setUp(() => stack = app.getBean<FullStack>());

    test('the guard comes first, the cache keeps one body', () async {
      expect(await asRoot(stack.value), 10);
      expect(await asRoot(stack.value), 10);
      expect(stack.bodies, 1);
      await expectLater(asAda(stack.value), _denied);
      await expectLater(asNobody(stack.value), throwsA(anything));
      expect(stack.bodies, 1);
    });

    test('a user switch: a kept value reaches nobody refused', () async {
      expect(await asRoot(stack.value), 10);
      await expectLater(asBob(stack.value), _denied);
      expect(await asRoot(stack.value), 10);
    });

    test('evicted and changed, it loads the new value', () async {
      expect(await asRoot(stack.value), 10);
      stack
        ..base = 2
        ..evict();
      await told();
      expect(await asRoot(stack.value), 20);
      expect(stack.bodies, 2);
    });

    test('@Caching on a @Computed', () {
      expect(stack.cachingOnComputed(), 1);
      stack.base = 2;
      expect(stack.cachingOnComputed(), 1, reason: 'a hit, as in Spring');
    });

    test('a @Computed whose transaction fails: the error is the caller\'s, '
        'the next load works', () async {
      expect(await stack.failsInTransaction(), 1);
      stack.base = -1;
      await told();
      await expectLater(stack.failsInTransaction(), throwsStateError);
      stack.base = 3;
      await told();
      expect(await stack.failsInTransaction(), 3);
    });
  });

  group('events, schedules, aspects', () {
    test('@EventListener assigns', () async {
      final busy = app.getBean<Busy>();
      app.publishEvent(Tick(app, 4));
      await told();
      expect(busy.heard, 4);
    });

    test('@Async listener assigns', () async {
      final busy = app.getBean<Busy>();
      app.publishEvent(LaterTick(app, 6));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(busy.later, 6);
    });

    test('@Scheduled assigns, and a reader follows', () async {
      final busy = app.getBean<Busy>();
      final (seen, _) = _follow(() => busy.ticks);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen.length, greaterThan(1));
    });

    test('aspects run by @Order, a composed annotation too', () {
      final aspected = app.getBean<Aspected>();
      final outer = app.getBean<OuterAspect>();
      expect(aspected.observed, 2);
      expect(outer.calls, ['outer observed', 'inner observed']);
      outer.calls.clear();
      aspected.composed();
      expect(outer.calls, ['outer composed']);
    });

    test('advice per call, the body per change', () {
      final aspected = app.getBean<Aspected>();
      aspected
        ..observed
        ..observed;
      expect(aspected.bodies, 1);
    });

    test('this skips the advice but is followed', () async {
      final aspected = app.getBean<Aspected>();
      final outer = app.getBean<OuterAspect>();
      final (seen, _) = _follow(aspected.viaThis);
      expect(outer.calls, isEmpty);
      aspected.value = 5;
      await told();
      expect(seen, [2, 6]);
      expect(outer.calls, isEmpty);
    });

    test('a call through a @Lazy self reference is advised', () {
      final bean = app.getBean<SelfCalling>();
      expect(asAda(bean.throughThis), 1);
      expect(() => asAda(bean.throughSelf), _denied);
      expect(asRoot(bean.throughSelf), 1);
    });

    test('a bean with only signals has no proxy', () {
      expect(AopUtils.isAopProxy(app.getBean<Options>()), isFalse);
      expect(AopUtils.isAopProxy(app.getBean<Shelf>()), isTrue);
      expect(AopUtils.getTarget(app.getBean<Shelf>()), isA<SignalBeanHolder>());
    });
  });

  group('flush and options', () {
    late Options options;
    late SignalQueues queues;

    setUp(() {
      options = app.getBean<Options>();
      queues = app.getBean<SignalRuntime>().queues;
    });

    test('microtask: one run is one change, a @Computed sees it', () async {
      final shelf = app.getBean<Shelf>();
      final watcher = app.getBean<ShelfWatcher>()..seen.clear();
      shelf.assignTwo(4);
      expect(watcher.seen, isEmpty);
      expect(shelf.doubled, 8);
      await told();
      expect(watcher.seen, ['4/4']);
    });

    test('immediate: told at the assignment', () {
      final (seen, _) = _follow(() => options.instant);
      options.instant = 1;
      expect(seen, [0, 1]);
    });

    test('interval: told when it comes', () async {
      final (seen, _) = _follow(() => options.ticked);
      options.ticked = 1;
      expect(seen, [0]);
      expect(options.ticked, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen, [0, 1]);
    });

    testWidgets('frame: told at the next frame', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final (seen, _) = _follow(() => options.framed);
      options.framed = 1;
      await tester.idle();
      expect(seen, [0]);
      await tester.pump();
      expect(seen, [0, 1]);
    });

    test('a held write: the field has it, readers are told by flush', () {
      final (seen, _) = _follow(() => options.held);
      options.held = 3;
      expect(options.held, 3);
      expect(seen, [0]);
      queues.of('manual').flush();
      expect(seen, [0, 3]);
      expect(options.heldTwice, 6);
    });

    test('on-overflow flush', () {
      final (seen, _) = _follow(() => options.smallA);
      options.smallA = 1;
      options.smallB = 1;
      expect(seen, [0, 1]);
      queues.of('small').flush();
    });

    test('on-overflow drop-oldest', () {
      options.oldestA = 1;
      options.oldestB = 1;
      expect(options.oldestA, 0);
      expect(options.oldestB, 1);
      queues.of('oldest').flush();
    });

    test('on-overflow drop-newest', () {
      options.newestA = 1;
      options.newestB = 1;
      expect(options.newestA, 1);
      expect(options.newestB, 0);
      queues.of('newest').flush();
    });

    test('equal by ==, another object: the new one, no tick', () async {
      final (seen, _) = _follow(() => options.tag.label);
      options.tag = const Tag(1, 'second');
      await told();
      expect(options.tag.label, 'second');
      expect(seen, ['first']);
    });

    test('equals: what it calls equal is kept, without a tick', () async {
      final (seen, _) = _follow(() => options.parity);
      options.parity = 2;
      await told();
      expect(options.parity, 2);
      expect(seen, [0]);
      options.parity = 3;
      await told();
      expect(seen, [0, 3]);
    });

    test('eager: made with the bean; the rest on first use', () {
      final state = (options as SignalBeanHolder).signalBean;
      expect(state.members.keys, contains('ready'));
      expect(state.members.keys, isNot(contains('tag')));
    });

    test('global eager makes them all', () async {
      final eager = await startApp(['--spring.flutter.signals.eager=true']);
      addTearDown(eager.closeAsync);
      final state = (eager.getBean<Options>() as SignalBeanHolder).signalBean;
      expect(state.members.keys, contains('tag'));
    });

    test('followCollection: false follows assignments only', () async {
      final (plain, _) = _follow(() => options.plainList.length);
      final (followed, _) = _follow(() => options.followedList.length);
      options.plainList.add(1);
      options.followedList.add(1);
      await told();
      expect(plain, [0]);
      expect(followed, [0, 1]);
    });

    test('hidden: no value in the debug tab', () {
      options.secretNote;
      final state = (options as SignalBeanHolder).signalBean;
      final row = SignalsRow.member(state.members['secretNote']!, null);
      expect(row.tone, SignalsValueTone.locked);
    });

    test('an unknown executor fails the start, naming the known', () {
      expect(
        () => queues.of('nope'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('manual'),
          ),
        ),
      );
    });
  });

  group('watching', () {
    late Watched watched;

    setUp(() => watched = app.getBean<Watched>());

    test('a group: on for the first, off after the last', () async {
      final (_, stopA) = _follow(() => watched.a);
      final (_, stopB) = _follow(() => watched.b);
      await told();
      expect(watched.calls, ['group on']);
      stopA();
      await told();
      expect(watched.calls, ['group on']);
      stopB();
      await told();
      expect(watched.calls, ['group on', 'group off']);
    });

    test('each: for each of them', () async {
      final (_, stopC) = _follow(() => watched.c);
      final (_, stopSum) = _follow(() => watched.sum);
      await told();
      expect(watched.calls.where((c) => c == 'each on'), hasLength(2));
      stopC();
      stopSum();
    });

    test('delay: a new watcher within it cancels the call', () async {
      final (_, stop) = _follow(() => watched.slow);
      await told();
      stop();
      await told();
      final (_, again) = _follow(() => watched.slow);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(watched.calls, isNot(contains('slow off')));
      again();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(watched.calls, contains('slow off'));
    });

    test('an error goes to the handler, with its kind', () async {
      final errors = app.getBean<SignalErrors>();
      final (_, stop) = _follow(() => watched.bad);
      await told();
      stop();
      await told();
      expect(errors.errors.map((e) => e.kind), [
        SignalExecutionKind.watched,
        SignalExecutionKind.unwatched,
      ]);
    });

    testWidgets('a Watch that flaps within a frame is not unwatched', (
      tester,
    ) async {
      await tester.runAsync(() async {});
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Watch((_) => Text('${watched.a}')),
        ),
      );
      await tester.pump();
      watched.calls.clear();
      watched.a = 1;
      await tester.pump();
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(watched.calls, isNot(contains('group off')));
    });
  });

  group('scopes', () {
    late TestScopes scopes;
    late List<String> warnings;

    setUp(() {
      scopes = app.getBean<TestScopes>();
      warnings = [];
      SpringLog.setLevel('spring.flutter.signals', SpringLogLevel.warning);
      addTearDown(() => SpringLog.setLevel('spring.flutter.signals', null));
      addTearDown(
        SpringLog.listen((record) {
          if (record.level == SpringLogLevel.warning) {
            warnings.add(record.message);
          }
        }),
      );
    });

    void endScope(SimpleMapScope scope, String name) {
      app.beanFactory.destroyScopedBean(name);
    }

    test('discard: dropped, with a warning naming bean and field', () {
      final bean = app.getBean<DiscardState>();
      final (seen, _) = _follow(() => bean.value);
      bean.value = 1;
      endScope(scopes.custom, 'discardState');
      expect(seen, [0]);
      expect(bean.value, 0);
      expect(
        warnings,
        contains(allOf(contains('DiscardState'), contains('value'))),
      );
    });

    test('flush: told as the scope ends', () {
      final bean = app.getBean<FlushState>();
      final (seen, _) = _follow(() => bean.value);
      bean.value = 1;
      endScope(scopes.custom, 'flushState');
      expect(seen, [0, 1]);
    });

    test('defer: told by its executor after the scope ended', () {
      final bean = app.getBean<DeferState>();
      final (seen, _) = _follow(() => bean.value);
      bean.value = 1;
      endScope(scopes.custom, 'deferState');
      expect(seen, [0]);
      app.getBean<SignalRuntime>().queues.of('manual').flush();
      expect(seen, [0, 1]);
    });

    test('defer: dropped after its timeout, with a warning', () async {
      final short = await startApp([
        '--spring.flutter.signals.defer-timeout=5ms',
      ]);
      addTearDown(short.closeAsync);
      SpringLog.setLevel('spring.flutter.signals', SpringLogLevel.warning);
      final bean = short.getBean<DeferState>();
      bean.value = 1;
      short.beanFactory.destroyScopedBean('deferState');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bean.value, 0);
      expect(warnings, contains(contains('defer-timeout')));
    });

    test('the real route scope discards, the real branch scope flushes', () {
      final scopes = app.getBean<RouteScopes>();
      final route = runZoned(
        app.getBean<RouteScoped>,
        zoneValues: RouteScopes.zoneValues(1),
      );
      final branch = runZoned(
        app.getBean<BranchScoped>,
        zoneValues: RouteScopes.zoneValues(1, shell: 7, branch: 0),
      );
      final (seen, _) = _follow(() => branch.value);
      route.value = 1;
      branch.value = 1;
      scopes
        ..destroyScreen(1)
        ..destroyShell(7);
      expect(route.value, 0);
      expect(seen, [0, 1]);
      expect(
        warnings,
        contains(allOf(contains('RouteScoped'), contains('value'))),
      );
    });

    test('each prototype has its own state', () {
      final first = app.getBean<ProtoState>();
      final second = app.getBean<ProtoState>();
      first.value = 1;
      expect(second.value, 0);
      app.getBean<SignalRuntime>().queues.of('manual').flush();
    });
  });

  group('errors', () {
    late Failing failing;
    late SignalErrors errors;

    setUp(() {
      failing = app.getBean<Failing>();
      errors = app.getBean<SignalErrors>();
    });

    test('a @Computed read: the caller gets its own error', () {
      failing.value = -1;
      expect(() => failing.computedFails, throwsArgumentError);
      expect(errors.errors, isEmpty);
    });

    test('the first run of an effect: the bean is not made', () {
      expect(() => app.getBean<FailsFirst>(), throwsA(anything));
      expect(errors.errors, isEmpty);
    });

    test('a re-run: to the handler, the other effect goes on', () async {
      failing.survived.clear();
      failing.value = 13;
      await told();
      expect(errors.errors.single.kind, SignalExecutionKind.effect);
      expect(errors.errors.single.bean, 'Failing');
      expect(errors.errors.single.member, 'fails');
      expect(errors.errors.single.cause, isStateError);
      expect(failing.survived, [13]);
    });

    test('the message never has a value', () async {
      failing.value = 13;
      await told();
      expect('${errors.errors.single}', isNot(contains('13')));
    });

    test('a handler that throws: logged, the rest goes on', () async {
      errors.throwing = true;
      failing.survived.clear();
      failing.value = 13;
      await told();
      expect(failing.survived, [13]);
      failing.value = 1;
      await told();
      expect(failing.survived, [13, 1]);
    });

    test('without a handler: FlutterError.reportError', () {
      final reported = <Object>[];
      final before = FlutterError.onError;
      FlutterError.onError = (details) => reported.add(details.exception);
      addTearDown(() => FlutterError.onError = before);
      SignalErrorReporter().report(
        SignalExecutionKind.effect,
        'Bean',
        'run',
        StateError('x'),
        StackTrace.current,
      );
      expect(reported.single, isA<SignalExecutionException>());
    });
  });
}
