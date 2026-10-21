import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/log_buffer.dart';
import 'package:spring_boot_starter_logging/src/logging_system.dart';

const _source = 'package:spring_boot_starter_logging#LoggingAutoConfiguration';

const _enabled = [
  ConditionGroup(_source, [
    ConditionalOnProperty('logging.enabled', matchIfMissing: true),
  ]),
];

/// The beans of [LoggingSystem]: the initializer, the system itself and
/// its [LogBuffer] (inject it into a log screen). Off with
/// `logging.enabled=false`.
final loggingAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<LoggingSystemInitializer>(
    name: 'loggingSystemInitializer',
    types: const [
      LoggingSystemInitializer,
      BeanFactoryPostProcessor,
      PriorityOrdered,
      Ordered,
      DisposableBean,
    ],
    source: _source,
    conditions: _enabled,
    create: (r) => LoggingSystemInitializer(r.dependency<Environment>()),
  ),
  BeanDefinition<LoggingSystem>(
    name: 'loggingSystem',
    source: _source,
    conditions: _enabled,
    create: (_) => LoggingSystem.instance,
  ),
  BeanDefinition<LogBuffer>(
    name: 'logBuffer',
    source: _source,
    conditions: _enabled,
    create: (_) => LoggingSystem.instance.buffer,
  ),
];
