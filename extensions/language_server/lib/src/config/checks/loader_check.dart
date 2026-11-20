import 'package:dart_spring_language_server/src/config/config_check.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/config/theme_loaders.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';

/// The loaders and the splash of the themes: a key a loader's kind does
/// not take, a `web:` file that is missing or outside the app, a
/// `splash.loader` or `splash.animation` that names nothing declared.
/// Errors.
final class LoaderCheck implements ConfigDocumentCheck {
  /// The check over [model].
  LoaderCheck(this.model) : _loaders = ThemeLoaders(model);

  /// What the workspace knows.
  final ProjectModel model;

  final ThemeLoaders _loaders;

  @override
  void check(ConfigCheckPass pass, List<Problem> problems) {
    final keys = pass.document.keys;
    final kinds = ThemeLoaders.kindsOf(keys);
    final reported = <String>{};
    for (final key in keys) {
      final relative = themeRelative(key.segments);
      if (relative == null || relative.rest.isEmpty) {
        continue;
      }
      final rest = relative.rest;
      final head = canonicalName(rest[0]);
      if (head == 'loaders' && rest.length >= 3) {
        if (_checkLoaderKey(pass, key, relative.theme, rest, kinds, reported)
            case final problem?) {
          problems.add(problem);
        }
      }
      if (head == 'loaders' &&
          rest.length == 3 &&
          canonicalName(rest[2]) == 'web' &&
          key.value != null) {
        if (_checkWebFile(pass, key) case final problem?) {
          problems.add(problem);
        }
      }
      if (head == 'splash' && rest.length == 2 && key.value != null) {
        final section = ThemeLoaders.sectionNamedBy([
          'splash',
          canonicalName(rest[1]),
        ]);
        if (section != null) {
          if (_checkNameOf(pass, key, section) case final problem?) {
            problems.add(problem);
          }
        }
      }
    }
  }

  // A key of `loaders.<name>` its kind does not take.
  Problem? _checkLoaderKey(
    ConfigCheckPass pass,
    ConfigKey key,
    String? theme,
    List<String> rest,
    Map<String, String> kinds,
    Set<String> reported,
  ) {
    final kind = kinds['$theme|${canonicalName(rest[1])}'];
    final allowed = kind == null ? null : _loaders.keysOfKind(pass.path, kind);
    if (allowed == null) {
      return null;
    }
    final name = rest[2];
    final index = key.segments.length - rest.length + 2 - key.parentCount;
    if (index < 0 || index >= key.spans.length) {
      // The segment is on a line above, which reports it.
      return null;
    }
    final known = [...loaderCommonKeys, ...allowed];
    if (known.any((k) => canonicalName(k) == canonicalName(name)) ||
        !reported.add('${key.line}|$name')) {
      return null;
    }
    final (from, to) = key.spans[index];
    final guess = didYouMean(name, known);
    final range = pass.document.range(key.line, from, to);
    return Problem(
      range,
      "'$name' is not a key of a '$kind' loader. It takes: "
      '${known.join(', ')}'
      "${guess == null ? '' : ". Did you mean '$guess'?"}",
      error: true,
      fixes: Fix.suggesting(range, guess),
    );
  }

  // `splash.loader` and `splash.animation` name something declared.
  Problem? _checkNameOf(ConfigCheckPass pass, ConfigKey key, String section) {
    final value = key.value!;
    if (value.isEmpty || value.contains(r'$') || value.contains('#{')) {
      return null;
    }
    final names = _loaders.declaredNames(pass.path, section);
    if (names.any((n) => canonicalName(n) == canonicalName(value))) {
      return null;
    }
    final what = section == 'loaders' ? 'loader' : 'animation';
    final guess = didYouMean(value, names);
    final range = pass.document.range(key.line, key.valueStart, key.valueEnd);
    return Problem(
      range,
      "'$value' is no $what ($section.<name>) of any theme"
      "${guess == null ? '' : ". Did you mean '$guess'?"}",
      error: true,
      fixes: Fix.suggesting(range, guess),
    );
  }

  // The `web:` file of a loader: a path below the app's directory.
  Problem? _checkWebFile(ConfigCheckPass pass, ConfigKey key) {
    final value = key.value!;
    if (value.isEmpty || value.contains(r'${')) {
      return null;
    }
    final range = pass.document.range(key.line, key.valueStart, key.valueEnd);
    if (value.startsWith('/') ||
        RegExp(r'(^|[\\/])\.\.([\\/]|$)').hasMatch(value) ||
        RegExp(r'^[A-Za-z]:|\\').hasMatch(value)) {
      return Problem(
        range,
        "'$value' must be a path below the app's directory "
        '(no .. and not absolute)',
        error: true,
      );
    }
    if (_loaders.webFile(pass.path, value) == null) {
      return Problem(
        range,
        "The file '$value' does not exist (the path is relative to the "
        "app's directory, or `lib/resources/` of a package it uses)",
        error: true,
      );
    }
    return null;
  }
}
