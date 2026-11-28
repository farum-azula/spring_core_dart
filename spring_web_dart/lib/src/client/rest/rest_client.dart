import 'dart:async';
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/src/client/address/allowed_addresses.dart';
import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/rest/api_version_inserter.dart';
import 'package:spring_web_dart/src/client/rest/client_http_request_interceptor.dart';
import 'package:spring_web_dart/src/client/rest/default_rest_client.dart';
import 'package:spring_web_dart/src/client/rest/http_message_converter.dart';
import 'package:spring_web_dart/src/client/rest/request_values.dart';
import 'package:spring_web_dart/src/client/rest/rest_client_exception.dart';
import 'package:spring_web_dart/src/client/rest/uri_builder.dart';
import 'package:spring_web_dart/src/client/rest/uri_template.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/http_status.dart';
import 'package:spring_web_dart/src/response_entity.dart';
import 'package:spring_web_dart/src/sse/event_stream.dart';
import 'package:spring_web_dart/src/sse/sse_connection.dart';

/// Calls an HTTP API and gives the answer back as objects: a fluent
/// request (method, URI template, headers, body), then what to get from
/// the response (the body as a type, a `ResponseEntity`, the status only,
/// server-sent events).
///
/// ```dart
/// final rest = RestClient.create('https://api.neon.books');
///
/// final book = await rest.get()
///     .uri('/books/{isbn}', isbn)
///     .retrieve()
///     .body<Book>();
///
/// final created = await rest.post()
///     .uri('/books')
///     .body(book) // JSON through the ObjectMapper
///     .retrieve()
///     .toEntity<Book>();
/// log.info(created.headers.location);
/// ```
///
/// - A 4xx answer throws an [HttpClientErrorException], a 5xx an
///   [HttpServerErrorException], no answer a [ResourceAccessException];
///   `onStatus` (per call) and `defaultStatusHandler` (per client) change
///   that.
/// - Bodies go through the [HttpMessageConverter]s: bytes and text as
///   they are, a stream read while it is sent, a `MultipartBody` as
///   `multipart/form-data` (as a stream when a part is streamed), a `Map`
///   with `application/x-www-form-urlencoded` as a form, anything else as
///   JSON.
/// - A call runs under the `RequestDeadline` of the code that makes it:
///   it is not sent when the deadline has passed and is given up when it
///   passes.
/// - Every call goes through an [HttpTransport]: in an application, the
///   `httpTransport` bean of `spring_boot_starter_restclient`, whose
///   `RestClientBuilder` bean is the way to get a client there.
///
/// The client is immutable and cheap to keep: build it once per API. A
/// URI template is compiled the first time it is used and kept (up to 256
/// per client), so a call expands it without parsing it again.
///
/// Spring (Java): `org.springframework.web.client.RestClient`:
/// ```java
/// Book book = restClient.get()
///     .uri("/books/{isbn}", isbn)
///     .retrieve()
///     .body(Book.class);
/// ```
abstract interface class RestClient {
  /// A client for [baseUrl] (`null`: every call gives a whole URL) with
  /// the defaults: a `platformHttpTransport()` that calls only the host of
  /// [baseUrl], and a plain `ObjectMapper`. Every other address is denied
  /// with a [FilteredHostException] (in a [ResourceAccessException]):
  /// giving the base URL is what allows its host, as the base URL of a
  /// `spring.http.serviceclient` group does. A host name that resolves to
  /// loopback or a private network is denied too, unless it is
  /// `localhost` or the base URL gives the address itself
  /// (`http://10.0.0.5:8080`); see [AllowedAddresses].
  ///
  /// To call other hosts, give the builder a transport with the
  /// [AllowedAddresses] it may call; in an application, inject the
  /// `RestClientBuilder` bean instead: it has the configured transport
  /// (`spring.http.clients.allowed-addresses`), the application's
  /// `ObjectMapper` and the customizers.
  ///
  /// ```dart
  /// final rest = RestClient.builder()
  ///     .transport(platformHttpTransport(
  ///       allowedAddresses: AllowedAddresses(['api.neon.books', '*.cdn']),
  ///     ))
  ///     .build();
  /// ```
  ///
  /// Spring (Java): `RestClient.create(String baseUrl)`, which calls any
  /// address.
  factory RestClient.create([String? baseUrl]) =>
      RestClientBuilder().baseUrl(baseUrl).build();

