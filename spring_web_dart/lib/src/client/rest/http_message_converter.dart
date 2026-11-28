import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/media_type.dart';
import 'package:spring_web_dart/src/multipart/multipart.dart';

/// Writes a request body and reads a response body of a `RestClient`: one
/// link of the chain its builder holds (`messageConverters`), asked in
/// order; the first that can, does.
///
/// The defaults, in order: [ByteArrayHttpMessageConverter] (`Uint8List`),
/// [StringHttpMessageConverter] (`String`),
/// [MultipartHttpMessageConverter] (`MultipartBody`, written only),
/// [FormHttpMessageConverter] (a `Map` sent as
/// `application/x-www-form-urlencoded`, written only) and
/// [JsonHttpMessageConverter] (anything else, as JSON through the
/// `ObjectMapper`). Add one for another format (XML, CBOR, protobuf) in
/// front of them.
///
/// ```dart
/// final client = RestClient.builder()
///     .messageConverters((converters) => converters.insert(0, CsvConverter()))
///     .build();
/// ```
///
/// Spring (Java): `HttpMessageConverter`, configured with
/// `RestClient.Builder.messageConverters(...)`.
abstract interface class HttpMessageConverter {
  /// Whether it writes [value] as a body of [contentType] (`null`: the
  /// request has none yet).
  bool canWrite(Object value, String? contentType);

  /// The bytes of [value] and the `Content-Type` to send them with;
  /// [type] describes [value] when the caller gave it (`body(value,
  /// type)`).
  ({List<int> bytes, String contentType}) write(
    Object value,
    String? contentType,
    TypeInfo<Object?>? type,
  );

  /// Whether it reads a body of [contentType] (`null`: the response has
  /// none) as [type].
  bool canRead(TypeInfo<Object?> type, String? contentType);

  /// The [body] of [contentType] read as [type]. Throws a
  /// [FormatException] or a [JsonMappingException] for a body that does
  /// not fit.
  Object? read(TypeInfo<Object?> type, Uint8List body, String? contentType);
}

/// Bytes as they are: writes a `Uint8List` (as
/// `application/octet-stream` unless the request says otherwise) and reads
/// a body as `Uint8List` (a `List<int>` is a JSON array of numbers).
///
/// Spring (Java): `ByteArrayHttpMessageConverter`.
final class ByteArrayHttpMessageConverter implements HttpMessageConverter {
  /// The converter; it has no settings.
  const ByteArrayHttpMessageConverter();

  @override
  bool canWrite(Object value, String? contentType) => value is Uint8List;

  @override
  ({List<int> bytes, String contentType}) write(
    Object value,
    String? contentType,
    TypeInfo<Object?>? type,
  ) => (
    bytes: value as Uint8List,
    contentType: contentType ?? MediaType.applicationOctetStream,
  );

  @override
  bool canRead(TypeInfo<Object?> type, String? contentType) =>
      type.type == Uint8List;

  @override
  Object? read(TypeInfo<Object?> type, Uint8List body, String? contentType) =>
      body;
}

/// Text as it is: writes a `String` in UTF-8 (as `text/plain` unless the
/// request says otherwise, so a JSON text written by hand keeps
/// `application/json`) and reads a body as a `String` in its charset.
///
/// Spring (Java): `StringHttpMessageConverter`.
final class StringHttpMessageConverter implements HttpMessageConverter {
  /// The converter; it has no settings.
  const StringHttpMessageConverter();

  @override
  bool canWrite(Object value, String? contentType) => value is String;

  @override
  ({List<int> bytes, String contentType}) write(
    Object value,
    String? contentType,
    TypeInfo<Object?>? type,
  ) => (
    bytes: utf8.encode(value as String),
    contentType: contentType ?? '${MediaType.textPlain}; charset=utf-8',
  );

  @override
  bool canRead(TypeInfo<Object?> type, String? contentType) =>
      type.type == String;

  @override
  Object? read(TypeInfo<Object?> type, Uint8List body, String? contentType) =>
      HttpResponse.decodeBody(body, contentType);
}

/// Writes a `MultipartBody` with its own `Content-Type` (which carries the
/// boundary); reads nothing.
///
/// Spring (Java): `FormHttpMessageConverter` writing a `MultiValueMap` of
/// parts as `multipart/form-data`.
final class MultipartHttpMessageConverter implements HttpMessageConverter {
  /// The converter; it has no settings.
  const MultipartHttpMessageConverter();

  @override
  bool canWrite(Object value, String? contentType) => value is MultipartBody;

