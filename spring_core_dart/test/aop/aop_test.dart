import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Timed {
  const Timed();
}

class Audited {
  const Audited();
}

const _targetTypes = ['PriceService', 'Service', 'Base'];

MethodSignature sig(
  String name, {
  String returnType = 'int',
  List<String> params = const ['int'],
  List<Object> annotations = const [],
  MemberKind kind = MemberKind.method,
  List<Object> targetAnnotations = const [],
}) => MethodSignature(
  name: name,
  declaringType: 'Service',
  targetType: 'PriceService',
  declaringTypes: const ['PriceService', 'Service'],
  kind: kind,
  returnType: returnType,
  parameterTypes: params,
  annotations: annotations,
  targetTypes: _targetTypes,
  targetAnnotations: targetAnnotations,
);

bool matches(
  String expression,
  MethodSignature signature, [
  String bean = 'priceService',
  Map<String, String> named = const {},
]) => ExpressionPointcut(
  expression,
  namedPointcuts: named,
).matches(signature, bean);

abstract interface class Service {
  int price(int amount);
  Future<int> fetch(int id);
  void reset();
  String get name;
}

class PriceService implements Service {
  int resets = 0;
  @override
  int price(int amount) {
    if (amount < 0) {
      throw ArgumentError('negative');
    }
    return amount * 2;
  }

  @override
  Future<int> fetch(int id) async {
    if (id < 0) {
      throw StateError('missing');
    }
    return id + 100;
  }

  @override
  void reset() => resets++;

  @override
  String get name => 'prices';
}

/// A hand-written proxy, like the generated ones.
class ServiceProxy implements Service, Advised {
  ServiceProxy(this._target, this._invoker);
  final PriceService _target;
  final ProxyInvoker _invoker;

  static final List<MethodSignature> signatures = [
    sig('price', annotations: const [Timed()]),
    sig('fetch', returnType: 'Future'),
    sig('reset', returnType: 'void', params: const []),
    sig(
      'name',
      returnType: 'String',
      params: const [],
      kind: MemberKind.getter,
    ),
  ];

  @override
  Object get aopTarget => _target;

  @override
  List<PointcutAdvisor> get aopAdvisors => _invoker.advisors;

  @override
  void addAdvisor(PointcutAdvisor advisor) => _invoker.addAdvisor(advisor);

  @override
  bool removeAdvisor(PointcutAdvisor advisor) =>
      _invoker.removeAdvisor(advisor);

  @override
  void addAdvice(MethodInterceptor advice) => _invoker.addAdvice(advice);

  @override
  bool removeAdvice(MethodInterceptor advice) => _invoker.removeAdvice(advice);

  @override
  int price(int amount) =>
      _invoker.invoke(this, _target, 0, [
            amount,
          ], (args) => _target.price(args[0]! as int))!
          as int;

  @override
  Future<int> fetch(int id) => _invoker.invokeAsync<int>(this, _target, 1, [
    id,
  ], (args) => _target.fetch(args[0]! as int));

  @override
  void reset() {
    _invoker.invoke(this, _target, 2, const [], (args) {
      _target.reset();
      return null;
    });
  }

  @override
  String get name =>
      _invoker.invoke(this, _target, 3, const [], (_) => _target.name)!
          as String;
}

final factory = AopProxyFactory(
  signatures: ServiceProxy.signatures,
  create: (target, invoker) => ServiceProxy(target as PriceService, invoker),
);

final log = <String>[];

class Recorder {
  void record(String text) => log.add(text);
}

AspectAdviceInterceptor interceptor(
  AdviceKind kind,
  Object? Function(Recorder aspect, JoinPoint jp, Object? value) invoke, {
  bool Function(Object? value)? accepts,
}) => AspectAdviceInterceptor(
  AspectAdvice<Recorder>(
    kind: kind,
    pointcut: 'execution(* *(..))',
    methodName: kind.name,
    invoke: (a, jp, v, _) => invoke(a, jp, v),
    accepts: accepts,
  ),
  Recorder.new,
);

PointcutAdvisor advisor(
  MethodInterceptor advice, [
  String expression = 'execution(* *(..))',
]) => DefaultPointcutAdvisor(ExpressionPointcut(expression), advice);

