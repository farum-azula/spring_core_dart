/// Finds the `${key:default}` placeholders and `#{...}` SpEL expressions
/// in the text of an annotation string or a config value, with their
/// offsets, for highlighting, navigation and checks.
///
/// It reads source text, so `\${` written in a non-raw Dart string (a
/// literal `${` at run time) counts as a placeholder too.
library;

/// Whether a [TemplatePart] is a placeholder or a SpEL expression.
enum TemplatePartKind {
  /// `${key}` or `${key:default}`: a property, looked up by key.
  placeholder,

  /// `#{expression}`: SpEL, evaluated at run time.
  expression,
}

/// One placeholder or expression found by [scanTemplate], with offsets
/// relative to the scanned text.
///
/// An unclosed one (no `}`) runs to the end of the text, so the editor
/// can still colour it and report the missing brace.
final class TemplatePart {
  /// A part of [kind] from [start] to [end], whose content lies between
  /// [innerStart] and [innerEnd].
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

  /// The offset of the opening `$` or `#` (of the backslash, for `\${`).
  final int start;

  /// The offset after the closing `}`, or the end of the text when unclosed.
  final int end;

  /// The offset after `${` or `#{`.
  final int innerStart;

  /// The offset of the closing `}`, or the end of the text when unclosed.
  final int innerEnd;

  /// For a placeholder, where the key ends: the offset of the `:` before a
  /// default, or [innerEnd] without one. `null` for an expression.
  final int? keyEnd;

  /// Whether the closing `}` is missing.
  bool get unclosed => end == innerEnd;

  /// The placeholder's key or the expression's source, trimmed, taken from
  /// [text], the text that was scanned.
  String inner(String text) =>
      text.substring(innerStart, keyEnd ?? innerEnd).trim();

  @override
  String toString() => '$kind($start..$end)';
}

/// The placeholders and expressions of [text], outermost first.
///
/// Placeholders in a default (`${a:${b}}`) are returned too, after the
/// outer one. Inside an expression, braces in SpEL string literals do not
/// count, and `''` is an escaped quote.
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
