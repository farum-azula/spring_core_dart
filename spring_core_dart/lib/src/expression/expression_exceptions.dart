/// The severity of a [SpelMessage]. Every message defined today is an
/// [error]; the other kinds exist because Spring defines them.
///
/// ```dart
/// SpelMessage.typeNotFound.kind; // SpelMessageKind.error
/// ```
///
/// Spring (Java):
/// ```java
/// SpelMessage.Kind kind = SpelMessage.Kind.ERROR;
/// ```
enum SpelMessageKind {
  /// Informational.
  info,

  /// A warning.
  warning,

  /// An error (codes rendered as `EL1001E`).
  error,
}

/// The catalogue of SpEL failures: each value is one kind of error with
/// its code (`EL1005E`) and message text.
///
/// Every [SpelParseException] and [SpelEvaluationException] carries one of
/// these as its `messageCode`, so code can react to a specific failure
/// (an unknown type, a missing property) without parsing the message
/// text. Names (in lowerCamelCase), numbers and texts are Spring's, so a
/// code looked up in Spring's documentation means the same here.
///
/// ```dart
/// // Tell an unknown type apart from other failures.
/// try {
///   SpelExpressionParser().parseExpression('T(Missing)').getValue();
/// } on SpelEvaluationException catch (e) {
///   e.messageCode; // SpelMessage.typeNotFound
///   e.simpleMessage; // EL1005E: Type cannot be found 'Missing'
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
///
/// A few codes are never raised here (no compiler, no Java arrays or
/// static-method checks, no overloads) and exist so the numbering matches
/// Spring; their comments say "not raised".
enum SpelMessage {
  /// `EL1001E`: a value cannot be converted (also a condition that is not a
  /// boolean).
  typeConversionError(
    SpelMessageKind.error,
    1001,
    'Type conversion problem, cannot convert from {0} to {1}',
  ),

  /// `EL1002E`: `new Name(...)` has no matching constructor.
  constructorNotFound(
    SpelMessageKind.error,
    1002,
    'Constructor call: No suitable constructor found on type {0} for '
    'arguments {1}',
  ),

  /// `EL1003E`: a constructor resolver failed.
  constructorInvocationProblem(
    SpelMessageKind.error,
    1003,
    'A problem occurred whilst attempting to construct an object of type '
    "''{0}'' using arguments ''{1}''",
  ),

  /// `EL1004E`: no method resolver handles the call.
  methodNotFound(
    SpelMessageKind.error,
    1004,
    'Method call: Method {0} cannot be found on type {1}',
  ),

  /// `EL1005E`: `T(Name)` names an unknown type.
  typeNotFound(SpelMessageKind.error, 1005, "Type cannot be found ''{0}''"),

  /// `EL1006E`: `#name(...)` is not registered.
  functionNotDefined(
    SpelMessageKind.error,
    1006,
    "Function ''{0}'' could not be found",
  ),

  /// `EL1007E`: a property was read on `null` without `?.`.
  propertyOrFieldNotReadableOnNull(
    SpelMessageKind.error,
    1007,
    "Property or field ''{0}'' cannot be found on null",
  ),

  /// `EL1008E`: no property accessor can read the property.
  propertyOrFieldNotReadable(
    SpelMessageKind.error,
    1008,
    "Property or field ''{0}'' cannot be found on object of type ''{1}'' - "
    'maybe not public or not valid?',
  ),

  /// `EL1009E`: a property was written on `null`.
  propertyOrFieldNotWritableOnNull(
    SpelMessageKind.error,
    1009,
    "Property or field ''{0}'' cannot be set on null",
  ),

  /// `EL1010E`: no property accessor can write the property.
  propertyOrFieldNotWritable(
    SpelMessageKind.error,
    1010,
    "Property or field ''{0}'' cannot be set on object of type ''{1}'' - "
    'maybe not public or not writable?',
  ),

  /// `EL1011E`: a method was called on `null` without `?.`.
  methodCallOnNullObjectNotAllowed(
    SpelMessageKind.error,
    1011,
    'Method call: Attempted to call method {0} on null context object',
  ),

