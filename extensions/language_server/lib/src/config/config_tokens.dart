import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';
import 'package:dart_spring_language_server/src/tokens/template_tokens.dart';

/// The semantic tokens of a config file: the placeholders and SpEL of its
/// values, line by line, comments left out (`#` / `!` lines of
/// `.properties`, `#` after a space in YAML).
List<SemanticToken> configTokens(ConfigDocument document) {
  final tokens = <SemanticToken>[];
  final lines = document.lines;
  for (var row = 0; row < lines.length; row++) {
    final content = document.format.content(lines[row]);
    if (!content.contains(r'${') && !content.contains('#{')) {
      continue;
    }
    templateTokens(content, 0, (start, end, type, [modifiers = 0]) {
      if (end > start) {
        tokens.add(
          SemanticToken(row, start, end - start, type, modifiers: modifiers),
        );
      }
    });
  }
  return tokens;
}
