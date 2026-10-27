import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/order.dart';

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

/// A post-processor that also hooks into instantiation, like Spring's
/// `InstantiationAwareBeanPostProcessor`.
///
/// [postProcessBeforeInstantiation] may return the bean itself (a proxy,
/// a stub), short-circuiting the container: no instantiation, injection
/// or init callbacks; only [postProcessAfterInitialization] of the
/// processors still runs on it. [postProcessAfterInstantiation] returning
/// `false` skips the injection of the bean's fields and setters;
/// [postProcessProperties] runs right after that injection (Spring's
/// `AutowiredAnnotationBeanPostProcessor` injects there; in Dart the
/// generated code does, so it is the hook to inject or check more).
///
/// ```dart
/// class StubRemote extends InstantiationAwareBeanPostProcessor {
///   @override
///   Object? postProcessBeforeInstantiation(Type beanType, String beanName) =>
///       beanType == RemoteClient ? FakeRemoteClient() : null;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class StubRemote implements InstantiationAwareBeanPostProcessor {
///   public Object postProcessBeforeInstantiation(Class<?> type, String name) {
///     return type == RemoteClient.class ? new FakeRemoteClient() : null;
///   }
/// }
/// ```
abstract class InstantiationAwareBeanPostProcessor extends BeanPostProcessor {
  /// The bean to use instead of creating one of [beanType], or `null` to
  /// create it as usual.
  Object? postProcessBeforeInstantiation(Type beanType, String beanName) =>
      null;

  /// Whether the fields and setters of the freshly created [bean] are
  /// injected; `false` skips the injection (and the following
  /// [postProcessProperties] calls).
  bool postProcessAfterInstantiation(Object bean, String beanName) => true;

  /// Called after the fields and setters of [bean] were injected, before
  /// the Aware callbacks and init callbacks.
  void postProcessProperties(Object bean, String beanName) {}
}

/// An [InstantiationAwareBeanPostProcessor] that predicts bean types, like
/// Spring's `SmartInstantiationAwareBeanPostProcessor`:
/// [predictBeanType] answers `getType(name)` for a bean not created yet
/// (e.g. a processor that replaces beans with subtypes). Dart has no
/// early references for circular dependencies and the generator picks the
/// constructor, so `getEarlyBeanReference` and
/// `determineCandidateConstructors` have no counterpart.
///
/// ```dart
/// class Instrumenting extends SmartInstantiationAwareBeanPostProcessor {
///   @override
///   Type? predictBeanType(Type beanType, String beanName) =>
///       beanType == Repo ? InstrumentedRepo : null;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Instrumenting implements SmartInstantiationAwareBeanPostProcessor {
///   public Class<?> predictBeanType(Class<?> type, String name) { ... }
/// }
/// ```
abstract class SmartInstantiationAwareBeanPostProcessor
    extends InstantiationAwareBeanPostProcessor {
  /// The type the bean named [beanName] will have, or `null` for
  /// [beanType] (the definition's).
  Type? predictBeanType(Type beanType, String beanName) => null;
}

/// A post-processor told about each bean definition before its first
/// bean is initialized, like Spring's `MergedBeanDefinitionPostProcessor`
/// (Dart definitions have no parents, so they are already "merged").
/// [postProcessMergedBeanDefinition] runs once per definition, after the
/// first instance is created and before it is injected (cache metadata
/// there); [resetBeanDefinition] when the definition is replaced or
/// removed.
///
/// ```dart
/// class Metadata extends MergedBeanDefinitionPostProcessor {
///   final cache = <String, List<Object>>{};
///   @override
///   void postProcessMergedBeanDefinition(
///     BeanDefinition<Object> definition,
///     Type beanType,
///     String beanName,
///   ) => cache[beanName] = definition.annotations;
///   @override
///   void resetBeanDefinition(String beanName) => cache.remove(beanName);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Metadata implements MergedBeanDefinitionPostProcessor {
///   public void postProcessMergedBeanDefinition(
///       RootBeanDefinition definition, Class<?> type, String name) { ... }
/// }
/// ```
abstract class MergedBeanDefinitionPostProcessor extends BeanPostProcessor {
  /// Called once for [definition] (of a bean of [beanType]) before its
  /// first bean is injected.
  void postProcessMergedBeanDefinition(
    BeanDefinition<Object> definition,
    Type beanType,
    String beanName,
  );

  /// The definition named [beanName] was replaced or removed: drop what
  /// was cached for it.
  void resetBeanDefinition(String beanName) {}
}

/// Where `@PostConstruct` methods run in the post-processor chain, like
/// Spring's `CommonAnnotationBeanPostProcessor`: a [PriorityOrdered]
/// processor with order `Ordered.lowestPrecedence - 3`, so `@PostConstruct`
/// runs after the `postProcessBeforeInitialization` of the processors
/// before it (`PriorityOrdered` ones with a smaller order, those added to
/// the factory directly) and before the others (`Ordered` and plain
/// ones). `afterPropertiesSet` and init methods still run after all of
/// them. An application context registers it; on a bare factory without
/// it, `@PostConstruct` runs after every `postProcessBeforeInitialization`.
///
/// ```dart
/// factory.addBeanPostProcessor(CommonAnnotationBeanPostProcessor());
/// ```
///
/// Spring (Java):
/// ```java
/// factory.addBeanPostProcessor(new CommonAnnotationBeanPostProcessor());
/// ```
class CommonAnnotationBeanPostProcessor extends BeanPostProcessor
    implements PriorityOrdered {
  /// The `@PostConstruct` step (stateless; the factory runs the callbacks
  /// when it reaches this processor).
  CommonAnnotationBeanPostProcessor();

  /// The bean name an application context registers it under.
  static const beanName =
      // A string that cannot be split without changing it.
      // ignore: lines_longer_than_80_chars
      'org.springframework.context.annotation.internalCommonAnnotationProcessor';

  @override
  int get order => Ordered.lowestPrecedence - 3;
}
