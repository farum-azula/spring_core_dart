// Beans for the edges of followed state (signal_edges_test.dart): state
// from a base class and a mixin, late and injected fields, scopes, a
// method that throws, an effect that writes what it reads. The generator
// writes spring_gen/cases.spring.dart (`dart run build_runner build`).
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

import '../spring_gen/cases/cases.spring.dart';

abstract class Counted {
  @Signal()
  int count = 0;

  @Computed()
  int get twice => count * 2;
}

mixin Priced {
  @Signal()
  double price = 1;
}

@Component()
class Inherited extends Counted with Priced {
  final List<int> seen = [];

  @Computed()
  double get cost => count * price;

  @Effect()
  void watch() => seen.add(count);
}

@Component()
class Overriding extends Counted {
  @override
  @Computed()
  int get twice => count * 3;
}

@Component()
class Late {
  @Signal()
  late String name;

  @Signal()
  String? nick;

  @Computed()
  String get shown => nick ?? name;
}

@Component()
class Settings {
  final String currency = 'EUR';
}

@Component()
class Injected {
  @Autowired()
  @Signal()
  late Settings settings;

  @Value(r'${cases.limit:3}')
  @Signal()
  late int limit;

  int started = 0;

  @Computed()
  int get doubled => limit * 2;

  // Both: called once as the bean is made, and run as an effect.
  @PostConstruct()
  @Effect()
  void start() {
    started++;
    limit;
  }
}

@Component()
class Constructed {
  Constructed() {
    count = 5;
    initial = twice;
  }

  @Signal()
  int count = 0;

  late final int initial;
  int ready = -1;

  @Computed()
  int get twice => count * 2;

  @PostConstruct()
  void init() {
    count++;
    ready = twice;
  }
}

@Component()
@Scope('prototype')
class Draft {
  @Signal()
  String text = '';

  int runs = 0;

  @Effect()
  void watch() {
    text;
    runs++;
  }
}

@Component()
@Scope('screen')
class ScreenState {
  @Signal()
  int taps = 0;

  int runs = 0;
  bool destroyed = false;
  int tapsAtDestroy = -1;

  @Effect()
  void watch() {
    taps;
    runs++;
  }

  @PreDestroy()
  void bye() {
    destroyed = true;
    tapsAtDestroy = taps;
  }
}

/// The scope of [ScreenState], ended by the test.
@Component()
class ScreenScope implements BeanFactoryPostProcessor {
  final SimpleMapScope scope = SimpleMapScope();

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      beanFactory.registerScope('screen', scope);
}

typedef Titles = List<String>;

@Component()
class Shapes {
  @Signal()
  void Function(int)? listener;

  @Signal()
  (int, String) pair = (1, 'a');

  @Signal()
  Map<String, List<int>>? index;

  @Signal()
  Iterable<int> lazy = const [];

  @Signal()
  dynamic any;

  @Signal()
  Object? thing;

  @Signal()
  Titles titles = [];

  @Signal()
  Set<int> ids = {};

  @Signal()
  covariant num amount = 0;

  // Declared as classes of their own: handed out as they are.
  @Signal()
  HashSet<int> fast = HashSet();

  @Signal()
  ListQueue<int> line = ListQueue();

  @Signal()
  LinkedHashMap<String, int> byName = LinkedHashMap();

  @Signal()
  UnmodifiableListView<int> frozen = UnmodifiableListView(const []);

  static int shared = 0;

  int _hidden = 0;

  int get hidden => _hidden;

  void _bump() => _hidden++;

  void inc() {
    _bump();
    amount = amount + 1;
  }

  // A setter that is no field: one change, like a method.
  set both(int value) {
    amount = value;
    thing = value;
  }

  T pick<T extends Object>(T first, {T? second, int times = 1}) =>
      second ?? first;

  int operator +(int other) => amount.toInt() + other;

  int call() => amount.toInt();

  @override
  String toString() => 'Shapes($amount)';
}

@Component()
class Steps {
  @Signal()
  int a = 0;

  @Signal()
  int b = 0;

  final List<String> seen = [];

  @Effect()
  void watch() => seen.add('$a/$b');

