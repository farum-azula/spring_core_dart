import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem_check.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/strings/string_roles.dart';

/// What the string roles check in the strings of the file: placeholders
/// and SpEL, pointcuts, cache keys, message codes, routes, profiles,
/// assets. Role by role, each in the order of the source.
final class StringRoleCheck implements ProblemCheck {
  /// The checks of [roles].
  const StringRoleCheck(this.roles);

  /// The roles a string can have.
  final StringRoles roles;

  @override
  void check(DartFileFacts facts, List<Problem> problems) =>
      roles.problems(facts.strings, problems);
}
