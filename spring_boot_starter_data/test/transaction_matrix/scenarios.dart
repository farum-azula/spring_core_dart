// Any object may be thrown in Dart; the scenarios throw their own.
// ignore_for_file: only_throw_errors
// The scenarios of the transaction matrix. Each one resets the tables,
// drives its transactions and returns a normalized outcome (see env.dart);
// tool/data_reference has the same scenarios, with the same ids and keys,
// written for Spring: the differential test compares outcome by outcome.
//
// Groups: `propagation/<outer>/<inner>/<variant>` (every outer, and none,
// against every inner), `propagation-lock/<inner>`, `rules/*`, `template/*`,
// `readonly/*`, `isolation/<anomaly>/<level>`, `lock/*`, `version/*`,
// `timeout/*`.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../repository/jdbc/support.dart';
import 'env.dart';
import 'services.dart';

/// A scenario: its id and what it does.
final class Scenario {
  const Scenario(this.id, this.run);

  final String id;
  final Future<Outcome> Function(Env env) run;
}

/// The isolation levels by the names the outcomes use.
const levels = <String, Isolation>{
  'default': Isolation.defaultLevel,
  'readUncommitted': Isolation.readUncommitted,
  'readCommitted': Isolation.readCommitted,
  'repeatableRead': Isolation.repeatableRead,
  'serializable': Isolation.serializable,
};

/// Every scenario, in the order they run.
List<Scenario> allScenarios() => [
  ..._propagation(),
  ..._propagationLocks(),
  ..._rules(),
  ..._templates(),
  ..._readOnly(),
  ..._isolation(),
  ..._locks(),
  ..._versions(),
  ..._timeouts(),
];

/// The outcome of a scenario, as the JSON the reference prints.
Future<Outcome> runScenario(Env env, Scenario scenario) async {
  await env.reset();
  return await scenario.run(env);
}

// ------------------------------------------------------------ propagation

const _outers = <String, Propagation?>{
  'none': null,
  'required': Propagation.required,
  'supports': Propagation.supports,
  'mandatory': Propagation.mandatory,
  'requiresNew': Propagation.requiresNew,
  'notSupported': Propagation.notSupported,
  'never': Propagation.never,
  'nested': Propagation.nested,
};

List<Scenario> _propagation() => [
  for (final MapEntry(key: outerName, value: outer) in _outers.entries)
    for (final inner in propagations.keys)
      for (final variant in Variant.values)
        Scenario('propagation/$outerName/${inner.name}/${variant.name}', (
          env,
        ) async {
          final proxy = Proxy(env.manager);
          final service = Outer(proxy, Inner(proxy));
          final c = Ctx(env, variant, inner);
          try {
            await service.call(outer, c);
            c.out['outer'] = 'ok';
          } on Object catch (error) {
            c.out['outer'] = kindOf(error);
          }
          c.out['rows'] = await env.logRows();
          return c.out;
        }),
];

// What an inner method waits for when the outer one holds the row: each
// statement stops after a second.
List<Scenario> _propagationLocks() => [
  for (final inner in propagations.keys)
    Scenario('propagation-lock/${inner.name}', (env) async {
      final proxy = Proxy(env.manager);
      final timed = env.jdbcWithTimeout(const Duration(seconds: 1));
      final out = <String, Object?>{};
      try {
        await proxy(
          'Outer',
          'required',
          propagations[Propagation.required]!,
          () async {
            await env.jdbc.update(
              'update wallets set balance = balance + 1 where id = 1',
            );
            try {
              await proxy('Inner', inner.name, propagations[inner]!, () async {
                await timed.update(
                  'update wallets set balance = balance + 1 where id = 1',
                );
              });
              out['inner'] = 'ok';
            } on Object catch (error) {
              out['inner'] = kindOf(error);
            }
          },
        );
        out['outer'] = 'ok';
      } on Object catch (error) {
        out['outer'] = kindOf(error);
      }
      out['balance'] = await env.scalar<int>(
        'select balance from wallets where id = 1',
      );
      return out;
    }),
];

// ------------------------------------------------------------------ rules

