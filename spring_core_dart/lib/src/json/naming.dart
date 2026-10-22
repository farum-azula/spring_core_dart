/// How Dart property names become JSON names, like Jackson's
/// `PropertyNamingStrategies` (`spring.jackson.property-naming-strategy`).
/// `@JsonProperty` on a property wins.
///
/// ```dart
/// PropertyNamingStrategy.snakeCase.translate('publishedAt');  // published_at
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

  // Words of a camelCase name; acronyms stay together (`URLValue` → URL,
  // Value), digits stick to the word before them (`isbn13`).
  static final _words = RegExp(r'[A-Z]+(?![a-z])|[A-Z]?[a-z0-9]+|[0-9]+');

  /// The JSON name of the Dart property [name].
  String translate(String name) {
    if (this == lowerCamelCase) {
      return name;
    }
    final words = [
      for (final match in _words.allMatches(name)) match[0]!.toLowerCase(),
    ];
    if (words.isEmpty) {
      return name;
    }
    return switch (this) {
      lowerCamelCase => name,
      upperCamelCase => words.map(_capitalize).join(),
      snakeCase => words.join('_'),
      upperSnakeCase => words.join('_').toUpperCase(),
      kebabCase => words.join('-'),
      lowerCase => words.join(),
      lowerDotCase => words.join('.'),
    };
  }

  static String _capitalize(String word) =>
      word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

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
