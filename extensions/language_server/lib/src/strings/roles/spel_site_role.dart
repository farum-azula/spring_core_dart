import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/spel_editor.dart';
import 'package:dart_spring_language_server/src/strings/roles/spel_expression_target.dart';
import 'package:dart_spring_language_server/src/strings/roles/spel_scopes.dart';
import 'package:dart_spring_language_server/src/strings/spel_paths.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
import 'package:dart_spring_language_server/src/templates.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';
import 'package:dart_spring_language_server/src/tokens/spel_tokens.dart';
import 'package:spring_core_dart/expression.dart' show SpelExpressionParser;
// The SpEL tokenizer is not exported: the variables are read from its
// tokens.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// The variables every context has.
final _positional = RegExp(r'^(root|this|[pa]\d+)$');

/// One expression of a string: its text and where it starts in the string.
typedef _Piece = ({String text, int start});

/// The arguments of [spelSites]: what each can read at run time is in its
/// scope. The `#{...}` of a template is also the template role's, which
/// colours and parses it; this role adds what depends on the scope.
final class SpelSiteRole extends StringRole {
  /// The role, over [model].
  SpelSiteRole(this.model)
    : _sites = {for (final site in spelSites) site.callee: site};

  /// What the workspace knows.
  final ProjectModel model;

  final Map<String, SpelSite> _sites;

  static String _positionalIndex(ArgumentList list, Expression literal) {
    final positional = list.arguments.where((a) => a is! NamedArgument);
    return '${positional.toList().indexOf(literal)}';
  }

  // The site of [string], directly or through a composed annotation.
  SpelSite? _claim(StringContext string) {
    final literal = string.literal;
    final (list, key) = switch (literal.parent) {
      final NamedArgument named => (named.parent, named.name.lexeme),
      final ArgumentList arguments => (
        arguments,
        _positionalIndex(arguments, literal),
      ),
      _ => (null, ''),
    };
    if (list is! ArgumentList) {
      return null;
    }
    final callee = switch (list.parent) {
      final Annotation annotation => annotationName(annotation),
      SuperConstructorInvocation() =>
        literal
            .thisOrAncestorOfType<ClassDeclaration>()
            ?.extendsClause
            ?.superclass
            .name
            .lexeme,
      final InstanceCreationExpression creation =>
        creation.constructorName.type.name.lexeme,
      final MethodInvocation invocation => switch (invocation.target) {
        final SimpleIdentifier type =>
          '${type.name}.${invocation.methodName.name}',
        _ => invocation.methodName.name,
      },
      _ => null,
    };
    if (callee == null) {
      return null;
    }
    final direct = _sites[callee];
    if (direct != null) {
      return direct.arguments.contains(key) ? direct : null;
    }
    return list.parent is Annotation ? _composed(callee, key) : null;
  }

  // `class Avatar extends SignedUrl { const Avatar(super.path); }`: the
  // site of the argument [key] of `@Avatar(...)`, when it goes to `super`.
  SpelSite? _composed(String callee, String key) {
    final classes = model.classes.classesNamed(callee);
    if (classes.length != 1) {
      return null;
    }
    final declaration = classes.single.declaration;
    final parent = declaration.extendsClause?.superclass.name.lexeme;
    final site = parent == null ? null : _sites[parent];
    if (site == null) {
      return null;
    }
    final positionalIndex = int.tryParse(key);
    for (final parameters in _constructors(declaration)) {
      final positional = parameters.where((p) => p.isPositional).toList();
      final parameter = positionalIndex == null
          ? parameters.where((p) => p.name?.lexeme == key).firstOrNull
          : positional.elementAtOrNull(positionalIndex);
      if (parameter is! SuperFormalParameter) {
        continue;
      }
      final forwarded = parameter.isNamed
          ? parameter.name.lexeme
          : '${_superIndex(positional, parameter)}';
      if (site.arguments.contains(forwarded)) {
        return site;
      }
    }
    return null;
  }

  static int _superIndex(
    List<FormalParameter> positional,
    SuperFormalParameter parameter,
  ) => positional.whereType<SuperFormalParameter>().toList().indexOf(parameter);

  static Iterable<List<FormalParameter>> _constructors(
    ClassDeclaration declaration,
  ) sync* {
    if (declaration.namePart case final PrimaryConstructorDeclaration primary) {
      yield primary.formalParameters.parameters;
    }
    for (final member in declaration.body.members) {
      if (member is ConstructorDeclaration && member.name == null) {
        yield member.parameters.parameters;
      }
    }
  }