  Future<void> later() async {
    a = 1;
    b = 1;
    await Future<void>.delayed(Duration.zero);
    a = 2;
    b = 2;
  }

  void fail() {
    a = 7;
    b = 7;
    throw StateError('after the assignments');
  }
}

@Component()
class Clamped {
  @Signal()
  int level = 0;

  int runs = 0;

  // Writes what it reads, until it holds.
  @Effect()
  void clamp() {
    runs++;
    if (level > 10) {
      level = 10;
    }
  }
}

@Component()
class Fragile {
  @Signal()
  int value = 0;

  @Effect()
  void check() {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'negative');
    }
  }
}

@Component()
class Looping {
  @Signal()
  int seed = 0;

  @Computed()
  int get first => seed == 0 ? 0 : second + 1;

  @Computed()
  int get second => first + 1;
}

class Ping extends ApplicationEvent {
  Ping(super.source);
}

@Service()
class Listening {
  @Signal()
  int heard = 0;

  @EventListener()
  void on(Ping ping) => heard++;
}

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const SizedBox(),
  ),
);

/// Marks a member another advice wraps, as `@Transactional` would.
class Audited {
  const Audited();
}

/// Stands for an advice of another starter (a transaction): it notes
/// where the call began and how it ended.
@Aspect()
@Component()
class Audit {
  final List<String> log = [];

  @Around('@annotation(Audited)')
  Object? around(ProceedingJoinPoint joinPoint) {
    final name = joinPoint.signature.name;
    log.add('begin $name');
    try {
      final result = joinPoint.proceed();
      if (result is Future) {
        return result.whenComplete(() => log.add('commit $name'));
      }
      log.add('commit $name');
      return result;
    } on Object {
      log.add('rollback $name');
      rethrow;
    }
  }
}

/// Marks a member only the owner may read, as `@PreAuthorize` would.
class OwnerOnly {
  const OwnerOnly();
}

/// Stands for method security: an advice with an earlier order than the
/// one that follows state, which refuses the call unless [owner] is set.
@Aspect()
@Order(Ordered.highestPrecedence + 100)
@Component()
class Guard {
  bool owner = true;
  int checks = 0;

  @Around('@annotation(OwnerOnly)')
  Object? check(ProceedingJoinPoint joinPoint) {
    checks++;
    if (!owner) {
      throw StateError('denied');
    }
    return joinPoint.proceed();
  }
}

@Component()
class Ledger {
  @Signal()
  int balance = 0;

  @Signal()
  int version = 0;

  final List<String> seen = [];

  @Effect()
  void watch() => seen.add('$balance/$version');

  @Audited()
  void deposit(int amount) {
    balance += amount;
    version++;
  }

  // Its own calls skip the other advice, as in any bean.
  void depositTwice(int amount) {
    deposit(amount);
    deposit(amount);
  }

  @Audited()
  void failing() {
    balance = 100;
    throw StateError('declined');
  }

  @Audited()
  Future<void> transfer(int amount) async {
    balance -= amount;
    await Future<void>.delayed(Duration.zero);
    version++;
  }

  @Audited()
  @Computed()
  Future<int> get doubled async => balance * 2;

  int totals = 0;

  @OwnerOnly()
  @Computed()
  int get total {
    totals++;
    return balance + version;
  }
}

/// A plain field under a value only the owner may read.
@Component()
class Vault {
  @Signal()
  int secret = 0;

  @OwnerOnly()
  @Computed()
  int get report => secret * 2;

  // Not guarded itself, made from the guarded one.
  @Computed()
  int get summary => report + 1;
}

/// An effect only the owner may run.
@Component()
class Watchman {
  @Signal()
  int door = 0;

  final List<int> noted = [];

  @OwnerOnly()
  @Effect()
  void note() => noted.add(door);
}

/// Another bean that reads the guarded value of [Vault]: a call from
/// outside, so the guard runs for whoever makes the change.
@Component()
class Reader {
  Reader(this.vault);

  final Vault vault;
  final List<int> seen = [];

  @Computed()
  int get view => vault.report + 1;

  @Effect()
  void watch() => seen.add(vault.report);
}
