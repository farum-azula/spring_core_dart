import 'package:spring_core_dart/spring_core_dart.dart';

/// A copy of every log record written while the application starts, kept
/// for a logging system that is set up later.
///
/// A logging system such as `spring_boot_starter_logging` is a bean, so it
/// only starts writing to its log file once the context is being created.
/// The first lines of a run (config files read, profiles, the banner) come
/// before that. `SpringApplication` collects them from the very start and
/// registers this object as the bean [beanName]; the logging system takes
/// the records with [switchOver] and writes them to its own outputs. The
/// records still reach the `SpringLog.handler` of the time as usual, so
/// they are not shown twice on the console. `SpringApplication` stops
/// collecting by itself once the context is refreshed or the start fails.
///
/// Only a logging system needs it; applications never do.
///
/// ```dart
/// // In the logging system's BeanFactoryPostProcessor, once its appenders
/// // exist: write the early records to the log file too.
/// if (beanFactory.containsBean(DeferredLogs.beanName)) {
///   final logs =
///       beanFactory.getBeanByName(DeferredLogs.beanName) as DeferredLogs;
///   logs.switchOver().forEach(fileAppender.append);
/// }
/// ```
///
/// Spring (Java): Spring Boot's `DeferredLogs`, which a logging system
/// replays in the same way.
final class DeferredLogs {
  DeferredLogs._();

  /// Starts collecting every record logged through `SpringLog` from now
  /// on, until [switchOver] is called. `SpringApplication` creates one per
  /// run.
  factory DeferredLogs.capture() {
    final logs = DeferredLogs._();
    logs._stop = SpringLog.listen(logs._records.add);
    return logs;
  }

  /// The bean name under which `SpringApplication` registers the
  /// collector of the current run.
  static const beanName = 'springBootDeferredLogs';

  final _records = <SpringLogRecord>[];
  void Function()? _stop;

  /// Whether records are still being collected: true until the first
  /// [switchOver].
  bool get isCapturing => _stop != null;

  /// Stops collecting and returns the records collected so far, oldest
  /// first.
  ///
  /// The records are handed over once: a second call returns an empty
  /// list. Whoever calls it first gets them, so a logging system should
  /// call it while the context is refreshed, before `SpringApplication`
  /// stops the collection at the end of the refresh.
  List<SpringLogRecord> switchOver() {
    _stop?.call();
    _stop = null;
    final records = List.of(_records);
    _records.clear();
    return records;
  }
}
