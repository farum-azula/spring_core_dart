import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/core.dart' show Principal;
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/media_type.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

// Principal was declared here before it moved to spring_core_dart: code
// generated then imports it from this library.
export 'package:spring_core_dart/core.dart' show Principal;

/// An incoming HTTP request as a server hands it to the application, like
/// Spring's `ServerHttpRequest`. The web starter's server (`dart:io`) and
/// `MockMvc` both implement it, so filters and controllers never see the
/// server behind it.
abstract interface class ServerHttpRequest {
  /// The method (`GET`, `POST`, ...).
  HttpMethod get method;

  /// The full URI: scheme, host, port, path and query.
  Uri get uri;

  /// The path, still percent-encoded (`/api/books/978-0`).
  String get path;

  /// The request headers (read-only).
  HttpHeaders get headers;

  /// The query parameters, each with all its values.
  Map<String, List<String>> get queryParameters;

  /// The cookies sent, by name.
  Map<String, String> get cookies;

  /// The client's address, when the server knows it.
  String? get remoteAddress;

  /// Whether the request came over TLS (`https`, `wss`).
  bool get isSecure;

  /// Values filters and handlers attach to the request (Spring's request
  /// attributes).
  Map<String, Object?> get attributes;

  /// Who sent the request; set by an authentication filter.
  Principal? get principal;
  set principal(Principal? value);

  /// The body, read once.
  Stream<Uint8List> get body;

  /// Whether this is a WebSocket handshake (`Upgrade: websocket`).
  bool get isWebSocketUpgrade;

  /// Accepts the WebSocket handshake and returns the open session;
  /// [protocol] is the sub-protocol chosen from the client's
  /// `Sec-WebSocket-Protocol`. The response must not be used afterwards.
  Future<WebSocketSession> upgradeToWebSocket({String? protocol});
}

/// Reading the body of a [ServerHttpRequest].
extension ServerHttpRequestBody on ServerHttpRequest {
  /// The `Content-Type`, or `null` when absent or malformed.
  MediaType? get contentType {
    final value = headers.contentType;
    if (value == null) {
      return null;
    }
    try {
      return MediaType.parse(value);
    } on InvalidMediaTypeException {
      return null;
    }
  }

  /// The whole body as bytes; more than [maxLength] bytes throws a
  /// [PayloadTooLargeException].
  Future<Uint8List> readBodyBytes({int? maxLength}) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body) {
      builder.add(chunk);
      if (maxLength != null && builder.length > maxLength) {
        throw PayloadTooLargeException(maxLength);
      }
    }
    return builder.takeBytes();
  }

  /// The whole body as text, in the `charset` of the `Content-Type`
  /// (UTF-8 by default).
  Future<String> readBodyText({int? maxLength}) async {
    final bytes = await readBodyBytes(maxLength: maxLength);
    final charset = contentType?.getParameter('charset')?.toLowerCase();
    return switch (charset) {
      'iso-8859-1' || 'latin1' || 'latin-1' => latin1.decode(bytes),
      'us-ascii' || 'ascii' => ascii.decode(bytes, allowInvalid: true),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  }
}

/// A request body longer than the server accepts.
class PayloadTooLargeException implements Exception {
  /// The body exceeded [maxLength] bytes.
  PayloadTooLargeException(this.maxLength);

  /// The largest accepted body, in bytes.
  final int maxLength;

  @override
  String toString() =>
      'PayloadTooLargeException: the body is larger than $maxLength bytes';
}

/// Parses a `Cookie` header (`a=1; b=2`) into a map.
Map<String, String> parseCookieHeader(Iterable<String> values) => {
  for (final value in values)
    for (final part in value.split(';'))
      if (part.indexOf('=') case final eq when eq > 0)
        part.substring(0, eq).trim(): _unquote(part.substring(eq + 1).trim()),
};

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

/// A [ServerHttpRequest] passing everything to [delegate]; override what
/// changes, like Spring's `ServerHttpRequestDecorator` (a filter changing
/// the path, the headers, the principal).
class ServerHttpRequestDecorator implements ServerHttpRequest {
  /// Wraps [delegate].
  ServerHttpRequestDecorator(this.delegate);

  /// The wrapped request.
  final ServerHttpRequest delegate;

  @override
  HttpMethod get method => delegate.method;

  @override
  Uri get uri => delegate.uri;

  @override
  String get path => delegate.path;

  @override
  HttpHeaders get headers => delegate.headers;

  @override
  Map<String, List<String>> get queryParameters => delegate.queryParameters;

  @override
  Map<String, String> get cookies => delegate.cookies;

  @override
  String? get remoteAddress => delegate.remoteAddress;

  @override
  bool get isSecure => delegate.isSecure;

  @override
  Map<String, Object?> get attributes => delegate.attributes;

  @override
  Principal? get principal => delegate.principal;

  @override
  set principal(Principal? value) => delegate.principal = value;

  @override
  Stream<Uint8List> get body => delegate.body;

  @override
  bool get isWebSocketUpgrade => delegate.isWebSocketUpgrade;

  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) =>
      delegate.upgradeToWebSocket(protocol: protocol);
}
