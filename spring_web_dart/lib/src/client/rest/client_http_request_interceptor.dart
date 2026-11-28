import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';

/// Runs around every request of a `RestClient`: it may change the request
/// (a token, a trace id), answer by itself, or look at the response, and
/// calls [ClientHttpRequestExecution.execute] to go on to the next
/// interceptor and finally the transport.
///
/// Interceptors run in the order they were added to the builder, the
/// first outermost. Each call of `execute` sends the request again, so an
/// interceptor may retry; `body` is the encoded body, sent again as it is.
///
/// For a streamed answer (`eventStream`, `bodyStream`) the response an
/// interceptor sees carries the status and headers only: the body arrives
/// afterwards, to the stream's listener. An error status is read whole, so
/// there the interceptor sees its body.
///
/// ```dart
/// final client = RestClient.builder()
///     .requestInterceptor(ClientHttpRequestInterceptor.of(
///       (request, body, execution) {
///         request.headers.set('X-Request-Id', ids.next());
///         return execution.execute(request, body);
///       },
///     ))
///     .build();
/// ```
///
/// Spring (Java): `ClientHttpRequestInterceptor`:
/// ```java
/// RestClient.builder().requestInterceptor((request, body, execution) -> {
///   request.getHeaders().set("X-Request-Id", ids.next());
///   return execution.execute(request, body);
/// });
/// ```
abstract interface class ClientHttpRequestInterceptor {
  /// The interceptor that calls [intercept].
  const factory ClientHttpRequestInterceptor.of(
    Future<HttpResponse> Function(
      HttpRequest request,
      List<int>? body,
      ClientHttpRequestExecution execution,
    )
    intercept,
  ) = _FunctionInterceptor;

  /// Handles [request] with [body]: usually changes it and returns
  /// `execution.execute(request, body)`.
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  );
}

/// The rest of the chain, for an interceptor: the interceptors after it,
/// then the transport.
///
/// Spring (Java): `ClientHttpRequestExecution`.
abstract interface class ClientHttpRequestExecution {
  /// Sends [request] with [body] (which replaces the request's own) on to
  /// the next interceptor or the transport, and returns the response.
  Future<HttpResponse> execute(HttpRequest request, List<int>? body);
}

final class _FunctionInterceptor implements ClientHttpRequestInterceptor {
  const _FunctionInterceptor(this._intercept);

  final Future<HttpResponse> Function(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  )
  _intercept;

  @override
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) => _intercept(request, body, execution);
}
