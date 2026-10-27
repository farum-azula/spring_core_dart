// The hand-written proxies use `this.` like generated code does.
// ignore_for_file: unnecessary_this

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Audited {
  const Audited();
}

class Marker {
  const Marker();
}

abstract interface class Orders {
  String place(Object item);
  int count();
  void audit();
}

@Audited()
abstract class BaseOrders implements Orders {
  int placed = 0;

  // Inherited by DefaultOrders, not overridden.
  @override
  int count() => placed;
}

@Marker()
class DefaultOrders extends BaseOrders {
  @override
  String place(Object item) {
    placed++;
    return 'placed $item';
  }

  // `@protected` in real code (package:meta).
  @override
  void audit() {}
}

@Audited()
class AuditedItem {
  const AuditedItem();
}

abstract interface class UsageTracked {
  int get uses;
  void use();
}

class DefaultUsageTracked implements UsageTracked {
  @override
  int uses = 0;

  @override
  void use() => uses++;
}

// ---- what the generator writes ----

const _types = ['DefaultOrders', 'BaseOrders', 'Orders'];

const orderSignatures = [
  MethodSignature(
    name: 'place',
    declaringType: 'Orders',
    targetType: 'DefaultOrders',
    returnType: 'String',
    parameterTypes: ['Object'],
    parameterNames: ['item'],
    targetTypes: _types,
    targetAnnotations: [Marker()],
    targetAnnotationTypes: ['Marker'],
  ),
  MethodSignature(
    name: 'count',
    declaringType: 'Orders',
    targetType: 'DefaultOrders',
    returnType: 'int',
    targetTypes: _types,
    targetAnnotations: [Marker()],
    targetAnnotationTypes: ['Marker'],
    implementingTypes: ['BaseOrders', 'Orders'],
    implementingTypeAnnotations: [Audited()],
    implementingTypeAnnotationTypes: ['Audited'],
  ),
  MethodSignature(
    name: 'audit',
    declaringType: 'Orders',
    targetType: 'DefaultOrders',
    returnType: 'void',
    targetTypes: _types,
    targetAnnotations: [Marker()],
    targetAnnotationTypes: ['Marker'],
    isProtected: true,
  ),
];

class _$OrdersProxy implements Orders, UsageTracked, Advised {
  _$OrdersProxy(this._target, this._invoker);

  final DefaultOrders _target;
  final ProxyInvoker _invoker;

  @override
  Object get aopTarget => this._target;

  @override
  List<PointcutAdvisor> get aopAdvisors => this._invoker.advisors;

  @override
  void addAdvisor(PointcutAdvisor advisor) => this._invoker.addAdvisor(advisor);

  @override
  bool removeAdvisor(PointcutAdvisor advisor) =>
      this._invoker.removeAdvisor(advisor);

  @override
  void addAdvice(MethodInterceptor advice) => this._invoker.addAdvice(advice);

  @override
  bool removeAdvice(MethodInterceptor advice) =>
      this._invoker.removeAdvice(advice);

  @override
  String place(Object item) =>
      this._invoker.invoke(this, this._target, 0, [
            item,
          ], (args) => this._target.place(args[0]!))!
          as String;

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
  void audit() {
    this._invoker.invoke(this, this._target, 2, const [], (args) {
      this._target.audit();
      return null;
    });
  }

  // `@DeclareParents`: forwarded to the introduction, not advised.
  @override
  int get uses => (this._invoker.introduction(0) as UsageTracked).uses;

  @override
  void use() => (this._invoker.introduction(0) as UsageTracked).use();
}

AopProxyFactory ordersFactory({bool introduce = false}) => AopProxyFactory(
  signatures: orderSignatures,
  create: (target, invoker) => _$OrdersProxy(target as DefaultOrders, invoker),
  introductions: [
    if (introduce)
      Introduction(
        interfaceName: 'UsageTracked',
        aspectType: 'UsageTracking',
        create: DefaultUsageTracked.new,
      ),
  ],
);

class Counter {
  int count = 0;
  int next() => ++count;
}

