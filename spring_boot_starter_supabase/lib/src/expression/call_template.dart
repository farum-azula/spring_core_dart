import 'package:spring_security_core/spring_security_core.dart';

/// How the values of a [CallTemplate] (what a `{parameter}` or a `#{...}`
/// gives at a call) and its fixed text go into the result.
///
/// A value is data, never structure: an encoder refuses what would change
/// the meaning of the text around it.
abstract interface class TemplateEncoder {
  /// The fixed text [text] of the template, as it goes into the result.
  /// Called once, when the template is read; throws an [ArgumentError]
  /// for text the template may not have.
  String literal(String text);

  /// The [value] an [expression] of the template gave, as it goes into
  /// the result. Throws an [ArgumentError] for a value it refuses.
  String value(Object? value, String expression);
}

/// Values as single segments of a path: a value cannot add a `/`, be `.`
/// or `..`, be empty or carry a control character, and is percent-encoded.
/// So a call never leaves the folder its template names.
///
/// ```dart
/// // '{userId}/avatar.png' with userId = '../admin' is refused.
/// ```
final class PathSegmentEncoder implements TemplateEncoder {
  /// The encoder; with [encode] false it only checks, for a path that is
  /// percent-encoded later.
  const PathSegmentEncoder({this.encode = true});

  /// Whether the segments are percent-encoded here.
  final bool encode;

  @override
  String literal(String text) => [
    for (final segment in text.split('/'))
      if (segment == '.' || segment == '..')
        throw ArgumentError.value(text, 'path', 'has a "$segment" segment')
      else if (encode)
        Uri.encodeComponent(segment)
      else
        segment,
  ].join('/');

  @override
  String value(Object? value, String expression) {
    final text = switch (value) {
      null => '',
      final Enum value => value.name,
      _ => '$value',
    };
    if (text.isEmpty) {
      throw ArgumentError('$expression gave no value for a path segment');
    }
    if (text == '.' ||
        text == '..' ||
        text.contains('/') ||
        text.contains(r'\') ||
        text.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw ArgumentError(
        '$expression gave a value that is not one path segment '
        '(a "/", "..", "." or a control character)',
      );
    }
    return encode ? Uri.encodeComponent(text) : text;
  }
}

/// Values as parts of a name (a Realtime topic, a function's name):
/// anything but an empty value or a control character, as it is.
final class NameEncoder implements TemplateEncoder {
  /// The encoder.
  const NameEncoder();

  @override
  String literal(String text) => text;

  @override
  String value(Object? value, String expression) {
    final text = switch (value) {
      null => '',
      final Enum value => value.name,
      _ => '$value',
    };
    if (text.isEmpty) {
      throw ArgumentError('$expression gave no value');
    }
    if (text.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw ArgumentError('$expression gave a value with a control character');
    }
    return text;
  }
}

/// A text of a declared interface's annotation (a Storage path, a Realtime
/// topic, a function's name), read once and filled at each call:
///
/// - `${property}` is replaced from the configuration when it is read;
/// - `{name}` is the method's parameter `name`;
/// - `#{...}` is SpEL, with the parameters as `#name`, `authentication`
///   and `principal` as in `@PreAuthorize`, and beans as `@name`.
///
/// ```dart
/// @Upload('#{authentication.name}/avatar.png')
/// Future<void> put(Uint8List bytes);
///
/// @Download('{userId}/{kind}.png')
/// Stream<List<int>> get(String userId, AvatarKind kind);
/// ```
///
/// Made by [CallTemplates.parse].
final class CallTemplate {
  CallTemplate._(this.text, this._parts, this._templates);

  /// The annotation's text, as written.
  final String text;

  final List<_Part> _parts;
  final CallTemplates _templates;

  /// Whether the text has neither `{name}` nor `#{...}`: every call gives
  /// the same result.
  bool get isConstant => _parts.every((part) => part is _Literal);

  /// The names of the parameters the text uses as `{name}`.
  Iterable<String> get parameters =>
      _parts.whereType<_Parameter>().map((part) => part.name);

  /// The text for a call of [method] with [arguments].
  ///
  /// Throws an [ArgumentError] when a value is refused by the encoder or
  /// an expression cannot be evaluated.
  String expand(ProxyMethod method, List<Object?> arguments) {
    StandardEvaluationContext? context;
    final buffer = StringBuffer();
    for (final part in _parts) {
      switch (part) {
        case _Literal(:final text):
          buffer.write(text);
        case _Parameter(:final name, :final index, :final encoder):
          buffer.write(encoder.value(arguments[index], '{$name}'));
        case _Expression(:final source, :final expression, :final encoder):
          context ??= _templates._context(method, arguments);
          final Object? value;
          try {
            value = expression.getValue(context);
          } on ExpressionException catch (error) {
            throw ArgumentError(
              '#{$source} of "$text" could not be evaluated: '
              '${error.message}',
            );
          }
          buffer.write(encoder.value(value, '#{$source}'));
      }
    }
    return buffer.toString();
  }

