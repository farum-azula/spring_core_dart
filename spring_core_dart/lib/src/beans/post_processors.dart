import 'package:spring_core_dart/src/beans/bean_factory.dart';

/// Hooks into bean initialization, like Spring's `BeanPostProcessor`.
///
/// Both methods may return a different object (e.g. a wrapper); the default
/// returns the bean unchanged. Order processors with `Ordered` /
/// `PriorityOrdered` / `@Order`. An application context detects
/// post-processor beans automatically; on a bare factory register them
/// with `ConfigurableBeanFactory.addBeanPostProcessor`.
///
/// ```dart
/// @Component()
/// class TimingPostProcessor extends BeanPostProcessor {
///   @override
///   Object postProcessAfterInitialization(Object bean, String beanName) {
///     print('ready: $beanName');
///     return bean;
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class TimingPostProcessor implements BeanPostProcessor {
///   @Override
///   public Object postProcessAfterInitialization(Object bean, String name) {
///     System.out.println("ready: " + name);
///     return bean;
///   }
/// }
/// ```
///
/// Init callbacks always run on the raw instance, even if
/// [postProcessBeforeInitialization] returned a wrapper.
abstract class BeanPostProcessor {
  /// Called after injection and aware callbacks, before the init callbacks
  /// (`@PostConstruct`, `afterPropertiesSet`, init method). Returns the
  /// object to expose (usually [bean] itself).
  Object postProcessBeforeInitialization(Object bean, String beanName) => bean;

  /// Called after the init callbacks; the returned object (e.g. a proxy)
  /// is what the container exposes and injects. Also applied to
  /// `FactoryBean` products.
  Object postProcessAfterInitialization(Object bean, String beanName) => bean;
}

/// A [BeanPostProcessor] that is also told about destruction, like Spring's
/// `DestructionAwareBeanPostProcessor`.
///
/// ```dart
/// class ClosingPostProcessor extends DestructionAwareBeanPostProcessor {
///   @override
///   bool requiresDestruction(Object bean) => bean is Sink<Object?>;
///
///   @override
///   void postProcessBeforeDestruction(Object bean, String beanName) =>
///       (bean as Sink<Object?>).close();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class ClosingPostProcessor implements DestructionAwareBeanPostProcessor {
///   @Override
///   public boolean requiresDestruction(Object bean) {
///     return bean instanceof AutoCloseable;
///   }
///   @Override
///   public void postProcessBeforeDestruction(Object bean, String name)
///       throws Exception {
///     ((AutoCloseable) bean).close();
///   }
/// }
/// ```
abstract class DestructionAwareBeanPostProcessor extends BeanPostProcessor {
  /// Called with the exposed bean before its `@PreDestroy`,
  /// `DisposableBean.destroy` and destroy-method callbacks run. Errors are
  /// collected and do not stop the shutdown.
  void postProcessBeforeDestruction(Object bean, String beanName);

  /// Whether [bean] needs [postProcessBeforeDestruction]. Returning `false`
  /// lets the container skip tracking beans without destroy callbacks.
  bool requiresDestruction(Object bean) => true;
}

/// Modifies bean definitions before any bean is created, like Spring's
/// `BeanFactoryPostProcessor`.
///
/// Declared as a bean, it is instantiated and run by the application
/// context during refresh, after all definitions are registered and before
/// the bean graph is validated and singletons are created.
///
/// ```dart
/// @Component()
/// class MakeReportsLazy implements BeanFactoryPostProcessor {
///   @override
///   void postProcessBeanFactory(ConfigurableListableBeanFactory factory) {
///     factory.getBeanDefinition('reports').lazy = true;
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class MakeReportsLazy implements BeanFactoryPostProcessor {
///   @Override
///   public void postProcessBeanFactory(
///       ConfigurableListableBeanFactory factory) {
///     factory.getBeanDefinition("reports").setLazyInit(true);
///   }
/// }
/// ```
abstract interface class BeanFactoryPostProcessor {
  /// Inspects or changes the definitions in [beanFactory] (scope, lazy,
  /// primary, ...). Avoid creating beans here: they would miss later
  /// post-processing.
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory);
}

/// Registers more bean definitions before the factory post-processors run,
/// like Spring's `BeanDefinitionRegistryPostProcessor`.
///
/// ```dart
/// @Component()
/// class GermanRegistrar implements BeanDefinitionRegistryPostProcessor {
///   @override
///   void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
///     registry.registerBeanDefinition(
///       BeanDefinition<German>(
///         name: 'german',
///         types: const [German, Greeter],
///         create: (_) => German(),
///       ),
///     );
///   }
///
///   @override
///   void postProcessBeanFactory(ConfigurableListableBeanFactory factory) {}
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class GermanRegistrar implements BeanDefinitionRegistryPostProcessor {
///   @Override
///   public void postProcessBeanDefinitionRegistry(
///       BeanDefinitionRegistry registry) {
///     registry.registerBeanDefinition("german",
///         new RootBeanDefinition(German.class));
///   }
/// }
/// ```
abstract interface class BeanDefinitionRegistryPostProcessor
    implements BeanFactoryPostProcessor {
  /// Adds, removes or replaces definitions in [registry]; runs before every
  /// [BeanFactoryPostProcessor.postProcessBeanFactory].
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry);
}
