import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final log = <String>[];

class Repo {
  String? url;
  void connect() => log.add('repo:postConstruct');
}

class FakeRepo extends Repo {}

class Logging extends BeanPostProcessor {
  Logging(this.name);
  final String name;
  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    if (beanName == 'repo') {
      log.add('$name:before');
    }
    return bean;
  }

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (beanName == 'repo') {
      log.add('$name:after');
    }
    return bean;
  }
}

class PriorityLogging extends Logging implements PriorityOrdered {
  PriorityLogging(super.name, this.order);
  @override
  final int order;
}

class OrderedLogging extends Logging implements Ordered {
  OrderedLogging(super.name, this.order);
  @override
  final int order;
}

class Instantiation extends SmartInstantiationAwareBeanPostProcessor {
  Instantiation({this.replace, this.inject = true, this.predict});
  final Object? replace;
  final bool inject;
  final Type? predict;

  @override
  Object? postProcessBeforeInstantiation(Type beanType, String beanName) {
    log.add('beforeInstantiation($beanType, $beanName)');
    return beanName == 'repo' ? replace : null;
  }

  @override
  bool postProcessAfterInstantiation(Object bean, String beanName) {
    log.add('afterInstantiation($beanName)');
    return inject;
  }

  @override
  void postProcessProperties(Object bean, String beanName) {
    log.add('properties($beanName, url: ${(bean as Repo).url})');
  }

  @override
  Type? predictBeanType(Type beanType, String beanName) =>
      beanName == 'repo' ? predict : null;
}

class Merged extends MergedBeanDefinitionPostProcessor {
  @override
  void postProcessMergedBeanDefinition(
    BeanDefinition<Object> definition,
    Type beanType,
    String beanName,
  ) => log.add('merged($beanType, $beanName)');

  @override
  void resetBeanDefinition(String beanName) => log.add('reset($beanName)');
}

BeanDefinition<Repo> repo({String scope = ScopeType.singleton}) =>
    BeanDefinition<Repo>(
      name: 'repo',
      scope: scope,
      create: (_) {
        log.add('repo:create');
        return Repo();
      },
      inject: (bean, _) {
        log.add('repo:inject');
        bean.url = 'db';
      },
      postConstruct: (bean) => bean.connect(),
      preDestroy: (_) => log.add('repo:preDestroy'),
    );

BeanDefinition<Object> processor(String name, BeanPostProcessor instance) =>
    BeanDefinition<BeanPostProcessor>(
      name: name,
      types: [
        instance.runtimeType,
        BeanPostProcessor,
        if (instance is Ordered) Ordered,
        if (instance is PriorityOrdered) PriorityOrdered,
      ],
      create: (_) => instance,
    );