  /// A new builder, with the defaults of [RestClient.create].
  ///
  /// Spring (Java): `RestClient.builder()`.
  static RestClientBuilder builder() => RestClientBuilder();

  /// A `GET` request.
  RequestHeadersUriSpec get();

  /// A `HEAD` request.
  RequestHeadersUriSpec head();

  /// A `POST` request, with a body.
  RequestBodyUriSpec post();

  /// A `PUT` request, with a body.
  RequestBodyUriSpec put();

  /// A `PATCH` request, with a body.
  RequestBodyUriSpec patch();

  /// A `DELETE` request.
  RequestHeadersUriSpec delete();

  /// An `OPTIONS` request.
  RequestHeadersUriSpec options();

  /// A request of [method], which may have a body (not `GET` or `HEAD`,
  /// whose body a browser's `fetch` refuses: [RequestBodySpec.body] then
  /// throws).
  RequestBodyUriSpec method(HttpMethod method);

  /// A builder with this client's settings, to build a client that
  /// differs in some of them; this client stays as it is.
  RestClientBuilder mutate();
}

/// How a status handler deals with a response whose status it matched:
/// it usually throws; returning lets the call go on as for a success.
///
/// Spring (Java): `RestClient.ResponseSpec.ErrorHandler`.
typedef RestClientErrorHandler = FutureOr<void> Function(
  HttpRequest request,
  HttpResponse response,
);

/// What [RequestHeadersSpec.exchange] does with the response: anything,
/// with no status handling.
///
/// Spring (Java): `RestClient.RequestHeadersSpec.ExchangeFunction`.
typedef ExchangeFunction<T> = FutureOr<T> Function(
  HttpRequest request,
  ConvertibleClientHttpResponse response,
);

/// Sets the URI of a request.
///
/// Spring (Java): `RestClient.UriSpec`.
abstract interface class UriSpec<S> {
  /// The URI of the request, one of:
  ///
  /// - a URI template, `'/books/{isbn}'`, relative to the base URL unless
  ///   it has a scheme, with [variables]: a `List` in order, a `Map` by
  ///   name (and the client's `defaultUriVariables`), or the one value of
  ///   a template with one variable;
  /// - a [Uri], relative to the base URL unless it has a scheme;
  /// - a function of a [UriBuilder] that starts from the base URL:
  ///   `(UriBuilder b) => b.path('/books').queryParam('q', q).build()`.
  ///
  /// Throws an [ArgumentError] for a missing or extra value, or a path
  /// variable `.` or `..` (see `UriTemplate.expand`).
  S uri(Object uri, [Object? variables]);
}

/// The headers of a request, and how to send it.
///
/// Spring (Java): `RestClient.RequestHeadersSpec`.
abstract interface class RequestHeadersSpec {
  /// Adds [value] to the header [name] (with the client's default headers,
  /// a header of the same name set here replaces the default's values).
  /// Throws an [ArgumentError] for a name that is no header name, or a
  /// value with a line break (CR, LF) or a NUL, which would start another
  /// header.
  RequestHeadersSpec header(String name, String value);

  /// Changes the headers of the request in [configure] (checked as
  /// [header] checks them).
  RequestHeadersSpec headers(void Function(HttpHeaders headers) configure);

  /// Sets `Accept`: one media type or a comma-separated list.
  RequestHeadersSpec accept(String mediaTypes);

  /// Adds a cookie (all of them go in one `Cookie` header, after the
  /// client's default cookies). Throws an [ArgumentError] for a name that
  /// is no token, or a value with a control character or a `;`, which
  /// would add another cookie.
  RequestHeadersSpec cookie(String name, String value);

  /// The API version of this call, put into the request by the client's
  /// `ApiVersionInserter` (a header, a query parameter, a path segment);
  /// it replaces the client's `defaultApiVersion`, and `null` sends none.
  /// A call with a version on a client without an inserter fails with a
  /// [StateError], as in Spring.
  ///
  /// ```dart
  /// final books = await rest.get()
  ///     .uri('/books')
  ///     .apiVersion('2.0')
  ///     .retrieve()
  ///     .body<String>();
  /// ```
  ///
  /// Spring (Java): `RequestHeadersSpec.apiVersion(Object)`.
  RequestHeadersSpec apiVersion(Object? version);

