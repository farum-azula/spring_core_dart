/// A rule that turns Dart property names (`publishedAt`) into JSON names
/// (`published_at`), applied to every property of a class or of the whole
/// mapper.
///
/// Use it when the JSON you exchange follows another convention than Dart's
/// lowerCamelCase, such as a snake_case API, instead of writing
/// `@JsonProperty` on every field. Set it for all classes with
/// `ObjectMapper(namingStrategy: ...)` (in Spring Boot, the property
/// `spring.jackson.property-naming-strategy`), or for one class with
/// `@JsonNaming`. A name given by `@JsonProperty` is used as it is. The
/// translation follows Jackson's `PropertyNamingStrategies`, acronyms
/// included.
///
/// ```dart
/// // Talk to a snake_case API.
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
  /// The Dart name unchanged: `publishedAt`. The default.
  lowerCamelCase,

  /// The first letter upper-cased: `PublishedAt`.
  upperCamelCase,

  /// Lower case, words joined by `_`: `published_at`.
  snakeCase,

  /// Upper case, words joined by `_`: `PUBLISHED_AT`.
  upperSnakeCase,

  /// Lower case, words joined by `-`: `published-at`.
  kebabCase,

  /// Lower case, no separator: `publishedat`.
  lowerCase,

  /// Lower case, words joined by `.`: `published.at`.
  lowerDotCase;

  /// Returns the JSON name for the Dart property [name].
  ///
  /// Acronyms follow Jackson: snake case keeps one as a single word with
  /// the next one (`myURLValue` becomes `my_urlvalue`), kebab and dot case
  /// split it before its last letter (`my-url-value`). A leading `_` is
  /// dropped in snake case.
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

  /// Returns the strategy a configuration value names, such as
  /// `SNAKE_CASE`, `snake_case`, `snakeCase` or `kebab-case` (case,
  /// `-`, `_`, `.` and spaces are ignored).
  ///
  /// Throws an [ArgumentError] listing the valid names for any other
  /// value.
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
