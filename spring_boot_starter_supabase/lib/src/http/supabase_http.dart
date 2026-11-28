import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_credentials_interceptor.dart';
import 'package:spring_boot_starter_supabase/src/http/timed_request.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';
import 'package:spring_boot_starter_supabase/src/supabase_exception.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The HTTP services of a Supabase project, each under its own path of
/// `spring.supabase.url`.
enum SupabaseService {
  /// The database's REST API (PostgREST): `/rest/v1`.
  rest,

  /// Auth (GoTrue): `/auth/v1`.
  auth,

  /// Storage: `/storage/v1`.
  storage,

  /// Edge Functions: `/functions/v1`.
  functions;

  /// The path of the service under the project's address.
  String get path => '/$name/v1';
}

/// The HTTP client every part of the starter calls Supabase through (the
/// bean `supabaseHttp`): it knows the project's address, puts the key and
/// the token of [SupabaseCredentials] on each call, limits its time,
/// records an `Observation` per call (`supabase.rest`, `supabase.auth`,
/// `supabase.storage`) and logs without keys, tokens or query values.
///
/// [send] calls through a `RestClient`: the application's
/// `RestClientBuilder` (its transport, `spring.http.clients.*` and its
/// customizers), never following a redirect, with a
/// [SupabaseCredentialsInterceptor] last. It runs under the
/// `RequestDeadline` of the code that calls and [SupabaseProperties.timeout],
/// the earlier of the two. [stream] hands the body over as it arrives, on
/// the transport itself.
///
/// It answers with the response whatever its status; each service turns
/// its own errors into its exceptions. Only no answer at all throws, a
/// [SupabaseUnavailableException].
///
/// ```dart
/// final response = await http.send(
///   SupabaseService.rest,
///   HttpMethod.get,
///   '/todos',
///   query: [const MapEntry('done', 'eq.false')],
/// );
/// ```
///
/// Application code rarely needs it: the repositories, `StorageTemplate`
/// and the declared interfaces are built on it.
final class SupabaseHttp {
  /// A client of the project of [properties], sending as [credentials]
  /// say through a client of [restClientBuilder] (the application's
  /// `RestClientBuilder` bean), or of a builder on [transport] without
  /// one.
  SupabaseHttp({
    required this.properties,
    required this.transport,
    required this.credentials,
    RestClientBuilder? restClientBuilder,
    ObservationRegistry? observations,
  }) : observations = observations ?? ObservationRegistry.noop,
       _builder = restClientBuilder;

  /// The `spring.supabase.*` properties.
  final SupabaseProperties properties;

  /// What sends the requests of [stream] (the application's
  /// `HttpTransport` bean), and those of [send] when no
  /// `RestClientBuilder` was given.
  final HttpTransport transport;

  final RestClientBuilder? _builder;

  // Built at the first call: the project's address may be missing until
  // then.
  late final RestClient _rest =
      (_builder ?? RestClient.builder().transport(transport))
          // A redirect could carry the key and the token to another host.
          .followRedirects(false)
          .sensitiveHeaders(const ['apikey'])
          .requestInterceptor(const _CallTimeout())
          .requestInterceptor(_credentials)
          .build();

  late final SupabaseCredentialsInterceptor _credentials =
      SupabaseCredentialsInterceptor(credentials: credentials, origin: baseUrl);

  /// Where the key and the token of each call come from.
  final SupabaseCredentials credentials;

  /// Where each call is recorded.
  final ObservationRegistry observations;

  static const _log = SpringLog('spring.supabase.http');

  /// The project's address, without a trailing slash. Throws a
  /// [StateError] when `spring.supabase.url` is not set or is not an
  /// `http(s)` address.
  late final Uri baseUrl = _baseUrl();

