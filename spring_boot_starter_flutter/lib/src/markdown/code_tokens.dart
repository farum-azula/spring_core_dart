/// What a piece of code is, for its color: the token kinds `styles.code`
/// colors (`keyword`, `string`, ...).
enum CodeTokenKind {
  /// Anything else: names, operators, spaces.
  plain,

  /// A keyword of the language (`class`, `final`, `if`; `true` in YAML).
  keyword,

  /// A string literal.
  string,

  /// A comment.
  comment,

  /// A number.
  number,

  /// A key: of YAML, properties and JSON.
  key,

  /// An annotation (`@Component()`), a YAML tag (`!include`).
  annotation,

  /// Brackets, braces, commas, colons, a list's dash.
  punctuation,

  /// A reference: a theme's `$colors.primary`, a placeholder `${port}`, a
  /// shell's `$HOME`, a YAML anchor or alias (`&base`, `*base`).
  variable,

  /// A type name of Dart (`Basket`, `String`).
  type,
}

/// One piece of code and its kind.
typedef CodeToken = ({String text, CodeTokenKind kind});

/// Splits code into colored pieces, for the languages of the docs: Dart,
/// YAML, properties, shell and JSON (`dart`, `yaml`/`yml`, `properties`,
/// `sh`/`bash`/`shell`/`console`, `json`). Another language is one plain
/// piece. A small tokenizer of its own: no package of the Dart team does
/// it, and the docs need only these.
///
/// ```dart
/// CodeTokens.of('final a = 1; // one', 'dart');
/// // final (keyword), ' a = ', 1 (number), '; ', '// one' (comment)
/// ```
abstract final class CodeTokens {
  /// The pieces of [code] in [language], in order; joined they are [code].
  static List<CodeToken> of(String code, String? language) =>
      switch (language?.toLowerCase()) {
        'dart' => _scan(code, _dart),
        'yaml' || 'yml' => _yaml(code),
        'properties' || 'ini' => _lines(code, _propertiesLine),
        'sh' || 'bash' || 'shell' || 'console' || 'zsh' => _scan(code, _shell),
        'json' => _scan(code, _json),
        _ => [(text: code, kind: CodeTokenKind.plain)],
      };

