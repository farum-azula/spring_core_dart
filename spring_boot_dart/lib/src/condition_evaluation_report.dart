import 'package:spring_core_dart/spring_core_dart.dart';

/// The list of `@Conditional...` checks made while the beans were
/// registered, with which ones matched and which did not.
///
/// Auto-configuration adds or skips beans depending on conditions (is
/// there already such a bean, is a property set). When a bean you
/// expected is missing, or one appears that you did not expect, this
/// report says why. The usual way to see it is to start the application
/// with `--debug` (or `debug=true` in a config file): `SpringApplication`
/// then logs it at INFO under the logger
/// `spring_boot_dart.ConditionEvaluationReport` after the start, or after
/// a failed start. Without `debug`, a failed start logs how to get it.
///
/// Read it in code in a test, to check that a starter backs off:
///
/// ```dart
/// final report = ConditionEvaluationReport.of(context);
/// // The sources that were left out, with the conditions that failed.
/// expect(report.negativeMatches.keys, contains('cache'));
/// ```
///
/// Spring (Java):
/// ```java
/// ConditionEvaluationReport report =
///     ConditionEvaluationReport.get(context.getBeanFactory());
/// ```
final class ConditionEvaluationReport {
  /// A report of [evaluations], given in the order they were made. Use
  /// [ConditionEvaluationReport.of] to get the report of a context.
  ConditionEvaluationReport(Iterable<ConditionEvaluation> evaluations)
    : evaluations = List.unmodifiable(evaluations);

  /// The report of the conditions evaluated by [context]'s last refresh.
  ///
  /// It is empty for a context that is not an
  /// `AnnotationConfigApplicationContext`, the kind `SpringApplication`
  /// creates.
  factory ConditionEvaluationReport.of(ApplicationContext context) =>
      ConditionEvaluationReport(
        context is AnnotationConfigApplicationContext
            ? context.conditionEvaluations
            : const [],
      );

  /// Every outcome, in the order the conditions were evaluated.
  final List<ConditionEvaluation> evaluations;

  /// The outcomes grouped by what the conditions guard: a bean name, a
  /// configuration class (`package:app#CacheConfig`) or a
  /// `@PropertySource`. Sources come in the order they were first
  /// evaluated; the map is computed on each call.
  Map<String, List<ConditionEvaluation>> get bySource {
    final result = <String, List<ConditionEvaluation>>{};
    for (final evaluation in evaluations) {
      result.putIfAbsent(evaluation.source, () => []).add(evaluation);
    }
    return result;
  }

  /// The sources whose conditions all matched: what was registered
  /// because of them.
  Map<String, List<ConditionEvaluation>> get positiveMatches => {
    for (final MapEntry(:key, :value) in bySource.entries)
      if (value.every((e) => e.matched)) key: value,
  };

  /// The sources with at least one condition that did not match: what
  /// was left out. Each list holds all the source's outcomes, the matched
  /// ones too.
  Map<String, List<ConditionEvaluation>> get negativeMatches => {
    for (final MapEntry(:key, :value) in bySource.entries)
      if (value.any((e) => !e.matched)) key: value,
  };

  /// The report in Spring Boot's text layout (`CONDITIONS EVALUATION
  /// REPORT`, positive matches, then negative matches), as it is logged
  /// with `--debug`.
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