  static bool _whole(SpelSite site, StringContext string) =>
      site.form == SpelForm.expression ||
      (site.form == SpelForm.expressionOrTemplate &&
          !string.value.startsWith('#{'));

  // The expressions of [string]; those with a placeholder have no text
  // to read until the placeholder is replaced.
  static List<_Piece> _pieces(SpelSite site, StringContext string) {
    final contents = string.contents;
    if (_whole(site, string)) {
      return contents.contains(r'${') ? const [] : [(text: contents, start: 0)];
    }
    return [
      for (final part in scanTemplate(contents))
        if (part.kind == TemplatePartKind.expression &&
            !part.unclosed &&
            !contents.substring(part.innerStart, part.innerEnd).contains(r'${'))
          (
            text: contents.substring(part.innerStart, part.innerEnd),
            start: part.innerStart,
          ),
    ];
  }

  SpelMethod _method(StringContext string) {
    final annotation = string.annotation;
    return SpelMethod(
      model.dartTypes,
      string.file,
      string.literal,
      switch (annotation?.parent) {
        final MethodDeclaration method => method,
        _ => null,
      },
      annotation,
    );
  }

  SpelEnv _env(SpelSite site, SpelMethod method) =>
      spelEnvOf(method, arguments: site.scope.parameters);

  @override
  Handled<Target>? target(StringContext string, int offset) {
    final site = _claim(string);
    if (site == null) {
      return null;
    }
    final at = offset - string.contentStart;
    final method = _method(string);
    final env = _env(site, method);
    for (final piece in _pieces(site, string)) {
      final inner = at - piece.start;
      if (inner < 0 || inner > piece.text.length) {
        continue;
      }
      if (model.spelPaths.target(piece.text, inner, env) case final member?) {
        return Handled(member);
      }
      if (_variable(string, method, piece.text, inner) case final variable?) {
        return Handled(variable);
      }
      for (final root in model.spelPaths.read(piece.text, env).roots) {
        if (inner >= root.start && inner <= root.end) {
          if (site.scope.names[root.name] case final known?) {
            return Handled(TextTarget(known.hover));
          }
        }
      }
      if (_whole(site, string)) {
        return Handled(SpelExpressionTarget(model).at(piece.text, inner));
      }
    }
    return null;
  }