  static const _dartKeywords = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'Function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'when',
    'while',
    'with',
    'yield',
  };

  // A type name: a built-in one (`int`) or a capitalized word that is not
  // a constant (`Basket`, not `MAX`).
  static bool _isDartType(String word) =>
      const {'int', 'double', 'num', 'bool'}.contains(word) ||
      RegExp(r'^_?[A-Z]').hasMatch(word) && RegExp('[a-z]').hasMatch(word);

  static final _dart = <(RegExp, CodeTokenKind Function(String))>[
    (RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'), (_) => CodeTokenKind.comment),
    (
      RegExp(
        r"r?'''[\s\S]*?'''|r?"
        '"""'
        r'[\s\S]*?"""'
        r"|r?'(?:\\.|[^'\\\n])*'"
        r'|r?"(?:\\.|[^"\\\n])*"',
      ),
      (_) => CodeTokenKind.string,
    ),
    (RegExp(r'@[A-Za-z_][A-Za-z0-9_.]*'), (_) => CodeTokenKind.annotation),
    (
      RegExp(r'\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b'),
      (_) => CodeTokenKind.number,
    ),
    (
      RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*'),
      (word) => _dartKeywords.contains(word)
          ? CodeTokenKind.keyword
          : _isDartType(word)
          ? CodeTokenKind.type
          : CodeTokenKind.plain,
    ),
    (RegExp(r'[{}()\[\];,]'), (_) => CodeTokenKind.punctuation),
  ];

  static const _shellKeywords = {
    'if',
    'then',
    'else',
    'elif',
    'fi',
    'for',
    'in',
    'do',
    'done',
    'while',
    'case',
    'esac',
    'function',
    'export',
    'cd',
    'echo',
    'return',
  };

  static final _shell = <(RegExp, CodeTokenKind Function(String))>[
    (RegExp(r'#[^\n]*'), (_) => CodeTokenKind.comment),
    (
      RegExp(
        r"'[^']*'|"
        r'"(?:\\.|[^"\\])*"',
      ),
      (_) => CodeTokenKind.string,
    ),
    (RegExp(r'\s--?[A-Za-z][\w-]*'), (_) => CodeTokenKind.key),
    (_variable, (_) => CodeTokenKind.variable),
    (RegExp(r'\|\||&&|[|;<>]'), (_) => CodeTokenKind.punctuation),
    (
      RegExp(r'[A-Za-z_][A-Za-z0-9_-]*'),
      (word) => _shellKeywords.contains(word)
          ? CodeTokenKind.keyword
          : CodeTokenKind.plain,
    ),
  ];

  static final _json = <(RegExp, CodeTokenKind Function(String))>[
    (RegExp(r'"(?:\\.|[^"\\])*"(?=\s*:)'), (_) => CodeTokenKind.key),
    (RegExp(r'"(?:\\.|[^"\\])*"'), (_) => CodeTokenKind.string),
    (
      RegExp(r'-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b'),
      (_) => CodeTokenKind.number,
    ),
    (RegExp(r'\b(?:true|false|null)\b'), (_) => CodeTokenKind.keyword),
    (RegExp(r'[{}\[\],:]'), (_) => CodeTokenKind.punctuation),
  ];

  // A placeholder or reference: `${port}`, `$colors.primary`, `$HOME`.
  static final _variable = RegExp(
    r'\$\{[^}\n]*\}|\$[A-Za-z_][A-Za-z0-9_]*(?:[.-][A-Za-z0-9_]+)*',
  );

  // The pieces of [code]: at each position the first rule that matches
  // there makes a piece; the rest is plain.
  static List<CodeToken> _scan(
    String code,
    List<(RegExp, CodeTokenKind Function(String))> rules,
  ) {
    final tokens = <CodeToken>[];
    var plain = StringBuffer();
    var i = 0;
    void flush() {
      if (plain.isNotEmpty) {
        _add(tokens, plain.toString(), CodeTokenKind.plain);
        plain = StringBuffer();
      }
    }

    while (i < code.length) {
      CodeToken? token;
      for (final (pattern, kind) in rules) {
        final match = pattern.matchAsPrefix(code, i);
        if (match != null && match.end > i) {
          token = (text: match[0]!, kind: kind(match[0]!));
          break;
        }
      }
      if (token == null) {
        plain.write(code[i]);
        i++;
        continue;
      }
      flush();
      _add(tokens, token.text, token.kind);
      i += token.text.length;
    }
    flush();
    return tokens;
  }

  static List<CodeToken> _lines(
    String code,
    List<CodeToken> Function(String line) line,
  ) {
    final tokens = <CodeToken>[];
    final lines = code.split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final token in line(lines[i])) {
        _add(tokens, token.text, token.kind);
      }
      if (i < lines.length - 1) {
        _add(tokens, '\n', CodeTokenKind.plain);
      }
    }
    return tokens;
  }

  // YAML, line by line, the flow collections (`{ a: 1 }`, `[a, b]`) kept
  // open across lines.
  static List<CodeToken> _yaml(String code) {
    final tokens = <CodeToken>[];
    void add(String text, CodeTokenKind kind) => _add(tokens, text, kind);
    var depth = 0;
    final lines = code.split('\n');
    for (var n = 0; n < lines.length; n++) {
      if (n > 0) {
        add('\n', CodeTokenKind.plain);
      }
      final line = lines[n];
      final comment = _commentStart(line, '#');
      final body = comment < 0 ? line : line.substring(0, comment);
      var i = 0;
      if (depth == 0) {
        final marker = _yamlMarker.matchAsPrefix(body);
        if (marker != null) {
          add(marker[0]!, CodeTokenKind.punctuation);
          i = marker.end;
        }
        // `- ` items, one or more, then a key.
        while (true) {
          final dash = _yamlDash.matchAsPrefix(body, i);
          if (dash == null) {
            break;
          }
          add(dash[1]!, CodeTokenKind.plain);
          add('-', CodeTokenKind.punctuation);
          i = dash.end;
        }
      }
      i = _yamlKeyAt(body, i, add);
      depth = _yamlValue(body, i, depth, add);
      if (comment >= 0) {
        add(line.substring(comment), CodeTokenKind.comment);
      }
    }
    return tokens;
  }

  static final _yamlMarker = RegExp(r'(?:---|\.\.\.)(?=\s|$)');
  static final _yamlDash = RegExp(r'(\s*)-(?=\s|$)');
  static final _yamlKey = RegExp(
    r'(\s*)("(?:\\.|[^"\\])*"'
    r"|'(?:''|[^'])*'"
    r'|[^\s#:,{}\[\]&*!|>%@`'
    "'"
    r'"-][^#:,{}\[\]]*?'
    r'|-[^\s#:,{}\[\]][^#:,{}\[\]]*?)(\s*)(:)(?=\s|$|[,}\]])',
  );

  // A key at [i] of [body] (`name:`), added; the position after it.
  static int _yamlKeyAt(
    String body,
    int i,
    void Function(String, CodeTokenKind) add,
  ) {
    final key = _yamlKey.matchAsPrefix(body, i);
    if (key == null) {
      return i;
    }
    add(key[1]!, CodeTokenKind.plain);
    add(key[2]!, CodeTokenKind.key);
    add(key[3]!, CodeTokenKind.plain);
    add(key[4]!, CodeTokenKind.punctuation);
    return key.end;
  }

  // The value part of a YAML line from [start]: flow brackets, keys inside
  // them, quoted strings, references and plain words; the flow depth after.
  static int _yamlValue(
    String body,
    int start,
    int depth,
    void Function(String, CodeTokenKind) add,
  ) {
    var i = start;
    var level = depth;
    while (i < body.length) {
      final char = body[i];
      if (char == ' ' || char == '\t') {
        add(char, CodeTokenKind.plain);
        i++;
        continue;
      }
      if (char == '{' || char == '[') {
        add(char, CodeTokenKind.punctuation);
        level++;
        i = _yamlKeyAt(body, i + 1, add);
        continue;
      }
      if (char == '}' || char == ']') {
        add(char, CodeTokenKind.punctuation);
        level = level > 0 ? level - 1 : 0;
        i++;
        continue;
      }
      if (char == ',' && level > 0) {
        add(char, CodeTokenKind.punctuation);
        i = _yamlKeyAt(body, i + 1, add);
        continue;
      }
      if (char == '"' || char == "'") {
        final quoted = (char == '"' ? _yamlDouble : _yamlSingle).matchAsPrefix(
          body,
          i,
        );
        final end = quoted?.end ?? body.length;
        add(body.substring(i, end), CodeTokenKind.string);
        i = end;
        continue;
      }
      final block = _yamlBlock.matchAsPrefix(body, i);
      if (level == 0 && block != null) {
        add(block[0]!, CodeTokenKind.punctuation);
        i = block.end;
        continue;
      }
      final special = _yamlSpecial.matchAsPrefix(body, i);
      if (special != null) {
        add(
          special[0]!,
          special[0]!.startsWith('!')
              ? CodeTokenKind.annotation
              : CodeTokenKind.variable,
        );
        i = special.end;
        continue;
      }
      // A plain word: up to a space, or a flow character inside a flow.
      final word = (level > 0 ? _yamlFlowWord : _yamlWord).matchAsPrefix(
        body,
        i,
      );
      final end = word == null || word.end == i ? i + 1 : word.end;
      _word(body.substring(i, end), add);
      i = end;
    }
    return level;
  }

  static final _yamlDouble = RegExp(r'"(?:\\.|[^"\\])*"?');
  static final _yamlSingle = RegExp(r"'(?:''|[^'])*'?");
  static final _yamlBlock = RegExp(r'[|>][-+0-9]*(?=\s*$)');
  static final _yamlSpecial = RegExp(r'[&*][\w.-]+|![\w!./:-]*');
  static final _yamlWord = RegExp(r'\S+');
  static final _yamlFlowWord = RegExp(r'[^\s,{}\[\]]+');
  static final _number = RegExp(
    r'^[-+]?(?:0x[0-9a-fA-F]+|(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][-+]?\d+)?'
    r'(?:ms|us|ns|s|m|h|d|%|px|x)?)$',
  );
  static const _yamlKeywords = {
    'true',
    'false',
    'null',
    '~',
    'yes',
    'no',
    'on',
    'off',
    'True',
    'False',
    'Null',
    'TRUE',
    'FALSE',
    'NULL',
  };

  // A plain word of a value: a number (`120ms`, `35%`), a keyword
  // (`true`), references inside it (`${a}-b`), or text, which is a string
  // without quotes (`ease-out`), colored as one as editors do.
  static void _word(String word, void Function(String, CodeTokenKind) add) {
    if (_number.hasMatch(word)) {
      add(word, CodeTokenKind.number);
      return;
    }
    if (_yamlKeywords.contains(word)) {
      add(word, CodeTokenKind.keyword);
      return;
    }
    var i = 0;
    for (final match in _variable.allMatches(word)) {
      add(word.substring(i, match.start), CodeTokenKind.string);
      add(match[0]!, CodeTokenKind.variable);
      i = match.end;
    }
    add(word.substring(i), CodeTokenKind.string);
  }

  static List<CodeToken> _propertiesLine(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#') || trimmed.startsWith('!')) {
      return [(text: line, kind: CodeTokenKind.comment)];
    }
    final separator = RegExp(r'\s*[=:]\s*|\s+').firstMatch(trimmed);
    if (separator == null) {
      return [(text: line, kind: CodeTokenKind.key)];
    }
    final indent = line.substring(0, line.length - trimmed.length);
    final tokens = <CodeToken>[];
    void add(String text, CodeTokenKind kind) => _add(tokens, text, kind);
    add(indent, CodeTokenKind.plain);
    add(trimmed.substring(0, separator.start), CodeTokenKind.key);
    final sign = separator[0]!;
    final at = sign.indexOf(RegExp('[=:]'));
    if (at < 0) {
      add(sign, CodeTokenKind.plain);
    } else {
      add(sign.substring(0, at), CodeTokenKind.plain);
      add(sign[at], CodeTokenKind.punctuation);
      add(sign.substring(at + 1), CodeTokenKind.plain);
    }
    final value = trimmed.substring(separator.end);
    for (final part in RegExp(r'\s+|[^\s,]+|,').allMatches(value)) {
      final text = part[0]!;
      if (text == ',') {
        add(text, CodeTokenKind.punctuation);
      } else if (text.trim().isEmpty) {
        add(text, CodeTokenKind.plain);
      } else {
        _word(text, add);
      }
    }
    return tokens;
  }

  // Where a comment starts in [line] (outside quotes), or -1.
  static int _commentStart(String line, String marker) {
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == marker && (i == 0 || line[i - 1] == ' ')) {
        return i;
      }
    }
    return -1;
  }

  // Adds a piece, merged with the one before when of the same kind.
  static void _add(List<CodeToken> tokens, String text, CodeTokenKind kind) {
    if (text.isEmpty) {
      return;
    }
    if (tokens.isNotEmpty && tokens.last.kind == kind) {
      tokens.last = (text: tokens.last.text + text, kind: kind);
      return;
    }
    tokens.add((text: text, kind: kind));
  }
}
