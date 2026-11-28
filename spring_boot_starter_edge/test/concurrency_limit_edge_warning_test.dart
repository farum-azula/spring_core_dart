// A bean with @ConcurrencyLimit is named among what works differently in
// a function: the limit counts the calls of one instance.
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
import 'package:spring_boot_starter_edge/spring_auto_configuration.dart';
import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:test/test.dart';

class Reports {
  @ConcurrencyLimit(2)
  Future<int> make() async => 1;
}

class Plain {
  Future<int> make() async => 1;
}

const _target = AopTarget('Reports', types: ['Reports']);

final _proxies = AopProxyFactory(
  signatures: const [
    MethodSignature.of(
      'make',
      _target,
      returnType: 'Future',
      annotations: [ConcurrencyLimit(2)],
      annotationTypes: ['ConcurrencyLimit'],
    ),
  ],
  create: (target, invoker) => _$ReportsProxy(target as Reports, invoker),
);

class _$ReportsProxy with AdvisedWrapper implements Reports {
  _$ReportsProxy(this._target, this.aopInvoker);

  final Reports _target;

  @override
  final ProxyInvoker aopInvoker;

  @override
  Object get aopTarget => _target;

  @override
  Future<int> make() => this.aopInvoker.invokeAsync<int>(
    proxy: this,
    target: this._target,
    methodIndex: 0,
    arguments: const [],
    original: (args) => this._target.make(),
  );
}

void main() {
  test('each bean with a limit has its line', () {
    final context = AnnotationConfigApplicationContext(
      [
        BeanModule('app', [
          BeanDefinition<Reports>(
            name: 'reports',
            create: (_) => Reports(),
            aopProxy: _proxies,
          ),
          BeanDefinition<Plain>(name: 'plain', create: (_) => Plain()),
        ]),
        springBootResilienceAutoConfiguration,
      ],
      environment: StandardEnvironment(systemEnvironment: const {}),
    )..refresh();
    addTearDown(context.close);
    final lines = ConcurrencyLimitEdgeWarning(
      context.beanFactory,
    ).warnings(context).toList();
    expect(lines, [
      allOf(
        startsWith("@ConcurrencyLimit (bean 'reports')"),
        contains('short-lived instance'),
      ),
    ]);
  });
}