  /// Sets the request attribute [name] to [value]: not sent, but handed
  /// to the interceptors in `HttpRequest.attributes` (the OAuth2
  /// registration of `ClientAttributes.clientRegistrationId`, a trace
  /// tag). Set in `defaultRequest`, it applies to every call; a call's own
  /// value of the same name replaces it.
  ///
  /// ```dart
  /// final trace = await rest.get()
  ///     .uri('/orders')
  ///     .attribute('trace.tag', 'checkout')
  ///     .retrieve()
  ///     .body<String>();
  /// ```
  ///
  /// Spring (Java): `RequestHeadersSpec.attribute(String, Object)`.
  RequestHeadersSpec attribute(String name, Object? value);

  /// Changes the request attributes in [configure] (see [attribute]).
  ///
  /// Spring (Java): `RequestHeadersSpec.attributes(Consumer)`.
  RequestHeadersSpec attributes(
    void Function(Map<String, Object?> attributes) configure,
  );

  /// What to read from the response; the request is sent by the method
  /// called on the result (`body`, `toEntity`, ...), once per call.
  ResponseSpec retrieve();

  /// Sends the request and hands the response to [exchange], with no
  /// status handling: a 404 is a response like a 200.
  ///
  /// ```dart
  /// final book = await rest.get().uri('/books/{isbn}', isbn).exchange(
  ///   (request, response) => response.statusCode == HttpStatus.notFound
  ///       ? null
  ///       : response.bodyTo<Book>(),
  /// );
  /// ```
  Future<T> exchange<T>(ExchangeFunction<T> exchange);
}

/// The headers and the body of a request.
///
/// Spring (Java): `RestClient.RequestBodySpec`.
abstract interface class RequestBodySpec implements RequestHeadersSpec {
  @override
  RequestBodySpec header(String name, String value);

  @override
  RequestBodySpec headers(void Function(HttpHeaders headers) configure);

  @override
  RequestBodySpec accept(String mediaTypes);

  @override
  RequestBodySpec cookie(String name, String value);

  @override
  RequestBodySpec apiVersion(Object? version);

  @override
  RequestBodySpec attribute(String name, Object? value);

  @override
  RequestBodySpec attributes(
    void Function(Map<String, Object?> attributes) configure,
  );

  /// Sets `Content-Type`; the body is then written in that type (a `Map`
  /// as a form with `application/x-www-form-urlencoded`).
  RequestBodySpec contentType(String mediaType);

  /// The body: written by the first converter that takes it
  /// (`Uint8List` and `String` as they are, a `Stream<List<int>>` or a
  /// `StreamingBody` read while it is sent, a `MultipartBody`, as a stream
  /// when a part is streamed, a form, or JSON through the `ObjectMapper`,
  /// with [type] for a generic value). Throws an [ArgumentError] for a
  /// `GET` or `HEAD` request.
  ///
  /// A streamed body is never read whole into memory, unless an
  /// interceptor of the client needs the bytes (see
  /// `StreamingClientHttpRequestInterceptor`). A stream is sent once: a
  /// retry of the call fails with a `NonRepeatableBodyException`, where a
  /// `StreamingBody.repeatable` (a file) is opened again.
  RequestBodySpec body(Object? body, [TypeInfo<Object?>? type]);
}

/// A `GET`, `HEAD`, `DELETE` or `OPTIONS` request before its URI is set:
/// it has no body.
abstract interface class RequestHeadersUriSpec
    implements UriSpec<RequestHeadersSpec>, RequestHeadersSpec {}

/// A request with a body before its URI is set.
abstract interface class RequestBodyUriSpec
    implements UriSpec<RequestBodySpec>, RequestBodySpec {}

