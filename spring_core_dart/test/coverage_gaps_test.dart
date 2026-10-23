// Targeted tests for small branches not covered by the feature tests.
// ignore_for_file: prefer_const_constructors

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart/src/expression/tokenizer.dart';
import 'package:test/test.dart' hide Description;

import 'beans/support.dart';

class _Names extends EnumerablePropertySource<Map<String, String>> {
  const _Names(super.name, super.source);
  @override
  Object? getProperty(String name) => source[name];
  @override
  List<String> get propertyNames => source.keys.toList();
}

class _Cleanup extends DestructionAwareBeanPostProcessor {
  final destroyed = <String>[];
  @override
  void postProcessBeforeDestruction(Object bean, String beanName) =>
      destroyed.add(beanName);
}

class _Matrix {
  List<List<int>?> rows = [
    [1, 2],
    null,
  ];
}

final _matrixIntrospection = BeanIntrospection<_Matrix>(
  properties: [
    BeanProperty<_Matrix>(
      'rows',
      type: List<List<int>?>,
      get: (b) => b.rows,
      set: (b, v) => b.rows = v! as List<List<int>?>,
    ),
  ],
);

void main() {
  test('annotations can be created at runtime', () {
    final annotations = <Object>[
      Component('c'),
      Service('s'),
      Repository('r'),
      Controller('ctl'),
      Configuration(name: 'cfg', proxyBeanMethods: false),
      Bean(
        name: 'b',
        aliases: ['a'],
        initMethod: 'i',
        destroyMethod: 'd',
        autowireCandidate: false,
      ),
      Scope(ScopeType.prototype),
      Lazy(false),
      Primary(),
      Fallback(),
      Qualifier('q'),
      DependsOn(['x']),
      Description('d'),
      Autowired(),
      Inject(),
      Named('n'),
      Value(r'${v}'),
      PostConstruct(),
      PreDestroy(),
      Profile(['dev']),
      Conditional([Object]),
      Import([Object]),
      PropertySource(
        ['p'],
        name: 'n',
        ignoreResourceNotFound: true,
        factory: Object,
      ),
      ComponentScan(),
      Configurable(),
      EventListener(classes: [int], condition: print, id: 'id'),
      Introspected(),
      Aspect(),
      Pointcut('p()'),
      Before('b'),
      After('a'),
      AfterReturning('r'),
      AfterThrowing('t'),
      Around('x'),
      Order(5),
      Valid(),
    ];
    expect(annotations, hasLength(36));
    expect((annotations[5] as Bean).destroyMethod, 'd');
    expect(Bean().destroyMethod, Bean.inferMethod);
  });

  group('small runtime branches', () {
    test('toString of definitions, modules, events, listeners', () {
      expect(
        english().toString(),
        "BeanDefinition<English>('english', singleton)",
      );
      expect(
        BeanModule('m', [english()]).toString(),
        "BeanModule('m', 1 beans)",
      );
      expect(
        PayloadApplicationEvent<Object>('src', 1).toString(),
        contains('payload=1'),
      );
      expect(_Event('src').toString(), '_Event[source=src]');
      expect(
        EventListenerMethod.of<Object, int>('x', (_, _) => null).toString(),
        'EventListenerMethod(x)',
      );
      expect(
        Token(TokenKind.identifier, 0, 1, 'a').toString(),
        'TokenKind.identifier(a)@0',
      );
      expect(Token(TokenKind.dot, 0, 1).toString(), 'TokenKind.dot@0');
      expect(
        NoSuchBeanDefinitionException(int, qualifier: 'q').toString(),
        contains("qualifier 'q'"),
      );
    });

    test('EventListenerMethod.matching and match', () {
      final method = EventListenerMethod<List<Object>>.matching(
        id: 'm',
        accepts: (c) => c is int || c is String,
        invoke: (bean, event) => bean
          ..add(
            EventListenerMethod.match(event, (c) => c is int || c is String),
          ),
        condition: (Object value) => value != 'skip',
      );
      final bean = <Object>[];
      expect(method.supports(1), isTrue);
      expect(
        method.supports(PayloadApplicationEvent<Object>('s', 'x')),
        isTrue,
      );
      expect(method.supports(2.5), isFalse);
      expect(method.supports('skip'), isFalse);
      method.invoke(bean, PayloadApplicationEvent<Object>('s', 'x'));
      expect(bean, ['x']);
      expect(
        () => EventListenerMethod.match(2.5, (c) => c is int),
        throwsArgumentError,
      );
      final unconditional = EventListenerMethod<Object>.matching(
        id: 'u',
        accepts: (c) => c is int,
        invoke: (_, _) => null,
      );
      expect(unconditional.supports(1), isTrue);
    });

    test('ApplicationContext.run and bean method listener description', () {
      final context = ApplicationContext.run(
        [
          BeanModule('m', [english()]),
        ],
        environment: StandardEnvironment(systemEnvironment: {}),
        id: 'run',
      );
      expect(context.isActive, isTrue);
      expect(context.id, 'run');
      context.close();
    });

    test('registered singletons are beans but not definitions', () {
      final factory = DefaultListableBeanFactory()
        ..registerSingleton('x', English());
      expect(factory.getBeanByName('x'), same(factory.getSingleton('x')));
      expect(factory.containsBeanDefinition('x'), isFalse);
      expect(factory.beanDefinitionNames, isEmpty);
      expect(
        () => factory.getBeanDefinition('x'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      factory.registerBeanDefinition(
        lifecycleDefinition('user', onCreate: (r) => r.getBeanByName('x')),
      );
      factory.getBeanByName('user');
      expect(factory.isBeanNameInUse('x'), isTrue);
    });

    test('optional values through the expression resolver', () {
      final factory = DefaultListableBeanFactory()
        ..beanExpressionResolver = StandardBeanExpressionResolver();
      expect(factory.optionalValue<int>('#{1 + 1}'), 2);
    });

    test('destruction-aware processors default to every bean', () {
      final cleanup = _Cleanup();
      final factory = DefaultListableBeanFactory()
        ..addBeanPostProcessor(cleanup)
        ..registerBeanDefinition(english());
      factory
        ..preInstantiateSingletons()
        ..destroySingletons();
      expect(cleanup.destroyed, ['english']);
    });

    test('enumerable property source default containsProperty', () {
      const source = _Names('n', {'a': '1'});
      expect(source.containsProperty('a'), isTrue);
      expect(source.containsProperty('b'), isFalse);
    });

    test('properties parser edge cases', () {
      expect(PropertiesParser.parse('a = b\\'), {'a': 'b'});
      expect(PropertiesParser.parse('key   =value'), {'key': 'value'});
      expect(PropertiesParser.parse('key   :value'), {'key': 'value'});
    });

    test('message format edge cases', () {
      expect(
        MessageFormat.format('{0,choice,0#none|1#{1} item}', [1, 'one']),
        'one item',
      );
      expect(MessageFormat.format('{0}', [-1.5]), '-1.5');
      expect(
        MessageFormat.format('{0,number,#.##########}', [1e-7]),
        '.0000001',
      );
      expect(
        // The double 1.5e-10 is 1.4999...e-10: rounded on its exact value,
        // like Java's DecimalFormat.
        MessageFormat.format('{0,number,#.##########}', [1.5e-10]),
        '.0000000001',
      );
    });

    test('bean wrapper nested indexes', () {
      final matrix = _Matrix();
      final wrapper = BeanWrapper(
        matrix,
        introspector: BeanIntrospector(introspections: [_matrixIntrospection]),
      );
      wrapper.setPropertyValue('rows[0][1]', 9);
      expect(matrix.rows[0], [1, 9]);
      expect(
        () => wrapper.getPropertyValue('rows[1][0]'),
        throwsA(isA<NullValueInNestedPathException>()),
      );
      wrapper.setPropertyValue('rows[0]', [7]);
      expect(matrix.rows[0], [7]);
    });

    test('async proxy invocation without advice', () async {
      final factory = AopProxyFactory(
        signatures: const [
          MethodSignature(name: 'later', declaringType: 'T', targetType: 'T'),
        ],
        create: (target, invoker) => _AsyncProxy(invoker),
      );
      final proxy = factory.createProxy(Object(), const []) as _AsyncProxy;
      expect(await proxy.later(), 7);
      expect(
        const MethodSignature(
          name: 'n',
          declaringType: 'D',
          targetType: 'T',
        ).toString(),
        'dynamic D.n()',
      );
    });
  });

  group('expression branches', () {
    final parser = SpelExpressionParser();

    test('nodes, comparators, converters, overloaders', () {
      expect(
        (parser.parseExpression('1') as SpelExpression).ast.isNullSafe,
        isFalse,
      );
      expect(
        (parser.parseExpression('{1,2}') as SpelExpression).ast.toString(),
        '{1,2}',
      );
      final context = StandardEvaluationContext()..setVariable('n', null);
      expect(
        () => parser.parseExpression('#n[0] = 1').getValue(context),
        throwsA(isA<SpelEvaluationException>()),
      );
      final utc = DateTime.utc(2026);
      final local = utc.toLocal();
      expect(
        parser
            .parseExpression('#a == #b')
            .getValue(
              StandardEvaluationContext()
                ..setVariable('a', utc)
                ..setVariable('b', local),
            ),
        isTrue,
      );
      expect(
        () => const StandardTypeComparator().compare('a', 1),
        throwsA(isA<SpelEvaluationException>()),
      );
      expect(
        () => const StandardOperatorOverloader().operate(Operation.add, 1, 2),
        throwsA(isA<SpelEvaluationException>()),
      );
      expect(
        const StandardOperatorOverloader().overridesOperation(
          Operation.add,
          1,
          2,
        ),
        isFalse,
      );
      expect(
        () => StandardTypeConverter().convertValue('x', int),
        throwsA(isA<SpelEvaluationException>()),
      );
      final simple = SimpleEvaluationContext.forReadOnlyDataBinding().build();
      expect(simple.operatorOverloader, isA<StandardOperatorOverloader>());
      expect(simple.beanResolver, isNull);
      expect(simple.lookupVariable('x'), isNull);
      const builtins = BuiltinPropertyAccessor();
      expect(builtins.canWrite(simple, 'x', 'length'), isFalse);
      expect(
        () => builtins.write(simple, 'x', 'length', 1),
        throwsUnsupportedError,
      );
    });

    test('composite templates without a context', () {
      final template = parser.parseExpression('a#{1}b', ParserContext.template);
      expect(template.getValue(), 'a1b');
      expect(template.getValueAs<String>(), 'a1b');
    });

    test('dotted type names and statics', () {
      final locator = StandardTypeLocator()
        ..registerType(
          SpelType.of<Uri>(
            'dart.core.Uri',
            staticMethods: {'parse': Uri.parse},
          ),
        );
      final context = StandardEvaluationContext()..typeLocator = locator;
      expect(
        parser
            .parseExpression("T(dart.core.Uri).parse('a:b')")
            .getValue(context),
        Uri.parse('a:b'),
      );
      Object? eval(String text) => parser.parseExpression(text).getValue();
      expect(eval('T(int).MIN_VALUE < 0'), isTrue);
      expect(eval('T(double).MAX_VALUE > 0'), isTrue);
      expect((eval('T(double).NaN')! as double).isNaN, isTrue);
      expect(eval('T(double).INFINITY'), double.infinity);
      expect(eval("T(double).parse('1.5')"), 1.5);
      expect(eval("T(double).tryParse('x')"), isNull);
      expect(eval("T(String).valueOf(1) + T(String).fromCharCode(65)"), '1A');
      expect(eval('T(List).of({1, 2})'), [1, 2]);
      expect(eval('new Map()'), isEmpty);
      expect(eval('new Set()'), isEmpty);
      expect(eval('new Object()'), isA<Object>());
      expect(eval("T(bool).parse('TRUE')"), isTrue);
      expect(
        eval("T(num).parse('2') + T(int).tryParse('3') + T(int).valueOf('4')"),
        9,
      );
      expect(eval('T(DateTime).now().year > 2000'), isTrue);
      expect(eval("T(DateTime).parse('2026-01-01').month"), 1);
      expect(eval('T(Duration).ofMillis(1).inMicroseconds'), 1000);
      expect(eval('T(Duration).ofMinutes(1).inSeconds'), 60);
      expect(eval('T(Duration).ofHours(1).inMinutes'), 60);
      expect(eval('T(Duration).ofDays(1).inHours'), 24);
    }, skip: false);

    test('exception rendering without position', () {
      final error = SpelEvaluationException(
        SpelMessage.typeConversionError,
        'm',
        expressionString: 'x',
      );
      expect(error.toString(), "SpelEvaluationException: m in expression 'x'");
      // An exponent marker without digits belongs to the next token.
      expect(Tokenizer('1e').process().map((t) => t.kind), [
        TokenKind.literalInt,
        TokenKind.identifier,
      ]);
    });
  });
}

class _Event extends ApplicationEvent {
  _Event(super.source);
}

class _AsyncProxy {
  _AsyncProxy(this._invoker);
  final ProxyInvoker _invoker;
  Future<int> later() =>
      _invoker.invokeAsync<int>(this, this, 0, const [], (_) async => 7);
}
