import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/scheduled_annotation_bean_post_processor.dart';
import 'package:spring_boot_starter_scheduling/src/task_scheduler.dart';

const _source =
    'package:spring_boot_starter_scheduling#SchedulingAutoConfiguration';

const _enabled = ConditionalOnProperty(
  'spring.task.scheduling.enabled',
  matchIfMissing: true,
);

/// The bean definitions this starter adds to every application that
/// depends on it. Applications do not use the list directly; the
/// generator adds it through `springBootStarterSchedulingAutoConfiguration`.
///
/// - `taskScheduler`, a [TimerTaskScheduler], unless the application
///   declares its own [TaskScheduler]. It reads the shutdown properties
///   below and uses the only or primary `ErrorHandler` bean.
/// - `scheduledAnnotationBeanPostProcessor`, the
///   [ScheduledAnnotationBeanPostProcessor] that finds `@Scheduled`
///   methods and runs them.
/// - `applicationTaskExecutor` (alias `taskExecutor`), a
///   [SimpleAsyncTaskExecutor], unless the application declares a
///   [TaskExecutor]; having one turns `@Async` event listeners on, as
///   Spring Boot's `TaskExecutionAutoConfiguration` does.
///
/// Spring Boot schedules only with `@EnableScheduling`; here the
/// dependency is enough. `spring.task.scheduling.enabled=false` switches
/// scheduling off, which keeps tests deterministic: no scheduler and no
/// tasks; the executor stays. With
/// `spring.task.scheduling.shutdown.await-termination=true` the context's
/// `closeAsync()` waits for the runs going on, at most
/// `spring.task.scheduling.shutdown.await-termination-period`.
///
/// ```properties
/// spring.task.scheduling.enabled=false
/// spring.task.scheduling.shutdown.await-termination=true
/// spring.task.scheduling.shutdown.await-termination-period=30s
/// ```
final schedulingAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<TaskExecutor>(
    name: 'applicationTaskExecutor',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'applicationTaskExecutor',
    aliases: const [
      AnnotationConfigApplicationContext.defaultTaskExecutorBeanName,
    ],
    types: const [TaskExecutor, SimpleAsyncTaskExecutor],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.applicationTaskExecutor', [
        ConditionalOnMissingBean(TaskExecutor),
      ]),
    ],
    create: (_) => SimpleAsyncTaskExecutor(),
  ),
  BeanDefinition<TaskScheduler>(
    name: 'taskScheduler',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'taskScheduler',
    types: const [TaskScheduler, TimerTaskScheduler, DisposableBean],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.taskScheduler', [
        _enabled,
        ConditionalOnMissingBean(TaskScheduler),
      ]),
    ],
    create: (r) {
      // Spring Boot's TaskSchedulingProperties.Shutdown.
      final environment = r.dependency<Environment>();
      return TimerTaskScheduler(
        awaitTermination:
            environment.getPropertyAs<bool>(
              'spring.task.scheduling.shutdown.await-termination',
            ) ??
            false,
        awaitTerminationPeriod: environment.getPropertyAs<Duration>(
          'spring.task.scheduling.shutdown.await-termination-period',
        ),
        // The only (or primary) ErrorHandler bean; none when ambiguous.
        errorHandler: r.provider<ErrorHandler>().getIfUnique(),
      );
    },
  ),
  BeanDefinition<ScheduledAnnotationBeanPostProcessor>(
    name: 'scheduledAnnotationBeanPostProcessor',
    types: const [
      ScheduledAnnotationBeanPostProcessor,
      BeanPostProcessor,
      BeanFactoryAware,
      SmartLifecycle,
      Lifecycle,
      DisposableBean,
    ],
    source: _source,
    conditions: const [
      ConditionGroup(_source, [_enabled]),
    ],
    create: (r) => ScheduledAnnotationBeanPostProcessor(
      // Like Spring: the only TaskScheduler, the primary one, or the one
      // named `taskScheduler` (others are picked with @Scheduled(scheduler:)).
      r.dependency<TaskScheduler>(name: 'taskScheduler'),
      r.dependency<Environment>(),
    ),
  ),
];
