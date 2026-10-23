import 'package:spring_core_dart/src/expression/expression_exceptions.dart';

/// Token kinds of SpEL, like Spring's `TokenKind`.
///
/// Textual operators (`div`, `mod`, `and`, `or`, `not`, `eq`, `ne`, `lt`,
/// `le`, `gt`, `ge`, `instanceof`, `matches`, `between`) are matched
/// case-insensitively and map to the same kinds as their symbols.
///
/// ```dart
/// final kinds = Tokenizer('a.?[x gt 1]').process().map((t) => t.kind);
/// // identifier, select, identifier, gt, literalInt, rsquare
/// ```
///
/// Spring (Java):
/// ```java
/// // Internal to org.springframework.expression.spel.standard:
/// // TokenKind.IDENTIFIER, TokenKind.SELECT, TokenKind.GT, ...
/// ```
enum TokenKind {
  /// A decimal integer, e.g. `42`.
  literalInt,

  /// A decimal integer with an `L` suffix, e.g. `42L` (a Dart `int`).
  literalLong,

  /// A hexadecimal integer, e.g. `0x7F`.
  literalHexInt,

  /// A hexadecimal integer with an `L` suffix, e.g. `0xFFL`.
  literalHexLong,

  /// A real number, e.g. `3.14`, `1e3` or `2d`.
  literalReal,

  /// A real number with an `f` suffix, e.g. `1.5f` (a Dart `double`).
  literalRealFloat,

  /// A quoted string, e.g. `'text'` or `"text"`.
  literalString,

  /// A name: property, method, type or variable name, `true`, `null`...
  identifier,

  /// `(`: grouping, arguments or `T(...)`.
  lparen,

  /// `)`: closes a `(`.
  rparen,

  /// `[`: indexing.
  lsquare,

  /// `]`: closes indexing, selection or projection.
  rsquare,

  /// `{`: opens an inline list or map.
  lcurly,

  /// `}`: closes an inline list or map.
  rcurly,

  /// `,`: separates arguments and inline items.
  comma,

  /// `:`: ternary else-branch or inline map entry.
  colon,

  /// `#`, the variable/function prefix.
  hash,

  /// `.`, property or method navigation.
  dot,

  /// `+`: addition, concatenation or unary plus.
  plus,

  /// `-`: subtraction or negation.
  minus,

  /// `*`: multiplication.
  star,

  /// `/` or `div`.
  div,

  /// `%` or `mod`.
  mod,

  /// `^`: power.
  power,

  /// `!` or `not`.
  not,

  /// `=`: assignment.
  assign,

  /// `==` or `eq`.
  eq,

  /// `!=` or `ne`.
  ne,

  /// `<` or `lt`.
  lt,

  /// `<=` or `le`.
  le,

  /// `>` or `gt`.
  gt,

  /// `>=` or `ge`.
  ge,

  /// `&&` or `and`.
  and,

  /// `||` or `or`.
  or,

  /// `?`, the ternary operator.
  qmark,

  /// `?:`, the Elvis operator.
  elvis,

  /// `?.`, safe navigation.
  safeNavi,

  /// `.?[`, selection of all matches.
  select,

  /// `.^[`, selection of the first match.
  selectFirst,

  /// `.$[`, selection of the last match.
  selectLast,

  /// `.![`, projection.
  project,

  /// `@`, a bean reference.
  beanRef,

  /// `&`, a factory bean reference.
  factoryBeanRef,

  /// `++`: increment.
  inc,

  /// `--`: decrement.
  dec,

  /// `instanceof`: a type check against `T(Name)`.
  instanceOf,

  /// `matches`, a regular expression match.
  matches,

  /// `between`, a range check.
  between,
}

