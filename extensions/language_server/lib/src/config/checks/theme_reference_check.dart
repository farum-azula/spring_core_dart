import 'package:dart_spring_language_server/src/config/config_check.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/config/theme_references.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';

/// A `$` reference of a theme value that no theme of the package or its
/// dependencies declares and that is not built in: an error, with a
/// did-you-mean. Headers and image keys take no references.
final class ThemeReferenceCheck implements ConfigKeyCheck {
  /// The check.
  const ThemeReferenceCheck();

  @override
  void check(ConfigCheckPass pass, ResolvedKey key, List<Problem> problems) {
    final config = key.key;
    if (key.resolution.isUnknown ||
        !key.hasPlainValue ||
        !key.isTheme ||
        takesNoReferences(config.segments)) {
      return;
    }
    for (final reference in themeReferences(config.value!)) {
      if (pass.references.exists(reference.path)) {
        continue;
      }
      final guess = pass.references.closest(reference.path);
      problems.add(
        Problem(
          pass.document.range(
            config.line,
            config.valueStart + reference.start,
            config.valueStart + reference.end,
          ),
          'Unknown reference \$${reference.path.join('.')}'
          "${guess == null ? '' : ". Did you mean \$$guess?"}",
          error: true,
        ),
      );
    }
  }
}
