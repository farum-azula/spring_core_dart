// A shop of hand-written beans for the tests of the debug bean graph and
// its layer: services, a repository, a `@Bean` method, a lazy bean, a
// route bean, a controller, a widget's bindings, a bean a profile leaves
// out, and an auto-configuration with a hand-written bean and an advisor.
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

Type typeOf<T>() => T;

abstract interface class Basket {
  int get count;
}

class Store {}

class Clock {}

class Audit {}

class ShopConfig {}

class OrdersController {}

class DevTools {}

class Metrics {
  Metrics(this.store);

  final Store store;
}

class ShopBasket implements Basket {
  ShopBasket(this.store, this.clock, this.audit, this.events);

  final Store store;
  final Clock Function() clock;
  final ObjectProvider<Audit> audit;
  final ApplicationEventPublisher events;

  @override
  int get count => 0;
}

class ScreenState {
  ScreenState(this.basket);

  final Basket basket;
}

// What a generated proxy is for the graph: the bean behind it and its
// advisors.
final class _AdvisedBasket implements Basket, Advised {
  _AdvisedBasket(this.aopTarget, this.aopAdvisors);

  @override
  final Object aopTarget;

  @override
  final List<PointcutAdvisor> aopAdvisors;

  @override
  int get count => 0;

  @override
  void addAdvice(MethodInterceptor advice) {}

  @override
  void addAdvisor(PointcutAdvisor advisor) {}

  @override
  bool removeAdvice(MethodInterceptor advice) => false;

  @override
  bool removeAdvisor(PointcutAdvisor advisor) => false;
}

final class _Advising extends BeanPostProcessor {
  _Advising(this.advisor);

  final PointcutAdvisor advisor;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) =>
      bean is ShopBasket ? _AdvisedBasket(bean, [advisor]) : bean;
}

const _basketSource = 'package:shop/src/basket/basket.dart#ShopBasket';
const _configSource = 'package:shop/src/config.dart#ShopConfig';
const basketBadge =
    'package:shop/src/basket/basketbasketBadge.dart#BasketBadge';

const _checkout = AopTarget('ShopBasket', types: ['ShopBasket', 'Basket']);

