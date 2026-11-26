// Beans for the matrix of followed state with real advice, a real store
// and two users (test/matrix_test.dart).
import 'dart:async';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:spring_security_core/spring_security_core.dart';

class Note {
  const Note(this.id, this.owner);
  final String id;
  final String owner;
}

/// Equal by id only, for "equal but another object".
class Tag {
  const Tag(this.id, this.label);
  final int id;
  final String label;
  @override
  bool operator ==(Object other) => other is Tag && other.id == id;
  @override
  int get hashCode => id;
}

bool sameParity(Object? previous, Object? next) =>
    previous is int && next is int && previous.isEven == next.isEven;

@Service()
class Shelf {
  Shelf(this.jdbc, @Lazy() this.inner);
  final JdbcTemplate jdbc;
  final ShelfInner inner;

  @Signal()
  int value = 0;
  @Signal()
  int other = 0;
  @Signal()
  List<String> items = [];
  @Signal()
  Map<String, int> counts = {};
  @Signal(queued: false)
  int unbuffered = 0;

  int doubledRuns = 0;

  @Computed()
  int get doubled {
    doubledRuns++;
    return value * 2;
  }

  Future<void> setUp() async {
    await jdbc.execute('create table if not exists shelf(v integer)');
    await jdbc.update('delete from shelf');
    await jdbc.update('insert into shelf values (0)');
  }

  Future<int> stored() => jdbc.queryForObject<int>('select v from shelf');

  @Transactional()
  Future<void> commits(int v) async {
    value = v;
    other = v;
    await jdbc.update('update shelf set v=?', [v]);
  }

  @Transactional()
  Future<void> fails(int v) async {
    value = v;
    await jdbc.update('update shelf set v=?', [v]);
    other = v;
    throw StateError('declined');
  }

  @Transactional()
  Future<List<int>> readsOwn(int v, Future<void> gate) async {
    value = v;
    final seen = [value, doubled];
    await gate;
    return [...seen, value];
  }

  @Transactional()
  Future<void> addsItem(String item, {bool fail = false}) async {
    items.add(item);
    counts[item] = 1;
    await jdbc.update('update shelf set v=v+1');
    if (fail) {
      throw StateError('declined');
    }
  }

  @Transactional()
  Future<int> onlyReadsItems() async {
    await jdbc.queryForObject<int>('select v from shelf');
    return items.length;
  }

  @Transactional(readOnly: true)
  Future<void> readOnlyWrites(int v) async {
    value = v;
    await jdbc.queryForObject<int>('select v from shelf');
  }

  @Transactional()
  Future<void> unbufferedInTransaction(int v) async {
    unbuffered = v;
    await jdbc.update('update shelf set v=v+1');
    throw StateError('declined');
  }

  @Transactional()
  Future<void> outerWithNested(
    int outer,
    int nested, {
    required bool fail,
  }) async {
    value = outer;
    try {
      await inner.nested(nested, fail: fail);
    } on StateError {
      // The savepoint went back; the outer goes on.
    }
    other = outer;
  }

  @Transactional()
  Future<void> outerThenFails(int v) async {
    value = v;
    await inner.nested(v + 1, fail: false);
    throw StateError('declined');
  }

  @Transactional()
  Future<void> outerWithRequiresNew(int v) async {
    value = v;
    await inner.requiresNew(v + 1);
    throw StateError('declined');
  }

  void assignTwo(int v) {
    value = v;
    other = v;
  }
}

@Service()
class ShelfInner {
  ShelfInner(@Lazy() this.shelf);
  final Shelf shelf;

  @Transactional(propagation: Propagation.nested)
  Future<void> nested(int v, {required bool fail}) async {
    shelf.other = v;
    if (fail) {
      throw StateError('nested declined');
    }
  }

  @Transactional(propagation: Propagation.requiresNew)
  Future<void> requiresNew(int v) async {
    shelf.other = v;
  }
}

@Component()
class ShelfWatcher {
  ShelfWatcher(this.shelf);
  final Shelf shelf;
  final List<String> seen = [];

  @Effect()
  void watch() => seen.add('${shelf.value}/${shelf.other}');
}

@Service()
class Guarded {
  int bodies = 0;

  @Signal()
  int level = 1;

  @Signal()
  List<Note> notes = const [Note('1', 'ada'), Note('2', 'bob')];

  @PreAuthorize("hasRole('ADMIN')")
  @Computed()
  int get pre {
    bodies++;
    return level * 10;
  }

