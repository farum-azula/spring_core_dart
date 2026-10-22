import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/cron_expression.dart';
import 'package:spring_boot_starter_scheduling/src/scheduled.dart';
import 'package:spring_boot_starter_scheduling/src/task_scheduler.dart';
import 'package:spring_boot_starter_scheduling/src/trigger.dart';

const _log = SpringLog('spring.scheduling');

/// Finds `@Scheduled` methods and runs them, like Spring's
/// `ScheduledAnnotationBeanPostProcessor`. Registered by the starter's
/// auto-configuration; you rarely use it directly.
///
/// The methods come from `BeanDefinition.annotatedMethods` (written by the
/// generator). Each `@Scheduled` is checked when its bean is created —
/// a wrong attribute fails the startup naming `Class.method` — and becomes
/// a task when the context has been refreshed (beans created later, e.g.
/// `@Lazy` ones, start right away). Closing the context cancels them.
/// Only singletons are scheduled; `@Scheduled` on other scopes is ignored
/// with a warning.
///
/// The method is called on the bean as other beans see it, so AOP advice
/// (`@Around`, `@Cacheable`, ...) applies.
///
/// ```dart
/// final processor = context.getBean<ScheduledAnnotationBeanPostProcessor>();
/// for (final task in processor.scheduledTasks) {
///   print('${task.name}: next at ${task.nextExecution}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// ScheduledAnnotationBeanPostProcessor processor =
///     context.getBean(ScheduledAnnotationBeanPostProcessor.class);
/// processor.getScheduledTasks().forEach(System.out::println);
/// ```
final class ScheduledAnnotationBeanPostProcessor extends BeanPostProcessor
    implements BeanFactoryAware, SmartLifecycle, DisposableBean {
  /// A processor scheduling through [scheduler], resolving placeholders
  /// with [environment].
  ScheduledAnnotationBeanPostProcessor(this.scheduler, this.environment);

  /// Runs the tasks.
  final TaskScheduler scheduler;

  /// Resolves `${...}` in the attributes.
  final PropertyResolver environment;

  BeanFactory? _beanFactory;
  final _definitions = <_ScheduledMethod>[];
  final _tasks = <ScheduledTask>[];
  var _running = false;

  /// The running tasks of `@Scheduled` methods.
  List<ScheduledTask> get scheduledTasks => List.unmodifiable(_tasks);

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (factory is! BeanDefinitionRegistry ||
        !(factory as BeanDefinitionRegistry).containsBeanDefinition(beanName)) {
      return bean;
    }
    final definition = (factory as BeanDefinitionRegistry).getBeanDefinition(
      beanName,
    );
    final methods = [
      for (final method in definition.annotatedMethods)
        if (method.annotations.whereType<Scheduled>().isNotEmpty) method,
    ];
    if (methods.isEmpty) {
      return bean;
    }
    final owner = _typeName(definition.beanType);
    if (definition.scope != ScopeType.singleton) {
      _log.warning(
        "@Scheduled methods of $owner are ignored: bean '$beanName' has "
        "scope '${definition.scope}'; only singletons are scheduled",
      );
      return bean;
    }
    final found = <_ScheduledMethod>[];
    for (final method in methods) {
      final name = '$owner.${method.name}';
      if (method.parameterTypes.isNotEmpty) {
        throw StateError(
          'Invalid @Scheduled method $name: it must not take parameters',
        );
      }
      for (final annotation in method.annotations.whereType<Scheduled>()) {
        final trigger = _trigger(annotation, name);
        if (trigger != null) {
          found.add(_ScheduledMethod(name, beanName, method, trigger));
        }
      }
    }
    _definitions.addAll(found);
    if (_running) {
      found.forEach(_start);
    }
    return bean;
  }

  // The trigger of one @Scheduled, or null when its cron is `-`.
  Trigger? _trigger(Scheduled scheduled, String method) {
    Never invalid(String reason) =>
        throw StateError('Invalid @Scheduled on $method: $reason');

    String resolve(String text, String attribute) {
      try {
        return environment.resolveRequiredPlaceholders(text).trim();
      } on Object catch (error) {
        invalid('$attribute "$text": $error');
      }
    }

    Duration? duration(Duration? value, String? text, String attribute) {
      if (value != null && text != null) {
        invalid('give $attribute or ${attribute}String, not both');
      }
      if (text != null) {
        final resolved = resolve(text, '${attribute}String');
        try {
          value = DurationStyle.parse(resolved);
        } on FormatException catch (error) {
          invalid(
            '${attribute}String "$text" is not a duration '
            '(${error.message})',
          );
        }
      }
      if (value != null && value.isNegative) {
        invalid('$attribute must not be negative');
      }
      return value;
    }

    final rate = duration(
      scheduled.fixedRate,
      scheduled.fixedRateString,
      'fixedRate',
    );
    final delay = duration(
      scheduled.fixedDelay,
      scheduled.fixedDelayString,
      'fixedDelay',
    );
    final initialDelay = duration(
      scheduled.initialDelay,
      scheduled.initialDelayString,
      'initialDelay',
    );
    final kinds = [scheduled.cron != null, rate != null, delay != null];
    final count = kinds.where((k) => k).length;
    if (count != 1) {
      invalid(
        count == 0
            ? 'give one of cron, fixedRate or fixedDelay'
            : 'give only one of cron, fixedRate or fixedDelay',
      );
    }
    if (scheduled.cron case final cron?) {
      if (initialDelay != null) {
        invalid('initialDelay is not supported with cron');
      }
      final expression = resolve(cron, 'cron');
      if (expression == Scheduled.cronDisabled) {
        _log.debug('@Scheduled $method is switched off (cron "-")');
        return null;
      }
      final zone = scheduled.zone == null
          ? null
          : resolve(scheduled.zone!, 'zone');
      final utc = switch (zone?.toUpperCase()) {
        null || '' => false,
        'UTC' || 'Z' || 'GMT' => true,
        _ => invalid(
          'zone "$zone" is not supported: use UTC or leave it out for '
          'local time (Dart has no time zone database)',
        ),
      };
      try {
        return CronTrigger(CronExpression.parse(expression), utc: utc);
      } on FormatException catch (error) {
        invalid(error.message);
      }
    }
    final period = rate ?? delay!;
    if (period == Duration.zero) {
      invalid('${rate != null ? 'fixedRate' : 'fixedDelay'} must be positive');
    }
    return PeriodicTrigger(
      period,
      fixedRate: rate != null,
      initialDelay: initialDelay ?? Duration.zero,
    );
  }

  void _start(_ScheduledMethod scheduled) {
    Object? target;
    _tasks.add(
      scheduler.schedule(
        () {
          // Looked up at the first run: the bean as other beans see it
          // (its AOP proxy), which exists only once creation is finished.
          target ??= _beanFactory!.getBeanByName(scheduled.beanName);
          final bean = target!;
          final method = scheduled.method;
          final result = method.invoke(
            method.appliesTo(bean) ? bean : AopUtils.getTarget(bean),
            const [],
          );
          // A returned Future is awaited; other results are ignored.
          return result is Future ? result : null;
        },
        scheduled.trigger,
        name: scheduled.name,
      ),
    );
  }

  /// Starts the tasks (at context refresh).
  @override
  void start() {
    if (_running) {
      return;
    }
    _running = true;
    _definitions.forEach(_start);
  }

  /// Cancels the tasks (at context close); [start] schedules them again.
  @override
  void stop() {
    _running = false;
    for (final task in _tasks) {
      task.cancel();
    }
    _tasks.clear();
  }

  @override
  bool get isRunning => _running;

  @override
  bool get isAutoStartup => true;

  /// Starts after the other lifecycle beans and stops before them.
  @override
  int get phase => SmartLifecycle.defaultPhase;

  @override
  void destroy() => stop();

  static String _typeName(Type type) {
    final name = type.toString();
    final generic = name.indexOf('<');
    return generic < 0 ? name : name.substring(0, generic);
  }
}

final class _ScheduledMethod {
  _ScheduledMethod(this.name, this.beanName, this.method, this.trigger);

  final String name;
  final String beanName;
  final BeanMethod<Object> method;
  final Trigger trigger;
}
