import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';

/// One check of Dart files: reads what one walk of the file collected
/// ([DartFileFacts]) and adds the problems it finds.
///
/// The checks are registered once, in order (`problemChecks`): a new check
/// is a new class and one entry there.
abstract interface class ProblemCheck {
  /// Adds the problems of the file of [facts] to [problems].
  void check(DartFileFacts facts, List<Problem> problems);
}
