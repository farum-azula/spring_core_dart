/// The options of a `SpelExpressionParser`: the limits that protect
/// against hostile or runaway expressions, and auto-grow for data
/// binding.
///
/// The defaults suit most uses; pass a configuration when expressions are
/// legitimately larger (a long generated rule, a big projection) or when
/// a binding path such as `lines[3].product.name` should create the
/// missing list elements and objects instead of failing. Build one with
/// [SpelParserConfiguration.builder] (Spring 7's builder) or use
/// [SpelParserConfiguration.withDefaults]. The parser hands it to every
/// expression it returns.
///
/// ```dart
/// // Data binding: lists grow, and big forms get more operations.
/// final parser = SpelExpressionParser(
///   SpelParserConfiguration.builder()
///       .autoGrowCollections()
///       .maximumOperations(50000)
///       .build(),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// SpelExpressionParser parser = new SpelExpressionParser(
///     SpelParserConfiguration.builder()
///         .autoGrowCollections()
///         .maximumOperations(50_000)
///         .build());
/// ```
///
/// Differences from Spring: no compiler mode and no `BigInteger` power
/// limit. The default of [maximumOperations] can be changed with the
/// compile-time define `-Dspring.expression.maxOperations=...`
/// (`--dart-define` in Flutter), the counterpart of Spring's system
/// property.
final class SpelParserConfiguration {
  SpelParserConfiguration._({
    required this.autoGrowNullReferences,
    required this.autoGrowCollections,
    required this.maximumAutoGrowSize,
    required this.maximumExpressionLength,
    required this.maximumOperations,
    required this.maximumNestingDepth,
  });

  /// Default of [maximumAutoGrowSize] (Spring's
  /// `DEFAULT_MAX_AUTO_GROW_SIZE`).
  static const defaultMaxAutoGrowSize = 256;

  /// Default of [maximumExpressionLength] (Spring's
  /// `DEFAULT_MAX_EXPRESSION_LENGTH`).
  static const defaultMaxExpressionLength = 10000;

  /// Default of [maximumOperations] (Spring's `DEFAULT_MAX_OPERATIONS`).
  static const defaultMaxOperations = 10000;

  /// Default of [maximumNestingDepth] (Spring's
  /// `DEFAULT_MAX_EXPRESSION_NESTING_DEPTH`).
  static const defaultMaxExpressionNestingDepth = 1000;

  /// The name of the compile-time define that changes the default of
  /// [maximumOperations] for every parser
  /// (`-Dspring.expression.maxOperations=50000`; Spring's
  /// `SPRING_EXPRESSION_MAX_OPERATIONS_PROPERTY_NAME`). A value that is
  /// not a positive integer makes `build()` throw an [ArgumentError].
  static const springExpressionMaxOperationsPropertyName =
      'spring.expression.maxOperations';

  static const _maxOperationsProperty = String.fromEnvironment(
    springExpressionMaxOperationsPropertyName,
  );

  static final SpelParserConfiguration _defaults = builder().build();

  /// The default configuration, shared (Spring's `withDefaults()`): no
  /// auto-grow and the default limits.
  static SpelParserConfiguration withDefaults() => _defaults;

  /// A builder starting from the defaults (Spring's `builder()`).
  static SpelParserConfigurationBuilder builder() =>
      SpelParserConfigurationBuilder._();

  /// Whether a `null` property followed by `.x` or `[i]` is replaced by a
  /// new object, list or map instead of failing. It works only where the
  /// property type is known, that is on `@Introspected` classes. Off by
  /// default.
  final bool autoGrowNullReferences;

  /// Whether reading or writing past the end of a list grows it, filled
  /// with `null`, instead of failing with EL1025E. Off by default.
  final bool autoGrowCollections;

  /// The largest size a list may grow to ([defaultMaxAutoGrowSize] by
  /// default); growing further fails with EL1052E.
  final int maximumAutoGrowSize;

  /// The longest expression text the parser accepts, in characters
  /// ([defaultMaxExpressionLength] by default); longer text fails with
  /// EL1079E.
  final int maximumExpressionLength;

  /// The most operations (property and index accesses, method calls,
  /// variable lookups, selected and projected elements, ...) one
  /// evaluation may perform; going over fails with EL1085E. Defaults to
  /// [defaultMaxOperations] or the `spring.expression.maxOperations`
  /// define.
  final int maximumOperations;

  /// The deepest nesting (parentheses, arguments, inline collections,
  /// unary chains) the parser accepts ([defaultMaxExpressionNestingDepth]
  /// by default); deeper text fails with EL1087E.
  final int maximumNestingDepth;

