import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Timed {
  const Timed([this.label = '']);
  final String label;
}

class Audited {
  const Audited();
}

abstract class Base {}

abstract interface class Calc {
  int add(int a, int b);
  Future<int> later(int a);
  FutureOr<int> maybe(int a);
  void reset();
  String echo(Object value);
  Future<int> failFast(int code);
}

@Audited()
class SimpleCalc extends Base implements Calc {
  final calls = <String>[];

  @Timed('add')
  @override
  int add(int a, int b) => a + b;

  @override
  Future<int> later(int a) async {
    calls.add('later');
    return a * 10;
  }

  @override
  FutureOr<int> maybe(int a) => a.isEven ? Future.value(a) : a;

  @override
  void reset() => calls.add('reset');

  @override
  String echo(Object value) => '$value';

  // Not `async`: throws before returning a future.
  @override
  Future<int> failFast(int code) {
    if (code < 0) {
      throw StateError('sync');
    }
    return Future.value(code);
  }
}

class Counter {
  int count = 0;
  final int _step = 1;
  int next() => count += _step;
}

class Selfie {
  Object who() => AopContext.currentProxy();

  Future<Object> whoLater() async {
    await Future<void>.delayed(Duration.zero);
    return AopContext.currentProxy();
  }
}

// ---- generated ----

MethodSignature _calc(
  String name,
  String returnType,
  List<String> parameterTypes,
  List<String> parameterNames, {
  List<Object> annotations = const [],
  List<String> annotationTypes = const [],
}) => MethodSignature(
  name: name,
  declaringType: 'Calc',
  targetType: 'SimpleCalc',
  declaringTypes: const ['SimpleCalc', 'Calc'],
  returnType: returnType,
  parameterTypes: parameterTypes,
  parameterNames: parameterNames,
  annotations: annotations,
  annotationTypes: annotationTypes,
  targetTypes: const ['SimpleCalc', 'Base', 'Calc'],
  targetAnnotations: const [Audited()],
  targetAnnotationTypes: const ['Audited'],
);

final calcSignatures = [
  _calc(
    'add',
    'int',
    ['int', 'int'],
    ['a', 'b'],
    annotations: const [Timed('add')],
    annotationTypes: const ['Timed'],
  ),
  _calc('later', 'Future', ['int'], ['a']),
  _calc('maybe', 'FutureOr', ['int'], ['a']),
  _calc('reset', 'void', [], []),
  _calc('echo', 'String', ['Object'], ['value']),
  _calc('failFast', 'Future', ['int'], ['code']),
];

class _$CalcProxy implements Calc, Advised {
  _$CalcProxy(this._target, this._invoker);

  final SimpleCalc _target;
  final ProxyInvoker _invoker;

  @override
  Object get aopTarget => _target;

  @override
  List<PointcutAdvisor> get aopAdvisors => _invoker.advisors;

  @override
  int add(int a, int b) =>
      _invoker.invoke(this, _target, 0, [
            a,
            b,
          ], (args) => _target.add(args[0]! as int, args[1]! as int))!
          as int;

  @override
  Future<int> later(int a) => _invoker.invokeAsync<int>(this, _target, 1, [
    a,
  ], (args) => _target.later(args[0]! as int));

  @override
  FutureOr<int> maybe(int a) => _invoker.invokeFutureOr<int>(this, _target, 2, [
    a,
  ], (args) => _target.maybe(args[0]! as int));

  @override
  void reset() {
    _invoker.invoke(this, _target, 3, const [], (args) {
      _target.reset();
      return null;
    });
  }

  @override
  String echo(Object value) =>
      _invoker.invoke(this, _target, 4, [
            value,
          ], (args) => _target.echo(args[0]!))!
          as String;

  @override
  Future<int> failFast(int code) => _invoker.invokeAsync<int>(
    this,
    _target,
    5,
    [code],
    (args) => _target.failFast(args[0]! as int),
  );
}

final calcFactory = AopProxyFactory(
  signatures: calcSignatures,
  create: (target, invoker) => _$CalcProxy(target as SimpleCalc, invoker),
);

const counterSignatures = [
  MethodSignature(
    name: 'next',
    declaringType: 'Counter',
    targetType: 'Counter',
    returnType: 'int',
    targetTypes: ['Counter'],
  ),
];

