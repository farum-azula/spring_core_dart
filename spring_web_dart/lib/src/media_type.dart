/// Common media types for `Content-Type` and `Accept`, like Spring's
/// `MediaType` constants.
///
/// ```dart
/// headers.set(HttpHeaders.contentType, MediaType.applicationJson);
/// @PostMapping('/books', consumes: MediaType.applicationJson)
/// ```
///
/// Spring (Java):
/// ```java
/// headers.setContentType(MediaType.APPLICATION_JSON);
/// @PostMapping(path = "/books", consumes = MediaType.APPLICATION_JSON_VALUE)
/// ```
abstract final class MediaType {
  /// `application/json`.
  static const applicationJson = 'application/json';

  /// `text/plain`.
  static const textPlain = 'text/plain';

  /// `application/octet-stream`.
  static const applicationOctetStream = 'application/octet-stream';

  /// `application/x-www-form-urlencoded`.
  static const applicationFormUrlencoded = 'application/x-www-form-urlencoded';

  /// `multipart/form-data`.
  static const multipartFormData = 'multipart/form-data';

  /// `text/html`.
  static const textHtml = 'text/html';

  /// `*/*`.
  static const all = '*/*';
}
