/// The error for a `${...}` placeholder that has no value and no default,
/// or that refers to itself in a loop (`a=${b}`, `b=${a}`).
///
/// It is thrown wherever a value must be complete: `@Value(r'${key}')`,
/// reading a property whose value holds such a placeholder, and
/// `resolveRequiredPlaceholders`. During startup it fails the start, and
/// the message names the placeholder and the chain of values it was found
/// in. Catch it only where text comes from users or from outside, such as
/// a template with placeholders.
///
/// ```dart
/// // A mail template edited by the shop owner may name unknown keys.
/// try {
///   return environment.resolveRequiredPlaceholders(template);
/// } on PlaceholderResolutionException catch (error) {
///   log.warn('Template uses ${error.placeholder}, which is not set');
///   return environment.resolvePlaceholders(template);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   return environment.resolveRequiredPlaceholders(template);
/// } catch (PlaceholderResolutionException ex) {
///   log.warn(ex.getMessage());
///   return environment.resolvePlaceholders(template);
/// }
/// ```
///
/// The class is Spring 6.2's.
final class PlaceholderResolutionException implements Exception {
  /// Creates the exception for [placeholder], which failed because of
  /// [reason] while [values] were being resolved.
  PlaceholderResolutionException(this.reason, this.placeholder, this.values);

  /// Why resolution failed, such as `Could not resolve placeholder 'db.url'`
  /// or `Circular placeholder reference 'a'`.
  final String reason;

  /// The key of the placeholder that failed, such as `db.url`.
  final String placeholder;

  /// The chain that led to the failure: the text the placeholder was in,
  /// and the keys (or texts) resolved on the way there. [message] shows
  /// it.
  final List<String> values;

  /// The full message: [reason] followed by the chain of [values], such
  /// as `Could not resolve placeholder 'b' in value "${b}" <-- "a"` when
  /// the property `a` holds `${b}`.
  String get message =>
      '$reason in value "${values.isEmpty ? placeholder : values.first}"'
      '${values.length > 1 ? ' <-- "${values.skip(1).join('" <-- "')}"' : ''}';

  @override
  String toString() => 'PlaceholderResolutionException: $message';
}

/// The error for properties that were declared required and have no
/// value.
///
/// Startup code declares keys the application cannot run without with
/// `setRequiredProperties`; `validateRequiredProperties` then throws this,
/// listing all missing keys at once, so an operator sees everything to fix
/// in one go. An application context validates when it starts, so the
/// start fails before any bean is created. Applications receive it as a
/// startup failure; they rarely catch it.
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

  /// The required keys that have no value, in the order they were
  /// declared.
  final List<String> missingRequiredProperties;

  @override
  String toString() =>
      'MissingRequiredPropertiesException: The following properties were '
      'declared as required but could not be resolved: '
      '$missingRequiredProperties';
}

/// The error for a property read as required that no source has.
///
/// `getRequiredProperty` and `getRequiredPropertyAs` throw it instead of
/// returning `null`, so code that needs a value can read it in one line
/// and fail with a clear message ("Required key 'db.url' not found") when
/// it is missing.
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
  /// Creates the exception for the missing [key].
  MissingPropertyException(this.key);

  /// The key that was read and not found.
  final String key;

  @override
  String toString() =>
      "MissingPropertyException: Required key '$key' not found";
}
