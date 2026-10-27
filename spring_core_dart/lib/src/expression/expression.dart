import 'package:spring_core_dart/src/expression/ast.dart';
import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/spel_parser_configuration.dart';

/// Parses expression strings, like Spring's `ExpressionParser`.
///
/// The standard implementation is `SpelExpressionParser`. Program against
/// this interface when the parser should be replaceable (e.g. in
/// `StandardBeanExpressionResolver`).
///
/// ```dart
/// ExpressionParser parser = SpelExpressionParser();
/// final expression = parser.parseExpression('1 + 2');
/// expression.getValue(); // 3
/// ```
///
/// Spring (Java):
/// ```java
/// ExpressionParser parser = new SpelExpressionParser();
/// Expression expression = parser.parseExpression("1 + 2");
/// Integer value = expression.getValue(Integer.class); // 3
/// ```
abstract interface class ExpressionParser {
  /// Parses [expressionString]; with a template [context], literal text
  /// and `#{...}` parts are combined.
  ///
  /// ```dart
  /// parser.parseExpression('Hi #{name}', ParserContext.template);
  /// ```
  ///
  /// Throws a `SpelParseException` when the text is not valid SpEL.
  Expression parseExpression(String expressionString, [ParserContext? context]);
}

/// How to parse: plain or as a template, like Spring's `ParserContext`.
///
/// Without a context (or with a non-template one) the whole string is one
/// expression. With [ParserContext.template], text outside `#{...}` is
/// kept literally.
///
/// ```dart
/// final greeting = SpelExpressionParser()
///     .parseExpression('Hello #{name}!', ParserContext.template)
///     .getValue(StandardEvaluationContext({'name': 'Ada'}));
/// // 'Hello Ada!'
/// ```
///
/// Spring (Java):
/// ```java
/// String greeting = parser
///     .parseExpression("Hello #{name}!", ParserContext.TEMPLATE_EXPRESSION)
///     .getValue(context, String.class);
/// ```
abstract interface class ParserContext {
  /// `#{` ... `}` templates (Spring's
  /// `ParserContext.TEMPLATE_EXPRESSION`).
  static const ParserContext template = TemplateParserContext();

  /// Whether the text is a template mixing literal text and expressions.
  bool get isTemplate;

  /// The delimiter that opens an embedded expression, e.g. `#{`.
  String get expressionPrefix;

  /// The delimiter that closes an embedded expression, e.g. `}`.
  String get expressionSuffix;
}

/// Template parsing with configurable delimiters, like Spring's
/// `TemplateParserContext`.
///
/// ```dart
/// final expression = SpelExpressionParser().parseExpression(
///   '[[n]] items',
///   const TemplateParserContext('[[', ']]'),
/// );
/// expression.getValue(StandardEvaluationContext({'n': 3})); // '3 items'
/// ```
///
/// Spring (Java):
/// ```java
/// Expression expression = parser.parseExpression(
///     "[[n]] items", new TemplateParserContext("[[", "]]"));
/// ```
final class TemplateParserContext implements ParserContext {
  /// Creates a template context with [expressionPrefix] and
  /// [expressionSuffix], `#{` and `}` by default.
  const TemplateParserContext([
    this.expressionPrefix = '#{',
    this.expressionSuffix = '}',
  ]);

  @override
  bool get isTemplate => true;

  @override
  final String expressionPrefix;

  @override
  final String expressionSuffix;
}

/// A parsed expression, like Spring's `Expression`. Parse once, evaluate
/// many times.
///
/// Implementations: [SpelExpression] (one SpEL expression),
/// [LiteralExpression] and [CompositeStringExpression] (templates).
/// Expressions are immutable and can be shared; per-evaluation state lives
/// in the [EvaluationContext].
///
/// ```dart
/// final expression = SpelExpressionParser().parseExpression('qty * 2');
/// expression.getValue(StandardEvaluationContext({'qty': 3})); // 6
/// expression.getValueAs<String>(null, {'qty': 4}); // '8'
/// ```
///
/// Spring (Java):
/// ```java
/// Expression expression = parser.parseExpression("qty * 2");
/// Integer six = expression.getValue(context, Integer.class);
/// String eight = expression.getValue(rootObject, String.class);
/// ```
abstract interface class Expression {
  /// The original expression text.
  String get expressionString;

  /// Evaluates against [context] (a fresh `StandardEvaluationContext` when
  /// omitted); [rootObject] overrides the context's root.
  ///
  /// A `null` [rootObject] means "use the context's root".
  ///
  /// ```dart
  /// parser.parseExpression('name.length').getValue(null, {'name': 'Ada'});
  /// // 3
  /// ```
  ///
  /// Throws a `SpelEvaluationException` when evaluation fails.
  Object? getValue([EvaluationContext? context, Object? rootObject]);

