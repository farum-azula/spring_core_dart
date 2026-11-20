import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem_check.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/symbols/source_locations.dart';
import 'package:dart_spring_language_server/src/test_properties.dart';

/// The container mistakes of a test file ([containerProblemsOf]): a
/// `@Container` field that is not `static`, `@ServiceConnection` on a
/// `GenericContainer`. Errors, as the build reports them.
final class ContainerCheck implements ProblemCheck {
  /// The check, with [locations] for the ranges.
  const ContainerCheck(this.locations);

  /// Turns offsets into ranges.
  final SourceLocations locations;

  @override
  void check(DartFileFacts facts, List<Problem> problems) {
    if (!isTestFile(facts.file.path)) {
      return;
    }
    for (final field in facts.fields) {
      for (final problem in containerProblemsOf(field)) {
        problems.add(
          Problem(
            locations.rangeOf(facts.file, problem.start, problem.end),
            problem.message,
            error: true,
          ),
        );
      }
    }
  }
}