  @Secured(['ROLE_ADMIN'])
  @Computed()
  int get secured {
    bodies++;
    return level * 20;
  }

  @PostAuthorize('returnObject.owner == authentication.name')
  @Computed()
  Note get first {
    bodies++;
    return notes.first;
  }

  @PostFilter('filterObject.owner == authentication.name')
  @Computed()
  List<Note> get mine {
    bodies++;
    return notes.toList();
  }

  @PreFilter('filterObject.owner == authentication.name')
  void replace(List<Note> incoming) => notes = incoming;

  @PreAuthorize("hasRole('ADMIN')")
  void raise(int v) => level = v;

  int viaThis() => pre;
}

@Component()
class GuardedReader {
  GuardedReader(this.guarded);
  final Guarded guarded;

  @Signal()
  int tick = 0;

  @Computed()
  int get fromPre => guarded.pre + tick;

  @Computed()
  int get fromSecured => guarded.secured + tick;

  @Computed()
  List<String> get fromMine => [for (final note in guarded.mine) note.id];

  @Computed()
  String get fromFirst => guarded.first.id;

  @Computed()
  String get whoAsks =>
      SecurityContextHolder.getContext().authentication?.name ?? 'nobody';
}

@Lazy()
@Component()
class GuardedWatch {
  GuardedWatch(this.guarded);
  final Guarded guarded;
  final List<String> calls = [];

  @Signal()
  int door = 0;

  @PreAuthorize("hasRole('ADMIN')")
  @OnWatched(['door'])
  void opened() => calls.add('opened');
}

@Service()
class Combo {
  Combo(this.jdbc);
  final JdbcTemplate jdbc;
  int bodies = 0;

  @Signal()
  int base = 1;

  @PreAuthorize("hasRole('ADMIN')")
  @Cacheable('comboGuarded')
  @Computed()
  int guarded() {
    bodies++;
    return base * 3;
  }

  @PostFilter('filterObject.owner == authentication.name')
  @Cacheable('comboFiltered')
  @Computed()
  List<Note> filtered() {
    bodies++;
    return [Note('$base', 'ada'), Note('${base + 1}', 'bob')];
  }

  @PreAuthorize('isAuthenticated()')
  @Cacheable('comboTx', key: '#user')
  @Transactional()
  Future<String> load(String user) async {
    bodies++;
    await jdbc.queryForObject<int>('select 1');
    base = base + 1;
    return '$user:$bodies';
  }

  @CachePut('comboPut', key: "'k'")
  @Computed()
  int put() => base * 5;

  @Cacheable('comboEvicted')
  int cached() {
    bodies++;
    return base;
  }

  @CacheEvict('comboEvicted', allEntries: true)
  void evict(int v) => base = v;

  @Caching(
    evict: [CacheEvict('comboEvicted', allEntries: true)],
    put: [CachePut('comboPut', key: "'k'")],
  )
  int both(int v) {
    base = v;
    return v;
  }
}

class Tick extends ApplicationEvent {
  Tick(super.source, this.value);
  final int value;
}

class LaterTick extends ApplicationEvent {
  LaterTick(super.source, this.value);
  final int value;
}

@Service()
class Busy {
  @Signal()
  int heard = 0;
  @Signal()
  int ticks = 0;
  @Signal()
  int later = 0;

  @EventListener()
  void on(Tick event) => heard = event.value;

  @Scheduled(fixedRate: Duration(milliseconds: 5))
  void tick() => ticks++;

  @Async()
  @EventListener()
  Future<void> assignLater(LaterTick event) async => later = event.value;
}

class Observed {
  const Observed();
}

@Observed()
class ComposedObserved {
  const ComposedObserved();
}

@Aspect()
@Order(10)
@Component()
class OuterAspect {
  final List<String> calls = [];

  @Around('@annotation(Observed) || @annotation(ComposedObserved)')
  Object? around(ProceedingJoinPoint point) {
    calls.add('outer ${point.signature.name}');
    return point.proceed();
  }
}

@Aspect()
@Order(20)
@Component()
class InnerAspect {
  InnerAspect(this.outer);
  final OuterAspect outer;

  @Around('@annotation(Observed)')
  Object? around(ProceedingJoinPoint point) {
    outer.calls.add('inner ${point.signature.name}');
    return point.proceed();
  }
}

@Component()
class Aspected {
  @Signal()
  int value = 1;
  int bodies = 0;

  @Observed()
  @Computed()
  int get observed {
    bodies++;
    return value + 1;
  }