  /// `EL1012E`: `[...]` was applied to `null` without `?.`.
  cannotIndexIntoNullValue(
    SpelMessageKind.error,
    1012,
    'Cannot index into a null value',
  ),

  /// `EL1013E`: two values cannot be ordered.
  notComparable(
    SpelMessageKind.error,
    1013,
    'Cannot compare instances of {0} and {1}',
  ),

  /// `EL1014E`: a function got too few or too many arguments.
  incorrectNumberOfArgumentsToFunction(
    SpelMessageKind.error,
    1014,
    "Incorrect number of arguments for function ''{0}'': {1} supplied but "
    'function takes {2}',
  ),

  /// `EL1015E`: `.?[...]` on something that is not a collection or map.
  invalidTypeForSelection(
    SpelMessageKind.error,
    1015,
    "Cannot perform selection on input data of type ''{0}''",
  ),

  /// `EL1016E`: a selection criterion did not yield a boolean.
  resultOfSelectionCriteriaIsNotBoolean(
    SpelMessageKind.error,
    1016,
    'Result of selection criteria is not boolean',
  ),

  /// `EL1017E`: the right side of `between` is not a two-element list.
  betweenRightOperandMustBeTwoElementList(
    SpelMessageKind.error,
    1017,
    "Right operand for the 'between' operator has to be a two-element list",
  ),

  /// `EL1018E`: a `matches` pattern is not a valid regular expression.
  invalidPattern(SpelMessageKind.error, 1018, "Pattern is not valid ''{0}''"),

  /// `EL1019E`: `.![...]` on something that is not a collection or map.
  projectionNotSupportedOnType(
    SpelMessageKind.error,
    1019,
    "Projection is not supported on the type ''{0}''",
  ),

  /// `EL1020E`: not raised (lambda argument lists).
  arglistShouldNotBeEvaluated(
    SpelMessageKind.error,
    1020,
    'The argument list of a lambda expression should never have getValue() '
    'called upon it',
  ),

  /// `EL1021E`: a property accessor threw while reading.
  exceptionDuringPropertyRead(
    SpelMessageKind.error,
    1021,
    "A problem occurred whilst attempting to access the property ''{0}'': "
    "''{1}''",
  ),

  /// `EL1022E`: `#name(...)` refers to a variable that is not a function.
  functionReferenceCannotBeInvoked(
    SpelMessageKind.error,
    1022,
    "The function ''{0}'' mapped to an object of type ''{1}'' cannot be "
    'invoked',
  ),

  /// `EL1023E`: a registered function threw.
  exceptionDuringFunctionCall(
    SpelMessageKind.error,
    1023,
    "A problem occurred whilst attempting to invoke the function ''{0}'': "
    "''{1}''",
  ),

  /// `EL1024E`: not raised (Java arrays are lists here, see
  /// [collectionIndexOutOfBounds]).
  arrayIndexOutOfBounds(
    SpelMessageKind.error,
    1024,
    "The array has ''{0}'' elements, index ''{1}'' is invalid",
  ),

  /// `EL1025E`: an index is outside a list or collection.
  collectionIndexOutOfBounds(
    SpelMessageKind.error,
    1025,
    "The collection has ''{0}'' elements, index ''{1}'' is invalid",
  ),

  /// `EL1026E`: an index is outside a string.
  stringIndexOutOfBounds(
    SpelMessageKind.error,
    1026,
    "The string has ''{0}'' characters, index ''{1}'' is invalid",
  ),

  /// `EL1027E`: the target cannot be indexed.
  indexingNotSupportedForType(
    SpelMessageKind.error,
    1027,
    "Indexing into type ''{0}'' is not supported",
  ),

  /// `EL1028E`: the right side of `instanceof` is not a type.
  instanceofOperatorNeedsClassOperand(
    SpelMessageKind.error,
    1028,
    "The operator 'instanceof' needs the right operand to be a class, not a "
    "''{0}''",
  ),

  /// `EL1029E`: a method executor failed with an `AccessException`.
  exceptionDuringMethodInvocation(
    SpelMessageKind.error,
    1029,
    "A problem occurred when trying to execute method ''{0}'' on object of "
    "type ''{1}'': ''{2}''",
  ),

