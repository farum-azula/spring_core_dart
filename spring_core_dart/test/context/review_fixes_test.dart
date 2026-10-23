import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

abstract interface class Notifier {
  String send();
}

class Email implements Notifier {
  @override
  String send() => 'email';
}

class Sms implements Notifier {
  @override
  String send() => 'sms';
}

class Composite implements Notifier {
  Composite(this.all);
  final List<Notifier> all;
  @override
  String send() => all.map((n) => n.send()).join(',');
}

class Logging implements Notifier {
  Logging(this.delegate);
  final Notifier delegate;
  @override
  String send() => 'log(${delegate.send()})';
}

class Marker {}

class Worker with SmartLifecycle {
  Worker(this.name, this.log, {this.failOnStop = false});
  final String name;
  final List<String> log;
  final bool failOnStop;
  @override
  bool isRunning = false;
  @override
  int get phase => 0;
  @override
  bool get isAutoStartup => true;
  @override
  void start() => isRunning = true;
  @override
  void stop() {
    if (failOnStop) {
      throw StateError('$name cannot stop');
    }
    isRunning = false;
    log.add('$name:stop');
  }
}

AnnotationConfigApplicationContext ctx(
  List<BeanDefinition<Object>> defs, {
  ApplicationContext? parent,
  Map<String, Object?> properties = const {},
  List<PropertySourceDeclaration> propertySources = const [],
}) => AnnotationConfigApplicationContext(
  [BeanModule('m', defs, propertySources: propertySources)],
  environment: StandardEnvironment(systemEnvironment: {})
    ..propertySources.addFirst(MapPropertySource('test', properties)),
  parent: parent,
);

BeanDefinition<Email> email() => BeanDefinition<Email>(
  name: 'email',
  types: const [Email, Notifier],
  create: (_) => Email(),
);

BeanDefinition<Sms> sms() => BeanDefinition<Sms>(
  name: 'sms',
  types: const [Sms, Notifier],
  create: (_) => Sms(),
);

void main() {
  late SpringLogHandler savedHandler;
  final logged = <SpringLogRecord>[];
  setUp(() {
    savedHandler = SpringLog.handler;
    logged.clear();
    SpringLog.handler = logged.add;
  });
  tearDown(() => SpringLog.handler = savedHandler);

  group('a bean is not injected into itself (Spring isSelfReference)', () {
    test('composite gets the other beans of its type', () {
      final c = ctx([
        email(),
        sms(),
        BeanDefinition<Composite>(
          name: 'composite',
          types: const [Composite, Notifier],
          primary: true,
          dependencies: const [Dependency.collection(Notifier)],
          create: (r) => Composite(r.dependencyList<Notifier>()),
        ),
      ])..refresh();
      expect(c.getBean<Notifier>().send(), 'email,sms');
    });

    test('decorator gets the decorated bean', () {
      final c = ctx([
        email(),
        BeanDefinition<Logging>(
          name: 'logging',
          types: const [Logging, Notifier],
          primary: true,
          dependencies: const [Dependency(Notifier, name: 'delegate')],
          create: (r) => Logging(r.dependency<Notifier>(name: 'delegate')),
        ),
      ])..refresh();
      expect(c.getBean<Notifier>().send(), 'log(email)');
    });

    test('a bean depending only on itself is still a cycle', () {
      final c = ctx([
        BeanDefinition<Logging>(
          name: 'logging',
          types: const [Logging, Notifier],
          dependencies: const [Dependency(Notifier)],
          create: (r) => Logging(r.dependency<Notifier>()),
        ),
      ]);
      expect(c.refresh, throwsA(isA<BeanCurrentlyInCreationException>()));
    });
  });

  test('events published during refresh reach the parent once', () {
    final parent = ctx([])..refresh();
    final seen = <Object>[];
    parent.addListener<String>(seen.add);
    final child = ctx([
      BeanDefinition<Marker>(
        name: 'publisher',
        create: (r) {
          r.dependency<ApplicationEventPublisher>().publishEvent('hello');
          return Marker();
        },
      ),
    ], parent: parent);
    final childSeen = <Object>[];
    child
      ..addListener<String>(childSeen.add)
      ..refresh();
    expect(seen, ['hello']);
    expect(childSeen, ['hello']);
  });

  group('close() is exception-safe (Spring doClose)', () {
    test('a failing ContextClosedEvent listener does not stop shutdown', () {
      final log = <String>[];
      final c = ctx([
        BeanDefinition<Worker>(
          name: 'worker',
          types: const [Worker, SmartLifecycle, Lifecycle],
          create: (_) => Worker('worker', log),
        ),
      ])..refresh();
      c.addListener<ContextClosedEvent>((_) => throw StateError('listener'));
      c.close();
      expect(log, ['worker:stop']);
      expect(c.isClosed, isTrue);
      expect(logged.single.message, contains('ContextClosedEvent'));
    });

    test('a bean that fails to stop does not keep the others running', () {
      final log = <String>[];
      final c = ctx([
        BeanDefinition<Worker>(
          name: 'a',
          types: const [Worker, SmartLifecycle, Lifecycle],
          create: (_) => Worker('a', log),
        ),
        BeanDefinition<Worker>(
          name: 'b',
          types: const [Worker, SmartLifecycle, Lifecycle],
          create: (_) => Worker('b', log, failOnStop: true),
        ),
      ])..refresh();
      c.close();
      expect(log, ['a:stop']);
      expect(logged.single.message, contains('Failed to stop'));
    });

    test('close() from a ContextClosedEvent listener is a no-op', () {
      final c = ctx([])..refresh();
      var events = 0;
      c.addListener<ContextClosedEvent>((_) {
        events++;
        c.close();
      });
      c.close();
      expect(events, 1);
      expect(c.isClosed, isTrue);
    });
  });

  test('@PropertySource of a class whose conditions fail is not loaded', () {
    final c = ctx(
      [],
      propertySources: const [
        PropertySourceDeclaration(
          ['file:/definitely/missing/prod.properties'],
          conditions: [
            ProfileCondition(['prod']),
          ],
        ),
      ],
    )..refresh();
    expect(c.isActive, isTrue);
  });
}
