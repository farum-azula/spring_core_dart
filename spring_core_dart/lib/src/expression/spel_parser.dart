import 'package:spring_core_dart/src/expression/ast.dart';
import 'package:spring_core_dart/src/expression/expression.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// Parses SpEL, like Spring's `SpelExpressionParser`.
///
/// Parsing is pure and the parser is stateless: keep one instance and
/// cache parsed [Expression]s, which can be evaluated many times against
/// different contexts and roots.
///
/// ```dart
/// final parser = SpelExpressionParser();
/// final context = StandardEvaluationContext({'name': 'Ada', 'price': 5});
/// parser.parseExpression("'Hello ' + name").getValue(context);
/// // 'Hello Ada'
/// parser
///     .parseExpression('Total: #{price * 2}', ParserContext.template)
///     .getValue(context); // 'Total: 10'
/// ```
///
/// Spring (Java):
/// ```java
/// ExpressionParser parser = new SpelExpressionParser();
/// parser.parseExpression("'Hello ' + name").getValue(context);
/// parser.parseExpression("Total: #{price * 2}",
///     ParserContext.TEMPLATE_EXPRESSION).getValue(context);
/// ```
///
/// Differences from Spring: no compiler mode (`SpelCompilerMode`), and
/// types in `T(...)` / `new` must be registered in a `StandardTypeLocator`.
class SpelExpressionParser implements ExpressionParser {
  /// Creates a parser.
  SpelExpressionParser();

  @override
  Expression parseExpression(
    String expressionString, [
    ParserContext? context,
  ]) {
    if (context != null && context.isTemplate) {
      return _parseTemplate(expressionString, context);
    }
    return SpelExpression(expressionString, _Parser(expressionString).parse());
  }

  // Splits a template into literal and expression parts. A template that
  // is a single `#{...}` returns that expression itself, so its value
  // keeps its type instead of becoming a string.
  Expression _parseTemplate(String text, ParserContext context) {
    final prefix = context.expressionPrefix;
    final suffix = context.expressionSuffix;
    final parts = <Expression>[];
    var position = 0;
    while (position < text.length) {
      final start = text.indexOf(prefix, position);
      if (start < 0) {
        parts.add(LiteralExpression(text.substring(position)));
        break;
      }
      if (start > position) {
        parts.add(LiteralExpression(text.substring(position, start)));
      }
      final expressionStart = start + prefix.length;
      final end = _findSuffix(text, expressionStart, prefix, suffix);
      final inner = text.substring(expressionStart, end);
      if (inner.trim().isEmpty) {
        throw SpelParseException(
          SpelMessage.unexpectedEndOfExpression,
          "No expression defined within delimiter '$prefix$suffix'",
          expressionString: text,
          position: start,
        );
      }
      parts.add(parseExpression(inner));
      position = end + suffix.length;
    }
    if (parts.isEmpty) {
      return LiteralExpression('');
    }
    return parts.length == 1
        ? parts.single
        : CompositeStringExpression(text, parts);
  }

  /// Index of the suffix closing an expression that starts at [from],
  /// skipping brackets and quoted strings, like Spring's template parser.
  static int _findSuffix(String text, int from, String prefix, String suffix) {
    final stack = <String>[];
    const pairs = {'(': ')', '[': ']', '{': '}'};
    var i = from;
    while (i < text.length) {
      if (stack.isEmpty && text.startsWith(suffix, i)) {
        return i;
      }
      final c = text[i];
      if (pairs.containsKey(c)) {
        stack.add(pairs[c]!);
      } else if (pairs.containsValue(c)) {
        if (stack.isEmpty || stack.removeLast() != c) {
          throw SpelParseException(
            SpelMessage.missingCloseBracket,
            "Found closing '$c' without a matching opening bracket",
            expressionString: text,
            position: i,
          );
        }
      } else if (c == "'" || c == '"') {
        final close = text.indexOf(c, i + 1);
        if (close < 0) {
          throw SpelParseException(
            SpelMessage.unterminatedString,
            'Unterminated string literal',
            expressionString: text,
            position: i,
          );
        }
        i = close;
      }
      i++;
    }
    throw SpelParseException(
      SpelMessage.missingCloseBracket,
      "No ending suffix '$suffix' for expression starting at "
      'position ${from - prefix.length}',
      expressionString: text,
      position: from - prefix.length,
    );
  }
}

