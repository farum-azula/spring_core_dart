/// Error codes of SpEL failures, like Spring's `SpelMessage`.
///
/// Every [SpelParseException] and [SpelEvaluationException] carries one of
/// these codes, so callers can react to a specific failure without parsing
/// the message text.
///
/// ```dart
/// try {
///   SpelExpressionParser().parseExpression('1 / 0').getValue();
/// } on SpelEvaluationException catch (e) {
///   print(e.code); // SpelMessage.divisionByZero
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   parser.parseExpression("@missing").getValue(context);
/// } catch (SpelEvaluationException ex) {
///   SpelMessage code = ex.getMessageCode();
/// }
/// ```
enum SpelMessage {
  /// The parser found a token it did not expect (Spring:
  /// `NOT_EXPECTED_TOKEN`).
  unexpectedToken,

  /// The expression ended too early, e.g. `1 +` (Spring: `OOD`).
  unexpectedEndOfExpression,

  /// A string literal has no closing quote (Spring:
  /// `NON_TERMINATING_QUOTED_STRING`).
  unterminatedString,

  /// A numeric literal is malformed or too large (Spring:
  /// `NOT_AN_INTEGER`, `NOT_A_LONG`).
  invalidNumber,

  /// A template expression or bracket is not closed, e.g. `#{1 + 2`
  /// (Spring raises a `ParseException` from its template parser).
  missingCloseBracket,

  /// A character that is not part of the SpEL syntax, e.g. a single `|`
  /// (Spring: `MISSING_CHARACTER`).
  unexpectedData,

  /// The target cannot be assigned, or assignment is disabled (Spring:
  /// `NOT_ASSIGNABLE`).
  notAssignable,

  /// No property accessor can read the property (Spring:
  /// `PROPERTY_OR_FIELD_NOT_READABLE`).
  propertyNotReadable,

  /// No property accessor can write the property (Spring:
  /// `PROPERTY_OR_FIELD_NOT_WRITABLE`).
  propertyNotWritable,

  /// No method resolver handles the call, or the method failed (Spring:
  /// `METHOD_NOT_FOUND`).
  methodNotFound,

  /// A method was called on `null` without `?.` (Spring:
  /// `METHOD_CALL_ON_NULL_OBJECT_NOT_ALLOWED`).
  methodOnNull,

  /// A property was read on `null` without `?.` (Spring:
  /// `PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL`).
  propertyOnNull,

  /// An index is past the end of a list or string (Spring:
  /// `COLLECTION_INDEX_OUT_OF_BOUNDS`).
  indexOutOfBounds,

  /// An index is negative, not a number, or the target cannot be indexed
  /// (Spring: `INDEXING_NOT_SUPPORTED_FOR_TYPE`).
  invalidIndex,

  /// `T(Name)` names a type that is not registered (Spring:
  /// `TYPE_NOT_FOUND`).
  typeNotFound,

  /// `new Name(...)` has no matching constructor (Spring:
  /// `CONSTRUCTOR_NOT_FOUND`).
  constructorNotFound,

  /// `#name(...)` refers to a variable that is not a function (Spring:
  /// `FUNCTION_REFERENCE_CANNOT_BE_INVOKED`).
  variableNotFunction,

  /// `#name(...)` is not registered or cannot take the arguments (Spring:
  /// `FUNCTION_NOT_DEFINED`).
  functionNotFound,

  /// `@bean` was used but the context has no bean resolver (Spring:
  /// `NO_BEAN_RESOLVER_REGISTERED`).
  beanResolverNotRegistered,

  /// The bean resolver failed to resolve `@bean` (Spring:
  /// `EXCEPTION_DURING_BEAN_RESOLUTION`).
  beanNotFound,

  /// An operator does not support the operand types (Spring:
  /// `OPERATOR_NOT_SUPPORTED_BETWEEN_TYPES`).
  operatorNotSupported,

  /// Integer division or modulus by zero (Java throws
  /// `ArithmeticException`).
  divisionByZero,

  /// A value cannot be converted to the requested type (Spring:
  /// `TYPE_CONVERSION_ERROR`).
  typeConversionError,

  /// A condition did not evaluate to a boolean (Spring reports a
  /// `TYPE_CONVERSION_ERROR` to `boolean`).
  notBoolean,

  /// Two values cannot be ordered (Spring: `NOT_COMPARABLE`).
  notComparable,

  /// `matches` got a non-string operand or an invalid pattern (Spring:
  /// `INVALID_PATTERN`).
  invalidRegex,

  /// The right side of `between` is not a two-element list (Spring:
  /// `BETWEEN_RIGHT_OPERAND_MUST_BE_TWO_ELEMENT_LIST`).
  betweenRightOperandMustBeTwoElementList,

  /// `.![...]` was applied to something that is not a collection or map
  /// (Spring: `PROJECTION_NOT_SUPPORTED_ON_TYPE`).
  projectionNotSupported,

  /// `.?[...]` was applied to something that is not a collection or map
  /// (Spring: `INVALID_TYPE_FOR_SELECTION`).
  selectionNotSupported,

  /// A feature (types, constructors) is disabled in a
  /// `SimpleEvaluationContext`.
  notSupportedInSimpleContext,

  /// A resolved method threw (Spring: `EXCEPTION_DURING_METHOD_INVOCATION`).
  exceptionDuringMethodInvocation,