  /// `EL1030E`: an operator does not support the operand types.
  operatorNotSupportedBetweenTypes(
    SpelMessageKind.error,
    1030,
    "The operator ''{0}'' is not supported between objects of type ''{1}'' "
    "and ''{2}''",
  ),

  /// `EL1031E`: a method resolver failed with an `AccessException`.
  problemLocatingMethod(
    SpelMessageKind.error,
    1031,
    'Problem locating method {0} on type {1}',
  ),

  /// `EL1032E`: the node cannot be assigned (`1 = 2`).
  setvalueNotSupported(
    SpelMessageKind.error,
    1032,
    "setValue(ExpressionState, Object) not supported for ''{0}''",
  ),

  /// `EL1033E`: not raised (no overload resolution).
  multiplePossibleMethods(
    SpelMessageKind.error,
    1033,
    "Method call of ''{0}'' is ambiguous, supported type conversions allow "
    'multiple variants to match',
  ),

  /// `EL1034E`: a property accessor threw while writing.
  exceptionDuringPropertyWrite(
    SpelMessageKind.error,
    1034,
    "A problem occurred whilst attempting to set the property ''{0}'': {1}",
  ),

  /// `EL1035E`: an integer literal is malformed.
  notAnInteger(
    SpelMessageKind.error,
    1035,
    "The value ''{0}'' cannot be parsed as an int",
  ),

  /// `EL1036E`: a long literal (`...L`) is malformed or too large.
  notALong(
    SpelMessageKind.error,
    1036,
    "The value ''{0}'' cannot be parsed as a long",
  ),

  /// `EL1037E`: the left side of `matches` is not a string.
  invalidFirstOperandForMatchesOperator(
    SpelMessageKind.error,
    1037,
    "First operand to matches operator must be a string. ''{0}'' is not",
  ),

  /// `EL1038E`: the right side of `matches` is not a string.
  invalidSecondOperandForMatchesOperator(
    SpelMessageKind.error,
    1038,
    "Second operand to matches operator must be a string. ''{0}'' is not",
  ),

  /// `EL1039E`: not raised (functions are plain Dart functions).
  functionMustBeStatic(
    SpelMessageKind.error,
    1039,
    'Only static methods can be called via function references. '
    "The method ''{0}'' referred to by name ''{1}'' is not static.",
  ),

  /// `EL1040E`: a real literal is malformed.
  notAReal(
    SpelMessageKind.error,
    1040,
    "The value ''{0}'' cannot be parsed as a double",
  ),

  /// `EL1041E`: text follows a complete expression (`1 2`).
  moreInput(
    SpelMessageKind.error,
    1041,
    'After parsing a valid expression, there is still more data in the '
    "expression: ''{0}''",
  ),

  /// `EL1042E`: the right operand of an operator is missing.
  rightOperandProblem(
    SpelMessageKind.error,
    1042,
    'Problem parsing right operand',
  ),

  /// `EL1043E`: the parser found a token it did not expect.
  notExpectedToken(
    SpelMessageKind.error,
    1043,
    "Unexpected token. Expected ''{0}'' but was ''{1}''",
  ),

  /// `EL1044E`: the expression ended too early (`1 +`, empty text).
  ood(SpelMessageKind.error, 1044, 'Unexpectedly ran out of input'),

  /// `EL1045E`: a `"..."` string has no closing quote.
  nonTerminatingDoubleQuotedString(
    SpelMessageKind.error,
    1045,
    'Cannot find terminating " for string',
  ),

  /// `EL1046E`: a `'...'` string has no closing quote.
  nonTerminatingQuotedString(
    SpelMessageKind.error,
    1046,
    "Cannot find terminating '' for string",
  ),

  /// `EL1047E`: not raised (`.5` fails with [ood] instead).
  missingLeadingZeroForNumber(
    SpelMessageKind.error,
    1047,
    "A real number must be prefixed by zero, it cannot start with just ''.''",
  ),

  /// `EL1048E`: a real literal has an `L` suffix (`1.5L`).
  realCannotBeLong(
    SpelMessageKind.error,
    1048,
    'Real number cannot be suffixed with a long (L or l) suffix',
  ),