Scenario _rule(
  String id,
  Transactional annotation,
  Object Function() throwing,
) => Scenario('rules/$id', (env) async {
  final proxy = Proxy(env.manager);
  final out = <String, Object?>{};
  try {
    await proxy<void>('Rules', 'method', annotation, () async {
      await env.jdbc.update("insert into log (who) values ('o1')");
      if (out.isEmpty) {
        throw throwing();
      }
    });
    out['outer'] = 'ok';
  } on Object catch (error) {
    out['outer'] = kindOf(error);
  }
  out['rows'] = await env.logRows();
  return out;
});

List<Scenario> _rules() => [
  _rule('default-rollback', const Transactional(), Boom.new),
  _rule(
    'noRollbackFor-commits',
    const Transactional(noRollbackFor: [Soft]),
    Soft.new,
  ),
  _rule(
    'noRollbackFor-covers-subclass',
    const Transactional(noRollbackFor: [Soft]),
    Hard.new,
  ),
  _rule(
    'rollbackFor-beats-noRollbackFor-of-supertype',
    const Transactional(noRollbackFor: [Soft], rollbackFor: [Hard]),
    Hard.new,
  ),
  _rule(
    'noRollbackFor-closer-than-rollbackFor',
    const Transactional(rollbackFor: [Soft], noRollbackFor: [Hard]),
    Hard.new,
  ),
  _rule(
    'unlisted-rolls-back',
    const Transactional(noRollbackFor: [Soft]),
    Boom.new,
  ),
  _rule('checked-exception', const Transactional(), Checked.new),
  _rule(
    'rollbackFor-checked',
    const Transactional(rollbackFor: [Checked]),
    Checked.new,
  ),
  _rule('error-rolls-back', const Transactional(), Fatal.new),
  Scenario('rules/joined-noRollbackFor', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    try {
      await proxy('Outer', 'required', const Transactional(), () async {
        await env.jdbc.update("insert into log (who) values ('o1')");
        try {
          await proxy(
            'Inner',
            'required',
            const Transactional(noRollbackFor: [Soft]),
            () async {
              await env.jdbc.update("insert into log (who) values ('i')");
              throw Soft();
            },
          );
        } on Object catch (error) {
          out['inner'] = kindOf(error);
        }
        await env.jdbc.update("insert into log (who) values ('o2')");
      });
      out['outer'] = 'ok';
    } on Object catch (error) {
      out['outer'] = kindOf(error);
    }
    out['rows'] = await env.logRows();
    return out;
  }),
];

// -------------------------------------------------------------- templates

List<Scenario> _templates() => [
  Scenario('template/commit', (env) async {
    final out = <String, Object?>{};
    out['result'] = await TransactionTemplate(env.manager).execute((_) async {
      await env.jdbc.update("insert into log (who) values ('o1')");
      return 'value';
    });
    out['rows'] = await env.logRows();
    return out;
  }),
  Scenario('template/exception', (env) async {
    final out = <String, Object?>{};
    out['outer'] = await attempt(
      () => TransactionTemplate(env.manager).execute((_) async {
        await env.jdbc.update("insert into log (who) values ('o1')");
        throw Boom();
      }),
    );
    out['rows'] = await env.logRows();
    return out;
  }),
  Scenario('template/set-rollback-only', (env) async {
    final out = <String, Object?>{};
    out['outer'] = await attempt(
      () => TransactionTemplate(env.manager).execute((status) async {
        await env.jdbc.update("insert into log (who) values ('o1')");
        status.setRollbackOnly();
        return 'value';
      }),
    );
    out['rows'] = await env.logRows();
    return out;
  }),
  Scenario('template/set-rollback-only-joined', (env) async {
    final out = <String, Object?>{};
    out['outer'] = await attempt(
      () => TransactionTemplate(env.manager).execute((_) async {
        await env.jdbc.update("insert into log (who) values ('o1')");
        out['inner'] = await attempt(
          () => TransactionTemplate(env.manager).execute((status) async {
            await env.jdbc.update("insert into log (who) values ('i')");
            status.setRollbackOnly();
            return 'value';
          }),
        );
      }),
    );
    out['rows'] = await env.logRows();
    return out;
  }),
];

// -------------------------------------------------------------- read only

Scenario _readOnlyOp(String id, String sql, {bool query = false}) =>
    Scenario('readonly/$id', (env) async {
      final proxy = Proxy(env.manager);
      final out = <String, Object?>{};
      out['outer'] = await completion(
        () => proxy(
          'Service',
          'readOnly',
          const Transactional(readOnly: true),
          () async {
            out['op'] = await attempt(
              () => query ? env.scalar<int>(sql) : env.jdbc.update(sql),
            );
          },
        ),
      );
      out['rows'] = await env.logRows();
      return out;
    });

