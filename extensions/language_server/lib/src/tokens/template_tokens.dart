import 'package:dart_spring_language_server/src/templates.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';
import 'package:dart_spring_language_server/src/tokens/spel_tokens.dart';

/// Calls [add] with the tokens of the `${...}` placeholders and `#{...}`
/// expressions in [source], which starts at [base] in the text [add]
/// reads.
///
/// With [resolves], a placeholder's key that it does not resolve (and that
/// has no default) is marked [TokenModifier.unresolved]; a default is
/// marked [TokenModifier.defaultValue].
void templateTokens(
  String source,
  int base,
  AddToken add, {
  bool Function(String key)? resolves,
}) {
  for (final part in scanTemplate(source)) {
    if (part.kind == TemplatePartKind.placeholder) {
      _placeholder(source, base, part, add, resolves);
    } else {
      _expression(source, base, part, add);
    }
  }
}

void _placeholder(
  String source,
  int base,
  TemplatePart part,
  AddToken add,
  bool Function(String key)? resolves,
) {
  final keyEnd = part.keyEnd!;
  final hasDefault = keyEnd < part.innerEnd;
  final key = part.inner(source);
  add(base + part.start, base + part.innerStart, TokenType.operator);
  add(
    base + part.innerStart,
    base + keyEnd,
    TokenType.property,
    !hasDefault && key.isNotEmpty && resolves != null && !resolves(key)
        ? TokenModifier.unresolved.bit
        : 0,
  );
  if (hasDefault) {
    add(base + keyEnd, base + keyEnd + 1, TokenType.operator);
    final fallback = source.substring(keyEnd + 1, part.innerEnd);
    // A default with placeholders of its own: those get their tokens.
    if (!fallback.contains(r'${') && !fallback.contains('#{')) {
      add(
        base + keyEnd + 1,
        base + part.innerEnd,
        TokenType.string,
        TokenModifier.defaultValue.bit,
      );
    }
  }
  if (!part.unclosed) {
    add(base + part.innerEnd, base + part.end, TokenType.operator);
  }
}

void _expression(String source, int base, TemplatePart part, AddToken add) {
  add(base + part.start, base + part.innerStart, TokenType.keyword);
  final expression = source.substring(part.innerStart, part.innerEnd);
  // Placeholders are resolved first; tokens of the expression would be
  // wrong.
  if (!expression.contains(r'${')) {
    spelTokens(expression, base + part.innerStart, add);
  }
  if (!part.unclosed) {
    add(base + part.innerEnd, base + part.end, TokenType.keyword);
  }
}
