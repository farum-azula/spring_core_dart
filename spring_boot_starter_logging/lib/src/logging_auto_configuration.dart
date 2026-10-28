import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/log_buffer.dart';
import 'package:spring_boot_starter_logging/src/logging_system.dart';

const _source = 'package:spring_boot_starter_logging#LoggingAutoConfiguration';

const _enabled = [
  ConditionGroup(_source, [
    ConditionalOnProperty('logging.enabled', matchIfMissing: true),
  ]),
];

/// The bean definitions this starter adds to every application that
/// depends on it.
///
/// - `loggingSystemInitializer`, a [LoggingSystemInitializer]: configures
///   [LoggingSystem.instance] from the `logging.*` properties and installs
///   it before any application bean is created, and uninstalls it when the
///   context closes.
/// - `loggingSystem`: [LoggingSystem.instance], so a bean can inject it to
///   change levels at runtime.
/// - `logBuffer`: its [LogBuffer], so a log screen can inject it.
///
/// `logging.enabled=false` leaves all three out, and `SpringLog` keeps its
/// plain output. Applications do not use this list directly; the
/// generator adds it through `springBootStarterLoggingAutoConfiguration`.
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