List<Scenario> _readOnly() => [
  _readOnlyOp('read-ok', 'select count(*) from wallets', query: true),
  _readOnlyOp('insert-refused', "insert into log (who) values ('o1')"),
  _readOnlyOp('update-refused', 'update wallets set balance = 0'),
  _readOnlyOp('delete-refused', 'delete from wallets'),
  _readOnlyOp(
    'select-for-update-refused',
    'select count(*) from (select id from wallets for update) w',
    query: true,
  ),
  Scenario('readonly/joined-read-write-keeps-write', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy('Outer', 'required', const Transactional(), () async {
        out['inner'] = await attempt(
          () => proxy(
            'Inner',
            'required',
            const Transactional(readOnly: true),
            () => env.jdbc.update("insert into log (who) values ('i')"),
          ),
        );
      }),
    );
    out['rows'] = await env.logRows();
    return out;
  }),
  Scenario('readonly/requires-new-read-only-in-read-write', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy('Outer', 'required', const Transactional(), () async {
        out['inner'] = await attempt(
          () => proxy(
            'Inner',
            'requiresNew',
            const Transactional(
              propagation: Propagation.requiresNew,
              readOnly: true,
            ),
            () => env.jdbc.update("insert into log (who) values ('i')"),
          ),
        );
      }),
    );
    out['rows'] = await env.logRows();
    return out;
  }),
  Scenario('readonly/joined-read-write-in-read-only', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy(
        'Outer',
        'readOnly',
        const Transactional(readOnly: true),
        () async {
          out['inner'] = await attempt(
            () => proxy(
              'Inner',
              'required',
              const Transactional(),
              () => env.jdbc.update("insert into log (who) values ('i')"),
            ),
          );
        },
      ),
    );
    out['rows'] = await env.logRows();
    return out;
  }),
];

// -------------------------------------------------------------- isolation

Future<Object?> _balance(Env env, [int id = 1]) =>
    env.scalar<int>('select balance from wallets where id = $id');

Future<Object?> _isolationLevel(Env env) =>
    env.scalar<String>('show transaction_isolation');

