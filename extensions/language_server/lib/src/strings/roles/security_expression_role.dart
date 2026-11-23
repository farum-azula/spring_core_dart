import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/roles/security_expressions.dart';
import 'package:dart_spring_language_server/src/strings/roles/spel_expression_target.dart';
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

/// The variables SpEL and method security give every expression besides
/// the method's parameters.
final _builtinVariable = RegExp(r'^(root|this|[pa]\d+)$');

/// A security expression: which annotation reads it, and the method it is
/// on (`null` on a class or in a composed annotation).
typedef _SecurityString = ({String annotation, MethodDeclaration? method});

/// The expression of `@PreAuthorize`, `@PostAuthorize`, `@PreFilter` and
/// `@PostFilter`, also in `super(...)` of a class that extends one.
///
/// It is highlighted and parsed; its functions, `principal` and the
/// method's parameters complete, explain themselves on hover and are
/// checked. A name an application adds through a customizer is possible,
/// so an unknown one is a warning.
final class SecurityExpressionRole extends StringRole {
  /// The role, over [model].
  const SecurityExpressionRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  static _SecurityString? _claim(StringContext string) {
    final arguments = string.literal.parent;
    if (arguments is! ArgumentList ||
        arguments.arguments.isEmpty ||
        arguments.arguments.first != string.literal) {
      return null;
    }
    final name = switch (arguments.parent) {
      final Annotation annotation => annotationName(annotation),
      SuperConstructorInvocation() =>
        string.literal
            .thisOrAncestorOfType<ClassDeclaration>()
            ?.extendsClause
            ?.superclass
            .name
            .lexeme,
      _ => null,
    };
    if (name == null || !securityAnnotations.contains(name)) {
      return null;
    }
    return (
      annotation: name,
      method: arguments.parent is Annotation
          ? string.literal.thisOrAncestorOfType<MethodDeclaration>()
          : null,
    );
  }

  SpelEnv _env(StringContext string, _SecurityString claim) => spelEnvOf(
    SpelMethod(
      model.dartTypes,
      string.file,
      string.literal,
      claim.method,
      string.annotation,
    ),
    rootValues: securityRootValues,
  );

  static List<FormalParameter> _parameters(MethodDeclaration? method) =>
      method?.parameters?.parameters.toList() ?? const [];