  @ComposedObserved()
  int composed() => value;

  @Observed()
  void assign(int v) => value = v;

  int viaThis() => observed;
}

@Component()
class SelfCalling {
  SelfCalling(@Lazy() this.self);
  final SelfCalling self;

  final List<String> log = [];

  @Signal()
  int value = 1;

  @PreAuthorize("hasRole('ADMIN')")
  int adminValue() {
    log.add('admin body');
    return value;
  }

  int throughThis() => adminValue();
  int throughSelf() => self.adminValue();

  @Computed()
  int get followedThroughThis => adminValue() + 1;
}

@Component()
class Options {
  @Signal(hidden: true)
  String secretNote = 's';

  @Signal(equals: sameParity)
  int parity = 0;

  @Signal()
  Tag tag = const Tag(1, 'first');

  @Signal(queue: 'manual')
  int held = 0;

  @Signal(queue: 'small')
  int smallA = 0;
  @Signal(queue: 'small')
  int smallB = 0;

  @Signal(queue: 'oldest')
  int oldestA = 0;
  @Signal(queue: 'oldest')
  int oldestB = 0;

  @Signal(queue: 'newest')
  int newestA = 0;
  @Signal(queue: 'newest')
  int newestB = 0;

  @Signal(queue: 'immediate')
  int instant = 0;

  @Signal(queue: 'frames')
  int framed = 0;

  @Signal(queue: 'ticking')
  int ticked = 0;

  @Signal(eager: true)
  int ready = 0;

  @Signal(followCollection: false)
  List<int> plainList = [];

  @Signal()
  List<int> followedList = [];

  @Computed()
  int get heldTwice => held * 2;
}

@Component()
class Watched {
  final List<String> calls = [];

  @Signal()
  int a = 0;
  @Signal()
  int b = 0;
  @Signal()
  int c = 0;
  @Signal()
  int slow = 0;
  @Signal()
  int bad = 0;

  @Computed()
  int get sum => a + b;

  @OnWatched(['a', 'b'])
  void groupOn() => calls.add('group on');

  @OnUnwatched(['a', 'b'])
  void groupOff() => calls.add('group off');

  @OnWatched(['c', 'sum'], each: true)
  void eachOn() => calls.add('each on');

  @OnUnwatched(['slow'], delay: Duration(milliseconds: 20))
  void slowOff() => calls.add('slow off');

  @OnWatched(['bad'])
  void failsOn() => throw StateError('watch failed');

  @OnUnwatched(['bad'])
  void failsOff() => throw StateError('unwatch failed');
}

@Component()
@Scope('prototype')
class ProtoState {
  @Signal(queue: 'manual')
  int value = 0;
}

@Component()
@Scope('custom')
class DiscardState {
  @Signal(queue: 'manual')
  int value = 0;
}

@Component()
@Scope('custom')
class FlushState {
  @Signal(queue: 'manual', onScopeEnd: OnScopeEnd.flush)
  int value = 0;
}

@Component()
@Scope('custom')
class DeferState {
  @Signal(queue: 'manual', onScopeEnd: OnScopeEnd.defer)
  int value = 0;
}

@Component()
@Scope('route')
class RouteScoped {
  @Signal(queue: 'manual')
  int value = 0;
}

@Component()
@Scope('branch')
class BranchScoped {
  @Signal(queue: 'manual', onScopeEnd: OnScopeEnd.flush)
  int value = 0;
}

/// The custom scope of the test; `route` and `branch` are the
/// navigation starter's own.
@Component()
class TestScopes implements BeanFactoryPostProcessor {
  final SimpleMapScope custom = SimpleMapScope();

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      beanFactory.registerScope('custom', custom);
}

@Component()
class Failing {
  @Signal()
  int value = 0;
  @Signal()
  int other = 0;
  final List<int> survived = [];

  @Computed()
  int get computedFails {
    if (value < 0) {
      throw ArgumentError('negative');
    }
    return value;
  }

  @Effect()
  void fails() {
    if (value == 13) {
      throw StateError('effect failed');
    }
  }

  @Effect()
  void survives() => survived.add(value);
}

@Lazy()
@Component()
class FailsFirst {
  @Signal()
  int value = 0;

  @Effect()
  void fails() => throw StateError('first run');
}

/// The handler of the errors no caller waits for.
@Component()
class SignalErrors implements TypedErrorHandler<SignalExecutionException> {
  final List<SignalExecutionException> errors = [];
  bool throwing = false;

