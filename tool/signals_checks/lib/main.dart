// Real beans for the check of signals with real advice. Everything that
// happens is appended to [trace], in order.
import 'dart:async';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'package:signals_checks/spring_gen/main.spring.dart';

final List<String> trace = [];
void t(String line) => trace.add(line);

String who() =>
    SecurityContextHolder.getContext().authentication?.name ?? '(nobody)';

class Doc {
  Doc(this.id, this.owner);
  final String id;
  final String owner;
  @override
  String toString() => '$id:$owner';
}

class TxHook extends TransactionSynchronization {
  @override
  void afterCommit() => t('COMMIT');
  @override
  void afterCompletion(TransactionCompletion status) =>
      t('TX-END ${status.name}');
}

void hook() {
  t('TX-OPEN');
  TransactionSynchronizationManager.registerSynchronization(TxHook());
}

// ---------- 1. @Transactional ----------
@Service()
class Ledger {
  Ledger(this.jdbc);
  final JdbcTemplate jdbc;

  @Signal()
  int balance = 0;
  @Signal()
  int other = 0;

  Future<void> setUp() async {
    await jdbc.execute('create table if not exists acc(v integer)');
    await jdbc.update('delete from acc');
    await jdbc.update('insert into acc values (0)');
  }

  Future<int> db() => jdbc.queryForObject<int>('select v from acc');

  @Transactional()
  Future<void> syncLooking(int v) {
    hook();
    t('body assign balance=$v');
    balance = v;
    other = v;
    return jdbc.update('update acc set v=?', [v]).then((_) => t('body end'));
  }

  @Transactional()
  Future<void> asyncBody(int v) async {
    hook();
    t('body assign balance=$v');
    balance = v;
    await jdbc.update('update acc set v=?', [v]);
    t('body (after await) assign other=$v');
    other = v;
    t('body (after await) assign balance=${v + 1}');
    balance = v + 1;
    t('body end');
  }

  @Transactional()
  Future<void> asyncFails(int v) async {
    hook();
    balance = v;
    await jdbc.update('update acc set v=?', [v]);
    other = v;
    t('body throws');
    throw StateError('boom');
  }

  Future<void> plainAsync(int v) async {
    t('plain async body assigns both');
    balance = v;
    other = v;
    t('plain async body assigned, before await');
    await Future<void>.delayed(Duration.zero);
    t('plain async after await assigns other');
    other = v + 1;
  }

  @Transactional()
  Future<void> gated(int v, Future<void> gate) async {
    hook();
    balance = v;
    await jdbc.update('update acc set v=?', [v]);
    await gate;
    t('body throws');
    throw StateError('boom');
  }

  @Transactional()
  Future<void> syncFails(int v) {
    hook();
    balance = v;
    return jdbc.update('update acc set v=?', [v]).then<void>((_) {
      t('body throws');
      throw StateError('boom');
    });
  }
}

@Component()
class LedgerWatcher {
  LedgerWatcher(this.ledger);
  final Ledger ledger;

  @Effect()
  void watch() =>
      t('@Effect saw balance=${ledger.balance} other=${ledger.other}');
}

// ---------- 2,3,4. Method security ----------
@Service()
class Vault {
  int computes = 0;

  @Signal()
  int secret = 1;

  @Signal()
  List<Doc> docs = [Doc('1', 'ada'), Doc('2', 'bob'), Doc('3', 'ada')];

  @Signal()
  Map<String, String> owners = {'1': 'ada', '2': 'bob', '3': 'ada'};

  @PreAuthorize("hasRole('ADMIN')")
  void assignAdmin(int v) {
    t('body assignAdmin');
    secret = v;
  }

  @PreAuthorize("hasRole('ADMIN')")
  @Computed()
  int get guarded {
    computes++;
    t('compute guarded as ${who()}');
    return secret * 10;
  }

  @PreAuthorize("hasRole('ADMIN')")
  @Computed()
  Future<int> get guardedLater async {
    computes++;
    final value = secret * 10;
    t('compute guardedLater as ${who()}');
    return value;
  }

