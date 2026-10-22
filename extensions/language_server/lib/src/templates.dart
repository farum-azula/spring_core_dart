/// Placeholders (`${key:default}`) and SpEL expressions (`#{...}`) inside
/// the source text of an annotation string.
library;

/// What a [TemplatePart] is.
enum TemplatePartKind {
  /// `${key}` or `${key:default}`.
  placeholder,

  /// `#{expression}`.
  expression,
}

/// One placeholder or expression; offsets are relative to the scanned text.
final class TemplatePart {
  /// Creates a part.
  const TemplatePart(
    this.kind,
    this.start,
    this.end,
    this.innerStart,
    this.innerEnd, {
    this.keyEnd,
  });

  /// Placeholder or expression.
  final TemplatePartKind kind;

  /// Offset of `$` / `#`.
  final int start;

  /// Offset after the closing `}` (or the end of the text if unclosed).
  final int end;

  /// Offset after `${` / `#{`.
  final int innerStart;

  /// Offset of the closing `}`.
  final int innerEnd;

  /// For placeholders: the end of the key (before `:default`).
  final int? keyEnd;

  /// Whether the closing `}` is missing.
  bool get unclosed => end == innerEnd;

  /// The placeholder key or the expression text.
  String inner(String text) =>
      text.substring(innerStart, keyEnd ?? innerEnd).trim();

  @override
  String toString() => '$kind($start..$end)';
}

/// The placeholders and expressions of [text], outermost first; nested
/// placeholders in defaults (`${a:${b}}`) are returned too.
List<TemplatePart> scanTemplate(String text) {
  final parts = <TemplatePart>[];
  _scan(text, 0, text.length, parts);
  return parts;
}

void _scan(String text, int from, int to, List<TemplatePart> parts) {
  var i = from;
  while (i < to - 1) {
    final c = text[i];
    // `\$` in a non-raw Dart string is a literal dollar sign.
    if (c == r'\' && text[i + 1] == r'$') {
      final start = i;
      i++;
      if (i + 1 < to && text[i + 1] == '{') {
        i = _placeholder(text, start, i + 2, to, parts);
        continue;
      }
    }
    if (c == r'$' && text[i + 1] == '{') {
      i = _placeholder(text, i, i + 2, to, parts);
      continue;
    }
    if (c == '#' && text[i + 1] == '{') {
      i = _expression(text, i, i + 2, to, parts);
      continue;
    }
    i++;
  }
}

int _placeholder(
  String text,
  int start,
  int inner,
  int to,
  List<TemplatePart> parts,
) {
  var depth = 1;
  int? keyEnd;
  var i = inner;
  while (i < to) {
    final c = text[i];
    if ((c == r'$' || c == '#') && i + 1 < to && text[i + 1] == '{') {
      depth++;
      i += 2;
      continue;
    }
    if (c == ':' && depth == 1 && keyEnd == null) {
      keyEnd = i;
    } else if (c == '}') {
      depth--;
      if (depth == 0) {
        parts.add(
          TemplatePart(
            TemplatePartKind.placeholder,
            start,
            i + 1,
            inner,
            i,
            keyEnd: keyEnd ?? i,
          ),
        );
        if (keyEnd != null) {
          _scan(text, keyEnd + 1, i, parts); // placeholders in the default
        }
        return i + 1;
      }
    }
    i++;
  }
  parts.add(
    TemplatePart(
      TemplatePartKind.placeholder,
      start,
      to,
      inner,
      to,
      keyEnd: keyEnd ?? to,
    ),
  );
  return to;
}

int _expression(
  String text,
  int start,
  int inner,
  int to,
  List<TemplatePart> parts,
) {
  var depth = 1;
  String? quote;
  var i = inner;
  while (i < to) {
    final c = text[i];
    if (quote != null) {
      if (c == quote) {
        // '' inside a SpEL string is an escaped quote.
        if (i + 1 < to && text[i + 1] == quote) {
          i += 2;
          continue;
        }
        quote = null;
      }
    } else if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) {
        parts.add(
          TemplatePart(TemplatePartKind.expression, start, i + 1, inner, i),
        );
        return i + 1;
      }
    }
    i++;
  }
  parts.add(TemplatePart(TemplatePartKind.expression, start, to, inner, to));
  return to;
}