  static int _defaultMaxOperations() {
    final value = _maxOperationsProperty.trim();
    if (value.isEmpty) {
      return defaultMaxOperations;
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw ArgumentError.value(
        value,
        springExpressionMaxOperationsPropertyName,
        'Must be a positive integer',
      );
    }
    return parsed;
  }

  @override
  String toString() =>
      'SpelParserConfiguration(autoGrowNullReferences: '
      '$autoGrowNullReferences, autoGrowCollections: $autoGrowCollections, '
      'maximumAutoGrowSize: $maximumAutoGrowSize, maximumExpressionLength: '
      '$maximumExpressionLength, maximumOperations: $maximumOperations, '
      'maximumNestingDepth: $maximumNestingDepth)';
}

/// Builds a [SpelParserConfiguration], starting from the defaults.
///
/// Get one from [SpelParserConfiguration.builder], call the options you
/// want to change, then [build]. Every limit must be positive (the auto-
/// grow size may be 0); a wrong value throws an [ArgumentError] at once.
///
/// ```dart
/// // Short expressions only, and null references are created on demand.
/// final configuration = SpelParserConfiguration.builder()
///     .autoGrowNullReferences()
///     .maximumExpressionLength(500)
///     .build();
/// ```
///
/// Spring (Java):
/// ```java
/// SpelParserConfiguration configuration = SpelParserConfiguration.builder()
///     .autoGrowNullReferences()
///     .maximumExpressionLength(500)
///     .build();
/// ```
final class SpelParserConfigurationBuilder {
  SpelParserConfigurationBuilder._();

  bool _autoGrowNullReferences = false;
  bool _autoGrowCollections = false;
  int _maximumAutoGrowSize = SpelParserConfiguration.defaultMaxAutoGrowSize;
  int _maximumExpressionLength =
      SpelParserConfiguration.defaultMaxExpressionLength;
  int? _maximumOperations;
  int _maximumNestingDepth =
      SpelParserConfiguration.defaultMaxExpressionNestingDepth;

  /// Turns on [SpelParserConfiguration.autoGrowNullReferences]: a `null`
  /// property followed by `.x` or `[i]` is replaced by a new object.
  SpelParserConfigurationBuilder autoGrowNullReferences() {
    _autoGrowNullReferences = true;
    return this;
  }

  /// Turns on [SpelParserConfiguration.autoGrowCollections]: lists indexed
  /// past their end grow.
  SpelParserConfigurationBuilder autoGrowCollections() {
    _autoGrowCollections = true;
    return this;
  }

  /// Sets the largest size a list may grow to (not negative; 0 disables
  /// growing).
  SpelParserConfigurationBuilder maximumAutoGrowSize(int size) {
    _maximumAutoGrowSize = _check(size, 'size', allowZero: true);
    return this;
  }

  /// Sets the longest accepted expression, in characters (positive).
  SpelParserConfigurationBuilder maximumExpressionLength(int length) {
    _maximumExpressionLength = _check(length, 'length');
    return this;
  }

  /// Sets the most operations per evaluation (positive), instead of the
  /// default or the `spring.expression.maxOperations` define.
  SpelParserConfigurationBuilder maximumOperations(int operations) {
    _maximumOperations = _check(operations, 'operations');
    return this;
  }

  /// Sets the deepest accepted nesting (positive).
  SpelParserConfigurationBuilder maximumNestingDepth(int depth) {
    _maximumNestingDepth = _check(depth, 'depth');
    return this;
  }

  /// Creates the configuration. Throws an [ArgumentError] when the
  /// `spring.expression.maxOperations` define is invalid and no maximum
  /// was set here.
  SpelParserConfiguration build() => SpelParserConfiguration._(
    autoGrowNullReferences: _autoGrowNullReferences,
    autoGrowCollections: _autoGrowCollections,
    maximumAutoGrowSize: _maximumAutoGrowSize,
    maximumExpressionLength: _maximumExpressionLength,
    maximumOperations:
        _maximumOperations ?? SpelParserConfiguration._defaultMaxOperations(),
    maximumNestingDepth: _maximumNestingDepth,
  );

  static int _check(int value, String name, {bool allowZero = false}) {
    if (value < 0 || (value == 0 && !allowZero)) {
      throw ArgumentError.value(
        value,
        name,
        allowZero ? 'Must not be negative' : 'Must be positive',
      );
    }
    return value;
  }
}
