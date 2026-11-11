import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
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
/// `supabase.storage`, `supabase.functions`) and logs without keys,
/// tokens or query values.
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
  /// A client of the project of [properties], sending through [transport]
  /// as [credentials] say.
  SupabaseHttp({
    required this.properties,
    required this.transport,
    required this.credentials,
    ObservationRegistry? observations,
  }) : observations = observations ?? ObservationRegistry.noop;

  /// The `spring.supabase.*` properties.
  final SupabaseProperties properties;

  /// What sends the requests (the application's `HttpTransport` bean).
  final HttpTransport transport;

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
  }) => _observed(service, method, path, () async {
    final request = await _request(
      service,
      method,
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      bearer: bearer,
      timeout: timeout ?? properties.timeout,
    );
    return await transport.send(request);
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
    final request = await _request(
      service,
      method,
      path,
      query: query,
      headers: headers,
      body: body,
      json: json,
      bearer: bearer,
      timeout: timeout ?? properties.timeout,
    );
    return await transport.stream(request);
  }, (response) => response.statusCode.value);

  Future<HttpRequest> _request(
    SupabaseService service,
    HttpMethod method,
    String path, {
    required Iterable<MapEntry<String, String>> query,
    required Map<String, String> headers,
    required List<int>? body,
    required Object? json,
    required String? bearer,
    required Duration timeout,
  }) async {
    final all = HttpHeaders();
    headers.forEach(all.set);
    var bytes = body;
    if (bytes == null && json != null) {
      bytes = utf8.encode(jsonEncode(json));
      if (all[HttpHeaders.contentTypeHeader] == null) {
        all.set(HttpHeaders.contentTypeHeader, 'application/json');
      }
    }
    // Last, so that nothing given by a caller replaces them.
    all
      ..set('apikey', credentials.apiKey)
      ..set(
        HttpHeaders.authorizationHeader,
        'Bearer ${bearer ?? await credentials.accessToken()}',
      );
    return HttpRequest(
      method: method,
      url: url(service, path, query: query),
      headers: all,
      body: bytes,
      timeout: timeout,
      // A redirect could carry the key and the token to another host.
      followRedirects: false,
    );
  }

  Future<T> _observed<T>(
    SupabaseService service,
    HttpMethod method,
    String path,
    Future<T> Function() call,
    int Function(T response) status,
  ) {
    final observation = observations
        .observation('supabase.${service.name}')
        .lowCardinalityKeyValue('method', method.name.toUpperCase());
    return observation.observe(() async {
      final watch = Stopwatch()..start();
      try {
        final response = await call();
        final code = status(response);
        observation.lowCardinalityKeyValue('status', '$code');
        _log.debug(
          '${method.name.toUpperCase()} ${service.path}$path -> $code '
          '(${watch.elapsedMilliseconds} ms)',
        );
        return response;
      } on HttpTransportException catch (error) {
        observation.lowCardinalityKeyValue('status', 'none');
        _log.debug(
          '${method.name.toUpperCase()} ${service.path}$path failed: '
          '${error.message}',
        );
        throw SupabaseUnavailableException(
          'No answer from ${baseUrl.host} for '
          '${method.name.toUpperCase()} ${service.path}$path: '
          '${error.message}',
          cause: error,
          isTimeout: error.isTimeout,
        );
      }
    });
  }
}