// A subclass proxy: the bean is an instance of this class; advice is
// attached later by the auto proxy creator.
class _$CounterProxy extends Counter implements Advised {
  ProxyInvoker? _$invoker;

  @override
  Object get aopTarget => this;

  @override
  List<PointcutAdvisor> get aopAdvisors => _$invoker?.advisors ?? const [];

  @override
  int next() {
    final invoker = _$invoker;
    return invoker == null
        ? super.next()
        : invoker.invoke(this, this, 0, const [], (args) => super.next())!
              as int;
  }

  Object? _$advise(ProxyInvoker invoker) {
    _$invoker = invoker;
    return this;
  }
}

final counterFactory = AopProxyFactory.subclass(
  signatures: counterSignatures,
  advise: (bean, invoker) =>
      bean is _$CounterProxy ? bean._$advise(invoker) : null,
);

class _$SelfieProxy implements Selfie, Advised {
  _$SelfieProxy(this._target, this._invoker);

  final Selfie _target;
  final ProxyInvoker _invoker;

  static const signatures = [
    MethodSignature(name: 'who', declaringType: 'Selfie', targetType: 'S'),
    MethodSignature(name: 'whoLater', declaringType: 'Selfie', targetType: 'S'),
  ];

  @override
  Object get aopTarget => _target;

  @override
  List<PointcutAdvisor> get aopAdvisors => _invoker.advisors;

  @override
  Object who() =>
      _invoker.invoke(this, _target, 0, const [], (_) => _target.who())!;

  @override
  Future<Object> whoLater() => _invoker.invokeAsync<Object>(
    this,
    _target,
    1,
    const [],
    (_) => _target.whoLater(),
  );
}

// ---- end generated ----

final log = <String>[];

AdviceBinding binding<T>(String typeName) =>
    AdviceBinding(typeName, (value) => value is T);

PointcutAdvisor advice(
  AdviceKind kind,
  String pointcut,
  Object? Function(JoinPoint joinPoint, Object? value, Map<String, Object?> b)
  body, {
  Map<String, AdviceBinding> bindings = const {},
  Map<String, String> named = const {},
  String? owner,
  bool Function(Object? value)? accepts,
}) => DefaultPointcutAdvisor(
  ExpressionPointcut(
    pointcut,
    namedPointcuts: named,
    bindings: bindings,
    owner: owner,
  ),
  AspectAdviceInterceptor(
    AspectAdvice<Object>(
      kind: kind,
      pointcut: pointcut,
      methodName: kind.name,
      invoke: (_, joinPoint, value, bound) => body(joinPoint, value, bound),
      accepts: accepts,
      bindings: bindings,
    ),
    Object.new,
  ),
);

Calc proxy(
  List<PointcutAdvisor> advisors, {
  SimpleCalc? target,
  String beanName = 'calc',
  List<String> aliases = const [],
}) => calcFactory.createProxy(
  target ?? SimpleCalc(),
  advisors,
  beanName: beanName,
  beanAliases: aliases,
) as Calc;

bool matches(
  String expression,
  MethodSignature signature, {
  Map<String, AdviceBinding> bindings = const {},
  Map<String, String> named = const {},
  String? owner,
  String bean = 'calc',
}) => ExpressionPointcut(
  expression,
  bindings: bindings,
  namedPointcuts: named,
  owner: owner,
).matches(signature, bean);

class Recorder {
  Recorder(this.name);
  final String name;
  void record(String text) => log.add('$name:$text');
}

class OrderedRecorder extends Recorder implements Ordered {
  OrderedRecorder() : super('ordered');

  @override
  int get order => 1;
}

BeanDefinition<SimpleCalc> calcBean({
  String name = 'calc',
  List<String> aliases = const [],
  Set<String> qualifiers = const {},
}) => BeanDefinition<SimpleCalc>(
  name: name,
  aliases: aliases,
  qualifiers: qualifiers,
  types: const [SimpleCalc, Base, Calc],
  aopProxy: calcFactory,
  create: (_) => SimpleCalc(),
);