  @override
  String toString() => text;
}

sealed class _Part {}

final class _Literal extends _Part {
  _Literal(this.text);
  final String text;
}

final class _Parameter extends _Part {
  _Parameter(this.name, this.index, this.encoder);
  final String name;
  final int index;
  final TemplateEncoder encoder;
}

final class _Expression extends _Part {
  _Expression(this.source, this.expression, this.encoder);
  final String source;
  final Expression expression;
  final TemplateEncoder encoder;
}

/// Reads the texts of the declared interfaces (the bean `callTemplates`):
/// see [CallTemplate].
final class CallTemplates {
  /// Templates resolving `${...}` from [environment], `@name` from
  /// [beanFactory], and `authentication` / `principal` / `hasRole(...)`
  /// through [security] (Spring Security's own expression support, when
  /// the application has it).
  CallTemplates({
    required this.environment,
    this.beanFactory,
    this.introspector,
    MethodSecurityExpressionHandler? security,
  }) : security =
           security ??
           MethodSecurityExpressionHandler(
             introspector: introspector,
             beanFactory: beanFactory,
           );

  /// Where `${...}` is resolved.
  final Environment environment;

  /// Where `@name` is resolved; none without it.
  final BeanFactory? beanFactory;

  /// How the properties of the application's own classes are read
  /// (`#user.id`).
  final BeanIntrospector? introspector;

  /// What gives the expressions `authentication`, `principal` and the
  /// functions of `@PreAuthorize`.
  final MethodSecurityExpressionHandler security;

  final _parser = SpelExpressionParser();

  /// Reads [text], an annotation's text on [method]; values go through
  /// [encoder].
  ///
  /// Throws an [ArgumentError] naming what is wrong: a `{name}` that is no
  /// parameter of the method, an unclosed `{`, an expression that does not
  /// parse, a property that is not set, fixed text the encoder refuses.
  CallTemplate parse(
    String text, {
    required ProxyMethod method,
    required TemplateEncoder encoder,
  }) {
    final String resolved;
    try {
      resolved = environment.resolveRequiredPlaceholders(text);
    } on Object catch (error) {
      throw ArgumentError('"$text": $error');
    }
    final names = [for (final parameter in method.parameters) parameter.name];
    final parts = <_Part>[];
    final literal = StringBuffer();
    void flush() {
      if (literal.isNotEmpty) {
        parts.add(_Literal(encoder.literal('$literal')));
        literal.clear();
      }
    }

    var index = 0;
    while (index < resolved.length) {
      final char = resolved[index];
      if (char == '#' &&
          index + 1 < resolved.length &&
          resolved[index + 1] == '{') {
        final end = _expressionEnd(resolved, index + 2);
        if (end < 0) {
          throw ArgumentError('"$text": the #{ at $index is never closed');
        }
        final source = resolved.substring(index + 2, end).trim();
        final Expression expression;
        try {
          expression = _parser.parseExpression(source);
        } on ExpressionException catch (error) {
          throw ArgumentError(
            '"$text": #{$source} is not an expression: ${error.message}',
          );
        }
        flush();
        parts.add(_Expression(source, expression, encoder));
        index = end + 1;
      } else if (char == '{') {
        final end = resolved.indexOf('}', index);
        if (end < 0) {
          throw ArgumentError('"$text": the { at $index is never closed');
        }
        final name = resolved.substring(index + 1, end).trim();
        final parameter = names.indexOf(name);
        if (parameter < 0) {
          throw ArgumentError(
            '"$text": {$name} is not a parameter of ${method.name}'
            '(${names.join(', ')})',
          );
        }
        flush();
        parts.add(_Parameter(name, parameter, encoder));
        index = end + 1;
      } else {
        literal.write(char);
        index++;
      }
    }
    flush();
    return CallTemplate._(text, List.unmodifiable(parts), this);
  }

  // The index of the `}` that closes an expression starting at [start]:
  // braces inside it (inline lists and maps) are counted, quoted text is
  // skipped.
  static int _expressionEnd(String text, int start) {
    var depth = 0;
    String? quote;
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        }
      } else if (char == "'" || char == '"') {
        quote = char;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        if (depth == 0) {
          return index;
        }
        depth--;
      }
    }
    return -1;
  }

  StandardEvaluationContext _context(
    ProxyMethod method,
    List<Object?> arguments,
  ) => security.createEvaluationContext(
    security.createRoot(
      () => SecurityContextHolder.getContext().authentication,
    ),
    MethodSignature(
      name: method.name,
      declaringType: 'Object',
      targetType: 'Object',
      parameterNames: [
        for (final parameter in method.parameters) parameter.name,
      ],
    ),
    arguments,
  );
}
