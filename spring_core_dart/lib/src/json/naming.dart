/// How Dart property names become JSON names, like Jackson's
/// `PropertyNamingStrategies` (`spring.jackson.property-naming-strategy`).
/// `@JsonProperty` on a property wins.
///
/// ```dart
/// PropertyNamingStrategy.snakeCase.translate('publishedAt');  // published_at
/// PropertyNamingStrategy.snakeCase.translate('myURLValue');   // my_urlvalue
/// PropertyNamingStrategy.kebabCase.translate('URLValue');     // url-value
/// ObjectMapper(namingStrategy: PropertyNamingStrategy.snakeCase);
/// ```
///
/// Spring (Java):
/// ```java
/// mapper.setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE);
/// ```
enum PropertyNamingStrategy {
  /// `publishedAt` (the Dart name, unchanged).
  lowerCamelCase,

  /// `PublishedAt`.
  upperCamelCase,

  /// `published_at`.
  snakeCase,

  /// `PUBLISHED_AT`.
  upperSnakeCase,

  /// `published-at`.
  kebabCase,

  /// `publishedat`.
  lowerCase,

  /// `published.at`.
  lowerDotCase;

  /// The JSON name of the Dart property [name], translated like Jackson's
  /// `PropertyNamingStrategies` (an acronym is one word for snake case:
  /// `myURLValue` → `my_urlvalue`; kebab and dot case split it before its
  /// last letter: `my-url-value`).
  String translate(String name) => switch (this) {
    lowerCamelCase => name,
    upperCamelCase =>
      name.isEmpty ? name : name[0].toUpperCase() + name.substring(1),
    snakeCase => _snakeCase(name),
    upperSnakeCase => _snakeCase(name).toUpperCase(),
    kebabCase => _lowerCaseWithSeparator(name, '-'),
    lowerCase => name.toLowerCase(),
    lowerDotCase => _lowerCaseWithSeparator(name, '.'),
  };

  static bool _isUpperCase(String char) => char != char.toLowerCase();

  // Jackson's SnakeCaseStrategy: an upper-case letter starts a word unless
  // the previous letter was upper-case too; a leading `_` is dropped.
  static String _snakeCase(String input) {
    final result = StringBuffer();
    var last = '';
    var wasPrevTranslated = false;
    for (var i = 0; i < input.length; i++) {
      var char = input[i];
      if (i == 0 && char == '_') {
        continue;
      }
      if (_isUpperCase(char)) {
        if (!wasPrevTranslated && result.isNotEmpty && last != '_') {
          result.write('_');
        }
        char = char.toLowerCase();
        wasPrevTranslated = true;
      } else {
        wasPrevTranslated = false;
      }
      result.write(char);
      last = char;
    }
    return result.isEmpty ? input : result.toString();
  }

  // Jackson's translateLowerCaseWithSeparator: an upper-case letter starts
  // a word; in an acronym the last upper-case letter starts the next word.
  static String _lowerCaseWithSeparator(String input, String separator) {
    final result = <String>[];
    var upperCount = 0;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (!_isUpperCase(char)) {
        if (upperCount > 1) {
          result.insert(result.length - 1, separator);
        }
        upperCount = 0;
      } else {
        if (upperCount == 0 && i > 0) {
          result.add(separator);
        }
        upperCount++;
      }
      result.add(char.toLowerCase());
    }
    return result.join();
  }

  /// The strategy for a property value such as `SNAKE_CASE`, `snake_case`,
  /// `snakeCase` or `kebab-case`.
  static PropertyNamingStrategy parse(String value) {
    final key = value.replaceAll(RegExp('[-_ .]'), '').toLowerCase();
    for (final strategy in values) {
      if (strategy.name.toLowerCase() == key) {
        return strategy;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unknown property naming strategy; one of SNAKE_CASE, UPPER_SNAKE_CASE, '
          'UPPER_CAMEL_CASE, LOWER_CAMEL_CASE, LOWER_CASE, KEBAB_CASE, '
          'LOWER_DOT_CASE',
    );
  }
}