/// Recursive-descent parser over the token list (Spring's grammar).
///
/// Precedence, lowest to highest (one method per level):
/// assignment / Elvis / ternary (`_expression`), `or`, `and`, relational
/// (`_relational`, non-associative), `+ -`, `* / %`, `^` and postfix
/// `++ --` (`_powerIncDec`), unary `! - + ++ --`, then primary
/// expressions with their `.x`, `?.x`, `[i]`, `.?[...]` chains.
final class _Parser {
  _Parser(this.text) : _tokens = Tokenizer(text).process();

  final String text;
  final List<Token> _tokens;
  int _pos = 0;

  SpelNode parse() {
    if (_tokens.isEmpty) {
      throw _error(
        SpelMessage.unexpectedEndOfExpression,
        'Empty expression',
        0,
      );
    }
    final node = _expression();
    if (_pos < _tokens.length) {
      final token = _tokens[_pos];
      throw _error(
        SpelMessage.unexpectedToken,
        "Unexpected token '${_describe(token)}'",
        token.start,
      );
    }
    return node;
  }

  // expression: logicalOr ((= logicalOr) | (?: expression)
  //             | (? expression : expression))?
  // The right side of `=` is a logicalOr, so `a = b = c` is rejected
  // (as in Spring); `?:` and `? :` recurse, so they are right-associative.
  SpelNode _expression() {
    final node = _logicalOr();
    if (_peek(TokenKind.assign)) {
      final token = _next();
      return Assign(token.start, node, _logicalOr());
    }
    if (_peek(TokenKind.elvis)) {
      final token = _next();
      return Elvis(token.start, node, _expression());
    }
    if (_peek(TokenKind.qmark)) {
      final token = _next();
      final whenTrue = _expression();
      _expect(TokenKind.colon, "':' in ternary expression");
      return Ternary(token.start, node, whenTrue, _expression());
    }
    return node;
  }

  // Left-associative loops: `a or b or c` is ((a or b) or c).
  SpelNode _logicalOr() {
    var node = _logicalAnd();
    while (_peek(TokenKind.or)) {
      final token = _next();
      node = BinaryOperator(token.start, BinaryKind.or, node, _logicalAnd());
    }
    return node;
  }

  SpelNode _logicalAnd() {
    var node = _relational();
    while (_peek(TokenKind.and)) {
      final token = _next();
      node = BinaryOperator(token.start, BinaryKind.and, node, _relational());
    }
    return node;
  }

  static const _relationalKinds = {
    TokenKind.eq: BinaryKind.eq,
    TokenKind.ne: BinaryKind.ne,
    TokenKind.lt: BinaryKind.lt,
    TokenKind.le: BinaryKind.le,
    TokenKind.gt: BinaryKind.gt,
    TokenKind.ge: BinaryKind.ge,
    TokenKind.instanceOf: BinaryKind.instanceOf,
    TokenKind.matches: BinaryKind.matches,
    TokenKind.between: BinaryKind.between,
  };

  // At most one relational operator: `1 < 2 < 3` is a parse error.
  SpelNode _relational() {
    final node = _sum();
    final kind = _current == null ? null : _relationalKinds[_current!.kind];
    if (kind == null) {
      return node;
    }
    final token = _next();
    return BinaryOperator(token.start, kind, node, _sum());
  }

  SpelNode _sum() {
    var node = _product();
    while (_peek(TokenKind.plus) || _peek(TokenKind.minus)) {
      final token = _next();
      node = BinaryOperator(
        token.start,
        token.kind == TokenKind.plus ? BinaryKind.add : BinaryKind.subtract,
        node,
        _product(),
      );
    }
    return node;
  }

