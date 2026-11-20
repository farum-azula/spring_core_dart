import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_value_role.dart';
import 'package:dart_spring_language_server/src/config/theme_names.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';

/// Theme keys whose value is the name of a theme.
const _themeNameKeys = {'active', 'systemlight', 'systemdark', 'extends'};

/// A value the schema describes: `true`/`false` for a boolean, the values
/// of a choice or a hint, the profiles for a key whose hint provides
/// them, the theme names for `active`, `extends`, ..., and `$colors.` for
/// a theme color.
final class SchemaValue extends ConfigValueRole {
  /// The role over [model].
  const SchemaValue(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<CompletionResult>? complete(ValueCompletionRequest request) {
    final segments = request.segments;
    final resolution = model.schemas.schemaFor(request.path).resolve(segments);
    final prop = resolution.isUnknown ? null : resolution.node?.prop;
    if (prop == null || resolution.rest.isNotEmpty && prop.type != 'color') {
      return null;
    }
    final items = <Completion>[
      if (prop.type == 'bool' || prop.type == 'true / false') ...const [
        Completion('true', kind: 12),
        Completion('false', kind: 12),
      ],
      for (final (value, description) in prop.values)
        Completion(value, kind: 20, documentation: description),
      if (prop.hint?.provider == 'profiles')
        for (final profile
            in model.properties.knownProfiles(request.path).toList()..sort())
          Completion(profile, kind: 20, detail: 'profile'),
      if (prop.theme) ..._themeValues(request, prop, resolution.rest),
    ];
    if (items.isEmpty) {
      return null;
    }
    final word = RegExp(r'[A-Za-z0-9_.\-$]*$').firstMatch(request.valueText)!;
    return Handled(
      CompletionResult(
        request.rangeFrom(request.valueStart + word.start),
        items,
      ),
    );
  }

  Iterable<Completion> _themeValues(
    ValueCompletionRequest request,
    SchemaProp prop,
    List<String> rest,
  ) sync* {
    final segments = request.segments;
    final name = segments.isEmpty ? '' : canonicalName(segments.last);
    if (_themeNameKeys.contains(name)) {
      for (final theme in ThemeNames(model).of(request.path)) {
        yield Completion(theme, kind: 20, detail: 'theme');
      }
      if (name == 'active') {
        yield const Completion(
          'system',
          kind: 20,
          detail: 'follow the device',
        );
      }
    }
    if (prop.type == 'color' &&
        (rest.isEmpty || const {'color', 'with'}.contains(rest.lastOrNull))) {
      yield const Completion(r'$colors.', kind: 18, detail: 'a color role');
    }
  }
}
