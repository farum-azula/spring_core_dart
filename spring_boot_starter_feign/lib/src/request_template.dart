import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';

/// A Feign request that is about to be sent, still open to changes.
///
/// A [RequestInterceptor] receives it to change what every call sends:
/// the URL, the headers, the body. It is built from the method's mapping
/// and the call's arguments; once the interceptors ran, the configured
/// default headers and query parameters are added and the request is
/// sent. Every attempt of a call, retries included, starts from a new
/// template, so changes never pile up.
///
/// [header] and [query] add a value, as in Feign; to replace a header,
/// remove it first (or call `headers.set`).
///
/// ```dart
/// // In an interceptor: a request id, the language, and a fresh token
/// // instead of whatever the call carried.
/// template
///   ..header('X-Request-Id', uuid())
///   ..query('lang', 'en')
///   ..removeHeader('Authorization')
///   ..header('Authorization', 'Bearer $token');
/// ```
///
/// Spring (Java):
/// ```java
/// template.header("X-Request-Id", uuid()).query("lang", "en")
///     .removeHeader("Authorization")
///     .header("Authorization", "Bearer " + token);
/// ```
class RequestTemplate {
  /// A request of [method] to [url], made by the method [methodKey] of
  /// the client [clientName], with no headers and no body unless given.
  /// The client creates templates; interceptors receive them.
  RequestTemplate({
    required this.method,
    required this.url,
    required this.methodKey,
    required this.clientName,
    HttpHeaders? headers,
    this.body,
  }) : headers = headers ?? HttpHeaders();

  /// The HTTP method; an interceptor may change it.
  HttpMethod method;

  /// The full URL, base URL, path and query included; an interceptor may
  /// replace it.
  Uri url;

  /// The request headers, to read or change.
  final HttpHeaders headers;

  /// The encoded body, or `null` for none. Replacing it does not change
  /// the `Content-Type` header.
  List<int>? body;

  /// Which method of which client makes the call, such as
  /// `CatalogClient#find(String)`; error decoders get the same key.
  final String methodKey;

  /// The client's `@FeignClient` name, such as `catalog`; an interceptor
  /// shared by all clients checks it to act on some only.
  final String clientName;

  /// Adds [value] to the values of the header [name], keeping those
  /// already there, as Feign's `header(name, values...)` does.
  void header(String name, String value) => headers.add(name, value);

  /// Removes every value of the header [name], as Feign's `removeHeader`
  /// does.
  void removeHeader(String name) => headers.remove(name);

  /// Adds the query parameter [name] with [value] at the end of [url],
  /// encoded as in a form (`+` for a space); the query already in [url]
  /// stays as written, and a parameter of that name is not replaced.
  void query(String name, String value) =>
      url = appendQuery(url, [(name, value)]);
}

/// [url] with [parameters] appended to its query, encoded as in a form
/// (`+` for a space); the query already in [url] is kept as written.
/// Internal: the library hides it.
Uri appendQuery(Uri url, Iterable<(String, String)> parameters) {
  final added = [
    for (final (name, value) in parameters)
      '${Uri.encodeQueryComponent(name)}=${Uri.encodeQueryComponent(value)}',
  ];
  if (added.isEmpty) {
    return url;
  }
  return url.replace(
    query: [
      if (url.hasQuery && url.query.isNotEmpty) url.query,
      ...added,
    ].join('&'),
  );
}

/// Code that changes every request of the Feign clients before it is
/// sent.
///
/// Use it for what all calls need and no method should repeat: an
/// authentication header, a tracing id, a common query parameter.
/// Declare it as a bean: every `RequestInterceptor` bean applies to all
/// clients, in `@Order` (check `template.clientName` to act on some
/// only, or declare it in a client's `configuration` class). Interceptors
/// run at every attempt of a call, so a token refreshed between retries
/// is used. [BasicAuthRequestInterceptor] and
/// [BearerTokenRequestInterceptor] cover the usual authentication.
///
/// ```dart
/// // Every call carries the id of the request that caused it.
/// final class RequestIds implements RequestInterceptor {
///   @override
///   void apply(RequestTemplate template) =>
///       template.header('X-Request-Id', currentRequestId());
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean RequestInterceptor tokens(TokenStore store) {
///   return template ->
///       template.header("Authorization", "Bearer " + store.token());
/// }
/// ```
abstract interface class RequestInterceptor {
  /// Changes [template] before it is sent. It may return a `Future`, for
  /// example to fetch a fresh token first; the call waits for it. An
  /// exception fails the call.
  FutureOr<void> apply(RequestTemplate template);
}

/// A [RequestInterceptor] that logs every call in with a user name and a
/// password (HTTP Basic authentication): it adds
/// `Authorization: Basic <base64 of user:password>`.
///
/// Use it for services protected by a fixed account. The credentials are
/// encoded in ISO-8859-1, as in Feign; pass `encoding: utf8` for names
/// or passwords with other characters.
///
/// ```dart
/// // The catalog's account, from the configuration.
/// @Bean()
/// RequestInterceptor catalogAuth(Environment env) =>
///     BasicAuthRequestInterceptor(
///       env.getRequiredProperty('catalog.user'),
///       env.getRequiredProperty('catalog.password'),
///     );
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// RequestInterceptor catalogAuth() {
///   return new BasicAuthRequestInterceptor("shop", "s3cret");
/// }
/// ```
class BasicAuthRequestInterceptor implements RequestInterceptor {
  /// Sends [username] and [password], encoded with [encoding]
  /// (ISO-8859-1 by default). Throws an `ArgumentError` for characters
  /// the encoding cannot represent.
  BasicAuthRequestInterceptor(
    String username,
    String password, {
    Encoding encoding = latin1,
  }) : _value = 'Basic ${base64Encode(encoding.encode('$username:$password'))}';

  final String _value;

  @override
  void apply(RequestTemplate template) =>
      template.header(HttpHeaders.authorizationHeader, _value);
}

/// A [RequestInterceptor] that sends an access token with every call:
/// `Authorization: Bearer <token>`.
///
/// Use it for APIs secured with OAuth 2 or similar tokens. It asks
/// [token] for the token at each request, retries included, so a token
/// that was refreshed meanwhile is the one sent. When [token] returns
/// `null` (nobody logged in), no header is added.
///
/// ```dart
/// // The user's token, refreshed by the session when it expires.
/// @Bean()
/// RequestInterceptor auth(UserSession session) =>
///     BearerTokenRequestInterceptor(() => session.accessToken());
/// ```
class BearerTokenRequestInterceptor implements RequestInterceptor {
  /// An interceptor that asks [token] for the token of each request.
  BearerTokenRequestInterceptor(this.token);

  /// Gives the current token, or `null` to send none; it may return a
  /// `Future`.
  final FutureOr<String?> Function() token;

  @override
  Future<void> apply(RequestTemplate template) async {
    final value = await token();
    if (value != null) {
      template.header(HttpHeaders.authorizationHeader, 'Bearer $value');
    }
  }
}
