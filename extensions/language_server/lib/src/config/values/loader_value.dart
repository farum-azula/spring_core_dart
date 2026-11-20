import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/config_value_role.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/config/theme_loaders.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// The value of `splash.loader`, `splash.animation` (a name declared under
/// `loaders` or `animations`) or of a loader's `web:` (an `.html` file):
/// it goes to the declaration or the file, and completes with the names or
/// the files.
final class LoaderValue extends ConfigValueRole {
  /// The role over [model].
  LoaderValue(this.model) : _loaders = ThemeLoaders(model);

  /// What the workspace knows.
  final ProjectModel model;

  final ThemeLoaders _loaders;

  @override
  Handled<List<SourceRange>>? definition(
    ConfigDocument document,
    ConfigKey key,
    int column,
  ) {
    final found = _loaders.definition(document.path, key);
    return found.isEmpty ? null : Handled(found);
  }

  @override
  Handled<CompletionResult>? complete(ValueCompletionRequest request) {
    final relative = themeRelative(request.segments);
    if (relative == null || relative.rest.isEmpty) {
      return null;
    }
    final rest = relative.rest.map(canonicalName).toList();
    final List<Completion> items;
    if (ThemeLoaders.sectionNamedBy(rest) case final section?) {
      final what = section == 'loaders' ? 'loader' : 'animation';
      items = [
        for (final name in _loaders.declaredNames(request.path, section))
          Completion(name, kind: 20, detail: what),
      ];
    } else if (rest.length == 3 && rest[0] == 'loaders' && rest[2] == 'web') {
      items = [
        for (final file in _loaders.webFiles(request.path))
          Completion(file, kind: 17, detail: 'web page loader'),
      ];
    } else {
      return null;
    }
    if (items.isEmpty) {
      return null;
    }
    final word = RegExp(r'[A-Za-z0-9_.\-/$]*$').firstMatch(request.valueText)!;
    return Handled(
      CompletionResult(
        request.rangeFrom(request.valueStart + word.start),
        items,
      ),
    );
  }
}
