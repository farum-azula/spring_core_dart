import 'package:spring_core_dart/src/expression/ast.dart';
import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/spel_parser_configuration.dart';

/// Turns expression text into an [Expression] that can be evaluated.
///
/// The only implementation is `SpelExpressionParser`; create that one.
/// The interface exists so that code which takes a parser, such as
/// `StandardBeanExpressionResolver`, can be handed a configured or a
/// different one.
///
/// ```dart
/// // Parse once, keep the expression, evaluate it whenever needed.
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
  /// Parses [expressionString] into an expression.
  ///
  /// Without [context] the whole text is one expression. With a template
  /// context such as [ParserContext.template], the text outside `#{...}`
  /// is kept as it is and only the `#{...}` parts are parsed.
  ///
  /// ```dart
  /// parser.parseExpression('Hi #{name}', ParserContext.template);
  /// ```
  ///
  /// Throws a `SpelParseException` when the text is not valid SpEL, and a
  /// `ParseException` when a template is malformed (an unclosed `#{`).
  Expression parseExpression(String expressionString, [ParserContext? context]);
}

/// Tells the parser whether a text is one expression or a template of
/// literal text with embedded expressions, and which delimiters mark them.
///
/// Templates are what `@Value` uses: `'Hello #{name}!'` is mostly text,
/// with one expression inside. Pass [ParserContext.template] for the usual
/// `#{...}` delimiters, or a [TemplateParserContext] with others. Without
/// a context (or with one whose [isTemplate] is `false`) the whole string
/// is a single expression.
///
/// ```dart
/// // A greeting text from configuration, with the user's name filled in.
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
  /// Templates with `#{` and `}` around each expression (Spring's
  /// `ParserContext.TEMPLATE_EXPRESSION`).
  static const ParserContext template = TemplateParserContext();

  /// Whether the text is a template mixing literal text and expressions;
  /// when `false` the prefix and suffix are ignored.
  bool get isTemplate;

  /// The delimiter that opens an embedded expression, such as `#{`.
  String get expressionPrefix;

  /// The delimiter that closes an embedded expression, such as `}`.
  String get expressionSuffix;
}

/// A template [ParserContext] with delimiters of your choice.
///
/// Use it when the text itself contains `#{` (or when another tool already
/// owns that syntax) and the expressions must be marked differently. The
/// default delimiters are `#{` and `}`, the same as
/// [ParserContext.template].
///
/// ```dart
/// // `[[...]]` marks the expressions of this message.
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