  /// Like [getValue], converted to [T] with the context's type converter.
  ///
  /// ```dart
  /// parser.parseExpression("'42'").getValueAs<int>(); // 42
  /// ```
  ///
  /// Throws a `SpelEvaluationException` (`typeConversionError`) when the
  /// value is `null` for a non-nullable [T] or cannot be converted.
  T getValueAs<T>([EvaluationContext? context, Object? rootObject]);

  /// Assigns [value] to the property, variable or element the expression
  /// denotes.
  ///
  /// ```dart
  /// final data = {'count': 1};
  /// parser.parseExpression('count').setValue(null, data, 2);
  /// // data == {'count': 2}
  /// ```
  ///
  /// Throws a `SpelEvaluationException` (`notAssignable`) when the target
  /// is not assignable or the context disables assignment.
  void setValue(EvaluationContext? context, Object? rootObject, Object? value);

  /// Whether [setValue] would succeed for this expression and context.
  bool isWritable([EvaluationContext? context, Object? rootObject]);

  /// The type of the value the expression evaluates to (`null` for a
  /// `null` value), like Spring's `getValueType`.
  ///
  /// ```dart
  /// parser.parseExpression("'abc'.length").getValueType(); // int
  /// ```
  ///
  /// Evaluates the expression; throws like [getValue].
  Type? getValueType([EvaluationContext? context, Object? rootObject]);
}

// Returns value unchanged when it already is a T; otherwise converts it
// with the context's TypeConverter (null is never converted).
T _convert<T>(Object? value, EvaluationContext context, String expression) {
  if (value is T) {
    return value;
  }
  final Object? converted;
  try {
    converted = value == null
        ? null
        : context.typeConverter.convertValue(value, T);
  } on SpelEvaluationException catch (error) {
    throw SpelEvaluationException(
      error.messageCode,
      inserts: error.inserts,
      cause: error.cause,
      expressionString: expression,
    );
  }
  if (converted is T) {
    return converted;
  }
  throw SpelEvaluationException(
    SpelMessage.typeConversionError,
    inserts: [if (value == null) 'null' else value.runtimeType, T],
    expressionString: expression,
  );
}

/// A compiled SpEL expression, like Spring's `SpelExpression`.
///
/// Created by `SpelExpressionParser.parseExpression`; holds the parsed
/// tree in [ast] and the parser's [configuration] (limits, auto-grow).
///
/// ```dart
/// final expression = SpelExpressionParser().parseExpression('a + b');
/// expression is SpelExpression; // true
/// expression.getValue(StandardEvaluationContext({'a': 1, 'b': 2})); // 3
/// ```
///
/// Spring (Java):
/// ```java
/// SpelExpression expression =
///     (SpelExpression) parser.parseExpression("a + b");
/// SpelNode ast = expression.getAST();
/// ```
final class SpelExpression implements Expression {
  /// Wraps the parsed [ast] of [expressionString], evaluated under
  /// [configuration] (the defaults when omitted).
  SpelExpression(
    this.expressionString,
    this.ast, [
    SpelParserConfiguration? configuration,
  ]) : configuration = configuration ?? SpelParserConfiguration.withDefaults();

  @override
  final String expressionString;

  /// The root node of the parsed tree.
  final SpelNode ast;

  /// The limits and auto-grow options of evaluations.
  final SpelParserConfiguration configuration;

  // A fresh StandardEvaluationContext when none is given; an explicit root
  // replaces the context's root object for this evaluation only.
  ExpressionState _state(EvaluationContext? context, Object? root) {
    final effective = context ?? StandardEvaluationContext();
    return ExpressionState(
      effective,
      root ?? effective.rootObject,
      expressionString,
      configuration,
    );
  }

  // Evaluates [body], turning a stack overflow (an expression nested more
  // deeply than the stack allows) into a SpEL error.
  T _run<T>(ExpressionState state, T Function() body) {
    try {
      return body();
    } on StackOverflowError {
      throw SpelEvaluationException(
        SpelMessage.maxExpressionNestingDepthExceeded,
        inserts: [configuration.maximumNestingDepth],
        expressionString: expressionString,
        position: 0,
      );
    }
  }

  @override
  Object? getValue([EvaluationContext? context, Object? rootObject]) {
    final state = _state(context, rootObject);
    return _run(state, () => ast.getValue(state));
  }

  @override
  T getValueAs<T>([EvaluationContext? context, Object? rootObject]) {
    final state = _state(context, rootObject);
    return _convert<T>(
      _run(state, () => ast.getValue(state)),
      state.context,
      expressionString,
    );
  }

