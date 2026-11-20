import 'package:dart_spring_language_server/src/config/checks/color_object_check.dart';
import 'package:dart_spring_language_server/src/config/checks/loader_check.dart';
import 'package:dart_spring_language_server/src/config/checks/placeholder_check.dart';
import 'package:dart_spring_language_server/src/config/checks/theme_reference_check.dart';
import 'package:dart_spring_language_server/src/config/checks/unknown_key_check.dart';
import 'package:dart_spring_language_server/src/config/checks/value_check.dart';
import 'package:dart_spring_language_server/src/config/config_check.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/project_model.dart';

/// The checks of each key of a config file, in the order their problems
/// are listed for a key: a new check is a new class and one entry here.
List<ConfigKeyCheck> configKeyChecks(ProjectModel model) => [
  const UnknownKeyCheck(),
  const ValueCheck(),
  const ThemeReferenceCheck(),
  PlaceholderCheck(model),
];

/// The checks of a whole config file, after those of its keys.
List<ConfigDocumentCheck> configDocumentChecks(ProjectModel model) => [
  LoaderCheck(model),
  const ColorObjectCheck(),
];

/// The problems of config files: unknown keys and theme keys, values of
/// the wrong type or out of range, `${}` that nothing defines and invalid
/// SpEL, unknown `$` references of the theme, incomplete color objects,
/// loaders with keys their kind does not take.
final class ConfigProblems {
  /// The checks over [model].
  ConfigProblems(this.model)
    : _keyChecks = configKeyChecks(model),
      _documentChecks = configDocumentChecks(model);

  /// What the workspace knows.
  final ProjectModel model;

  final List<ConfigKeyCheck> _keyChecks;
  final List<ConfigDocumentCheck> _documentChecks;

  /// The problems of [document].
  List<Problem> problems(ConfigDocument document) {
    final pass = ConfigCheckPass(model, document);
    final problems = <Problem>[];
    for (final key in document.keys) {
      if (pass.reported.any((p) => startsWithSegments(key.segments, p))) {
        continue;
      }
      final resolved = ResolvedKey(key, pass.schema.resolve(key.segments));
      pass.checked.add(resolved);
      for (final check in _keyChecks) {
        check.check(pass, resolved, problems);
      }
    }
    for (final check in _documentChecks) {
      check.check(pass, problems);
    }
    return problems;
  }
}
