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
/// An interceptor gets the body as bytes, as in Spring. A streamed body
/// (a `Stream`, a `StreamingBody`, a `MultipartBody` with a streamed part)
/// is therefore read whole into memory before the first interceptor runs,
/// unless every interceptor of the client is a
/// [StreamingClientHttpRequestInterceptor], which lets it through as a
/// stream. A client without interceptors always streams it.
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

/// A [ClientHttpRequestInterceptor] that never reads the body, so a
/// streamed one passes it as a stream instead of being read whole into
/// memory first: one that adds a header, a token, a trace id, or looks at
/// the response.
///
/// When every interceptor of a `RestClient` is one, a streamed body
/// reaches them as `request.streamingBody`, with `null` for `body`, and
/// each passes `body` on as it got it (or bytes of its own, which then
/// replace the stream). A body in bytes reaches them as bytes. Calling
/// `execute` a second time sends the body again: a stream read once then
/// fails with a `NonRepeatableBodyException`, so an interceptor that
/// sends again checks `request.streamingBody?.isRepeatable` first. The
/// family's own interceptors are of this kind (the OAuth2 client's, the
/// Supabase starter's credentials).
///
/// ```dart
/// final client = RestClient.builder()
///     .requestInterceptor(StreamingClientHttpRequestInterceptor.of(
///       (request, body, execution) {
///         request.headers.set('X-Request-Id', ids.next());
///         return execution.execute(request, body);
///       },
///     ))
///     .build();
/// ```
///
/// Spring (Java): no counterpart. Spring's interceptors always get the
/// body as a `byte[]`: `InterceptingClientHttpRequest` buffers it, and a
/// large upload goes through a client without interceptors, or through
/// `WebClient` and its `ExchangeFilterFunction`.
abstract interface class StreamingClientHttpRequestInterceptor
    implements ClientHttpRequestInterceptor {
  /// The interceptor that calls [intercept], which never reads the body.
  const factory StreamingClientHttpRequestInterceptor.of(
    Future<HttpResponse> Function(
      HttpRequest request,
      List<int>? body,
      ClientHttpRequestExecution execution,
    )
    intercept,
  ) = _FunctionStreamingInterceptor;
}

/// The rest of the chain, for an interceptor: the interceptors after it,
/// then the transport.
///
/// Spring (Java): `ClientHttpRequestExecution`.
abstract interface class ClientHttpRequestExecution {
  /// Sends [request] with [body] (which replaces the request's own) on to
  /// the next interceptor or the transport, and returns the response. With
  /// `null` for [body], the request's `streamingBody` is sent when it has
  /// one.
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

final class _FunctionStreamingInterceptor extends _FunctionInterceptor
    implements StreamingClientHttpRequestInterceptor {
  const _FunctionStreamingInterceptor(super._intercept);
}
