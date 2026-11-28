// A @Scheduled method that is @Retryable: the scheduler calls the bean
// through its proxy, so a failed run is retried before the next one, and
// the next run is scheduled after the retried one ends (fixed delay).
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
import 'dart:async';

import 'package:spring_boot_starter_scheduling/spring_auto_configuration.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:test/test.dart';

import 'fake_clock.dart';

class Feeds {
  final calls = <int>[];

  @Scheduled(fixedDelay: Duration(seconds: 10))
  @Retryable(delay: Duration.zero)
  Future<void> pull() async {
    calls.add(calls.length + 1);
    if (calls.length.isOdd) {
      throw TimeoutException('slow');
    }
  }
}

const _target = AopTarget('Feeds', types: ['Feeds']);

final _proxies = AopProxyFactory(
  signatures: const [
    MethodSignature.of(
      'pull',
      _target,
      returnType: 'Future',
      annotations: [
        Scheduled(fixedDelay: Duration(seconds: 10)),
        Retryable(delay: Duration.zero),
      ],
      annotationTypes: ['Scheduled', 'Retryable'],
    ),
  ],
  create: (target, invoker) => _$FeedsProxy(target as Feeds, invoker),
);

class _$FeedsProxy implements Feeds {
  _$FeedsProxy(this._target, this._invoker);

  final Feeds _target;
  final ProxyInvoker _invoker;

  @override
  List<int> get calls => _target.calls;

  @override
  Future<void> pull() => this._invoker.invokeAsync<void>(
    proxy: this,
    target: this._target,
    methodIndex: 0,
    arguments: const [],
    original: (args) => this._target.pull(),
  );
}

void main() {
  test('each scheduled run is retried through the proxy', () async {
    final clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
    final scheduler = TimerTaskScheduler(
      now: clock.now,
      createTimer: clock.timer,
    );
    final feeds = Feeds();
    final context = AnnotationConfigApplicationContext(
      [
        BeanModule('app', [
          BeanDefinition<TaskScheduler>(
            name: 'taskScheduler',
            create: (_) => scheduler,
          ),
          BeanDefinition<Feeds>(
            name: 'feeds',
            create: (_) => feeds,
            aopProxy: _proxies,
            annotatedMethods: [
              IntrospectedMethod<Feeds>(
                'pull',
                invoke: (bean, arguments) => bean.pull(),
                annotations: const [
                  Scheduled(fixedDelay: Duration(seconds: 10)),
                ],
              ),
            ],
          ),
        ]),
        springBootResilienceAutoConfiguration,
        springBootStarterSchedulingAutoConfiguration,
      ],
      environment: StandardEnvironment(systemEnvironment: const {}),
    )..refresh();
    addTearDown(context.close);
    await clock.elapseAsync(const Duration(seconds: 15));
    expect(feeds.calls, [1, 2, 3, 4]);
  });
}