/// One token with its source span, like Spring's `Token`.
///
/// ```dart
/// final token = Tokenizer("'hi'").process().single;
/// token.kind; // TokenKind.literalString
/// token.data; // hi
/// (token.start, token.end); // (0, 4)
/// ```
///
/// Spring (Java):
/// ```java
/// // Internal: new Token(TokenKind.LITERAL_STRING, data, start, end)
/// ```
final class Token {
  /// Creates a token of [kind] spanning [start] (inclusive) to [end]
  /// (exclusive), with optional [data].
  Token(this.kind, this.start, this.end, [this.data]);

  /// What kind of token this is.
  final TokenKind kind;

  /// Offset of the first character in the expression text.
  final int start;

  /// Offset just past the last character in the expression text.
  final int end;

  /// Literal text or identifier name.
  final String? data;

  @override
  String toString() => '$kind${data == null ? '' : '($data)'}@$start';
}

/// Splits an expression into tokens, like Spring's `Tokenizer`.
///
/// Used by `SpelExpressionParser`; you rarely need it directly. Whitespace
/// is skipped, strings use `'` or `"` with the quote doubled as escape
/// (`'It''s'`), and numbers support hex (`0x1F`), exponents (`1e3`) and
/// the suffixes `L`, `f` and `d`.
///
/// ```dart
/// final tokens = Tokenizer('price * 2').process();
/// // [TokenKind.identifier(price)@0, TokenKind.star@6,
///   TokenKind.literalInt(2)@8]
/// ```
///
/// Spring (Java):
/// ```java
/// // Package-private in Spring; used by InternalSpelExpressionParser:
/// List<Token> tokens = new Tokenizer("price * 2").process();
/// ```
final class Tokenizer {
  /// Creates a tokenizer for [expression].
  Tokenizer(this.expression);

  /// The expression text being tokenized.
  final String expression;
  final _tokens = <Token>[];
  int _pos = 0;

  // Word operators; only treated as operators when not right after a dot
  // (see _previousIsDot), so `map.div` stays a property name.
  static const _textualOperators = {
    'div': TokenKind.div,
    'mod': TokenKind.mod,
    'and': TokenKind.and,
    'or': TokenKind.or,
    'not': TokenKind.not,
    'eq': TokenKind.eq,
    'ne': TokenKind.ne,
    'lt': TokenKind.lt,
    'le': TokenKind.le,
    'gt': TokenKind.gt,
    'ge': TokenKind.ge,
    'instanceof': TokenKind.instanceOf,
    'matches': TokenKind.matches,
    'between': TokenKind.between,
  };