void main() {
  setUp(log.clear);

  group('pointcut expressions', () {
    final price = sig(
      'price',
      annotations: const [Timed()],
      targetAnnotations: const [Audited()],
    );

    test('execution', () {
      expect(matches('execution(* *(..))', price), isTrue);
      expect(matches('execution(int price(int))', price), isTrue);
      expect(
        matches('execution(public int Service.price(int))', price),
        isTrue,
      );
      expect(matches('execution(* PriceService.*(..))', price), isTrue);
      // Package qualification can't be honoured in Dart; a qualified
      // wildcard is rejected instead of silently ignoring the package.
      expect(
        () => matches('execution(* com.example..*Service.pri*(..))', price),
        throwsA(isA<FormatException>()),
      );
      expect(matches('execution(* Other.*(..))', price), isFalse);
      expect(matches('execution(String *(..))', price), isFalse);
      expect(matches('execution(* *())', price), isFalse);
      expect(matches('execution(* *(*))', price), isTrue);
      expect(matches('execution(* *(int, ..))', price), isTrue);
      expect(matches('execution(* *(.., int))', price), isTrue);
      expect(matches('execution(* *(String, ..))', price), isFalse);
      expect(matches('execution(* *(int, int))', price), isFalse);
      expect(
        matches('execution(List<int> *(..))', sig('x', returnType: 'List')),
        isTrue,
      );
      expect(
        matches('execution(* *(..))', sig('name', kind: MemberKind.getter)),
        isFalse,
      );
    });

    test('a syntax error carries its position', () {
      int? offsetOf(String expression) {
        try {
          ExpressionPointcut(expression);
        } on FormatException catch (e) {
          return e.offset;
        }
        return null;
      }

      expect(offsetOf('within(A) && '), 13);
      expect(offsetOf('within(A) && frob(B)'), 13);
      expect(offsetOf('within(A) && execution(String)'), 13);
      expect(offsetOf('within(A'), 0);
      expect(offsetOf('within(A) )'), 10);
      expect(offsetOf('within(A) && other()'), 13);
    });

    test('within, target, bean, annotations', () {
      expect(matches('within(*Service)', price), isTrue);
      expect(matches('within(Service)', price), isFalse);
      expect(matches('target(Base)', price), isTrue);
      expect(matches('this(PriceService)', price), isTrue);
      expect(matches('target(Other)', price), isFalse);
      expect(matches('bean(price*)', price), isTrue);
      expect(matches('bean(other)', price), isFalse);
      expect(matches('@annotation(Timed)', price), isTrue);
      expect(matches('@annotation(Audited)', price), isFalse);
      expect(matches('@within(Audited)', price), isTrue);
      expect(matches('@within(Timed)', price), isFalse);
    });

    test('combinators and named pointcuts', () {
      expect(matches('bean(price*) && @annotation(Timed)', price), isTrue);
      expect(matches('bean(x) || @annotation(Timed)', price), isTrue);
      expect(matches('bean(x) or bean(y)', price), isFalse);
      expect(matches('!bean(x) and not bean(y)', price), isTrue);
      expect(
        matches('(bean(x) || bean(price*)) && !@annotation(Audited)', price),
        isTrue,
      );
      final named = {
        'timed': '@annotation(Timed)',
        'Aspect.prices': 'bean(price*) && timed()',
      };
      expect(matches('timed()', price, 'b', named), isTrue);
      expect(matches('Aspect.prices()', price, 'priceService', named), isTrue);
      // A qualified reference names its type, like Spring's fully
      // qualified pointcut references: no fallback to another type's.
      expect(
        () => matches('Other.timed()', price, 'b', named),
        throwsFormatException,
      );
    });

    test('errors', () {
      for (final bad in [
        '',
        'execution(* *(..)',
        'bogus(x)',
        'nope()',
        'execution(oops)',
        'bean(x) &&',
        'bean(x) bean(y)',
        'execution',
        '(bean(x)',
      ]) {
        expect(
          () => ExpressionPointcut(bad),
          throwsFormatException,
          reason: bad,
        );
      }
      expect(
        () =>
            ExpressionPointcut('a()', namedPointcuts: {'a': 'b()', 'b': 'a()'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('circular'),
          ),
        ),
      );
      expect(ExpressionPointcut('bean(x)').toString(), contains('bean(x)'));
    });

    test('other pointcuts', () {
      expect(const TruePointcut().matches(price, 'x'), isTrue);
      expect(
        const NameMatchMethodPointcut(['pri*', 'x']).matches(price, 'x'),
        isTrue,
      );
      expect(const NameMatchMethodPointcut(['x']).matches(price, 'x'), isFalse);
      expect(
        const AnnotationMatchingPointcut<Timed>().matches(price, 'x'),
        isTrue,
      );
      expect(
        const AnnotationMatchingPointcut<Audited>(onClass: true)
            .matches(price, 'x'),
        isTrue,
      );
      expect(wildcardMatch('a*c', 'abc'), isTrue);
    });
  });

  group('proxy invocation', () {
    test('no advice: direct call', () {
      final target = PriceService();
      final proxy = factory.createProxy(target, const []) as Service;
      expect(proxy.price(2), 4);
      expect(AopUtils.isAopProxy(proxy), isTrue);
      expect(AopUtils.getTarget(proxy), same(target));
      expect(AopUtils.isAopProxy(target), isFalse);
      expect((proxy as Advised).aopAdvisors, isEmpty);
    });

    test('advice kinds in Spring order', () {
      final advisors = [
        advisor(
          interceptor(AdviceKind.around, (a, jp, _) {
            a.record('around:before');
            final result = (jp as ProceedingJoinPoint).proceed();
            a.record('around:after');
            return result;
          }),
        ),
        advisor(
          interceptor(
            AdviceKind.before,
            (a, jp, _) => a.record('before ${jp.args}'),
          ),
        ),
        advisor(interceptor(AdviceKind.after, (a, jp, _) => a.record('after'))),
        advisor(
          interceptor(
            AdviceKind.afterReturning,
            (a, jp, v) => a.record('returned $v'),
          ),
        ),
        advisor(
          interceptor(
            AdviceKind.afterThrowing,
            (a, jp, e) => a.record('threw $e'),
          ),
        ),
      ];
      final proxy = factory.createProxy(
        PriceService(),
        advisors,
        beanName: 'priceService',
      ) as Service;
      expect(proxy.price(2), 4);
      expect(log, [
        'around:before',
        'before [2]',
        'returned 4',
        'after',
        'around:after',
      ]);
      log.clear();
      expect(() => proxy.price(-1), throwsArgumentError);
      expect(log, [
        'around:before',
        'before [-1]',
        'threw Invalid argument(s): negative',
        'after',
      ]);
      log.clear();
      proxy.reset();
      expect(log.first, 'around:before');
      expect(proxy.name, 'prices');
    });

    test('afterReturning and afterThrowing filter by type', () {
      final proxy = factory.createProxy(PriceService(), [
        // execution(...) only matches methods; TruePointcut also matches
        // the getter.
        DefaultPointcutAdvisor(
          const TruePointcut(),
          interceptor(
            AdviceKind.afterReturning,
            (a, jp, v) => a.record('string'),
            accepts: (v) => v is String,
          ),
        ),
        advisor(
          interceptor(
            AdviceKind.afterThrowing,
            (a, jp, e) => a.record('state'),
            accepts: (e) => e is StateError,
          ),
        ),
      ]) as Service..price(1);
      expect(() => proxy.price(-1), throwsArgumentError);
      expect(log, isEmpty);
      expect(proxy.name, 'prices');
      expect(log, ['string']);
    });

    test(
      'afterReturning on a void method: Object? gets null, Object skips',
      () {
        // As generated for `@AfterReturning void any(Object? result)` and
        // `void some(Object result)`.
        (factory.createProxy(PriceService(), [
          advisor(
            interceptor(
              AdviceKind.afterReturning,
              (a, jp, v) => a.record('any:$v'),
            ),
          ),
          advisor(
            interceptor(
              AdviceKind.afterReturning,
              (a, jp, v) => a.record('some:${v!}'),
              accepts: (v) => v is Object,
            ),
          ),
        ]) as Service).reset();
        expect(log, ['any:null']);
      },
    );

    test('around can replace arguments and results; join point info', () {
      final proxy = factory.createProxy(PriceService(), [
        advisor(
          interceptor(AdviceKind.around, (a, jp, _) {
            final pjp = jp as ProceedingJoinPoint;
            a.record(
              '${pjp.toShortString()} ${pjp.signature} '
              'target=${pjp.target.runtimeType} '
              'proxy=${pjp.proxy is ServiceProxy} $pjp',
            );
            return (pjp.proceed([10])! as int) + 1;
          }),
          '@annotation(Timed)',
        ),
      ]) as Service;
      expect(proxy.price(1), 21);
      expect(
        log.single,
        contains(
          'execution(Service.price(..)) int Service.price(int) '
          'target=PriceService proxy=true',
        ),
      );
      expect(proxy.name, 'prices', reason: 'not matched');
    });

    test('async advice waits for the future and keeps its type', () async {
      final proxy = factory.createProxy(PriceService(), [
        advisor(
          interceptor(AdviceKind.before, (a, jp, _) => a.record('before')),
        ),
        advisor(interceptor(AdviceKind.after, (a, jp, _) => a.record('after'))),
        advisor(
          interceptor(
            AdviceKind.afterReturning,
            (a, jp, v) => a.record('returned $v'),
          ),
        ),
        advisor(
          interceptor(
            AdviceKind.afterThrowing,
            (a, jp, e) => a.record('threw ${e.runtimeType}'),
          ),
        ),
      ]) as Service;
      final future = proxy.fetch(1);
      expect(future, isA<Future<int>>());
      expect(log, ['before']);
      expect(await future, 101);
      expect(log, ['before', 'returned 101', 'after']);
      log.clear();
      await expectLater(proxy.fetch(-1), throwsStateError);
      expect(log, ['before', 'threw StateError', 'after']);
    });

    test('async around returning an untyped future is retyped', () async {
      final proxy = factory.createProxy(PriceService(), [
        advisor(
          interceptor(AdviceKind.around, (a, jp, _) async {
            final value =
                await ((jp as ProceedingJoinPoint).proceed()!
                    as Future<Object?>);
            return (value! as int) * 2;
          }),
        ),
      ]) as Service;
      final result = proxy.fetch(1);
      expect(result, isA<Future<int>>());
      expect(await result, 202);
    });

    test('retypeFuture', () async {
      expect(await retypeFuture<int>(Future<Object?>.value(1)), 1);
      expect(await retypeFuture<int>(2), 2);
      final typed = Future<int>.value(3);
      expect(retypeFuture<int>(typed), same(typed));
    });

    test('custom interceptors and eligibility', () {
      final upper = DefaultPointcutAdvisor(
        const NameMatchMethodPointcut(['name']),
        _Upper(),
        order: 1,
      );
      expect(upper.toString(), contains('order 1'));
      final other = DefaultPointcutAdvisor(
        const NameMatchMethodPointcut(['zzz']),
        _Upper(),
      );
      expect(factory.eligibleAdvisors([upper, other], 'x'), [upper]);
      final proxy = factory.createProxy(PriceService(), [upper]) as Service;
      expect(proxy.name, 'PRICES');
      expect(
        AspectAdvice<Recorder>(
          kind: AdviceKind.before,
          pointcut: 'p',
          methodName: 'm',
          invoke: (_, _, _, _) => null,
        ).toString(),
        '@before(p) m',
      );
    });
  });

  group('auto proxy creator', () {
    BeanDefinition<PriceService> service({String name = 'priceService'}) =>
        BeanDefinition<PriceService>(
          name: name,
          types: const [PriceService, Service],
          aopProxy: factory,
          create: (_) => PriceService(),
        );

    BeanDefinition<Recorder> aspect({
      int? order,
      String expression = 'execution(* price(..))',
      String name = 'recorder',
      String? source,
    }) => BeanDefinition<Recorder>(
      name: name,
      order: order,
      source: source,
      create: (_) => Recorder(),
      aspect: AspectMetadata<Recorder>(
        pointcuts: {'prices': expression},
        advice: [
          AspectAdvice<Recorder>(
            kind: AdviceKind.afterReturning,
            pointcut: 'prices()',
            methodName: 'returned',
            invoke: (a, jp, v, _) {
              a.record('$name:returned $v');
              return null;
            },
          ),
          AspectAdvice<Recorder>(
            kind: AdviceKind.before,
            pointcut: 'Recorder.prices()',
            methodName: 'before',
            invoke: (a, jp, v, _) {
              a.record('$name:before');
              return null;
            },
          ),
        ],
      ),
    );

    test('aspects and advisor beans through the context', () {
      final context = AnnotationConfigApplicationContext([
        BeanModule('aop', [
          service(),
          aspect(order: 2, name: 'second'),
          aspect(order: 1, name: 'first'),
          BeanDefinition<DefaultPointcutAdvisor>(
            name: 'upper',
            types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor],
            create: (_) => DefaultPointcutAdvisor(
              const NameMatchMethodPointcut(['name']),
              _Upper(),
            ),
          ),
          BeanDefinition<PriceService>(
            name: 'plain',
            create: (_) => PriceService(),
          ),
        ]),
      ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
      final proxy = context.getBean<Service>();
      expect(proxy, isA<Advised>());
      expect(proxy.price(3), 6);
      expect(log, [
        'first:before',
        'second:before',
        'second:returned 6',
        'first:returned 6',
      ]);
      expect(proxy.name, 'PRICES');
      expect(
        context.getBean<PriceService>(qualifier: 'plain'),
        isNot(isA<Advised>()),
      );
      expect(
        () => context.getBean<PriceService>(qualifier: 'priceService'),
        throwsA(isA<BeanNotOfRequiredTypeException>()),
      );
      context.close();
    });

    group('a proxy left to the application (AopProxyFactory.deferred)', () {
      const source = 'package:lib/src/prices.dart#PriceService';
      BeanDefinition<PriceService> deferred({bool lazy = false}) =>
          BeanDefinition<PriceService>(
            name: 'priceService',
            source: source,
            types: const [PriceService, Service],
            lazy: lazy,
            aopProxy: AopProxyFactory.deferred(
              signatures: ServiceProxy.signatures,
            ),
            create: (_) => PriceService(),
          );
      BeanModule library({bool lazy = false}) =>
          BeanModule('library', [deferred(lazy: lazy)]);
      BeanModule application() =>
          BeanModule('application', [aspect()], aopProxies: {source: factory});

      for (final (order, modules) in [
        ('application first', () => [application(), library()]),
        ('library first', () => [library(), application()]),
      ]) {
        test('takes the factory the application brings ($order)', () {
          final context = AnnotationConfigApplicationContext(
            modules(),
            environment: StandardEnvironment(systemEnvironment: {}),
          )..refresh();
          final proxy = context.getBean<Service>();
          expect(proxy, isA<Advised>());
          expect(proxy.price(3), 6);
          expect(log, ['recorder:before', 'recorder:returned 6']);
          context.close();
        });
      }

      test('without it, matching advice fails the startup', () {
        final context = AnnotationConfigApplicationContext([
          library(),
          BeanModule('aspects', [aspect()]),
        ], environment: StandardEnvironment(systemEnvironment: {}));
        expect(
          context.refresh,
          throwsA(
            predicate(
              (Object? e) => '$e'.contains('declared in a library package'),
            ),
          ),
        );
      });

      test('without it, a lazy bean fails at startup, not on first use', () {
        final context = AnnotationConfigApplicationContext([
          library(lazy: true),
          BeanModule('aspects', [aspect()]),
        ], environment: StandardEnvironment(systemEnvironment: {}));
        expect(
          context.refresh,
          throwsA(
            isA<AopConfigException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains("bean 'priceService'"),
                contains('ApplicationContextRunner'),
              ),
            ),
          ),
        );
      });

      test('one context taking the factory leaves the definition as it is', () {
        // The module is shared by both contexts, as a top-level module of
        // a starter is in one process.
        final shared = library();
        AnnotationConfigApplicationContext([
            shared,
            application(),
          ], environment: StandardEnvironment(systemEnvironment: {}))
          ..refresh()
          ..close();
        expect(shared.definitions.single.aopProxy!.isDeferred, isTrue);
        final without = AnnotationConfigApplicationContext([
          shared,
          BeanModule('aspects', [aspect(expression: 'bean(nothing)')]),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        expect(without.getBean<Service>(), isNot(isA<Advised>()));
        without.close();
      });

      test("the advisors the check creates convert with the application's "
          'conversionService', () {
        _Rate? rate;
        final context = AnnotationConfigApplicationContext([
          library(),
          BeanModule('application', [
            BeanDefinition<DefaultConversionService>(
              name: 'conversionService',
              types: const [DefaultConversionService, ConversionService],
              create: (_) =>
                  DefaultConversionService()
                    ..addConverter<String, _Rate>((s) => _Rate(int.parse(s))),
            ),
            // The advisor's dependency reads a value of a type only that
            // service converts.
            BeanDefinition<_RateHolder>(
              name: 'rateHolder',
              create: (r) => _RateHolder(r.value<_Rate>('7')),
            ),
            BeanDefinition<DefaultPointcutAdvisor>(
              name: 'rated',
              types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor],
              create: (r) {
                rate = r.getBean<_RateHolder>().rate;
                return DefaultPointcutAdvisor(
                  ExpressionPointcut('bean(nothing)'),
                  _Upper(),
                );
              },
            ),
          ]),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        expect(rate?.value, 7);
        expect(context.getBean<Service>(), isNot(isA<Advised>()));
        context.close();
      });

      test('a placeholder an ImportBeanDefinitionRegistrar registers takes '
          'the factory too', () {
        final context = AnnotationConfigApplicationContext([
          BeanModule(
            'library',
            const [],
            registrars: [ImportDeclaration(() => _Registers(deferred()))],
          ),
          application(),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        final proxy = context.getBean<Service>();
        expect(proxy, isA<Advised>());
        expect(proxy.price(3), 6);
        context.close();
      });

      test('a bean checked at startup is not checked again when created', () {
        final pointcut = _CountingPointcut();
        final context = AnnotationConfigApplicationContext([
          library(),
          BeanModule('aspects', [
            BeanDefinition<DefaultPointcutAdvisor>(
              name: 'counting',
              types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor],
              create: (_) => DefaultPointcutAdvisor(pointcut, _Upper()),
            ),
          ]),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        expect(context.getBean<Service>(), isNot(isA<Advised>()));
        // Each signature once, by the check at startup.
        expect(pointcut.calls, ServiceProxy.signatures.length);
        context.close();
      });

      test('a registered factory leaving out a member advice matches fails '
          'the startup', () {
        // The application's factory proxies `name` only; the aspect
        // advises `price`.
        final partial = AopProxyFactory(
          signatures: [ServiceProxy.signatures[3]],
          create: (target, invoker) =>
              ServiceProxy(target as PriceService, invoker),
        );
        final context = AnnotationConfigApplicationContext([
          library(),
          BeanModule('application', [aspect()], aopProxies: {source: partial}),
        ], environment: StandardEnvironment(systemEnvironment: {}));
        expect(
          context.refresh,
          throwsA(
            isA<AopConfigException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains("member 'price' of bean 'priceService'"),
                contains('aop_prune: false'),
              ),
            ),
          ),
        );
      });

      test('a registered factory leaving out only unadvised members is '
          'used', () {
        final context = AnnotationConfigApplicationContext([
          library(),
          BeanModule(
            'application',
            [aspect()],
            aopProxies: {
              source: AopProxyFactory(
                signatures: ServiceProxy.signatures,
                create: (target, invoker) =>
                    ServiceProxy(target as PriceService, invoker),
              ),
            },
          ),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        expect(context.getBean<Service>().price(3), 6);
        expect(log, ['recorder:before', 'recorder:returned 6']);
        context.close();
      });

      test('registerAopProxies rejects a factory that cannot proxy', () {
        for (final unusable in [
          const AopProxyFactory.pruned(),
          AopProxyFactory.deferred(signatures: ServiceProxy.signatures),
          AopProxyFactory.unavailable(
            signatures: ServiceProxy.signatures,
            reason: 'no class',
          ),
        ]) {
          expect(
            () => DefaultListableBeanFactory().registerAopProxies({
              source: unusable,
            }),
            throwsA(isA<AopConfigException>()),
          );
        }
      });

      test('registerAopProxies rejects a second, different factory for a '
          'source', () {
        final beanFactory = DefaultListableBeanFactory()
          ..registerAopProxies({source: factory})
          // The same one again (the module loaded twice) is fine.
          ..registerAopProxies({source: factory});
        expect(
          () => beanFactory.registerAopProxies({
            source: AopProxyFactory(
              signatures: [ServiceProxy.signatures[3]],
              create: (target, invoker) =>
                  ServiceProxy(target as PriceService, invoker),
            ),
          }),
          throwsA(isA<AopConfigException>()),
        );
        expect(
          beanFactory.aopProxyOf(deferred()),
          same(factory),
          reason: 'the first one stays',
        );
        // Two modules bringing different factories fail the startup.
        final context = AnnotationConfigApplicationContext([
          library(),
          application(),
          BeanModule(
            'other',
            const [],
            aopProxies: {source: const AopProxyFactory.pruned()},
          ),
        ], environment: StandardEnvironment(systemEnvironment: {}));
        expect(context.refresh, throwsA(isA<AopConfigException>()));
      });

      test('without it and without matching advice, the bean is plain', () {
        final context = AnnotationConfigApplicationContext([
          library(),
          BeanModule('aspects', [aspect(expression: 'bean(nothing)')]),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        expect(context.getBean<Service>(), isNot(isA<Advised>()));
        context.close();
      });
    });

    group('proxies the build pruned', () {
      const known = {'package:app/src/recorder.dart#Recorder'};
      BeanDefinition<PriceService> pruned() => BeanDefinition<PriceService>(
        name: 'plain',
        types: const [PriceService],
        aopProxy: const AopProxyFactory.pruned(knownAdvisors: known),
        create: (_) => PriceService(),
      );
      BeanDefinition<PriceService> partial() => BeanDefinition<PriceService>(
        name: 'priceService',
        types: const [PriceService, Service],
        aopProxy: AopProxyFactory(
          signatures: ServiceProxy.signatures,
          create: (target, invoker) =>
              ServiceProxy(target as PriceService, invoker),
          knownAdvisors: known,
        ),
        create: (_) => PriceService(),
      );
      BeanDefinition<DefaultPointcutAdvisor> guard({String? source}) =>
          BeanDefinition<DefaultPointcutAdvisor>(
            name: 'guard',
            source: source,
            types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor],
            create: (_) => DefaultPointcutAdvisor(
              const NameMatchMethodPointcut(['name']),
              _Upper(),
            ),
          );
      AnnotationConfigApplicationContext context(
        List<BeanModule> modules, {
        ApplicationContext? parent,
      }) => AnnotationConfigApplicationContext(
        modules,
        parent: parent,
        environment: StandardEnvironment(systemEnvironment: {}),
      );
      Matcher unknownAdvisor(String name) => throwsA(
        isA<AopConfigException>().having(
          (e) => e.message,
          'message',
          allOf(contains("bean '$name'"), contains('aop_prune: false')),
        ),
      );

      test('start with the advisors the build knew of', () {
        final started = context([
          BeanModule('app', [
            pruned(),
            partial(),
            aspect(source: known.single),
          ]),
        ])..refresh();
        expect(started.getBean<Service>().price(3), 6);
        expect(log, ['recorder:before', 'recorder:returned 6']);
        started.close();
      });

      test('an advisor an ImportBeanDefinitionRegistrar registers fails the '
          'startup', () {
        final failing = context([
          BeanModule(
            'app',
            [pruned(), aspect(source: known.single)],
            registrars: [ImportDeclaration(() => _Registers(guard()))],
          ),
        ]);
        expect(failing.refresh, unknownAdvisor('guard'));
      });

      test(
        'an advisor registered with registerSingleton fails the startup',
        () {
          final failing = context([
            BeanModule('app', [
              pruned(),
              BeanDefinition<_RegistersAdvisor>(
                name: 'registersAdvisor',
                types: const [_RegistersAdvisor, BeanFactoryPostProcessor],
                create: (_) => _RegistersAdvisor(),
              ),
            ]),
          ]);
          expect(failing.refresh, unknownAdvisor('manualGuard'));
        },
      );

      test('an advisor of a known package is known', () {
        context([
            BeanModule('app', [
              BeanDefinition<PriceService>(
                name: 'plain',
                types: const [PriceService],
                aopProxy: const AopProxyFactory.pruned(
                  knownAdvisors: {'package:starter'},
                ),
                create: (_) => PriceService(),
              ),
              guard(source: 'package:starter#StarterAutoConfiguration'),
            ]),
          ])
          ..refresh()
          ..close();
        expect(
          context([
            BeanModule('app', [
              BeanDefinition<PriceService>(
                name: 'plain',
                types: const [PriceService],
                aopProxy: const AopProxyFactory.pruned(
                  knownAdvisors: {'package:starter'},
                ),
                create: (_) => PriceService(),
              ),
              guard(source: 'package:starter_two#StarterAutoConfiguration'),
            ]),
          ]).refresh,
          unknownAdvisor('guard'),
        );
      });

      test(
        "an unknown advisor of a parent context fails the child's startup",
        () {
          final parent = context([
            BeanModule('parent', [guard()]),
          ])..refresh();
          addTearDown(parent.close);
          expect(
            context([
              BeanModule('child', [pruned()]),
            ], parent: parent).refresh,
            unknownAdvisor('guard'),
          );
        },
      );

      test('without pruned proxies, any advisor is fine', () {
        final started = context([
          BeanModule('app', [service(), guard()]),
        ])..refresh();
        expect(started.getBean<Service>().name, 'PRICES');
        started.close();
      });

      test('a partial proxy rejects advice added at run time', () {
        final started = context([
          BeanModule('app', [partial(), aspect(source: known.single)]),
        ])..refresh();
        final proxy = started.getBean<Service>() as Advised;
        expect(
          () => proxy.addAdvice(_Upper()),
          throwsA(
            isA<AopConfigException>().having(
              (e) => e.message,
              'message',
              contains('aop_prune: false'),
            ),
          ),
        );
        expect(
          () => proxy.addAdvisor(
            DefaultPointcutAdvisor(const TruePointcut(), _Upper()),
          ),
          throwsA(isA<AopConfigException>()),
        );
        expect(
          () => ProxyFactory.forBean(started.beanFactory, 'priceService')
            ..addAdvice(_Upper())
            ..getProxy(),
          throwsA(isA<AopConfigException>()),
        );
        // A full proxy takes it.
        final full = factory.createProxy(PriceService(), const []) as Advised
          ..addAdvice(_Upper());
        expect((full as Service).name, 'PRICES');
        started.close();
      });
    });

    test(
      'beans without matching advice stay unproxied; no AOP without aspects',
      () {
        final noMatch = AnnotationConfigApplicationContext([
          BeanModule('aop', [service(), aspect(expression: 'bean(nothing)')]),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        expect(noMatch.getBean<Service>(), isNot(isA<Advised>()));
        final noAop = AnnotationConfigApplicationContext([
          BeanModule('aop', [service()]),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
        expect(
          noAop.beanFactory.beanPostProcessorCount,
          3,
          reason:
              'only the aware processor, the @PostConstruct step and the '
              'listener detector',
        );
      },
    );

    test('advice matching a bean that cannot be proxied fails the start', () {
      BeanDefinition<PriceService> unproxyable(String name) =>
          BeanDefinition<PriceService>(
            name: name,
            create: (_) => PriceService(),
            aopProxy: AopProxyFactory.unavailable(
              signatures: const [
                MethodSignature(
                  name: 'price',
                  declaringType: 'PriceService',
                  targetType: 'PriceService',
                  returnType: 'int',
                  parameterTypes: ['int'],
                ),
              ],
              reason: 'PriceService has private members and no interface.',
            ),
          );
      expect(
        () => AnnotationConfigApplicationContext([
          BeanModule('aop', [unproxyable('priceService'), aspect()]),
        ], environment: StandardEnvironment(systemEnvironment: {}))..refresh(),
        throwsA(
          isA<BeanCreationException>().having(
            (e) => '${e.cause}',
            'cause',
            allOf(
              contains("Advice matches bean 'priceService'"),
              contains('PriceService has private members and no interface.'),
            ),
          ),
        ),
      );
      // Without matching advice the bean is simply not proxied.
      final context = AnnotationConfigApplicationContext([
        BeanModule('aop', [
          unproxyable('priceService'),
          aspect(expression: 'bean(nothing)'),
        ]),
      ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
      expect(context.getBean<PriceService>(), isNot(isA<Advised>()));
      context.close();
    });

    test('post-processor directly', () {
      final beanFactory = DefaultListableBeanFactory()
        ..registerBeanDefinition(service())
        ..registerBeanDefinition(aspect())
        ..registerSingleton('manual', PriceService());
      final creator = AspectAutoProxyCreator(beanFactory);
      expect(creator.order, Ordered.highestPrecedence);
      expect(
        creator.postProcessAfterInitialization(PriceService(), 'manual'),
        isA<PriceService>(),
      );
      expect(
        creator.postProcessAfterInitialization(PriceService(), 'priceService'),
        isA<Advised>(),
      );
      expect(
        creator.postProcessAfterInitialization(Recorder(), 'recorder'),
        isA<Recorder>(),
      );
      expect(creator.advisors, hasLength(2));
    });

    test('event listeners receive the target of proxied beans', () {
      final seen = <int>[];
      AnnotationConfigApplicationContext([
          BeanModule('aop', [
            BeanDefinition<PriceService>(
              name: 'priceService',
              types: const [PriceService, Service],
              aopProxy: factory,
              create: (_) => PriceService(),
              eventListeners: [
                EventListenerMethod.of<PriceService, int>('PriceService.on', (
                  bean,
                  e,
                ) {
                  seen.add(bean.price(e));
                  return null;
                }),
              ],
            ),
            aspect(),
          ]),
        ], environment: StandardEnvironment(systemEnvironment: {}))
        ..refresh()
        ..publishEvent(5);
      expect(seen, [10]);
    });
  });
}

final class _Registers implements ImportBeanDefinitionRegistrar {
  _Registers(this.definition);
  final BeanDefinition<Object> definition;

  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) =>
      registry.registerBeanDefinition(definition);
}

// Registers an advisor as a plain singleton, as a post-processor may.
final class _RegistersAdvisor implements BeanFactoryPostProcessor {
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      beanFactory.registerSingleton(
        'manualGuard',
        DefaultPointcutAdvisor(
          const NameMatchMethodPointcut(['name']),
          _Upper(),
        ),
      );
}

// Matches nothing, counting how often it is asked.
final class _CountingPointcut implements AopPointcut {
  int calls = 0;

  @override
  bool matches(MethodSignature signature, String beanName) {
    calls++;
    return false;
  }
}

class _Rate {
  const _Rate(this.value);
  final int value;
}

class _RateHolder {
  const _RateHolder(this.rate);
  final _Rate rate;
}

class _Upper implements MethodInterceptor {
  @override
  Object? invoke(MethodInvocation invocation) =>
      (invocation.proceed()! as String).toUpperCase();
}