  @Computed()
  int get derivedSameBean => guarded + 1;

  @PostAuthorize("returnObject == authentication.name")
  String postAssign(String v) {
    t('body postAssign');
    secret = secret + 1;
    return v;
  }

  @PostAuthorize("returnObject.owner == authentication.name")
  @Computed()
  Doc get firstDoc {
    computes++;
    t('compute firstDoc as ${who()} (secret=$secret)');
    return docs.first;
  }

  @PostAuthorize("returnObject.owner == authentication.name")
  @Computed()
  Future<Doc> get firstDocLater async {
    computes++;
    final first = docs.first;
    t('compute firstDocLater as ${who()}');
    return first;
  }

  @PostFilter('filterObject.owner == authentication.name')
  @Computed()
  List<Doc> get visible {
    computes++;
    t('compute visible as ${who()}');
    return docs.toList();
  }

  @PostFilter('filterObject.owner == authentication.name')
  @Computed()
  Future<List<Doc>> get visibleLater async {
    computes++;
    final all = docs.toList();
    t('compute visibleLater as ${who()}');
    return all;
  }

  @PostFilter('filterObject.value == authentication.name')
  @Computed()
  Map<String, String> get visibleMap {
    computes++;
    t('compute visibleMap as ${who()}');
    return {...owners};
  }

  @PostFilter('filterObject.value == authentication.name')
  @Computed()
  Map<String, String> get keptMap => owners;

  @PostFilter('filterObject.value == authentication.name')
  Map<String, String> ownersOf() => owners;

  @PostFilter('filterObject.owner == authentication.name')
  List<Doc> docsOf() => docs;

  @PreFilter('filterObject.owner == authentication.name')
  void replaceDocs(List<Doc> incoming) {
    t('body replaceDocs got $incoming');
    docs = incoming;
  }

  @Computed()
  String get perUser {
    computes++;
    final name = who();
    t('compute perUser as $name');
    return 'private of $name (secret=$secret)';
  }
}

@Service()
class TxVault {
  TxVault(this.jdbc);
  final JdbcTemplate jdbc;

  @Signal()
  int value = 0;

  Future<void> setUp() async {
    await jdbc.execute('create table if not exists tv(v integer)');
    await jdbc.update('delete from tv');
    await jdbc.update('insert into tv values (0)');
  }

  Future<int> db() => jdbc.queryForObject<int>('select v from tv');

  @Transactional()
  @PostAuthorize("returnObject == authentication.name")
  Future<String> save(int v, String returned) async {
    hook();
    t('body assign value=$v');
    value = v;
    await jdbc.update('update tv set v=?', [v]);
    t('body end');
    return returned;
  }
}

@Component()
class VaultReader {
  VaultReader(this.vault);
  final Vault vault;
  int computes = 0;

  @Signal()
  int tick = 0;

  @Computed()
  int get fromGuarded {
    computes++;
    t('compute VaultReader.fromGuarded as ${who()}');
    return vault.guarded + tick;
  }

  @Computed()
  List<Doc> get fromVisible {
    t('compute VaultReader.fromVisible as ${who()}');
    return vault.visible;
  }

  @Computed()
  String get fromFirstDoc {
    t('compute VaultReader.fromFirstDoc as ${who()}');
    return vault.firstDoc.id;
  }
}

@Component()
class VaultEffect {
  VaultEffect(this.vault);
  final Vault vault;

  @Effect()
  void watch() {
    try {
      t('VaultEffect as ${who()} read guarded=${vault.guarded}');
    } on Object catch (error) {
      t('VaultEffect as ${who()} refused: ${error.runtimeType}');
    }
  }
}

@Lazy()
@Component()
class LateVaultEffect {
  LateVaultEffect(this.vault);
  final Vault vault;

  @Effect()
  void watch() {
    try {
      t('LateVaultEffect as ${who()} read guarded=${vault.guarded}');
    } on Object catch (error) {
      t('LateVaultEffect as ${who()} refused: ${error.runtimeType}');
    }
  }
}

