import 'package:dart_spring_language_server/src/config/config_check.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/diagnostics/missing_property_fixes.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/templates.dart';

/// The `${key}` and `#{...}` of a value: an unclosed one or invalid SpEL
/// (errors), a key without a default that nothing defines for the
/// package (a warning), unknown beans and members in SpEL.
final class PlaceholderCheck implements ConfigKeyCheck {
  /// The check over [model].
  const PlaceholderCheck(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  void check(ConfigCheckPass pass, ResolvedKey key, List<Problem> problems) {
    final config = key.key;
    if (!key.hasPlainValue) {
      return;
    }
    final value = config.value!;
    if (!value.contains(r'${') && !value.contains('#{')) {
      return;
    }
    for (final part in scanTemplate(value)) {
      if (part.unclosed) {
        problems.add(
          Problem(
            pass.document.range(
              config.line,
              config.valueStart + part.start,
              config.valueStart + part.end,
            ),
            part.kind == TemplatePartKind.placeholder
                ? "Unclosed placeholder: missing '}'"
                : "Unclosed SpEL expression: missing '}'",
            error: true,
          ),
        );
      } else if (part.kind == TemplatePartKind.placeholder) {
        _placeholder(pass, config, part, problems);
      } else {
        _expression(pass, config, part, problems);
      }
    }
  }

  void _placeholder(
    ConfigCheckPass pass,
    ConfigKey config,
    TemplatePart part,
    List<Problem> problems,
  ) {
    final name = part.inner(config.value!);
    final hasDefault = part.keyEnd! < part.innerEnd;
    if (hasDefault || name.isEmpty || model.keys.resolves(pass.path, name)) {
      return;
    }
    final keyEnd = config.valueStart + part.keyEnd!;
    problems.add(
      Problem(
        pass.document.range(
          config.line,
          config.valueStart + part.innerStart,
          keyEnd,
        ),
        "Cannot resolve property '$name' in any properties file",
        fixes: MissingPropertyFixes(model).of(
          pass.path,
          name,
          pass.document.range(config.line, keyEnd, keyEnd),
        ),
      ),
    );
  }

  void _expression(
    ConfigCheckPass pass,
    ConfigKey config,
    TemplatePart part,
    List<Problem> problems,
  ) {
    final expression = config.value!.substring(part.innerStart, part.innerEnd);
    if (expression.contains(r'${')) {
      return;
    }
    for (final issue in model.spel.issuesIn(pass.path, expression)) {
      final range = pass.document.range(
        config.line,
        config.valueStart + part.innerStart + issue.start,
        config.valueStart + part.innerStart + issue.end,
      );
      problems.add(
        Problem(
          range,
          issue.message,
          error: issue.error,
          fixes: Fix.suggesting(range, issue.guess),
        ),
      );
    }
  }
}
