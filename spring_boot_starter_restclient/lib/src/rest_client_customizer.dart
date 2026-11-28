import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_restclient/src/config/http_client_properties.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Changes every `RestClientBuilder` the starter makes: the bean each
/// injection gets, and the builder of each HTTP service group. Declare
/// one as a bean; several run in their `@Order`.
///
/// ```dart
/// @Configuration()
/// class HttpSetup {
///   @Bean()
///   RestClientCustomizer tracing(Tracer tracer) =>
///       RestClientCustomizer.of(
///         (builder) => builder.requestInterceptor(TracingInterceptor(tracer)),
///       );
/// }
/// ```
///
/// Spring (Java): Spring Boot's `RestClientCustomizer`:
/// ```java
/// @Bean
/// RestClientCustomizer tracing(Tracer tracer) {
///   return builder ->
///       builder.requestInterceptor(new TracingInterceptor(tracer));
/// }
/// ```
abstract interface class RestClientCustomizer {
  /// The customizer that calls [customize].
  const factory RestClientCustomizer.of(
    void Function(RestClientBuilder builder) customize,
  ) = _FunctionCustomizer;

  /// Changes [builder].
  void customize(RestClientBuilder builder);
}

final class _FunctionCustomizer implements RestClientCustomizer {
  const _FunctionCustomizer(this._customize);

  final void Function(RestClientBuilder builder) _customize;

  @override
  void customize(RestClientBuilder builder) => _customize(builder);
}

/// Sets a `RestClientBuilder` up as the starter's own bean is: the
/// application's `httpTransport` and `ObjectMapper`, the
/// `spring.http.clients.*` timeouts (as the requests' own, so a group's
/// longer connect timeout, which the transport then allows, does not
/// lengthen them) and redirects, then the
/// [RestClientCustomizer] beans in order. Inject it (the
/// `restClientBuilderConfigurer` bean) to set up a builder of your own
/// the same way.
///
/// Spring (Java): Spring Boot's `RestClientBuilderConfigurer`.
final class RestClientBuilderConfigurer {
  /// A configurer of [transport], [mapper], the [properties] and the
  /// [customizers] (applied in this order).
  const RestClientBuilderConfigurer({
    required this.transport,
    required this.mapper,
    required this.properties,
    this.customizers = const [],
  });

  /// The transport every builder sends through.
  final HttpTransport transport;

  /// The mapper of the JSON bodies.
  final ObjectMapper mapper;

  /// `spring.http.clients.*`.
  final HttpClientsProperties properties;

  /// Applied after the settings, in this order.
  final List<RestClientCustomizer> customizers;

  /// [builder], set up; returns it.
  RestClientBuilder configure(RestClientBuilder builder) {
    builder
        .transport(transport)
        .objectMapper(mapper)
        .connectTimeout(positiveOrNull(properties.connectTimeout))
        .readTimeout(positiveOrNull(properties.readTimeout))
        .followRedirects(properties.redirects.followsRedirects);
    for (final customizer in customizers) {
      customizer.customize(builder);
    }
    return builder;
  }

  /// [duration], or `null` when it is zero or negative (none).
  static Duration? positiveOrNull(Duration? duration) =>
      duration == null || duration <= Duration.zero ? null : duration;
}
