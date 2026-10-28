/// The error the JSON mapper throws when JSON cannot be turned into the
/// requested type, or a value cannot be written as JSON.
///
/// Typical causes: text that is not JSON, a missing required property, a
/// value of the wrong type, a constructor that threw. The [path] says
/// where in the document the problem is, so the message can go back to
/// whoever sent the JSON. Catch it where you read JSON from outside; the
/// web starter turns it into a 400 response for request bodies.
///
/// ```dart
/// // Reject a bad upload with a message naming the field.
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
  /// A problem described by [message] at [path] (empty for the root),
  /// caused by [cause].
  JsonMappingException(this.message, {this.path = '', this.cause});

  /// What went wrong, without the path.
  final String message;

  /// Where the problem is, such as `items[2].price`; empty for the whole
  /// value.
  final String path;

  /// The underlying error, such as a `FormatException` for invalid JSON or
  /// what a constructor threw; `null` when there is none.
  final Object? cause;

  @override
  String toString() =>
      'JsonMappingException: ${path.isEmpty ? '' : '$path: '}$message';
}
