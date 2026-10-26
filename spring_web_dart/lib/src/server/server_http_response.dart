import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/src/http_headers.dart';

/// The response a server sends for a [ServerHttpRequest], like Spring's
/// `ServerHttpResponse`: status and headers until the first body bytes are
/// written ([isCommitted]), then the body, possibly in parts (server-sent
/// events, downloads).
///
/// ```dart
/// response
///   ..statusCode = 200
///   ..headers.contentType = 'text/plain; charset=utf-8'
///   ..write('hello');
/// await response.close();
/// ```
abstract interface class ServerHttpResponse {
  /// The status code (200 until set).
  int get statusCode;
  set statusCode(int value);

  /// The response headers; changes after [isCommitted] are ignored.
  HttpHeaders get headers;

  /// Adds a `Set-Cookie` header.
  void addCookie(ResponseCookie cookie);

  /// Whether the status and headers were sent (the first body bytes, a
  /// [flush], or [close]).
  bool get isCommitted;

  /// Writes [bytes] of the body.
  void add(List<int> bytes);

  /// Writes [text] in UTF-8.
  void write(String text);

  /// Sends what was written so far (a server-sent event right away).
  Future<void> flush();

  /// Writes every chunk of [stream].
  Future<void> addStream(Stream<List<int>> stream);

  /// Ends the response.
  Future<void> close();

  /// Completes when the response ended: closed, or the client went away
  /// (an event stream stops then).
  Future<void> get done;
}

/// A `Set-Cookie` value, like Spring's `ResponseCookie`.
///
/// ```dart
/// response.addCookie(ResponseCookie('session', id,
///     httpOnly: true, secure: true, sameSite: 'Lax', path: '/'));
/// ```
final class ResponseCookie {
  /// A cookie [name]=[value] with its attributes.
  const ResponseCookie(
    this.name,
    this.value, {
    this.maxAge,
    this.domain,
    this.path,
    this.secure = false,
    this.httpOnly = false,
    this.sameSite,
    this.partitioned = false,
  });

  /// The cookie name.
  final String name;

  /// The value.
  final String value;

  /// How long it lives; `Duration.zero` deletes it, `null` keeps it for
  /// the browser session.
  final Duration? maxAge;

  /// The `Domain` attribute.
  final String? domain;

  /// The `Path` attribute.
  final String? path;

  /// The `Secure` attribute (sent over HTTPS only).
  final bool secure;

  /// The `HttpOnly` attribute (hidden from scripts).
  final bool httpOnly;

  /// The `SameSite` attribute: `Strict`, `Lax` or `None`.
  final String? sameSite;

  /// The `Partitioned` attribute.
  final bool partitioned;

  /// The header value.
  @override
  String toString() {
    final out = StringBuffer('$name=$value');
    if (maxAge case final maxAge?) {
      out.write('; Max-Age=${maxAge.inSeconds}');
      out.write(
        '; Expires=${HttpHeaders.formatDate(DateTime.now().toUtc().add(maxAge))}',
      );
    }
    if (domain case final domain?) {
      out.write('; Domain=$domain');
    }
    if (path case final path?) {
      out.write('; Path=$path');
    }
    if (secure) {
      out.write('; Secure');
    }
    if (httpOnly) {
      out.write('; HttpOnly');
    }
    if (sameSite case final sameSite?) {
      out.write('; SameSite=$sameSite');
    }
    if (partitioned) {
      out.write('; Partitioned');
    }
    return out.toString();
  }
}

/// Writes text and JSON to a [ServerHttpResponse].
extension ServerHttpResponseWriting on ServerHttpResponse {
  /// Sets the status, `Content-Type` and body [text], and closes.
  Future<void> send(
    int status,
    String text, {
    String contentType = 'text/plain; charset=utf-8',
  }) {
    final bytes = utf8.encode(text);
    statusCode = status;
    headers
      ..contentType = contentType
      ..contentLength = bytes.length;
    add(bytes);
    return close();
  }
}

/// A [ServerHttpResponse] passing everything to [delegate]; override what
/// changes, like Spring's `ServerHttpResponseDecorator`.
class ServerHttpResponseDecorator implements ServerHttpResponse {
  /// Wraps [delegate].
  ServerHttpResponseDecorator(this.delegate);

  /// The wrapped response.
  final ServerHttpResponse delegate;

  @override
  int get statusCode => delegate.statusCode;

  @override
  set statusCode(int value) => delegate.statusCode = value;

  @override
  HttpHeaders get headers => delegate.headers;

  @override
  void addCookie(ResponseCookie cookie) => delegate.addCookie(cookie);

  @override
  bool get isCommitted => delegate.isCommitted;

  @override
  void add(List<int> bytes) => delegate.add(bytes);

  @override
  void write(String text) => delegate.write(text);

  @override
  Future<void> flush() => delegate.flush();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      delegate.addStream(stream);

  @override
  Future<void> close() => delegate.close();

  @override
  Future<void> get done => delegate.done;
}
