import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import '../beans/support.dart';

void main() {
  test('@Value #{...} is evaluated by the context', () {
    final environment = StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(
        const MapPropertySource('test', {'app.name': 'neon', 'factor': '3'}),
      );
    final values = <String, Object?>{};
    final context = AnnotationConfigApplicationContext([
      BeanModule('test', [
        english(),
        BeanDefinition<Holder>(
          name: 'holder',
          create: (r) {
            values['math'] = r.value<int>('#{2 * 3}');
            values['env'] = r.value<String>(
              "#{environment['app.name'].toUpperCase()}",
            );
            values['placeholder'] = r.value<int>(r'#{${factor} * 2}');
            values['bean'] = r.value<Greeter>('#{english}');
            values['ref'] = r.value<Greeter>('#{@english}');
            values['template'] = r.value<String>(r'Hi #{1 + 1} ${app.name}');
            values['missing'] = r.optionalValue<String>(r'${nope}');
            return Holder(English());
          },
        ),
      ]),
    ], environment: environment)..refresh();
    expect(context.containsBean('holder'), isTrue);
    expect(values, {
      'math': 6,
      'env': 'NEON',
      'placeholder': 6,
      'bean': isA<English>(),
      'ref': isA<English>(),
      'template': 'Hi 2 neon',
      'missing': null,
    });
  });

  test('resolver customization and accessors', () {
    final resolver = _CustomResolver(
      propertyAccessors: [
        FunctionPropertyAccessor<Holder>(getters: {'tag': (_) => 'holder-tag'}),
      ],
      methodResolvers: [
        FunctionMethodResolver<English>({
          'shout': (e, _) => e.greet().toUpperCase(),
        }),
      ],
    );
    final factory = DefaultListableBeanFactory()
      ..registerSingleton('english', English(), types: [English, Greeter])
      ..registerSingleton('holder', Holder(French()))
      ..beanExpressionResolver = resolver;
    expect(factory.value<String>('#{english.shout()}'), 'HELLO');
    expect(factory.value<String>('#{holder.tag}'), 'holder-tag');
    expect(factory.value<int>('#{#answer}'), 42);
    expect(factory.value<String>('#{1}#{2}'), '12');
    expect(
      () => factory.value<String>('#{unknown}'),
      throwsA(isA<SpelEvaluationException>()),
    );
    const accessor = BeanExpressionContextAccessor();
    final context = StandardEvaluationContext();
    expect(accessor.canWrite(context, Object(), 'x'), isFalse);
    expect(
      () => accessor.write(context, Object(), 'x', 1),
      throwsUnsupportedError,
    );
    const envAccessor = EnvironmentAccessor();
    expect(envAccessor.canWrite(context, Object(), 'x'), isFalse);
    expect(
      () => envAccessor.write(context, Object(), 'x', 1),
      throwsUnsupportedError,
    );
    expect(BeanExpressionContext(factory).getObject('nope'), isNull);
  });

  test('systemEnvironment, systemProperties and the environment', () {
    final environment =
        StandardEnvironment(systemEnvironment: {'HOME': '/home/neon'})
          ..propertySources.addFirst(
            const MapPropertySource('test', {
              'app.name': 'neon',
              'app.port': '8080',
            }),
          )
          ..propertySources.addFirst(
            SimpleCommandLinePropertySource(['--server.port=9000', '--debug']),
          );
    final factory = DefaultListableBeanFactory()
      ..registerSingleton('environment', environment)
      ..beanExpressionResolver = StandardBeanExpressionResolver();
    expect(factory.value<String>("#{systemEnvironment['HOME']}"), '/home/neon');
    expect(factory.value<String>("#{systemEnvironment.HOME}"), '/home/neon');
    // Dart has no system properties: the command-line arguments stand in.
    expect(factory.value<String>("#{systemProperties['server.port']}"), '9000');
    expect(factory.value<int>("#{systemProperties['server.port']}"), 9000);
    expect(factory.value<String>("#{systemProperties['debug']}"), '');
    expect(
      factory.optionalValue<String>("#{systemProperties['app.name']}"),
      isNull,
    );
    expect(factory.value<Map<String, Object?>>('#{systemProperties}'), {
      'server.port': '9000',
      'debug': '',
    });
    expect(factory.value<String>("#{environment['app.name']}"), 'neon');
    expect(
      factory.value<String>("#{environment.getProperty('app.name')}"),
      'neon',
    );
    expect(factory.value<int>("#{environment.getProperty('app.port')}"), 8080);
    expect(
      factory.value<String>("#{environment.getProperty('nope', 'fallback')}"),
      'fallback',
    );
    expect(factory.optionalValue<String>("#{environment['nope']}"), isNull);
    expect(
      factory.value<bool>("#{environment.containsProperty('app.name')}"),
      isTrue,
    );
    expect(
      factory.value<bool>("#{environment.matchesProfiles('dev')}"),
      isFalse,
    );
    expect(
      () => factory.value<String>("#{environment.getRequiredProperty('nope')}"),
      throwsA(isA<MissingPropertyException>()),
    );
    // Beans named like the special maps win.
    factory.registerSingleton('systemProperties', {'custom': true});
    expect(factory.value<bool>("#{systemProperties['custom']}"), isTrue);
  });

  test('special maps without an environment bean', () {
    final factory = DefaultListableBeanFactory()
      ..beanExpressionResolver = StandardBeanExpressionResolver();
    expect(factory.value<Map<String, Object?>>('#{systemProperties}'), isEmpty);
    expect(
      factory.value<Map<String, String>>('#{systemEnvironment}'),
      // The process environment (none on the web).
      StandardEnvironment().systemEnvironment,
    );
    final root = BeanExpressionContext(factory);
    expect(root.containsObject('systemEnvironment'), isTrue);
    expect(root.containsObject('systemProperties'), isTrue);
  });

  test('the factory ConversionService converts inside expressions', () {
    final factory = DefaultListableBeanFactory()
      ..beanExpressionResolver = StandardBeanExpressionResolver();
    expect(
      () => factory.value<int>("#{'ja' ? 1 : 2}"),
      throwsA(isA<SpelEvaluationException>()),
    );
    factory.conversionService = DefaultConversionService()
      ..addConverter<String, bool>((s) => s == 'ja');
    expect(factory.value<int>("#{'ja' ? 1 : 2}"), 1);
    expect(factory.value<int>("#{'nein' ? 1 : 2}"), 2);
  });

  test('parsed expressions are cached per resolver', () {
    final parser = _CountingParser();
    final factory = DefaultListableBeanFactory()
      ..beanExpressionResolver = StandardBeanExpressionResolver(parser: parser);
    final other = DefaultListableBeanFactory()
      ..beanExpressionResolver = factory.beanExpressionResolver;
    expect(factory.value<int>('#{1 + 1}'), 2);
    expect(factory.value<int>('#{1 + 1}'), 2);
    expect(other.value<int>('#{1 + 1}'), 2);
    expect(factory.value<int>('#{1 + 2}'), 3);
    expect(parser.parsed, ['#{1 + 1}', '#{1 + 2}']);
  });

  test('user exceptions and parse errors in @Value', () {
    final factory = DefaultListableBeanFactory()
      ..registerSingleton('english', English(), types: [English, Greeter])
      ..beanExpressionResolver = StandardBeanExpressionResolver(
        methodResolvers: [
          FunctionMethodResolver<English>({
            'boom': (_, _) => throw StateError('boom'),
          }),
        ],
      );
    // An exception of the method itself is rethrown as is, not wrapped.
    expect(
      () => factory.value<String>('#{english.boom()}'),
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'boom')),
    );
    expect(
      () => factory.value<String>('#{english.nope()}'),
      throwsA(
        isA<SpelEvaluationException>().having(
          (e) => e.messageCode,
          'messageCode',
          SpelMessage.methodNotFound,
        ),
      ),
    );
    expect(
      () => factory.value<int>('x #{1 +} y'),
      throwsA(
        isA<SpelParseException>()
            .having((e) => e.position, 'position', greaterThanOrEqualTo(0))
            .having((e) => e.message, 'message', contains('@')),
      ),
    );
  });
}

class _CountingParser implements ExpressionParser {
  final parsed = <String>[];
  final _delegate = SpelExpressionParser();

  @override
  Expression parseExpression(
    String expressionString, [
    ParserContext? context,
  ]) {
    parsed.add(expressionString);
    return _delegate.parseExpression(expressionString, context);
  }
}

class _CustomResolver extends StandardBeanExpressionResolver {
  _CustomResolver({super.propertyAccessors, super.methodResolvers});

  @override
  void customizeEvaluationContext(StandardEvaluationContext context) =>
      context.setVariable('answer', 42);
}
