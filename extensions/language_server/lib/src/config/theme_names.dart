import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';

/// The names of the themes a file sees: `light` and `dark`, and those its
/// package and dependencies declare under `themes:`.
final class ThemeNames {
  /// Theme names over [model].
  const ThemeNames(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  /// The theme names for the file [path], sorted.
  List<String> of(String path) {
    final names = <String>{'light', 'dark'};
    for (final entry in model.properties.configEntries(path)) {
      final segments = splitKey(entry.key);
      if (isThemeKey(segments)) {
        if (themeOf(segments) case final theme?) {
          names.add(theme);
        }
      }
    }
    return names.toList()..sort();
  }
}
