// The behaviour the audit reported as X1-X12, each as an assertion. X7 is
// Spring's documented behaviour of a cache and is asserted as such; the
// others were bugs.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_checks/matrix.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'support.dart';

final _denied = throwsA(isA<AccessDeniedException>());

void main() {
  late ConfigurableApplicationContext app;
  setUp(() async => app = await startApp());
  tearDown(() => app.closeAsync());

  test('X1 a plain async method: its synchronous part is one change', () async {
    final ledger = app.getBean<Ledger>();
    final seen = <String>[];
    final stop = signals.effect(
      () => seen.add('${ledger.balance}/${ledger.other}'),
    );
    addTearDown(stop);
    await ledger.plainAsync(5);
    await told();
    expect(seen, ['0/0', '5/5', '5/6']);
  });

  testWidgets('X2 a Watch never shows a value of a transaction that rolls '
      'back', (tester) async {
    final ledger = app.getBean<Ledger>();
    await tester.runAsync(ledger.setUp);
    final built = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Watch((_) {
          built.add(ledger.balance);
          return Text('${ledger.balance}');
        }),
      ),
    );
    final gate = Completer<void>();
    late Future<void> running;
    await tester.runAsync(() async {
      running = ledger.gated(77, gate.future);
      unawaited(running.catchError((_) {}));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(find.text('77'), findsNothing);
    await tester.runAsync(() async {
      gate.complete();
      await running.catchError((_) {});
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    expect(ledger.balance, 0);
    expect(built, everyElement(0));
  });

  test(
    'X3 an @Effect of another bean: checked as whoever made it run',
    () async {
      final vault = app.getBean<Vault>();
      asRoot(() => app.getBean<LateVaultEffect>());
      trace.clear();
      await asRoot(() async {
        vault.secret = 2;
        await told();
      });
      expect(
        trace,
        contains(contains('LateVaultEffect as root read guarded=20')),
      );
      trace.clear();
      await asAda(() async {
        vault.secret = 3;
        await told();
      });
      expect(
        trace,
        contains(contains('LateVaultEffect as root read guarded=30')),
      );
      expect(trace, isNot(contains(contains('LateVaultEffect as ada'))));
      trace.clear();
      await asRoot(() async {
        vault.secret = 4;
        await told();
      });
      expect(
        trace,
        contains(contains('LateVaultEffect as root read guarded=40')),
      );
    },
  );

  testWidgets('X4 a Watch of a guarded value fails closed when the user '
      'changes', (tester) async {
    final vault = app.getBean<Vault>();
    final holder = SecurityContextHolder.getContextHolderStrategy();
    holder.setContext(ctx('root', ['ADMIN']));
    addTearDown(holder.clearContext);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Watch((_) {
          try {
            return Text('guarded=${vault.guarded}');
          } on AccessDeniedException {
            return const Text('refused');
          }
        }),
      ),
    );
    expect(find.text('guarded=10'), findsOneWidget);
    holder.setContext(ctx('ada', ['USER']));
    await tester.pump();
    await tester.pump();
    expect(find.text('guarded=10'), findsNothing);
    expect(find.text('refused'), findsOneWidget);
  });

  testWidgets('X5 an AsyncView over secured futures', (tester) async {
    final vault = app.getBean<Vault>();
    final holder = SecurityContextHolder.getContextHolderStrategy();
    addTearDown(holder.clearContext);
    Future<String> shown(
      Future<Object?> Function() value,
      String user,
      List<String> roles,
    ) async {
      holder.setContext(ctx(user, roles));
      await tester.pumpWidget(
        Directionality(
          key: UniqueKey(),
          textDirection: TextDirection.ltr,
          child: AsyncView<Object?>(
            value,
            data: (_, data) => Text('data:$data'),
            error: (_, error, _) => Text('error:${error.runtimeType}'),
            loading: (_) => const Text('loading'),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      await tester.pump();
      return (tester.widget<Text>(find.byType(Text)).data)!;
    }

    expect(await shown(() => vault.guardedLater, 'root', ['ADMIN']), 'data:10');
    expect(
      await shown(() => vault.guardedLater, 'ada', ['USER']),
      startsWith('error:'),
    );
    expect(
      await shown(() => vault.visibleLater, 'ada', ['USER']),
      'data:[1:ada, 3:ada]',
    );
    expect(
      await shown(() => vault.firstDocLater, 'bob', ['USER']),
      startsWith('error:'),
    );
  });

  test('X6 a guarded @Effect made for root runs as root when ada changes '
      'what it read', () async {
    final errors = app.getBean<SignalErrors>();
    final state = app.getBean<EffectState>();
    asRoot(() => app.getBean<GuardedEffect>());
    await asAda(() async {
      state.value = 2;
      await told();
    });
    expect(state.value, 2);
    expect(errors.errors, isEmpty);
    expect(trace, contains('GuardedEffect body as root value=2'));
  });

  test('X7 (Spring) a cache hit answers until it is evicted', () {
    final priced = app.getBean<Priced>();
    expect(priced.cachedSync(), 100);
    priced.n = 2;
    expect(priced.cachedSync(), 100, reason: 'a hit, as in Spring');
    priced.evict();
    expect(priced.cachedSync(), 200);
    expect(priced.bodies, 2);
  });

  test('X8 a @Computed future loads again for a change', () async {
    final priced = app.getBean<Priced>();
    expect(await priced.plainLoaded(), 2);
    priced.n = 2;
    expect(await priced.plainLoaded(), 4);
  });

  test('X9 a @Transactional @Computed follows and refreshes', () async {
    final priced = app.getBean<Priced>();
    expect(await priced.loaded(), 2);
    priced.n = 5;
    expect(await priced.loaded(), 10);
    final future = priced.loaded();
    await future;
    await future.refresh();
    expect(await priced.loaded(), 10);
    expect(future.state.value, 10);
  });

  test('X10 a guarded method is checked through a bean with no proxy', () {
    final plain = app.getBean<PlainSecured>();
    final helper = app.getBean<Unadvised>();
    final selfish = app.getBean<Selfish>();
    expect(() => asAda(plain.adminOnly), _denied);
    expect(() => asAda(plain.openViaAdvised), _denied);
    expect(() => asAda(plain.openViaUnadvised), _denied);
    expect(() => asAda(helper.callPlain), _denied);
    expect(() => asAda(() => selfish.viaUnadvised(helper)), _denied);
  });

  test('X11 an @Effect run by an assignment runs as the user it was made '
      'for', () async {
    final selfish = app.getBean<Selfish>();
    asRoot(() => app.getBean<SelfishEffect>());
    trace.clear();
    await asAda(() async {
      selfish.assignNow(1);
      await told();
    });
    expect(trace, contains(contains('SelfishEffect as root v=1 read')));
    trace.clear();
    await asAda(() => selfish.assignAfterAwait(2));
    await asAda(told);
    expect(trace, contains(contains('SelfishEffect as root v=2 read')));
  });

  test('X12 a plain signals effect (not the starter\'s) runs in the zone of '
      'the commit, as the one who committed', () async {
    final selfish = app.getBean<Selfish>();
    final seen = <String>[];
    final stop = signals.effect(() {
      final value = selfish.v;
      if (value == 0) {
        return;
      }
      try {
        seen.add('read ${selfish.adminValue}');
      } on AccessDeniedException {
        seen.add('refused');
      }
    });
    addTearDown(stop);
    await asAda(() => selfish.assignInTx(4));
    await told();
    expect(seen, ['refused']);
  });
}
