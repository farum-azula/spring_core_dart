import 'package:dart_spring_language_server/src/diagnostics/checks/container_check.dart';
import 'package:dart_spring_language_server/src/diagnostics/checks/injection_check.dart';
import 'package:dart_spring_language_server/src/diagnostics/checks/interpolated_placeholder_check.dart';
import 'package:dart_spring_language_server/src/diagnostics/checks/query_check.dart';
import 'package:dart_spring_language_server/src/diagnostics/checks/string_role_check.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem_check.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/project_model.dart';

/// The checks of Dart files, in the order their problems are listed.
List<ProblemCheck> problemChecks(ProjectModel model) => [
  InterpolatedPlaceholderCheck(model.locations),
  StringRoleCheck(model.roles),
  QueryCheck(model.query, model.derived),
  InjectionCheck(model),
  ContainerCheck(model.locations),
];

/// The problems of Dart files, for the editor to underline: what the
/// [problemChecks] find in one walk of the file.
///
/// - an interpolated `'${key}'` in a template annotation (error: write
///   `r'${key}'`);
/// - what the string roles check: an unclosed placeholder or SpEL
///   expression, invalid SpEL, a `${key}` that nothing defines, an invalid
///   pointcut, an unknown variable in a cache key, an unknown message
///   code, route or profile, a missing or undeclared `asset:`;
/// - the SQL of `@Query` methods and the names of derived queries;
/// - an injection point without a bean, or with several and none
///   `@Primary`;
/// - a test's containers used the wrong way.
final class DartProblems {
  /// The checks over [model].
  DartProblems(this.model) : _checks = problemChecks(model);

  /// What the workspace knows.
  final ProjectModel model;

  final List<ProblemCheck> _checks;

  /// The problems of the Dart file [path]; empty for other files.
  List<Problem> problems(String path) {
    final file = model.files.dartFile(path);
    if (file == null) {
      return const [];
    }
    final facts = DartFileFacts.of(file);
    final problems = <Problem>[];
    for (final check in _checks) {
      check.check(facts, problems);
    }
    return problems;
  }
}
