/// Annotations whose string argument is a pointcut expression.
const pointcutAnnotations = {
  'Pointcut',
  'Before',
  'After',
  'AfterReturning',
  'AfterThrowing',
  'Around',
};

/// Designators of pointcut expressions (the runtime supports `execution`,
/// `within`, `target`, `this`, `bean`, `@annotation` and `@within`; the
/// others are highlighted and reported by the check).
const _designators = {
  'execution',
  'within',
  'target',
  'this',
  'bean',
  '@annotation',
  '@within',
  'args',
  '@target',
  '@args',
};

/// What a piece of a pointcut expression is.
enum PointcutPartKind {
  /// `execution`, `within`, `@annotation`, ... and `public` in `execution`.
  designator,

  /// `&&`, `||`, `!`, `and`, `or`, `not`.
  operator,

  /// `*` and `..` in patterns.
  wildcard,

  /// A type (pattern): `within(OrderService)`, types in `execution`.
  type,

  /// An annotation type: `@annotation(Timed)`.
  annotation,

  /// A bean name pattern: `bean(order*)`.
  bean,

  /// The method name pattern of `execution(* Type.name(..))`.
  member,

  /// The declaring type pattern of `execution(* Type.name(..))`.
  declaringType,

  /// A named pointcut reference: `pricing()`, `AuditAspect.pricing()`.
  reference,

  /// The aspect of a qualified reference: `AuditAspect` in
  /// `AuditAspect.pricing()`.
  aspect,
}

/// A piece of a pointcut expression (offsets relative to the expression).
final class PointcutPart {
  /// Creates a part.
  const PointcutPart(this.kind, this.start, this.end, this.text);

  /// Kind.
  final PointcutPartKind kind;

  /// Start offset.
  final int start;

  /// End offset.
  final int end;

  /// Source text.
  final String text;

  @override
  String toString() => '${kind.name}($text)';
}

// The runtime's tokens: operators, parentheses, identifiers (optionally
// `@`-prefixed and dotted) and other runs of non-space characters.
final _tokens = RegExp(r'&&|\|\||!|\(|\)|@?[A-Za-z_$][\w$.]*|[^\s()]+');

/// Splits a pointcut expression into highlighted, navigable parts. Never
/// throws: broken expressions give the parts that can be recognised.
List<PointcutPart> scanPointcut(String source) {
  final parts = <PointcutPart>[];
  final tokens = _tokens.allMatches(source).toList();
  var i = 0;
  while (i < tokens.length) {
    final token = tokens[i];
    final text = token[0]!;
    final next = i + 1 < tokens.length ? tokens[i + 1][0] : null;
    if (text == '&&' ||
        text == '||' ||
        text == '!' ||
        (next != '(' && (text == 'and' || text == 'or' || text == 'not'))) {
      parts.add(
        PointcutPart(PointcutPartKind.operator, token.start, token.end, text),
      );
      i++;
      continue;
    }
    if (next != '(' || text == '(' || text == ')') {
      i++;
      continue;
    }
    // `name( ... )`: the body up to the matching parenthesis.
    final open = tokens[i + 1];
    var depth = 0;
    var close = i + 1;
    for (; close < tokens.length; close++) {
      final value = tokens[close][0];
      if (value == '(') {
        depth++;
      } else if (value == ')' && --depth == 0) {
        break;
      }
    }
    final bodyEnd = close < tokens.length ? tokens[close].start : source.length;
    final body = source.substring(open.end, bodyEnd);
    if (_designators.contains(text)) {
      parts.add(
        PointcutPart(PointcutPartKind.designator, token.start, token.end, text),
      );
      _designatorBody(text, body, open.end, parts);
    } else {
      final dot = text.lastIndexOf('.');
      if (dot > 0) {
        parts.add(
          PointcutPart(
            PointcutPartKind.aspect,
            token.start,
            token.start + dot,
            text.substring(0, dot),
          ),
        );
      }
      parts.add(
        PointcutPart(
          PointcutPartKind.reference,
          token.start + dot + 1,
          token.end,
          text.substring(dot + 1),
        ),
      );
    }
    i = close + 1;
  }
  return parts;
}