  /// `EL1049E`: a dot is followed by something that is not a name.
  unexpectedDataAfterDot(
    SpelMessageKind.error,
    1049,
    "Unexpected data after ''.'': ''{0}''",
  ),

  /// `EL1050E`: `new Name` without `(...)` or `[...]`.
  missingConstructorArgs(
    SpelMessageKind.error,
    1050,
    "The arguments '(...)' for the constructor call are missing",
  ),

  /// `EL1051E`: not raised.
  runOutOfArguments(
    SpelMessageKind.error,
    1051,
    'Unexpectedly ran out of arguments',
  ),

  /// `EL1052E`: auto-growing a list beyond the configured maximum.
  unableToGrowCollection(
    SpelMessageKind.error,
    1052,
    'Unable to grow collection',
  ),

  /// `EL1053E`: auto-growing a list whose elements cannot be `null`.
  unableToGrowCollectionUnknownElementType(
    SpelMessageKind.error,
    1053,
    'Unable to grow collection: unable to determine list element type',
  ),

  /// `EL1054E`: not raised (with auto-grow on, a `null` list property
  /// that cannot be created gives [unableToDynamicallyCreateObject]).
  unableToCreateListForIndexing(
    SpelMessageKind.error,
    1054,
    'Unable to dynamically create a List to replace a null value',
  ),

  /// `EL1055E`: not raised (with auto-grow on, a `null` map property
  /// that cannot be created gives [unableToDynamicallyCreateObject]).
  unableToCreateMapForIndexing(
    SpelMessageKind.error,
    1055,
    'Unable to dynamically create a Map to replace a null value',
  ),

  /// `EL1056E`: with auto-grow on, a `null` property could not be
  /// replaced by a new value (its type is unknown or cannot be created
  /// without arguments).
  unableToDynamicallyCreateObject(
    SpelMessageKind.error,
    1056,
    "Unable to dynamically create instance of ''{0}'' to replace a null "
    'value',
  ),

  /// `EL1057E`: `@bean` was used but the context has no bean resolver.
  noBeanResolverRegistered(
    SpelMessageKind.error,
    1057,
    'No bean resolver registered in the context to resolve access to bean '
    "''{0}''",
  ),

  /// `EL1058E`: the bean resolver failed with an `AccessException`.
  exceptionDuringBeanResolution(
    SpelMessageKind.error,
    1058,
    "A problem occurred when trying to resolve bean ''{0}'': ''{1}''",
  ),

  /// `EL1059E`: `@` or `&` is not followed by a name.
  invalidBeanReference(
    SpelMessageKind.error,
    1059,
    '@ or & can only be followed by an identifier or a quoted name',
  ),

  /// `EL1060E`: not raised (array type names are always identifiers).
  typeNameExpectedForArrayConstruction(
    SpelMessageKind.error,
    1060,
    'Expected the type of the new array to be specified as a String but '
    "found ''{0}''",
  ),

  /// `EL1061E`: an array initializer element does not fit the element type.
  incorrectElementTypeForArray(
    SpelMessageKind.error,
    1061,
    "The array of type ''{0}'' cannot have an element of type ''{1}'' "
    'inserted',
  ),

  /// `EL1062E`: `new int[2][2]{...}`.
  multidimArrayInitializerNotSupported(
    SpelMessageKind.error,
    1062,
    'Using an initializer to build a multi-dimensional array is not '
    'currently supported',
  ),

  /// `EL1063E`: `new int[]` without a size or initializer.
  missingArrayDimension(
    SpelMessageKind.error,
    1063,
    'A required array dimension has not been specified',
  ),

  /// `EL1064E`: `new int[3]{1, 2}`.
  initializerLengthIncorrect(
    SpelMessageKind.error,
    1064,
    'Array initializer size does not match array dimensions',
  ),

  /// `EL1065E`: a backslash outside a string (`a \ b`); strings have no
  /// backslash escapes.
  unexpectedEscapeChar(
    SpelMessageKind.error,
    1065,
    'Unexpected escape character',
  ),

  /// `EL1066E`: `++` on something that cannot be assigned.
  operandNotIncrementable(
    SpelMessageKind.error,
    1066,
    "The expression component ''{0}'' does not support increment",
  ),

