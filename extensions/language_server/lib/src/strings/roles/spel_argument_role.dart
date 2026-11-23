import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/roles/spel_scopes.dart';
import 'package:dart_spring_language_server/src/strings/spel_paths.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';
import 'package:dart_spring_language_server/src/tokens/spel_tokens.dart';
import 'package:spring_core_dart/expression.dart';
// The SpEL tokenizer is not exported: the checks read its tokens.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// Annotation arguments whose whole string is one SpEL expression, without
/// `#{}`: the keys and conditions of the cache annotations, by annotation
/// name. Also inside `@Caching(cacheable: [Cacheable(key: ...)])`.
const spelArguments = {
  'Cacheable': {'key', 'condition', 'unless'},
  'CachePut': {'key', 'condition', 'unless'},
  'CacheEvict': {'key', 'condition'},
};

/// The SpEL variables a cache expression may use besides the method's
/// parameters: `#root`, `#this`, `#result`, and `#p0` or `#a0` for a
/// parameter by position.
final _builtinVariable = RegExp(r'^(root|this|result|[pa]\d+)$');

/// A SpEL argument of a cache annotation ([spelArguments]): `key: '#isbn'`.
///
/// It is highlighted and parsed, and a `#name` in it must be a parameter
/// of the annotated method, or one of the variables every cache expression
/// has (`#root`, `#result`, `#p0`, ...); `#isbn` goes to the parameter.
final class SpelArgumentRole extends StringRole {
  /// The role, over [model].
  const SpelArgumentRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  // Whether [literal] is the value of a SpEL argument of an annotation or
  // of a `Cacheable(...)` inside `@Caching`.
  static bool _claims(StringContext string) {
    final named = string.literal.parent;
    if (named is! NamedArgument) {
      return false;
    }
    final callee = switch (named.parent?.parent) {
      final Annotation annotation => annotationName(annotation),
      final InstanceCreationExpression creation =>
        creation.constructorName.type.name.lexeme,
      // `Cacheable(...)`, or `Cacheable.of(...)` (unresolved syntax).
      final MethodInvocation invocation => switch (invocation.target) {
        final SimpleIdentifier type => type.name,
        _ => invocation.methodName.name,
      },
      _ => null,
    };
    return spelArguments[callee]?.contains(named.name.lexeme) ?? false;
  }

  // The method the string's annotation is on: `null` on a class, in a
  // composed annotation, or for a `Cacheable(...)` value in plain code,
  // whose parameters are not known here.
  static MethodDeclaration? _methodOf(StringContext string) =>
      switch (string.annotation?.parent) {
        final MethodDeclaration method => method,
        _ => null,
      };

  static List<FormalParameter> _parametersOf(StringContext string) =>
      _methodOf(string)?.parameters?.parameters.toList() ?? const [];

  SpelEnv _env(StringContext string) => spelEnvOf(
    SpelMethod(
      model.dartTypes,
      string.file,
      string.literal,
      _methodOf(string),
      string.annotation,
    ),
    rootValues: cacheRootValues,
    variables: cacheVariables,
  );

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    if (!_claims(string)) {
      return null;
    }
    final found = model.spelPaths.complete(request.before, _env(string));
    return found == null
        ? null
        : Handled(
            CompletionResult(
              request.rangeFrom(string.contentStart + found.$1),
              found.$2,
            ),
          );
  }

  @override
  Handled<Target>? target(StringContext string, int offset) {
    if (!_claims(string)) {
      return null;
    }
    final expression = string.contents;
    final at = offset - string.contentStart;
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return const Handled(null);
    }
    final member = model.spelPaths.target(expression, at, _env(string));
    if (member != null) {
      return Handled(member);
    }
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != TokenKind.identifier ||
          tokens[i - 1].kind != TokenKind.hash ||
          at < token.start - 1 ||
          at > token.end) {
        continue;
      }
      final name = expression.substring(token.start, token.end);
      return Handled(
        DeclarationTarget('Parameter `$name`', [
          for (final parameter in _parametersOf(string))
            if (parameter.name?.lexeme == name)
              DeclarationSite(
                string.path,
                parameter.name!.offset,
                name.length,
                '`${parameter.toSource()}`',
              ),
        ]),
      );
    }
    return const Handled(null);
  }

  @override
  void tokens(StringContext string, AddToken add) {
    if (_claims(string)) {
      spelTokens(string.contents, string.contentStart, add);
    }
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    if (!_claims(string)) {
      return;
    }
    final expression = string.contents;
    final start = string.contentStart;
    final end = string.contentEnd;
    try {
      SpelExpressionParser().parseExpression(expression);
    } on SpelParseException catch (error) {
      final at = start + (error.position < 0 ? 0 : error.position);
      problems.add(
        Problem(
          model.locations.rangeOf(
            string.file,
            at.clamp(start, end),
            (at + 1).clamp(start, end),
          ),
          'SpEL: ${error.message}',
          error: true,
        ),
      );
      return;
    } on Object {
      return;
    }
    final parameters = {
      for (final parameter in _parametersOf(string)) ?parameter.name?.lexeme,
    };
    final tokens = _methodOf(string) == null
        ? const <Token>[]
        : Tokenizer(expression).process();
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != TokenKind.identifier ||
          tokens[i - 1].kind != TokenKind.hash) {
        continue;
      }
      final name = expression.substring(token.start, token.end);
      if (parameters.contains(name) || _builtinVariable.hasMatch(name)) {
        continue;
      }
      final known = parameters.isEmpty
          ? ''
          : '; parameters: ${parameters.map((p) => '#$p').join(', ')}';
      problems.add(
        Problem(
          model.locations.rangeOf(
            string.file,
            start + token.start - 1,
            start + token.end,
          ),
          "Unknown variable '#$name'$known",
        ),
      );
    }
    for (final issue in model.spelPaths.issues(expression, _env(string))) {
      final range = model.locations.rangeOf(
        string.file,
        start + issue.start,
        start + issue.end,
      );
      problems.add(
        Problem(
          range,
          issue.message,
          fixes: Fix.suggesting(range, issue.guess),
        ),
      );
    }
  }
}