BeanDefinition<Recorder> aspectBean(
  String name, {
  required String typeName,
  Map<String, String> pointcuts = const {},
  required List<(AdviceKind, String)> advice,
  int? order,
  Recorder Function()? create,
  List<Type>? types,
}) => BeanDefinition<Recorder>(
  name: name,
  order: order,
  types: types,
  create: (_) => create?.call() ?? Recorder(name),
  aspect: AspectMetadata<Recorder>(
    typeName: typeName,
    pointcuts: pointcuts,
    advice: [
      for (final (kind, pointcut) in advice)
        AspectAdvice<Recorder>(
          kind: kind,
          pointcut: pointcut,
          methodName: kind.name,
          invoke: (aspect, joinPoint, _, _) {
            aspect.record('${kind.name} ${joinPoint.signature.name}');
            return kind == AdviceKind.around
                ? (joinPoint as ProceedingJoinPoint).proceed()
                : null;
          },
        ),
    ],
  ),
);

AnnotationConfigApplicationContext context(
  List<BeanDefinition<Object>> beans, {
  ApplicationContext? parent,
}) => AnnotationConfigApplicationContext(
  [BeanModule('test', beans)],
  parent: parent,
  environment: StandardEnvironment(systemEnvironment: {}),
)..refresh();

class _Tag implements MethodInterceptor {
  _Tag(this.tag);
  final String tag;

  @override
  Object? invoke(MethodInvocation invocation) {
    log.add('$tag ${invocation.signature.name}');
    return invocation.proceed();
  }
}

class _PlainAdvisor implements Advisor {
  @override
  MethodInterceptor get advice => _Tag('plain');
}

class _SeesProxy extends BeanPostProcessor implements Ordered {
  _SeesProxy(this.tag);
  final String tag;

  @override
  int get order => 0;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (beanName == 'calc') {
      log.add('$tag sees ${bean is Advised ? 'proxy' : 'bean'}');
    }
    return bean;
  }
}

class _SeesRaw extends _SeesProxy implements PriorityOrdered {
  _SeesRaw() : super('priority');
}

