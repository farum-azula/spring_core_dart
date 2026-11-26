// Each test states the expected behaviour (README or Spring). A failing
// test is a reproduced bug.
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'support.dart';

final _denied = throwsA(isA<AccessDeniedException>());

void main() {
  late ConfigurableApplicationContext app;
  setUp(() async => app = await startApp());

  test('R1 a @Computed of another bean does not hand a guarded value to a '
      'user the guard refuses', () {
    final reader = app.getBean<VaultReader>();
    expect(asRoot(() => reader.fromGuarded), 10);
    expect(() => asAda(() => reader.fromGuarded), _denied);
  });

  test('R2 a @Computed of another bean does not hand ada\'s filtered list '
      'to bob', () {
    final reader = app.getBean<VaultReader>();
    asAda(() => reader.fromVisible);
    expect(
      asBob(() => reader.fromVisible).map((d) => d.owner),
      everyElement('bob'),
    );
  });

  test('R3 a guarded method called back through a bean with no proxy is '
      'checked', () {
    final selfish = app.getBean<Selfish>();
    final helper = app.getBean<Unadvised>();
    expect(() => asAda(() => selfish.viaUnadvised(helper)), _denied);
  });

  test('R4 a reader run by an assignment does not skip the guard', () async {
    final selfish = app.getBean<Selfish>();
    final seen = <int>[];
    final stop = signals.effect(() {
      if (selfish.v == 0) {
        return;
      }
      try {
        seen.add(selfish.adminValue);
      } on AccessDeniedException {
        // refused, as it must be
      }
    });
    addTearDown(stop);
    await asAda(() => selfish.assignAfterAwait(2));
    expect(seen, isEmpty);
  });

  test('R5 @PostFilter on a kept Map: each user gets their own entries', () {
    final vault = app.getBean<Vault>();
    expect(asAda(() => vault.visibleMap).keys, ['1', '3']);
    expect(asBob(() => vault.visibleMap).keys, ['2']);
  });

  test('R6 a filtered read does not delete entries of a @Signal Map', () {
    final vault = app.getBean<Vault>();
    asAda(vault.ownersOf);
    expect(vault.owners.length, 3);
  });

  test('R7 a @Transactional method is one change (README)', () async {
    final ledger = app.getBean<Ledger>();
    await ledger.setUp();
    final seen = <String>[];
    final stop = signals.effect(
      () => seen.add('${ledger.balance}/${ledger.other}'),
    );
    addTearDown(stop);
    await ledger.syncLooking(10);
    expect(seen, ['0/0', '10/10']);
  });

  test(
    'R8 a @Transactional @Computed loads again when its state changes',
    () async {
      final priced = app.getBean<Priced>();
      expect(await priced.loaded(), 2);
      priced.n = 2;
      expect(await priced.loaded(), 4);
    },
  );

  test('R9 a @Cacheable @Computed still follows after a cache hit', () {
    final priced = app.getBean<Priced>();
    priced.cachedSync();
    priced.evict();
    priced.n = 2;
    expect(priced.cachedSync(), 200);
    priced.n = 3; // a hit: the kept 200 is right
    priced.cachedSync();
    priced.evict();
    priced.n = 4;
    expect(priced.cachedSync(), 400);
  });

  test('R10 .state works on a @Transactional @Computed future', () async {
    final future = app.getBean<Priced>().loaded();
    await future;
    expect(future.state.value, 2);
  });

  test('R11 .state works on a @PostFilter @Computed future', () async {
    final vault = app.getBean<Vault>();
    await asAda(() async {
      final future = vault.visibleLater;
      await future;
      expect(future.state.value, hasLength(2));
    });
  });

  test('R12 closing the context reports no error', () async {
    app.getBean<Vault>().secret;
    app.close();
    await Future<void>.delayed(Duration.zero);
  });
}