  Uri _baseUrl() {
    final text = properties.url?.trim() ?? '';
    if (text.isEmpty) {
      throw StateError(
        "spring.supabase.url is not set: the project's address "
        '(https://<ref>.supabase.co)',
      );
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw StateError(
        'spring.supabase.url must be an http(s) address without user, '
        'query or fragment, like https://<ref>.supabase.co',
      );
    }
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path);
  }

  /// The address of [path] of [service] with [query]. [path] starts with
  /// `/` and is already percent-encoded; the query values are encoded
  /// here, in order, and a name may repeat.
  Uri url(
    SupabaseService service,
    String path, {
    Iterable<MapEntry<String, String>> query = const [],
  }) {
    if (path.isNotEmpty && !path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'must start with /');
    }
    final text = [
      for (final entry in query)
        [
          _encode(entry.key),
          _encode(entry.value),
        ].join('='),
    ].join('&');
    return baseUrl.replace(
      path: '${baseUrl.path}${service.path}$path',
      query: text.isEmpty ? null : text,
    );
  }

  // Spaces as %20: a `+` in a query is a space only to form decoders.
  static String _encode(String text) =>
      Uri.encodeQueryComponent(text).replaceAll('+', '%20');

  /// The WebSocket address of Realtime (`wss://<host>/realtime/v1`).
  Uri get realtimeUrl => baseUrl.replace(
    scheme: baseUrl.scheme == 'http' ? 'ws' : 'wss',
    path: '${baseUrl.path}/realtime/v1',
  );

  /// Sends a request and reads the whole answer.
  ///
  /// [json] is encoded as the body (with `Content-Type:
  /// application/json`) unless [body] is given. [bearer] replaces the
  /// token of [credentials] (Auth's own calls, which make the token).
  /// [timeout] replaces `spring.supabase.timeout`.
  Future<HttpResponse> send(
    SupabaseService service,
    HttpMethod method,
    String path, {
    Iterable<MapEntry<String, String>> query = const [],
    Map<String, String> headers = const {},
    List<int>? body,
    Object? json,
    String? bearer,
    Duration? timeout,
  }) => _observed(service, method, path, () {
    final own = timeout ?? properties.timeout;
    final outer = RequestDeadline.current;
    Future<HttpResponse> call() {
      final bytes =
          body ?? (json == null ? null : utf8.encode(jsonEncode(json)));
      final spec = _rest.method(method).uri(url(service, path, query: query));
      if (headers.isNotEmpty || (body == null && json != null)) {
        spec.headers((all) {
          headers.forEach(all.set);
          if (body == null && json != null) {
            all.contentType ??= MediaType.applicationJson;
          }
        });
      }
      if (bearer != null) {
        spec.attribute(SupabaseCredentialsInterceptor.bearerAttribute, bearer);
      }
      if (outer == null) {
        spec.attribute(_CallTimeout.attribute, own);
      }
      if (bytes != null) {
        spec.body(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
      }
      return spec.exchange((_, response) => response.response);
    }

    // Under a later deadline of the caller the call gets one of its own;
    // under an earlier one the client applies that one; under none the
    // request carries its time limit itself (no zone to run in).
    return outer != null && own < outer.remaining
        ? RequestDeadline.run(own, call)
        : call();
  }, (response) => response.statusCode.value);

  /// Sends a request and answers as soon as the status and the headers
  /// are there; the body is read by the caller, without a time limit.
  Future<StreamedHttpResponse> stream(
    SupabaseService service,
    HttpMethod method,
    String path, {
    Iterable<MapEntry<String, String>> query = const [],
    Map<String, String> headers = const {},
    List<int>? body,
    Object? json,
    String? bearer,
    Duration? timeout,
  }) => _observed(service, method, path, () async {
    final all = HttpHeaders();
    headers.forEach(all.set);
    var bytes = body;
    if (bytes == null && json != null) {
      bytes = utf8.encode(jsonEncode(json));
      all.contentType ??= MediaType.applicationJson;
    }
    // Last, so that nothing given by a caller replaces them.
    await _credentials.authorize(all, bearer: bearer);
    final left = RequestDeadline.current?.remaining;
    final own = timeout ?? properties.timeout;
    try {
      return await transport.stream(
        HttpRequest(
          method: method,
          url: url(service, path, query: query),
          headers: all,
          body: bytes,
          timeout: left != null && left < own ? left : own,
          // A redirect could carry the key and the token to another host.
          followRedirects: false,
          sensitiveHeaders: const {'apikey'},
        ),
      );
    } on HttpTransportException catch (error) {
      throw ResourceAccessException(error.message, cause: error);
    }
  }, (response) => response.statusCode.value);

  Future<T> _observed<T>(
    SupabaseService service,
    HttpMethod method,
    String path,
    Future<T> Function() call,
    int Function(T response) status,
  ) {
    if (observations.isNoop) {
      return _logged(service, method, path, call, status, null);
    }
    final observation = observations
        .observation('supabase.${service.name}')
        .lowCardinalityKeyValue('method', method.value);
    return observation.observe(
      () => _logged(service, method, path, call, status, observation),
    );
  }

  Future<T> _logged<T>(
    SupabaseService service,
    HttpMethod method,
    String path,
    Future<T> Function() call,
    int Function(T response) status,
    Observation? observation,
  ) async {
    final watch = _log.isEnabled(SpringLogLevel.debug)
        ? (Stopwatch()..start())
        : null;
    try {
      final response = await call();
      final code = status(response);
      observation?.lowCardinalityKeyValue('status', '$code');
      if (watch != null) {
        _log.debug(
          '${method.value} ${service.path}$path -> $code '
          '(${watch.elapsedMilliseconds} ms)',
        );
      }
      return response;
    } on ResourceAccessException catch (error) {
      final cause = error.cause;
      final message = cause is HttpTransportException
          ? cause.message
          : error.message;
      observation?.lowCardinalityKeyValue('status', 'none');
      if (watch != null) {
        _log.debug('${method.value} ${service.path}$path failed: $message');
      }
      throw SupabaseUnavailableException(
        'No answer from ${baseUrl.host} for '
        '${method.value} ${service.path}$path: $message',
        cause: cause ?? error,
        isTimeout: error.isTimeout,
      );
    }
  }
}

// Gives a request the time limit its call asked for (the attribute
// [attribute]): the whole exchange, as `HttpRequest.timeout` says.
final class _CallTimeout implements ClientHttpRequestInterceptor {
  const _CallTimeout();

  static const attribute = 'supabase.timeout';

  @override
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) => switch (request.attributes[attribute]) {
    final Duration timeout => execution.execute(
      timedRequest(request, timeout),
      body,
    ),
    _ => execution.execute(request, body),
  };
}
