import 'package:spring_core_dart/spring_core_dart.dart';

/// The conditions a context evaluated and their outcomes, grouped by what
/// they guard, like Spring Boot's `ConditionEvaluationReport`.
/// `SpringApplication` logs it (at INFO, logger
/// `spring_boot_dart.ConditionEvaluationReport`) after the refresh, or when
/// the start fails, if `debug` is set (`--debug`, `debug=true`).
///
/// ```dart
/// final report = ConditionEvaluationReport.of(context);
/// print(report.negativeMatches.keys); // what was left out, and why
/// print(report);
/// ```
///
/// Spring (Java):
/// ```java
/// ConditionEvaluationReport report =
///     ConditionEvaluationReport.get(context.getBeanFactory());
/// ```
final class ConditionEvaluationReport {
  /// The report of [evaluations] (in evaluation order).
  ConditionEvaluationReport(Iterable<ConditionEvaluation> evaluations)
    : evaluations = List.unmodifiable(evaluations);

  /// The report of [context]'s last refresh (empty for a context that is
  /// not an `AnnotationConfigApplicationContext`).
  factory ConditionEvaluationReport.of(ApplicationContext context) =>
      ConditionEvaluationReport(
        context is AnnotationConfigApplicationContext
            ? context.conditionEvaluations
            : const [],
      );

  /// Every outcome, in evaluation order.
  final List<ConditionEvaluation> evaluations;

  /// The outcomes per source (bean name or configuration class), in the
  /// order the sources were first evaluated.
  Map<String, List<ConditionEvaluation>> get bySource {
    final result = <String, List<ConditionEvaluation>>{};
    for (final evaluation in evaluations) {
      result.putIfAbsent(evaluation.source, () => []).add(evaluation);
    }
    return result;
  }

  /// The sources whose conditions all matched.
  Map<String, List<ConditionEvaluation>> get positiveMatches => {
    for (final MapEntry(:key, :value) in bySource.entries)
      if (value.every((e) => e.matched)) key: value,
  };

  /// The sources with a condition that did not match.
  Map<String, List<ConditionEvaluation>> get negativeMatches => {
    for (final MapEntry(:key, :value) in bySource.entries)
      if (value.any((e) => !e.matched)) key: value,
  };

  /// The report as Spring Boot prints it.
  @override
  String toString() {
    final out = StringBuffer()
      ..writeln()
      ..writeln()
      ..writeln('============================')
      ..writeln('CONDITIONS EVALUATION REPORT')
      ..writeln('============================')
      ..writeln()
      ..writeln()
      ..writeln('Positive matches:')
      ..writeln('-----------------')
      ..writeln();
    final positive = positiveMatches;
    if (positive.isEmpty) {
      out
        ..writeln('    None')
        ..writeln();
    }
    for (final MapEntry(:key, :value) in positive.entries) {
      out.writeln('   $key matched:');
      for (final evaluation in value) {
        out.writeln('      - ${evaluation.condition} matched');
      }
      out.writeln();
    }
    out
      ..writeln()
      ..writeln('Negative matches:')
      ..writeln('-----------------')
      ..writeln();
    final negative = negativeMatches;
    if (negative.isEmpty) {
      out
        ..writeln('    None')
        ..writeln();
    }
    for (final MapEntry(:key, :value) in negative.entries) {
      out
        ..writeln('   $key:')
        ..writeln('      Did not match:');
      for (final evaluation in value.where((e) => !e.matched)) {
        out.writeln('         - ${evaluation.condition} did not match');
      }
      final matched = value.where((e) => e.matched).toList();
      if (matched.isNotEmpty) {
        out.writeln('      Matched:');
        for (final evaluation in matched) {
          out.writeln('         - ${evaluation.condition} matched');
        }
      }
      out.writeln();
    }
    return out.toString();
  }
}
