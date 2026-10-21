// A small hand-written application for the starter's own tests.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

abstract interface class Greeter {
  String greet(String name);
}

class RealGreeter implements Greeter {
  RealGreeter(this.prefix) {
    created++;
  }

  static int created = 0;
  final String prefix;

  @override
  String greet(String name) => '$prefix, $name';
}

class FakeGreeter implements Greeter {
  @override
  String greet(String name) => 'fake $name';
}

abstract interface class Mailer {
  String get kind;
}

class SmtpMailer implements Mailer {
  @override
  String get kind => 'smtp';
}

class SesMailer implements Mailer {
  @override
  String get kind => 'ses';
}

class FakeMailer implements Mailer {
  @override
  String get kind => 'fake';
}

class Counter {
  int value = 0;
}

class Notifier {
  Notifier(this.greeter, this.mailer);

  final Greeter greeter;
  final Mailer mailer;

  String notify(String name) => '${mailer.kind}: ${greeter.greet(name)}';
}

const _log = SpringLog('test.app');

BeanModule appModule() => BeanModule('app', [
  BeanDefinition<RealGreeter>(
    name: 'greeter',
    types: const [RealGreeter, Greeter],
    create: (r) {
      _log.info('creating greeter');
      return RealGreeter(r.value<String>(r'${greeting.prefix:Hello}'));
    },
  ),
  BeanDefinition<SmtpMailer>(
    name: 'smtpMailer',
    types: const [SmtpMailer, Mailer],
    qualifiers: const {'primaryMail'},
    create: (_) => SmtpMailer(),
  ),
  BeanDefinition<SesMailer>(
    name: 'sesMailer',
    types: const [SesMailer, Mailer],
    create: (_) => SesMailer(),
  ),
  BeanDefinition<Counter>(name: 'counter', create: (_) => Counter()),
  BeanDefinition<Notifier>(
    name: 'notifier',
    create: (r) => Notifier(
      r.dependency<Greeter>(),
      r.dependency<Mailer>(qualifier: 'primaryMail'),
    ),
  ),
]);

/// A starter-like module: a default greeter unless the app has one.
final greeterAutoConfiguration = BeanModule('greeterAuto', [
  BeanDefinition<RealGreeter>(
    name: 'defaultGreeter',
    types: const [RealGreeter, Greeter],
    conditions: const [
      ConditionalOnMissingBean(Greeter),
      ConditionalOnProperty('greeter.enabled', matchIfMissing: true),
    ],
    create: (r) => RealGreeter(r.value<String>(r'${greeting.prefix:Hi}')),
  ),
]);

final failingModule = BeanModule('failing', [
  BeanDefinition<Counter>(
    name: 'broken',
    create: (_) => throw StateError('cannot start'),
  ),
]);
