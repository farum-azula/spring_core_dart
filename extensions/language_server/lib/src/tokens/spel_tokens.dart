import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';
// The SpEL tokenizer is not exported: the highlighting reads its tokens.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// The words of SpEL coloured as keywords, in lower case.
const _keywords = {
  'true',
  'false',
  'null',
  'new',
  'and',
  'or',
  'not',
  'instanceof',
  'matches',
  'between',
  'eq',
  'ne',
  'lt',
  'le',
  'gt',
  'ge',
  'div',
  'mod',
};

/// The literal tokens and their colour.
const Map<TokenKind, TokenType> _literals = {
  TokenKind.literalInt: TokenType.number,
  TokenKind.literalLong: TokenType.number,
  TokenKind.literalHexInt: TokenType.number,
  TokenKind.literalHexLong: TokenType.number,
  TokenKind.literalReal: TokenType.number,
  TokenKind.literalRealFloat: TokenType.number,
  TokenKind.literalString: TokenType.string,
};

/// The tokens coloured as operators. Brackets, commas, colons and dots
/// are left as they are, and `#`, `@` and `&` are coloured with the name
/// after them.
const Set<TokenKind> _operators = {
  TokenKind.plus,
  TokenKind.minus,
  TokenKind.star,
  TokenKind.div,
  TokenKind.mod,
  TokenKind.power,
  TokenKind.not,
  TokenKind.assign,
  TokenKind.eq,
  TokenKind.ne,
  TokenKind.lt,
  TokenKind.le,
  TokenKind.gt,
  TokenKind.ge,
  TokenKind.and,
  TokenKind.or,
  TokenKind.qmark,
  TokenKind.elvis,
  TokenKind.safeNavi,
  TokenKind.select,
  TokenKind.selectFirst,
  TokenKind.selectLast,
  TokenKind.project,
  TokenKind.inc,
  TokenKind.dec,
  TokenKind.instanceOf,
  TokenKind.matches,
  TokenKind.between,
};

/// Calls [add] with the span (offsets from [offset]) and the token type of
/// each piece of the SpEL [expression]. An expression the tokenizer
/// rejects gives no tokens.
void spelTokens(String expression, int offset, AddToken add) {
  final List<Token> tokens;
  try {
    tokens = Tokenizer(expression).process();
  } on Object {
    return;
  }
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final start = offset + token.start;
    final end = offset + token.end;
    if (_literals[token.kind] case final type?) {
      add(start, end, type);
    } else if (_operators.contains(token.kind)) {
      add(start, end, TokenType.operator);
    } else if (token.kind == TokenKind.identifier) {
      final (from, type) = _identifier(expression, tokens, i);
      add(offset + from, end, type);
    }
  }
}

// The start and the colour of the identifier at [i]: a keyword, `T` of
// `T(...)`, a `#variable`, an `@bean` or `&bean`, the type inside `T(...)`,
// a method, else a property.
(int, TokenType) _identifier(String expression, List<Token> tokens, int i) {
  final token = tokens[i];
  final name = expression.substring(token.start, token.end);
  final previous = i > 0 ? tokens[i - 1].kind : null;
  final next = i + 1 < tokens.length ? tokens[i + 1].kind : null;
  if (name == 'T' && next == TokenKind.lparen ||
      _keywords.contains(name.toLowerCase())) {
    return (token.start, TokenType.keyword);
  }
  if (previous == TokenKind.hash) {
    return (token.start - 1, TokenType.variable);
  }
  if (previous == TokenKind.beanRef || previous == TokenKind.factoryBeanRef) {
    return (token.start - 1, TokenType.classType);
  }
  if (i >= 2 &&
      tokens[i - 2].kind == TokenKind.identifier &&
      expression.substring(tokens[i - 2].start, tokens[i - 2].end) == 'T' &&
      previous == TokenKind.lparen) {
    return (token.start, TokenType.type);
  }
  if (next == TokenKind.lparen) {
    return (token.start, TokenType.method);
  }
  return (token.start, TokenType.property);
}