/// A parsed expression, ready to be evaluated as often as needed.
///
/// Parsing costs more than evaluating, so parse a text once and keep the
/// expression. It holds no state of its own: the values it reads come
/// from the [EvaluationContext] and the root object given to each call,
/// so one expression can be shared and evaluated against different
/// objects.
///
/// The parser returns a [SpelExpression] for one SpEL expression, and a
/// [LiteralExpression] or [CompositeStringExpression] for a template.
///
/// ```dart
/// // A pricing rule parsed once, evaluated for each order line.
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
  /// The text the expression was parsed from (the whole template for a
  /// template).
  String get expressionString;

  /// Evaluates the expression and returns its value.
  ///
  /// Names without a prefix (`name`, `size()`) are read on [rootObject],
  /// or on the context's root object when [rootObject] is `null`. Without
  /// [context] a new `StandardEvaluationContext` is used, so variables,
  /// functions and registered types are only available when you pass a
  /// context.
  ///
  /// ```dart
  /// parser.parseExpression('name.length').getValue(null, {'name': 'Ada'});
  /// // 3
  /// ```
  ///
  /// Throws a `SpelEvaluationException` when evaluation fails. An
  /// exception thrown by a method or constructor the expression calls is
  /// rethrown as it is.
  Object? getValue([EvaluationContext? context, Object? rootObject]);

  /// Evaluates like [getValue] and returns the value as a [T].
  ///
  /// A value that already is a [T] is returned unchanged; any other value
  /// is converted with the context's `TypeConverter` (a `'42'` becomes
  /// `42` for an `int`). Use it when the caller needs a typed value, such
  /// as a `bool` for a condition.
  ///
  /// ```dart
  /// parser.parseExpression("'42'").getValueAs<int>(); // 42
  /// ```
  ///
  /// Throws a `SpelEvaluationException` (`typeConversionError`) when the
  /// value is `null` for a non-nullable [T] or cannot be converted.
  T getValueAs<T>([EvaluationContext? context, Object? rootObject]);

  /// Stores [value] in the property, variable or element the expression
  /// names, such as `user.name`, `#count` or `items[0]`.
  ///
  /// This is how data binding writes a form field addressed by a path. A
  /// `null` [rootObject] means the context's root; a `null` [context] a
  /// new `StandardEvaluationContext`.
  ///
  /// ```dart
  /// final data = {'count': 1};
  /// parser.parseExpression('count').setValue(null, data, 2);
  /// // data == {'count': 2}
  /// ```
  ///
  /// Throws a `SpelEvaluationException` (`notAssignable`) when the target
  /// is not assignable (a literal, a template) or the context disables
  /// assignment.
  void setValue(EvaluationContext? context, Object? rootObject, Object? value);

  /// Whether [setValue] would store a value: the expression names a
  /// writable property, variable or element and the context allows
  /// assignment.
  ///
  /// Returns `false` instead of throwing when the path cannot be
  /// evaluated.
  bool isWritable([EvaluationContext? context, Object? rootObject]);

  /// The runtime type of the value, or `null` when the value is `null`
  /// (`String` for a template).
  ///
  /// ```dart
  /// parser.parseExpression("'abc'.length").getValueType(); // int
  /// ```
  ///
  /// It evaluates the expression, so it throws like [getValue].
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

/// One parsed SpEL expression: the syntax tree of the text and the parser
/// options it runs under.
///
/// `SpelExpressionParser` returns one for a plain expression (and for
/// each `#{...}` part of a template). Use it through [Expression]; the
/// concrete type only matters to tools that inspect the parsed tree in
/// [ast]. Every evaluation counts operations against the limits of
/// [configuration], and an expression nested too deeply for the stack
/// fails with `maxExpressionNestingDepthExceeded` instead of a stack
/// overflow.
///
/// ```dart
/// // A tool printing how an expression was understood.
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
  /// [configuration] (the defaults when omitted). The parser calls it;
  /// applications do not.
  SpelExpression(
    this.expressionString,
    this.ast, [
    SpelParserConfiguration? configuration,
  ]) : configuration = configuration ?? SpelParserConfiguration.withDefaults();

  @override
  final String expressionString;

  /// The root node of the parsed tree; its `toString()` prints the
  /// expression as the parser read it, with parentheses (`(a + b)`).
  final SpelNode ast;

  /// The operation limit and auto-grow options every evaluation uses,
  /// taken from the parser.
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

/// An expression whose value is fixed text: a template with no `#{...}`
/// in it, or a text part of a template.
///
/// Its value is the text itself whatever the context; [getValueAs]
/// converts it with the context's type converter. It can never be
/// assigned. You get one from the parser; there is rarely a reason to
/// create one, except to pass fixed text where an [Expression] is
/// expected.
///
/// ```dart
/// // A template that turned out to contain no expression.
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

/// A template made of several parts, text and `#{...}` expressions, whose
/// value is the parts joined into one string.
///
/// The parser returns one for templates such as `'Hello #{name}!'`. Each
/// part is evaluated against the same context and root, converted to a
/// `String` with the context's type converter (a list becomes `1,2`), and
/// a `null` part adds nothing. A template that is a single `#{...}` with
/// no text around it is not composite: the parser returns that expression
/// itself, so its value keeps its type (`'#{2}'` gives the `int` 2).
///
/// ```dart
/// // A message whose numbers are computed when it is shown.
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
