/// The HTTP request methods (`GET`, `POST`, ...), as an enum.
///
/// Mapping annotations carry one (`@RequestMapping.of(method: ...)`), a
/// server request tells its method with it, and a client request is sent
/// with it. Code that compares or switches on methods uses the enum
/// values instead of strings; [value] is the text sent on the wire.
///
/// ```dart
/// // An interceptor letting reads through and checking writes.
/// final isRead = switch (request.method) {
///   HttpMethod.get || HttpMethod.head || HttpMethod.options => true,
///   _ => false,
/// };
///
/// HttpMethod.parse('DELETE'); // HttpMethod.delete
/// HttpMethod.post.value;      // 'POST'
/// ```
///
/// Spring (Java):
/// ```java
/// HttpMethod.POST.name();          // "POST"
/// HttpMethod.valueOf("DELETE");
/// ```
enum HttpMethod {
  /// `GET`: reads a resource without changing it.
  get,

  /// `HEAD`: like `GET`, but the answer has only the status and headers.
  head,

  /// `POST`: sends data to create something or start an action.
  post,

  /// `PUT`: replaces the resource at the path with the body.
  put,

  /// `PATCH`: changes part of the resource at the path.
  patch,

  /// `DELETE`: removes the resource at the path.
  delete,

  /// `OPTIONS`: asks which methods a path supports; browsers send it as
  /// the CORS pre-flight request.
  options,

  /// `TRACE`: asks the server to echo the request, for debugging.
  trace;

  /// The method's name as sent on the wire, in upper case: `GET`,
  /// `POST`, ... [toString] returns it too.
  String get value => name.toUpperCase();

  /// The method named exactly [value], such as `'DELETE'`. HTTP method
  /// names are case-sensitive, so `'get'` or `' GET'` is an
  /// `ArgumentError`, as is an unknown method.
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