@Lazy()
@Component()
class UncaughtVaultEffect {
  UncaughtVaultEffect(this.vault);
  final Vault vault;

  @Effect()
  void watch() => t('UncaughtVaultEffect as ${who()} read ${vault.guarded}');
}

// ---------- 5. @Cacheable, @Transactional on @Computed ----------
@Service()
class Priced {
  Priced(this.jdbc);
  final JdbcTemplate jdbc;

  int bodies = 0;

  @Signal()
  int n = 1;

  @Cacheable('priced')
  @Computed()
  int cachedSync() {
    bodies++;
    t('body cachedSync n=$n');
    return n * 100;
  }

  @Cacheable('pricedAsync')
  @Computed()
  Future<int> cachedAsync() async {
    bodies++;
    final seen = n;
    t('body cachedAsync n=$seen');
    return seen * 100;
  }

  @CacheEvict('priced', allEntries: true)
  void evict() => t('evict');

  @CacheEvict('pricedAsync', allEntries: true)
  void evictAsync() => t('evictAsync');

  @Computed()
  Future<int> plainLoaded() async {
    final seen = n;
    t('plainLoaded body n=$seen');
    await Future<void>.delayed(Duration.zero);
    return seen * 2;
  }

  @Transactional(readOnly: true)
  @Computed()
  Future<int> loaded() async {
    final seen = n;
    t(
      'TX-OPEN loaded n=$seen inTx='
      '${TransactionSynchronizationManager.isActualTransactionActive}',
    );
    TransactionSynchronizationManager.registerSynchronization(TxHook());
    await jdbc.queryForObject<int>('select 1');
    return seen * 2;
  }

  @PreAuthorize("hasRole('ADMIN')")
  @Cacheable('guardedCache')
  @Computed()
  int guardedCached() {
    bodies++;
    t('body guardedCached as ${who()}');
    return n * 7;
  }

  @PostFilter('filterObject.owner == authentication.name')
  @Cacheable('filteredCache')
  @Computed()
  List<Doc> filteredCached() {
    bodies++;
    t('body filteredCached as ${who()}');
    return [Doc('1', 'ada'), Doc('2', 'bob')];
  }
}

// ---------- 6. Self-calls ----------
class PlainHelper {
  PlainHelper(this.run);
  final void Function() run;
  void call() => run();
}

@Component()
class Runner {
  void run(void Function() callback) {
    t('Runner runs callback');
    callback();
  }

  Future<void> runLater(void Function() callback) async {
    await Future<void>.delayed(Duration.zero);
    t('Runner runs callback after await');
    callback();
  }
}

@Service()
class Selfish {
  Selfish(this.jdbc, this.runner);
  final JdbcTemplate jdbc;
  final Runner runner;

  @Signal()
  int v = 0;

  /// The proxy of this bean, as another object would hold it.
  Selfish? reference;

  @Transactional()
  Future<void> save(int x) async {
    t(
      'save body inTx='
      '${TransactionSynchronizationManager.isActualTransactionActive}',
    );
    v = x;
  }

  @PreAuthorize("hasRole('ADMIN')")
  void adminOnly(int x) {
    t('adminOnly body ran as ${who()}');
    v = x;
  }

  @PreAuthorize("hasRole('ADMIN')")
  @Computed()
  int get adminValue => v * 10;

  void selfSave() => save(5);
  void selfAdmin() => adminOnly(6);

  Future<void> afterAwaitSelf() async {
    await Future<void>.delayed(Duration.zero);
    t('afterAwaitSelf calling adminOnly as ${who()}');
    adminOnly(7);
  }

  Future<void> afterAwaitTx() async {
    await Future<void>.delayed(Duration.zero);
    await save(8);
  }

  void viaRunner() => runner.run(() => adminOnly(9));

  Future<void> viaRunnerLater() => runner.runLater(() => adminOnly(10));

