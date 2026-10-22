/// A value that cannot be written as JSON or rebuilt from it, with the
/// [path] to the problem, like Jackson's `JsonMappingException`.
///
/// ```dart
/// try {
///   mapper.readValue<Order>(json);
/// } on JsonMappingException catch (error) {
///   print(error); // items[2].price: expected a number, got "abc"
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// catch (JsonMappingException e) { e.getPathReference(); }
/// ```
class JsonMappingException implements Exception {
  /// A problem at [path] (empty for the root).
  JsonMappingException(this.message, {this.path = '', this.cause});

  /// What went wrong.
  final String message;

  /// Where: `items[2].price`; empty for the whole value.
  final String path;

  /// The error that caused it (e.g. thrown by a constructor), if any.
  final Object? cause;

  @override
  String toString() =>
      'JsonMappingException: ${path.isEmpty ? '' : '$path: '}$message';
}