void main() {
  setUp(log.clear);

  group('@PostConstruct runs at the CommonAnnotationBeanPostProcessor', () {
    test('after PriorityOrdered processors, before Ordered and plain ones', () {
      final context = AnnotationConfigApplicationContext([
        BeanModule('m', [
          processor('plain', Logging('plain')),
          processor('ordered', OrderedLogging('ordered', 1)),
          processor('priority', PriorityLogging('priority', 1)),
          processor(
            'latePriority',
            PriorityLogging('latePriority', Ordered.lowestPrecedence),
          ),
          BeanDefinition<Repo>(
            name: 'repo',
            create: (_) => _InitRepo(),
            postConstruct: (bean) => bean.connect(),
          ),
        ]),
      ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
      expect(log, [
        'priority:before',
        'repo:postConstruct',
        'latePriority:before',
        'ordered:before',
        'plain:before',
        'afterPropertiesSet',
        'priority:after',
        'latePriority:after',
        'ordered:after',
        'plain:after',
      ]);
      context.close();
    });

    test('a processor added to the factory directly runs before it', () {
      final context = AnnotationConfigApplicationContext([
        BeanModule('m', [repo()]),
      ], environment: StandardEnvironment(systemEnvironment: {}));
      context.beanFactory.addBeanPostProcessor(Logging('programmatic'));
      context.refresh();
      expect(
        log,
        containsAllInOrder([
          'programmatic:before',
          'repo:postConstruct',
          'programmatic:after',
        ]),
      );
      context.close();
    });

    test('a bare factory without it runs @PostConstruct after every '
        'postProcessBeforeInitialization', () {
      final factory = DefaultListableBeanFactory()
        ..addBeanPostProcessor(OrderedLogging('a', 1))
        ..registerBeanDefinition(repo());
      factory.getBean<Repo>();
      expect(log, [
        'repo:create',
        'repo:inject',
        'a:before',
        'repo:postConstruct',
        'a:after',
      ]);
    });

    test('a bare factory with it runs @PostConstruct at its place', () {
      final factory = DefaultListableBeanFactory()
        ..addBeanPostProcessor(Logging('first'))
        ..addBeanPostProcessor(CommonAnnotationBeanPostProcessor())
        ..addBeanPostProcessor(Logging('second'))
        ..registerBeanDefinition(repo());
      factory.getBean<Repo>();
      expect(log, [
        'repo:create',
        'repo:inject',
        'first:before',
        'repo:postConstruct',
        'second:before',
        'first:after',
        'second:after',
      ]);
      expect(
        CommonAnnotationBeanPostProcessor().order,
        Ordered.lowestPrecedence - 3,
      );
    });
  });

  group('InstantiationAwareBeanPostProcessor', () {
    test('postProcessBeforeInstantiation short-circuits creation', () {
      final fake = FakeRepo();
      final factory = DefaultListableBeanFactory()
        ..addBeanPostProcessor(Instantiation(replace: fake))
        ..addBeanPostProcessor(Logging('plain'))
        ..registerBeanDefinition(repo());
      expect(factory.getBean<Repo>(), same(fake));
      // No creation, injection, before-init or init callbacks: only the
      // postProcessAfterInitialization of the processors.
      expect(log, ['beforeInstantiation(Repo, repo)', 'plain:after']);
      log.clear();
      factory.destroySingletons();
      expect(log, isEmpty, reason: 'no destroy callbacks, like Spring');
    });

    test('postProcessAfterInstantiation and postProcessProperties', () {
      final factory = DefaultListableBeanFactory()
        ..addBeanPostProcessor(Instantiation())
        ..registerBeanDefinition(repo());
      factory.getBean<Repo>();
      expect(log, [
        'beforeInstantiation(Repo, repo)',
        'repo:create',
        'afterInstantiation(repo)',
        'repo:inject',
        'properties(repo, url: db)',
        'repo:postConstruct',
      ]);
    });

    test('postProcessAfterInstantiation returning false skips injection', () {
      final factory = DefaultListableBeanFactory()
        ..addBeanPostProcessor(Instantiation(inject: false))
        ..registerBeanDefinition(repo());
      expect(factory.getBean<Repo>().url, isNull);
      expect(log, isNot(contains('repo:inject')));
      expect(log.where((e) => e.startsWith('properties')), isEmpty);
      expect(log, contains('repo:postConstruct'));
    });

    test('SmartInstantiationAware predictBeanType answers getType', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(repo());
      expect(factory.getType('repo'), Repo);
      factory.addBeanPostProcessor(Instantiation(predict: FakeRepo));
      expect(factory.getType('repo'), FakeRepo);
    });
  });

  group('MergedBeanDefinitionPostProcessor', () {
    test('called once per definition, before injection', () {
      final factory = DefaultListableBeanFactory()
        ..addBeanPostProcessor(Merged())
        ..registerBeanDefinition(repo(scope: ScopeType.prototype));
      factory
        ..getBean<Repo>()
        ..getBean<Repo>();
      expect(log.where((e) => e.startsWith('merged')), ['merged(Repo, repo)']);
      expect(log.sublist(0, 3), [
        'repo:create',
        'merged(Repo, repo)',
        'repo:inject',
      ]);
    });

    test('resetBeanDefinition when the definition is replaced or removed', () {
      final factory = DefaultListableBeanFactory()
        ..allowBeanDefinitionOverriding = true
        ..addBeanPostProcessor(Merged())
        ..registerBeanDefinition(repo());
      factory.getBean<Repo>();
      factory.registerBeanDefinition(repo());
      expect(log, contains('reset(repo)'));
      log.clear();
      factory.getBean<Repo>();
      expect(log, contains('merged(Repo, repo)'));
      log.clear();
      factory.removeBeanDefinition('repo');
      expect(log, contains('reset(repo)'));
    });
  });
}

class _InitRepo extends Repo implements InitializingBean {
  @override
  void afterPropertiesSet() => log.add('afterPropertiesSet');
}