  @override
  ({List<int> bytes, String contentType}) write(
    Object value,
    String? contentType,
    TypeInfo<Object?>? type,
  ) {
    final body = value as MultipartBody;
    return (bytes: body.encode(), contentType: body.contentType);
  }

  @override
  bool canRead(TypeInfo<Object?> type, String? contentType) => false;

  @override
  Object? read(TypeInfo<Object?> type, Uint8List body, String? contentType) =>
      throw UnsupportedError('MultipartHttpMessageConverter reads nothing');
}

/// Writes a `Map` as `application/x-www-form-urlencoded` when the request
/// has that `Content-Type`: one `name=value` per entry, one per item of a
/// list, `null` values left out, in the charset of the type (UTF-8 by
/// default). Reads nothing.
///
/// Spring (Java): `FormHttpMessageConverter` writing a `MultiValueMap`.
final class FormHttpMessageConverter implements HttpMessageConverter {
  /// The converter; it has no settings.
  const FormHttpMessageConverter();

  @override
  bool canWrite(Object value, String? contentType) =>
      value is Map && contentType != null && isFormContentType(contentType);

  @override
  ({List<int> bytes, String contentType}) write(
    Object value,
    String? contentType,
    TypeInfo<Object?>? type,
  ) {
    final encoding = MediaType.parse(contentType!).charset ?? utf8;
    String encode(Object? text) =>
        Uri.encodeQueryComponent('$text', encoding: encoding);
    final pairs = [
      for (final MapEntry(:key, :value) in (value as Map).entries)
        if (key != null && value != null)
          for (final item in value is Iterable ? value : [value])
            if (item != null) '${encode(key)}=${encode(item)}',
    ];
    return (bytes: ascii.encode(pairs.join('&')), contentType: contentType);
  }

  @override
  bool canRead(TypeInfo<Object?> type, String? contentType) => false;

  @override
  Object? read(TypeInfo<Object?> type, Uint8List body, String? contentType) =>
      throw UnsupportedError('FormHttpMessageConverter reads nothing');

  /// Whether [contentType] is `application/x-www-form-urlencoded`.
  static bool isFormContentType(String contentType) =>
      _typeOf(contentType) == MediaType.applicationFormUrlencoded;
}

/// JSON through the `ObjectMapper`: writes any value (as
/// `application/json` unless the request says another JSON type) and reads
/// a body of a JSON type (`application/json`, `application/*+json`) or of
/// none into the type asked for.
///
/// Spring (Java): `JacksonJsonHttpMessageConverter` (Jackson 3).
final class JsonHttpMessageConverter implements HttpMessageConverter {
  /// The converter writing and reading with [mapper].
  const JsonHttpMessageConverter(this.mapper);

  /// Writes and reads the JSON.
  final ObjectMapper mapper;

  @override
  bool canWrite(Object value, String? contentType) =>
      contentType == null || isJsonContentType(contentType);

  @override
  ({List<int> bytes, String contentType}) write(
    Object value,
    String? contentType,
    TypeInfo<Object?>? type,
  ) => (
    bytes: utf8.encode(
      type == null
          ? mapper.writeValueAsString(value)
          : jsonEncode(mapper.valueToTree(value, type)),
    ),
    contentType: contentType ?? MediaType.applicationJson,
  );

  @override
  bool canRead(TypeInfo<Object?> type, String? contentType) =>
      contentType == null || isJsonContentType(contentType);

  @override
  Object? read(TypeInfo<Object?> type, Uint8List body, String? contentType) =>
      mapper.readValue<Object?>(
        HttpResponse.decodeBody(body, contentType),
        type,
      );

  /// Whether [contentType] is a JSON type: `application/json` or a
  /// `+json` suffix (`application/problem+json`).
  static bool isJsonContentType(String contentType) {
    // The usual answer, without taking the text apart.
    if (contentType.startsWith(MediaType.applicationJson) &&
        (contentType.length == MediaType.applicationJson.length ||
            contentType.codeUnitAt(MediaType.applicationJson.length) == 0x3B)) {
      return true;
    }
    final type = _typeOf(contentType);
    return type == MediaType.applicationJson || type.endsWith('+json');
  }
}

// The type and subtype of a Content-Type, in lower case, without
// parameters.
String _typeOf(String contentType) {
  final semicolon = contentType.indexOf(';');
  return (semicolon < 0 ? contentType : contentType.substring(0, semicolon))
      .trim()
      .toLowerCase();
}
