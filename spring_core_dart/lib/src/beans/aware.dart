import 'package:spring_core_dart/src/beans/bean_factory.dart';

/// Marker for callbacks that hand container objects to a bean, like
/// Spring's `Aware`.
///
/// Aware callbacks run after injection and before
/// `postProcessBeforeInitialization`. See [BeanNameAware] and
/// [BeanFactoryAware]; the context package adds more (e.g.
/// `ApplicationContextAware`).
///
/// ```dart
/// @Service()
/// class Audit implements BeanNameAware {
///   late String name;
///
///   @override
///   void setBeanName(String name) => this.name = name;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Audit implements BeanNameAware {
///   String name;
///   @Override public void setBeanName(String name) { this.name = name; }
/// }
/// ```
abstract interface class Aware {}

/// Receives its bean name, like Spring's `BeanNameAware`.
///
/// ```dart
/// @Component()
/// class Worker implements BeanNameAware {
///   late final String id;
///
///   @override
///   void setBeanName(String name) => id = name;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Worker implements BeanNameAware {
///   String id;
///   @Override public void setBeanName(String name) { id = name; }
/// }
/// ```
abstract interface class BeanNameAware implements Aware {
  /// Called with the bean's canonical name (not an alias) after injection.
  void setBeanName(String name);
}

/// Receives its bean factory, like Spring's `BeanFactoryAware`.
///
/// Injecting `BeanFactory` (or `ObjectProvider<T>`) through the
/// constructor is usually simpler; this is mostly for framework code.
///
/// ```dart
/// @Component()
/// class PluginLoader implements BeanFactoryAware {
///   late BeanFactory factory;
///
///   @override
///   void setBeanFactory(BeanFactory beanFactory) => factory = beanFactory;
///
///   Plugin load(String name) => factory.getBeanByName(name) as Plugin;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class PluginLoader implements BeanFactoryAware {
///   BeanFactory factory;
///   @Override public void setBeanFactory(BeanFactory beanFactory) {
///     factory = beanFactory;
///   }
///   Plugin load(String name) { return (Plugin) factory.getBean(name); }
/// }
/// ```
abstract interface class BeanFactoryAware implements Aware {
  /// Called with the owning factory after injection and [BeanNameAware].
  void setBeanFactory(BeanFactory beanFactory);
}