// A subclass proxy: no invoker until advice is attached.
class _$CounterProxy extends Counter implements Advised {
  ProxyInvoker? _$invoker;

  @override
  Object get aopTarget => this;

  @override
  List<PointcutAdvisor> get aopAdvisors => this._$invoker?.advisors ?? const [];

  @override
  void addAdvisor(PointcutAdvisor advisor) =>
      (this._$invoker ?? ProxyInvoker.notAdvised(this)).addAdvisor(advisor);

  @override
  bool removeAdvisor(PointcutAdvisor advisor) =>
      (this._$invoker ?? ProxyInvoker.notAdvised(this)).removeAdvisor(advisor);

  @override
  void addAdvice(MethodInterceptor advice) =>
      (this._$invoker ?? ProxyInvoker.notAdvised(this)).addAdvice(advice);

  @override
  bool removeAdvice(MethodInterceptor advice) =>
      (this._$invoker ?? ProxyInvoker.notAdvised(this)).removeAdvice(advice);
}

// ---- end generated ----

final log = <String>[];

class _Tag implements MethodInterceptor {
  _Tag(this.tag);
  final String tag;

  @override
  Object? invoke(MethodInvocation invocation) {
    log.add('$tag ${invocation.signature.name}');
    return invocation.proceed();
  }
}

AdviceBinding binding<T>(String typeName) =>
    AdviceBinding(typeName, (value) => value is T);

PointcutAdvisor before(
  String pointcut, {
  Map<String, AdviceBinding> bindings = const {},
  Map<String, bool Function(Object?)> typeTests = const {},
  Map<String, Object? Function(Object?)> argumentAnnotations = const {},
  void Function(JoinPoint joinPoint, Map<String, Object?> bound)? body,
}) => DefaultPointcutAdvisor(
  ExpressionPointcut(
    pointcut,
    bindings: bindings,
    typeTests: typeTests,
    argumentAnnotations: argumentAnnotations,
  ),
  AspectAdviceInterceptor(
    AspectAdvice<Object>(
      kind: AdviceKind.before,
      pointcut: pointcut,
      methodName: 'before',
      invoke: (_, joinPoint, _, bound) {
        if (body != null) {
          body(joinPoint, bound);
        } else {
          log.add('before ${joinPoint.signature.name}');
        }
        return null;
      },
      bindings: bindings,
    ),
    Object.new,
  ),
);

Orders proxy(List<PointcutAdvisor> advisors, {DefaultOrders? target}) =>
    ordersFactory(introduce: true).createProxy(
      target ?? DefaultOrders(),
      advisors,
      beanName: 'orders',
    ) as Orders;

bool matches(String expression, String member) =>
    ExpressionPointcut(expression)
        .matches(orderSignatures.firstWhere((s) => s.name == member), 'orders');

AnnotationConfigApplicationContext context(
  List<BeanDefinition<Object>> beans,
) => AnnotationConfigApplicationContext([
  BeanModule('test', beans),
], environment: StandardEnvironment(systemEnvironment: {}))..refresh();

BeanDefinition<DefaultOrders> ordersBean(
  String name, {
  bool introduce = false,
}) => BeanDefinition<DefaultOrders>(
  name: name,
  types: const [DefaultOrders, BaseOrders, Orders],
  aopProxy: ordersFactory(introduce: introduce),
  create: (_) => DefaultOrders(),
);

class CallCounter {
  int calls = 0;
}

BeanDefinition<CallCounter> counterAspect(
  String name, {
  required String perClause,
  required String pointcut,
  String scope = ScopeType.prototype,
  List<CallCounter>? created,
}) => BeanDefinition<CallCounter>(
  name: name,
  scope: scope,
  create: (_) {
    final counter = CallCounter();
    created?.add(counter);
    return counter;
  },
  aspect: AspectMetadata<CallCounter>(
    typeName: 'CallCounter',
    perClause: perClause,
    advice: [
      AspectAdvice<CallCounter>(
        kind: AdviceKind.before,
        pointcut: pointcut,
        methodName: 'count',
        invoke: (aspect, joinPoint, _, _) {
          aspect.calls++;
          log.add('${joinPoint.signature.name} #${aspect.calls}');
          return null;
        },
      ),
    ],
  ),
);

