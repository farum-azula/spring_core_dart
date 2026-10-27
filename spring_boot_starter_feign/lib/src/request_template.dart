import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';

/// The request about to be sent, as [RequestInterceptor]s see it (Feign's
/// `RequestTemplate`): change the URL, headers or body. Every attempt of a
/// call (retries too) starts from a new template.
///
/// [header] and [query] add a value like Feign's; to replace a header,
/// remove it first (or use [headers]`.set`).
///
/// ```dart
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
  /// A request of [method] to [url] by the method [methodKey] of client
  /// [clientName].
  RequestTemplate({
    required this.method,
    required this.url,
    required this.methodKey,
    required this.clientName,
    HttpHeaders? headers,
    this.body,
  }) : headers = headers ?? HttpHeaders();

  /// The HTTP method.
  HttpMethod method;

  /// The full URL, query included.
  Uri url;

  /// The headers.
  final HttpHeaders headers;

  /// The body bytes, if any.
  List<int>? body;

  /// `CatalogClient#find(String)`.
  final String methodKey;

  /// The `@FeignClient` name.
  final String clientName;

  /// Adds [value] to the values of header [name], like Feign's
  /// `header(name, values...)`.
  void header(String name, String value) => headers.add(name, value);

  /// Removes every value of header [name], like Feign's `removeHeader`.
  void removeHeader(String name) => headers.remove(name);

  /// Adds query parameter [name] = [value] (the query already in [url]
  /// stays as written).
  void query(String name, String value) =>
      url = appendQuery(url, [(name, value)]);
}

/// [url] with [parameters] appended to its query, encoded like a form
/// (`+` for spaces); the query already in [url] is kept as written.
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

/// Changes every request of the Feign clients before it is sent, like
/// Feign's `RequestInterceptor` — authentication headers, tracing ids,
/// common query parameters. Every `RequestInterceptor` bean applies to all
/// clients (check `template.clientName` to limit it).
///
/// ```dart
/// @Bean()
/// RequestInterceptor tokens(TokenStore store) =>
///     BearerTokenRequestInterceptor(() => store.accessToken);
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
  /// Changes [template]; may be asynchronous (e.g. to refresh a token).
  FutureOr<void> apply(RequestTemplate template);
}

/// Adds `Authorization: Basic ...` (Feign's
/// `BasicAuthRequestInterceptor`); pass `encoding: utf8` for names or
/// passwords outside ISO-8859-1, like Feign's `Charset` argument.
///
/// ```dart
/// @Bean()
/// RequestInterceptor auth() => BasicAuthRequestInterceptor('shop', 's3cret');
/// ```
class BasicAuthRequestInterceptor implements RequestInterceptor {
  /// Sends [username] and [password], encoded with [encoding] (ISO-8859-1
  /// by default, like Feign; throws `ArgumentError` for characters it
  /// cannot encode).
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

/// Adds `Authorization: Bearer <token>`, asking [token] for each request
/// (no header when it returns `null`).
///
/// ```dart
/// BearerTokenRequestInterceptor(() async => (await auth.session()).token)
/// ```
class BearerTokenRequestInterceptor implements RequestInterceptor {
  /// Uses the token [token] returns.
  BearerTokenRequestInterceptor(this.token);

  /// The current token.
  final FutureOr<String?> Function() token;

  @override
  Future<void> apply(RequestTemplate template) async {
    final value = await token();
    if (value != null) {
      template.header(HttpHeaders.authorizationHeader, 'Bearer $value');
    }
  }
}
