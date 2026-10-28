import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// A hook that sees every bean as it is created, and may change or replace
/// it before the container hands it out.
///
/// This is how cross-cutting features are built: wrapping beans in
/// proxies (AOP, caching, transactions), checking or logging every bean,
/// injecting something special. Applications rarely write one; the
/// starters and annotations bring the ones they need. Both methods may
/// return a different object (a wrapper); the defaults return the bean
/// unchanged.
///
/// An application context finds post-processor beans by itself, creates
/// them before the other beans and orders them by `PriorityOrdered`,
/// `Ordered` or `@Order`. On a bare factory, register them with
/// `ConfigurableBeanFactory.addBeanPostProcessor`. A post-processor only
/// sees beans created after it was added, so it should depend on few
/// beans.
///
/// ```dart
/// // Log each bean when it is ready.
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
  /// Called for each new bean after injection and the aware callbacks,
  /// before the init callbacks (`@PostConstruct`, `afterPropertiesSet`,
  /// init method). Returns the object to go on with, usually [bean]
  /// itself.
  Object postProcessBeforeInitialization(Object bean, String beanName) => bean;

  /// Called for each new bean after its init callbacks. The returned
  /// object (a proxy, say) is what the container exposes and injects.
  /// Also applied to `FactoryBean` products.
  Object postProcessAfterInitialization(Object bean, String beanName) => bean;
}

/// A [BeanPostProcessor] that is also called before each bean is
/// destroyed.
///
/// Use it to release, in one place, something that many beans hold
/// without each declaring a destroy callback: closing every sink, ending
/// every subscription a framework added. It runs before the bean's own
/// `@PreDestroy` and destroy callbacks. For one bean, a `@PreDestroy`
/// method is simpler.
///
/// ```dart
/// // Close every bean that is a Sink, when the context closes.
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
  /// Called with the exposed bean (the one others received) before its
  /// `@PreDestroy`, `DisposableBean.destroy` and destroy-method callbacks
  /// run. Errors are logged and collected; they do not stop the shutdown.
  void postProcessBeforeDestruction(Object bean, String beanName);

  /// Whether [bean] needs [postProcessBeforeDestruction]; `true` by
  /// default. Returning `false` lets the container skip tracking beans
  /// that have no destroy callbacks of their own.
  bool requiresDestruction(Object bean) => true;
}

/// A hook that runs once at startup, after all bean definitions are
/// registered and before any ordinary bean is created, to inspect or
/// change them.
///
/// Use it to adjust beans you did not declare yourself: make a library's
/// bean lazy, change a scope, check that a required bean exists. It sees
/// definitions, not beans. Declared as a bean, it is created and run by
/// the application context during refresh, before the bean graph is
/// validated. Most applications never need one.
///
/// ```dart
/// // The slow `reports` bean starts on first use, not at startup.
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
  /// primary, ...). Avoid creating beans here: they would be created before
  /// the bean post-processors exist and miss their processing.
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory);
}

/// A [BeanFactoryPostProcessor] that may also add, remove or replace bean
/// definitions, before any `postProcessBeanFactory` runs.
///
/// Use it when the set of beans is only known at startup: one bean per
/// entry of a configuration file, one per plug-in found. Definitions it
/// registers are seen by every later post-processor. A library uses it more
/// often than an application.
///
/// ```dart
/// // Adds a German greeter, written by hand, to the scanned greeters.
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
  /// Adds, removes or replaces definitions in [registry]. Runs before every
  /// [BeanFactoryPostProcessor.postProcessBeanFactory], this processor's
  /// own included.
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry);
}

/// A [BeanPostProcessor] that is also called around the creation and the
/// injection of each bean, not only around its initialization.
///
/// It is for framework code that must supply a bean instead of the
/// container (a stub in tests, a remote proxy), skip or add injection.
/// Applications almost never need it.
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
/// // In tests, the remote client is replaced by a fake one.
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
  /// The object to use as the bean [beanName] instead of creating one of
  /// [beanType], or `null` (the default) to create it as usual. A returned
  /// object gets no injection, init or destroy callbacks; only
  /// `postProcessAfterInitialization` runs on it.
  Object? postProcessBeforeInstantiation(Type beanType, String beanName) =>
      null;

  /// Called right after [bean] was constructed. Return `false` to skip its
  /// field, setter and method injection (and the following
  /// [postProcessProperties] calls); `true` by default.
  bool postProcessAfterInstantiation(Object bean, String beanName) => true;

  /// Called after the fields and setters of [bean] were injected, before
  /// the aware callbacks and the init callbacks: the place to inject or
  /// check more.
  void postProcessProperties(Object bean, String beanName) {}
}

/// An [InstantiationAwareBeanPostProcessor] that can also tell the type a
/// bean will have before it is created.
///
/// Write one when your processor replaces beans with objects of another
/// type, so that `getType(name)` reports that type without creating the
/// bean. Applications almost never need it. Spring's
/// `SmartInstantiationAwareBeanPostProcessor` also has
/// `getEarlyBeanReference` and `determineCandidateConstructors`; they have
/// no counterpart here, because there are no early references for circular
/// dependencies and the generator picks the constructor.
///
/// ```dart
/// // This processor replaces Repo beans with an instrumented subclass.
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
  /// The type the bean named [beanName] will have, or `null` (the default)
  /// when it keeps [beanType], the definition's type.
  Type? predictBeanType(Type beanType, String beanName) => null;
}

/// A [BeanPostProcessor] that is shown each bean definition once, when
/// its first bean has been constructed and before it is injected.
///
/// Framework code uses it to read and cache what it needs from a
/// definition (its annotations, say) once, rather than on every bean.
/// [postProcessMergedBeanDefinition] runs once per definition;
/// [resetBeanDefinition] runs when the definition is replaced or removed,
/// to drop the cache. Applications almost never need it. The name comes
/// from Spring's `MergedBeanDefinitionPostProcessor`; Dart definitions
/// have no parents, so they are already "merged".
///
/// ```dart
/// // Keeps the annotations of each bean for later lookups.
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
  /// Called once for [definition] of the bean [beanName] (of class
  /// [beanType]), after its first instance is constructed and before it is
  /// injected.
  void postProcessMergedBeanDefinition(
    BeanDefinition<Object> definition,
    Type beanType,
    String beanName,
  );

  /// The definition named [beanName] was replaced or removed: drop what
  /// was cached for it.
  void resetBeanDefinition(String beanName) {}
}

/// A marker in the post-processor chain that says where the
/// `@PostConstruct` methods run.
///
/// It does nothing itself: when the factory reaches it in the chain, it
/// runs the bean's `@PostConstruct` methods. It is [PriorityOrdered] with
/// order `Ordered.lowestPrecedence - 3`, so `@PostConstruct` runs after
/// the `postProcessBeforeInitialization` of the processors before it
/// (`PriorityOrdered` ones with a smaller order, those added to the
/// factory directly) and before the others (`Ordered` and plain ones), as
/// in Spring. `afterPropertiesSet` and init methods still run after all of
/// them. An application context registers it; on a bare factory without
/// it, `@PostConstruct` runs after every `postProcessBeforeInitialization`.
/// Add it to a bare factory to get the context's order.
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
  /// Creates the marker; it holds no state.
  CommonAnnotationBeanPostProcessor();

  /// The bean name an application context registers it under.
  static const beanName =
      // A string that cannot be split without changing it.
      // ignore: lines_longer_than_80_chars
      'org.springframework.context.annotation.internalCommonAnnotationProcessor';

  @override
  int get order => Ordered.lowestPrecedence - 3;
}
