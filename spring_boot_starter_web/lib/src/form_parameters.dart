import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/spring_web_dart.dart';

/// The request attribute caching the form fields of a request.
const formParametersAttribute = 'spring.web.formParameters';

/// The form fields of a `application/x-www-form-urlencoded` request,
/// read once (at most [maxLength] bytes) and kept: the request handed on
/// replays its body, so a controller still reads it. `null` for other
/// requests.
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
  final text = utf8.decode(bytes, allowMalformed: true);
  for (final pair in text.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final separator = pair.indexOf('=');
    String decode(String part) {
      try {
        return Uri.decodeQueryComponent(part);
      } on ArgumentError {
        return part;
      }
    }

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
