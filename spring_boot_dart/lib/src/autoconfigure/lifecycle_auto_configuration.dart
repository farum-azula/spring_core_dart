import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#LifecycleAutoConfiguration';

/// The `lifecycleProcessor` bean with the shutdown timeout of the
/// configuration, `spring.lifecycle.timeout-per-shutdown-phase` (30
/// seconds by default, as in Spring Boot).
///
/// When the application closes, the processor stops its lifecycle beans
/// phase by phase and waits at most this long for each phase, for
/// example for the web server's graceful shutdown to let running
/// requests finish; then it goes on and the beans are destroyed. Without
/// this bean the context's own processor would wait 10 seconds (Spring
/// Framework's default), whatever the property says.
///
/// It backs off when the application declares a bean named
/// `lifecycleProcessor` itself. Switch it off with
/// `spring.autoconfigure.exclude=LifecycleAutoConfiguration`.
///
/// ```properties
/// # Requests get up to a minute to finish when the server stops.
/// spring.lifecycle.timeout-per-shutdown-phase=1m
/// ```
///
/// Spring (Java): `LifecycleAutoConfiguration`, with the same property.
final lifecycleAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<DefaultLifecycleProcessor>(
    name: AnnotationConfigApplicationContext.lifecycleProcessorBeanName,
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'defaultLifecycleProcessor',
    types: const [DefaultLifecycleProcessor, LifecycleProcessor, Lifecycle],
    source: _source,
    conditions: const [
      ConditionalOnMissingBean.named(
        AnnotationConfigApplicationContext.lifecycleProcessorBeanName,
        search: SearchStrategy.current,
      ),
    ],
    create: (r) => DefaultLifecycleProcessor(
      r.dependency<ConfigurableListableBeanFactory>(),
      timeoutPerShutdownPhase:
          r.dependency<Environment>().getPropertyAs<Duration>(
            'spring.lifecycle.timeout-per-shutdown-phase',
          ) ??
          const Duration(seconds: 30),
    ),
  ),
];
