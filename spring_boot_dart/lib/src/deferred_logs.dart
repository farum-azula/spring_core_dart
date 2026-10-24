import 'package:spring_core_dart/spring_core_dart.dart';

/// The records logged while an application starts, before a logging
/// system takes over, like Spring Boot's `DeferredLogs`: `SpringApplication`
/// collects them from the start of a run and registers them as the bean
/// [beanName], so a logging system (`spring_boot_starter_logging`) can
/// replay them into its appenders (a log file, the log buffer). The
/// records still reach the `SpringLog.handler` of the time, as usual.
///
/// ```dart
/// final logs = beanFactory.getBeanByName(DeferredLogs.beanName) as DeferredLogs;
/// logs.switchOver().forEach(appender.append);
/// ```
final class DeferredLogs {
  DeferredLogs._();

  /// Collects every record emitted from now on, until [switchOver].
  factory DeferredLogs.capture() {
    final logs = DeferredLogs._();
    logs._stop = SpringLog.listen(logs._records.add);
    return logs;
  }

  /// The name of the bean `SpringApplication` registers.
  static const beanName = 'springBootDeferredLogs';

  final _records = <SpringLogRecord>[];
  void Function()? _stop;

  /// Whether records are still being collected.
  bool get isCapturing => _stop != null;

  /// Stops collecting and hands over the records so far (once: a second
  /// call gives none).
  List<SpringLogRecord> switchOver() {
    _stop?.call();
    _stop = null;
    final records = List.of(_records);
    _records.clear();
    return records;
  }
}
