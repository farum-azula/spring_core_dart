// The two services of the propagation matrix, written the way the
// generator's proxies run a `@Transactional` method: the annotation of the
// method gives the plan (definition and rollback rules) of the starter's
// own TransactionInterceptor, and the method's body runs in a transaction of
// that plan. `Outer` calls `Inner`, whose method has the propagation under
// test. tool/data_reference has the same two services with real
// `@Transactional` annotations.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_template.dart'
    show runInTransaction;

import 'env.dart';

/// The exceptions of the scenarios. `Soft` is the one transactions may
/// commit through, `Hard` a kind of it, `Checked` is Java's checked
/// exception, `Fatal` an error.
class Boom implements Exception {}

class Soft implements Exception {}

class Hard extends Soft {}

class Checked implements Exception {}

class Fatal extends Error {}

/// What the inner method does after writing its row.
enum Variant {
  /// Nothing fails.
  ok,

  /// The inner method throws and the outer one catches it.
  innerThrowsCaught,

  /// The inner method throws and the outer one lets it through.
  innerThrowsPropagates,

  /// The inner method returns, the outer one throws at its end.
  outerThrowsAfter,
}

/// What the starter's generated proxies do around a `@Transactional`
/// method.
final class Proxy {
  Proxy(this.manager)
    : interceptor = TransactionInterceptor(
        transactionManager: manager,
        introspector: BeanIntrospector()
          ..registerTypeTests({
            Boom: (v) => v is Boom,
            Soft: (v) => v is Soft,
            Hard: (v) => v is Hard,
            Checked: (v) => v is Checked,
            Fatal: (v) => v is Fatal,
          }),
      );

  final DataSourceTransactionManager manager;
  final TransactionInterceptor interceptor;

  /// Runs [body] as the method [name] of [bean] annotated [annotation].
  Future<T> call<T>(
    String bean,
    String name,
    Transactional annotation,
    Future<T> Function() body,
  ) {
    final plan = interceptor.planOf(
      MethodSignature(
        name: name,
        declaringType: bean,
        targetType: bean,
        returnType: 'Future',
        annotations: [annotation],
      ),
    )!;
    return runInTransaction<T>(
      manager,
      plan.definition,
      (_) => body(),
      rollbackOn: plan.rollsBackOn,
    );
  }
}

/// The state one propagation scenario shares between its services.
final class Ctx {
  Ctx(this.env, this.variant, this.innerPropagation);

  final Env env;
  final Variant variant;
  final Propagation innerPropagation;
  final out = <String, Object?>{};

  /// The transaction the outer method ran in (`none` without one).
  String outerXid = 'none';

  bool get innerThrows =>
      variant == Variant.innerThrowsCaught ||
      variant == Variant.innerThrowsPropagates;
}

/// The annotations the propagations are tested with.
const propagations = <Propagation, Transactional>{
  Propagation.required: Transactional(),
  Propagation.supports: Transactional(propagation: Propagation.supports),
  Propagation.mandatory: Transactional(propagation: Propagation.mandatory),
  Propagation.requiresNew: Transactional(propagation: Propagation.requiresNew),
  Propagation.notSupported: Transactional(
    propagation: Propagation.notSupported,
  ),
  Propagation.never: Transactional(propagation: Propagation.never),
  Propagation.nested: Transactional(propagation: Propagation.nested),
};

/// The bean with the method under test.
final class Inner {
  Inner(this.proxy);

  final Proxy proxy;

  /// Calls the method of [propagation].
  Future<void> call(Propagation propagation, Ctx c) => proxy(
    'Inner',
    propagation.name,
    propagations[propagation]!,
    () => _work(c),
  );

  Future<void> _work(Ctx c) async {
    final env = c.env;
    c.out['innerSeesO1'] = await env.scalar<int>(
      "select count(*) from log where who = 'o1'",
    );
    final state = await env.txState();
    c.out['innerTx'] = state == 'none'
        ? 'none'
        : (state == c.outerXid ? 'same' : 'new');
    await env.jdbc.update("insert into log (who) values ('i')");
    if (c.innerThrows) {
      throw Boom();
    }
  }
}

/// The bean that calls [Inner].
final class Outer {
  Outer(this.proxy, this.inner);

  final Proxy proxy;
  final Inner inner;

  /// Calls the method of [propagation]; without one, a method with no
  /// annotation.
  Future<void> call(Propagation? propagation, Ctx c) => propagation == null
      ? _body(c)
      : proxy(
          'Outer',
          propagation.name,
          propagations[propagation]!,
          () => _body(c),
        );

  Future<void> _body(Ctx c) async {
    final env = c.env;
    await env.jdbc.update("insert into log (who) values ('o1')");
    c.outerXid = await env.txState();
    c.out['outerTx'] = c.outerXid == 'none' ? 'none' : 'tx';
    try {
      await inner.call(c.innerPropagation, c);
      c.out['inner'] = 'ok';
    } on Object catch (error) {
      if (c.variant == Variant.innerThrowsPropagates) {
        rethrow;
      }
      c.out['inner'] = kindOf(error);
    }
    c.out['outerSeesI'] = await env.scalar<int>(
      "select count(*) from log where who = 'i'",
    );
    await env.jdbc.update("insert into log (who) values ('o2')");
    if (c.variant == Variant.outerThrowsAfter) {
      throw Boom();
    }
  }
}