List<Scenario> _isolation() => [
  for (final MapEntry(key: name, value: level) in levels.entries) ...[
    Scenario('isolation/dirty-read/$name', (env) async {
      final out = <String, Object?>{};
      final a = await Session.begin(env, at(level));
      final b = await Session.begin(env, at(level));
      await a.run(
        () => env.jdbc.update('update wallets set balance = 0 where id = 1'),
      );
      out['bRead'] = await b.run(() => _balance(env));
      out['level'] = await b.run(() => _isolationLevel(env));
      await a.end(commit: false);
      await b.end();
      return out;
    }),
    Scenario('isolation/non-repeatable-read/$name', (env) async {
      final out = <String, Object?>{};
      final a = await Session.begin(env, at(level));
      final b = await Session.begin(env);
      out['firstRead'] = await a.run(() => _balance(env));
      out['level'] = await a.run(() => _isolationLevel(env));
      await b.run(
        () => env.jdbc.update('update wallets set balance = 150 where id = 1'),
      );
      out['bEnd'] = await b.end();
      out['secondRead'] = await a.run(() => _balance(env));
      out['aEnd'] = await a.end();
      return out;
    }),
    Scenario('isolation/phantom/$name', (env) async {
      const count = 'select count(*) from wallets where balance >= 100';
      final out = <String, Object?>{};
      final a = await Session.begin(env, at(level));
      final b = await Session.begin(env);
      out['firstCount'] = await a.run(() => env.scalar<int>(count));
      out['level'] = await a.run(() => _isolationLevel(env));
      await b.run(
        () => env.jdbc.update("insert into wallets values (3, 'cy', 200)"),
      );
      out['bEnd'] = await b.end();
      out['secondCount'] = await a.run(() => env.scalar<int>(count));
      out['aEnd'] = await a.end();
      return out;
    }),
    for (final atomic in [false, true])
      Scenario(
        'isolation/lost-update-${atomic ? 'atomic' : 'read-modify-write'}/$name',
        (env) async {
          final out = <String, Object?>{};
          final a = await Session.begin(env, at(level));
          final b = await Session.begin(env, at(level));
          final aRead = await a.run(() => _balance(env));
          final bRead = await b.run(() => _balance(env));
          out['level'] = await a.run(() => _isolationLevel(env));
          Future<Object?> write(Session s, int read, int by) => s.run(
            () => atomic
                ? env.jdbc.update(
                    'update wallets set balance = balance + $by where id = 1',
                  )
                : env.jdbc.update(
                    'update wallets set balance = ${read + by} where id = 1',
                  ),
          );
          out['aUpdate'] = await write(a, aRead! as int, 10);
          final bUpdate = write(b, bRead! as int, 20);
          out['bBlocked'] = await env.awaitBlocked();
          out['aEnd'] = await a.end();
          out['bUpdate'] = await bUpdate;
          out['bEnd'] = await b.end();
          out['balance'] = await _balance(env);
          return out;
        },
      ),
    Scenario('isolation/write-skew/$name', (env) async {
      const count = 'select count(*) from doctors where on_call';
      final out = <String, Object?>{};
      final a = await Session.begin(env, at(level));
      final b = await Session.begin(env, at(level));
      out['aCount'] = await a.run(() => env.scalar<int>(count));
      out['bCount'] = await b.run(() => env.scalar<int>(count));
      out['level'] = await a.run(() => _isolationLevel(env));
      out['aUpdate'] = await a.run(
        () => env.jdbc.update(
          "update doctors set on_call = false where name = 'alice'",
        ),
      );
      out['bUpdate'] = await b.run(
        () => env.jdbc.update(
          "update doctors set on_call = false where name = 'bob'",
        ),
      );
      out['aEnd'] = await a.end();
      out['bEnd'] = await b.end();
      out['onCall'] = await env.scalar<int>(count);
      return out;
    }),
  ],
  Scenario('isolation/deadlock', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(
      () => env.jdbc.update('update wallets set balance = 1 where id = 1'),
    );
    await b.run(
      () => env.jdbc.update('update wallets set balance = 2 where id = 2'),
    );
    final aWaits = a.run(
      () => env.jdbc.update('update wallets set balance = 3 where id = 2'),
    );
    out['aBlocked'] = await env.awaitBlocked();
    final bWaits = b.run(
      () => env.jdbc.update('update wallets set balance = 4 where id = 1'),
    );
    // The victim fails after the deadlock timeout; the other one goes on
    // when the victim's transaction ends.
    final (victim, victimResult) = await Future.any([
      aWaits.then((r) => (a, r)),
      bWaits.then((r) => (b, r)),
    ]);
    final survivor = identical(victim, a) ? b : a;
    final survivorWaits = identical(victim, a) ? bWaits : aWaits;
    final victimEnd = await victim.end();
    final survivorResult = await survivorWaits;
    final survivorEnd = await survivor.end();
    out['updates'] = ['$victimResult', '$survivorResult']..sort();
    out['ends'] = ['$victimEnd', '$survivorEnd']..sort();
    return out;
  }),
];

// ------------------------------------------------------------------ locks

Future<Object?> _lockStock(Env env, String sku) async =>
    (await env.kit.sqlStocks.findBySku(sku))?.quantity;

Future<Object?> _stockSkus(
  Env env, {
  LockMode lock = LockMode.pessimisticWrite,
  Duration? lockTimeout,
  bool skipLocked = false,
  int? limit,
}) async => [
  for (final stock in await env.kit.store.find(
    env.kit.entity<Stock>(),
    sort: Sort.by(['sku']),
    limit: limit,
    lock: lock,
    lockTimeout: lockTimeout,
    skipLocked: skipLocked,
  ))
    stock.sku,
];

