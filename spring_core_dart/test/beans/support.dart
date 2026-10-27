import 'package:spring_core_dart/spring_core_dart.dart';

/// Shared fixtures for container tests.
final log = <String>[];

abstract interface class Greeter {
  String greet();
}

class English implements Greeter {
  @override
  String greet() => 'hello';
}

class French implements Greeter {
  @override
  String greet() => 'bonjour';
}

class German implements Greeter {
  @override
  String greet() => 'hallo';
}

class OrderedGreeter implements Greeter, Ordered {
  OrderedGreeter(this.order);
  @override
  final int order;
  @override
  String greet() => 'ordered $order';
}

class PriorityGreeter implements Greeter, PriorityOrdered {
  @override
  int get order => 100;
  @override
  String greet() => 'priority';
}

class Counter {
  Counter() {
    created++;
  }
  static int created = 0;
}

class Holder {
  Holder(this.greeter);
  final Greeter greeter;
  Counter? counter;
  String? value;
}

/// Records every lifecycle step.
class LifecycleBean
    implements
        InitializingBean,
        DisposableBean,
        BeanNameAware,
        BeanFactoryAware {
  LifecycleBean(this.id) {
    log.add('$id:construct');
  }
  final String id;
  String? beanName;
  BeanFactory? factory;

  void inject() => log.add('$id:inject');
  void postConstruct() => log.add('$id:postConstruct');
  void customInit() => log.add('$id:initMethod');
  void preDestroy() => log.add('$id:preDestroy');
  void customDestroy() => log.add('$id:destroyMethod');

  @override
  void setBeanName(String name) {
    beanName = name;
    log.add('$id:beanName');
  }

  @override
  void setBeanFactory(BeanFactory beanFactory) {
    factory = beanFactory;
    log.add('$id:beanFactory');
  }

  @override
  void afterPropertiesSet() => log.add('$id:afterPropertiesSet');

  @override
  void destroy() => log.add('$id:destroy');
}

BeanDefinition<LifecycleBean> lifecycleDefinition(
  String name, {
  List<String> dependsOn = const [],
  List<Dependency> dependencies = const [],
  void Function(DependencyResolver r)? onCreate,
  bool lazy = false,
  String scope = ScopeType.singleton,
}) => BeanDefinition<LifecycleBean>(
  name: name,
  dependsOn: dependsOn,
  dependencies: dependencies,
  lazy: lazy,
  scope: scope,
  create: (r) {
    onCreate?.call(r);
    return LifecycleBean(name);
  },
  inject: (bean, _) => bean.inject(),
  postConstruct: (bean) => bean.postConstruct(),
  initMethod: (bean) => bean.customInit(),
  preDestroy: (bean) => bean.preDestroy(),
  destroyMethod: (bean) => bean.customDestroy(),
);

class RecordingPostProcessor extends DestructionAwareBeanPostProcessor {
  RecordingPostProcessor(this.id);
  final String id;

  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    log.add('$id:before:$beanName');
    return bean;
  }

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    log.add('$id:after:$beanName');
    return bean;
  }

  @override
  void postProcessBeforeDestruction(Object bean, String beanName) =>
      log.add('$id:destruction:$beanName');

  @override
  bool requiresDestruction(Object bean) => bean is LifecycleBean;
}

class GreeterFactory extends FactoryBean<Greeter> {
  GreeterFactory({this.singleton = true});
  final bool singleton;
  int calls = 0;

  @override
  Greeter getObject() {
    calls++;
    return German();
  }

  @override
  bool get isSingleton => singleton;
}

BeanDefinition<English> english({
  bool primary = false,
  bool fallback = false,
  int? order,
  List<String> aliases = const [],
  Set<String> qualifiers = const {},
  bool autowireCandidate = true,
}) => BeanDefinition<English>(
  name: 'english',
  types: const [English, Greeter],
  primary: primary,
  fallback: fallback,
  order: order,
  aliases: aliases,
  qualifiers: qualifiers,
  autowireCandidate: autowireCandidate,
  create: (_) => English(),
);

BeanDefinition<French> french({
  bool primary = false,
  bool fallback = false,
  int? order,
  Set<String> qualifiers = const {},
}) => BeanDefinition<French>(
  name: 'french',
  types: const [French, Greeter],
  primary: primary,
  fallback: fallback,
  order: order,
  qualifiers: qualifiers,
  create: (_) => French(),
);
