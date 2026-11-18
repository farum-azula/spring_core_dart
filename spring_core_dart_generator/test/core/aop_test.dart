// AOP in the main builder's output: pointcuts and their validation,
// proxy pruning, subclass proxies, argument binding, the proxies' members.
import 'package:build/build.dart';
import 'package:spring_core_dart_generator/builder.dart';
import 'package:spring_core_dart_generator/src/core/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/spring_builder.dart';
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  test('a bean that cannot be proxied keeps its signatures and '
      'the reason', () async {
    final output = await generateModule('''
class Counter {
  int _n = 0;
  @Timed()
  int next() => _n++;
}

class Timed {
  const Timed();
}

@Configuration()
class Config {
  @Bean()
  Counter counter() => Counter();
}
''', proxyMode: ProxyMode.all);
    expect(output, isNot(contains(r'class_$Config_counterProxy')));
    expect(output, hasCode('aopProxy: AopProxyFactory.unavailable('));
    expect(output, hasCode("MethodSignature.of(r'next',"));
    expect(output, hasCode("annotationTypes: [r'Timed']"));
    expect(
      output,
      hasCode(
        "reason: r'Counter cannot be implemented by a generated class (it has "
        'private members, or is final, base or sealed) and implements no '
        'interface. Add an interface with the advised methods and inject the '
        "bean by it, or make its members public.')",
      ),
    );
  });

  group('pointcut validation and pruning', () {
    const header = '''
class Timed {
  const Timed();
}

@Service()
class Orders {
  void place() {}
}

@Service()
class Mail {
  void send() {}
}

@Service()
class Slow {
  @Timed()
  void run() {}
}
''';

    Future<String> generate(String aspect, {bool prune = true}) =>
        generateApplication(
          '$header\n@Aspect() @Component() class A { $aspect }',
          prune: prune,
        );

    test('a syntax error fails the build with the position', () async {
      await expectBuildError(
        "$header\n@Aspect() @Component() class A { @Before('execution(* *(..)) "
            "&&') void b() {} }",
        'is invalid: Invalid pointcut (unexpected end of expression) at '
            "character 21 of 'execution(* *(..)) &&'",
        proxyMode: ProxyMode.all,
      );
      await expectBuildError(
        "$header\n@Aspect() @Component() class A { @Before('within(Orders) && "
            "frobnicate(Mail)') void b() {} }",
        "unknown designator 'frobnicate') at character 18",
        proxyMode: ProxyMode.all,
      );
      await expectBuildError(
        "$header\n@Aspect() @Component() class A { @Before('execution(* "
            "*(..))') void b() {} "
            "@Pointcut('execution(String)') void bad() {} }",
        'The @Pointcut A.bad is invalid',
        proxyMode: ProxyMode.all,
      );
      // Also without proxies: the expression is wrong either way.
      await expectBuildError(
        "$header\n@Aspect() @Component() class A { @Before('bean(') void b() "
            '{} }',
        'is invalid',
      );
    });

    test(
      'a reference to a pointcut of another class is left to the runtime',
      () async {
        final output = await generate("@Before('Common.web()') void b() {}");
        expect(output, contains(r'_$OrdersProxy'));
      },
    );

    test('beans no pointcut matches get no proxy class', () async {
      final output = await generate(
        "@Before('execution(* Orders.*(..))') void b() {}",
      );
      expect(output, contains(r'class_$OrdersProxy'));
      expect(output, isNot(contains(r'_$MailProxy')));
      // Nothing is generated for its members; the runtime says why.
      expect(
        output,
        matches(
          RegExp(
            r'BeanDefinition<Mail>\((?:(?!BeanDefinition<).)*'
            r'AopProxyFactory\.pruned\(knownAdvisors:_\$knownAdvisors\d+,?\)',
          ),
        ),
      );
    });

    test('annotation, within and name pointcuts', () async {
      final annotation = await generate(
        "@Before('@annotation(Timed)') void b() {}",
      );
      // `@Timed` is no stereotype: a starter's advisor may match by it.
      expect(annotation, contains(r'class_$SlowProxy'));
      expect(annotation, isNot(contains(r'_$OrdersProxy')));
      final within = await generate("@Before('within(Mail)') void b() {}");
      expect(within, contains(r'class_$MailProxy'));
      expect(within, isNot(contains(r'_$OrdersProxy')));
      final byName = await generate("@Before('bean(orders)') void b() {}");
      expect(byName, contains(r'class_$OrdersProxy'));
      expect(byName, isNot(contains(r'_$MailProxy')));
      // A negation matches a lot: everything else keeps its proxy.
      final all = await generate("@Before('!within(Mail)') void b() {}");
      expect(all, contains(r'class_$OrdersProxy'));
      expect(all, contains(r'class_$SlowProxy'));
    });

    test('nothing advises: no proxy class at all', () async {
      // The build reads the advisors of the auto-configurations: with no
      // aspect and none of their annotations, nothing is advised.
      final none = await generateApplication(header);
      expect(none, isNot(contains(r'class_$MailProxy')));
      expect(none, isNot(contains(r'class_$OrdersProxy')));
    });

    test('in doubt, every bean keeps its proxy', () async {
      final everything = await generate(
        "@Before('execution(* Orders.*(..))') void b() {}",
        prune: false,
      );
      expect(everything, contains(r'class_$MailProxy'));
      // A @ComponentScan module may be imported by any other module, whose
      // aspects the build cannot see: it is never pruned.
      final module = await generateModule(
        '$header\n@Aspect() @Component() class A { '
        "@Before('execution(* Orders.*(..))') void b() {} }",
        proxyMode: ProxyMode.all,
      );
      expect(module, contains(r'class_$MailProxy'));
      // An advisor bean of the module may match anything.
      final advisor = await generateApplication("""
$header
@Aspect() @Component() class A { @Before('execution(* Orders.*(..))') void b() {} }
@Component() class Custom extends DefaultPointcutAdvisor {
  Custom() : super(const TruePointcut(), const _Noop());
}
class _Noop implements MethodInterceptor {
  const _Noop();
  @override
  Object? invoke(MethodInvocation invocation) => invocation.proceed();
}
""");
      expect(advisor, contains(r'class_$MailProxy'));
      // A starter's annotation-driven advisor (`@Cacheable`) matches the
      // beans carrying its annotations; a look-alike of the application's
      // own advises nothing.
      final starter = await generateApplication("""
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart' as cache;
$header
class Cacheable { const Cacheable(); }
@Service() class Cached { @cache.Cacheable('c') int get(int id) => id; }
@Service() class LookAlike { @Cacheable() void get() {} }
@Aspect() @Component() class A { @Before('execution(* Orders.*(..))') void b() {} }
""");
      expect(starter, contains(r'class_$CachedProxy'));
      expect(starter, isNot(contains(r'_$LookAlikeProxy')));
      expect(starter, isNot(contains(r'_$MailProxy')));
    });
  });

  group('subclass proxies', () {
    const counter = '''
class Counter {
  Counter(this.step, {this.name = 'n'});
  final int step;
  final String name;
  int _n = 0;
  int next() => _n += step;
  void reset() {
    _n = 0;
  }
  Future<int> later() async => _n;
  Duration wait([Duration d = const Duration(seconds: 1)]) => d;
  int get count => _n;
  set count(int value) {
    _n = value;
  }
  Counter operator +(Counter other) => this;
}
''';

    test('a component with private members and no interface', () async {
      final output = await generateModule(
        '@Component() $counter',
        proxyMode: ProxyMode.all,
      );
      // AdvisedSubclass holds the invoker and implements Advised.
      expect(
        output,
        hasCode(r'class _$CounterProxy extends Counter with AdvisedSubclass {'),
      );
      expect(output, hasCode(r'_$CounterProxy(super.p0, {super.name});'));
      expect(
        output,
        hasCode(
          r'int next() { final _$i = this.aopInvoker; return _$i == null ? '
          r'super.next() : (_$i.invoke(this, this, 0, const [], (args) => '
          'super.next()) as int); '
          '}',
        ),
      );
      expect(
        output,
        hasCode(
          r'void reset() { final _$i = this.aopInvoker; if (_$i == null) { '
          r'super.reset(); } else { _$i.invoke(this, this, 1, const [], (args) '
          '{ super.reset(); return null; }); } '
          '}',
        ),
      );
      expect(output, hasCode(r'Future<int> later() { final _$i'));
      expect(
        output,
        hasCode(
          r'_$i.invokeAsync<int>(this, this, 2, const [], (args) => '
          'super.later())',
        ),
      );
      // A constant default value is re-created, like an annotation.
      expect(
        output,
        hasCode('Duration wait([Duration d = const Duration(seconds: 1)])'),
      );
      expect(output, hasCode('super.wait((args[0] as Duration))'));
      expect(
        output,
        hasCode(
          r'int get count { final _$i = this.aopInvoker; return _$i == null ? '
          r'super.count : (_$i.invoke(',
        ),
      );
      expect(output, hasCode(r'set count(int value) { final _$i'));
      expect(output, hasCode('super.count = value;'));
      expect(
        output,
        isNot(contains('operator')),
        reason: 'operators are inherited',
      );
      expect(output, isNot(contains('toString')));
      expect(
        output,
        hasCode(
          'aopProxy: AopProxyFactory.subclass(signatures: const '
          '[MethodSignature.of(',
        ),
      );
      expect(
        output,
        hasCode(
          r'advise: (bean, invoker) => bean is _$CounterProxy ? '
          '(bean..aopInvoker = invoker) : null',
        ),
      );
      expect(output, hasCode(r'create: (r) => _$CounterProxy('));
    });

    test('a named constructor and a base class', () async {
      final output = await generateModule('''
@Component()
class Named {
  @Autowired()
  Named.create([int size = 1]) : _size = size;
  final int _size;
  int size() => _size;
}

@Component()
base class Guarded {
  int _n = 0;
  int tick() => ++_n;
}
''', proxyMode: ProxyMode.all);
      expect(output, hasCode(r'_$NamedProxy([super.p0]) : super.create();'));
      expect(
        output,
        hasCode(
          r'final class _$GuardedProxy extends Guarded with AdvisedSubclass',
        ),
      );
      expect(
        output,
        hasCode(r'create: (r) => _$NamedProxy(r.optionalDependency<int>'),
      );
    });

    test('the generated code compiles', () async {
      expect(
        await compileErrors({
          'lib/src/service.dart':
              '''
@Component() $counter
@Component()
class Named {
  @Autowired()
  Named.create([int size = 1]) : _size = size;
  final int _size;
  int size() => _size;
}
@Component()
base class Guarded {
  int _n = 0;
  int tick() => ++_n;
}
''',
        }),
        isEmpty,
      );
    });

    test('a class that cannot be extended keeps only its signatures '
        '(AopProxyFactory.unavailable: fails at startup only when advice '
        'matches)', () async {
      final locked = await generateModule(
        '@Component() final class Locked { int _n = 0; int next() => _n++; }',
        proxyMode: ProxyMode.all,
      );
      expect(locked, hasCode('aopProxy: AopProxyFactory.unavailable('));
      expect(
        locked,
        hasCode(
          'Locked cannot be implemented by a generated class (it has private '
          'members, or is final, base or sealed) and implements no '
          'interface.',
        ),
      );
      expect(
        locked,
        hasCode(
          'because Locked cannot be extended (it is final). Remove `final`, '
          'or add an interface with the advised methods and inject the bean '
          'by it.',
        ),
      );
      expect(
        await generateModule(
          '@Component() interface class Api { int _n = 0; int next() => _n++; '
          '}',
          proxyMode: ProxyMode.all,
        ),
        hasCode('Api cannot be extended (it is interface). Remove `interface`'),
      );
      expect(
        await generateModule(
          '@Component() class Made { Made._(); factory Made() => Made._(); '
          'int _n = 0; int next() => _n++; }',
          proxyMode: ProxyMode.all,
        ),
        hasCode('is created through the factory constructor'),
      );
      // Only `all` generates subclass proxies: `interfaces` keeps the
      // signatures and fails at startup when advice matches.
      final output = await generateModule(
        '@Component() final class Locked { int _n = 0; int next() => _n++; }',
        proxyMode: ProxyMode.interfaces,
      );
      expect(output, hasCode('aopProxy: AopProxyFactory.unavailable('));
    });

    test('a @Bean method type cannot get a subclass proxy', () async {
      final output = await generateModule('''
$counter
@Configuration()
class Config {
  @Bean()
  Counter counter() => Counter(1);
}
''', proxyMode: ProxyMode.all);
      expect(output, isNot(contains('extends Counter')));
      expect(output, hasCode('aopProxy: AopProxyFactory.unavailable('));
    });
  });

  group('argument binding', () {
    test('bound parameters are read from the bindings map', () async {
      final output = await generateModule('''
class Timed {
  const Timed();
}

@Service()
class Svc {
  @Timed()
  int find(int id) => id;
}

@Aspect()
@Component()
class Audit {
  @Pointcut('args(id, ..)')
  void withId() {}

  @Before('@annotation(timed) && withId()')
  void tagged(JoinPoint jp, Timed timed, int id) {}

  @AfterReturning('withId() && this(proxy) && target(bean)', returning: 'result')
  void returned(int result, Svc bean, Object proxy, int id) {}

  @AfterThrowing('@within(timed)', throwing: 'error')
  void failed(Timed timed, StateError error) {}

  @Around('@target(timed) && args(id, ..)')
  Object? around(ProceedingJoinPoint pjp, Timed timed, int? id) => pjp.proceed();
}
''', proxyMode: ProxyMode.all);
      expect(
        output,
        hasCode(
          "aspect.tagged(joinPoint, (bindings[r'timed'] as Timed), "
          "(bindings[r'id'] as int)), "
          "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is "
          'Timed), '
          "r'id': AdviceBinding(r'int', (value) => value is int)}",
        ),
      );
      expect(
        output,
        hasCode(
          "aspect.returned((value as int), (bindings[r'bean'] as Svc), "
          "(bindings[r'proxy'] as Object), (bindings[r'id'] as int)), "
          "bindings: {r'bean': AdviceBinding(r'Svc', (value) => value is Svc), "
          "r'proxy': AdviceBinding(r'Object', (value) => value is Object), "
          "r'id': AdviceBinding(r'int', (value) => value is int)}, "
          'accepts: (value) => value is int',
        ),
      );
      expect(
        output,
        hasCode(
          "aspect.failed((bindings[r'timed'] as Timed), (value as "
          'StateError)), '
          "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is "
          'Timed)}, '
          'accepts: (value) => value is StateError',
        ),
      );
      expect(
        output,
        hasCode(
          'aspect.around((joinPoint as ProceedingJoinPoint), '
          "(bindings[r'timed'] as Timed), (bindings[r'id'] as int?)), "
          "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is "
          'Timed), '
          "r'id': AdviceBinding(r'int', (value) => value is int?)}",
        ),
      );
    });

    test(
      'advice and pointcuts of superclasses and mixins are inherited',
      () async {
        final output = await generateModule('''
class Timed {
  const Timed();
}

abstract class BaseAspect {
  @Pointcut('within(Svc)')
  void svc() {}

  @Before('svc() && @annotation(timed)')
  void inherited(Timed timed) {}

  @After('svc()')
  void overridden() {}
}

mixin Logging {
  @AfterReturning('svc()')
  void logged(Object? result) {}
}

@Aspect()
@Component()
class Child extends BaseAspect with Logging {
  @override
  void overridden() {}

  @Around('svc()')
  Object? own(ProceedingJoinPoint pjp) => pjp.proceed();
}
''');
        expect(
          output,
          hasCode(
            "methodName: r'inherited', invoke: (aspect, joinPoint, value, "
            "bindings) => aspect.inherited((bindings[r'timed'] as Timed)), "
            "bindings: {r'timed': AdviceBinding(r'Timed', (value) => value is "
            'Timed)}',
          ),
        );
        expect(output, hasCode("methodName: r'logged'"));
        expect(output, hasCode("methodName: r'own'"));
        expect(output, hasCode("pointcuts: {r'svc': r'within(Svc)'}"));
        // The override without @After is not advice.
        expect(output, isNot(contains("methodName: r'overridden'")));
      },
    );

    test(
      "a parameter of another class's pointcut is bound at runtime",
      () async {
        final output = await generateModule('''
@Aspect()
@Component()
class Audit {
  @Before('Common.withId()')
  void before(int id) {}
}
''');
        expect(output, hasCode("aspect.before((bindings[r'id'] as int))"));
      },
    );

    test('binding mistakes fail the build', () async {
      await expectBuildError(
        "@Aspect() @Component() class A { @Before('execution(* *(..))') void "
            'b(String s) {} }',
        'Unexpected parameter s of @Before advice b: the pointcut does not '
            'bind it. Bind it with @annotation(s), @within(s), @target(s), '
            'this(s), target(s) or args(s, ..).',
      );
      await expectBuildError(
        "@Aspect() @Component() class A { @AfterReturning('execution(* "
            "*(..))', returning: 'r') void b(Object? r, String s) {} }",
        'or name it in `returning:`.',
      );
      await expectBuildError(
        "@Aspect() @Component() class A { @Before('@annotation(timed)') void "
            'b() {} }',
        "The pointcut of @Before advice b binds 'timed', which is not a "
            'parameter of the advice method. Add a parameter named timed, or '
            'match by type with a type name (starting with an uppercase '
            'letter).',
      );
      await expectBuildError(
        "@Aspect() @Component() class A { @AfterThrowing('x()', throwing: 'e') "
            'void b(Object? error) {} }',
        "@AfterThrowing advice b names the throwing parameter 'e', which it "
            'does not declare.',
      );
    });
  });

  group('AOP', () {
    test('aspect metadata', () async {
      final output = await generateModule('''
class Marker {
  const Marker();
}

@Aspect()
@Component()
class Audit {
  @Pointcut('execution(* *(..))')
  void all() {}

  @Before('all()')
  void before(JoinPoint jp) {}

  @After('all()')
  void after() {}

  @AfterReturning('all()')
  void returned(JoinPoint jp, String result) {}

  @AfterReturning('all()')
  void anyResult(Object? result) {}

  @AfterReturning('all()')
  void someResult(Object result) {}

  @AfterThrowing('all()')
  void failed(StateError error) {}

  @Around('@annotation(Marker)')
  Object? around(ProceedingJoinPoint pjp) => pjp.proceed();
}
''', proxyMode: ProxyMode.all);
      expect(output, hasCode('aspect: AspectMetadata<Audit>('));
      expect(
        output,
        hasCode(
          "kind: AdviceKind.before, pointcut: r'all()', methodName: r'before', "
          'invoke: (aspect, joinPoint, value, bindings) => '
          'aspect.before(joinPoint))',
        ),
      );
      expect(
        output,
        hasCode(
          'invoke: (aspect, joinPoint, value, bindings) => aspect.after()',
        ),
      );
      expect(
        output,
        hasCode(
          'aspect.returned(joinPoint, (value as String)), accepts: (value) => '
          'value is String',
        ),
      );
      expect(output, hasCode('aspect.anyResult((value as Object?))'));
      // A void method returns null: a non-nullable Object skips it.
      expect(
        output,
        hasCode(
          'aspect.someResult((value as Object)), '
          'accepts: (value) => value is Object',
        ),
      );
      expect(
        output,
        hasCode('accepts: (value) => value is StateError'.replaceAll('', '')),
      );
      expect(
        output,
        hasCode('aspect.around((joinPoint as ProceedingJoinPoint))'),
      );
      expect(output, hasCode("pointcuts: {r'all': r'execution(* *(..))'}"));
      expect(
        output,
        isNot(contains(r'_$AuditProxy')),
        reason: 'aspects are not proxied',
      );
    });

    test('proxy members of every kind', () async {
      final output = await generateModule(r'''
class Note {
  const Note();
}

abstract interface class Api {
  @Note()
  String plain(int a, [int b = 2, String? c]);
  T generic<T extends Object>(T value, {required String key, int retries = 3});
  void act();
  Future<int> later();
  int get count;
  set count(int value);
  String transform(String Function(int) f, (int, {String name}) record);
}

@Service()
@Note()
class Impl implements Api {
  @override
  String plain(int a, [int b = 2, String? c]) => '$a$b$c';
  @override
  T generic<T extends Object>(T value, {required String key, int retries = 3}) => value;
  @override
  void act() {}
  @override
  Future<int> later() async => 1;
  @override
  int count = 0;
  @override
  String transform(String Function(int) f, (int, {String name}) record) => f(record.$1);
  @override
  String toString() => 'Impl';
}
''', proxyMode: ProxyMode.all);
      expect(
        output,
        hasCode(
          r'class _$ImplProxy with AdvisedWrapper implements Impl, Api {',
        ),
      );
      expect(output, hasCode(r'_$ImplProxy(this._target, this.aopInvoker);'));
      expect(output, hasCode('@override final ProxyInvoker aopInvoker;'));
      expect(output, hasCode('Object get aopTarget => _target;'));
      expect(output, hasCode('String toString() => _target.toString();'));
      expect(
        output,
        hasCode(
          'String plain(int a, [int b = 2, String? c]) => '
          '(this.aopInvoker.invoke(this, this._target, 0, [a, b, c], '
          '(args) => this._target.plain((args[0] as int), (args[1] as int), '
          '(args[2] as String?))) as String);',
        ),
      );
      expect(
        output,
        hasCode(
          'T generic<T extends Object>(T value, {required String key, int '
          'retries = 3}) => '
          '(this.aopInvoker.invoke(this, this._target, 1, '
          '[value, key, retries], '
          '(args) => this._target.generic<T>((args[0] as T), '
          'key: (args[1] as String), retries: (args[2] as int))) as T);',
        ),
      );
      expect(
        output,
        hasCode(
          'void act() {this.aopInvoker.invoke(this, this._target, 2, const [], '
          '(args) {this._target.act(); return null;});}',
        ),
      );
      expect(
        output,
        hasCode(
          'Future<int> later() => this.aopInvoker.invokeAsync<int>(this, '
          'this._target, 3, const [], (args) => this._target.later());',
        ),
      );
      expect(
        output,
        hasCode(
          'int get count => (this.aopInvoker.invoke(this, this._target, 5, '
          'const '
          '[], (_) => this._target.count) as int);',
        ),
      );
      expect(
        output,
        hasCode(
          'set count(int value) {this.aopInvoker.invoke(this, this._target, 6, '
          '[value], (args) {this._target.count = (args[0] as int); return '
          'null;});}',
        ),
      );
      expect(
        output,
        hasCode(
          'String transform(String Function(int) f, (int, {String name}) '
          'record)',
        ),
      );
      expect(
        output,
        hasCode(
          r"MethodSignature.of(r'plain', _$target0, declaringType: r'Api', "
          "declaringTypes: [r'Impl', r'Api'], returnType: r'String', "
          "parameterTypes: [r'int', r'int', r'String'], parameterNames: [r'a', "
          "r'b', r'c'], annotations: [Note()], annotationTypes: [r'Note'])",
        ),
      );
      // The bean class, shared by the signatures of its members.
      expect(
        output,
        hasCode(
          r"const _$target0 = AopTarget(r'Impl', types: [r'Impl', r'Api'], "
          'annotations: [Service(), Note()], '
          "annotationTypes: [r'Service', r'Note']);",
        ),
      );
      expect(output, hasCode('kind: MemberKind.getter'));
      expect(output, hasCode('kind: MemberKind.setter'));
      expect(output, hasCode("parameterTypes: [r'Function', r'Record']"));
      expect(
        output,
        hasCode(
          r'create: (target, invoker) => _$ImplProxy((target as Impl), '
          'invoker)',
        ),
      );
    });

    test(
      'public fields are advised like explicit getters and setters',
      () async {
        final output = await generateModule('''
class Note {
  const Note();
}

@Service()
class Plain {
  @Note()
  String title = '';
  final int id = 1;
  @NotBlank()
  String name = 'n';
  static int shared = 0;
  String get label => title;
}

@Service()
class Hidden {
  int count = 0;
  int _secret = 0;
  int get secret => _secret;
}
''', proxyMode: ProxyMode.all);
        for (final proxy in [r'_$PlainProxy', r'_$HiddenProxy']) {
          expect(output, contains(proxy));
        }
        // Implementing proxy: field accessors forward through the advice.
        expect(output, hasCode('String get title => (this.aopInvoker.invoke('));
        expect(
          output,
          hasCode('set title(String value) {this.aopInvoker.invoke('),
        );
        expect(output, hasCode('int get id => (this.aopInvoker.invoke('));
        expect(output, isNot(contains('setid(')), reason: 'final: no setter');
        expect(output, hasCode('String get label => (this.aopInvoker.invoke('));
        expect(
          output,
          isNot(contains('shared')),
          reason: 'static: not a member',
        );
        // The field's annotations reach the pointcut (`@annotation(Note)`).
        // Declared by the bean class itself: no declaringType.
        expect(
          output,
          matches(RegExp(r"MethodSignature\.of\(r'title',_\$target\d+,kind:")),
        );
        expect(output, hasCode('annotations: [Note()]'));
        expect(output, isNot(contains('annotations:[Note(),Note()]')));
        expect(
          RegExp(r'annotations:\[Note\(\)\]').allMatches(output),
          hasLength(2),
          reason: 'the getter and the setter of the field',
        );
        // Subclass proxy: the same for a class with private members.
        expect(
          output,
          hasCode(
            r'int get count { final _$i = this.aopInvoker; '
            r'return _$i == null ? '
            r'super.count : (_$i.invoke(',
          ),
        );
        expect(output, hasCode(r'set count(int value) { final _$i'));
      },
    );

    test('generic type arguments in proxied signatures', () async {
      final output = await generateModule('''
abstract interface class Jobs {
  Future<T> run<T>(T value);
  List<void Function()> hooks();
  Map<String, (int, String)> table();
}

@Service()
class JobRunner implements Jobs {
  @override
  Future<T> run<T>(T value) async => value;
  @override
  List<void Function()> hooks() => [];
  @override
  Map<String, (int, String)> table() => {};
  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => 0;
}
''', proxyMode: ProxyMode.all);
      expect(
        output,
        hasCode('Future<T> run<T>(T value) => this.aopInvoker.invokeAsync<T>('),
      );
      expect(output, hasCode('List<void Function()> hooks()'));
      expect(output, hasCode('Map<String, (int, String)> table()'));
      expect(output, isNot(contains('operator==')));
    });

    test('@Bean methods returning aspects or configurations', () async {
      final output = await generateModule('''
@Aspect()
class Audit { void log() {} }

@Configuration()
class Nested { void helper() {} }

@Configuration()
class Config {
  @Bean() Audit auditAspect() => Audit();
  @Bean() Nested nestedConfig() => Nested();
}
''', proxyMode: ProxyMode.all);
      expect(output, isNot(contains(r'_$Config$AuditAspectProxy')));
      expect(output, isNot(contains(r'_$Config$NestedConfigProxy')));
    });

    test('proxy modes and exclusions', () async {
      const source = '''
abstract interface class Api { void run(); }
abstract class Base { void base(); }

@Service() class WithPrivate implements Api { int _secret = 0; @override void run() {} }
@Service() class Plain { void work() {} }
@Service() class Both extends Base implements Api { @override void run() {} @override void base() {} }
@Service() class Ops implements Api { @override void run() {} int operator [](int i) => i; }
@Service() class OnlyOps { int operator +(int other) => other; }
@Service() class ComplexDefault implements Api { @override void run([Duration d = const Duration(seconds: 1)]) {} }
@Service() class Untyped implements Api { @override void run() {} void typed(void Function<T>() f) {} }
@Service() class Product extends FactoryBean<Plain> { @override Plain getObject() => Plain(); }
@Service() class Processor extends BeanPostProcessor {}
@Configuration() class Config { @Bean() Api api() => Both(); @Bean() String text() => ''; }
''';
      final all = await generateModule(source, proxyMode: ProxyMode.all);
      // Private members: a subclass proxy (CGLIB), not one implementing
      // only the interface.
      expect(
        all,
        contains(
          r'class_$WithPrivateProxyextendsWithPrivatewithAdvisedSubclass{',
        ),
        reason: 'class with private members: subclass',
      );
      expect(
        all,
        contains(r'class_$PlainProxywithAdvisedWrapperimplementsPlain'),
      );
      expect(
        all,
        contains(r'class_$BothProxywithAdvisedWrapperimplementsBoth,Base,Api'),
      );
      // Operators cannot be forwarded: a subclass proxy inherits them.
      expect(
        all,
        contains(r'class_$OpsProxyextendsOpswithAdvisedSubclass{'),
        reason: 'operators',
      );
      expect(all, isNot(contains('operator')));
      expect(
        all,
        contains(r'class_$OnlyOpsProxyextendsOnlyOpswithAdvisedSubclass{'),
      );
      // A constant default value is re-created.
      expect(
        all,
        contains(
          r'class_$ComplexDefaultProxywithAdvisedWrapper'
          'implementsComplexDefault,Api',
        ),
        reason: 'non-literal default',
      );
      expect(all, contains('run([Durationd=constDuration(seconds:1)])'));
      // A member the subclass cannot override stays inherited.
      expect(
        all,
        contains(r'class_$UntypedProxyextendsUntypedwithAdvisedSubclass{'),
        reason: 'generic function type parameter',
      );
      expect(all, isNot(contains('typed(')));
      for (final excluded in ['Product', 'Processor', 'Config']) {
        expect(all, isNot(contains('_\$${excluded}Proxy')), reason: excluded);
      }
      // The bean type is inferred from the method body (`Both()`).
      expect(
        all,
        contains(
          r'class_$Config$ApiProxywithAdvisedWrapperimplementsBoth,Base,Api',
        ),
      );
      expect(all, isNot(contains(r'_$Config$TextProxy')), reason: 'SDK types');

      final interfaces = await generateModule(
        source,
        proxyMode: ProxyMode.interfaces,
      );
      expect(
        interfaces,
        contains(r'class_$BothProxywithAdvisedWrapperimplementsBase,Api'),
      );
      expect(interfaces, isNot(contains(r'_$PlainProxy')));
      expect(
        interfaces,
        contains(r'class_$Config$ApiProxywithAdvisedWrapperimplementsBase,Api'),
      );

      final none = await generateModule(source);
      expect(none, isNot(contains('Proxy')));
    });

    test('builder option', () {
      expect(
        (springCoreDartBuilder(
          const BuilderOptions({'aop_proxies': 'interfaces'}),
        ) as SpringBuilder).proxyMode,
        ProxyMode.interfaces,
      );
      expect(
        () => springCoreDartBuilder(
          const BuilderOptions({'aop_proxies': 'bogus'}),
        ),
        throwsArgumentError,
      );
    });
  });

  test('proxy signatures carry the parameter names', () async {
    final output = await generateModule('''
class Timed {
  const Timed();
}

@Service()
class Books {
  @Timed()
  String find(String isbn, {int page = 0}) => isbn;
}
''', proxyMode: ProxyMode.all);
    expect(
      output,
      hasCode(
        "parameterTypes: [r'String', r'int'], parameterNames: [r'isbn', "
        "r'page']",
      ),
    );
  });
}