  SpelNode _product() {
    var node = _powerIncDec();
    while (_peek(TokenKind.star) ||
        _peek(TokenKind.div) ||
        _peek(TokenKind.mod)) {
      final token = _next();
      node = BinaryOperator(
        token.start,
        switch (token.kind) {
          TokenKind.star => BinaryKind.multiply,
          TokenKind.div => BinaryKind.divide,
          _ => BinaryKind.modulus,
        },
        node,
        _powerIncDec(),
      );
    }
    return node;
  }

  // `^` takes a single unary on each side (`2 ^ 3 ^ 2` is rejected, like
  // Spring), and unary minus binds tighter: `-2 ^ 2` is 4.
  SpelNode _powerIncDec() {
    final node = _unary();
    if (_peek(TokenKind.power)) {
      final token = _next();
      return BinaryOperator(token.start, BinaryKind.power, node, _unary());
    }
    if (_peek(TokenKind.inc) || _peek(TokenKind.dec)) {
      final token = _next();
      return IncDec(
        token.start,
        node,
        increment: token.kind == TokenKind.inc,
        prefix: false,
      );
    }
    return node;
  }

  SpelNode _unary() {
    final token = _current;
    switch (token?.kind) {
      case TokenKind.not:
        _next();
        return UnaryOperator(token!.start, UnaryKind.not, _unary());
      case TokenKind.minus:
        _next();
        return UnaryOperator(token!.start, UnaryKind.minus, _unary());
      case TokenKind.plus:
        _next();
        return UnaryOperator(token!.start, UnaryKind.plus, _unary());
      case TokenKind.inc || TokenKind.dec:
        _next();
        return IncDec(
          token!.start,
          _unary(),
          increment: token.kind == TokenKind.inc,
          prefix: true,
        );
      default:
        return _primary();
    }
  }

  // A start node followed by any number of navigation nodes; more than
  // one becomes a CompoundExpression evaluated left to right.
  SpelNode _primary() {
    final start = _startNode();
    final nodes = [start];
    while (true) {
      final node = _node();
      if (node == null) {
        break;
      }
      nodes.add(node);
    }
    return nodes.length == 1 ? start : CompoundExpression(start.start, nodes);
  }

  /// A node following another one: `.x`, `?.x`, `[i]`, `.?[...]`, ...
  SpelNode? _node() {
    final token = _current;
    switch (token?.kind) {
      case TokenKind.dot:
        _next();
        return _dotted(nullSafe: false);
      case TokenKind.safeNavi:
        _next();
        return _dotted(nullSafe: true);
      case TokenKind.lsquare:
        return _indexer(nullSafe: false);
      case TokenKind.select ||
          TokenKind.selectFirst ||
          TokenKind.selectLast ||
          TokenKind.project:
        return _selectionOrProjection(nullSafe: false);
      default:
        return null;
    }
  }

  // After `.` or `?.`: a property or method name. After `?.` the
  // tokenizer cannot see `?.?[`, `?.![`, ... as one token, so those are
  // reassembled here from `?`, `!`, `^` or `$` followed by `[`.
  SpelNode _dotted({required bool nullSafe}) {
    final token = _current;
    if (token == null) {
      throw _error(
        SpelMessage.unexpectedEndOfExpression,
        'Expected a property or method after the dot',
        text.length,
      );
    }
    if (nullSafe) {
      // ?.[index], ?.?[select], ?.![project], ?.^[first], ?.$[last]
      if (token.kind == TokenKind.lsquare) {
        return _indexer(nullSafe: true);
      }
      final kind = switch (token.kind) {
        TokenKind.qmark => TokenKind.select,
        TokenKind.not => TokenKind.project,
        TokenKind.power => TokenKind.selectFirst,
        TokenKind.identifier when token.data == r'$' => TokenKind.selectLast,
        _ => null,
      };
      if (kind != null && _peekAt(1, TokenKind.lsquare)) {
        _next();
        return _selectionOrProjection(nullSafe: true, kind: kind);
      }
    }
    if (token.kind == TokenKind.identifier) {
      return _methodOrProperty(nullSafe: nullSafe);
    }
    throw _error(
      SpelMessage.unexpectedToken,
      "Unexpected token '${_describe(token)}' after a dot",
      token.start,
    );
  }