BeanModule _shop() => BeanModule('application', [
  BeanDefinition<_Advising>(
    name: 'advising',
    types: const [_Advising, BeanPostProcessor],
    source: 'package:shop/src/advising.dart#Advising',
    create: (r) => _Advising(r.dependency<DefaultPointcutAdvisor>()),
  ),
  BeanDefinition<ShopConfig>(
    name: 'shopConfig',
    source: _configSource,
    annotations: const [Configuration()],
    create: (_) => ShopConfig(),
  ),
  BeanDefinition<ShopBasket>(
    name: 'basket',
    types: const [ShopBasket, Basket],
    source: _basketSource,
    annotations: const [Service()],
    dependencies: const [
      Dependency(Store, name: 'store'),
      Dependency.lazy(Clock, name: 'clock'),
      Dependency.provider(Audit, name: 'audit'),
      Dependency(ApplicationEventPublisher, name: 'events'),
    ],
    aopProxy: AopProxyFactory.unavailable(
      signatures: const [
        MethodSignature.of(
          'checkout',
          _checkout,
          annotationTypes: ['Transactional', 'PreAuthorize'],
        ),
        MethodSignature.of('count', _checkout, kind: MemberKind.getter),
      ],
      reason: 'a test',
    ),
    create: (r) => ShopBasket(
      r.dependency<Store>(name: 'store'),
      r.lazyDependency<Clock>(name: 'clock'),
      r.provider<Audit>(name: 'audit'),
      r.dependency<ApplicationEventPublisher>(name: 'events'),
    ),
  ),
  BeanDefinition<Store>(
    name: 'store',
    source: 'package:shop/src/store/store.dart#Store',
    annotations: const [Repository()],
    conditions: const [
      ConditionalOnProperty(
        'shop.store.enabled',
        havingValue: 'true',
        matchIfMissing: true,
      ),
    ],
    create: (_) => Store(),
  ),
  BeanDefinition<Clock>(
    name: 'clock',
    source: '$_configSource.clock',
    factoryBeanName: 'shopConfig',
    factoryMethodName: 'clock',
    lazy: true,
    create: (_) => Clock(),
  ),
  BeanDefinition<Audit>(
    name: 'audit',
    source: 'package:shop/src/audit/audit.dart#Audit',
    annotations: const [Component()],
    eventListeners: [
      EventListenerMethod.of<Audit, ApplicationReadyEvent>(
        'Audit.onReady',
        (_, _) => null,
      ),
    ],
    create: (_) => Audit(),
  ),
  BeanDefinition<OrdersController>(
    name: 'ordersController',
    source: 'package:shop/src/orders/orders_controller.dart#OrdersController',
    annotations: const [Controller()],
    dependsOn: const ['audit'],
    create: (_) => OrdersController(),
  ),
  BeanDefinition<ScreenState>(
    name: 'screenState',
    source: 'package:shop/src/basket/screen_state.dart#ScreenState',
    scope: 'route',
    dependencies: const [Dependency(Basket, name: 'basket')],
    create: (r) => ScreenState(r.dependency<Basket>(name: 'basket')),
  ),
  BeanDefinition<DevTools>(
    name: 'devTools',
    source: 'package:shop/src/dev/dev_tools.dart#DevTools',
    conditions: const [
      ProfileCondition(['dev']),
    ],
    create: (_) => DevTools(),
  ),
  BeanDefinition<SpringWidgetBindings>(
    name: 'shopWidgetBindings',
    source: 'package:shop/main.dart#widgetBindings',
    create: (_) => SpringWidgetBindings([
      SpringWidgetBinding(
        widget: basketBadge,
        beans: typeOf<(Basket,)>(),
        types: const [Basket],
        resolve: (factory) => (factory.getBean<Basket>(),),
      ),
    ]),
  ),
]);

// An auto-configuration: a hand-written bean that declares no injection
// point, an advisor, and a bean left out by its property.
final _shopAutoConfiguration = BeanModule('shopAutoConfiguration', [
  BeanDefinition<Metrics>(
    name: 'metrics',
    source: 'package:shop_starter/spring_auto_configuration.dart',
    create: (r) => Metrics(r.dependency<Store>()),
  ),
  BeanDefinition<DefaultPointcutAdvisor>(
    name: 'notifyListenersAdvisor',
    types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
    source: 'package:shop_starter/spring_auto_configuration.dart',
    create: (_) => DefaultPointcutAdvisor(
      const NotifyListenersPointcut(),
      const NotifyListenersInterceptor(),
    ),
  ),
  BeanDefinition<DevTools>(
    name: 'metricsExporter',
    source: 'package:shop_starter/spring_auto_configuration.dart',
    conditions: const [
      ConditionalOnProperty('shop.metrics.export', havingValue: 'true'),
    ],
    create: (_) => DevTools(),
  ),
]);

final class Shop {
  Shop(this.application, this.context, this.scope) {
    graph = DebugBeanGraph(context)..useApplication(application);
  }

  final SpringApplication application;
  final ConfigurableApplicationContext context;
  final SimpleMapScope scope;
  late final DebugBeanGraph graph;

  DefaultListableBeanFactory get factory =>
      context.beanFactory as DefaultListableBeanFactory;
}

Shop startShop() {
  final application = SpringApplication(
    [_shop()],
    autoConfigurations: [_shopAutoConfiguration],
    applicationStartup: BufferingApplicationStartup(),
    bannerMode: BannerMode.off,
  );
  final context = application.run(const []);
  final scope = SimpleMapScope();
  context.beanFactory.registerScope('route', scope);
  return Shop(application, context, scope);
}

// Lets the graph's listeners hear (once per burst, in a microtask).
Future<void> settle() => Future<void>.delayed(Duration.zero);
