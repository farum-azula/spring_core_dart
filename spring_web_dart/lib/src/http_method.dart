/// The HTTP request methods, like Spring's `HttpMethod`.
///
/// ```dart
/// HttpMethod.post.value;           // 'POST'
/// HttpMethod.parse('delete');      // HttpMethod.delete
/// ```
///
/// Spring (Java):
/// ```java
/// HttpMethod.POST.name();          // "POST"
/// HttpMethod.valueOf("DELETE");
/// ```
enum HttpMethod {
  /// `GET`.
  get,

  /// `HEAD`.
  head,

  /// `POST`.
  post,

  /// `PUT`.
  put,

  /// `PATCH`.
  patch,

  /// `DELETE`.
  delete,

  /// `OPTIONS`.
  options,

  /// `TRACE`.
  trace;

  /// The method as sent on the wire: `GET`, `POST`, ...
  String get value => name.toUpperCase();

  /// The method named [value] (case-insensitive); throws `ArgumentError`
  /// for an unknown one.
  static HttpMethod parse(String value) {
    final key = value.trim().toLowerCase();
    for (final method in values) {
      if (method.name == key) {
        return method;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown HTTP method');
  }

  @override
  String toString() => value;
}
