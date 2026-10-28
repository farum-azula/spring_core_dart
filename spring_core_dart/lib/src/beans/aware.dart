import 'package:spring_core_dart/src/beans/bean_factory.dart';

/// The common supertype of the interfaces through which the container
/// hands a bean one of its own objects: its bean name, the bean factory,
/// the environment and so on.
///
/// A bean implements one of the subinterfaces ([BeanNameAware],
/// [BeanFactoryAware], and in the context package `EnvironmentAware`,
/// `ApplicationContextAware` and others), and the container calls its
/// setter once, after injection and before the init callbacks
/// (`@PostConstruct`, `afterPropertiesSet`). `Aware` itself has no
/// methods; it only groups them. Application code rarely needs
/// these interfaces: injecting the object through the constructor
/// (`BeanFactory`, `Environment`, `ApplicationContext`) is simpler. They
/// are for framework classes, and for the rare bean that needs its own
/// name.
///
/// ```dart
/// // An audit service that tags its log lines with its own bean name.
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

/// A bean that is told the name it is registered under.
///
/// Useful when several beans share one class and each must know which one
/// it is, for example to read its own settings or to label its logs.
/// Most beans do not care about their name.
///
/// ```dart
/// // Two workers of the same class, registered as 'importer' and
/// // 'exporter'; each reports under its own name.
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
  /// Receives the bean's name (never one of its aliases). Called once, after
  /// injection and before [BeanFactoryAware.setBeanFactory].
  void setBeanName(String name);
}

/// A bean that is handed the bean factory that created it, so it can look
/// up other beans by itself while it runs.
///
/// Use it when the beans you need are only known at run time (by a name
/// read from configuration, say). Injecting `BeanFactory` or an
/// `ObjectProvider<T>` through the constructor does the same and is
/// usually simpler; this interface is mostly for framework classes.
///
/// ```dart
/// // Plugins are beans; which one runs is decided by name at run time.
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
  /// Receives the factory that holds the bean. Called once, after
  /// injection and after [BeanNameAware.setBeanName].
  void setBeanFactory(BeanFactory beanFactory);
}
