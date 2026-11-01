/// What a piece of SQL text is made of, for the checks the build does on
/// the SQL of `@Query` methods and on the migrations.
library;

/// The kinds of [SqlToken].
enum SqlTokenKind {
  /// An unquoted name or keyword: `select`, `books`, `author_id`.
  word,

  /// A quoted name, `"order"` or `` `order` ``; the value is the name.
  quoted,

  /// A string literal, `'...'` or `$tag$...$tag$`.
  string,

  /// A number: `42`, `1.5`, `1e5`.
  number,

  /// A named parameter, `:year` or `:{year}`; the value is the name.
  parameter,

  /// A `:#{expression}` parameter; the value is the expression.
  expression,

  /// A `#{expression}`; the value is the expression.
  elExpression,

  /// A `${property}` placeholder; the value is its text.
  property,

  /// An entity placeholder, `{Book}` or `{Book.authorId}`; the value is the
  /// entity's class name and the member the property, or `null`.
  entity,

  /// A plain `?` marker.
  question,

  /// Any other character; `::` (a cast) is one symbol.
  symbol,

  /// A `:#{` or `#{` that is never closed; the text is the rest of the
  /// input.
  unclosed,

  /// A `:{name}` that is empty or never closed; the value says which.
  badParameter,
}

/// A piece of SQL: its [kind], the [text] as written and where it is.
final class SqlToken {
  /// A token of [kind] covering `[start, end)` of the input.
  const SqlToken(
    this.kind,
    this.text,
    this.start,
    this.end, {
    this.member,
    String? value,
  }) : value = value ?? text;

  /// What it is.
  final SqlTokenKind kind;

  /// The token as written.
  final String text;

  /// Where it starts in the input.
  final int start;

  /// Where it ends (exclusive).
  final int end;

  /// For an entity placeholder, the property after the dot; else `null`.
  final String? member;

  /// The meaning of the token: the name of a parameter, the text inside a
  /// placeholder or expression, a quoted name without its quotes; the text
  /// itself for the others.
  final String value;

  /// The word in lower case (a keyword is compared this way).
  String get lower => value.toLowerCase();

  /// Whether this is the symbol [symbol].
  bool isSymbol(String symbol) => kind == SqlTokenKind.symbol && text == symbol;

  /// Whether this is the unquoted word [word], in any case.
  bool isWord(String word) => kind == SqlTokenKind.word && lower == word;

  /// Whether this is a name: a word or a quoted name.
  bool get isName => kind == SqlTokenKind.word || kind == SqlTokenKind.quoted;

  @override
  String toString() => '${kind.name}($text)';
}

/// Cuts SQL text into [SqlToken]s, leaving out comments and white space.
///
/// It reads what the `@Query` runtime reads, in the same way, so the build
/// and the run time agree on the text: quoted text (`'...'`, `"..."`,
/// `` `...` ``, a doubled quote inside is part of it), `--` and `/* */`
/// comments, `$tag$...$tag$` literals, `::` (a cast), `:name` and `:{name}`
/// parameters (a name has letters, digits, `_` and inner dots), `:#{...}`
/// expressions, `#{...}`, `${...}` and `{Entity.property}` placeholders.
/// Anything quoted or commented stays out of every other kind.
///
/// ```dart
/// SqlLexer.tokenize("select title from books where id = :id -- one");
/// // select, title, from, books, where, id, =, :id
/// ```
///
/// Spring (Java): none; the scan of `NamedParameterUtils.parseSqlStatement`
/// and of `StringBasedJdbcQuery`'s `SpelEvaluator`.
abstract final class SqlLexer {
  static final RegExp _dollarTag = RegExp(r'\$[A-Za-z_]*\$');
  static final RegExp _entity = RegExp(
    r'\{([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?\}',
  );
  static final RegExp _number = RegExp(r'[0-9][A-Za-z0-9_]*(?:\.[0-9]+)?');

