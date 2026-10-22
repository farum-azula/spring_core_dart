import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class Greeter {
  Greeter(this.text);
  final String text;
}

class Counter {
  int value = 0;
}

/// "On startup" work: counts how often it ran, across contexts.
class StartupTask implements CommandLineRunner {
  static int runs = 0;

  @override
  void run(List<String> args) => runs++;
}

/// What the generated `springApplication` getter returns before and after a
/// hot reload that changed the beans.
SpringApplication app(String fingerprint, {String greeting = 'hello'}) =>
    SpringApplication(
      [
        BeanModule('application', [
          BeanDefinition<Counter>(name: 'counter', create: (_) => Counter()),
          BeanDefinition<StartupTask>(
            name: 'startupTask',
            types: const [StartupTask, CommandLineRunner],
            create: (_) => StartupTask(),
          ),
          BeanDefinition<Greeter>(
            name: 'greeter',
            create: (r) =>
                Greeter('$greeting ${r.value<String>(r'${name:nobody}')}'),
          ),
        ]),
      ],
      fingerprint: fingerprint,
      out: (_) {},
    );

void main() {
  test('unchanged code keeps the running context and its state', () {
    final context = app('v1').run(const [], systemEnvironment: const {});
    addTearDown(context.close);
    context.getBean<Counter>().value = 5;

    final reloaded = app('v1').reload(context);
    expect(reloaded, same(context));
    expect(reloaded.getBean<Counter>().value, 5);
  });

  test('changed code restarts with the new beans and the same arguments', () {
    final context = app('v1').run(['--name=Ada'], systemEnvironment: const {});
    expect(context.getBean<Greeter>().text, 'hello Ada');

    final reloaded = app('v2', greeting: 'hi').reload(context);
    addTearDown(reloaded.close);
    expect(reloaded, isNot(same(context)));
    expect(context.isActive, isFalse);
    expect(reloaded.getBean<Greeter>().text, 'hi Ada');
    expect(reloaded.getBean<Counter>().value, 0); // beans are new
  });

  test('without a fingerprint every reload restarts', () {
    final first = SpringApplication([
      BeanModule('m', []),
    ], out: (_) {}).run(const [], systemEnvironment: const {});
    final second = SpringApplication([
      BeanModule('m', []),
    ], out: (_) {}).reload(first);
    addTearDown(second.close);
    expect(second, isNot(same(first)));
    expect(first.isActive, isFalse);
  });

  test('a closed context is started again; reloadAsync', () async {
    final context = app('v1').run(const [], systemEnvironment: const {});
    context.close();
    final restarted = await app('v1').reloadAsync(context);
    addTearDown(restarted.close);
    expect(restarted.isActive, isTrue);
    expect(restarted, isNot(same(context)));
    expect(await app('v1').reloadAsync(restarted), same(restarted));
  });

  group('runners after a restart', () {
    setUp(() => StartupTask.runs = 0);

    test('run again by default, like Spring Boot DevTools', () {
      final context = app('v1').run(const [], systemEnvironment: const {});
      expect(StartupTask.runs, 1);
      final reloaded = app('v2').reload(context);
      addTearDown(reloaded.close);
      expect(StartupTask.runs, 2);
    });

    test('runners: false skips them; the beans are still new', () async {
      final context = app('v1').run(const [], systemEnvironment: const {});
      context.getBean<Counter>().value = 3;
      final reloaded = app('v2').reload(context, runners: false);
      expect(StartupTask.runs, 1);
      expect(reloaded.getBean<Counter>().value, 0);
      final again = await app('v3').reloadAsync(reloaded, runners: false);
      addTearDown(again.close);
      expect(StartupTask.runs, 1);
    });

    test('an unchanged reload never runs them', () {
      final context = app('v1').run(const [], systemEnvironment: const {});
      addTearDown(context.close);
      app('v1').reload(context);
      expect(StartupTask.runs, 1);
    });
  });
}
