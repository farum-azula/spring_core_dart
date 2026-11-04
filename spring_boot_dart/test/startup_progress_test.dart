import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class Plain {}

class Waiter implements ApplicationRunner {
  @override
  Future<void> run(ApplicationArguments args) =>
      Future<void>.delayed(const Duration(milliseconds: 5));
}

SpringApplication app() => SpringApplication([
  BeanModule('test', [
    for (var i = 0; i < 4; i++)
      BeanDefinition<Plain>(name: 'plain$i', create: (_) => Plain()),
    BeanDefinition<Waiter>(
      name: 'waiter',
      types: const [Waiter, ApplicationRunner],
      create: (_) => Waiter(),
    ),
  ]),
], bannerMode: BannerMode.off);

void main() {
  for (final async in [true, false]) {
    test(
      'progress goes up to the end (${async ? 'runAsync' : 'run'})',
      () async {
        final seen = <StartupProgress>[];
        final application = app()..progressListener = seen.add;
        final context = async
            ? await application.runAsync(const [], systemEnvironment: const {})
            : application.run(const [], systemEnvironment: const {});
        addTearDown(context.close);
        if (!async) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(seen.length, greaterThan(5));
        // Never back, never complete before the end.
        for (var i = 1; i < seen.length; i++) {
          expect(seen[i].fraction, greaterThanOrEqualTo(seen[i - 1].fraction));
        }
        expect(seen.where((p) => p.fraction >= 1), hasLength(1));
        expect(seen.last.fraction, 1);
        expect(seen.last.done, seen.last.total);
        // The runner is a step: the beans alone are not the end.
        expect(seen[seen.length - 2].fraction, lessThan(1));
      },
    );
  }

  test('without a listener nothing is tracked', () async {
    final context = await app().runAsync(
      const [],
      systemEnvironment: const {},
    );
    addTearDown(context.close);
    expect(context.isActive, isTrue);
  });
}