  @override
  Type? getValueType([EvaluationContext? context, Object? rootObject]) =>
      getValue(context, rootObject)?.runtimeType;

  @override
  void setValue(EvaluationContext? context, Object? rootObject, Object? value) {
    final state = _state(context, rootObject);
    if (!state.context.isAssignmentEnabled) {
      throw SpelEvaluationException(
        SpelMessage.notAssignable,
        inserts: [expressionString],
        expressionString: expressionString,
      );
    }
    _run(state, () => ast.assign(state, () => value));
  }

  @override
  bool isWritable([EvaluationContext? context, Object? rootObject]) {
    final state = _state(context, rootObject);
    if (!state.context.isAssignmentEnabled || !ast.isAssignable) {
      return false;
    }
    try {
      return _run(state, () => ast.getValueRef(state).isWritable);
    } on SpelEvaluationException {
      return false;
    }
  }

  @override
  String toString() => expressionString;
}

/// Plain text from a template without expressions, like Spring's
/// `LiteralExpression`.
///
/// Its value is the text itself; it is never writable.
///
/// ```dart
/// final literal = SpelExpressionParser()
///     .parseExpression('plain text', ParserContext.template);
/// literal is LiteralExpression; // true
/// literal.getValue(); // 'plain text'
/// ```
///
/// Spring (Java):
/// ```java
/// Expression literal = parser.parseExpression(
///     "plain text", ParserContext.TEMPLATE_EXPRESSION);
/// // literal instanceof LiteralExpression
/// ```
final class LiteralExpression implements Expression {
  /// Creates an expression whose value is [expressionString].
  LiteralExpression(this.expressionString);

  @override
  final String expressionString;

  @override
  Object? getValue([EvaluationContext? context, Object? rootObject]) =>
      expressionString;

  @override
  T getValueAs<T>([EvaluationContext? context, Object? rootObject]) =>
      _convert<T>(
        expressionString,
        context ?? StandardEvaluationContext(),
        expressionString,
      );

  @override
  Type? getValueType([EvaluationContext? context, Object? rootObject]) =>
      String;

  @override
  void setValue(
    EvaluationContext? context,
    Object? rootObject,
    Object? value,
  ) => throw SpelEvaluationException(
    SpelMessage.notAssignable,
    inserts: [expressionString],
    expressionString: expressionString,
  );

  @override
  bool isWritable([EvaluationContext? context, Object? rootObject]) => false;

  @override
  String toString() => expressionString;
}

/// Literal text and expressions concatenated as a string, like Spring's
/// `CompositeStringExpression`.
///
/// Each part is evaluated and converted to a `String` with the context's
/// type converter (a list becomes `1,2`); `null` parts are skipped. A
/// template with a single `#{...}` and no text is not composite and keeps
/// the value's type.
///
/// ```dart
/// final expression = SpelExpressionParser()
///     .parseExpression('#{a} + #{b} = #{a + b}', ParserContext.template);
/// expression.getValue(StandardEvaluationContext({'a': 1, 'b': 2}));
/// // '1 + 2 = 3'
/// ```
///
/// Spring (Java):
/// ```java
/// Expression expression = parser.parseExpression(
///     "#{a} + #{b} = #{a + b}", ParserContext.TEMPLATE_EXPRESSION);
/// String text = expression.getValue(context, String.class);
/// ```
final class CompositeStringExpression implements Expression {
  /// Combines [parts] parsed from the template [expressionString].
  CompositeStringExpression(this.expressionString, List<Expression> parts)
    : parts = List.unmodifiable(parts);

  @override
  final String expressionString;

  /// The literal and SpEL parts, in template order (unmodifiable).
  final List<Expression> parts;

  @override
  Object? getValue([EvaluationContext? context, Object? rootObject]) {
    final effective = context ?? StandardEvaluationContext();
    final buffer = StringBuffer();
    for (final part in parts) {
      final value = part.getValue(effective, rootObject);
      if (value != null) {
        buffer.write(_convert<String>(value, effective, expressionString));
      }
    }
    return buffer.toString();
  }

  @override
  T getValueAs<T>([EvaluationContext? context, Object? rootObject]) {
    final effective = context ?? StandardEvaluationContext();
    return _convert<T>(
      getValue(effective, rootObject),
      effective,
      expressionString,
    );
  }

  @override
  Type? getValueType([EvaluationContext? context, Object? rootObject]) =>
      String;

  @override
  void setValue(
    EvaluationContext? context,
    Object? rootObject,
    Object? value,
  ) => throw SpelEvaluationException(
    SpelMessage.notAssignable,
    inserts: [expressionString],
    expressionString: expressionString,
  );

  @override
  bool isWritable([EvaluationContext? context, Object? rootObject]) => false;

  @override
  String toString() => expressionString;
}
