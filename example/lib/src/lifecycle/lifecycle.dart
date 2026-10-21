// The full bean lifecycle and Lifecycle / SmartLifecycle.
//
// Spring (Java): Aware interfaces, @PostConstruct, InitializingBean,
// initMethod, DisposableBean, @PreDestroy, SmartLifecycle phases,
// SmartInitializingSingleton.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

/// Records every callback in the order the container calls it.
class LifecycleProbe
    implements
        BeanNameAware,
        BeanFactoryAware,
        EnvironmentAware,
        ApplicationContextAware,
        InitializingBean,
        DisposableBean {
  LifecycleProbe() {
    tourLog.add('probe: constructor');
  }

  @Autowired()
  set clockName(Environment environment) =>
      tourLog.add('probe: @Autowired setter');

  @override
  void setBeanName(String name) => tourLog.add('probe: setBeanName($name)');

  @override
  void setBeanFactory(BeanFactory beanFactory) =>
      tourLog.add('probe: setBeanFactory');

  @override
  void setEnvironment(Environment environment) =>
      tourLog.add('probe: setEnvironment');

  @override
  void setApplicationContext(ApplicationContext context) =>
      tourLog.add('probe: setApplicationContext');

  @PostConstruct()
  void postConstruct() => tourLog.add('probe: @PostConstruct');

  @override
  void afterPropertiesSet() => tourLog.add('probe: afterPropertiesSet');

  void customInit() => tourLog.add('probe: initMethod');

  @PreDestroy()
  void preDestroy() => tourLog.add('probe: @PreDestroy');

  @override
  void destroy() => tourLog.add('probe: DisposableBean.destroy');

  void customDestroy() => tourLog.add('probe: destroyMethod');
}

@Configuration()
class LifecycleConfig {
  @Bean(initMethod: 'customInit', destroyMethod: 'customDestroy')
  LifecycleProbe probe() => LifecycleProbe();
}

/// Started at refresh (phase 0) and stopped on close.
@Component()
class Warehouse implements SmartLifecycle {
  @override
  bool isRunning = false;

  @override
  int get phase => 0;

  @override
  bool get isAutoStartup => true;

  @override
  void start() {
    isRunning = true;
    tourLog.add('warehouse: start (phase $phase)');
  }

  @override
  void stop() {
    isRunning = false;
    tourLog.add('warehouse: stop');
  }
}

/// Started after the warehouse (higher phase), stopped before it.
@Component()
class Courier implements SmartLifecycle {
  @override
  bool isRunning = false;

  @override
  int get phase => 10;

  @override
  bool get isAutoStartup => true;

  @override
  void start() {
    isRunning = true;
    tourLog.add('courier: start (phase $phase)');
  }

  @override
  void stop() {
    isRunning = false;
    tourLog.add('courier: stop');
  }
}

/// Called once every eager singleton exists.
@Component()
class StartupReport implements SmartInitializingSingleton {
  @override
  void afterSingletonsInstantiated() =>
      tourLog.add('startup: all singletons instantiated');
}