/// What to read from a response, and how its status is handled.
///
/// Status handlers are asked in order: those of [onStatus], in the order
/// they were added, then the client's `defaultStatusHandler` instances, then
/// the default one, which throws a [RestClientResponseException] for a 4xx or
/// a 5xx. The first whose predicate matches handles the response; when it
/// returns instead of throwing, the response is read as a success.
///
/// Spring (Java): `RestClient.ResponseSpec`.
abstract interface class ResponseSpec {
  /// Handles the responses whose status matches [predicate] with
  /// [handler], before the client's handlers.
  ///
  /// ```dart
  /// final book = await rest.get().uri('/books/{isbn}', isbn).retrieve()
  ///     .onStatus((status) => status == HttpStatus.notFound, (_, _) {
  ///       throw BookNotFound(isbn);
  ///     })
  ///     .body<Book>();
  /// ```
  ResponseSpec onStatus(
    bool Function(HttpStatusCode status) predicate,
    RestClientErrorHandler handler,
  );

  /// Sends the request and reads the body as [T] ([type] for a generic
  /// type, `const ListType(ClassType<Book>())` for `List<Book>`). An
  /// empty body is `null` for a nullable [T] and a
  /// [RestClientException] otherwise.
  Future<T> body<T>([TypeInfo<T>? type]);

  /// Sends the request and returns the status, the headers and the body
  /// read as [T] (`null` when empty).
  Future<ResponseEntity<T>> toEntity<T>([TypeInfo<T>? type]);

  /// Sends the request and returns the status and the headers; the body
  /// is dropped.
  Future<ResponseEntity<void>> toBodilessEntity();

  /// The server-sent events (`text/event-stream`) of the response, each
  /// event's data read as [T] (a `String` as it is, anything else as
  /// JSON). It is cold: each listener sends its own request, and a lost
  /// connection is opened again by [reconnect] with `Last-Event-ID`. An
  /// error status fails the stream with the status handlers' exception.
  /// Each connection waits for the headers within the deadline of the
  /// code that listens; the stream itself is not limited.
  ///
  /// Spring (Java): no `RestClient` counterpart; `WebClient` reads
  /// `bodyToFlux(ServerSentEvent.class)`.
  EventStream<T> eventStream<T>({
    TypeInfo<T>? type,
    SseReconnect reconnect = const SseReconnect(),
  });

  /// The bytes of the body as they arrive, for a large download: one
  /// request per listener, never reconnected; an error status fails the
  /// stream. Cancelling the subscription closes the connection.
  Stream<List<int>> bodyStream();
}

/// The response [RequestHeadersSpec.exchange] gets: the transport's
/// response, with the client's converters to read its body.
///
/// Spring (Java):
/// `RestClient.RequestHeadersSpec.ConvertibleClientHttpResponse`.
final class ConvertibleClientHttpResponse {
  /// [response], read by `reader` (the client's converters).
  ConvertibleClientHttpResponse(this.response, this._reader);

  /// The response as the transport gave it.
  final HttpResponse response;

  final Object? Function(TypeInfo<Object?> type, HttpResponse response) _reader;

  /// The status.
  HttpStatusCode get statusCode => response.statusCode;

  /// The headers.
  HttpHeaders get headers => response.headers;

  /// The body bytes.
  Uint8List get bodyBytes => response.bodyBytes;

  /// The body as text.
  String get bodyText => response.bodyText;

  /// The body read as [T] with the converters, as `ResponseSpec.body`
  /// reads it (but whatever the status).
  T bodyTo<T>([TypeInfo<T>? type]) =>
      _reader(type ?? ClassType<T>(nullable: null is T), response) as T;

  /// The exception the default status handler would throw for this
  /// response.
  RestClientResponseException createException() =>
      RestClientResponseException.of(
        response,
        bodyReader: (type) => _reader(type, response),
      );
}

/// Builds a [RestClient]: the base URL, default headers, cookies and URI
/// variables, status handlers, interceptors, converters, the
/// `ObjectMapper`, the transport and its timeouts.
///
/// A builder is mutable, and a change shows in every client built after
/// it; [clone] gives an independent copy. In an application the
/// `RestClientBuilder` bean of `spring_boot_starter_restclient` is a new
/// builder for each injection, already set up from `spring.http.clients.*`
/// and the `RestClientCustomizer` beans.
///
/// ```dart
/// @Service()
/// class CatalogClient {
///   CatalogClient(RestClientBuilder builder)
///     : _rest = builder
///           .baseUrl('https://api.neon.books')
///           .defaultHeader('X-Api-Version', '2')
///           .build();
///   final RestClient _rest;
/// }
/// ```
///
/// Spring (Java): `RestClient.Builder`.
final class RestClientBuilder {
  /// A builder with the defaults: no base URL, a `platformHttpTransport()`
  /// that calls only the base URL's host (see [RestClient.create]), a
  /// plain `ObjectMapper`, redirects followed, no timeouts beyond the
  /// transport's.
  RestClientBuilder();

