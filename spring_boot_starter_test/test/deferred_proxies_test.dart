// A starter's bean whose proxy class only the application's build writes
// (`AopProxyFactory.deferred`), in a context built without the application's
// generated module: plain without matching advice, a startup failure that
// says what to do with it.
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

class _Audit {
  final calls = <String>[];
}

// A hand-written aspect: `@Before(expression) void audit()`.
BeanModule _aspect(String expression) => BeanModule('aspects', [
  BeanDefinition<_Audit>(
    name: 'audit',
    create: (_) => _Audit(),
    aspect: AspectMetadata<_Audit>(
      advice: [
        AspectAdvice<_Audit>(
          kind: AdviceKind.before,
          pointcut: expression,
          methodName: 'audit',
          invoke: (aspect, joinPoint, _, _) {
            aspect.calls.add(joinPoint.signature.name);
            return null;
          },
        ),
      ],
    ),
  ),
]);

void main() {
  final runner = const ApplicationContextRunner().withAutoConfiguration(
    springBootAutoConfiguration,
  );

  test('the library module leaves the proxy of BannerProperties out', () {
    runner.run((context) {
      final definition = context.context.beanFactory.getBeanDefinition(
        'bannerProperties',
      );
      expect(definition.aopProxy?.isDeferred, isTrue);
    });
  });

  test('advice that matches nothing of it: the bean is plain', () {
    runner.withUserConfiguration(_aspect('bean(nothing)')).run((context) {
      expect(context, isNot(hasFailed()));
      expect(context.getBeanByName('bannerProperties'), isNot(isA<Advised>()));
    });
  });

  test('advice that matches it: a startup failure that says why', () {
    runner.withUserConfiguration(_aspect('bean(bannerProperties)')).run((
      context,
    ) {
      expect(
        context,
        hasFailed(
          isA<AopConfigException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains("bean 'bannerProperties'"),
              contains('ApplicationContextRunner'),
              contains('@SpringBootApplication'),
            ),
          ),
        ),
      );
    });
  });

  const source =
      'package:spring_boot_dart/src/properties/boot_properties.dart'
      '#BannerProperties';

  test('a factory that leaves out the advised members: a startup failure', () {
    // Proxies no member of the bean: the advice would be skipped.
    final module = BeanModule(
      'application',
      const [],
      aopProxies: {
        source: AopProxyFactory(
          signatures: const [],
          create: (target, invoker) => target,
        ),
      },
    );
    runner
        .withUserConfiguration(module)
        .withUserConfiguration(_aspect('bean(bannerProperties)'))
        .run((context) {
          expect(
            context,
            hasFailed(
              isA<AopConfigException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains("of bean 'bannerProperties'"),
                  contains('aop_prune: false'),
                ),
              ),
            ),
          );
        });
  });

  test('a pruned factory for the bean: a startup failure', () {
    runner
        .withUserConfiguration(
          BeanModule(
            'application',
            const [],
            aopProxies: {source: const AopProxyFactory.pruned()},
          ),
        )
        .run((context) {
          expect(context, hasFailed(isA<AopConfigException>()));
        });
  });
}
