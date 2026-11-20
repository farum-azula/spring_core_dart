import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// Notes about Spring metadata that is missing for the package of a Dart
/// or config file (its own, or a dependency's): one information line at
/// the top of the file telling to run `build_runner`.
final class MetadataNotes {
  /// Notes over [model].
  const MetadataNotes(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  /// The notes of [path]; empty when nothing is missing or the file is not
  /// part of a Spring package.
  List<Problem> of(String path) {
    if (!path.endsWith('.dart') && !ConfigFormat.isConfigFile(path)) {
      return const [];
    }
    final view = model.metadataFor(path);
    final name = view.packageName;
    if (name == null || view.packageRoot == null) {
      return const [];
    }
    final range = SourceRange(path, 0, 0, 0, 1);
    if (view.missing.contains(name)) {
      return [
        Problem(
          range,
          'No Spring metadata for $name: run build_runner '
          '(`dart run build_runner build`) to get completion, hovers and '
          'checks for keys, beans and the theme',
          info: true,
        ),
      ];
    }
    if (view.missing.isNotEmpty) {
      return [
        Problem(
          range,
          'No Spring metadata in ${view.missing.join(', ')}: their keys and '
          'beans are not known here (they need a version with '
          '`lib/spring_gen/spring_metadata.json`)',
          info: true,
        ),
      ];
    }
    return const [];
  }
}