void _designatorBody(
  String designator,
  String body,
  int offset,
  List<PointcutPart> parts,
) {
  switch (designator) {
    case 'bean':
      final trimmed = body.trim();
      if (trimmed.isNotEmpty) {
        final start = offset + body.indexOf(trimmed);
        parts.add(
          PointcutPart(
            PointcutPartKind.bean,
            start,
            start + trimmed.length,
            trimmed,
          ),
        );
      }
    case '@annotation' || '@within' || '@target' || '@args':
      _types(body, offset, PointcutPartKind.annotation, parts);
    case 'execution':
      _execution(body, offset, parts);
    default:
      _types(body, offset, PointcutPartKind.type, parts);
  }
}

// Type names and wildcards of a type pattern (`*Service`, `Future<int>`,
// `com.x.Service`: only the last segment of a dotted name is a type).
void _types(
  String text,
  int offset,
  PointcutPartKind kind,
  List<PointcutPart> parts,
) {
  for (final word in RegExp(r'[\w$*.<>?]+').allMatches(text)) {
    final value = word[0]!;
    if (value == '..' || value == '*') {
      parts.add(
        PointcutPart(
          PointcutPartKind.wildcard,
          offset + word.start,
          offset + word.end,
          value,
        ),
      );
      continue;
    }
    // `Future<int>`: every name is a type; `com.x.Service`: the last one.
    for (final segment in value.split(RegExp('[<>,?]'))) {
      if (segment.isEmpty) {
        continue;
      }
      final segmentStart = word.start + value.indexOf(segment);
      final dot = segment.lastIndexOf('.');
      final name = segment.substring(dot + 1);
      if (name.isEmpty) {
        continue;
      }
      final start = offset + segmentStart + dot + 1;
      parts.add(
        PointcutPart(
          name.replaceAll('*', '').isEmpty ? PointcutPartKind.wildcard : kind,
          start,
          start + name.length,
          name,
        ),
      );
    }
  }
}

// `[modifiers] returnType [Type.]name(params)`.
void _execution(String body, int offset, List<PointcutPart> parts) {
  final open = body.indexOf('(');
  final head = open < 0 ? body : body.substring(0, open);
  final words = RegExp(r'\S+').allMatches(head).toList();
  var index = 0;
  while (index < words.length &&
      const {'public', 'static', 'final'}.contains(words[index][0])) {
    final word = words[index++];
    parts.add(
      PointcutPart(
        PointcutPartKind.designator,
        offset + word.start,
        offset + word.end,
        word[0]!,
      ),
    );
  }
  if (index < words.length) {
    final returnType = words[index++];
    _types(
      returnType[0]!,
      offset + returnType.start,
      PointcutPartKind.type,
      parts,
    );
  }
  if (index < words.length) {
    final qualified = words[index];
    final value = qualified[0]!;
    final dot = value.lastIndexOf('.');
    final start = offset + qualified.start;
    if (dot > 0) {
      final type = value.substring(0, dot);
      final typeDot = type.lastIndexOf('.');
      final typeName = type.substring(typeDot + 1);
      parts.add(
        PointcutPart(
          typeName.replaceAll('*', '').isEmpty
              ? PointcutPartKind.wildcard
              : PointcutPartKind.declaringType,
          start + typeDot + 1,
          start + dot,
          typeName,
        ),
      );
    }
    final name = value.substring(dot + 1);
    parts.add(
      PointcutPart(
        name.replaceAll('*', '').isEmpty
            ? PointcutPartKind.wildcard
            : PointcutPartKind.member,
        start + dot + 1,
        start + value.length,
        name,
      ),
    );
  }
  if (open >= 0) {
    final close = body.lastIndexOf(')');
    final params = body.substring(open + 1, close > open ? close : body.length);
    _types(params, offset + open + 1, PointcutPartKind.type, parts);
  }
}

/// `*` wildcard matching, like the runtime's `wildcardMatch`.
bool wildcardMatches(String pattern, String text) =>
    RegExp('^${pattern.split('*').map(RegExp.escape).join('.*')}\$')
        .hasMatch(text);