  static Target? _variable(
    StringContext string,
    SpelMethod method,
    String expression,
    int at,
  ) {
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return null;
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
      final sites = [
        for (final parameter in method.parameters)
          if (parameter.name?.lexeme == name)
            DeclarationSite(
              string.path,
              parameter.name!.offset,
              name.length,
              '`${parameter.toSource()}`',
            ),
      ];
      return sites.isEmpty
          ? null
          : DeclarationTarget('Parameter `$name`', sites);
    }
    return null;
  }

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    final site = _claim(string);
    if (site == null) {
      return null;
    }
    final String before;
    final int base;
    if (_whole(site, string)) {
      if (request.openPlaceholder != null) {
        return null;
      }
      before = request.before;
      base = string.contentStart;
    } else {
      final open = request.openExpression;
      if (open == null) {
        return null;
      }
      before = open.group(1)!;
      base = string.contentStart + open.start + 2;
    }
    if (_insideText(before)) {
      return const Handled(null);
    }
    final method = _method(string);
    final env = _env(site, method);
    CompletionResult result(int start, List<Completion> items) =>
        CompletionResult(request.rangeFrom(base + start), items);
    if (model.spelPaths.complete(before, env) case (final start, final items)) {
      return Handled(result(start, items));
    }
    if (RegExp(r'#(\w*)$').firstMatch(before) case final variable?) {
      return Handled(
        result(variable.start + 1, [
          if (site.scope.parameters)
            for (final (index, parameter) in method.parameters.indexed)
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
      return Handled(result(start, items));
    }
    final member = RegExp(
      r'(?:^|[^\w.#@])((?:[A-Za-z_]\w*\s*\??\.\s*)+)(\w*)$',
    ).firstMatch(before);
    if (member != null) {
      final members = _membersAlong(site, member.group(1)!);
      if (members == null) {
        return const Handled(null);
      }
      return Handled(
        result(before.length - member.group(2)!.length, [
          for (final name in members.keys) Completion(name, detail: 'property'),
        ]),
      );
    }
    if (site.scope.names.isEmpty || RegExp(r'[.#@]\s*\w*$').hasMatch(before)) {
      return _whole(site, string) ? const Handled(null) : null;
    }
    final typed = RegExp(r'\w*$').firstMatch(before)!.group(0)!;
    return Handled(
      result(before.length - typed.length, [
        for (final known in site.scope.names.values)
          Completion(
            known.name,
            kind: known.isMethod && !known.isProperty ? 2 : 10,
            detail: known.signature,
            documentation: known.documentation,
            insertText: known.insertText,
          ),
      ]),
    );
  }

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

  static Map<String, String?>? _membersAlong(SpelSite site, String path) {
    final steps = RegExp(r'[A-Za-z_]\w*').allMatches(path).toList();
    var type = site.scope.names[steps.first.group(0)]?.memberType;
    for (final step in steps.skip(1)) {
      type = type == null ? null : site.scope.memberTypes[type]?[step.group(0)];
    }
    return type == null ? null : site.scope.memberTypes[type];
  }

  @override
  void tokens(StringContext string, AddToken add) {
    final site = _claim(string);
    if (site == null || !_whole(site, string)) {
      return;
    }
    final contents = string.contents;
    final placeholders = [
      for (final part in scanTemplate(contents))
        if (part.kind == TemplatePartKind.placeholder) part,
    ];
    final masked = StringBuffer();
    var from = 0;
    for (final part in placeholders) {
      if (part.start < from) {
        continue;
      }
      masked
        ..write(contents.substring(from, part.start))
        ..write(' ' * (part.end - part.start));
      from = part.end;
    }
    masked.write(contents.substring(from));
    final base = string.contentStart;
    spelTokens('$masked', base, (start, end, type, [modifiers = 0]) {
      final overlaps = placeholders.any(
        (part) => start < base + part.end && end > base + part.start,
      );
      if (!overlaps) {
        add(start, end, type, modifiers);
      }
    });
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    final site = _claim(string);
    if (site == null) {
      return;
    }
    final method = _method(string);
    final env = _env(site, method);
    final whole = _whole(site, string);
    for (final piece in _pieces(site, string)) {
      final base = string.contentStart + piece.start;
      void report(SpelIssue issue) {
        final range = model.locations.rangeOf(
          string.file,
          base + issue.start,
          base + issue.end,
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

      if (whole) {
        final found = model.spel.issuesIn(string.path, piece.text)
          ..forEach(report);
        if (found.any((issue) => issue.message.startsWith('SpEL:'))) {
          continue;
        }
      } else {
        try {
          SpelExpressionParser().parseExpression(piece.text);
        } on Object {
          continue; // the template role reports it
        }
      }
      _variableIssues(site, method, piece.text).forEach(report);
      _rootIssues(site, piece.text, env).forEach(report);
      model.spelPaths.issues(piece.text, env).forEach(report);
    }
  }

  Iterable<SpelIssue> _variableIssues(
    SpelSite site,
    SpelMethod method,
    String expression,
  ) sync* {
    final scope = site.scope;
    final checked =
        scope.closedVariables || (scope.parameters && method.method != null);
    if (!checked) {
      return;
    }
    final parameters = [
      if (scope.parameters)
        for (final parameter in method.parameters) ?parameter.name?.lexeme,
    ];
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return;
    }
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != TokenKind.identifier ||
          tokens[i - 1].kind != TokenKind.hash) {
        continue;
      }
      final name = expression.substring(token.start, token.end);
      final builtin = scope.parameters
          ? _positional.hasMatch(name)
          : name == 'root' || name == 'this';
      if (parameters.contains(name) || builtin) {
        continue;
      }
      final guess = didYouMean(name, parameters);
      final known = parameters.isEmpty
          ? ''
          : '; parameters: ${parameters.map((p) => '#$p').join(', ')}';
      yield SpelIssue(
        token.start - 1,
        token.end,
        "Unknown variable '#$name'$known",
        error: false,
        guess: guess == null ? null : '#$guess',
      );
    }
  }

  Iterable<SpelIssue> _rootIssues(
    SpelSite site,
    String expression,
    SpelEnv env,
  ) sync* {
    final names = site.scope.names;
    if (names.isEmpty) {
      return;
    }
    for (final root in model.spelPaths.read(expression, env).roots) {
      if (names.containsKey(root.name)) {
        continue;
      }
      final guess = model.beans.beansNamed(root.name).isNotEmpty
          ? '@${root.name}'
          : didYouMean(root.name, names.keys.toList());
      yield SpelIssue(
        root.start,
        root.end,
        "Unknown name '${root.name}' in this expression"
        "${guess == null ? '' : ". Did you mean '$guess'?"}",
        error: false,
        guess: guess,
      );
    }
  }
}
