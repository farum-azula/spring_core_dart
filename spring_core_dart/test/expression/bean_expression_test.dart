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
}

class _CustomResolver extends StandardBeanExpressionResolver {
  _CustomResolver({super.propertyAccessors, super.methodResolvers});

  @override
  void customizeEvaluationContext(StandardEvaluationContext context) =>
      context.setVariable('answer', 42);
}
