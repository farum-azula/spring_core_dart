import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/diagnostics/missing_property_fixes.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/strings/navigation_strings.dart';
import 'package:dart_spring_language_server/src/strings/roles/spel_expression_target.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
import 'package:dart_spring_language_server/src/templates.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';
import 'package:dart_spring_language_server/src/tokens/template_tokens.dart';
import 'package:spring_core_dart/expression.dart';

/// Annotations whose strings are read as templates of `${...}`
/// placeholders and `#{...}` SpEL expressions, for highlighting,
/// navigation and checks.
///
/// In these, an interpolated (non-raw) `'${key}'` is an error, since Dart
/// would replace it before the framework sees it. The strings of other
/// annotations are read as templates too when they contain `${` or `#{`.
const templateAnnotations = {
  'Value',
  'ConditionalOnExpression',
  'Cacheable',
  'CachePut',
  'CacheEvict',
  'Query',
  'Scheduled',
};

/// A template of `${key}` placeholders and `#{...}` SpEL expressions: a
/// string of the [templateAnnotations], or of any annotation that holds
/// `${` or `#{` (the SQL of a repository's `@Query` and the `#{key}`
/// titles of the navigation are other roles').
///
/// A key goes to its definitions in the package's config files and the
/// test's own properties, and is reported when nothing defines it and it
/// has no default; an expression is highlighted and checked as SpEL, its
/// beans go to their declarations. Inside an annotation string, an open
/// `${` completes with the known keys and an open `#{` with SpEL.
final class TemplateRole extends StringRole {
  /// The role, over [model].
  const TemplateRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  // The strings that are templates for the highlighting, the checks and
  // the values shown inline.
  bool _claims(StringContext string) {
    if (string.annotation == null ||
        model.query.covers(string.file, string.contentStart) ||
        routeMessageKey(string) != null) {
      return false;
    }
    return _isTemplate(string);
  }

  static bool _isTemplate(StringContext string) {
    final value = string.value;
    return templateAnnotations.contains(string.annotationType) ||
        value.contains(r'${') ||
        value.contains('#{');
  }