  /// `EL1067E`: `--` on something that cannot be assigned.
  operandNotDecrementable(
    SpelMessageKind.error,
    1067,
    "The expression component ''{0}'' does not support decrement",
  ),

  /// `EL1068E`: assignment is disabled in the context, or the target is
  /// read-only.
  notAssignable(
    SpelMessageKind.error,
    1068,
    "The expression component ''{0}'' is not assignable",
  ),

  /// `EL1069E`: an expected character is missing (a single `|`).
  missingCharacter(
    SpelMessageKind.error,
    1069,
    "Missing expected character ''{0}''",
  ),

  /// `EL1070E`: the left operand of an operator is missing.
  leftOperandProblem(
    SpelMessageKind.error,
    1070,
    'Problem parsing left operand',
  ),

  /// `EL1071E`: `.?[]` without a criterion.
  missingSelectionExpression(
    SpelMessageKind.error,
    1071,
    'A required selection expression has not been specified',
  ),

  /// `EL1072E`: not raised (no compiler).
  exceptionRunningCompiledExpression(
    SpelMessageKind.error,
    1072,
    'An exception occurred whilst evaluating a compiled expression',
  ),

  /// `EL1073E`: a `matches` pattern has nested quantifiers (the shape of
  /// catastrophic backtracking).
  flawedPattern(
    SpelMessageKind.error,
    1073,
    "Failed to efficiently evaluate pattern ''{0}'': consider redesigning it",
  ),

  /// `EL1074E`: not raised (no compiler).
  exceptionCompilingExpression(
    SpelMessageKind.error,
    1074,
    'An exception occurred while compiling an expression',
  ),

  /// `EL1075E`: `new int[n]` with more than 262 144 elements.
  maxArrayElementsThresholdExceeded(
    SpelMessageKind.error,
    1075,
    "Array declares too many elements, exceeding the threshold of ''{0}''",
  ),

  /// `EL1076E`: `'text' * n` longer than [SpelLimits.maxRepeatedTextSize].
  maxRepeatedTextSizeExceeded(
    SpelMessageKind.error,
    1076,
    "Repeated text is too long, exceeding the threshold of ''{0}'' "
    'characters',
  ),

  /// `EL1077E`: a pattern longer than [SpelLimits.maxRegexLength].
  maxRegexLengthExceeded(
    SpelMessageKind.error,
    1077,
    "Regular expression is too long, exceeding the threshold of ''{0}'' "
    'characters',
  ),

  /// `EL1078E`: `+` would build a string longer than
  /// [SpelLimits.maxConcatenatedStringLength].
  maxConcatenatedStringLengthExceeded(
    SpelMessageKind.error,
    1078,
    "Concatenated string is too long, exceeding the threshold of ''{0}'' "
    'characters',
  ),

  /// `EL1079E`: the expression is longer than
  /// `SpelParserConfiguration.maximumExpressionLength`.
  maxExpressionLengthExceeded(
    SpelMessageKind.error,
    1079,
    "SpEL expression is too long, exceeding the threshold of ''{0}'' "
    'characters',
  ),

  /// `EL1080E`: the context forbids `#name = ...` (a
  /// `SimpleEvaluationContext`).
  variableAssignmentNotSupported(
    SpelMessageKind.error,
    1080,
    "Assignment to variable ''{0}'' is not supported",
  ),

  /// `EL1081E`: `'text' * n` with a negative `n`.
  negativeRepeatedTextCount(
    SpelMessageKind.error,
    1081,
    "Repeat count ''{0}'' must not be negative",
  ),

  /// `EL1082E`: a character that is not part of the SpEL syntax.
  unsupportedCharacter(
    SpelMessageKind.error,
    1082,
    "Unsupported character ''{0}'' ({1}) encountered in expression",
  ),

  /// `EL1083E`: an `IndexAccessor` threw while reading.
  exceptionDuringIndexRead(
    SpelMessageKind.error,
    1083,
    "A problem occurred while attempting to read index ''{0}'' in ''{1}''",
  ),

