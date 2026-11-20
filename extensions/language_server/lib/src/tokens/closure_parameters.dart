import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Reports the parameters of closures (`(alert) => ...`) where they are
/// declared and wherever the closure's body uses them: the
/// `closureParameter` tokens of a Dart file.
///
/// Parameters of methods and of local or top-level functions are not
/// reported. A name declared again inside the closure (a local variable,
/// a loop or catch variable, a pattern variable, a parameter of a local
/// function) hides the parameter there. A member or label with the same
/// name (`x.alert`, `alert:`) is not a use of it.
final class ClosureParameterFinder extends RecursiveAstVisitor<void> {
  /// A finder that calls [_add] with the offsets of each declaration and
  /// use.
  ClosureParameterFinder(this._add);

  final void Function(int start, int end) _add;

  // Innermost last: name -> whether it is a closure parameter.
  final _scopes = <Map<String, bool>>[];

  bool _isClosureParameter(String name) {
    for (final scope in _scopes.reversed) {
      if (scope[name] case final closure?) {
        return closure;
      }
    }
    return false;
  }

  void _declare(String name) {
    if (_scopes.isNotEmpty) {
      _scopes.last[name] = false;
    }
  }

  void _inScope(Map<String, bool> scope, void Function() body) {
    _scopes.add(scope);
    try {
      body();
    } finally {
      _scopes.removeLast();
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A local or top-level function is a FunctionExpression too; only
    // the others are closures.
    final closure = node.parent is! FunctionDeclaration;
    final scope = <String, bool>{};
    for (final parameter
        in node.parameters?.parameters ?? const <FormalParameter>[]) {
      final name = parameter.name;
      if (name == null) {
        continue;
      }
      scope[name.lexeme] = closure;
      if (closure) {
        _add(name.offset, name.end);
      }
    }
    node.typeParameters?.accept(this);
    node.parameters?.accept(this);
    _inScope(scope, () => node.body.accept(this));
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) => _inScope({
    for (final parameter
        in node.parameters?.parameters ?? const <FormalParameter>[])
      if (parameter.name case final name?) name.lexeme: false,
  }, () => super.visitMethodDeclaration(node));

  @override
  void visitBlock(Block node) => _inScope({}, () => super.visitBlock(node));

  // Loop, catch and pattern variables live only in their statement.
  @override
  void visitForStatement(ForStatement node) =>
      _inScope({}, () => super.visitForStatement(node));

  @override
  void visitForElement(ForElement node) =>
      _inScope({}, () => super.visitForElement(node));

  @override
  void visitCatchClause(CatchClause node) =>
      _inScope({}, () => super.visitCatchClause(node));

  @override
  void visitIfStatement(IfStatement node) =>
      _inScope({}, () => super.visitIfStatement(node));

  @override
  void visitIfElement(IfElement node) =>
      _inScope({}, () => super.visitIfElement(node));

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) =>
      _inScope({}, () => super.visitSwitchPatternCase(node));

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) =>
      _inScope({}, () => super.visitSwitchExpressionCase(node));

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _declare(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    _declare(node.name.lexeme);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    _declare(node.name.lexeme);
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _declare(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_isClosureParameter(node.name) && _isReference(node)) {
      _add(node.offset, node.end);
    }
  }

  // Not a use of a variable: `x.alert`, `x?.alert`, `x.alert()`, `alert:`.
  static bool _isReference(SimpleIdentifier node) => switch (node.parent) {
    PropertyAccess(:final propertyName) => propertyName != node,
    PrefixedIdentifier(:final identifier) => identifier != node,
    MethodInvocation(:final methodName, :final realTarget) =>
      methodName != node || realTarget == null,
    Label() => false,
    _ => true,
  };
}
