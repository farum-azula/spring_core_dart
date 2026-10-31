import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/src/http_headers.dart';

/// The HTTP response being written for a request: status code, headers,
/// cookies, then the body.
///
/// Status and headers can change until the response is committed, that
/// is until the first body bytes, a [flush] or [close]; from then on they
/// are on their way to the client ([isCommitted]). The body can be sent in
/// parts, which is how server-sent events and large downloads stream.
///
/// Most controllers never touch it: they return a value or a
/// `ResponseEntity` and the web starter writes the response. Declare a
/// controller parameter of this type to write the answer yourself; a
/// `WebFilter` or a `HandlerMapping` always works with it.
///
/// ```dart
/// // A controller method that streams a CSV export line by line.
/// @GetMapping('/export.csv')
/// Future<void> export(ServerHttpResponse response) async {
///   response
///     ..statusCode = 200
///     ..headers.contentType = 'text/csv; charset=utf-8';
///   await for (final book in books.all()) {
///     response.write('${book.isbn},${book.title}\n');
///   }
///   await response.close();
/// }
/// ```
///
/// Spring (Java): `ServerHttpResponse` (Spring WebFlux), or
/// `HttpServletResponse` on the servlet stack.
abstract interface class ServerHttpResponse {
  /// The status code to send; 200 until set. Changing it after the
  /// response is committed has no effect.
  int get statusCode;
  set statusCode(int value);

  /// The headers to send. Changes made after the response is committed
  /// ([isCommitted]) no longer reach the client.
  HttpHeaders get headers;

  /// Sends [cookie] to the client in a `Set-Cookie` header. Call it before
  /// the response is committed.
  void addCookie(ResponseCookie cookie);

  /// Whether the status and headers are already sent, which happens at
  /// the first body bytes, a [flush] or [close]. A filter that wants to
  /// change headers checks this first.
  bool get isCommitted;

  /// Appends [bytes] to the body; commits the response first if needed.
  void add(List<int> bytes);

  /// Appends [text] to the body, encoded in UTF-8 whatever the
  /// `Content-Type` says.
  void write(String text);

  /// Sends what was written so far to the client now instead of when the
  /// buffer fills; used after each server-sent event so that it arrives
  /// at once.
  Future<void> flush();

  /// Appends every chunk of [stream] to the body; completes when the
  /// stream is done. Use it to send a file or a proxied body without
  /// holding it in memory.
  Future<void> addStream(Stream<List<int>> stream);

  /// Ends the response: commits it if nothing was written, then finishes
  /// the body. Every response must be closed once.
  Future<void> close();

  /// Completes when the response is over: closed, or the client went
  /// away. A long-running stream (server-sent events) listens to it to
  /// stop producing.
  Future<void> get done;
}

/// A cookie to send to the client, with its attributes (lifetime, scope,
/// security flags); its [toString] is the `Set-Cookie` header value.
///
/// Pass it to [ServerHttpResponse.addCookie]. The attributes decide how
/// the browser keeps and sends the cookie back: [httpOnly] hides it from
/// scripts, [secure] keeps it to HTTPS, [sameSite] limits cross-site
/// requests.
///
/// ```dart
/// // After a login: a session cookie scripts cannot read.
/// response.addCookie(ResponseCookie('session', id,
///     httpOnly: true, secure: true, sameSite: 'Lax', path: '/'));
///
/// // At logout: the same cookie with a zero age deletes it.
/// response.addCookie(
///     ResponseCookie('session', '', maxAge: Duration.zero, path: '/'));
/// ```
///
/// The name, value, domain and path are checked as Spring's
/// `ResponseCookie` checks them (RFC 6265): a character that would end
/// the value or start another attribute (`;`, `,`, a space, a quote, a
/// control character, non-ASCII) is an [ArgumentError], so text from a
/// request can never add attributes such as `; Domain=evil.example`.
/// Encode such values first (`Uri.encodeComponent`).
///
/// Spring (Java):
/// ```java
/// ResponseCookie cookie = ResponseCookie.from("session", id)
///     .httpOnly(true).secure(true).sameSite("Lax").path("/").build();
/// response.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());
/// ```
final class ResponseCookie {
  /// A cookie [name]=[value]. Without attributes it lasts for the browser
  /// session and is sent back to the path that set it.
  ///
  /// Throws an [ArgumentError] when [name] is not an RFC 2616 token, when
  /// [value] has a character a cookie value cannot have (outside a pair
  /// of double quotes around it all), or when [domain] or [path] has an
  /// invalid character; the same checks as Spring's `Rfc6265Utils`.
  ResponseCookie(
    this.name,
    this.value, {
    this.maxAge,
    this.domain,
    this.path,
    this.secure = false,
    this.httpOnly = false,
    this.sameSite,
    this.partitioned = false,
  }) {
    _checkName(name);
    _checkValue(value);
    _checkDomain(domain);
    _checkPath(path);
  }

