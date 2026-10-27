/// Options of a `SpelExpressionParser`, like Spring's
/// `SpelParserConfiguration`: auto-grow and the limits that protect
/// against hostile expressions.
///
/// Create one with [SpelParserConfiguration.builder] (Spring 7's builder)
/// or use [SpelParserConfiguration.withDefaults].
///
/// ```dart
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

  /// Compile-time define that changes the default of [maximumOperations]
  /// (Spring's `SPRING_EXPRESSION_MAX_OPERATIONS_PROPERTY_NAME`).
  static const springExpressionMaxOperationsPropertyName =
      'spring.expression.maxOperations';

  static const _maxOperationsProperty = String.fromEnvironment(
    springExpressionMaxOperationsPropertyName,
  );

  static final SpelParserConfiguration _defaults = builder().build();

  /// The default configuration (Spring's `withDefaults()`).
  static SpelParserConfiguration withDefaults() => _defaults;

  /// A builder starting from the defaults (Spring's `builder()`).
  static SpelParserConfigurationBuilder builder() =>
      SpelParserConfigurationBuilder._();

  /// Whether a `null` property followed by `.x` or `[i]` is replaced by a
  /// new object, list or map (only where the property type is known, i.e.
  /// `@Introspected` classes).
  final bool autoGrowNullReferences;

  /// Whether writing or reading past the end of a list grows it (filled
  /// with `null`).
  final bool autoGrowCollections;

  /// The largest size a list may grow to.
  final int maximumAutoGrowSize;

  /// The longest expression text accepted by the parser.
  final int maximumExpressionLength;

  /// The most operations (property and index accesses, method calls,
  /// variable lookups, selected and projected elements, ...) one
  /// evaluation may perform.
  final int maximumOperations;

  /// The deepest nesting the parser accepts.
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

/// Builder of [SpelParserConfiguration], like Spring's
/// `SpelParserConfiguration.Builder`.
///
/// ```dart
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

  /// Replaces `null` references followed by `.x` or `[i]` with new objects.
  SpelParserConfigurationBuilder autoGrowNullReferences() {
    _autoGrowNullReferences = true;
    return this;
  }

  /// Grows lists indexed past their end.
  SpelParserConfigurationBuilder autoGrowCollections() {
    _autoGrowCollections = true;
    return this;
  }

  /// The largest size a list may grow to (not negative; 0 disables
  /// growing).
  SpelParserConfigurationBuilder maximumAutoGrowSize(int size) {
    _maximumAutoGrowSize = _check(size, 'size', allowZero: true);
    return this;
  }

  /// The longest accepted expression (positive).
  SpelParserConfigurationBuilder maximumExpressionLength(int length) {
    _maximumExpressionLength = _check(length, 'length');
    return this;
  }

  /// The most operations per evaluation (positive).
  SpelParserConfigurationBuilder maximumOperations(int operations) {
    _maximumOperations = _check(operations, 'operations');
    return this;
  }

  /// The deepest accepted nesting (positive).
  SpelParserConfigurationBuilder maximumNestingDepth(int depth) {
    _maximumNestingDepth = _check(depth, 'depth');
    return this;
  }

  /// Creates the configuration.
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