void main() {
  setUp(log.clear);
  final add = calcSignatures[0];
  final echo = calcSignatures[4];
  final reset = calcSignatures[3];

  group('designators', () {
    test('Type+ matches the type and its subtypes', () {
      expect(matches('within(Base+)', add), isTrue);
      expect(matches('within(Base)', add), isFalse);
      expect(matches('within(Calc+)', add), isTrue);
      expect(matches('within(com.example.Base+)', add), isTrue);
      expect(matches('within(*Calc+)', add), isTrue);
      expect(matches('within(Other+)', add), isFalse);
      expect(matches('execution(* Base+.add(..))', add), isTrue);
      expect(matches('execution(* Base.add(..))', add), isFalse);
      expect(matches('execution(* Other+.*(..))', add), isFalse);
      expect(
        () => matches('within(com.example..*+)', add),
        throwsFormatException,
      );
    });

    test('@target matches annotations of the bean class', () {
      expect(matches('@target(Audited)', add), isTrue);
      expect(matches('@target(Timed)', add), isFalse);
    });

    test('args matches the declared parameter types', () {
      expect(matches('args(int, int)', add), isTrue);
      expect(matches('args(int)', add), isFalse);
      expect(matches('args(int, ..)', add), isTrue);
      expect(matches('args(.., int)', add), isTrue);
      expect(matches('args(String, ..)', add), isFalse);
      expect(matches('args(..)', add), isTrue);
      expect(matches('args()', reset), isTrue);
      expect(matches('args()', add), isFalse);
      expect(matches('args(Map<String, int>)', add), isFalse);
      expect(matches('execution(* *(Map<String, int>, ..))', add), isFalse);
    });

    test('bean() also matches aliases and qualifier values', () {
      final pointcut = ExpressionPointcut('bean(fast*)');
      expect(pointcut.matches(add, 'calc'), isFalse);
      expect(pointcut.matchesBean(add, 'calc', ['fastCalc']), isTrue);
      expect(
        proxy(
          [advice(AdviceKind.before, 'bean(fast*)', (_, _, _) => log.add('b'))],
          aliases: ['fastCalc'],
        ).add(1, 2),
        3,
      );
      expect(log, ['b']);
    });

    test('bean() aliases and qualifiers through the context', () {
      final app = context([
        calcBean(aliases: ['calculator'], qualifiers: {'fast'}),
        aspectBean(
          'byAlias',
          typeName: 'ByAlias',
          advice: [(AdviceKind.before, 'bean(calculator)')],
        ),
        aspectBean(
          'byQualifier',
          typeName: 'ByQualifier',
          advice: [(AdviceKind.before, 'bean(fast)')],
        ),
      ]);
      app.getBean<Calc>().add(1, 2);
      expect(log, ['byAlias:before add', 'byQualifier:before add']);
      app.close();
    });
  });

  group('argument binding', () {
    test('@annotation(timed) binds the annotation', () {
      final bindings = {'timed': binding<Timed>('Timed')};
      final pointcut = ExpressionPointcut(
        '@annotation(timed)',
        bindings: bindings,
      );
      expect(pointcut.isRuntime, isTrue);
      expect(pointcut.matches(add, 'calc'), isTrue);
      expect(pointcut.matches(echo, 'calc'), isFalse);
      final calc = proxy([
        advice(AdviceKind.around, '@annotation(timed)', (jp, _, bound) {
          log.add('timed ${(bound['timed']! as Timed).label}');
          return (jp as ProceedingJoinPoint).proceed();
        }, bindings: bindings),
      ]);
      expect(calc.add(1, 2), 3);
      expect(calc.echo('x'), 'x');
      expect(log, ['timed add']);
    });

    test('@within and @target bind the class annotation', () {
      for (final designator in ['@within', '@target']) {
        log.clear();
        final calc = proxy([
          advice(
            AdviceKind.before,
            '$designator(audited) && execution(* echo(..))',
            (_, _, bound) => log.add('${bound['audited']}'),
            bindings: {'audited': binding<Audited>('Audited')},
          ),
        ]);
        calc.echo(1);
        expect(log, ["Instance of 'Audited'"], reason: designator);
      }
    });

    test('this and target bind the proxy and the bean', () {
      final target = SimpleCalc();
      late Calc calc;
      calc = proxy(target: target, [
        advice(
          AdviceKind.before,
          'execution(* add(..)) && this(self) && target(bean)',
          (_, _, bound) => log.add(
            '${identical(bound['self'], calc)} '
            '${identical(bound['bean'], target)}',
          ),
          bindings: {
            'self': binding<Calc>('Calc'),
            'bean': binding<SimpleCalc>('SimpleCalc'),
          },
        ),
      ]);
      calc.add(1, 2);
      expect(log, ['true true']);
      // A type the bean does not have: no static match.
      expect(
        matches(
          'this(other)',
          add,
          bindings: {'other': binding<Counter>('Counter')},
        ),
        isFalse,
      );
    });

    test('args binds arguments and checks their runtime type', () {
      final calc = proxy([
        advice(
          AdviceKind.before,
          'execution(* echo(..)) && args(text)',
          (_, _, bound) => log.add('text ${bound['text']}'),
          bindings: {'text': binding<String>('String')},
        ),
        advice(
          AdviceKind.before,
          'args(.., last)',
          (_, _, bound) => log.add('last ${bound['last']}'),
          bindings: {'last': binding<int>('int')},
        ),
      ]);
      calc.echo('x');
      expect(log, ['text x']);
      log.clear();
      calc.echo(42);
      expect(log, ['last 42'], reason: 'echo(Object) called with an int');
      log.clear();
      calc.add(1, 2);
      expect(log, ['last 2']);

      // A plain interceptor with such a pointcut is decided per call too.
      log.clear();
      final plain = proxy([
        DefaultPointcutAdvisor(
          ExpressionPointcut(
            'args(text)',
            bindings: {'text': binding<String>('String')},
          ),
          _Tag('dynamic'),
        ),
      ]);
      plain
        ..echo('x')
        ..echo(1);
      expect(log, ['dynamic echo']);
    });

    test('bindings under ! and || are decided per call', () {
      final bindings = {'text': binding<String>('String')};
      // Statically undecidable: assumed to match.
      expect(matches('!args(text)', echo, bindings: bindings), isTrue);
      final calc = proxy([
        advice(
          AdviceKind.before,
          'execution(* echo(..)) && !args(text)',
          (_, _, bound) => log.add('not text $bound'),
          bindings: bindings,
        ),
        advice(
          AdviceKind.before,
          'execution(* echo(..)) && (args(text) || bean(calc))',
          (_, _, bound) => log.add('either $bound'),
          bindings: bindings,
        ),
      ]);
      calc.echo('x');
      expect(log, ['either {text: x}']);
      log.clear();
      calc.echo(1);
      expect(log, ['not text {}', 'either {}']);
    });

    test('lower-case names that are no parameters are still rejected', () {
      expect(
        () => ExpressionPointcut('@annotation(timed)'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("needs an advice parameter named 'timed'"),
          ),
        ),
      );
      expect(() => ExpressionPointcut('@args(Timed)'), throwsFormatException);
    });
  });

  group('named pointcuts per aspect', () {
    test('owner scope, qualified references and holder classes', () {
      final named = {
        'A.p': 'bean(a)',
        'B.p': 'bean(b)',
        'Common.web': 'inWeb()',
        'Common.inWeb': 'bean(web*)',
        'A.inWeb': 'bean(nothing)',
        'shared': 'bean(shared)',
      };
      expect(matches('p()', add, named: named, owner: 'A', bean: 'a'), isTrue);
      expect(matches('p()', add, named: named, owner: 'A', bean: 'b'), isFalse);
      expect(matches('p()', add, named: named, owner: 'B', bean: 'b'), isTrue);
      expect(
        matches('B.p()', add, named: named, owner: 'A', bean: 'b'),
        isTrue,
      );
      expect(
        matches('com.x.B.p()', add, named: named, owner: 'A', bean: 'b'),
        isTrue,
      );
      // `inWeb()` inside Common.web is Common's, not A's.
      expect(
        matches('Common.web()', add, named: named, owner: 'A', bean: 'web1'),
        isTrue,
      );
      // Unqualified entries remain visible to every owner.
      expect(
        matches('shared()', add, named: named, owner: 'A', bean: 'shared'),
        isTrue,
      );
      expect(
        () => matches('q()', add, named: named, owner: 'A'),
        throwsFormatException,
      );
      expect(
        () => matches('C.p()', add, named: named, owner: 'A'),
        throwsFormatException,
      );
    });

    test('each aspect resolves its own pointcuts through the context', () {
      final app = context([
        calcBean(),
        aspectBean(
          'first',
          typeName: 'FirstAspect',
          pointcuts: {'ops': 'execution(* add(..))'},
          advice: [(AdviceKind.before, 'ops()')],
          order: 1,
        ),
        aspectBean(
          'second',
          typeName: 'SecondAspect',
          pointcuts: {
            'ops': 'execution(* echo(..))',
            // A holder class's pointcuts, listed by the generator.
            'Pointcuts.resets': 'execution(* reset(..))',
          },
          advice: [
            (AdviceKind.before, 'ops()'),
            (AdviceKind.after, 'FirstAspect.ops()'),
            (AdviceKind.afterReturning, 'Pointcuts.resets()'),
          ],
          order: 2,
        ),
      ]);
      final calc = app.getBean<Calc>();
      calc.add(1, 2);
      expect(log, ['first:before add', 'second:after add']);
      log.clear();
      calc.echo(1);
      expect(log, ['second:before echo']);
      log.clear();
      calc.reset();
      expect(log, ['second:afterReturning reset']);
      app.close();
    });

    test('an unqualified reference does not reach another aspect', () {
      expect(
        () => context([
          calcBean(),
          aspectBean(
            'first',
            typeName: 'FirstAspect',
            pointcuts: {'onlyFirst': 'execution(* add(..))'},
            advice: const [],
          ),
          aspectBean(
            'second',
            typeName: 'SecondAspect',
            advice: [(AdviceKind.before, 'onlyFirst()')],
          ),
        ]),
        throwsA(
          isA<BeanCreationException>().having(
            (e) => '${e.cause}',
            'cause',
            contains("unknown pointcut 'onlyFirst'"),
          ),
        ),
      );
    });
  });

  group('subclass proxies', () {
    final next = AspectAdvice<Recorder>(
      kind: AdviceKind.before,
      pointcut: 'execution(* next(..))',
      methodName: 'before',
      invoke: (aspect, joinPoint, _, _) {
        aspect.record('before ${joinPoint.signature.name}');
        return null;
      },
    );

    test('advice is attached to the generated subclass instance', () {
      final app = context([
        BeanDefinition<Counter>(
          name: 'counter',
          types: const [Counter],
          aopProxy: counterFactory,
          create: (_) => _$CounterProxy(),
        ),
        BeanDefinition<Recorder>(
          name: 'recorder',
          create: (_) => Recorder('r'),
          aspect: AspectMetadata<Recorder>(advice: [next]),
        ),
      ]);
      final counter = app.getBean<Counter>();
      expect(counter, isA<_$CounterProxy>());
      expect(counterFactory.isSubclass, isTrue);
      expect(AopUtils.isAopProxy(counter), isTrue);
      expect(AopUtils.getTarget(counter), same(counter));
      expect(counter.next(), 1);
      expect(counter.next(), 2);
      expect(log, ['r:before next', 'r:before next']);
      app.close();
    });

    test('without matching advice the instance is not a proxy', () {
      final app = context([
        BeanDefinition<Counter>(
          name: 'counter',
          aopProxy: counterFactory,
          create: (_) => _$CounterProxy(),
        ),
        BeanDefinition<Recorder>(
          name: 'recorder',
          create: (_) => Recorder('r'),
          aspect: AspectMetadata<Recorder>(
            advice: [
              AspectAdvice<Recorder>(
                kind: AdviceKind.before,
                pointcut: 'bean(nothing)',
                methodName: 'before',
                invoke: (_, _, _, _) => null,
              ),
            ],
          ),
        ),
      ]);
      final counter = app.getBean<Counter>();
      expect(AopUtils.isAopProxy(counter), isFalse);
      expect(counter.next(), 1);
      app.close();
    });

    test('createProxy returns the same object; a replaced bean fails', () {
      final advisor = DefaultPointcutAdvisor(const TruePointcut(), _Tag('t'));
      final raw = _$CounterProxy();
      expect(counterFactory.createProxy(raw, [advisor]), same(raw));
      expect(raw.next(), 1);
      expect(log, ['t next']);
      expect(
        () => counterFactory.createProxy(Counter(), [
          advisor,
        ], beanName: 'counter'),
        throwsA(
          isA<AopConfigException>().having(
            (e) => e.message,
            'message',
            allOf(contains("'counter'"), contains('replaced')),
          ),
        ),
      );
    });
  });

  group('invocation', () {
    test(
      'FutureOr members: after advice on the value or on completion',
      () async {
        final calc = proxy([
          advice(
            AdviceKind.afterReturning,
            'execution(* maybe(..))',
            (_, value, _) => log.add('returned $value'),
          ),
        ]);
        final sync = calc.maybe(1);
        expect(sync, 1);
        expect(log, ['returned 1']);
        log.clear();
        final async = calc.maybe(2);
        expect(async, isA<Future<int>>());
        expect(log, isEmpty);
        expect(await async, 2);
        expect(log, ['returned 2']);
      },
    );

    test(
      'AopContext.currentProxy() in synchronous and asynchronous calls',
      () async {
        expect(AopContext.currentProxy, throwsStateError);
        final factory = AopProxyFactory(
          signatures: _$SelfieProxy.signatures,
          create: (target, invoker) => _$SelfieProxy(target as Selfie, invoker),
        );
        final selfie = factory.createProxy(Selfie(), [
          DefaultPointcutAdvisor(const TruePointcut(), _Tag('t')),
        ]) as Selfie;
        expect(selfie.who(), same(selfie));
        expect(await selfie.whoLater(), same(selfie));
        expect(AopContext.currentProxy, throwsStateError);
        // Not advised, still called through the proxy.
        final bare = factory.createProxy(Selfie(), const []) as Selfie;
        expect(bare.who(), same(bare));
      },
    );

    test('advice gets a copy of the arguments; proceed checks their count', () {
      final calc = proxy([
        advice(AdviceKind.before, 'execution(* add(..))', (jp, _, _) {
          jp.args[0] = 99;
          log.add('${jp.args}');
          return null;
        }),
      ]);
      expect(calc.add(1, 2), 3);
      expect(log, ['[99, 2]']);

      final wrong = proxy([
        advice(
          AdviceKind.around,
          'execution(* add(..))',
          (jp, _, _) => (jp as ProceedingJoinPoint).proceed([1]),
        ),
      ]);
      expect(
        () => wrong.add(1, 2),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Expecting 2 arguments to proceed, but was passed 1 arguments',
          ),
        ),
      );
    });

    test('plain interceptors still change the live arguments', () {
      final calc = proxy([
        DefaultPointcutAdvisor(
          ExpressionPointcut('execution(* add(..))'),
          _Mutate(),
        ),
      ]);
      expect(calc.add(1, 2), 12);
    });

    test('async before advice is waited for on asynchronous members', () async {
      final target = SimpleCalc();
      final gate = Completer<void>();
      final calc = proxy(target: target, [
        advice(AdviceKind.before, 'execution(* later(..))', (_, _, _) {
          log.add('before');
          return gate.future;
        }),
        advice(AdviceKind.afterReturning, 'execution(* later(..))', (
          _,
          value,
          _,
        ) async {
          await Future<void>.delayed(Duration.zero);
          log.add('returned $value');
          return null;
        }),
      ]);
      final result = calc.later(1);
      expect(result, isA<Future<int>>());
      await Future<void>.delayed(Duration.zero);
      expect(target.calls, isEmpty, reason: 'waits for the advice');
      gate.complete();
      expect(await result, 10);
      expect(target.calls, ['later']);
      expect(log, ['before', 'returned 10']);
    });

    test(
      'async advice on a FutureOr member makes the result a Future',
      () async {
        final calc = proxy([
          advice(
            AdviceKind.before,
            'execution(* maybe(..))',
            (_, _, _) => Future<void>.value(),
          ),
        ]);
        final result = calc.maybe(1);
        expect(result, isA<Future<int>>());
        expect(await result, 1);
      },
    );

    test('async advice on a synchronous member fails fast', () {
      final target = SimpleCalc();
      final calc = proxy(target: target, [
        advice(
          AdviceKind.before,
          'execution(* add(..))',
          (_, _, _) => Future<void>.value(),
        ),
        advice(
          AdviceKind.after,
          'execution(* reset(..))',
          (_, _, _) => Future<void>.value(),
        ),
      ]);
      expect(
        () => calc.add(1, 2),
        throwsA(
          isA<AopInvocationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('returned a Future'), contains('Calc.add')),
          ),
        ),
      );
      expect(() => calc.reset(), throwsA(isA<AopInvocationException>()));
      expect(target.calls, ['reset'], reason: 'after advice runs after it');
    });

    test('a Future method throwing synchronously', () {
      // In the order the proxy creator sorts advice of one aspect.
      final calc = proxy([
        advice(
          AdviceKind.after,
          'execution(* failFast(..))',
          (_, _, _) => log.add('after'),
        ),
        advice(
          AdviceKind.afterReturning,
          'execution(* failFast(..))',
          (_, value, _) => log.add('returned $value'),
        ),
        advice(
          AdviceKind.afterThrowing,
          'execution(* failFast(..))',
          (_, error, _) => log.add('threw $error'),
        ),
      ]);
      // Like the bean itself: the error is thrown synchronously.
      expect(() => SimpleCalc().failFast(-1), throwsStateError);
      expect(() => calc.failFast(-1), throwsStateError);
      expect(log, ['threw Bad state: sync', 'after']);
    });

    test('returning / throwing name the value parameter', () {
      expect(
        const AfterReturning('p()', returning: 'result').returning,
        'result',
      );
      expect(const AfterReturning('p()').returning, isNull);
      expect(const AfterThrowing('p()', throwing: 'error').throwing, 'error');
    });
  });

  group('auto proxy creator', () {
    test('an aspect implementing Ordered is ordered by its order', () {
      final app = context([
        calcBean(),
        aspectBean(
          'annotated',
          typeName: 'Annotated',
          advice: [(AdviceKind.before, 'execution(* add(..))')],
          order: 2,
        ),
        aspectBean(
          'ordered',
          typeName: 'OrderedRecorder',
          advice: [(AdviceKind.before, 'execution(* add(..))')],
          // `@Order(5)` loses against `Ordered.order` (1).
          order: 5,
          create: OrderedRecorder.new,
          types: const [OrderedRecorder, Recorder, Ordered],
        ),
      ]);
      app.getBean<Calc>().add(1, 2);
      expect(log, ['ordered:before add', 'annotated:before add']);
      app.close();
    });

    test('a plain Advisor bean applies to every member', () {
      final app = context([
        calcBean(),
        BeanDefinition<_PlainAdvisor>(
          name: 'plain',
          types: const [_PlainAdvisor, Advisor],
          create: (_) => _PlainAdvisor(),
        ),
      ]);
      final calc = app.getBean<Calc>();
      calc.add(1, 2);
      calc.echo(1);
      expect(log, ['plain add', 'plain echo']);
      app.close();
    });

    test('an advisor bean that depends on a proxied bean', () {
      final app = context([
        calcBean(),
        // Created while `calc` is being created: it cannot advise `calc`
        // (Spring skips it the same way), but advises later beans.
        BeanDefinition<DefaultPointcutAdvisor>(
          name: 'needsCalc',
          types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor],
          dependencies: const [Dependency(Calc, qualifier: 'calc')],
          create: (r) {
            r.dependency<Calc>(qualifier: 'calc');
            return DefaultPointcutAdvisor(
              ExpressionPointcut('execution(* add(..))'),
              _Tag('needsCalc'),
            );
          },
        ),
        aspectBean(
          'aspect',
          typeName: 'Aspect',
          advice: [(AdviceKind.before, 'execution(* echo(..))')],
        ),
        calcBean(name: 'later'),
      ]);
      app.getBean<Calc>(qualifier: 'calc')
        ..add(1, 2)
        ..echo(1);
      expect(log, ['aspect:before echo']);
      log.clear();
      app.getBean<Calc>(qualifier: 'later').add(1, 2);
      expect(log, ['needsCalc add']);
      app.close();
    });

    test('aspects and advisors of ancestor contexts apply', () {
      final parent = context([
        aspectBean(
          'parentAspect',
          typeName: 'ParentAspect',
          pointcuts: {'adds': 'execution(* add(..))'},
          advice: [(AdviceKind.before, 'adds()')],
        ),
        BeanDefinition<DefaultPointcutAdvisor>(
          name: 'parentAdvisor',
          types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor],
          create: (_) => DefaultPointcutAdvisor(
            ExpressionPointcut('execution(* echo(..))'),
            _Tag('parentAdvisor'),
          ),
        ),
      ]);
      final child = context([calcBean()], parent: parent);
      expect(AspectAutoProxyCreator.isRequiredFor(child.beanFactory), isTrue);
      final calc = child.getBean<Calc>();
      calc
        ..add(1, 2)
        ..echo(1);
      expect(log, ['parentAspect:before add', 'parentAdvisor echo']);
      child.close();
      parent.close();
    });

    test('runs after PriorityOrdered and before Ordered post-processors', () {
      final app = context([
        calcBean(),
        aspectBean(
          'aspect',
          typeName: 'Aspect',
          advice: [(AdviceKind.before, 'execution(* add(..))')],
        ),
        BeanDefinition<_SeesProxy>(
          name: 'ordered',
          types: const [_SeesProxy, BeanPostProcessor, Ordered],
          create: (_) => _SeesProxy('ordered'),
        ),
        BeanDefinition<_SeesRaw>(
          name: 'priority',
          types: const [
            _SeesRaw,
            _SeesProxy,
            BeanPostProcessor,
            PriorityOrdered,
            Ordered,
          ],
          create: (_) => _SeesRaw(),
        ),
      ]);
      expect(log, ['priority sees bean', 'ordered sees proxy']);
      final processors = (app.beanFactory as DefaultListableBeanFactory)
          .beanPostProcessors
          .map((p) => p.runtimeType.toString())
          .toList();
      expect(
        processors.indexOf('AspectAutoProxyCreator'),
        allOf(
          greaterThan(processors.indexOf('_SeesRaw')),
          lessThan(processors.indexOf('_SeesProxy')),
        ),
      );
      app.close();
    });
  });
}

class _Mutate implements MethodInterceptor {
  @override
  Object? invoke(MethodInvocation invocation) {
    invocation.args[0] = 10;
    return invocation.proceed();
  }
}