  /// `EL1084E`: an `IndexAccessor` threw while writing.
  exceptionDuringIndexWrite(
    SpelMessageKind.error,
    1084,
    "A problem occurred while attempting to write index ''{0}'' in ''{1}''",
  ),

  /// `EL1085E`: one evaluation used more than
  /// `SpelParserConfiguration.maximumOperations` operations.
  maxOperationsExceeded(
    SpelMessageKind.error,
    1085,
    "SpEL expression evaluation exceeded the threshold of ''{0}'' operations",
  ),

  /// `EL1086E`: not raised (no `BigInt` arithmetic).
  maxBigPowerResultExceeded(
    SpelMessageKind.error,
    1086,
    "BigDecimal/BigInteger power operation with base bit length ''{0}'' and "
    "exponent ''{1}''would produce a result exceeding the configured "
    "maximum of ''{2}'' bits",
  ),

  /// `EL1087E`: the expression nests deeper than
  /// `SpelParserConfiguration.maximumNestingDepth`.
  maxExpressionNestingDepthExceeded(
    SpelMessageKind.error,
    1087,
    'SpEL expression nesting depth exceeds the threshold of {0}',
  );

  SpelMessage(this.kind, this.code, this.message);

  /// The severity; [SpelMessageKind.error] for every message.
  final SpelMessageKind kind;

  /// The number, such as `1008` for `EL1008E`.
  final int code;

  /// The message template in `java.text.MessageFormat` syntax (`{0}`
  /// placeholders, `''` for a quote).
  final String message;

  /// The text of an exception: the code, then [message] with [inserts]
  /// in place of `{0}`, `{1}`, ... (integers with thousands separators,
  /// like Java's `MessageFormat`).
  ///
  /// The exceptions call it; you need it only to build the same text
  /// yourself.
  ///
  /// ```dart
  /// SpelMessage.typeNotFound.formatMessage(['Point']);
  /// // EL1005E: Type cannot be found 'Point'
  /// ```
  String formatMessage([List<Object?> inserts = const []]) {
    final buffer = StringBuffer('EL$code')
      ..write(kind == SpelMessageKind.error ? 'E' : '')
      ..write(': ');
    var quoted = false;
    for (var i = 0; i < message.length; i++) {
      final c = message[i];
      if (c == "'") {
        if (i + 1 < message.length && message[i + 1] == "'") {
          buffer.write("'");
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == '{' && !quoted) {
        final close = message.indexOf('}', i);
        final index = close < 0
            ? null
            : int.tryParse(message.substring(i + 1, close));
        if (index == null) {
          buffer.write(c);
          continue;
        }
        buffer.write(
          index < inserts.length ? _formatInsert(inserts[index]) : '{$index}',
        );
        i = close;
      } else {
        buffer.write(c);
      }
    }
    return buffer.toString();
  }

  // Integers with grouping separators, like MessageFormat in English.
  static String _formatInsert(Object? insert) {
    if (insert is! int) {
      return '$insert';
    }
    final digits = insert.abs().toString();
    final grouped = StringBuffer(insert < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(digits[i]);
    }
    return grouped.toString();
  }
}

/// The fixed size limits of what one operator may build, which keep a
/// hostile expression from exhausting memory or time.
///
/// They have Spring's values and cannot be changed. Going over one fails
/// the evaluation with the matching code (EL1075E to EL1078E). The
/// limits that can be configured, expression length, nesting depth and
/// operations per evaluation, are set per parser in
/// `SpelParserConfiguration`.
///
/// ```dart
/// // 400 characters would be built: refused.
/// parser.parseExpression("'ab' * 200").getValue();
/// // SpelEvaluationException: EL1076E (400 > 256)
/// ```
///
/// Spring (Java):
/// ```java
/// // OpMultiply.MAX_REPEATED_TEXT_SIZE, OperatorMatches.MAX_REGEX_LENGTH,
/// // OpPlus.MAX_CONCATENATED_STRING_LENGTH,
/// // ConstructorReference.MAX_ARRAY_ELEMENTS
/// ```
abstract final class SpelLimits {
  /// Maximum length, in characters, of a string built by `'text' * n`.
  static const maxRepeatedTextSize = 256;

