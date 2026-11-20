/// The semantic token types the server reports, in the order of the
/// legend it announces at `initialize`: a token's type is sent as its
/// [index].
///
/// The first nine and [comment] are standard LSP types, which every theme
/// colours. [closureParameter] is the server's own, for a closure's
/// parameters where they are declared and used; it needs an editor rule to
/// get a colour. The editor rules match the [legendName]s, so a name must
/// never change and a new type goes at the end.
enum TokenType {
  /// A keyword of SpEL or SQL, and the `#{` and `}` around an expression.
  keyword('keyword'),

  /// An operator, and the `${`, `:` and `}` of a placeholder.
  operator('operator'),

  /// A number literal.
  number('number'),

  /// A string literal, and the default of a placeholder.
  string('string'),

  /// A variable: `#name` in SpEL, a bean of a pointcut, a query parameter.
  variable('variable'),

  /// A property: a placeholder's key, a member in SpEL, a column in SQL.
  property('property'),

  /// A method call or a method a pointcut names.
  method('method'),

  /// A type: `T(...)` in SpEL, a type of a pointcut.
  type('type'),

  /// A class: a bean in SpEL (`@name`), an annotation in a pointcut, a
  /// table or entity in SQL.
  classType('class'),

  /// A closure's parameter, where it is declared and where the closure's
  /// body uses it (an editor rule gives it a colour of its own).
  closureParameter('closureParameter'),

  /// A comment in the SQL of a `@Query`.
  comment('comment');

  TokenType(this.legendName);

  /// The name in the legend, which the editor's rules match.
  final String legendName;
}

/// The names of [TokenType], in the order of the legend.
final List<String> semanticTokenTypes = [
  for (final type in TokenType.values) type.legendName,
];

/// The semantic token modifiers the server reports: a token's modifiers
/// are a bit set over them, in the order of the legend it announces
/// ([semanticTokenModifiers]).
enum TokenModifier {
  /// A placeholder's key that nothing defines: no config file of the
  /// package, no test, no Spring metadata.
  unresolved,

  /// The default of a placeholder: `8080` of `${server.port:8080}`.
  defaultValue;

  /// The modifier's bit in a token's modifiers.
  int get bit => 1 << index;
}

/// The names of [TokenModifier], in the order of the legend.
final List<String> semanticTokenModifiers = [
  for (final modifier in TokenModifier.values) modifier.name,
];

/// Receives one token: the offsets [start] to [end] (in the text the
/// producer reads), its [type] and its [modifiers] bits.
typedef AddToken = void Function(
  int start,
  int end,
  TokenType type, [
  int modifiers,
]);

/// One piece of text to colour: a SpEL keyword, a placeholder key, a
/// closure parameter.
///
/// The position is absolute (zero-based line and UTF-16 column) and the
/// token stays on one line; the server sorts the tokens and turns them
/// into LSP's relative encoding.
final class SemanticToken {
  /// A token of [length] UTF-16 units at [line], [column], of [type], with
  /// [modifiers].
  const SemanticToken(
    this.line,
    this.column,
    this.length,
    this.type, {
    this.modifiers = 0,
  });

  /// The zero-based line.
  final int line;

  /// The zero-based column where the token starts, in UTF-16 units.
  final int column;

  /// The length in UTF-16 units.
  final int length;

  /// The token's type; its index in the legend is what the protocol sends.
  final TokenType type;

  /// The token's modifiers: the [TokenModifier.bit]s of those it has.
  final int modifiers;

  /// Whether it has [modifier].
  bool has(TokenModifier modifier) => modifiers & modifier.bit != 0;
}