  /// The tokens of [text], in order.
  static List<SqlToken> tokenize(String text) {
    final tokens = <SqlToken>[];
    final n = text.length;
    var i = 0;
    String at(int index) => index < n ? text[index] : '';
    void add(SqlTokenKind kind, int end, {String? value, String? member}) {
      tokens.add(
        SqlToken(
          kind,
          text.substring(i, end),
          i,
          end,
          value: value,
          member: member,
        ),
      );
      i = end;
    }

    while (i < n) {
      final c = text[i];
      final next = at(i + 1);
      if (c.trim().isEmpty) {
        i++;
      } else if (c == "'") {
        add(SqlTokenKind.string, endOfQuote(text, i));
      } else if (c == '"' || c == '`') {
        final end = endOfQuote(text, i);
        final closed = end - i >= 2 && text[end - 1] == c;
        final inner = text.substring(i + 1, closed ? end - 1 : end);
        add(
          SqlTokenKind.quoted,
          end,
          value: inner.replaceAll('$c$c', c),
        );
      } else if (c == '-' && next == '-') {
        final end = text.indexOf('\n', i);
        i = end < 0 ? n : end + 1;
      } else if (c == '/' && next == '*') {
        final end = text.indexOf('*/', i + 2);
        i = end < 0 ? n : end + 2;
      } else if (c == r'$' && next == '{') {
        final close = endOfBraces(text, i + 2);
        if (close < 0) {
          add(SqlTokenKind.symbol, i + 1);
        } else {
          add(
            SqlTokenKind.property,
            close + 1,
            value: text.substring(i + 2, close),
          );
        }
      } else if (c == r'$' && _dollarTag.matchAsPrefix(text, i) != null) {
        final tag = _dollarTag.matchAsPrefix(text, i)![0]!;
        final end = text.indexOf(tag, i + tag.length);
        add(SqlTokenKind.string, end < 0 ? n : end + tag.length);
      } else if (c == ':' && next == ':') {
        add(SqlTokenKind.symbol, i + 2);
      } else if (c == ':' && next == '#' && at(i + 2) == '{') {
        final close = endOfBraces(text, i + 3);
        if (close < 0) {
          add(SqlTokenKind.unclosed, n);
        } else {
          add(
            SqlTokenKind.expression,
            close + 1,
            value: text.substring(i + 3, close).trim(),
          );
        }
      } else if (c == '#' && next == '{') {
        final close = endOfBraces(text, i + 2);
        if (close < 0) {
          add(SqlTokenKind.unclosed, n);
        } else {
          add(
            SqlTokenKind.elExpression,
            close + 1,
            value: text.substring(i + 2, close).trim(),
          );
        }
      } else if (c == ':' && next == '{') {
        final close = text.indexOf('}', i + 2);
        if (close < 0) {
          add(
            SqlTokenKind.badParameter,
            n,
            value: 'Unterminated :{ parameter at position $i of [$text]',
          );
        } else if (close == i + 2) {
          add(
            SqlTokenKind.badParameter,
            close + 1,
            value: 'Empty parameter :{} at position $i of [$text]',
          );
        } else {
          add(
            SqlTokenKind.parameter,
            close + 1,
            value: text.substring(i + 2, close),
          );
        }
      } else if (c == ':' && next.isNotEmpty && _isNameStart(next)) {
        var j = i + 1;
        while (j < n) {
          if (_isNameChar(text[j]) ||
              (text[j] == '.' && j + 1 < n && _isNameStart(text[j + 1]))) {
            j++;
          } else {
            break;
          }
        }
        add(SqlTokenKind.parameter, j, value: text.substring(i + 1, j));
      } else if (c == '{' && _entity.matchAsPrefix(text, i) != null) {
        final match = _entity.matchAsPrefix(text, i)!;
        add(
          SqlTokenKind.entity,
          match.end,
          value: match[1],
          member: match[2],
        );
      } else if (c == '?') {
        add(SqlTokenKind.question, i + 1);
      } else if (_isDigit(c)) {
        add(SqlTokenKind.number, _number.matchAsPrefix(text, i)!.end);
      } else if (_isWordStart(c)) {
        var j = i + 1;
        // A `${property}` ends a word that touches it: `books_${year}`.
        while (j < n &&
            _isWordChar(text[j]) &&
            !(text[j] == r'$' && at(j + 1) == '{')) {
          j++;
        }
        add(SqlTokenKind.word, j);
      } else {
        add(SqlTokenKind.symbol, i + 1);
      }
    }
    return tokens;
  }

  /// The end (exclusive) of the quoted text that starts at [start]; a quote
  /// doubled inside is part of the text, and an unclosed one runs to the
  /// end.
  static int endOfQuote(String text, int start) {
    final quote = text[start];
    var j = start + 1;
    while (j < text.length) {
      if (text[j] == quote) {
        if (j + 1 < text.length && text[j + 1] == quote) {
          j += 2;
          continue;
        }
        return j + 1;
      }
      j++;
    }
    return text.length;
  }

  /// The index of the `}` that closes the `{` before [start]; -1 when there
  /// is none. Braces nest, and SpEL strings may hold braces.
  static int endOfBraces(String text, int start) {
    var depth = 1;
    var j = start;
    while (j < text.length) {
      final c = text[j];
      if (c == "'" || c == '"') {
        j = endOfQuote(text, j);
        continue;
      }
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          return j;
        }
      }
      j++;
    }
    return -1;
  }

  static bool _isDigit(String c) =>
      c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

  static bool _isNameStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F;
  }

  static bool _isNameChar(String c) => _isNameStart(c) || _isDigit(c);

  // A letter, `_` or a character beyond ASCII (a name in another script).
  static bool _isWordStart(String c) =>
      _isNameStart(c) || c.codeUnitAt(0) > 0x7F;

  static bool _isWordChar(String c) =>
      _isWordStart(c) || _isDigit(c) || c == r'$';
}
