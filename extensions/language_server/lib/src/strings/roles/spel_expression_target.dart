import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
// The SpEL tokenizer is not exported: the navigation reads its tokens.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// What is at a place of a `#{...}` expression of a template: a member of
/// a bean (a hover), or a bean, by `@name` or by a leading `name`.
final class SpelExpressionTarget {
  /// Targets over the beans of [model].
  const SpelExpressionTarget(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  /// The target at [at] of [expression]; `null` when there is none.
  Target? at(String expression, int at) {
    if (model.spel.hover(expression, at, beanPart: false) case final member?) {
      return TextTarget(member);
    }
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return null;
    }
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != TokenKind.identifier ||
          at < token.start ||
          at > token.end) {
        continue;
      }
      final previous = i > 0 ? tokens[i - 1].kind : null;
      final name = token.data ?? expression.substring(token.start, token.end);
      final isBean =
          previous == TokenKind.beanRef ||
          (previous == null || _startsPath(previous)) &&
              (i + 1 >= tokens.length ||
                  tokens[i + 1].kind != TokenKind.lparen);
      final beans = model.beans.beansNamed(name);
      if (isBean && beans.isNotEmpty) {
        return BeanTarget(beans, "Bean '$name'");
      }
      if (previous == TokenKind.beanRef) {
        return BeanTarget(const [], "Bean '$name'");
      }
    }
    return null;
  }

  // Whether a name after [previous] starts a path (is not a member, a
  // `?.` step or a `#variable`).
  static bool _startsPath(TokenKind previous) =>
      previous != TokenKind.dot &&
      previous != TokenKind.safeNavi &&
      previous != TokenKind.hash;
}