void main() {
  setUp(log.clear);

  group('within and @within use the class whose body runs', () {
    test('an inherited method is within its declaring class', () {
      expect(matches('within(BaseOrders)', 'count'), isTrue);
      expect(matches('within(DefaultOrders)', 'count'), isFalse);
      expect(matches('within(DefaultOrders)', 'place'), isTrue);
      expect(matches('within(BaseOrders)', 'place'), isFalse);
      // `+`: the class or a subtype of it.
      expect(matches('within(BaseOrders+)', 'place'), isTrue);
      expect(matches('within(Orders+)', 'count'), isTrue);
      expect(matches('within(DefaultOrders+)', 'count'), isFalse);
    });

    test('@within reads the declaring class, @target the bean class', () {
      expect(matches('@within(Audited)', 'count'), isTrue);
      expect(matches('@within(Audited)', 'place'), isFalse);
      expect(matches('@target(Audited)', 'count'), isFalse);
      expect(matches('@target(Marker)', 'count'), isTrue);
    });

    test('@within binds the declaring class annotation', () {
      proxy([
          before(
            '@within(audited)',
            bindings: {'audited': binding<Audited>('Audited')},
            body: (joinPoint, bound) =>
                log.add('${joinPoint.signature.name} ${bound['audited']}'),
          ),
        ])
        ..count()
        ..place('x');
      expect(log, ["count Instance of 'Audited'"]);
    });
  });

  group('args by runtime type', () {
    test('args(Type) tests the argument (instanceof) with a type test', () {
      proxy([
          before(
            'args(String)',
            typeTests: {'String': (value) => value is String},
          ),
        ])
        ..place('book')
        ..place(42);
      expect(log, ['before place']);
    });

    test('without a type test only the declared type counts', () {
      expect(matches('args(String)', 'place'), isFalse);
      expect(matches('args(Object)', 'place'), isTrue);
      expect(matches('args(*)', 'place'), isTrue);
      proxy([before('args(Object)')]).place(42);
      expect(log, ['before place']);
    });

    test('type tests of all aspects apply to every aspect', () {
      final created = <CallCounter>[];
      final ctx = context([
        ordersBean('orders'),
        BeanDefinition<CallCounter>(
          name: 'tests',
          create: (_) => CallCounter(),
          aspect: AspectMetadata<CallCounter>(
            typeName: 'Tests',
            typeTests: {'String': (value) => value is String},
          ),
        ),
        counterAspect(
          'strings',
          perClause: '',
          pointcut: 'args(String)',
          scope: ScopeType.singleton,
          created: created,
        ),
      ]);
      ctx.getBean<Orders>()
        ..place('a')
        ..place(1);
      expect(log, ['place #1']);
      ctx.close();
    });
  });

  group('@args', () {
    Object? audited(Object? value) =>
        value is AuditedItem ? const Audited() : null;

    test('matches arguments whose class carries the annotation', () {
      proxy([
          before('@args(Audited)', argumentAnnotations: {'Audited': audited}),
        ])
        ..place(const AuditedItem())
        ..place('plain')
        ..count();
      expect(log, ['before place']);
    });

    test('binds the annotation; unknown annotations never match', () {
      proxy([
        before(
          '@args(a, ..)',
          bindings: {'a': binding<Audited>('Audited')},
          argumentAnnotations: {'Audited': audited},
          body: (_, bound) => log.add('bound ${bound['a']}'),
        ),
      ]).place(const AuditedItem());
      expect(log, ["bound Instance of 'Audited'"]);
      expect(matches('@args(Audited)', 'place'), isFalse);
      expect(() => ExpressionPointcut('@args(audited)'), throwsFormatException);
    });
  });

  group('this / target bound to any type', () {
    test('an Object parameter matches and gets the proxy or target', () {
      final target = DefaultOrders();
      late Orders orders;
      orders = proxy(target: target, [
        before(
          'execution(* place(..)) && this(self) && target(bean)',
          bindings: {
            'self': binding<Object>('Object'),
            'bean': binding<Object>('Object'),
          },
          body: (_, bound) => log.add(
            '${identical(bound['self'], orders)} '
            '${identical(bound['bean'], target)}',
          ),
        ),
      ]);
      orders.place('x');
      expect(log, ['true true']);
    });

    test('this(t) of an introduced interface is decided per call', () {
      final orders =
          proxy([
              before(
                'execution(* place(..)) && this(usage)',
                bindings: {'usage': binding<UsageTracked>('UsageTracked')},
                body: (_, bound) => (bound['usage']! as UsageTracked).use(),
              ),
            ])
            ..place('a')
            ..place('b');
      expect((orders as UsageTracked).uses, 2);
    });
  });

  group('execution modifiers and throws', () {
    test('public, protected (@protected), private', () {
      expect(matches('execution(protected * *(..))', 'audit'), isTrue);
      expect(matches('execution(protected * *(..))', 'place'), isFalse);
      expect(matches('execution(public * *(..))', 'audit'), isFalse);
      expect(matches('execution(public * *(..))', 'place'), isTrue);
      expect(matches('execution(!public * *(..))', 'audit'), isTrue);
      expect(matches('execution(private * *(..))', 'place'), isFalse);
      expect(matches('execution(public final * *(..))', 'place'), isTrue);
    });

    test('a throws clause is rejected with the reason', () {
      expect(
        () => ExpressionPointcut('execution(* *(..) throws StateError)'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Dart methods declare no exceptions'),
          ),
        ),
      );
    });
  });

  group('ComposablePointcut', () {
    final place = orderSignatures[0];
    final count = orderSignatures[1];

    test('union and intersection', () {
      final union = ComposablePointcut(const NameMatchMethodPointcut(['place']))
          .union(const NameMatchMethodPointcut(['count']));
      expect(union.matches(place, 'orders'), isTrue);
      expect(union.matches(count, 'orders'), isTrue);
      expect(union.matches(orderSignatures[2], 'orders'), isFalse);
      final both = ComposablePointcut(ExpressionPointcut('within(Orders+)'))
          .intersection(const NameMatchMethodPointcut(['place']));
      expect(both.matches(place, 'orders'), isTrue);
      expect(both.matches(count, 'orders'), isFalse);
      expect(ComposablePointcut().matches(count, 'x'), isTrue);
    });

    test('bean(...) parts see aliases through the proxy factory', () {
      final pointcut = ComposablePointcut(ExpressionPointcut('bean(main)'));
      (ordersFactory().createProxy(
        DefaultOrders(),
        [DefaultPointcutAdvisor(pointcut, _Tag('t'))],
        beanName: 'orders',
        beanAliases: const ['main'],
      ) as Orders).count();
      expect(log, ['t count']);
    });
  });

  group('Advised.addAdvisor / removeAdvisor', () {
    test('changes the chain of a live proxy', () {
      final orders = proxy(const []);
      final advised = orders as Advised;
      final tag = _Tag('t');
      orders.count();
      advised.addAdvice(tag);
      orders.count();
      final placeOnly = DefaultPointcutAdvisor(
        const NameMatchMethodPointcut(['place']),
        _Tag('p'),
      );
      advised.addAdvisor(placeOnly);
      orders
        ..count()
        ..place('x');
      expect(advised.aopAdvisors, hasLength(2));
      expect(advised.removeAdvice(tag), isTrue);
      expect(advised.removeAdvice(tag), isFalse);
      expect(advised.removeAdvisor(placeOnly), isTrue);
      orders.place('y');
      expect(log, ['t count', 't count', 't place', 'p place']);
      expect(() => advised.aopAdvisors.add(placeOnly), throwsUnsupportedError);
    });

    test('a subclass proxy without advice is not advised', () {
      expect(
        () => _$CounterProxy().addAdvice(_Tag('t')),
        throwsA(isA<AopConfigException>()),
      );
    });
  });

  group('ProxyFactory / AspectJProxyFactory', () {
    test('creates proxies with the added advice', () {
      final target = DefaultOrders();
      final factory = ProxyFactory(target, ordersFactory(), beanName: 'orders')
        ..addAdvice(_Tag('a'))
        ..addAdvisor(
          DefaultPointcutAdvisor(
            ExpressionPointcut('execution(* place(..))'),
            _Tag('b'),
          ),
        );
      final orders = factory.getProxy() as Orders;
      expect(orders.place('x'), 'placed x');
      expect(log, ['a place', 'b place']);
      expect(AopUtils.getTarget(orders), same(target));
      expect(factory.removeAdvice(_Tag('z')), isFalse);
      expect(factory.advisors, hasLength(2));
      expect(factory.getProxy(), isNot(same(orders)));
    });

    test('forBean proxies the target of a context bean', () {
      final ctx = context([ordersBean('orders')]);
      final factory = ProxyFactory.forBean(ctx.beanFactory, 'orders')
        ..addAdvice(_Tag('x'));
      final orders = factory.getProxy() as Orders..count();
      expect(log, ['x count']);
      expect(
        AopUtils.getTarget(orders),
        same(AopUtils.getTarget(ctx.getBean<Orders>())),
      );
      ctx.close();
    });

    test('a bean without a proxy class or an unavailable one fails', () {
      final ctx = context([
        BeanDefinition<Counter>(name: 'plain', create: (_) => Counter()),
      ]);
      expect(
        () => ProxyFactory.forBean(ctx.beanFactory, 'plain'),
        throwsA(isA<AopConfigException>()),
      );
      ctx.close();
      final unavailable = ProxyFactory(
        DefaultOrders(),
        AopProxyFactory.unavailable(
          signatures: orderSignatures,
          reason: 'it is final',
        ),
      );
      expect(
        unavailable.getProxy,
        throwsA(
          isA<AopConfigException>().having(
            (e) => e.message,
            'message',
            contains('it is final'),
          ),
        ),
      );
    });

    test('AspectJProxyFactory adds an aspect instance, advice by kind', () {
      final aspect = CallCounter();
      final metadata = AspectMetadata<CallCounter>(
        typeName: 'Audit',
        pointcuts: {'placing': 'execution(* place(..))'},
        advice: [
          AspectAdvice<CallCounter>(
            kind: AdviceKind.after,
            pointcut: 'placing()',
            methodName: 'after',
            invoke: (a, _, _, _) {
              log.add('after ${a.calls}');
              return null;
            },
          ),
          AspectAdvice<CallCounter>(
            kind: AdviceKind.before,
            pointcut: 'Audit.placing()',
            methodName: 'before',
            invoke: (a, _, _, _) {
              log.add('before ${++a.calls}');
              return null;
            },
          ),
        ],
      );
      final factory = AspectJProxyFactory(DefaultOrders(), ordersFactory())
        ..addAspect(aspect, metadata);
      factory.getProxy() as Orders
        ..place('x')
        ..count();
      expect(log, ['before 1', 'after 1']);
      expect(
        () => AspectJProxyFactory(DefaultOrders(), ordersFactory()).addAspect(
          aspect,
          AspectMetadata<CallCounter>(
            typeName: 'PerThis',
            perClause: 'perthis(execution(* *(..)))',
          ),
        ),
        throwsA(isA<AopConfigException>()),
      );
    });
  });

  group('perthis / pertarget', () {
    test('one aspect instance per proxy, where the per clause matches', () {
      final created = <CallCounter>[];
      final ctx = context([
        ordersBean('first'),
        ordersBean('second'),
        counterAspect(
          'counter',
          perClause: 'perthis(execution(* place(..)))',
          pointcut: 'execution(* *(..))',
          created: created,
        ),
      ]);
      final first = ctx.getBean<Orders>(qualifier: 'first');
      final second = ctx.getBean<Orders>(qualifier: 'second');
      first
        ..place('a')
        ..place('b')
        ..count(); // the per clause does not match count()
      second.place('c');
      expect(log, ['place #1', 'place #2', 'place #1']);
      expect(created, hasLength(2));
      ctx.close();
    });

    test('pertarget keys the instance by the target', () {
      final created = <CallCounter>[];
      final ctx = context([
        ordersBean('orders'),
        counterAspect(
          'counter',
          perClause: 'pertarget(within(DefaultOrders))',
          pointcut: 'execution(* place(..))',
          created: created,
        ),
      ]);
      ctx.getBean<Orders>()
        ..place('a')
        ..place('b');
      expect(log, ['place #1', 'place #2']);
      expect(created, hasLength(1));
      ctx.close();
    });

    test('a singleton per-instance aspect and percflow fail', () {
      Matcher failsWith(String text) =>
          throwsA(predicate((Object e) => '$e'.contains(text)));
      expect(
        () => context([
          ordersBean('orders'),
          counterAspect(
            'counter',
            perClause: 'perthis(execution(* *(..)))',
            pointcut: 'execution(* *(..))',
            scope: ScopeType.singleton,
          ),
        ]),
        failsWith(
          "Bean with name 'counter' is a singleton, but aspect "
          'instantiation model is not singleton',
        ),
      );
      expect(
        () => context([
          ordersBean('orders'),
          counterAspect(
            'counter',
            perClause: 'percflow(execution(* *(..)))',
            pointcut: 'execution(* *(..))',
          ),
        ]),
        failsWith('Spring AOP does not do either'),
      );
    });
  });

  group('@DeclareParents introductions', () {
    test('unbound this(Introduced) matches the introduced interface', () {
      final ctx = context([
        ordersBean('tracked', introduce: true),
        ordersBean('plain'),
        BeanDefinition<CallCounter>(
          name: 'usageTracking',
          create: (_) => CallCounter(),
          aspect: AspectMetadata<CallCounter>(typeName: 'UsageTracking'),
        ),
        counterAspect(
          'counter',
          perClause: '',
          pointcut: 'this(UsageTracked) && execution(* count(..))',
          scope: ScopeType.singleton,
        ),
      ]);
      ctx.getBean<Orders>(qualifier: 'tracked').count();
      ctx.getBean<Orders>(qualifier: 'plain').count();
      expect(log, ['count #1']);
      ctx.close();
    });

    test('the proxy implements the interface with a delegate per proxy', () {
      final ctx = context([
        ordersBean('first', introduce: true),
        ordersBean('second', introduce: true),
        // An aspect with no advice that matches: the introduction alone
        // proxies the beans.
        BeanDefinition<CallCounter>(
          name: 'usageTracking',
          create: (_) => CallCounter(),
          aspect: AspectMetadata<CallCounter>(typeName: 'UsageTracking'),
        ),
      ]);
      final first = ctx.getBean<Orders>(qualifier: 'first');
      final second = ctx.getBean<Orders>(qualifier: 'second');
      expect(first, isA<UsageTracked>());
      (first as UsageTracked)
        ..use()
        ..use();
      (second as UsageTracked).use();
      expect((first as UsageTracked).uses, 2);
      expect((second as UsageTracked).uses, 1);
      ctx.close();
    });

    test('without the declaring aspect the bean is not proxied', () {
      final ctx = context([ordersBean('orders', introduce: true)]);
      expect(ctx.getBean<Orders>(), isNot(isA<UsageTracked>()));
      ctx.close();
    });
  });

  test('an Advisor registered with registerSingleton (from a '
      'BeanFactoryPostProcessor) is applied', () {
    final ctx = context([
      ordersBean('orders'),
      BeanDefinition<_RegistersAdvisor>(
        name: 'registersAdvisor',
        types: const [_RegistersAdvisor, BeanFactoryPostProcessor],
        create: (_) => _RegistersAdvisor(),
      ),
    ]);
    ctx.getBean<Orders>().count();
    expect(log, ['manual count']);
    ctx.close();
  });
}

class _RegistersAdvisor implements BeanFactoryPostProcessor {
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      beanFactory.registerSingleton(
        'manualAdvisor',
        DefaultPointcutAdvisor(
          const NameMatchMethodPointcut(['count']),
          _Tag('manual'),
        ),
      );
}
