/// The dependency-injection container: bean definitions, the bean factory
/// that creates and wires the beans, scopes, lifecycle callbacks and the
/// post-processor hooks, plus `BeanWrapper` and the compile-time
/// introspection that data binding and SpEL read.
///
/// Import it when you use the container without an application context
/// (a small tool, a test), or when you write library code that registers
/// bean definitions or post-processes beans. An application normally does
/// not import it on its own: it declares beans with annotations
/// (`@Component()`, `@Bean()`), lets the generator write the definitions
/// and starts an `ApplicationContext`, which owns a factory from this
/// library. `package:spring_core_dart/spring_core_dart.dart` exports it.
///
/// ```dart
/// // A container without a context: one bean registered by hand.
/// final factory = DefaultListableBeanFactory()
///   ..registerBeanDefinition(
///     BeanDefinition<Clock>(name: 'clock', create: (_) => SystemClock()),
///   );
/// final clock = factory.getBean<Clock>();
/// ```
///
/// Spring (Java): the `spring-beans` module.
/// ```java
/// var factory = new DefaultListableBeanFactory();
/// factory.registerBeanDefinition("clock",
///     new RootBeanDefinition(SystemClock.class));
/// Clock clock = factory.getBean(Clock.class);
/// ```
library;

export 'package:spring_core_dart/src/beans/aware.dart';
export 'package:spring_core_dart/src/beans/bean_definition.dart';
export 'package:spring_core_dart/src/beans/bean_factory.dart';
export 'package:spring_core_dart/src/beans/bean_factory_utils.dart';
export 'package:spring_core_dart/src/beans/bean_wrapper.dart';
export 'package:spring_core_dart/src/beans/default_listable_bean_factory.dart';
export 'package:spring_core_dart/src/beans/exceptions.dart';
export 'package:spring_core_dart/src/beans/factory_bean.dart';
export 'package:spring_core_dart/src/beans/interface_proxy.dart';
export 'package:spring_core_dart/src/beans/introspection.dart';
export 'package:spring_core_dart/src/beans/lifecycle_callbacks.dart';
export 'package:spring_core_dart/src/beans/null_bean.dart';
export 'package:spring_core_dart/src/beans/object_provider.dart';
export 'package:spring_core_dart/src/beans/post_processors.dart';
export 'package:spring_core_dart/src/beans/scope.dart';
export 'package:spring_core_dart/src/beans/type_info.dart';
