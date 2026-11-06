import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

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

  /// A type name (`Basket`, `String`).
  type,
}

/// One piece of code and its kind.
typedef CodeToken = ({String text, CodeTokenKind kind});

/// One rule of a [CodeSyntax]: where [pattern] matches, the text is a
/// piece of [kind]; a [word] rule gives a keyword, a type or plain text by
/// the language's lists.
final class CodeRule {
  /// A rule coloring what [pattern] matches as [kind], or, with [word],
  /// by the language's keywords and types.
  const CodeRule(this.pattern, this.kind, {this.word = false});

  /// What the rule matches, tried at each position in the rules' order.
  final RegExp pattern;

  /// The kind of a match; not used by a [word] rule.
  final CodeTokenKind kind;

  /// Whether a match is a word to look up in the keywords and types.
  final bool word;
}

/// A language of the code blocks, read from the theme's `syntax.<name>`:
/// its rules in order, its keywords, the pattern of its type names and
/// the other names a block may give it (`yml` for `yaml`).
///
/// The starter knows no language by itself: a theme brings the languages
/// it colors (in a file of its own, or downloaded with `source:`), and a
/// block in a language no theme has is plain text.
///
/// ```yaml
/// syntax:
///   java:
///     aliases: [jav]
///     keywords: [class, public, return, new]
///     types: '^[A-Z][A-Za-z0-9_]*[a-z]'
///     rules:
///       - { match: '//[^\n]*', kind: comment }
///       - { match: '"(?:\\.|[^"\\\n])*"', kind: string }
///       - { match: '@[A-Za-z_][\w.]*', kind: annotation }
///       - { match: '[A-Za-z_$][\w$]*', kind: word }
/// ```
final class CodeSyntax {
  /// A language of [rules], [keywords] and [types].
  CodeSyntax({
    required this.rules,
    this.keywords = const {},
    this.types,
    this.aliases = const [],
  });

  /// The kinds a rule may name: those of [CodeTokenKind], and `word`.
  static final kinds = [
    for (final kind in CodeTokenKind.values) kind.name,
    'word',
  ];

  static const _keys = {'rules', 'keywords', 'types', 'aliases'};

  /// Reads `syntax.<name>` of the theme [p]: `rules` (each a `match`, a
  /// regular expression, and a `kind`), `keywords`, `types` and `aliases`.
  /// Throws a [ThemePropertyException] for a missing or invalid value.
  factory CodeSyntax.parse(ThemeProperties p, String name) {
    final base = 'syntax.$name';
    for (final key in p.children(base)) {
      if (!_keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          '',
          'a key of a language: rules, keywords, types, aliases',
        );
      }
    }
    final indexes = [
      for (final child in p.children('$base.rules')) ?int.tryParse(child),
    ]..sort();
    if (indexes.isEmpty) {
      throw ThemePropertyException(
        p.propertyName('$base.rules'),
        '',
        'a list of rules, each { match, kind }',
      );
    }
    return CodeSyntax(
      rules: [for (final index in indexes) _rule(p, '$base.rules.$index')],
      keywords: {...?p.list('$base.keywords')},
      types: switch (p['$base.types']) {
        final pattern? => _pattern(p, '$base.types', pattern),
        null => null,
      },
      aliases: [...?p.list('$base.aliases')],
    );
  }

  static CodeRule _rule(ThemeProperties p, String path) {
    final match = p['$path.match'];
    if (match == null) {
      throw ThemePropertyException(
        p.propertyName('$path.match'),
        '',
        'a regular expression',
      );
    }
    final kind = p['$path.kind'] ?? '';
    final canonical = ThemeValues.canonical(kind);
    final word = canonical == 'word';
    final found = word
        ? CodeTokenKind.plain
        : CodeTokenKind.values
              .where((k) => ThemeValues.canonical(k.name) == canonical)
              .firstOrNull;
    if (found == null) {
      throw ThemePropertyException(
        p.propertyName('$path.kind'),
        kind,
        'a kind: ${kinds.join(', ')}',
      );
    }
    return CodeRule(_pattern(p, '$path.match', match), found, word: word);
  }

  static RegExp _pattern(ThemeProperties p, String path, String source) {
    try {
      return RegExp(source, multiLine: true);
    } on FormatException catch (error) {
      throw ThemePropertyException(
        p.propertyName(path),
        source,
        'a regular expression (${error.message})',
      );
    }
  }

  /// The rules, tried in order at each position; the first that matches
  /// wins.
  final List<CodeRule> rules;

  /// The words a `word` rule colors as keywords.
  final Set<String> keywords;

  /// The pattern a word must match to be a type name; `null` for none.
  final RegExp? types;

  /// The other names of the language in a fenced block (`yml`, `bash`).
  final List<String> aliases;

  /// The pieces of [code] with their kinds; what no rule matches is plain,
  /// and neighbors of one kind are one piece.
  List<CodeToken> tokens(String code) {
    final tokens = <CodeToken>[];
    final plain = StringBuffer();
    void add(String text, CodeTokenKind kind) {
      if (tokens.isNotEmpty && tokens.last.kind == kind) {
        tokens.last = (text: tokens.last.text + text, kind: kind);
      } else {
        tokens.add((text: text, kind: kind));
      }
    }

    void flush() {
      if (plain.isNotEmpty) {
        add(plain.toString(), CodeTokenKind.plain);
        plain.clear();
      }
    }

    var i = 0;
    while (i < code.length) {
      CodeToken? token;
      for (final rule in rules) {
        final match = rule.pattern.matchAsPrefix(code, i);
        if (match != null && match.end > i) {
          final text = match[0]!;
          token = (text: text, kind: rule.word ? _word(text) : rule.kind);
          break;
        }
      }
      if (token == null) {
        plain.write(code[i]);
        i++;
        continue;
      }
      flush();
      add(token.text, token.kind);
      i += token.text.length;
    }
    flush();
    return tokens;
  }

  CodeTokenKind _word(String word) => keywords.contains(word)
      ? CodeTokenKind.keyword
      : (types?.hasMatch(word) ?? false)
      ? CodeTokenKind.type
      : CodeTokenKind.plain;
}

/// Splits code into colored pieces by a language of the theme
/// (`syntax.<name>`, see [CodeSyntax]).
///
/// ```dart
/// CodeTokens.of('final a = 1;', SpringTheme.of(context).data.syntaxOf('dart'));
/// ```
abstract final class CodeTokens {
  /// The pieces of [code] in [syntax]; one plain piece without one.
  static List<CodeToken> of(String code, CodeSyntax? syntax) =>
      syntax?.tokens(code) ?? [(text: code, kind: CodeTokenKind.plain)];
}
