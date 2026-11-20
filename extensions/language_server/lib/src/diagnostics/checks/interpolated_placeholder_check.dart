import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem_check.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/strings/roles/template_role.dart';
import 'package:dart_spring_language_server/src/symbols/source_locations.dart';

/// An interpolated `'${key}'` in a string of a template annotation
/// ([templateAnnotations]): Dart replaces it before the framework sees
/// it, so it is an error; the fix is a raw string, `r'${key}'`.
final class InterpolatedPlaceholderCheck implements ProblemCheck {
  /// The check, with [locations] for the ranges.
  const InterpolatedPlaceholderCheck(this.locations);

  /// Turns offsets into ranges.
  final SourceLocations locations;

  @override
  void check(DartFileFacts facts, List<Problem> problems) {
    for (final (node, annotation) in facts.interpolations) {
      if (annotation != null &&
          templateAnnotations.contains(annotationName(annotation))) {
        problems.add(
          Problem(
            locations.rangeOf(facts.file, node.offset, node.end),
            r'In Dart ${...} in a normal string is interpolation, not a '
            r"placeholder: use a raw string, r'${key}' (or escape: '\${key}')",
            error: true,
          ),
        );
      }
    }
  }
}