List<Scenario> _locks() => [
  Scenario('lock/for-update-waits-and-sees-the-update', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => _lockStock(env, 'a'));
    await a.run(
      () => env.jdbc.update("update stock set quantity = 6 where sku = 'a'"),
    );
    final bLock = b.run(() => _lockStock(env, 'a'));
    out['bBlocked'] = await env.awaitBlocked();
    out['aEnd'] = await a.end();
    out['bQuantity'] = await bLock;
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario('lock/for-update-waits-and-sees-the-rollback', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => _lockStock(env, 'a'));
    await a.run(
      () => env.jdbc.update("update stock set quantity = 6 where sku = 'a'"),
    );
    final bLock = b.run(() => _lockStock(env, 'a'));
    out['bBlocked'] = await env.awaitBlocked();
    out['aEnd'] = await a.end(commit: false);
    out['bQuantity'] = await bLock;
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario('lock/for-share-is-shared-but-not-with-a-writer', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    out['aShare'] = await a.run(
      () async => [
        for (final s in await env.kit.sqlStocks.findByQuantityLessThan(2))
          s.sku,
      ],
    );
    out['bShare'] = await b.run(
      () async => [
        for (final s in await env.kit.sqlStocks.findByQuantityLessThan(2))
          s.sku,
      ],
    );
    out['bUpdateLock'] = await b.run(
      () => _stockSkus(env, lockTimeout: Duration.zero),
    );
    out['aEnd'] = await a.end();
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario('lock/for-share-blocks-a-writer', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => env.kit.sqlStocks.findByQuantityLessThan(2));
    final bUpdate = b.run(
      () => env.jdbc.update(
        "update stock set quantity = quantity + 1 where sku = 'b'",
      ),
    );
    out['bBlocked'] = await env.awaitBlocked();
    out['aEnd'] = await a.end();
    out['bUpdate'] = await bUpdate;
    out['bEnd'] = await b.end();
    out['quantity'] = await env.scalar<int>(
      "select quantity from stock where sku = 'b'",
    );
    return out;
  }),
  Scenario('lock/nowait', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => _lockStock(env, 'a'));
    final watch = Stopwatch()..start();
    out['bLock'] = await b.run(
      () => _stockSkus(env, lockTimeout: Duration.zero),
    );
    out['failedAtOnce'] = watch.elapsed < const Duration(seconds: 1);
    out['aEnd'] = await a.end();
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario('lock/skip-locked', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => _lockStock(env, 'a'));
    out['bSkus'] = await b.run(() => _stockSkus(env, skipLocked: true));
    out['aEnd'] = await a.end();
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario('lock/skip-locked-with-limit', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => _lockStock(env, 'a'));
    out['bSkus'] = await b.run(
      () => _stockSkus(env, skipLocked: true, limit: 1),
    );
    out['aEnd'] = await a.end();
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario('lock/lock-timeout', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => _lockStock(env, 'a'));
    final watch = Stopwatch()..start();
    out['bLock'] = await b.run(
      () => _stockSkus(env, lockTimeout: const Duration(milliseconds: 300)),
    );
    out['waited'] = watch.elapsed >= const Duration(milliseconds: 250);
    out['aEnd'] = await a.end();
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario('lock/plain-read-does-not-wait', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    await a.run(() => _lockStock(env, 'a'));
    await a.run(
      () => env.jdbc.update("update stock set quantity = 6 where sku = 'a'"),
    );
    out['bRead'] = await b.run(
      () => env.scalar<int>("select quantity from stock where sku = 'a'"),
    );
    out['aEnd'] = await a.end();
    out['bEnd'] = await b.end();
    return out;
  }),
  Scenario(
    'lock/outside-a-transaction',
    (env) async => {
      'result': await attempt(() => _lockStock(env, 'a')),
    },
  ),
];

// --------------------------------------------------------------- versions

Future<Object?> _saveAccount(Env env, Account loaded, String owner) async =>
    (await env.kit.sqlAccounts.save(
      Account(iban: loaded.iban, owner: owner, version: loaded.version),
    )).version;

Future<Account> _loadAccount(Env env) async =>
    (await env.kit.sqlAccounts.findById('acc-1'))!;

Future<Outcome> _accountRow(Env env, Outcome out) async {
  out['owner'] = await env.scalar<String>(
    "select owner from accounts where iban = 'acc-1'",
  );
  out['version'] = await env.scalar<int>(
    "select version from accounts where iban = 'acc-1'",
  );
  return out;
}

