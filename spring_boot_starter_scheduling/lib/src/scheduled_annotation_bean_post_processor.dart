import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/cron_expression.dart';
import 'package:spring_boot_starter_scheduling/src/scheduled.dart';
import 'package:spring_boot_starter_scheduling/src/task_scheduler.dart';
import 'package:spring_boot_starter_scheduling/src/trigger.dart';

const _log = SpringLog('spring.scheduling');

/// The bean that turns `@Scheduled` methods into running tasks. The
/// starter registers it; applications only look at it to list their
/// scheduled tasks, for example on an admin page or in a test.
///
/// It reads the methods from `BeanDefinition.annotatedMethods`, which the
/// generator writes. Each `@Scheduled` is checked when its bean is
/// created, so a wrong attribute fails the start naming `Class.method`.
/// The tasks start when the context has been refreshed; a bean created
/// later, such as a `@Lazy` one, starts its tasks at once. Closing the
/// context cancels them. Only singletons are scheduled: `@Scheduled` on a
/// bean of another scope is ignored with a warning.
///
/// The method is called on the bean as other beans see it, so AOP advice
/// (`@Around`, `@Cacheable`, ...) applies.
///
/// ```dart
/// // An admin command lists the scheduled tasks and their next runs.
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
    with SmartLifecycle
    implements BeanFactoryAware, DisposableBean {
  /// A processor that runs the methods on [scheduler], unless they name
  /// another one, and resolves `${...}` in the attributes with
  /// [environment].
  ScheduledAnnotationBeanPostProcessor(this.scheduler, this.environment);

  /// The default scheduler of `@Scheduled` methods, used when they give
  /// no `scheduler:`.
  final TaskScheduler scheduler;

  /// Resolves the `${...}` placeholders of the attributes.
  final PropertyResolver environment;

  BeanFactory? _beanFactory;
  final _definitions = <_ScheduledMethod>[];
  final _tasks = <ScheduledTask>[];
  var _running = false;

  /// The tasks started for `@Scheduled` methods, one per annotation, in
  /// start order. A one-time task stays listed after its run; the list is
  /// empty before the context is refreshed and after it closes.
  List<ScheduledTask> get scheduledTasks => List.unmodifiable(_tasks);

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (factory is! BeanDefinitionRegistry ||
        !(factory! as BeanDefinitionRegistry).containsBeanDefinition(
          beanName,
        )) {
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
      if (method.parameterTypes.isNotEmpty || method.parameters.isNotEmpty) {
        throw StateError(
          'Invalid @Scheduled method $name: it must not take parameters',
        );
      }
      for (final annotation in method.annotations.whereType<Scheduled>()) {
        final trigger = _trigger(annotation, name);
        if (trigger != null) {
          found.add(
            _ScheduledMethod(
              name,
              beanName,
              method,
              trigger,
              _schedulerName(annotation, name),
            ),
          );
        }
      }
    }
    _definitions.addAll(found);
    if (_running) {
      found.forEach(_start);
    }
    return bean;
  }

  // The qualifier (or bean name) of `scheduler:`, checked against the bean
  // definitions now; the bean itself is looked up when the task starts.
  String? _schedulerName(Scheduled scheduled, String method) {
    final text = scheduled.scheduler;
    if (text == null) {
      return null;
    }
    final String name;
    try {
      name = environment.resolveRequiredPlaceholders(text).trim();
    } on Object catch (error) {
      throw StateError(
        'Invalid @Scheduled on $method: scheduler "$text": '
        '$error',
      );
    }
    if (name.isEmpty) {
      return null; // like Spring's default "": the default scheduler
    }
    if (!_beanFactory!.containsBeanOfType(TaskScheduler, qualifier: name)) {
      throw StateError(
        "Invalid @Scheduled on $method: scheduler '$name': no TaskScheduler "
        'bean with this qualifier or name',
      );
    }
    return name;
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
      // Like Spring: a text that is (or resolves to) blank is not set.
      final resolved = switch (text) {
        final text? when text.trim().isNotEmpty => switch (resolve(
          text,
          '${attribute}String',
        )) {
          '' => null,
          final resolved => resolved,
        },
        _ => null,
      };
      if (value != null && resolved != null) {
        invalid('give $attribute or ${attribute}String, not both');
      }
      var result = value;
      if (resolved != null) {
        try {
          result = DurationStyle.parse(resolved);
        } on FormatException catch (error) {
          invalid(
            '${attribute}String "$text" is not a duration '
            '(${error.message})',
          );
        }
      }
      if (result != null && result.isNegative) {
        invalid('$attribute must not be negative');
      }
      return result;
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
    if (count == 0 && initialDelay != null) {
      // Spring 6.1: only an initial delay is a one-time task.
      return _OneTimeTrigger(initialDelay);
    }
    if (count != 1) {
      invalid(
        count == 0
            ? 'give one of cron, fixedRate or fixedDelay (or only '
                  'initialDelay to run once)'
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
    final scheduler = switch (scheduled.schedulerName) {
      final name? => _beanFactory!.getBean<TaskScheduler>(qualifier: name),
      null => this.scheduler,
    };
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

  /// Starts a task for every `@Scheduled` found so far. The context calls
  /// it at the end of its refresh; calling it again does nothing.
  @override
  void start() {
    if (_running) {
      return;
    }
    _running = true;
    _definitions.forEach(_start);
  }

  /// Cancels every task; runs going on finish. The context calls it when
  /// it closes. A later [start] schedules the methods again.
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

  /// The last phase, so the tasks start after the other lifecycle beans
  /// and stop before them.
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
  _ScheduledMethod(
    this.name,
    this.beanName,
    this.method,
    this.trigger,
    this.schedulerName,
  );

  final String name;
  final String beanName;
  final BeanMethod<Object> method;
  final Trigger trigger;
  // `@Scheduled(scheduler:)`; null: the default scheduler.
  final String? schedulerName;
}

// `@Scheduled(initialDelay: ...)` alone: one run, [delay] after the start
// (Spring's OneTimeTask).
final class _OneTimeTrigger implements Trigger {
  _OneTimeTrigger(this.delay);

  final Duration delay;

  @override
  DateTime? nextExecution(TriggerContext context) =>
      context.lastScheduledExecution == null ? context.now.add(delay) : null;

  @override
  String toString() => 'OneTimeTrigger(initialDelay: $delay)';
}
