/// A `${...}` placeholder could not be resolved, like Spring 6.2's
/// `PlaceholderResolutionException`.
///
/// ```dart
/// try {
///   environment.resolveRequiredPlaceholders(r'${missing.key}');
/// } on PlaceholderResolutionException catch (error) {
///   print(error.placeholder); // missing.key
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   environment.resolveRequiredPlaceholders("${missing.key}");
/// } catch (PlaceholderResolutionException ex) {
///   log.error(ex.getMessage());
/// }
/// ```
final class PlaceholderResolutionException implements Exception {
  /// Creates the exception for [placeholder] failing because of [reason]
  /// while resolving [values].
  PlaceholderResolutionException(this.reason, this.placeholder, this.values);

  /// Why resolution failed.
  final String reason;

  /// The placeholder key that failed.
  final String placeholder;

  /// The values being resolved, outermost first.
  final List<String> values;

  /// Full message: [reason] followed by the chain of values being
  /// resolved, e.g. `... in value "${a}" <-- "${b}"`.
  String get message =>
      '$reason in value "${values.isEmpty ? placeholder : values.first}"'
      '${values.length > 1 ? ' <-- "${values.skip(1).join('" <-- "')}"' : ''}';

  @override
  String toString() => 'PlaceholderResolutionException: $message';
}

/// Required properties are missing, like Spring's
/// `MissingRequiredPropertiesException`.
///
/// Thrown by `ConfigurablePropertyResolver.validateRequiredProperties`.
///
/// ```dart
/// environment
///   ..setRequiredProperties(['db.url', 'db.user'])
///   ..validateRequiredProperties(); // throws if one is missing
/// ```
///
/// Spring (Java):
/// ```java
/// environment.setRequiredProperties("db.url", "db.user");
/// environment.validateRequiredProperties();
/// ```
final class MissingRequiredPropertiesException implements Exception {
  /// Creates the exception listing the [missing] keys.
  MissingRequiredPropertiesException(Iterable<String> missing)
    : missingRequiredProperties = List.unmodifiable(missing);

  /// The required keys that could not be resolved.
  final List<String> missingRequiredProperties;

  @override
  String toString() =>
      'MissingRequiredPropertiesException: The following properties were '
      'declared as required but could not be resolved: '
      '$missingRequiredProperties';
}

/// A required property is not defined.
///
/// Thrown by `PropertyResolver.getRequiredProperty` and
/// `getRequiredPropertyAs`.
///
/// ```dart
/// try {
///   environment.getRequiredProperty('db.url');
/// } on MissingPropertyException catch (error) {
///   print(error.key); // db.url
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring throws IllegalStateException
/// // ("Required key 'db.url' not found").
/// String url = environment.getRequiredProperty("db.url");
/// ```
final class MissingPropertyException implements Exception {
  /// Creates the exception for the undefined [key].
  MissingPropertyException(this.key);

  /// The property key that was not found.
  final String key;

  @override
  String toString() =>
      "MissingPropertyException: Required key '$key' not found";
}