  // The indexes of the names read on the root: not members, variables,
  // beans, keywords or types, and not inside a selection, a projection or
  // an inline map, whose names belong to the element.
  static Iterable<int> _rootNames(String expression, List<Token> tokens) sync* {
    final scopes = <bool>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      switch (token.kind) {
        case TokenKind.select ||
            TokenKind.selectFirst ||
            TokenKind.selectLast ||
            TokenKind.project ||
            TokenKind.lcurly:
          scopes.add(true);
        case TokenKind.lsquare:
          scopes.add(false);
        case TokenKind.rsquare || TokenKind.rcurly:
          if (scopes.isNotEmpty) {
            scopes.removeLast();
          }
        case TokenKind.identifier:
          if (!scopes.contains(true) && _isRootName(expression, tokens, i)) {
            yield i;
          }
        case _:
          break;
      }
    }
  }

  static String _text(String expression, Token token) =>
      expression.substring(token.start, token.end);

  static bool _isRootName(String expression, List<Token> tokens, int i) {
    final name = _text(expression, tokens[i]);
    final next = i + 1 < tokens.length ? tokens[i + 1].kind : null;
    if (isSpelKeyword(name) || (name == 'T' && next == TokenKind.lparen)) {
      return false;
    }
    if (i == 0) {
      return true;
    }
    final previous = tokens[i - 1];
    if (const {
      TokenKind.dot,
      TokenKind.safeNavi,
      TokenKind.hash,
      TokenKind.beanRef,
      TokenKind.factoryBeanRef,
    }.contains(previous.kind)) {
      return false;
    }
    if (previous.kind == TokenKind.identifier &&
        _text(expression, previous).toLowerCase() == 'new') {
      return false;
    }
    return !(previous.kind == TokenKind.lparen &&
        i >= 2 &&
        tokens[i - 2].kind == TokenKind.identifier &&
        _text(expression, tokens[i - 2]) == 'T');
  }

  @override
  Handled<Target>? target(StringContext string, int offset) {
    final claim = _claim(string);
    if (claim == null) {
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
    final member = model.spelPaths.target(
      expression,
      at,
      _env(string, claim),
    );
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
      return Handled(_variableTarget(string, claim, _text(expression, token)));
    }
    for (final i in _rootNames(expression, tokens)) {
      if (at >= tokens[i].start && at <= tokens[i].end) {
        if (securityNames[_text(expression, tokens[i])] case final known?) {
          return Handled(TextTarget(known.hover));
        }
      }
    }
    return Handled(SpelExpressionTarget(model).at(expression, at));
  }

  static Target? _variableTarget(
    StringContext string,
    _SecurityString claim,
    String name,
  ) {
    final sites = [
      for (final parameter in _parameters(claim.method))
        if (parameter.name?.lexeme == name)
          DeclarationSite(
            string.path,
            parameter.name!.offset,
            name.length,
            '`${parameter.toSource()}`',
          ),
    ];
    if (sites.isNotEmpty) {
      return DeclarationTarget('Parameter `$name`', sites);
    }
    return switch (name) {
      'root' => const TextTarget('**#root**\n\nThe root of the expression.'),
      'this' => const TextTarget('**#this**\n\nThe current element.'),
      _ when _builtinVariable.hasMatch(name) => TextTarget(
        '**#$name**\n\nThe argument at position ${name.substring(1)}.',
      ),
      _ => null,
    };
  }

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    final claim = _claim(string);
    if (claim == null) {
      return null;
    }
    final before = request.before;
    if (_insideText(before)) {
      return const Handled(null);
    }
    if (model.spelPaths.complete(before, _env(string, claim)) case (
      final start,
      final items,
    )) {
      return Handled(
        CompletionResult(request.rangeFrom(string.contentStart + start), items),
      );
    }
    if (RegExp(r'#(\w*)$').firstMatch(before) case final variable?) {
      final typed = variable.group(1)!;
      return Handled(
        CompletionResult(request.rangeFrom(request.offset - typed.length), [
          for (final (index, parameter) in _parameters(claim.method).indexed)
            if (parameter.name?.lexeme case final name?) ...[
              Completion(
                name,
                kind: 6,
                detail: parameter.toSource(),
                sortText: '0$name',
              ),
              Completion(
                'p$index',
                kind: 6,
                detail: name,
                sortText: '1p$index',
              ),
            ],
          const Completion('root', kind: 6, sortText: '2root'),
          const Completion('this', kind: 6, sortText: '2this'),
        ]),
      );
    }
    if (model.spel.complete(before) case (final start, final items)) {
      return Handled(
        CompletionResult(request.rangeFrom(string.contentStart + start), items),
      );
    }
    final member = RegExp(
      r'(?:^|[^\w.#@])((?:[A-Za-z_]\w*\s*\??\.\s*)+)(\w*)$',
    ).firstMatch(before);
    if (member != null) {
      final members = _membersAlong(member.group(1)!);
      if (members == null) {
        return const Handled(null);
      }
      final typed = member.group(2)!;
      return Handled(
        CompletionResult(request.rangeFrom(request.offset - typed.length), [
          for (final name in members.keys) Completion(name, detail: 'property'),
        ]),
      );
    }
    if (RegExp(r'[.#@]\s*\w*$').hasMatch(before)) {
      return const Handled(null);
    }
    final typed = RegExp(r'\w*$').firstMatch(before)!.group(0)!;
    return Handled(
      CompletionResult(request.rangeFrom(request.offset - typed.length), [
        for (final known in securityNames.values)
          if (known.onlyIn?.contains(claim.annotation) ?? true)
            Completion(
              known.name,
              kind: known.isMethod && !known.isProperty ? 2 : 10,
              detail: known.signature,
              documentation: known.documentation,
              insertText: known.insertText,
            ),
        for (final word in const ['and', 'or', 'not'])
          Completion(word, kind: 14),
      ]),
    );
  }

  // Whether the cursor after [before] is inside a SpEL string.
  static bool _insideText(String before) {
    String? quote;
    for (var i = 0; i < before.length; i++) {
      final c = before[i];
      if (quote == null && (c == "'" || c == '"')) {
        quote = c;
      } else if (c == quote) {
        quote = null;
      }
    }
    return quote != null;
  }

  // The members after the path `authentication.principal.`; `null` when
  // the path is not of a known security type.
  static Map<String, String?>? _membersAlong(String path) {
    final steps = RegExp(r'[A-Za-z_]\w*').allMatches(path).toList();
    var type = securityNames[steps.first.group(0)]?.memberType;
    for (final step in steps.skip(1)) {
      type = type == null ? null : securityMembers[type]?[step.group(0)];
    }
    return type == null ? null : securityMembers[type];
  }

  @override
  void tokens(StringContext string, AddToken add) {
    if (_claim(string) != null) {
      spelTokens(string.contents, string.contentStart, add);
    }
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    final claim = _claim(string);
    if (claim == null) {
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
    final complete = model.metadataFor(string.path).complete;
    for (final issue in model.spel.issues(expression, complete: complete)) {
      final range = model.locations.rangeOf(
        string.file,
        start + issue.start,
        start + issue.end,
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
    final tokens = Tokenizer(expression).process();
    if (claim.method != null) {
      _checkVariables(string, claim, expression, tokens, problems);
    }
    for (final i in _rootNames(expression, tokens)) {
      _checkRootName(string, claim, expression, tokens, i, problems);
    }
    for (final issue in model.spelPaths.issues(
      expression,
      _env(string, claim),
    )) {
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

  void _checkVariables(
    StringContext string,
    _SecurityString claim,
    String expression,
    List<Token> tokens,
    List<Problem> problems,
  ) {
    final parameters = {
      for (final parameter in _parameters(claim.method))
        ?parameter.name?.lexeme,
    };
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != TokenKind.identifier ||
          tokens[i - 1].kind != TokenKind.hash) {
        continue;
      }
      final name = _text(expression, token);
      if (parameters.contains(name) || _builtinVariable.hasMatch(name)) {
        continue;
      }
      final guess = didYouMean(name, parameters.toList());
      final range = model.locations.rangeOf(
        string.file,
        string.contentStart + token.start - 1,
        string.contentStart + token.end,
      );
      final known = parameters.isEmpty
          ? ''
          : '; parameters: ${parameters.map((p) => '#$p').join(', ')}';
      problems.add(
        Problem(
          range,
          "Unknown variable '#$name'$known",
          fixes: Fix.suggesting(range, guess == null ? null : '#$guess'),
        ),
      );
    }
  }

  void _checkRootName(
    StringContext string,
    _SecurityString claim,
    String expression,
    List<Token> tokens,
    int i,
    List<Problem> problems,
  ) {
    final token = tokens[i];
    final name = _text(expression, token);
    final called =
        i + 1 < tokens.length && tokens[i + 1].kind == TokenKind.lparen;
    final range = model.locations.rangeOf(
      string.file,
      string.contentStart + token.start,
      string.contentStart + token.end,
    );
    final known = securityNames[name];
    if (known == null) {
      final isBean = model.beans.beansNamed(name).isNotEmpty;
      final guess = isBean
          ? '@$name'
          : didYouMean(name, securityNames.keys.toList());
      problems.add(
        Problem(
          range,
          "Unknown name '$name' in a security expression"
          "${guess == null ? '' : ". Did you mean '$guess'?"}",
          fixes: Fix.suggesting(range, guess),
        ),
      );
    } else if (known.onlyIn case final annotations?
        when !annotations.contains(claim.annotation)) {
      final where = annotations.map((a) => '@$a').join(' and ');
      problems.add(
        Problem(
          range,
          "'$name' has no value in @${claim.annotation}: it is set only in "
          '$where.',
          error: true,
        ),
      );
    } else if (known.isMethod && !known.isProperty && !called) {
      problems.add(
        Problem(
          range,
          "'$name' is a method: write ${known.signature}.",
          error: true,
          fixes: known.takesArguments
              ? const []
              : Fix.suggesting(range, known.signature),
        ),
      );
    } else if (called && !known.isMethod) {
      problems.add(
        Problem(
          range,
          "'$name' is not a method: write $name without parentheses.",
          error: true,
        ),
      );
    }
  }
}