  @override
  void handleError(SignalExecutionException error, StackTrace stackTrace) {
    errors.add(error);
    if (throwing) {
      throw StateError('handler failed');
    }
  }
}

/// `@Effect` and `@OnWatched` with each kind of advice that can go on a
/// method without a result.
@Lazy()
@Service()
class AdvisedRuns {
  AdvisedRuns(this.jdbc, this.source);
  final JdbcTemplate jdbc;
  final RunSource source;

  final List<String> runs = [];

  @Secured(['ROLE_ADMIN'])
  @Effect()
  void securedEffect() {
    source.value;
    runs.add('secured');
  }

  @PreAuthorize("hasRole('ADMIN')")
  @Effect()
  void preEffect() {
    source.value;
    runs.add('pre');
  }

  @Observed()
  @Effect()
  void aspectEffect() {
    source.value;
    runs.add('aspect');
  }

  @Transactional()
  @Effect()
  Future<void> transactionalEffect() async {
    final value = source.value;
    await jdbc.queryForObject<int>('select 1');
    runs.add(
      'tx ${TransactionSynchronizationManager.isActualTransactionActive} $value',
    );
  }

  @Signal()
  int watchedByAdvice = 0;

  @Transactional()
  @OnWatched(['watchedByAdvice'])
  Future<void> transactionalWatch() async {
    await jdbc.queryForObject<int>('select 1');
    runs.add(
      'watch tx ${TransactionSynchronizationManager.isActualTransactionActive}',
    );
  }

  @Observed()
  @OnUnwatched(['watchedByAdvice'])
  void aspectUnwatch() => runs.add('unwatch aspect');
}

@Service()
class RunSource {
  @Signal()
  int value = 0;
}

/// A value under a guard, a cache and a transaction together.
@Service()
class FullStack {
  FullStack(this.jdbc);
  final JdbcTemplate jdbc;
  int bodies = 0;

  @Signal()
  int base = 1;

  @PreAuthorize("hasRole('ADMIN')")
  @Cacheable('fullStack')
  @Transactional(readOnly: true)
  @Computed()
  Future<int> value() async {
    final seen = base;
    bodies++;
    await jdbc.queryForObject<int>('select 1');
    return seen * 10;
  }

  @CacheEvict('fullStack', allEntries: true)
  void evict() {}

  @Caching(
    cacheable: [Cacheable('fullStackCaching')],
    evict: [CacheEvict('fullStack', allEntries: true)],
  )
  @Computed()
  int cachingOnComputed() => base;

  @Transactional()
  @Computed()
  Future<int> failsInTransaction() async {
    if (base < 0) {
      throw StateError('declined');
    }
    await jdbc.queryForObject<int>('select 1');
    return base;
  }
}

/// What the flush schedules of the test did.
@Component()
class ScheduleLog {
  int schedules = 0;
  int flushes = 0;
  int cancels = 0;
}

/// A schedule of the application's own: a debounce, which tells the
/// readers 20 ms after the last write of a burst (state in the closure).
@Configuration()
class Schedules {
  @Bean()
  @Qualifier('delayed')
  SignalFlushSchedule delayedSchedule(ScheduleLog log) {
    Timer? timer;
    return (flush) {
      log.schedules++;
      timer?.cancel();
      final next = timer = Timer(const Duration(milliseconds: 20), () {
        log.flushes++;
        flush();
      });
      return () {
        log.cancels++;
        next.cancel();
      };
    };
  }
}

@Component()
class Delayed {
  @Signal(queue: 'delayed')
  int value = 0;

  @Signal(queue: 'delayed')
  int other = 0;

  @PreAuthorize("hasRole('ADMIN')")
  void adminAssigns(int v) => value = v;
}

class CartEvent extends ApplicationEvent {
  CartEvent(super.source, this.value);
  final int value;
}

@Service()
class Cart {
  Cart(this.jdbc);
  final JdbcTemplate jdbc;

  @Signal()
  int count = 0;
  @Signal()
  int other = 0;
  @Signal()
  bool loading = false;
  @Signal()
  List<String> lines = [];
  @Signal()
  int ticks = 0;

  int loads = 0;

  @SignalBuffer()
  Future<void> fill(int value, Future<void> gate) async {
    count = value;
    other = value;
    lines.add('$value');
    await gate;
  }

  @SignalBuffer()
  Future<List<int>> readsOwn(int value) async {
    count = value;
    await Future<void>.delayed(Duration.zero);
    return [count, other];
  }