  @override
  Handled<Target>? target(StringContext string, int offset) {
    if (!_isTemplate(string)) {
      return null;
    }
    final source = string.contents;
    final relative = offset - string.contentStart;
    for (final part in scanTemplate(source).reversed) {
      if (relative < part.start || relative > part.end) {
        continue;
      }
      if (part.kind == TemplatePartKind.placeholder) {
        final key = part.inner(source);
        return Handled(
          PropertyTarget(
            key,
            model.properties.property(key, from: string.path),
            fallback: part.fallback(source),
          ),
        );
      }
      return Handled(
        SpelExpressionTarget(model).at(
          source.substring(part.innerStart, part.innerEnd),
          relative - part.innerStart,
        ),
      );
    }
    return null;
  }

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    if (string.annotation == null) {
      return null;
    }
    if (request.openPlaceholder case final placeholder?) {
      return Handled(
        CompletionResult(
          request.rangeFrom(request.offset - placeholder.group(1)!.length),
          [
            for (final key in model.schemas.knownKeys(string.path))
              Completion(key, detail: 'property'),
          ],
        ),
      );
    }
    if (request.openExpression case final expression?) {
      final result = model.spel.complete(expression.group(1)!);
      return Handled(
        result == null
            ? null
            : CompletionResult(
                request.rangeFrom(
                  string.contentStart + expression.start + 2 + result.$1,
                ),
                result.$2,
              ),
      );
    }
    return null;
  }

  @override
  void tokens(StringContext string, AddToken add) {
    if (_claims(string)) {
      templateTokens(
        string.contents,
        string.contentStart,
        add,
        resolves: (key) => model.keys.resolves(string.path, key),
      );
    }
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    if (!_claims(string)) {
      return;
    }
    final base = string.contentStart;
    final source = string.contents;
    for (final part in scanTemplate(source)) {
      if (part.unclosed) {
        problems.add(
          Problem(
            model.locations.rangeOf(
              string.file,
              base + part.start,
              base + part.end,
            ),
            part.kind == TemplatePartKind.placeholder
                ? "Unclosed placeholder: missing '}'"
                : "Unclosed SpEL expression: missing '}'",
            error: true,
          ),
        );
      } else if (part.kind == TemplatePartKind.placeholder) {
        _placeholderProblems(string, source, part, problems);
      } else {
        _expressionProblems(string, source, part, problems);
      }
    }
  }

  // A `${key}` without a default that nothing defines. Not reported for a
  // key that looks like an environment variable (`PORT`) or for a nullable
  // target.
  void _placeholderProblems(
    StringContext string,
    String source,
    TemplatePart part,
    List<Problem> problems,
  ) {
    final key = part.inner(source);
    final hasDefault = part.keyEnd! < part.innerEnd;
    if (hasDefault ||
        key.isEmpty ||
        _targetIsNullable(string.literal) ||
        model.keys.resolves(string.path, key)) {
      return;
    }
    final base = string.contentStart;
    final keyEnd = base + part.keyEnd!;
    problems.add(
      Problem(
        model.locations.rangeOf(string.file, base + part.innerStart, keyEnd),
        "Cannot resolve property '$key' in any properties file",
        fixes: MissingPropertyFixes(model).of(
          string.path,
          key,
          model.locations.rangeOf(string.file, keyEnd, keyEnd),
        ),
      ),
    );
  }

  // Invalid SpEL (error), unknown beans and members.
  void _expressionProblems(
    StringContext string,
    String source,
    TemplatePart part,
    List<Problem> problems,
  ) {
    final expression = source.substring(part.innerStart, part.innerEnd);
    if (expression.contains(r'${')) {
      return;
    }
    final base = string.contentStart;
    try {
      SpelExpressionParser().parseExpression(expression);
      for (final issue in model.spel.issuesIn(string.path, expression)) {
        final range = model.locations.rangeOf(
          string.file,
          base + part.innerStart + issue.start,
          base + part.innerStart + issue.end,
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
    } on SpelParseException catch (error) {
      final position = error.position < 0 ? 0 : error.position;
      final at = base + part.innerStart + position;
      problems.add(
        Problem(
          model.locations.rangeOf(
            string.file,
            at.clamp(base + part.start, base + part.end),
            (at + 1).clamp(base + part.start, base + part.innerEnd),
          ),
          'SpEL: ${error.message}',
          error: true,
        ),
      );
    } on Object {
      // Other tokenizer errors are reported by the parser above.
    }
  }

  // `@Value(...) String? motto`: a missing key gives `null`, not an error.
  static bool _targetIsNullable(SimpleStringLiteral literal) {
    final annotation = literal.thisOrAncestorOfType<Annotation>();
    final owner = annotation?.parent;
    TypeAnnotation? type;
    if (owner is FieldDeclaration) {
      type = owner.fields.type;
    } else if (owner is FieldFormalParameter) {
      type = owner.type;
      if (type == null) {
        final classNode = owner.thisOrAncestorOfType<ClassDeclaration>();
        for (final member in classNode?.body.members ?? <ClassMember>[]) {
          if (member is FieldDeclaration &&
              member.fields.variables.any(
                (v) => v.name.lexeme == owner.name.lexeme,
              )) {
            type = member.fields.type;
          }
        }
      }
    } else if (owner is FormalParameter) {
      type = owner.type;
    } else if (owner is MethodDeclaration && owner.isSetter) {
      type = owner.parameters?.parameters.firstOrNull?.type;
    }
    return type?.question != null;
  }

  @override
  Iterable<String>? keysRead(StringContext string) {
    final value = string.value;
    if (string.annotation == null || !value.contains(r'${')) {
      return null;
    }
    return [
      for (final part in scanTemplate(value))
        if (part.kind == TemplatePartKind.placeholder && !part.unclosed)
          part.inner(value),
    ];
  }

  @override
  Iterable<PropertyReference> references(StringContext string) =>
      _claims(string)
      ? placeholderReferences(string.contents, string.contentStart)
      : const [];
}