List<Scenario> _versions() => [
  Scenario('version/lost-update-detected', (env) async {
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    final b = await Session.begin(env);
    final aLoaded = (await a.run(() => _loadAccount(env)))! as Account;
    final bLoaded = (await b.run(() => _loadAccount(env)))! as Account;
    out['aSave'] = await a.run(() => _saveAccount(env, aLoaded, 'a'));
    out['aEnd'] = await a.end();
    out['bSave'] = await b.run(() => _saveAccount(env, bLoaded, 'b'));
    out['bEnd'] = await b.end();
    return await _accountRow(env, out);
  }),
  Scenario('version/sequential-saves', (env) async {
    final out = <String, Object?>{};
    out['first'] = await attempt(
      () => TransactionTemplate(env.manager).execute(
        (_) async => await _saveAccount(env, await _loadAccount(env), 'a'),
      ),
    );
    out['second'] = await attempt(
      () => TransactionTemplate(env.manager).execute(
        (_) async => await _saveAccount(env, await _loadAccount(env), 'b'),
      ),
    );
    return await _accountRow(env, out);
  }),
  for (final (name, level) in [
    ('readCommitted', Isolation.readCommitted),
    ('repeatableRead', Isolation.repeatableRead),
  ])
    Scenario('version/concurrent-save-waits/$name', (env) async {
      final out = <String, Object?>{};
      final a = await Session.begin(env, at(level));
      final b = await Session.begin(env, at(level));
      final aLoaded = (await a.run(() => _loadAccount(env)))! as Account;
      final bLoaded = (await b.run(() => _loadAccount(env)))! as Account;
      out['aSave'] = await a.run(() => _saveAccount(env, aLoaded, 'a'));
      final bSave = b.run(() => _saveAccount(env, bLoaded, 'b'));
      out['bBlocked'] = await env.awaitBlocked();
      out['aEnd'] = await a.end();
      out['bSave'] = await bSave;
      out['bEnd'] = await b.end();
      return await _accountRow(env, out);
    }),
];

// --------------------------------------------------------------- timeouts

const _sleep = 'select count(*) from pg_sleep(';

List<Scenario> _timeouts() => [
  Scenario('timeout/statement-exceeds', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy(
        'Service',
        'timed',
        const Transactional(timeout: Duration(seconds: 1)),
        () async {
          out['statement'] = await attempt(
            () => env.scalar<int>('${_sleep}3)'),
          );
        },
      ),
    );
    return out;
  }),
  Scenario('timeout/lapsed-before-the-statement', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy(
        'Service',
        'timed',
        const Transactional(timeout: Duration(seconds: 1)),
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 1300));
          out['statement'] = await attempt(() => env.scalar<int>('select 1'));
        },
      ),
    );
    return out;
  }),
  Scenario('timeout/lock-wait-bounded', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    final a = await Session.begin(env);
    await a.run(
      () => env.jdbc.update('update wallets set balance = 1 where id = 1'),
    );
    out['outer'] = await completion(
      () => proxy(
        'Service',
        'timed',
        const Transactional(timeout: Duration(seconds: 1)),
        () async {
          out['statement'] = await attempt(
            () =>
                env.jdbc.update('update wallets set balance = 2 where id = 1'),
          );
        },
      ),
    );
    out['aEnd'] = await a.end();
    return out;
  }),
  Scenario('timeout/within-the-limit', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy(
        'Service',
        'timed',
        const Transactional(timeout: Duration(seconds: 5)),
        () async {
          out['statement'] = await attempt(
            () => env.scalar<int>('${_sleep}0.2)'),
          );
        },
      ),
    );
    return out;
  }),
  Scenario('timeout/ignored-when-joined', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy('Outer', 'required', const Transactional(), () async {
        out['inner'] = await attempt(
          () => proxy(
            'Inner',
            'required',
            const Transactional(timeout: Duration(seconds: 1)),
            () => env.scalar<int>('${_sleep}1.5)'),
          ),
        );
      }),
    );
    return out;
  }),
  Scenario('timeout/own-for-requires-new', (env) async {
    final proxy = Proxy(env.manager);
    final out = <String, Object?>{};
    out['outer'] = await completion(
      () => proxy(
        'Outer',
        'timed',
        const Transactional(timeout: Duration(seconds: 10)),
        () async {
          out['inner'] = await attempt(
            () => proxy(
              'Inner',
              'requiresNew',
              const Transactional(
                propagation: Propagation.requiresNew,
                timeout: Duration(seconds: 1),
              ),
              () => env.scalar<int>('${_sleep}3)'),
            ),
          );
          out['outerStatement'] = await attempt(
            () => env.scalar<int>('select 1'),
          );
        },
      ),
    );
    return out;
  }),
];
