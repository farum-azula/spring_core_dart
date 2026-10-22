import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';

/// The request about to be sent, as [RequestInterceptor]s see it (Feign's
/// `RequestTemplate`): change the URL, headers or body.
///
/// ```dart
/// template
///   ..header('X-Request-Id', uuid())
///   ..query('lang', 'en');
/// ```
///
/// Spring (Java):
/// ```java
/// template.header("X-Request-Id", uuid()).query("lang", "en");
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

  /// Sets header [name] to [value] (replacing it).
  void header(String name, String value) => headers.set(name, value);

  /// Adds query parameter [name] = [value].
  void query(String name, String value) {
    final all = {
      for (final MapEntry(:key, :value) in url.queryParametersAll.entries)
        key: [...value],
    };
    (all[name] ??= []).add(value);
    url = url.replace(queryParameters: all);
  }
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
///   return template -> template.header("Authorization", "Bearer " + store.token());
/// }
/// ```
abstract interface class RequestInterceptor {
  /// Changes [template]; may be asynchronous (e.g. to refresh a token).
  FutureOr<void> apply(RequestTemplate template);
}

/// Adds `Authorization: Basic ...` (Feign's
/// `BasicAuthRequestInterceptor`).
///
/// ```dart
/// @Bean()
/// RequestInterceptor auth() => BasicAuthRequestInterceptor('shop', 's3cret');
/// ```
class BasicAuthRequestInterceptor implements RequestInterceptor {
  /// Sends [username] and [password].
  BasicAuthRequestInterceptor(String username, String password)
    : _value = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  final String _value;

  @override
  void apply(RequestTemplate template) =>
      template.header(HttpHeaders.authorization, _value);
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
      template.header(HttpHeaders.authorization, 'Bearer $value');
    }
  }
}