  static const _separators = r'()<>@,;:\"/[]?={} ';
  static const _domainChars =
      '0123456789.-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static void _checkName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A cookie needs a name');
    }
    for (final c in name.codeUnits) {
      if (c <= 0x1F || c == 0x7F) {
        throw ArgumentError.value(
          name,
          'name',
          'RFC2616 token cannot have control chars',
        );
      }
      if (_separators.codeUnits.contains(c)) {
        throw ArgumentError.value(
          name,
          'name',
          'RFC2616 token cannot have separator chars such as '
              "'${String.fromCharCode(c)}'",
        );
      }
      if (c >= 0x80) {
        throw ArgumentError.value(
          name,
          'name',
          'RFC2616 token can only have US-ASCII',
        );
      }
    }
  }

  // The value is not echoed in the message: it may be a secret.
  static void _checkValue(String value) {
    var start = 0;
    var end = value.length;
    if (end > 1 && value.startsWith('"') && value.endsWith('"')) {
      start = 1;
      end--;
    }
    for (var i = start; i < end; i++) {
      final c = value.codeUnitAt(i);
      if (c < 0x21 || c == 0x22 || c == 0x2C || c == 0x3B || c == 0x5C) {
        throw ArgumentError(
          'RFC2616 cookie value cannot have the character 0x'
              '${c.toRadixString(16)} (at $i)',
          'value',
        );
      }
      if (c >= 0x7F) {
        throw ArgumentError(
          'RFC2616 cookie value can only have US-ASCII chars (0x'
              '${c.toRadixString(16)} at $i)',
          'value',
        );
      }
    }
  }

  static void _checkDomain(String? domain) {
    if (domain == null || domain.isEmpty) {
      return;
    }
    final first = domain[0];
    final last = domain[domain.length - 1];
    if (first == '-' || last == '.' || last == '-') {
      throw ArgumentError.value(
        domain,
        'domain',
        'Invalid first/last char in cookie domain',
      );
    }
    String? previous;
    for (final char in domain.split('')) {
      if (!_domainChars.contains(char) ||
          (previous == '.' && (char == '.' || char == '-')) ||
          (previous == '-' && char == '.')) {
        throw ArgumentError.value(
          domain,
          'domain',
          "invalid cookie domain char '$char'",
        );
      }
      previous = char;
    }
  }

  static void _checkPath(String? path) {
    if (path == null) {
      return;
    }
    for (final c in path.codeUnits) {
      if (c < 0x20 || c > 0x7E || c == 0x3B) {
        throw ArgumentError.value(
          path,
          'path',
          'Invalid cookie path char 0x${c.toRadixString(16)}',
        );
      }
    }
  }

  /// The name the browser stores the cookie under.
  final String name;

  /// The value, written as given (not encoded or quoted).
  final String value;

  /// How long the browser keeps the cookie, written as `Max-Age` (in
  /// seconds) and `Expires`. `Duration.zero` deletes it; `null` keeps it
  /// until the browser session ends.
  final Duration? maxAge;

  /// The `Domain` attribute: the host and its subdomains that receive the
  /// cookie; `null` for the current host only.
  final String? domain;

  /// The `Path` attribute: the path prefix that receives the cookie;
  /// `null` for the path of the request that set it.
  final String? path;

  /// The `Secure` attribute: the browser sends the cookie over HTTPS
  /// only. `false` by default.
  final bool secure;

  /// The `HttpOnly` attribute: scripts in the page cannot read the
  /// cookie. `false` by default.
  final bool httpOnly;

  /// The `SameSite` attribute: `Strict`, `Lax` or `None` (`None`
  /// requires [secure]); `null` leaves it out and the browser decides.
  final String? sameSite;

  /// The `Partitioned` attribute (CHIPS): a third-party cookie stored
  /// apart for each top-level site. `false` by default.
  final bool partitioned;

  /// The `Set-Cookie` header value, such as
  /// `session=abc; Max-Age=3600; Expires=...; Path=/; HttpOnly`. `Expires`
  /// is computed from the current time.
  @override
  String toString() {
    final out = StringBuffer('$name=$value');
    if (maxAge case final maxAge?) {
      out
        ..write('; Max-Age=${maxAge.inSeconds}')
        ..write(
          '; Expires='
          '${HttpHeaders.formatDate(DateTime.now().toUtc().add(maxAge))}',
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

/// A shortcut to answer with a complete text response in one call.
///
/// ```dart
/// // A HandlerMapping's handler refuses a request.
/// await response.send(403, 'Invalid CORS request');
/// ```
extension ServerHttpResponseWriting on ServerHttpResponse {
  /// Sends [status] with [text] as the body (UTF-8, `Content-Length` set)
  /// and closes the response. [contentType] defaults to
  /// `text/plain; charset=utf-8`; pass another for JSON or HTML text.
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

/// A [ServerHttpResponse] that forwards every call to another response,
/// so a subclass can change one part of the writing and keep the rest.
///
/// A filter uses it to watch or alter what the handler writes: add headers
/// just before the response is committed, drop the body of a `HEAD`
/// request, count the bytes sent. Extend it and override only what
/// changes.
///
/// ```dart
/// // For a HEAD request: the handler writes as for GET, no body is sent.
/// final class _NoBody extends ServerHttpResponseDecorator {
///   _NoBody(super.delegate);
///
///   @override
///   void add(List<int> bytes) {}
///
///   @override
///   void write(String text) {}
///
///   @override
///   Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
/// }
/// ```
///
/// Spring (Java): `ServerHttpResponseDecorator` (Spring WebFlux), or
/// `HttpServletResponseWrapper` on the servlet stack.
class ServerHttpResponseDecorator implements ServerHttpResponse {
  /// A response that behaves like [delegate] until a subclass overrides a
  /// member.
  ServerHttpResponseDecorator(this.delegate);

  /// The response every call is forwarded to.
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
