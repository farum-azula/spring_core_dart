// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

const _pointcut =
    '@annotation(Observed) || (@within(Observed) && execution(* *(..)))';

abstract interface class Orders {
  Future<String> place(String item);
  int count();
  String get label;
}

@Observed(lowCardinalityKeyValues: ['layer', 'service'])
class DefaultOrders implements Orders {
  DefaultOrders(this.registry);

  final ObservationRegistry registry;
  int placed = 0;

  @Observed(name: 'orders.place', contextualName: 'place order')
  @override
  Future<String> place(String item) async {
    await Future<void>.delayed(Duration.zero);
    if (item.isEmpty) {
      throw ArgumentError('no item');
    }
    placed++;
    return await registry.observe('orders.inner', () async => 'placed $item');
  }

  @override
  int count() => placed;

  @override
  String get label => 'orders';
}

// ---- what the generator writes ----

const _target = AopTarget(
  'DefaultOrders',
  types: ['DefaultOrders', 'Orders'],
  annotations: [
    Observed(lowCardinalityKeyValues: ['layer', 'service']),
  ],
  annotationTypes: ['Observed'],
);

const _signatures = [
  MethodSignature.of(
    'place',
    _target,
    returnType: 'Future<String>',
    parameterTypes: ['String'],
    parameterNames: ['item'],
    annotations: [
      Observed(name: 'orders.place', contextualName: 'place order'),
      override,
    ],
    annotationTypes: ['Observed', 'override'],
  ),
  MethodSignature.of(
    'count',
    _target,
    returnType: 'int',
    annotations: [override],
    annotationTypes: ['override'],
  ),
  MethodSignature.of(
    'label',
    _target,
    kind: MemberKind.getter,
    returnType: 'String',
    annotations: [override],
    annotationTypes: ['override'],
  ),
];

class _$OrdersProxy implements Orders {
  _$OrdersProxy(this._target, this._invoker);

  final DefaultOrders _target;
  final ProxyInvoker _invoker;

  @override
  Future<String> place(String item) =>
      this._invoker.invoke(this, this._target, 0, [
            item,
          ], (args) => this._target.place(args[0]! as String))!
          as Future<String>;

  @override
  int count() =>
      this._invoker.invoke(
            this,
            this._target,
            1,
            const [],
            (args) => this._target.count(),
          )!
          as int;

  @override
  String get label =>
      this._invoker.invoke(
            this,
            this._target,
            2,
            const [],
            (args) => this._target.label,
          )!
          as String;
}

final _proxies = AopProxyFactory(
  signatures: _signatures,
  create: (target, invoker) => _$OrdersProxy(target as DefaultOrders, invoker),
);

final _metadata = AspectMetadata<ObservedAspect>(
  typeName: 'ObservedAspect',
  advice: [
    AspectAdvice<ObservedAspect>(
      kind: AdviceKind.around,
      pointcut: _pointcut,
      methodName: 'observe',
      invoke: (aspect, joinPoint, _, _) =>
          aspect.observe(joinPoint as ProceedingJoinPoint),
    ),
  ],
);

// ----

class Stopped extends ObservationHandler {
  final contexts = <ObservationContext>[];

  @override
  void onStop(ObservationContext context) => contexts.add(context);
}

void main() {
  late Stopped stopped;
  late ObservationRegistry registry;
  late Orders orders;

  Orders proxy(ObservationRegistry registry) {
    final factory = AspectJProxyFactory(DefaultOrders(registry), _proxies)
      ..addAspect(ObservedAspect(registry), _metadata);
    return factory.getProxy() as Orders;
  }

  setUp(() {
    stopped = Stopped();
    registry = ObservationRegistry(handlers: [stopped]);
    orders = proxy(registry);
  });

  test('the pointcut matches observed methods, not getters', () {
    final pointcut = ExpressionPointcut(_pointcut);
    expect(
      [
        for (final signature in _signatures)
          pointcut.matches(signature, 'orders'),
      ],
      [true, true, false],
    );
    expect(ObservedAspect.annotationTypes, [Observed]);
  });

  test('a method of an @Observed class: default name and tags', () {
    orders.count();
    final context = stopped.contexts.single;
    expect(context.name, ObservedAspect.defaultName);
    expect(context.contextualName, 'DefaultOrders#count');
    expect(context.lowCardinalityKeyValues, {
      'class': 'DefaultOrders',
      'method': 'count',
      'layer': 'service',
    });
  });

  test('a getter is not observed', () {
    expect(orders.label, 'orders');
    expect(stopped.contexts, isEmpty);
  });

  test("the method's @Observed wins; a Future stops when done", () async {
    expect(await orders.place('book'), 'placed book');
    final [inner, outer] = stopped.contexts;
    expect(outer.name, 'orders.place');
    expect(outer.contextualName, 'place order');
    expect(outer.lowCardinalityKeyValues, {
      'class': 'DefaultOrders',
      'method': 'place',
    });
    expect(inner.name, 'orders.inner');
    expect(inner.parent, same(outer));
  });

  test('an error of an async method is recorded and passed on', () async {
    await expectLater(orders.place(''), throwsArgumentError);
    expect(stopped.contexts.single.error, isA<ArgumentError>());
  });

  test('with the noop registry the call runs unobserved', () async {
    final unobserved = proxy(ObservationRegistry.noop);
    expect(await unobserved.place('pen'), 'placed pen');
    expect(unobserved.count(), 1);
    expect(stopped.contexts, isEmpty);
  });
}
