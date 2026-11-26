import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean.dart';

/// A bean (or a configuration class) left out because a condition did not
/// match: a profile not active, a property not set, a bean missing or
/// already there. From the condition evaluation report.
final class DebugSkippedBean {
  /// The bean or class [source] of [module], left out by [conditions].
  const DebugSkippedBean({
    required this.source,
    required this.module,
    required this.application,
    required this.conditions,
  });

  /// What the conditions guard: a bean name, or a configuration class
  /// (`package:app/cache.dart#CacheConfig`).
  final String source;

  /// The module it would have been in.
  final String module;

  /// Whether the application defined it.
  final bool application;

  /// Every condition evaluated for it, the ones that matched too.
  final List<DebugBeanCondition> conditions;

  /// The conditions that did not match: why it is not there.
  Iterable<DebugBeanCondition> get failed =>
      conditions.where((condition) => !condition.matched);

  @override
  String toString() => 'DebugSkippedBean($source: ${failed.join(', ')})';
}
