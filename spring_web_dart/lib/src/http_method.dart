/// The HTTP request methods, like Spring's `HttpMethod`.
///
/// ```dart
/// HttpMethod.post.value;           // 'POST'
/// HttpMethod.parse('DELETE');      // HttpMethod.delete
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

  /// The method named exactly [value] (`GET`, `POST`, ...: case-sensitive,
  /// like Spring's `HttpMethod.valueOf`); throws `ArgumentError` for any
  /// other text (`'get'` too: HTTP methods are case-sensitive).
  static HttpMethod parse(String value) {
    for (final method in values) {
      if (method.value == value) {
        return method;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown HTTP method');
  }

  @override
  String toString() => value;
}
