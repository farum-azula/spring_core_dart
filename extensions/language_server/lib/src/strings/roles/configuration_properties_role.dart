import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// The prefix of `@ConfigurationProperties('shop')`: it goes to the keys
/// the class binds (`shop.*`) in the config files of its package.
final class ConfigurationPropertiesRole extends StringRole {
  /// The role, over [model].
  const ConfigurationPropertiesRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) {
    if (string.annotationType != 'ConfigurationProperties') {
      return null;
    }
    final prefix = string.value;
    return Handled(
      PropertyTarget(
        '$prefix.*',
        model.properties.propertiesWithPrefix(prefix, from: string.path),
      ),
    );
  }
}
