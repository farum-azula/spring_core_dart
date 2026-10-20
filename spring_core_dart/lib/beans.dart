/// Bean definitions, the bean factory, injection, post-processors, scopes,
/// `BeanWrapper` and introspection (Spring's `spring-beans`).
///
/// ```dart
/// final factory = DefaultListableBeanFactory()
///   ..registerBeanDefinition(
///     BeanDefinition<Clock>(name: 'clock', create: (_) => SystemClock()),
///   );
/// final clock = factory.getBean<Clock>();
/// ```
///
/// Spring (Java):
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
export 'package:spring_core_dart/src/beans/bean_wrapper.dart';
export 'package:spring_core_dart/src/beans/default_listable_bean_factory.dart';
export 'package:spring_core_dart/src/beans/exceptions.dart';
export 'package:spring_core_dart/src/beans/factory_bean.dart';
export 'package:spring_core_dart/src/beans/introspection.dart';
export 'package:spring_core_dart/src/beans/lifecycle_callbacks.dart';
export 'package:spring_core_dart/src/beans/object_provider.dart';
export 'package:spring_core_dart/src/beans/post_processors.dart';
export 'package:spring_core_dart/src/beans/scope.dart';
