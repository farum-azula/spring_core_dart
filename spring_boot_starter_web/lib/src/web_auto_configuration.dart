import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/cors.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_boot_starter_web/src/forwarded_headers.dart';
import 'package:spring_boot_starter_web/src/handler_method.dart';
import 'package:spring_boot_starter_web/src/http_session.dart';
import 'package:spring_boot_starter_web/src/multipart_resolver.dart';
import 'package:spring_boot_starter_web/src/platform_web_server_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_web/src/platform_web_server_io.dart'
    as platform;
import 'package:spring_boot_starter_web/src/request_mapping.dart';
import 'package:spring_boot_starter_web/src/response_writer.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_boot_starter_web/src/web_server_lifecycle.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _source = 'package:spring_boot_starter_web#WebMvcAutoConfiguration';

// A Flutter app (dart:ui exists): the server listens on 127.0.0.1 unless
// server.address says otherwise, so an app opens no port to the network
// by accident.
const _isFlutter = bool.fromEnvironment('dart.library.ui');

/// Reads the server's settings from `server.*` in [environment], as the
/// starter applies them: in a Flutter app the address defaults to
/// `127.0.0.1`, and a test with the `random-port` web environment gets
/// port 0 (a free port).
ServerProperties serverProperties(Environment environment) =>
    ServerProperties.of(
      environment,
      // Not redundant: `_isFlutter` is only false where analyzed (the VM).
      // ignore: avoid_redundant_argument_values
      defaultAddress: _isFlutter ? '127.0.0.1' : null,
    ).copyWith(
      port:
          environment.getProperty(webEnvironmentProperty)?.trim() ==
              'random-port'
          ? 0
          : null,
    );

// The CorsConfigurationSource bean named corsConfigurationSource, the one
// Spring Security's CorsConfigurer takes (CORS_CONFIGURATION_SOURCE_BEAN_NAME),
// so that CORS works the same with and without the security starter;
// beans of the type with other names are left alone (Spring MVC itself
// reads none), and several never fail the start. A bean of that name of
// another type is not CORS rules: ignored here (the security starter
// fails the start on it, as Spring Security).
CorsConfigurationSource? _corsConfigurationSource(DependencyResolver r) {
  const name = 'corsConfigurationSource';
  if (!r.containsBean(name)) {
    return null;
  }
  return switch (r.optionalResource<Object>(name)) {
    final CorsConfigurationSource source => source,
    _ => null,
  };
}

