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

/// An HTTP request received by the application: method, URL, headers,
/// cookies and a body that can be read once.
///
/// It hides which server received the request: the web starter's
/// `dart:io` server and `MockMvc` (with a `MockServerHttpRequest`) both
/// provide one, so filters and controllers run the same in production and
/// in tests.
///
/// Most controllers never touch it: they take the values they need with
/// `@PathVariable`, `@RequestParam`, `@RequestHeader` or `@RequestBody`.
/// Declare a parameter of this type when a method needs the raw request;
/// a `WebFilter` or a `HandlerMapping` always works with it.
///
/// ```dart
/// // A controller method that needs the client's address and a header.
/// @GetMapping('/whoami')
/// String whoami(ServerHttpRequest request) =>
///     '${request.remoteAddress} ${request.headers['User-Agent']}';
/// ```
///
/// Spring (Java): `ServerHttpRequest` (Spring WebFlux), or
/// `HttpServletRequest` on the servlet stack:
/// ```java
/// @GetMapping("/whoami")
/// String whoami(HttpServletRequest request) {
///   return request.getRemoteAddr() + " " + request.getHeader("User-Agent");
/// }
/// ```
abstract interface class ServerHttpRequest {
  /// The HTTP method of the request.
  HttpMethod get method;

  /// The full URL as the client asked for it: scheme, host, port, path
  /// and query (on the web starter's server, the host is the one of the
  /// `Host` header).
  Uri get uri;

  /// The path without the query, still percent-encoded
  /// (`/api/books/978-0`). Behind a `server.servlet.context-path`, filters
  /// and handlers see the path without that prefix.
  String get path;

  /// The headers the client sent. Treat them as read-only; to change
  /// them for the rest of the chain, wrap the request in a
  /// [ServerHttpRequestDecorator].
  HttpHeaders get headers;

  /// The query parameters, decoded, each name with all its values in
  /// order (`?tag=a&tag=b` gives `{'tag': ['a', 'b']}`).
  Map<String, List<String>> get queryParameters;

  /// The cookies of the `Cookie` header, by name (quotes around a value
  /// removed).
  Map<String, String> get cookies;

  /// The IP address of the client, or `null` when the server does not
  /// know it. Behind a proxy this is the proxy's address.
  String? get remoteAddress;

  /// Whether the request came over TLS (`https` or `wss`).
  bool get isSecure;

  /// A mutable map where filters and handlers leave values for the code
  /// that runs later on the same request, such as a parsed form or a
  /// trace id. It lives as long as the request.
  Map<String, Object?> get attributes;

  /// The authenticated user or client, or `null` while nobody is
  /// authenticated. An authentication filter (for example the security
  /// starter's) sets it; a controller parameter of type `Principal`
  /// receives it.
  Principal? get principal;
  set principal(Principal? value);

  /// The body as a stream of bytes. It can be listened to only once: a
  /// second read throws a `StateError`. On the web starter's server a body
  /// above `server.max-http-request-body-size` ends with a
  /// [PayloadTooLargeException], whatever its `Content-Type` (the
  /// starter's multipart resolver reads uploads with their own limit,
  /// `spring.servlet.multipart.max-request-size`). For small bodies,
  /// [ServerHttpRequestBody.readBodyBytes] and
  /// [ServerHttpRequestBody.readBodyText] are simpler.
  Stream<Uint8List> get body;

  /// Whether the client asks to open a WebSocket on this request
  /// (`Upgrade: websocket`).
  bool get isWebSocketUpgrade;

  /// Accepts the WebSocket handshake and returns the open connection.
  ///
  /// [protocol] is the sub-protocol the server picked among those the
  /// client listed in `Sec-WebSocket-Protocol`, or `null` for none. Throws
  /// a `StateError` when the request is not a handshake
  /// ([isWebSocketUpgrade] is false), and an `ErrorResponseException`
  /// when the server refuses the handshake's details (the web starter's
  /// server: a 400 for a missing, repeated or malformed
  /// `Sec-WebSocket-Key`, a 426 for a `Sec-WebSocket-Version` other than
  /// 13). After the upgrade the HTTP response
  /// must not be used any more. The WebSocket starter calls this for its
  /// endpoints; applications rarely do.
  Future<WebSocketSession> upgradeToWebSocket({String? protocol});
}

/// Helpers to read the body and the `Content-Type` of a
/// [ServerHttpRequest] without handling the byte stream yourself.
///
/// ```dart
/// // The handler of a HandlerMapping reads a webhook's payload itself.
/// final webhook = FunctionHttpHandler((request, response) async {
///   final payload = await request.readBodyText(maxLength: 64 * 1024);
///   await events.publish(payload);
///   await response.send(202, 'accepted');
/// });
/// ```
extension ServerHttpRequestBody on ServerHttpRequest {
  /// The `Content-Type` header parsed, or `null` when it is missing or
  /// is not a valid media type.
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

  /// Reads the whole body into memory. Throws a [PayloadTooLargeException]
  /// as soon as it grows past [maxLength] bytes (no limit when `null`).
  /// Like [ServerHttpRequest.body], it can be called only once.
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

  /// Reads the whole body as text, decoded with the `charset` of the
  /// `Content-Type`: ISO-8859-1 and US-ASCII are recognised, anything else
  /// (or no charset) is read as UTF-8, with malformed bytes replaced.
  /// [maxLength] limits the size in bytes as in [readBodyBytes].
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

/// Thrown while reading a request body that is longer than allowed.
///
/// The web starter's server raises it from [ServerHttpRequest.body] when
/// a body passes `server.max-http-request-body-size` (10 MB by default),
/// and [ServerHttpRequestBody.readBodyBytes] raises it past its
/// `maxLength`. The web starter turns it into a 413 response, so a
/// controller does not need to catch it.
class PayloadTooLargeException implements Exception {
  /// A body that went past [maxLength] bytes.
  PayloadTooLargeException(this.maxLength);

  /// The limit that was passed, in bytes.
  final int maxLength;

  @override
  String toString() =>
      'PayloadTooLargeException: the body is larger than $maxLength bytes';
}

/// Reads the cookies of `Cookie` header [values] (`a=1; b=2`) into a map
/// from name to value.
///
/// Servers use it to fill [ServerHttpRequest.cookies]. Quotes around a
/// value are removed, parts without `=` are skipped, and a name that
/// appears twice keeps its last value.
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

/// A [ServerHttpRequest] that forwards every call to another request, so
/// a subclass can change one part of a request and keep the rest.
///
/// A filter uses it to hand a modified request down the chain: a
/// different path, extra headers, a body that was already read and must
/// be replayed. Extend it and override only what changes.
///
/// ```dart
/// // A filter strips the `/v1` prefix before the controllers see the path.
/// final class _Unversioned extends ServerHttpRequestDecorator {
///   _Unversioned(super.delegate);
///
///   @override
///   String get path => delegate.path.substring('/v1'.length);
/// }
/// ```
///
/// Spring (Java): `ServerHttpRequestDecorator` (Spring WebFlux), or
/// `HttpServletRequestWrapper` on the servlet stack.
class ServerHttpRequestDecorator implements ServerHttpRequest {
  /// A request that behaves like [delegate] until a subclass overrides a
  /// member.
  ServerHttpRequestDecorator(this.delegate);

  /// The request every call is forwarded to.
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