  /// Tokenizes the whole [expression] and returns the tokens in order.
  ///
  /// Throws a [SpelParseException] for unknown characters, a single `|`,
  /// unterminated strings and malformed hex numbers.
  List<Token> process() {
    while (_pos < expression.length) {
      final c = expression[_pos];
      if (_isAlpha(c) || c == '_' || c == r'$') {
        _identifier();
      } else if (_isDigit(c)) {
        _number();
      } else if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        _pos++;
      } else if (c == "'" || c == '"') {
        _string(c);
      } else {
        _symbol(c);
      }
    }
    return _tokens;
  }

  // Operators and punctuation; multi-character tokens are recognized by
  // peeking ahead (`++`, `?.`, `?:`, `.?[`, `.![`, `.^[`, `.$[`, ...).
  void _symbol(String c) {
    String peek([int offset = 1]) =>
        _pos + offset < expression.length ? expression[_pos + offset] : '';
    void push(TokenKind kind, int length) {
      _tokens.add(Token(kind, _pos, _pos + length));
      _pos += length;
    }

    switch (c) {
      case '+':
        peek() == '+' ? push(TokenKind.inc, 2) : push(TokenKind.plus, 1);
      case '-':
        peek() == '-' ? push(TokenKind.dec, 2) : push(TokenKind.minus, 1);
      case '*':
        push(TokenKind.star, 1);
      case '/':
        push(TokenKind.div, 1);
      case '%':
        push(TokenKind.mod, 1);
      case '^':
        push(TokenKind.power, 1);
      case '(':
        push(TokenKind.lparen, 1);
      case ')':
        push(TokenKind.rparen, 1);
      case '[':
        push(TokenKind.lsquare, 1);
      case ']':
        push(TokenKind.rsquare, 1);
      case '{':
        push(TokenKind.lcurly, 1);
      case '}':
        push(TokenKind.rcurly, 1);
      case ',':
        push(TokenKind.comma, 1);
      case ':':
        push(TokenKind.colon, 1);
      case '#':
        push(TokenKind.hash, 1);
      case '@':
        push(TokenKind.beanRef, 1);
      case '.':
        // `.?[`, `.![`, `.^[` and `.$[` are single 3-character tokens;
        // otherwise the dot is plain navigation.
        if (peek() == '?' && peek(2) == '[') {
          push(TokenKind.select, 3);
        } else if (peek() == '!' && peek(2) == '[') {
          push(TokenKind.project, 3);
        } else if (peek() == '^' && peek(2) == '[') {
          push(TokenKind.selectFirst, 3);
        } else if (peek() == r'$' && peek(2) == '[') {
          push(TokenKind.selectLast, 3);
        } else {
          push(TokenKind.dot, 1);
        }
      case '?':
        if (peek() == '.') {
          push(TokenKind.safeNavi, 2);
        } else if (peek() == ':') {
          push(TokenKind.elvis, 2);
        } else {
          push(TokenKind.qmark, 1);
        }
      case '!':
        peek() == '=' ? push(TokenKind.ne, 2) : push(TokenKind.not, 1);
      case '=':
        peek() == '=' ? push(TokenKind.eq, 2) : push(TokenKind.assign, 1);
      case '&':
        // `&&` is logical and; a single `&` prefixes a factory bean name.
        peek() == '&'
            ? push(TokenKind.and, 2)
            : push(TokenKind.factoryBeanRef, 1);
      case '|':
        if (peek() != '|') {
          throw _error(SpelMessage.missingCharacter, ['|']);
        }
        push(TokenKind.or, 2);
      case '<':
        peek() == '=' ? push(TokenKind.le, 2) : push(TokenKind.lt, 1);
      case '>':
        peek() == '=' ? push(TokenKind.ge, 2) : push(TokenKind.gt, 1);
      case r'\':
        throw _error(SpelMessage.unexpectedEscapeChar);
      default:
        throw _error(SpelMessage.unsupportedCharacter, [c, c.codeUnitAt(0)]);
    }
  }

  // Letters, digits, `_` and `$`; textual operators become operator
  // tokens unless they follow a dot.
  void _identifier() {
    final start = _pos;
    while (_pos < expression.length &&
        (_isAlpha(expression[_pos]) ||
            _isDigit(expression[_pos]) ||
            expression[_pos] == '_' ||
            expression[_pos] == r'$')) {
      _pos++;
    }
    final text = expression.substring(start, _pos);
    final textual = _textualOperators[text.toLowerCase()];
    if (textual != null && !_previousIsDot()) {
      _tokens.add(Token(textual, start, _pos));
    } else {
      _tokens.add(Token(TokenKind.identifier, start, _pos, text));
    }
  }

  /// Textual operators are plain identifiers after a dot (`a.div`).
  bool _previousIsDot() {
    final last = _tokens.lastOrNull;
    return last != null &&
        (last.kind == TokenKind.dot || last.kind == TokenKind.safeNavi);
  }

  // Hex (`0x..`, optional `L`), or decimal with optional fraction,
  // exponent and `L`/`f`/`d` suffix. Token data holds the digits only.
  void _number() {
    final start = _pos;
    if (expression.startsWith('0x', _pos) ||
        expression.startsWith('0X', _pos)) {
      _pos += 2;
      final digitsStart = _pos;
      while (_pos < expression.length && _isHex(expression[_pos])) {
        _pos++;
      }
      if (_pos == digitsStart) {
        throw _error(SpelMessage.notAnInteger, [
          expression.substring(start, _pos),
        ], start);
      }
      final digits = expression.substring(digitsStart, _pos);
      if (_pos < expression.length &&
          (expression[_pos] == 'L' || expression[_pos] == 'l')) {
        _pos++;
        _tokens.add(Token(TokenKind.literalHexLong, start, _pos, digits));
      } else {
        _tokens.add(Token(TokenKind.literalHexInt, start, _pos, digits));
      }
      return;
    }
    while (_pos < expression.length && _isDigit(expression[_pos])) {
      _pos++;
    }
    var real = false;
    // A dot followed by a digit is a decimal point (not property access).
    if (_pos + 1 < expression.length &&
        expression[_pos] == '.' &&
        _isDigit(expression[_pos + 1])) {
      real = true;
      _pos++;
      while (_pos < expression.length && _isDigit(expression[_pos])) {
        _pos++;
      }
    }
    if (_pos < expression.length &&
        (expression[_pos] == 'e' || expression[_pos] == 'E')) {
      // Only an exponent if digits follow; otherwise back off so `1e`
      // tokenizes as `1` followed by the identifier `e`.
      final save = _pos;
      _pos++;
      if (_pos < expression.length &&
          (expression[_pos] == '+' || expression[_pos] == '-')) {
        _pos++;
      }
      if (_pos < expression.length && _isDigit(expression[_pos])) {
        real = true;
        while (_pos < expression.length && _isDigit(expression[_pos])) {
          _pos++;
        }
      } else {
        _pos = save;
      }
    }
    final text = expression.substring(start, _pos);
    if (_pos < expression.length) {
      final suffix = expression[_pos].toLowerCase();
      // `L` only applies to integers; `f`/`d` turn any number into a
      // real literal.
      if (suffix == 'l') {
        if (real) {
          throw _error(SpelMessage.realCannotBeLong, const [], start);
        }
        _pos++;
        _tokens.add(Token(TokenKind.literalLong, start, _pos, text));
        return;
      }
      if (suffix == 'f') {
        _pos++;
        _tokens.add(Token(TokenKind.literalRealFloat, start, _pos, text));
        return;
      }
      if (suffix == 'd') {
        _pos++;
        _tokens.add(Token(TokenKind.literalReal, start, _pos, text));
        return;
      }
    }
    _tokens.add(
      Token(
        real ? TokenKind.literalReal : TokenKind.literalInt,
        start,
        _pos,
        text,
      ),
    );
  }

  // A quoted string; the quote character doubled inside the literal is
  // an escaped quote (`'It''s'`). No backslash escapes, like Spring.
  void _string(String quote) {
    final start = _pos;
    _pos++;
    final buffer = StringBuffer();
    while (true) {
      if (_pos >= expression.length) {
        throw _error(
          quote == "'"
              ? SpelMessage.nonTerminatingQuotedString
              : SpelMessage.nonTerminatingDoubleQuotedString,
          const [],
          start,
        );
      }
      final c = expression[_pos];
      if (c == quote) {
        if (_pos + 1 < expression.length && expression[_pos + 1] == quote) {
          buffer.write(quote);
          _pos += 2;
          continue;
        }
        _pos++;
        break;
      }
      buffer.write(c);
      _pos++;
    }
    _tokens.add(Token(TokenKind.literalString, start, _pos, buffer.toString()));
  }

  SpelParseException _error(
    SpelMessage code, [
    List<Object?> inserts = const [],
    int? position,
  ]) => SpelParseException(
    code,
    inserts: inserts,
    expressionString: expression,
    position: position ?? _pos,
  );

  // ASCII letters plus any non-ASCII code unit, so Unicode identifiers
  // work.
  static bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code > 127;
  }

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isHex(String c) => _isDigit(c) || 'abcdefABCDEF'.contains(c);
}