/// The bean definitions the web starter adds to every application that
/// lists it: the server, the request pipeline and their helpers.
///
/// The generator registers them through the starter's auto-configuration
/// module. A bean marked "unless the application declares one" backs off
/// when the application has its own bean of that type. The beans are:
///
/// - `webServerFactory` — `IoWebServerFactory` (`dart:io`) with
///   `server.*` and the `WebServerFactoryCustomizer` beans, unless the
///   application declares a [WebServerFactory];
/// - `responseWriter` — writes results as JSON (the `ObjectMapper`), text,
///   bytes, `ProblemDetail`, server-sent events;
/// - `multipartResolver` — reads `multipart/form-data` uploads
///   (`spring.servlet.multipart.*`), unless the application declares one;
/// - `requestMappingHandlerMapping` — the controllers, with the
///   `WebMvcConfigurer` beans' interceptors, CORS mappings and argument
///   resolvers, and the `CorsConfigurationSource` bean named
///   `corsConfigurationSource`;
/// - `httpSessionRepository`, `httpSessionManager`, `httpSessionFilter` —
///   `request.getSession()` (`server.servlet.session.*`), sessions in
///   memory unless the application declares an [HttpSessionRepository];
/// - `forwardedHeaderFilter`, with `server.forward-headers-strategy` set
///   to `native` or `framework` — [ForwardedHeaderFilter], first of all
///   filters: behind a reverse proxy, the scheme, host, port and client
///   address the proxy forwards, from the proxies of
///   `server.forward-headers.trusted-proxies` only (loopback and private
///   networks by default).
/// - `dispatcherHandler` — the [HttpHandler]: the [WebFilter] beans, then
///   the [HandlerMapping] beans;
/// - `webServerStartStopLifecycle` — starts and stops the server with the
///   context;
/// - `portInUseFailureAnalyzer` — the startup report for a port in use.
///
/// Spring Boot spreads the same beans over
/// `ServletWebServerFactoryAutoConfiguration` and
/// `WebMvcAutoConfiguration`.
final webMvcAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<WebServerFactory>(
    name: 'webServerFactory',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'webServerFactory',
    types: const [WebServerFactory, ConfigurableWebServerFactory],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.webServerFactory', [
        ConditionalOnMissingBean(WebServerFactory),
      ]),
    ],
    create: (r) {
      final factory = platform.createPlatformWebServerFactory()
        ..settings = serverProperties(r.dependency<Environment>());
      for (final customizer
          in r.optionalDependencyList<WebServerFactoryCustomizer>() ??
              const <WebServerFactoryCustomizer>[]) {
        customizer.customize(factory);
      }
      return factory;
    },
  ),
  BeanDefinition<ResponseWriter>(
    name: 'responseWriter',
    source: _source,
    create: (r) {
      final environment = r.dependency<Environment>();
      return ResponseWriter(
        mapper:
            r.optionalDependency<ObjectMapper>() ??
            ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
        messageSource: r.optionalDependency<MessageSource>(),
        asyncTimeout: environment.getPropertyAs<Duration>(
          'spring.mvc.async.request-timeout',
        ),
        sseHeartbeat: environment.getPropertyAs<Duration>(
          'spring.mvc.sse.heartbeat-interval',
        ),
      );
    },
  ),
  BeanDefinition<MultipartResolver>(
    name: 'multipartResolver',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'multipartResolver',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.multipartResolver', [
        ConditionalOnMissingBean(MultipartResolver),
      ]),
    ],
    create: (r) =>
        MultipartResolver(MultipartProperties.of(r.dependency<Environment>())),
  ),
  BeanDefinition<RequestMappingHandlerMapping>(
    name: 'requestMappingHandlerMapping',
    types: const [
      RequestMappingHandlerMapping,
      HandlerMapping,
      Ordered,
      SmartInitializingSingleton,
    ],
    source: _source,
    create: (r) {
      final configurers =
          r.optionalDependencyList<WebMvcConfigurer>() ??
          const <WebMvcConfigurer>[];
      final interceptors = InterceptorRegistry();
      final cors = CorsRegistry();
      final resolvers = <HandlerMethodArgumentResolver>[];
      for (final configurer in configurers) {
        configurer
          ..addInterceptors(interceptors)
          ..addCorsMappings(cors)
          ..addArgumentResolvers(resolvers);
      }
      return RequestMappingHandlerMapping(
        beanFactory: r.dependency<ListableBeanFactory>(),
        writer: r.dependency<ResponseWriter>(),
        environment: r.dependency<Environment>(),
        argumentResolvers: resolvers,
        interceptors: interceptors.registrations,
        corsSource: cors.isEmpty ? null : cors.toSource(),
        corsConfigurationSource: _corsConfigurationSource(r),
        validator: r.provider<Validator>().getIfUnique(),
        multipartResolver: r.dependency<MultipartResolver>(),
      );
    },
  ),
  BeanDefinition<HttpSessionRepository>(
    name: 'httpSessionRepository',
    factoryMethodName: 'httpSessionRepository',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.httpSessionRepository', [
        ConditionalOnMissingBean(HttpSessionRepository),
      ]),
    ],
    create: (r) {
      final properties = HttpSessionProperties.of(r.dependency<Environment>());
      return InMemoryHttpSessionRepository(
        timeout: properties.timeout,
        maxSessions: properties.maxSessions,
      );
    },
  ),
  BeanDefinition<HttpSessionManager>(
    name: 'httpSessionManager',
    source: _source,
    create: (r) {
      final environment = r.dependency<Environment>();
      return HttpSessionManager(
        r.dependency<HttpSessionRepository>(),
        HttpSessionProperties.of(
          environment,
          contextPath: serverProperties(environment).contextPath,
        ),
      );
    },
  ),
  BeanDefinition<ForwardedHeaderFilter>(
    name: 'forwardedHeaderFilter',
    types: const [ForwardedHeaderFilter, WebFilter, Ordered],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.forwardedHeaderFilter', [_OnForwardHeaders()]),
    ],
    create: (r) {
      final text = r
          .dependency<Environment>()
          .getProperty('server.forward-headers.trusted-proxies')
          ?.trim();
      return ForwardedHeaderFilter(
        trustedProxies: text == null || text.isEmpty
            ? null
            : [
                for (final part in text.split(','))
                  if (part.trim().isNotEmpty) part.trim(),
              ],
      );
    },
  ),
  BeanDefinition<HttpSessionFilter>(
    name: 'httpSessionFilter',
    types: const [HttpSessionFilter, WebFilter, Ordered],
    source: _source,
    create: (r) => HttpSessionFilter(r.dependency<HttpSessionManager>()),
  ),
  BeanDefinition<DispatcherHandler>(
    name: 'dispatcherHandler',
    types: const [DispatcherHandler, HttpHandler],
    source: _source,
    create: (r) {
      final requestMapping = r.dependency<RequestMappingHandlerMapping>();
      final mappings =
          r.optionalDependencyList<HandlerMapping>() ??
          <HandlerMapping>[requestMapping];
      return DispatcherHandler(
        filters: r.optionalDependencyList<WebFilter>() ?? const <WebFilter>[],
        handlerMappings: mappings,
        requestMapping: requestMapping,
        writer: r.dependency<ResponseWriter>(),
        contextPath: serverProperties(r.dependency<Environment>()).contextPath,
      );
    },
  ),
  BeanDefinition<WebServerStartStopLifecycle>(
    name: 'webServerStartStopLifecycle',
    types: const [
      WebServerStartStopLifecycle,
      SmartLifecycle,
      Lifecycle,
      ApplicationContextAware,
      AsyncStartup,
    ],
    source: _source,
    create: (r) {
      final environment = r.dependency<Environment>();
      return WebServerStartStopLifecycle(
        r.dependency<WebServerFactory>(),
        r.dependency<HttpHandler>(name: 'dispatcherHandler'),
        environment,
        shutdownTimeout:
            environment.getPropertyAs<Duration>(
              'spring.lifecycle.timeout-per-shutdown-phase',
            ) ??
            const Duration(seconds: 30),
      );
    },
  ),
  BeanDefinition<PortInUseFailureAnalyzer>(
    name: 'portInUseFailureAnalyzer',
    types: const [PortInUseFailureAnalyzer, FailureAnalyzer],
    source: _source,
    create: (_) => const PortInUseFailureAnalyzer(),
  ),
];

// server.forward-headers-strategy=native or framework; another value
// than those and `none` stops the start.
final class _OnForwardHeaders implements Condition {
  const _OnForwardHeaders();

  @override
  bool matches(ConditionContext context) {
    final value = context.environment
        .getProperty('server.forward-headers-strategy')
        ?.trim()
        .toLowerCase();
    return switch (value) {
      null || '' || 'none' => false,
      'native' || 'framework' => true,
      _ => throw ArgumentError(
        'server.forward-headers-strategy must be none, native or framework: '
        '$value',
      ),
    };
  }
}