  SpelNode _indexer({required bool nullSafe}) {
    final token = _expect(TokenKind.lsquare, "'['");
    final index = _expression();
    _expect(TokenKind.rsquare, "']'");
    return Indexer(token.start, index, nullSafe: nullSafe);
  }

  // Without [kind], the current token is `.?[`-style and says which
  // operator it is; with [kind] (from _dotted) the `[` is still to come.
  SpelNode _selectionOrProjection({required bool nullSafe, TokenKind? kind}) {
    final token = kind == null ? _next() : _expect(TokenKind.lsquare, "'['");
    final selector = kind ?? token.kind;
    final expression = _expression();
    _expect(TokenKind.rsquare, "']'");
    return switch (selector) {
      TokenKind.project => Projection(
        token.start,
        expression,
        nullSafe: nullSafe,
      ),
      TokenKind.selectFirst => Selection(
        token.start,
        SelectionKind.first,
        expression,
        nullSafe: nullSafe,
      ),
      TokenKind.selectLast => Selection(
        token.start,
        SelectionKind.last,
        expression,
        nullSafe: nullSafe,
      ),
      _ => Selection(
        token.start,
        SelectionKind.all,
        expression,
        nullSafe: nullSafe,
      ),
    };
  }

  SpelNode _methodOrProperty({required bool nullSafe}) {
    final token = _next();
    if (_peek(TokenKind.lparen)) {
      return MethodReference(
        token.start,
        token.data!,
        _arguments(),
        nullSafe: nullSafe,
      );
    }
    return PropertyOrFieldReference(
      token.start,
      token.data!,
      nullSafe: nullSafe,
    );
  }

  List<SpelNode> _arguments() {
    _expect(TokenKind.lparen, "'('");
    final arguments = <SpelNode>[];
    if (!_peek(TokenKind.rparen)) {
      arguments.add(_expression());
      while (_peek(TokenKind.comma)) {
        _next();
        arguments.add(_expression());
      }
    }
    _expect(TokenKind.rparen, "')'");
    return arguments;
  }

  // The first node of a primary: literal, `( )`, inline collection,
  // `[i]` on the active object, `#var`, `#fn()`, `@bean`, `&bean`,
  // selection/projection on the active object, `true`/`false`/`null`
  // (case-insensitive), `T(Type)`, `new Type(...)`, or a property/method.
  SpelNode _startNode() {
    final token = _current;
    if (token == null) {
      throw _error(
        SpelMessage.unexpectedEndOfExpression,
        'Unexpected end of expression',
        text.length,
      );
    }
    switch (token.kind) {
      case TokenKind.literalInt:
        _next();
        return Literal(token.start, _parseInt(token, token.data!, 10));
      case TokenKind.literalLong:
        // Dart ints are 64-bit, so int and long literals are both `int`.
        _next();
        return Literal(token.start, _parseInt(token, token.data!, 10));
      case TokenKind.literalHexInt || TokenKind.literalHexLong:
        _next();
        return Literal(token.start, _parseInt(token, token.data!, 16));
      case TokenKind.literalReal || TokenKind.literalRealFloat:
        _next();
        return Literal(token.start, double.parse(token.data!));
      case TokenKind.literalString:
        _next();
        return Literal(token.start, token.data);
      case TokenKind.lparen:
        _next();
        final inner = _expression();
        _expect(TokenKind.rparen, "')'");
        return inner;
      case TokenKind.lcurly:
        return _inline();
      case TokenKind.lsquare:
        return _indexer(nullSafe: false);
      case TokenKind.hash:
        _next();
        final name = _expect(
          TokenKind.identifier,
          'a variable or function name',
        );
        if (_peek(TokenKind.lparen)) {
          return FunctionReference(token.start, name.data!, _arguments());
        }
        return VariableReference(token.start, name.data!);
      case TokenKind.beanRef || TokenKind.factoryBeanRef:
        _next();
        final name = _current;
        if (name == null ||
            (name.kind != TokenKind.identifier &&
                name.kind != TokenKind.literalString)) {
          throw _error(
            SpelMessage.unexpectedToken,
            'Expected a bean name after ${token.kind == TokenKind.beanRef ? '@' : '&'}',
            token.end,
          );
        }
        _next();
        return BeanReference(
          token.start,
          name.data!,
          factory: token.kind == TokenKind.factoryBeanRef,
        );
      case TokenKind.select ||
          TokenKind.selectFirst ||
          TokenKind.selectLast ||
          TokenKind.project:
        return _selectionOrProjection(nullSafe: false);
      case TokenKind.identifier:
        final lower = token.data!.toLowerCase();
        if (lower == 'true' || lower == 'false') {
          _next();
          return Literal(token.start, lower == 'true');
        }
        if (lower == 'null') {
          _next();
          return Literal(token.start, null);
        }
        if (token.data == 'T' && _peekAt(1, TokenKind.lparen)) {
          _next();
          _next();
          final name = _qualifiedName();
          _expect(TokenKind.rparen, "')' after the type name");
          return TypeReference(token.start, name);
        }
        if (token.data == 'new' && _peekAt(1, TokenKind.identifier)) {
          _next();
          final name = _qualifiedName();
          return ConstructorReference(token.start, name, _arguments());
        }
        return _methodOrProperty(nullSafe: false);
      default:
        throw _error(
          SpelMessage.unexpectedToken,
          "Unexpected token '${_describe(token)}'",
          token.start,
        );
    }
  }