  RestClientBuilder._copy(RestClientBuilder other)
    : _baseUrl = other._baseUrl,
      _defaultUriVariables = {...other._defaultUriVariables},
      _defaultHeaders = other._defaultHeaders.copy(),
      _defaultCookies = {
        for (final MapEntry(:key, :value) in other._defaultCookies.entries)
          key: [...value],
      },
      _defaultRequests = [...other._defaultRequests],
      _statusHandlers = [...other._statusHandlers],
      _interceptors = [...other._interceptors],
      _converterConfigurers = [...other._converterConfigurers],
      _mapper = other._mapper,
      _transport = other._transport,
      _readTimeout = other._readTimeout,
      _connectTimeout = other._connectTimeout,
      _followRedirects = other._followRedirects,
      _sensitiveHeaders = {...other._sensitiveHeaders},
      _defaultApiVersion = other._defaultApiVersion,
      _apiVersionInserter = other._apiVersionInserter;

  String? _baseUrl;
  Map<String, Object?> _defaultUriVariables = {};
  HttpHeaders _defaultHeaders = HttpHeaders();
  Map<String, List<String>> _defaultCookies = {};
  List<void Function(RequestHeadersSpec spec)> _defaultRequests = [];
  List<StatusHandler> _statusHandlers = [];
  List<ClientHttpRequestInterceptor> _interceptors = [];
  List<void Function(List<HttpMessageConverter> converters)>
  _converterConfigurers = [];
  ObjectMapper? _mapper;
  HttpTransport? _transport;
  Duration? _readTimeout;
  Duration? _connectTimeout;
  bool _followRedirects = true;
  Set<String> _sensitiveHeaders = {};
  Object? _defaultApiVersion;
  ApiVersionInserter? _apiVersionInserter;

  /// The base of every relative URI (a URL or a URI template, `${...}`
  /// already resolved); `null` for none.
  String? get configuredBaseUrl => _baseUrl;

  /// The API version of the calls that give none ([defaultApiVersion]);
  /// `null` for none.
  Object? get configuredDefaultApiVersion => _defaultApiVersion;

  /// What puts a call's API version into its request
  /// ([apiVersionInserter]); `null` for none.
  ApiVersionInserter? get configuredApiVersionInserter => _apiVersionInserter;

