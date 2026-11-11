import 'dart:async';

import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';

/// Marks an interface whose methods call the project's Edge Functions;
/// the generator writes the bean, as for a `@FeignClient`.
///
/// ```dart
/// @EdgeFunctions()
/// abstract interface class Functions {
///   @EdgeFunction('send-invite')
///   Future<InviteResult> sendInvite(@RequestBody() Invite invite);
///
///   @EdgeFunction('stats', method: HttpMethod.get)
///   Future<Stats> stats(@RequestParam('from') DateTime from);
/// }
/// ```
///
/// It is a Feign client of `<spring.supabase.url>/functions/v1` with the
/// key and the token of `SupabaseCredentials`: parameters
/// (`@RequestBody`, `@RequestParam`, `@RequestHeader`, `@PathVariable`),
/// results (JSON, `String`, a file as `Uint8List`, `ResponseEntity<T>`,
/// an `EventStream<T>` of server-sent events, a `Stream<List<int>>` of
/// the body as it arrives) and errors (`FeignException`
/// and its subclasses) are Feign's. Its settings are those of the Feign
/// client named [name] (`spring.feign.client.config.<name>.*`), except
/// that it never follows a redirect, which could carry the token to
/// another host.
@InterfaceProxy(primary: true)
class EdgeFunctions {
  /// Marks the interface; [name] is the Feign client's name.
  const EdgeFunctions({
    this.name = 'supabase-functions',
    this.qualifiers = const [],
    this.primary = true,
  });

  /// The name of the Feign client, for its settings and its logs.
  final String name;

  /// More names the bean can be injected by.
  final List<String> qualifiers;

  /// Whether the bean is the primary one of its type.
  final bool primary;
}

/// Calls the Edge Function [name] (on a method of an [EdgeFunctions]
/// interface).
///
/// `${property}` in the name is resolved from the configuration; a part
/// that changes per call is a `{name}` filled by a `@PathVariable()`
/// parameter, as in any Feign client.
///
/// ```dart
/// @EdgeFunction('reports/{year}', method: HttpMethod.get)
/// Future<Report> report(@PathVariable() int year);
/// ```
@BeanMethodAnnotation()
class EdgeFunction implements Mapping {
  /// The function [name], called with [method] (`POST` unless said).
  const EdgeFunction(
    this.name, {
    this.method = HttpMethod.post,
    this.headers = const [],
    this.produces,
    this.consumes,
  });

  /// The function's name, as deployed.
  final String name;

  @override
  final HttpMethod method;

  @override
  String get path => name.startsWith('/') ? name : '/$name';

  @override
  final List<String> headers;

  @override
  final String? produces;

  @override
  final String? consumes;
}

/// Puts the key and the token of [SupabaseCredentials] on the calls of
/// the [EdgeFunctions] clients, last, so that nothing else decides them.
final class EdgeFunctionsInterceptor implements RequestInterceptor {
  /// An interceptor taking the key and the token from [credentials].
  EdgeFunctionsInterceptor({
    required this.credentials,
    required this.properties,
  });

  /// Where the key and the token come from.
  final SupabaseCredentials credentials;

  /// The `spring.supabase.functions.*` properties.
  final SupabaseFunctionsProperties properties;

  @override
  Future<void> apply(RequestTemplate template) async {
    template
      ..removeHeader('apikey')
      ..removeHeader(HttpHeaders.authorizationHeader)
      ..header('apikey', credentials.apiKey)
      ..header(
        HttpHeaders.authorizationHeader,
        'Bearer ${await credentials.accessToken()}',
      );
    final region = properties.region?.trim();
    if (region != null && region.isNotEmpty) {
      template
        ..removeHeader('x-region')
        ..header('x-region', region);
    }
  }
}

/// Makes the beans of the [EdgeFunctions] interfaces (the bean
/// `edgeFunctionsFactory`).
final class EdgeFunctionsFactory implements InvocationHandlerFactory {
  /// A factory of clients of [http]'s project.
  EdgeFunctionsFactory({
    required this.http,
    required this.environment,
    required this.feign,
    required this.mapper,
    required this.transport,
    required this.interceptor,
    this.interceptors = const [],
    this.errorDecoder = const DefaultErrorDecoder(),
    this.retryer = Retryer.never,
    ObservationRegistry? observations,
  }) : observations = observations ?? ObservationRegistry.noop;

  /// The project.
  final SupabaseHttp http;

  /// Where `${...}` in function names is resolved.
  final Environment environment;

  /// Feign's properties (`spring.feign.client.config.<name>.*`).
  final FeignProperties feign;

  /// What encodes and decodes JSON.
  final ObjectMapper mapper;

  /// What sends the requests.
  final HttpTransport transport;

  /// What sets the key and the token; it runs after [interceptors].
  final EdgeFunctionsInterceptor interceptor;

  /// The application's `RequestInterceptor` beans.
  final List<RequestInterceptor> interceptors;

  /// What turns a failed answer into an exception.
  final ErrorDecoder errorDecoder;

  /// What decides whether a failed call is tried again.
  final Retryer retryer;

  /// Where each call is recorded (`supabase.functions`).
  final ObservationRegistry observations;

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<EdgeFunctions>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) {
    final functions = metadata.annotation<EdgeFunctions>()!;
    final config = FeignClientConfig.of(feign, functions.name);
    final problems = [
      for (final method in metadata.methods)
        if (method.annotations.whereType<Mapping>().isEmpty)
          '${metadata.typeName}.${method.name}: needs @EdgeFunction(name)',
    ];
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid @EdgeFunctions interface ${metadata.typeName}:\n'
        '${problems.map((problem) => '  - $problem').join('\n')}',
      );
    }
    return _ObservedHandler(
      FeignInvocationHandler(
        metadata: metadata,
        client: FeignClient(
          functions.name,
          url: '${http.url(SupabaseService.functions, '')}',
        ),
        config: FeignClientConfig(
          readTimeout: config.readTimeout,
          callTimeout:
              config.callTimeout ??
              http.properties.functions.timeout ??
              http.properties.timeout,
          loggerLevel: config.loggerLevel,
          dismiss404: config.dismiss404,
          defaultRequestHeaders: config.defaultRequestHeaders,
          defaultQueryParameters: config.defaultQueryParameters,
          // A redirect could carry the key and the token to another host.
          followRedirects: false,
          decodeSlash: config.decodeSlash,
          eventStreamReconnect: config.eventStreamReconnect,
          eventStreamReconnectDelay: config.eventStreamReconnectDelay,
          eventStreamMaxAttempts: config.eventStreamMaxAttempts,
          requestInterceptors: config.requestInterceptors,
          sensitiveHeaders: [...config.sensitiveHeaders, 'apikey'],
        ),
        environment: environment,
        mapper: mapper,
        transport: transport,
        interceptors: [
          for (final other in interceptors)
            if (!identical(other, interceptor)) other,
          interceptor,
        ],
        errorDecoder: errorDecoder,
        retryer: retryer,
      ),
      observations,
    );
  }
}

// One observation per call of a function, named after the service.
final class _ObservedHandler implements InvocationHandler {
  _ObservedHandler(this.handler, this.observations);

  final InvocationHandler handler;
  final ObservationRegistry observations;

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) {
    if (observations.isNoop) {
      return handler.invoke(method, arguments);
    }
    final mapping = method.annotations.whereType<Mapping>().firstOrNull;
    return observations
        .observation('supabase.functions')
        .lowCardinalityKeyValue(
          'function',
          mapping is EdgeFunction ? mapping.name : method.name,
        )
        .observe(() => handler.invoke(method, arguments));
  }
}