  /// Maximum length, in characters, of a `matches` pattern (operator and
  /// String method).
  static const maxRegexLength = 1000;

  /// Maximum length, in characters, of a string built by `+`.
  static const maxConcatenatedStringLength = 100000;

  /// Maximum number of elements of an array built by `new int[n]`
  /// (262 144).
  static const int maxArrayElements = 256 * 1024;
}

/// The common supertype of everything that can go wrong with an
/// expression: invalid text ([ParseException]) or a failed evaluation
/// ([EvaluationException]).
///
/// Catch it where an expression comes from configuration or a user and a
/// bad one should be reported rather than crash the caller. [message]
/// says which expression failed and where (`Expression [1 +] @3: ...`);
/// [simpleMessage] is the bare reason. Exceptions thrown by methods and
/// constructors the expression calls are not wrapped in it (those of
/// registered functions are, as EL1023E).
///
/// ```dart
/// // A rule typed by an administrator: report it, keep running.
/// try {
///   SpelExpressionParser().parseExpression(input).getValue(context);
/// } on ExpressionException catch (e) {
///   print(e.message); // Expression [1 +] @3: EL1044E: Unexpectedly ...
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   parser.parseExpression(input).getValue(context);
/// } catch (ExpressionException ex) {
///   log.warn(ex.getMessage());
/// }
/// ```
class ExpressionException implements Exception {
  /// Creates an exception with [simpleMessage], optionally pointing at
  /// [position] in [expressionString] and wrapping [cause].
  ExpressionException(
    this.simpleMessage, {
    this.expressionString,
    this.position = -1,
    this.cause,
  });

  /// The reason alone, without the expression and position (Spring's
  /// `getSimpleMessage()`), such as `EL1044E: Unexpectedly ran out of
  /// input`.
  final String simpleMessage;

  /// The text of the failed expression, or `null` when unknown.
  final String? expressionString;

  /// The character offset in [expressionString] where the problem was
  /// found, or -1 when unknown.
  final int position;

  /// The error that caused this one (a converter's or an accessor's), or
  /// `null`.
  final Object? cause;

  /// The full message, with the expression and position; the same as
  /// [toDetailedString] (Spring's `getMessage()`).
  String get message => toDetailedString();

  /// `Expression [text] @position: message`, or only [simpleMessage] when
  /// the expression is unknown (Spring's `toDetailedString()`).
  String toDetailedString() {
    final expression = expressionString;
    if (expression == null) {
      return simpleMessage;
    }
    return 'Expression [$expression]${position >= 0 ? ' @$position' : ''}: '
        '$simpleMessage';
  }

  @override
  String toString() =>
      // Subclasses show their own name.
      // ignore: no_runtimetype_tostring
      '$runtimeType: $message${cause == null ? '' : '; caused by $cause'}';
}

/// An expression was valid but could not be evaluated: a missing
/// property, an unknown type, a failed conversion.
///
/// SpEL itself throws the subtype [SpelEvaluationException], which adds
/// the error code. Catch this type when the parse step happened earlier
/// and only evaluation failures are expected here.
///
/// ```dart
/// // The expression was parsed at startup; this order lacks a field.
/// try {
///   expression.getValue(context);
/// } on EvaluationException catch (e) {
///   print(e.message);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   expression.getValue(context);
/// } catch (EvaluationException ex) {
///   log.warn(ex.getMessage());
/// }
/// ```
class EvaluationException extends ExpressionException {
  /// Creates an evaluation error with [simpleMessage].
  EvaluationException(
    super.simpleMessage, {
    super.expressionString,
    super.position,
    super.cause,
  });
}

/// The text of an expression or template is not valid, so it cannot be
/// parsed.
///
/// Thrown by `parseExpression`, before anything is evaluated, so parsing
/// at startup finds bad expressions early. Template structure errors (an
/// unclosed `#{`, an empty `#{}`, unbalanced brackets) are plain
/// `ParseException`s; errors inside an expression are
/// [SpelParseException]s with a [SpelMessage].
///
/// ```dart
/// // An `@Value`-style template missing its closing brace.
/// try {
///   parser.parseExpression('#{1 + 2', ParserContext.template);
/// } on ParseException catch (e) {
///   print(e.message); // No ending suffix '}' for expression starting ...
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   parser.parseExpression("#{1 + 2", ParserContext.TEMPLATE_EXPRESSION);
/// } catch (ParseException ex) {
///   log.warn(ex.getMessage());
/// }
/// ```
class ParseException extends ExpressionException {
  /// Creates a parse error with [simpleMessage].
  ParseException(
    super.simpleMessage, {
    super.expressionString,
    super.position,
    super.cause,
  });
}

/// The text of a SpEL expression is not valid; [messageCode] says what is
/// wrong.
///
/// Thrown by `SpelExpressionParser.parseExpression` before any
/// evaluation: a syntax error, a character SpEL does not know, a text
/// longer than `maximumExpressionLength` or nested deeper than
/// `maximumNestingDepth`.
///
/// ```dart
/// // An operator without its right operand.
/// try {
///   SpelExpressionParser().parseExpression('1 +');
/// } on SpelParseException catch (e) {
///   e.messageCode; // SpelMessage.ood
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
class SpelParseException extends ParseException {
  /// Creates a parse error of [messageCode] formatted with [inserts].
  SpelParseException(
    this.messageCode, {
    List<Object?> inserts = const [],
    super.expressionString,
    super.position,
  }) : inserts = List.unmodifiable(inserts),
       super(messageCode.formatMessage(inserts));

