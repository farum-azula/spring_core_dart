import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/scheduled_annotation_bean_post_processor.dart';
import 'package:spring_boot_starter_scheduling/src/task_scheduler.dart';

const _source =
    'package:spring_boot_starter_scheduling#SchedulingAutoConfiguration';

const _enabled = ConditionalOnProperty(
  'spring.task.scheduling.enabled',
  matchIfMissing: true,
);

/// The beans of the scheduling starter: a [TaskScheduler]
/// ([TimerTaskScheduler], unless the application declares its own) and the
/// [ScheduledAnnotationBeanPostProcessor] that runs `@Scheduled` methods.
///
/// Spring Boot schedules only with `@EnableScheduling`; here the
/// dependency is enough. Switch it off with
/// `spring.task.scheduling.enabled=false` (handy in tests).
///
/// ```properties
/// spring.task.scheduling.enabled=false
/// ```
final schedulingAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<TaskScheduler>(
    name: 'taskScheduler',
    types: const [TaskScheduler, TimerTaskScheduler, DisposableBean],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.taskScheduler', [
        _enabled,
        ConditionalOnMissingBean(TaskScheduler),
      ]),
    ],
    create: (_) => TimerTaskScheduler(),
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
