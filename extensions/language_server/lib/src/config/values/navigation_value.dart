import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/config_value_role.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// A path of `spring.flutter.navigation.initial`, `login` or `redirects`:
/// it goes to the screen it opens.
final class NavigationValue extends ConfigValueRole {
  /// The role over [model].
  const NavigationValue(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<List<SourceRange>>? definition(
    ConfigDocument document,
    ConfigKey key,
    int column,
  ) {
    final value = (key.value ?? '').trim();
    if (!isNavigationPath(key.segments) || !value.startsWith('/')) {
      return null;
    }
    final screens = model.screens.screensOf(document.path, value);
    return Handled(
      screens.definitions(TargetContext(model.locations, document.text, 0)),
    );
  }
}