  /// A plain object (not a bean) holding the proxy calls it back.
  void viaPlainObject(Selfish proxy) =>
      PlainHelper(() => proxy.adminOnly(11))();

  Future<void> viaPlainObjectAfterAwait(Selfish proxy) async {
    await Future<void>.delayed(Duration.zero);
    PlainHelper(() => proxy.adminOnly(12))();
  }

  /// Assigns after an await: readers run while this body is innermost.
  Future<void> assignAfterAwait(int x) async {
    await Future<void>.delayed(Duration.zero);
    t('assignAfterAwait assigning as ${who()}');
    v = x;
    t('assignAfterAwait assigned');
  }

  void assignNow(int x) => v = x;

  @Transactional()
  Future<void> assignInTx(int x) async {
    t('assignInTx assigning as ${who()}');
    v = x;
    t('assignInTx assigned');
  }

  void viaUnadvised(Unadvised u) => u.callSelfish();

  void publishVia(ApplicationEventPublisher publisher) =>
      publisher.publishEvent(Ping(this));
}

// A bean with no advice at all: it has no proxy, so nothing marks that
// the call left the caller's body.
@Component()
class Unadvised {
  Unadvised(this.factory);
  final BeanFactory factory;

  void callSelfish() => factory.getBean<Selfish>().adminOnly(13);
  String callPlain() => factory.getBean<PlainSecured>().adminOnly();
}

// The same, with advice: the control.
@Component()
class Advised2 {
  Advised2(this.factory);
  final BeanFactory factory;

  @PreAuthorize('permitAll')
  String callPlain() => factory.getBean<PlainSecured>().adminOnly();
}

// No signals anywhere: is the skip about signals or about every proxy?
@Service()
class PlainSecured {
  PlainSecured(this.unadvised, this.advised);
  final Unadvised unadvised;
  final Advised2 advised;

  @PreAuthorize("hasRole('ADMIN')")
  String adminOnly() {
    t('PlainSecured.adminOnly body ran as ${who()}');
    return 'admin data';
  }

  String openViaUnadvised() => unadvised.callPlain();
  String openViaAdvised() => advised.callPlain();

  @PreAuthorize('permitAll')
  String advisedEntryViaUnadvised() => unadvised.callPlain();

  @PreAuthorize('permitAll')
  Future<String> advisedEntryViaUnadvisedLater() async {
    await Future<void>.delayed(Duration.zero);
    return unadvised.callPlain();
  }

  Future<String> openViaUnadvisedLater() async {
    await Future<void>.delayed(Duration.zero);
    return unadvised.callPlain();
  }
}

@Service()
class Entry {
  Entry(this.selfish, this.unadvised);
  final Selfish selfish;
  final Unadvised unadvised;
}

class Ping extends ApplicationEvent {
  Ping(super.source);
}

@Component()
class PingListener {
  PingListener(this.factory);
  final BeanFactory factory;

  @EventListener()
  void on(Ping event) {
    t('listener (no proxy) calls Selfish.adminOnly as ${who()}');
    factory.getBean<Selfish>().adminOnly(14);
  }
}

@Lazy()
@Component()
class SelfishEffect {
  SelfishEffect(this.selfish);
  final Selfish selfish;

  @Effect()
  void watch() {
    final v = selfish.v;
    try {
      t('SelfishEffect as ${who()} v=$v read adminValue=${selfish.adminValue}');
    } on Object catch (e) {
      t('SelfishEffect as ${who()} v=$v refused ${e.runtimeType}');
    }
  }
}

// ---------- 7. @Effect with @PreAuthorize ----------
@Service()
class EffectState {
  @Signal()
  int value = 0;
}

@Lazy()
@Component()
class GuardedEffect {
  GuardedEffect(this.state);
  final EffectState state;

  @PreAuthorize("hasRole('ADMIN')")
  @Effect()
  void watch() => t('GuardedEffect body as ${who()} value=${state.value}');
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  await springApplication.runAsync(args);
}
