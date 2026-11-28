// ResilienceAutoConfiguration: the advisors of @Retryable and
// @ConcurrencyLimit at their orders, the events and the listener beans,
// and @Observed around the retries: one observation for the whole call.
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

const _quick = Duration(milliseconds: 1);

class Catalog {
  int calls = 0;

  @Observed(name: 'catalog.load')
  @Retryable(delay: _quick)
  Future<int> load() async {
    calls++;
    if (calls < 3) {
      throw StateErrorLike(calls);
    }
    return calls;
  }
}

final class StateErrorLike implements Exception {
  StateErrorLike(this.attempt);

  final int attempt;
}

const _target = AopTarget('Catalog', types: ['Catalog']);

final _proxies = AopProxyFactory(
  signatures: const [
    MethodSignature.of(
      'load',
      _target,
      returnType: 'Future',
      annotations: [
        Observed(name: 'catalog.load'),
        Retryable(delay: _quick),
      ],
      annotationTypes: ['Observed', 'Retryable'],
    ),
  ],
  create: (target, invoker) => _$CatalogProxy(target as Catalog, invoker),
);

class _$CatalogProxy with AdvisedWrapper implements Catalog {
  _$CatalogProxy(this._target, this.aopInvoker);

  final Catalog _target;

  @override
  final ProxyInvoker aopInvoker;

  @override
  Object get aopTarget => _target;

  @override
  int get calls => _target.calls;

  @override
  set calls(int value) => _target.calls = value;

  @override
  Future<int> load() => this.aopInvoker.invokeAsync<int>(
    proxy: this,
    target: this._target,
    methodIndex: 0,
    arguments: const [],
    original: (args) => this._target.load(),
  );
}

final class _Stopped extends ObservationHandler {
  final names = <String>[];

  @override
  void onStop(ObservationContext context) => names.add(context.name);
}

final class _Retries extends RetryListener {
  final names = <String>[];

  @override
  void beforeRetry(RetryPolicy retryPolicy, String name) => names.add(name);
}

void main() {
  late _Stopped stopped;
  late _Retries retries;

  ConfigurableApplicationContext run({bool resilience = true}) {
    stopped = _Stopped();
    retries = _Retries();
    return SpringApplication(
      [
        BeanModule('app', [
          BeanDefinition<Catalog>(
            name: 'catalog',
            create: (_) => Catalog(),
            aopProxy: _proxies,
          ),
          BeanDefinition<_Stopped>(
            name: 'stopped',
            types: const [_Stopped, ObservationHandler],
            create: (_) => stopped,
          ),
          BeanDefinition<_Retries>(
            name: 'retries',
            types: const [_Retries, RetryListener],
            create: (_) => retries,
          ),
        ]),
      ],
      autoConfigurations: [
        springBootAutoConfiguration,
        springBootObservedAnnotationsAutoConfiguration,
        if (resilience) springBootResilienceAutoConfiguration,
      ],
      out: (_) {},
    ).run(const [], systemEnvironment: const {});
  }

  test('the advisors, at their orders', () {
    final context = run();
    addTearDown(context.close);
    final concurrency = context.getBean<DefaultPointcutAdvisor>(
      qualifier: 'concurrencyLimitAdvisor',
    );
    final retry = context.getBean<DefaultPointcutAdvisor>(
      qualifier: 'retryAdvisor',
    );
    final observed = context.getBean<DefaultPointcutAdvisor>(
      qualifier: 'observedAdvisor',
    );
    expect(concurrency.pointcut, isA<ConcurrencyLimitPointcut>());
    expect(concurrency.order, AdvisorOrder.concurrencyLimit);
    expect(retry.pointcut, isA<RetryablePointcut>());
    expect(retry.order, AdvisorOrder.retry);
    expect(observed.order, AdvisorOrder.observation);
    final catalog = context.getBean<Catalog>() as Advised;
    expect(catalog.aopAdvisors, [observed, retry]);
  });

  test('@Observed counts one call however many attempts; the listener '
      'beans and the events are told', () async {
    final context = run();
    addTearDown(context.close);
    final events = <MethodRetryEvent>[];
    context.addApplicationListener(
      ApplicationListenerAdapter.of<MethodRetryEvent>(events.add),
    );
    final catalog = context.getBean<Catalog>();
    expect(await catalog.load(), 3);
    expect(catalog.calls, 3);
    expect(stopped.names, ['catalog.load']);
    expect(retries.names, ['Catalog.load', 'Catalog.load']);
    expect([for (final e in events) e.retryAborted], [false, false]);
  });

  test('without the module, nothing is retried', () async {
    final context = run(resilience: false);
    addTearDown(context.close);
    expect(context.containsBean('retryAdvisor'), isFalse);
    await expectLater(
      context.getBean<Catalog>().load(),
      throwsA(isA<StateErrorLike>()),
    );
  });
}
