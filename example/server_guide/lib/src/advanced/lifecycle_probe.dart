// Every lifecycle callback of a bean, in the order the container calls
// them: constructor, injection, Aware interfaces, @PostConstruct,
// InitializingBean, the init method; on close a
// DestructionAwareBeanPostProcessor, @PreDestroy, DisposableBean, the
// destroy method.
import 'package:neon_books_server/src/advanced/advanced_tour.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// What the probe saw, in order.
final lifecycleEvents = <String>[];

class LifecycleProbe
    implements
        BeanNameAware,
        BeanFactoryAware,
        EnvironmentAware,
        ApplicationContextAware,
        InitializingBean,
        DisposableBean {
  LifecycleProbe() {
    lifecycleEvents.add('constructor');
  }

  @Autowired()
  void inject(Environment environment) =>
      lifecycleEvents.add('@Autowired method');

  @override
  void setBeanName(String name) => lifecycleEvents.add('setBeanName($name)');

  @override
  void setBeanFactory(BeanFactory beanFactory) =>
      lifecycleEvents.add('setBeanFactory');

  @override
  void setEnvironment(Environment environment) =>
      lifecycleEvents.add('setEnvironment');

  @override
  void setApplicationContext(ApplicationContext context) =>
      lifecycleEvents.add('setApplicationContext');

  @PostConstruct()
  void postConstruct() => lifecycleEvents.add('@PostConstruct');

  @override
  void afterPropertiesSet() => lifecycleEvents.add('afterPropertiesSet');

  void customInit() => lifecycleEvents.add('initMethod');

  @PreDestroy()
  void preDestroy() => lifecycleEvents.add('@PreDestroy');

  @override
  void destroy() => lifecycleEvents.add('DisposableBean.destroy');

  void customDestroy() => lifecycleEvents.add('destroyMethod');
}

@Configuration()
@AdvancedTour()
class LifecycleConfig {
  @Bean(initMethod: 'customInit', destroyMethod: 'customDestroy')
  LifecycleProbe lifecycleProbe() => LifecycleProbe();
}

/// Runs before the destroy callbacks of the beans it asks for.
@Component()
@AdvancedTour()
class ShutdownWatcher extends DestructionAwareBeanPostProcessor {
  @override
  bool requiresDestruction(Object bean) => bean is LifecycleProbe;

  @override
  void postProcessBeforeDestruction(Object bean, String beanName) =>
      lifecycleEvents.add('DestructionAwareBeanPostProcessor($beanName)');
}
