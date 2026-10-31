import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/spring_web_dart.dart';

/// The name of the request attribute under which [readFormParameters]
/// keeps the fields it read, so the body is parsed only once per request.
const formParametersAttribute = 'spring.web.formParameters';

/// Reads the fields of an HTML form posted as
/// `application/x-www-form-urlencoded` (`name=ada&role=admin`).
///
/// A request body can be read only once, yet several parts of the server
/// need the form: a login filter reads the user name and password, a
/// CSRF filter reads the token, a controller binds `@RequestParam`
/// values. This function reads the body once and returns two things: a
/// request to hand on, which replays the same body to whoever reads it
/// next, and the fields by name (a name may repeat). The fields are also
/// kept in a request attribute ([formParametersAttribute]), so a second
/// call returns them without reading again.
///
/// For a request of another content type, the result is [request] itself
/// and `null`. The body is read up to [maxLength] bytes (1 MiB by
/// default); a larger form is a 413 `ResponseStatusException`. A form
/// that is not UTF-8, or has a malformed `%` escape (`title=%FF`,
/// `title=%G1`), is a 400 `ResponseStatusException`, as Tomcat answers.
///
/// ```dart
/// // A filter checks a form field and passes on the replaying request,
/// // so the controller can still read the body.
/// final (current, form) = await readFormParameters(request);
/// final token = form?['_csrf']?.firstOrNull;
/// ...
/// return chain.doFilter(current, response);
/// ```
Future<(ServerHttpRequest, Map<String, List<String>>?)> readFormParameters(
  ServerHttpRequest request, {
  int maxLength = 1 << 20,
}) async {
  const attribute = formParametersAttribute;
  final cached = request.attributes[attribute];
  if (cached is Map<String, List<String>>) {
    return (request, cached);
  }
  final type = request.contentType;
  if (type == null ||
      type.type != 'application' ||
      type.subtype != 'x-www-form-urlencoded') {
    return (request, null);
  }
  final Uint8List bytes;
  try {
    bytes = await request.readBodyBytes(maxLength: maxLength);
  } on PayloadTooLargeException {
    throw ResponseStatusException(
      HttpStatus.contentTooLarge,
      'The form is too large',
    );
  }
  final fields = <String, List<String>>{};
  Never invalid() => throw ResponseStatusException(
    HttpStatus.badRequest,
    'The form is not valid UTF-8 or has a malformed %-escape',
  );
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    invalid();
  }
  String decode(String part) {
    try {
      return Uri.decodeQueryComponent(part);
    } on ArgumentError {
      invalid();
    } on FormatException {
      invalid();
    }
  }

  for (final pair in text.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final separator = pair.indexOf('=');
    final name = decode(separator < 0 ? pair : pair.substring(0, separator));
    final value = separator < 0 ? '' : decode(pair.substring(separator + 1));
    (fields[name] ??= []).add(value);
  }
  final replay = _ReplayedBodyRequest(request, bytes);
  replay.attributes[attribute] = fields;
  return (replay, fields);
}

final class _ReplayedBodyRequest extends ServerHttpRequestDecorator {
  _ReplayedBodyRequest(super.delegate, this._bytes);

  final Uint8List _bytes;

  @override
  Stream<Uint8List> get body => Stream.value(_bytes);
}