  // `a.b.C`: dotted names are kept as one string for the TypeLocator.
  String _qualifiedName() {
    final parts = [_expect(TokenKind.identifier, 'a type name').data!];
    while (_peek(TokenKind.dot) && _peekAt(1, TokenKind.identifier)) {
      _next();
      parts.add(_next().data!);
    }
    return parts.join('.');
  }

  /// `{}`, `{:}`, `{1, 2}`, `{a: 1, 'b': 2}`.
  ///
  /// The first item decides: a `:` after it makes an inline map,
  /// otherwise an inline list.
  SpelNode _inline() {
    final open = _next();
    if (_peek(TokenKind.rcurly)) {
      _next();
      return InlineList(open.start, const []);
    }
    if (_peek(TokenKind.colon) && _peekAt(1, TokenKind.rcurly)) {
      _next();
      _next();
      return InlineMap(open.start, const []);
    }
    final first = _expression();
    if (_peek(TokenKind.colon)) {
      _next();
      final entries = [(first, _expression())];
      while (_peek(TokenKind.comma)) {
        _next();
        final key = _expression();
        _expect(TokenKind.colon, "':' in inline map");
        entries.add((key, _expression()));
      }
      _expect(TokenKind.rcurly, "'}'");
      return InlineMap(open.start, entries);
    }
    final items = [first];
    while (_peek(TokenKind.comma)) {
      _next();
      items.add(_expression());
    }
    _expect(TokenKind.rcurly, "'}'");
    return InlineList(open.start, items);
  }

  int _parseInt(Token token, String digits, int radix) =>
      int.tryParse(digits, radix: radix) ??
      (throw _error(
        SpelMessage.invalidNumber,
        "Number '$digits' is too large",
        token.start,
      ));

  Token? get _current => _pos < _tokens.length ? _tokens[_pos] : null;

  bool _peek(TokenKind kind) => _current?.kind == kind;

  bool _peekAt(int offset, TokenKind kind) =>
      _pos + offset < _tokens.length && _tokens[_pos + offset].kind == kind;

  Token _next() => _tokens[_pos++];

  Token _expect(TokenKind kind, String description) {
    final token = _current;
    if (token == null) {
      throw _error(
        SpelMessage.unexpectedEndOfExpression,
        'Expected $description but the expression ended',
        text.length,
      );
    }
    if (token.kind != kind) {
      throw _error(
        SpelMessage.unexpectedToken,
        "Expected $description but found '${_describe(token)}'",
        token.start,
      );
    }
    return _next();
  }

  String _describe(Token token) => text.substring(token.start, token.end);

  SpelParseException _error(SpelMessage code, String message, int position) =>
      SpelParseException(
        code,
        message,
        expressionString: text,
        position: position,
      );
}
