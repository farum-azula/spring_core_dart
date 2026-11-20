import 'package:dart_spring_language_server/src/derived_queries.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem_check.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/query_editor.dart';

/// The repositories of the file (read from its declarations, not a walk
/// of the whole tree): the SQL of their `@Query` methods and the names of
/// their derived queries.
final class QueryCheck implements ProblemCheck {
  /// The checks of [query] and [derived].
  const QueryCheck(this.query, this.derived);

  /// The editor of `@Query` texts.
  final QueryEditor query;

  /// The editor of derived query names.
  final DerivedQueryEditor derived;

  @override
  void check(DartFileFacts facts, List<Problem> problems) {
    final file = facts.file;
    problems
      ..addAll(query.problems(file, file.path))
      ..addAll(derived.problems(file, file.path));
  }
}