  /// What is wrong, as a code to compare against (Spring's
  /// `getMessageCode()`).
  final SpelMessage messageCode;

  /// The values put into the message, such as the unexpected token
  /// (Spring's `getInserts()`); unmodifiable.
  final List<Object?> inserts;
}

/// Evaluating a SpEL expression failed; [messageCode] says why.
///
/// Thrown by `Expression.getValue`, `setValue` and the other evaluating
/// methods: a property no accessor can read, a method or type that is not
/// found, a value that cannot be converted, a limit exceeded. [cause]
/// holds the underlying error when an accessor, converter or function
/// threw. Exceptions thrown by your methods and constructors are rethrown
/// unchanged, like Spring.
///
/// ```dart
/// // `T(Missing)` names a type nobody registered.
/// try {
///   SpelExpressionParser().parseExpression('T(Missing)').getValue();
/// } on SpelEvaluationException catch (e) {
///   e.messageCode; // SpelMessage.typeNotFound
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
class SpelEvaluationException extends EvaluationException {
  /// Creates an evaluation error of [messageCode] formatted with
  /// [inserts], optionally wrapping [cause].
  SpelEvaluationException(
    this.messageCode, {
    List<Object?> inserts = const [],
    super.cause,
    super.expressionString,
    super.position,
  }) : inserts = List.unmodifiable(inserts),
       super(messageCode.formatMessage(inserts));

  /// Why evaluation failed, as a code to compare against (Spring's
  /// `getMessageCode()`).
  final SpelMessage messageCode;

  /// The values put into the message, such as the property name and the
  /// target type (Spring's `getInserts()`); unmodifiable.
  final List<Object?> inserts;
}

/// The exception a plug-in (property or index accessor, method,
/// constructor or bean resolver, executor) throws to say it could not do
/// its job.
///
/// Throw it from your own plug-ins to have the failure reported as a
/// [SpelEvaluationException] with the matching code
/// (`exceptionDuringMethodInvocation`, `exceptionDuringBeanResolution`,
/// ...) and the expression's position; other exceptions from method and
/// constructor executors propagate unchanged.
///
/// ```dart
/// // A method that cannot run while its service is closed.
/// MethodExecutor executor = (context, target, args) =>
///     throw AccessException('Service is closed');
/// ```
///
/// Spring (Java):
/// ```java
/// throw new AccessException("Service is closed");
/// ```
class AccessException implements Exception {
  /// Creates an exception with [message], optionally wrapping [cause].
  AccessException(this.message, [this.cause]);

  /// What went wrong; it becomes part of the SpEL error message.
  final String message;

  /// The error that caused this one, or `null`.
  final Object? cause;

  @override
  String toString() =>
      'AccessException: $message${cause == null ? '' : '; caused by $cause'}';
}