  @SignalBuffer()
  Future<void> fails(int value) async {
    count = value;
    await Future<void>.delayed(Duration.zero);
    throw StateError('declined');
  }

  @SignalBuffer()
  Future<void> outer(int value) async {
    count = value;
    await fill(value + 1, Future<void>.value());
    other = value + 2;
  }

  @SignalBuffer(false)
  Future<void> showLoader(Future<void> gate) async {
    loading = true;
    await gate;
    loading = false;
  }

  @SignalBuffer()
  Future<void> loaderBuffered(Future<void> gate) async {
    loading = true;
    await gate;
    loading = false;
  }

  @SignalBuffer()
  Future<void> leavesWork() async {
    count = 1;
    Timer(const Duration(milliseconds: 5), () => count = 2);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 10), () => other = 3),
    );
  }

  @SignalBuffer()
  @Transactional()
  Future<void> inTransaction(int value, {bool fail = false}) async {
    count = value;
    await jdbc.queryForObject<int>('select 1');
    if (fail) {
      throw StateError('declined');
    }
  }

  @SignalBuffer()
  @PreAuthorize("hasRole('ADMIN')")
  Future<void> guardedFill(int value) async {
    count = value;
    await Future<void>.delayed(Duration.zero);
  }

  @SignalBuffer()
  @PostFilter('filterObject.owner == authentication.name')
  Future<List<Note>> filteredWithWrites() async {
    count = count + 1;
    await Future<void>.delayed(Duration.zero);
    return const [Note('1', 'ada'), Note('2', 'bob')];
  }

  @SignalBuffer()
  @PostAuthorize('returnObject.owner == authentication.name')
  Future<Note> authorizedWithWrites() async {
    other = other + 1;
    await Future<void>.delayed(Duration.zero);
    return const Note('1', 'ada');
  }

  @SignalBuffer()
  @PreAuthorize('isAuthenticated()')
  @Cacheable('cartLoads')
  Future<int> cachedLoad() async {
    loads++;
    count = count + 10;
    await Future<void>.delayed(Duration.zero);
    return loads;
  }

  @CacheEvict('cartLoads', allEntries: true)
  void evictLoads() {}

  @SignalBuffer()
  @Scheduled(fixedRate: Duration(milliseconds: 5))
  Future<void> tickTwice() async {
    ticks++;
    await Future<void>.delayed(Duration.zero);
    ticks++;
  }

  @SignalBuffer()
  @EventListener()
  Future<void> onEvent(CartEvent event) async {
    count = event.value;
    await Future<void>.delayed(Duration.zero);
    other = event.value;
  }
}

@Component()
@Scope('custom')
class ScopedCart {
  @Signal()
  int value = 0;

  @Signal(onScopeEnd: OnScopeEnd.flush)
  int flushed = 0;

  @SignalBuffer()
  Future<void> fill(int v, Future<void> gate) async {
    value = v;
    flushed = v;
    await gate;
  }
}

/// A plain object, no bean: its writes to beans' fields buffered by hand.
class Checkout {
  Checkout(this.cart);
  final Cart cart;

  Future<void> run(int value, Future<void> gate) => SignalBuffer.run(() async {
    cart.count = value;
    await gate;
    cart.other = value;
  });
}

/// A reader created as a user the guard refuses, before the guarded value
/// was ever computed.
@Lazy()
@Component()
class EarlyReader {
  EarlyReader(this.guarded);
  final Guarded guarded;
  final List<String> seen = [];

  @Effect()
  void watch() {
    try {
      seen.add('pre=${guarded.pre}');
    } on AccessDeniedException {
      seen.add('refused');
    }
  }
}

/// Readers made for a user, each run again by others' changes.
@Lazy()
@Component()
class OwnedReaders {
  OwnedReaders(this.guarded, this.combo);
  final Guarded guarded;
  final Combo combo;
  final List<String> strict = [];
  final List<List<String>> mine = [];
  final List<String> cached = [];

  // Reads the guarded value only once the level was raised: uncaught.
  @Effect()
  void strictly() {
    if (guarded.level > 1) {
      strict.add('pre=${guarded.pre}');
    } else {
      strict.add('level=${guarded.level}');
    }
  }

  @Effect()
  void filtered() => mine.add([for (final note in guarded.mine) note.id]);

  @Effect()
  void fromCache() {
    try {
      cached.add('guarded=${combo.guarded()}');
    } on AccessDeniedException {
      cached.add('refused');
    }
  }
}
