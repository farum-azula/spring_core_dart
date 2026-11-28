import 'dart:async';

import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Puts the key and the token of [credentials] on each request of a
/// `RestClient` that calls the project (the headers `apikey` and
/// `Authorization`), replacing whatever the request had, then [headers].
/// The starter adds it last to its clients (`SupabaseHttp`'s and the Edge
/// Functions group's), so that no other interceptor decides them, and it
/// runs again for each attempt of a retried call, so a refreshed token
/// reaches the retry.
///
/// A request for another origin than [origin] (the scheme, host and port
/// of `spring.supabase.url`) fails with a [StateError] before anything is
/// sent: the key and the token go to the project only.
final class SupabaseCredentialsInterceptor
    implements ClientHttpRequestInterceptor {
  /// The interceptor of the calls of [origin] with [credentials].
  const SupabaseCredentialsInterceptor({
    required this.credentials,
    required this.origin,
    this.headers = const {},
  });

  /// The request attribute whose `String` value is sent as the bearer
  /// token instead of the token of [credentials] (Auth's own calls, which
  /// make the token).
  static const bearerAttribute = 'supabase.bearer';

  /// Where the key and the token come from.
  final SupabaseCredentials credentials;

  /// The project's address; only its scheme, host and port are compared.
  final Uri origin;

  /// More headers set on every request, after the credentials.
  final Map<String, String> headers;

  @override
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) async {
    final url = request.url;
    if (url.scheme != origin.scheme ||
        url.host != origin.host ||
        url.port != origin.port) {
      throw StateError(
        'The key and the token of the Supabase project are sent to '
        '${origin.scheme}://${origin.host}:${origin.port} only, and '
        '${request.method.value} ${url.scheme}://${url.host}:${url.port}'
        '${url.path} is another address',
      );
    }
    _set(
      request.headers,
      switch (request.attributes[bearerAttribute]) {
        final String token => token,
        _ => await credentials.accessToken(),
      },
    );
    return await execution.execute(request, body);
  }

  /// Sets the key, the token ([bearer] instead of the credentials' when
  /// given) and [headers] in [target].
  Future<void> authorize(HttpHeaders target, {String? bearer}) async =>
      _set(target, bearer ?? await credentials.accessToken());

  void _set(HttpHeaders target, String token) {
    target
      ..set('apikey', credentials.apiKey)
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    headers.forEach(target.set);
  }
}