  /// A registered function threw (Spring: `EXCEPTION_DURING_FUNCTION_CALL`).
  exceptionDuringFunctionCall,

  /// A registered constructor threw (Spring:
  /// `CONSTRUCTOR_INVOCATION_PROBLEM`).
  constructorInvocationProblem,

  /// A property accessor threw while reading (Spring:
  /// `EXCEPTION_DURING_PROPERTY_READ`).
  exceptionDuringPropertyRead,

  /// A property accessor threw while writing (Spring:
  /// `EXCEPTION_DURING_PROPERTY_WRITE`).
  exceptionDuringPropertyWrite,

  /// `'text' * n` would repeat more than
  /// [SpelLimits.maxRepeatedTextSize] characters (Spring:
  /// `MAX_REPEATED_TEXT_SIZE_EXCEEDED`).
  maxRepeatedTextSizeExceeded,

  /// `'text' * n` with a negative `n` (Spring:
  /// `NEGATIVE_REPEATED_TEXT_COUNT`).
  negativeRepeatedTextCount,

  /// A `matches` pattern is longer than [SpelLimits.maxRegexLength]
  /// (Spring: `MAX_REGEX_LENGTH_EXCEEDED`).
  maxRegexLengthExceeded,

  /// String concatenation would exceed
  /// [SpelLimits.maxConcatenatedStringLength] characters (Spring:
  /// `MAX_CONCATENATED_STRING_LENGTH_EXCEEDED`).
  maxConcatenatedStringLengthExceeded,
}

/// Limits that keep untrusted expressions from exhausting memory, with
/// Spring's values.
///
/// ```dart
/// parser.parseExpression("'ab' * 200").getValue();
/// // SpelEvaluationException: maxRepeatedTextSizeExceeded (400 > 256)
/// ```
///
/// Spring (Java):
/// ```java
/// // OpMultiply.MAX_REPEATED_TEXT_SIZE, OperatorMatches.MAX_REGEX_LENGTH,
/// // OpPlus.MAX_CONCATENATED_STRING_LENGTH
/// ```
abstract final class SpelLimits {
  /// Maximum length of a string built by `'text' * n`.
  static const maxRepeatedTextSize = 256;

  /// Maximum length of a `matches` pattern.
  static const maxRegexLength = 1000;

  /// Maximum length of a string built by `+`.
  static const maxConcatenatedStringLength = 100000;
}

/// Base class of expression errors, like Spring's `ExpressionException`.
///
/// Catch this type to handle both parse and evaluation failures.
///
/// ```dart
/// try {
///   SpelExpressionParser().parseExpression(input).getValue(context);
/// } on ExpressionException catch (e) {
///   print('${e.message} at ${e.position}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   parser.parseExpression(input).getValue(context);
/// } catch (ExpressionException ex) {
///   log.warn(ex.getMessage() + " at " + ex.getPosition());
/// }
/// ```
abstract class ExpressionException implements Exception {
  /// Creates an exception with [message], optionally pointing at
  /// [position] in [expressionString].
  ExpressionException(
    this.message, {
    this.expressionString,
    this.position = -1,
  });

  /// A human-readable description of the failure.
  final String message;

  /// The expression text, when known.
  final String? expressionString;

  /// Position in [expressionString], or -1.
  final int position;

  @override
  String toString() {
    final where = expressionString == null
        ? ''
        : position >= 0
        ? " in expression '$expressionString' at position $position"
        : " in expression '$expressionString'";
    return '$runtimeType: $message$where';
  }
}

/// The expression text is invalid, like Spring's `SpelParseException`.
///
/// Thrown by `SpelExpressionParser.parseExpression` before any evaluation.
///
/// ```dart
/// try {
///   SpelExpressionParser().parseExpression('1 +');
/// } on SpelParseException catch (e) {
///   print(e.code); // SpelMessage.unexpectedEndOfExpression
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   new SpelExpressionParser().parseExpression("1 +");
/// } catch (SpelParseException ex) {
///   SpelMessage code = ex.getMessageCode(); // OOD
/// }
/// ```
class SpelParseException extends ExpressionException {
  /// Creates a parse error with [code] and [message].
  SpelParseException(
    this.code,
    super.message, {
    super.expressionString,
    super.position,
  });

  /// The kind of parse failure.
  final SpelMessage code;
}

/// Evaluation failed, like Spring's `SpelEvaluationException`.
///
/// Thrown by `Expression.getValue`, `setValue` and friends; [cause] holds
/// the underlying error when a user function, accessor or converter threw.
///
/// ```dart
/// try {
///   SpelExpressionParser().parseExpression('T(Missing)').getValue();
/// } on SpelEvaluationException catch (e) {
///   print(e.code); // SpelMessage.typeNotFound
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   parser.parseExpression("T(com.example.Missing)").getValue();
/// } catch (SpelEvaluationException ex) {
///   SpelMessage code = ex.getMessageCode(); // TYPE_NOT_FOUND
/// }
/// ```
class SpelEvaluationException extends ExpressionException {
  /// Creates an evaluation error with [code] and [message], optionally
  /// wrapping [cause].
  SpelEvaluationException(
    this.code,
    super.message, {
    super.expressionString,
    super.position,
    this.cause,
  });

  /// The kind of evaluation failure.
  final SpelMessage code;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() =>
      '${super.toString()}${cause == null ? '' : '; caused by $cause'}';
}