  /// Sets the base URL ([baseUrl] may hold `{variables}`, filled from
  /// [defaultUriVariables]).
  RestClientBuilder baseUrl(String? baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  /// Sets the values of URI variables that calls do not give (by name).
  RestClientBuilder defaultUriVariables(Map<String, Object?> variables) {
    _defaultUriVariables = {...variables};
    return this;
  }

  /// Sets the header [name] to [value] for every request (a request's own
  /// header of that name replaces it).
  RestClientBuilder defaultHeader(String name, String value) {
    _defaultHeaders.set(name, value);
    return this;
  }

  /// Changes the default headers in [configure].
  RestClientBuilder defaultHeaders(
    void Function(HttpHeaders headers) configure,
  ) {
    configure(_defaultHeaders);
    return this;
  }

  /// Adds the cookie [name] with [value] to every request.
  RestClientBuilder defaultCookie(String name, String value) {
    (_defaultCookies[name] ??= []).add(value);
    return this;
  }

  /// The API version every call asks for unless it gives its own
  /// (`apiVersion(...)` on the request, the `version:` of an exchange
  /// annotation); `null`: none. It goes into the request through the
  /// [apiVersionInserter], which a client with a version needs.
  ///
  /// ```dart
  /// builder
  ///     .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
  ///     .defaultApiVersion('1.2');
  /// ```
  ///
  /// Spring (Java): `RestClient.Builder.defaultApiVersion(Object)`.
  RestClientBuilder defaultApiVersion(Object? version) {
    _defaultApiVersion = version;
    return this;
  }

  /// Puts the API version of each call into its request: a header, a query
  /// parameter, a path segment, a parameter of the `Content-Type`
  /// ([ApiVersionInserter]); `null`: none, and a call with a version then
  /// fails with a [StateError].
  ///
  /// Spring (Java): `RestClient.Builder.apiVersionInserter(...)`.
  RestClientBuilder apiVersionInserter(ApiVersionInserter? inserter) {
    _apiVersionInserter = inserter;
    return this;
  }

  /// Runs [initializer] on every request spec as it is created, before the
  /// caller's own calls: default attributes, a header computed per call.
  ///
  /// ```dart
  /// builder.defaultRequest((spec) => spec.attribute('tenant', 'neon'));
  /// ```
  RestClientBuilder defaultRequest(
    void Function(RequestHeadersSpec spec) initializer,
  ) {
    _defaultRequests.add(initializer);
    return this;
  }

  /// Handles the responses whose status matches [predicate] with
  /// [handler] in every call, after the call's own `onStatus` handlers
  /// and before the default one; in the order added.
  RestClientBuilder defaultStatusHandler(
    bool Function(HttpStatusCode status) predicate,
    RestClientErrorHandler handler,
  ) {
    _statusHandlers.add(StatusHandler(predicate, handler));
    return this;
  }

  /// Adds [interceptor] after those added before (the first is the
  /// outermost).
  RestClientBuilder requestInterceptor(
    ClientHttpRequestInterceptor interceptor,
  ) {
    _interceptors.add(interceptor);
    return this;
  }

  /// Changes the list of interceptors in [configure].
  RestClientBuilder requestInterceptors(
    void Function(List<ClientHttpRequestInterceptor> interceptors) configure,
  ) {
    configure(_interceptors);
    return this;
  }

  /// Changes the converters in [configure], when the client is built: the
  /// list starts with the defaults (see [HttpMessageConverter]), the JSON
  /// one on the [objectMapper].
  RestClientBuilder messageConverters(
    void Function(List<HttpMessageConverter> converters) configure,
  ) {
    _converterConfigurers.add(configure);
    return this;
  }

  /// Writes and reads JSON with [mapper] (the application's, with its
  /// naming strategy and modules).
  RestClientBuilder objectMapper(ObjectMapper mapper) {
    _mapper = mapper;
    return this;
  }

  /// Sends the requests through [transport] (a mock in a test, the
  /// application's `httpTransport` bean, a `platformHttpTransport` with
  /// the [AllowedAddresses] to call). Without one, the client calls only
  /// the host of its base URL.
  ///
  /// Spring (Java): `requestFactory(ClientHttpRequestFactory)`.
  RestClientBuilder transport(HttpTransport transport) {
    _transport = transport;
    return this;
  }

  /// The longest wait for data, for the response and then between two
  /// chunks of the body (the request's `readTimeout`); `null`: none.
  RestClientBuilder readTimeout(Duration? timeout) {
    _readTimeout = timeout;
    return this;
  }

  /// The longest wait for a connection to open (the request's
  /// `connectTimeout`; on `dart:io` within the transport's own); `null`:
  /// the transport's.
  RestClientBuilder connectTimeout(Duration? timeout) {
    _connectTimeout = timeout;
    return this;
  }

  /// Whether the transport follows redirects; `true` by default.
  RestClientBuilder followRedirects(bool follow) {
    _followRedirects = follow;
    return this;
  }

  /// More headers that carry a credential (any case): masked in the
  /// client's log and dropped on a redirect to another origin, with those
  /// of `HttpSecrets.isSensitiveHeader`.
  RestClientBuilder sensitiveHeaders(Iterable<String> names) {
    _sensitiveHeaders = {
      ..._sensitiveHeaders,
      for (final name in names) name.trim().toLowerCase(),
    };
    return this;
  }

  /// Runs [configure] on this builder: settings kept in one function.
  RestClientBuilder apply(void Function(RestClientBuilder builder) configure) {
    configure(this);
    return this;
  }

  /// An independent copy of this builder.
  // Spring's name.
  // ignore: use_to_and_as_if_applicable
  RestClientBuilder clone() => RestClientBuilder._copy(this);

  /// The client with the settings as they are now; later changes to the
  /// builder do not reach it. Throws an [ArgumentError] for a default
  /// header or cookie that `RequestHeadersSpec.header` or `cookie` would
  /// refuse.
  RestClient build() {
    final mapper = _mapper ?? ObjectMapper();
    final converters = defaultConverters(mapper);
    for (final configure in _converterConfigurers) {
      configure(converters);
    }
    _defaultHeaders.forEach((name, values) {
      for (final value in values) {
        checkHeader(name, value);
      }
    });
    _defaultCookies.forEach((name, values) {
      for (final value in values) {
        checkCookie(name, value);
      }
    });
    return DefaultRestClient(
      clone(),
      baseUrl: _baseUrl,
      defaultUriVariables: Map.unmodifiable(_defaultUriVariables),
      defaultHeaders: HttpHeaders.readOnly(_defaultHeaders.copy()),
      defaultCookies: {
        for (final MapEntry(:key, :value) in _defaultCookies.entries)
          key: List.unmodifiable(value),
      },
      defaultRequests: List.unmodifiable(_defaultRequests),
      statusHandlers: List.unmodifiable(_statusHandlers),
      interceptors: List.unmodifiable(_interceptors),
      converters: List.unmodifiable(converters),
      transport: _transport ?? _defaultTransport(),
      readTimeout: _readTimeout,
      connectTimeout: _connectTimeout,
      followRedirects: _followRedirects,
      sensitiveHeaders: Set.unmodifiable(_sensitiveHeaders),
      defaultApiVersion: _defaultApiVersion,
      apiVersionInserter: _apiVersionInserter,
    );
  }

  /// The converters a client starts with, in order, the JSON one on
  /// [mapper].
  static List<HttpMessageConverter> defaultConverters(ObjectMapper mapper) => [
    const ByteArrayHttpMessageConverter(),
    const StringHttpMessageConverter(),
    const StreamingBodyHttpMessageConverter(),
    const MultipartHttpMessageConverter(),
    const FormHttpMessageConverter(),
    JsonHttpMessageConverter(mapper),
  ];

  /// What a denied call of a client built without a transport says to do.
  static const defaultTransportRemedy =
      'the RestClient was built without a transport, so it calls only the '
      'host of its base URL: give RestClient.builder() a transport with '
      'the AllowedAddresses it may call (transport: '
      'platformHttpTransport(allowedAddresses: AllowedAddresses([...]))), '
      'or inject the RestClientBuilder of spring_boot_starter_restclient '
      'and add it to spring.http.clients.allowed-addresses';

  // The transport of a client built without one: allows the base URL's
  // host and nothing else. One per host, shared by the clients of that
  // host and never closed (as the JDK HttpClient a RestClient.create()
  // makes); a few hosts at most in practice, the cache starts again past
  // [_defaultTransportLimit].
  HttpTransport _defaultTransport() {
    final host = _baseHost() ?? '';
    final shared = _defaultTransports[host];
    if (shared != null) {
      return shared;
    }
    if (_defaultTransports.length >= _defaultTransportLimit) {
      _defaultTransports.clear();
    }
    return _defaultTransports[host] = platformHttpTransport(
      allowedAddresses: AllowedAddresses([
        if (host.isNotEmpty) host,
      ], remedy: defaultTransportRemedy),
    );
  }

  // The host of the base URL, its default URI variables filled; null when
  // there is none or it cannot be told.
  String? _baseHost() {
    final base = _baseUrl?.trim();
    if (base == null || base.isEmpty) {
      return null;
    }
    try {
      final host = UriTemplate(base).expand(null, _defaultUriVariables).host;
      return host.isEmpty ? null : host;
    } on Object {
      return null;
    }
  }

  static const _defaultTransportLimit = 32;
  static final Map<String, HttpTransport> _defaultTransports = {};
}

/// One status handler: [predicate] says which statuses it takes, [handler]
/// what it does with them.
final class StatusHandler {
  /// The handler of the statuses of [predicate].
  const StatusHandler(this.predicate, this.handler);

  /// Whether the handler takes a status.
  final bool Function(HttpStatusCode status) predicate;

  /// What it does with a response it took.
  final RestClientErrorHandler handler;
}
